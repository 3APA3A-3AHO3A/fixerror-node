# ##########################################################################
#  ЗАЩИТА ОТ ПРОБЕРОВ РКН
#  Входящие соединения из госсетей и сетей сканеров отбрасываются: набор
#  ipset из списков shadow-netlab/traffic-guard-lists, правило в before.rules
#  ufw, обновление раз в сутки (systemd-таймер rkn-block.timer)
# ##########################################################################

# Зачем. Проберы ТСПУ и сканеры подключаются к ноде как клиенты и по ответу
# узнают VPN. Если не отвечать им вовсе, узнавать нечего.
#
# Что режется. Только НОВЫЕ входящие соединения из этих сетей. Ответы на
# соединения, которые открыла сама нода, проходят: клиенты на нодах, где весь
# трафик идёт через VPN, по-прежнему открывают госсайты.
#
# Порядок при загрузке. Правило ufw ссылается на набор ipset, и если набора
# нет, ufw не стартует целиком — нода остаётся без фаервола. Поэтому наборы
# поднимаются из сохранённой копии до ufw (rkn-block-restore.service и
# дополнение к ufw.service), а при сбое скачивания остаются прежними.

RKN_MARK="# защита от проберов РКН (fixerror-node)"

rkn_block_enabled() {
    [[ "${RKN_BLOCK:-y}" =~ ^[Yy]$ ]] && return 0
    return 1
}

# Скрипт обновления. Настройки вписываются при установке, тело — общее.
rkn_write_updater() {
    {
        cat <<HEAD
#!/bin/bash
# Наборы ipset rkn-block / rkn-block6 для защиты от проберов РКН (fixerror-node).
# Запуск: rkn-block            скачать списки и обновить наборы
#         rkn-block --restore  при загрузке, до ufw: поднять наборы из сохранённой копии
#         rkn-block --print    скачать и показать, что попадёт в наборы; ничего не менять
set -u
URL=\${RKN_LISTS_URL:-$RKN_LISTS_URL}
LISTS=\${RKN_LISTS:-"$RKN_LISTS"}
SAVE=\${RKN_SAVE:-$RKN_SAVE}
ALLOW=\${RKN_ALLOW_FILE:-$RKN_ALLOW_FILE}
PANEL_IP=$PANEL_IP
NOTIFY=$NOTIFY_BIN
HEAD
        cat <<'BODY'
SET4=rkn-block; SET6=rkn-block6
MIN4=500          # меньше сетей — значит, список сломан; наборы не трогаем
STATE=/var/lib/rkn-block
MODE=${1:-}

# Под systemd вывод и так уходит в журнал — echo только когда вывод идёт не
# туда, иначе каждая строка в журнале двоится
IN_JOURNAL=0
[ -n "${JOURNAL_STREAM:-}" ] && [ "$JOURNAL_STREAM" = "$(stat -Lc '%d:%i' /proc/$$/fd/1 2>/dev/null)" ] && IN_JOURNAL=1
log(){ [ $IN_JOURNAL = 1 ] || echo "$*"; logger -t rkn-block "$*" 2>/dev/null || true; }

# Ошибка: в журнал всегда, в Telegram — не чаще раза в сутки
fail(){
    log "ОШИБКА: $*, наборы не тронуты"
    mkdir -p "$STATE" 2>/dev/null
    if [ -z "$(find "$STATE/notified" -mmin -1440 2>/dev/null)" ] && [ -x "$NOTIFY" ]; then
        "$NOTIFY" "⚠️ <b>Не обновились сети РКН для блокировки</b>: $*" >/dev/null 2>&1 && touch "$STATE/notified"
    fi
    exit 1
}

create_sets(){
    ipset create -exist $SET4 hash:net family inet maxelem 131072
    ipset create -exist $SET6 hash:net family inet6 maxelem 131072
}

# Строки «сеть» или «сеть nomatch» в команды ipset restore для набора $1 / $2
restore_cmds(){
    awk -v s4="$1" -v s6="$2" '{ printf "add %s %s%s\n", (index($1, ":") ? s6 : s4), $1, ($2 == "nomatch" ? " nomatch" : "") }'
}

if [ "$MODE" = --restore ]; then
    # Загрузка не должна сорваться ни при каком исходе: пустой набор лучше,
    # чем ufw, который не поднялся
    create_sets || exit 0
    [ -s "$SAVE" ] && restore_cmds $SET4 $SET6 < "$SAVE" | ipset restore -exist 2>/dev/null
    log "наборы подняты из сохранённой копии: $(cat "$SAVE" 2>/dev/null | grep -c .) сетей"
    exit 0
fi

TMP=$(mktemp -d /var/tmp/rkn.XXXXXX); trap 'rm -rf "$TMP"' EXIT
for f in $LISTS; do
    curl -fsSL --retry 3 --max-time 120 -o "$TMP/$f" "$URL/$f" || fail "не удалось скачать $f"
done

# Берём только сети. Слишком широкие (IPv4 шире /16, IPv6 шире /24) не
# берём: в этих списках таких нет, и если появятся, это ошибка списка,
# которая отрезала бы от ноды целые провайдеры.
cat "$TMP"/* | tr -d '\r' | awk '
    { sub(/#.*/, "") }            # комментарий бывает и в конце строки с сетью
    /^[[:space:]]*$/ { next }
    { n = $1 }
    n ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$/ {
        p = (n ~ /\//) ? substr(n, index(n, "/") + 1) + 0 : 32
        if (p >= 16 && p <= 32) { print n; next }
    }
    n ~ /^[0-9a-fA-F:]+:[0-9a-fA-F:]*(\/[0-9]+)?$/ {
        p = (n ~ /\//) ? substr(n, index(n, "/") + 1) + 0 : 128
        if (p >= 24 && p <= 128) { print n; next }
    }
    { bad++ }
    END { if (bad) printf "пропущено строк: %d\n", bad > "/dev/stderr" }
' 2>"$TMP/skipped" | sort -u > "$TMP/nets"
n4=$(grep -vc ':' "$TMP/nets"); n6=$(grep -c ':' "$TMP/nets")
[ "$n4" -ge $MIN4 ] || fail "в списках всего $n4 сетей IPv4 — похоже, они сломаны"

# Исключения: IP панели и свои сети. nomatch в hash:net перекрывает более
# широкую сеть того же набора — адрес из исключений не блокируется никогда.
{ [ -n "$PANEL_IP" ] && echo "$PANEL_IP"
  [ -f "$ALLOW" ] && tr -d '\r' < "$ALLOW" | awk '!/^[[:space:]]*(#|$)/ { print $1 }'
} | sort -u | awk '{ print $1 " nomatch" }' > "$TMP/allow"

cat "$TMP/nets" "$TMP/allow" > "$TMP/list"
msg="сетей: IPv4 $n4, IPv6 $n6, исключений $(grep -c . "$TMP/allow")"
[ -s "$TMP/skipped" ] && msg="$msg, $(cat "$TMP/skipped")"

if [ "$MODE" = --print ]; then
    cat "$TMP/list"; log "проверка: $msg, ничего не менял"; exit 0
fi

# Новые наборы собираем рядом и подменяем разом: блокировка не исчезает
# ни на миг, а при сбое остаётся прежней
create_sets || fail "ipset не создал наборы"
ipset destroy $SET4-new 2>/dev/null; ipset destroy $SET6-new 2>/dev/null
{ echo "create $SET4-new hash:net family inet maxelem 131072"
  echo "create $SET6-new hash:net family inet6 maxelem 131072"
  restore_cmds $SET4-new $SET6-new < "$TMP/list"
} | ipset restore -exist || { ipset destroy $SET4-new 2>/dev/null; ipset destroy $SET6-new 2>/dev/null; fail "ipset не принял список"; }
ipset swap $SET4-new $SET4 && ipset swap $SET6-new $SET6 || fail "ipset не подменил наборы"
ipset destroy $SET4-new; ipset destroy $SET6-new
mkdir -p "$(dirname "$SAVE")"
cp "$TMP/list" "$SAVE.tmp" && mv "$SAVE.tmp" "$SAVE"
rm -f "$STATE/notified"
log "наборы обновлены: $msg"
BODY
    } > "$RKN_BIN"
    chmod 755 "$RKN_BIN"
    return 0
}

rkn_write_units() {
    # Подъём наборов до ufw. Без [Install]: его тянет за собой сам ufw через
    # дополнение ниже — тогда порядок соблюдается при любом способе запуска ufw.
    cat <<UNIT > "$RKN_RESTORE_UNIT"
[Unit]
Description=Наборы ipset для защиты от проберов РКН (до ufw)
DefaultDependencies=no
After=local-fs.target systemd-modules-load.service
Before=ufw.service network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$RKN_BIN --restore
UNIT
    mkdir -p "$(dirname "$RKN_UFW_DROPIN")"
    cat <<'UNIT' > "$RKN_UFW_DROPIN"
# fixerror-node: правило ufw ссылается на наборы ipset — поднять их раньше
[Unit]
Wants=rkn-block-restore.service
After=rkn-block-restore.service
UNIT
    cat <<UNIT > "$RKN_UNIT"
[Unit]
Description=Обновление сетей РКН для блокировки входящих
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$RKN_BIN
UNIT
    # Раз в сутки; разброс в час — чтобы ноды не ходили на GitHub разом
    cat <<'UNIT' > "$RKN_TIMER"
[Unit]
Description=Обновление сетей РКН для блокировки раз в сутки

[Timer]
OnCalendar=*-*-* 02:30:00 UTC
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
UNIT
    return 0
}

# Строки правил для before.rules ($1 = 4) или before6.rules ($1 = 6)
rkn_rules_render() {
    local chain="ufw-before-input" set="rkn-block"
    [[ "$1" == 6 ]] && { chain="ufw6-before-input"; set="rkn-block6"; }
    echo "$RKN_MARK"
    echo "-A $chain -m conntrack --ctstate NEW -m set --match-set $set src -j DROP"
    return 0
}

# Вписывает правило в файл ($1) после «# End required lines»; старые строки
# убирает, поэтому повторный запуск ничего не дублирует. Без $2 — только убрать.
rkn_rules_write() {
    local file="$1" blk="${2:-}" tmp
    [[ -f "$file" ]] || return 0
    tmp=$(mktemp)
    if ! grep -v -e '--match-set rkn-block' -e "^$RKN_MARK" "$file" \
        | awk -v blk="$blk" '
            { print }
            blk != "" && /^# End required lines/ && !done { print blk; done=1 }
            END { if (blk != "" && !done) exit 3 }' > "$tmp"; then
        rm -f "$tmp"
        echo "  [СБОЙ] в $file нет строки «# End required lines» — правило не вставлено"
        return 1
    fi
    cat "$tmp" > "$file"
    rm -f "$tmp"
    return 0
}

rkn_rules_apply() {
    rkn_rules_write "$UFW_BEFORE" "$(rkn_rules_render 4)" || return 1
    rkn_rules_write "$UFW_BEFORE6" "$(rkn_rules_render 6)" || return 1
    return 0
}

rkn_rules_remove() {
    rkn_rules_write "$UFW_BEFORE" || return 1
    rkn_rules_write "$UFW_BEFORE6" || return 1
    return 0
}

rkn_sets_exist() {
    ipset list -n rkn-block >/dev/null 2>&1 && ipset list -n rkn-block6 >/dev/null 2>&1 && return 0
    return 1
}

# После сброса ufw (пункт «UFW + торренты») правило пропадает вместе с
# before.rules. Возвращаем его, только если наборы уже есть: правило без
# набора не даст ufw включиться.
rkn_rules_reapply() {
    rkn_block_enabled || return 0
    rkn_sets_exist || return 0
    rkn_rules_apply || return 1
    return 0
}

rkn_write_allow() {
    local n
    mkdir -p "$(dirname "$RKN_ALLOW_FILE")"
    if [[ ! -f "$RKN_ALLOW_FILE" ]]; then
        {
            echo "# Сети и адреса, которые защита от проберов РКН не блокирует никогда,"
            echo "# по одной на строку. IP панели добавляется сам. После правки: sudo rkn-block"
        } > "$RKN_ALLOW_FILE"
    fi
    for n in ${RKN_ALLOW:-}; do
        grep -qxF "$n" "$RKN_ALLOW_FILE" || echo "$n" >> "$RKN_ALLOW_FILE"
    done
    return 0
}

comp_rkn_block() {
    echo ">>> Защита от проберов РКН (ipset)..."
    ufw status 2>/dev/null | head -1 | grep -q 'active' \
        || { echo "  [СБОЙ] ufw не включён — сначала пункт 2 -> 5 (UFW + торренты)"; return 1; }
    apt-get "${APT_WAIT[@]}" install -y ipset >>"$SETUP_LOG" 2>&1 || true
    command -v ipset >/dev/null 2>&1 || { echo "  [СБОЙ] не удалось поставить ipset (см. $SETUP_LOG)"; return 1; }
    rkn_write_allow
    rkn_write_updater
    rkn_write_units
    systemctl daemon-reload >>"$SETUP_LOG" 2>&1

    # Сначала наборы, потом правило: наоборот ufw не перезагрузится
    if ! "$RKN_BIN"; then
        echo "  [СБОЙ] не удалось скачать списки (журнал: journalctl -t rkn-block)"
        rkn_sets_exist && [[ -s "$RKN_SAVE" ]] || return 1
        echo "  Прежние наборы на месте — продолжаю с ними."
    fi
    rkn_sets_exist || { echo "  [СБОЙ] наборов ipset нет после обновления"; return 1; }
    echo "  В наборах: IPv4 $(rkn_set_count rkn-block), IPv6 $(rkn_set_count rkn-block6)"

    rkn_rules_apply || return 1
    if ! ufw reload >>"$SETUP_LOG" 2>&1; then
        echo "  [СБОЙ] ufw не перезагрузился с правилом — убираю правило"
        rkn_rules_remove; ufw reload >>"$SETUP_LOG" 2>&1 || true
        return 1
    fi
    iptables -S ufw-before-input 2>/dev/null | grep -q -- '--match-set rkn-block src' \
        || { echo "  [СБОЙ] правило не появилось в ufw-before-input"; return 1; }

    systemctl enable --now rkn-block.timer >>"$SETUP_LOG" 2>&1 || true
    systemctl is-enabled --quiet rkn-block.timer 2>/dev/null \
        || { echo "  [СБОЙ] таймер rkn-block.timer не включился"; return 1; }
    echo "  Режутся новые входящие из этих сетей; ответы на исходящие проходят"
    echo "  Обновление: раз в сутки в 02:30 UTC, плюс до часа"
    echo "  Исключения: $RKN_ALLOW_FILE (IP панели — всегда)"
    return 0
}

# Выключение: правило, таймер и наборы убираются, сохранённая копия остаётся
rkn_block_off() {
    echo ">>> Выключаю защиту от проберов РКН..."
    rkn_rules_remove || return 1
    ufw reload >>"$SETUP_LOG" 2>&1 || { echo "  [СБОЙ] ufw не перезагрузился"; return 1; }
    systemctl disable --now rkn-block.timer >>"$SETUP_LOG" 2>&1 || true
    rm -f "$RKN_UFW_DROPIN"
    systemctl daemon-reload >>"$SETUP_LOG" 2>&1
    ipset destroy rkn-block 2>/dev/null || true
    ipset destroy rkn-block6 2>/dev/null || true
    RKN_BLOCK="n"; save_state
    echo "  Выключено. Включить снова: меню, пункт 2 -> 28."
    return 0
}

comp_rkn_block_menu() {
    local a=""
    if rkn_sets_exist; then
        echo "  Защита включена: IPv4 $(rkn_set_count rkn-block), IPv6 $(rkn_set_count rkn-block6) сетей."
        read -ep "  1 — обновить и переустановить, 2 — выключить, Enter — назад: " a || a=""
        case "$a" in
            1) ;;
            2) rkn_block_off; return $? ;;
            *) return 0 ;;
        esac
    fi
    RKN_BLOCK="y"
    comp_rkn_block || return 1
    save_state
    return 0
}
