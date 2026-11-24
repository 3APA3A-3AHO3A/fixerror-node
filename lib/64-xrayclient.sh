# ##########################################################################
#  СВОЙ XRAY-КЛИЕНТ НА НОДАХ В РФ
#  Через него ходят Telegram-уведомления ноды: api.telegram.org из РФ закрыт.
#  Конфиг — «Автовыбор» из подписки FixErrorVPN, обновление раз в 6 часов.
# ##########################################################################

# Зачем подписка, а не конфиг руками. Серверы в панели добавляются и меняются,
# а конфиг, вписанный руками один раз, тихо устаревает: однажды все его серверы
# окажутся мёртвыми, и нода перестанет сообщать, что с ней что-то не так.
# Из подписки берётся конфиг «Автовыбор» шаблона AutoBalancer — тот же, что
# у клиентов: российское напрямую, остальное через лучший живой сервер.
#
# Что защищает от поломки. Новый конфиг ставится, только если прошёл
# xray -test и через него открылся Telegram; иначе возвращается прежний.
# Входы всегда принудительно на 127.0.0.1:10808/10809, что бы ни пришло.

xrayc_wanted() {
    [[ "${INSTALL_XRAY_CLIENT:-n}" =~ ^[Yy]$ ]] && return 0
    return 1
}

# Архитектура в имени архива релиза Xray
xrayc_asset_name() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "Xray-linux-64.zip" ;;
        aarch64|arm64) echo "Xray-linux-arm64-v8a.zip" ;;
        *) return 1 ;;
    esac
    return 0
}

# Бинарник из официального релиза XTLS, со сверкой SHA-256 из .dgst
xrayc_install_bin() {
    local asset t want got
    asset=$(xrayc_asset_name) || { echo "  [СБОЙ] архитектура $(uname -m) не поддерживается"; return 1; }
    t=$(mktemp -d)
    if ! curl -fsSL --retry 2 --max-time 180 -o "$t/x.zip" "$XRAYC_REL_URL/$asset" \
       || ! curl -fsSL --retry 2 --max-time 60 -o "$t/x.dgst" "$XRAYC_REL_URL/$asset.dgst"; then
        rm -rf "$t"; echo "  [СБОЙ] не удалось скачать Xray с GitHub"; return 1
    fi
    want=$(awk -F'= *' 'toupper($1) ~ /^SHA2-256/ {print $2; exit}' "$t/x.dgst" | tr -d '[:space:]')
    got=$(sha256sum "$t/x.zip" | awk '{print $1}')
    if [[ -z "$want" || "$want" != "$got" ]]; then
        rm -rf "$t"; echo "  [СБОЙ] контрольная сумма архива Xray не совпала — не ставлю"; return 1
    fi
    if ! unzip -o -q "$t/x.zip" xray -d "$t" || ! "$t/xray" version >/dev/null 2>&1; then
        rm -rf "$t"; echo "  [СБОЙ] архив Xray не распаковался"; return 1
    fi
    if [[ -x "$XRAYC_BIN" ]] && cmp -s "$t/xray" "$XRAYC_BIN"; then
        echo "  Xray уже последней версии: $("$XRAYC_BIN" version | awk 'NR==1{print $2}')"
    else
        install -m 755 "$t/xray" "$XRAYC_BIN"
        echo "  Xray: $("$XRAYC_BIN" version | awk 'NR==1{print $2}')"
    fi
    rm -rf "$t"
    return 0
}

xrayc_write_units() {
    # Своя служба — только если её ещё нет: на нодах, где xray ставили
    # установщиком XTLS, его служба остаётся как есть
    if ! systemctl cat xray.service >/dev/null 2>&1; then
        cat <<UNIT > "$XRAYC_UNIT"
[Unit]
Description=Xray-клиент ноды (Telegram-уведомления), только 127.0.0.1
After=network-online.target
Wants=network-online.target

[Service]
User=nobody
NoNewPrivileges=true
ExecStart=$XRAYC_BIN run -config $XRAYC_CFG
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT
    fi
    # Geo-базы — те же, что у ноды: их и так раз в 3 дня обновляет geo-update
    mkdir -p "$(dirname "$XRAYC_DROPIN")"
    cat <<UNIT > "$XRAYC_DROPIN"
# fixerror-node: geo-базы — общие с нодой ($GEODATA_DIR, обновляет geo-update)
[Service]
Environment=XRAY_LOCATION_ASSET=$GEODATA_DIR
UNIT
    cat <<UNIT > "$XRAYC_SUB_UNIT"
[Unit]
Description=Конфиг xray-клиента из подписки FixErrorVPN (Автовыбор)
Wants=network-online.target
After=network-online.target xray.service

[Service]
Type=oneshot
ExecStart=$XRAYC_UPDATER
UNIT
    cat <<'UNIT' > "$XRAYC_SUB_TIMER"
[Unit]
Description=Обновление конфига xray-клиента из подписки раз в 6 часов

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
RandomizedDelaySec=20min
Persistent=true

[Install]
WantedBy=timers.target
UNIT
    return 0
}

# Скрипт обновления. Пути вписываются при установке; переменные окружения
# XSUB_* их подменяют — так скрипт проверяется тестами без сервера.
xrayc_write_updater() {
    {
        cat <<HEAD
#!/bin/bash
# xray-sub-update — конфиг xray-клиента ноды из подписки FixErrorVPN («Автовыбор»).
# Новый конфиг ставится, только если прошёл xray -test и через него открылся
# Telegram; иначе возвращается прежний. Ссылка подписки — в URL_FILE (600).
set -u
URL_FILE=\${XSUB_URL_FILE:-$XRAYC_SUB_FILE}
CFG=\${XSUB_CFG:-$XRAYC_CFG}
XRAY=\${XSUB_XRAY:-$XRAYC_BIN}
ASSET=\${XSUB_ASSET:-$GEODATA_DIR}
STATE=\${XSUB_STATE:-/var/lib/xray-sub}
NOTIFY=\${XSUB_NOTIFY:-$NOTIFY_BIN}
PROXY=$XRAYC_PROXY
HEAD
        cat <<'BODY'
PREV=$CFG.prev
mkdir -p "$STATE"
log(){ echo "$*"; logger -t xray-sub "$*" 2>/dev/null || true; }
# Ошибка: в журнал всегда, в Telegram — не чаще раза в сутки
fail(){
    log "ОШИБКА: $*"
    if [ -z "$(find "$STATE/notified" -mmin -1440 2>/dev/null)" ] && [ -x "$NOTIFY" ]; then
        "$NOTIFY" "⚠️ <b>xray-клиент: не обновился конфиг из подписки</b>: $*" >/dev/null 2>&1 && touch "$STATE/notified"
    fi
    exit 1
}
[ -s "$URL_FILE" ] || fail "нет ссылки подписки ($URL_FILE)"
URL=$(tr -d ' \r\n' < "$URL_FILE")
VER=$("$XRAY" version 2>/dev/null | awk 'NR==1{print $2}')
HWID="srv-$(sha256sum /etc/machine-id 2>/dev/null | cut -c1-16)"
T=$(mktemp -d /var/tmp/xsub.XXXXXX); trap 'rm -rf "$T"' EXIT

# Правило ответов «FixErrorVPN Xray» отдаёт Xray JSON по такому User-Agent
get(){ curl -fsS -m 40 "$@" -o "$T/sub.json" \
        -H "User-Agent: FixErrorVPN-server Xray-core/${VER:-0}" -H "x-hwid: $HWID" \
        -H "x-device-os: Linux" -H "x-device-model: $(hostname -s)" "$URL"; }
# Сначала напрямую, при неудаче — через сам клиент
get 2>/dev/null || get -x "$PROXY" 2>/dev/null || fail "подписка не скачалась"

python3 - "$T/sub.json" "$T/new.json" <<'PY' || fail "в подписке нет конфига «Автовыбор» (балансировщик Default_Balancer)"
import json, sys
d = json.load(open(sys.argv[1]))
items = d if isinstance(d, list) else [d]
pick = next((c for c in items if isinstance(c, dict) and any(b.get('tag') == 'Default_Balancer'
             for b in c.get('routing', {}).get('balancers', []))), None)
if not pick or sum(1 for o in pick.get('outbounds', []) if str(o.get('tag', '')).startswith('proxy')) < 2:
    sys.exit(1)
pick.pop('remarks', None)
# Входы — только наши порты и только localhost, что бы ни пришло
pick['inbounds'] = [i for i in pick.get('inbounds', []) if i.get('port') in (10808, 10809)]
for i in pick['inbounds']:
    i['listen'] = '127.0.0.1'
if len(pick['inbounds']) != 2:
    sys.exit(1)
json.dump(pick, open(sys.argv[2], 'w'), indent=2, ensure_ascii=False)
PY

if cmp -s "$T/new.json" "$CFG"; then log "без изменений"; rm -f "$STATE/notified"; exit 0; fi
XRAY_LOCATION_ASSET=$ASSET "$XRAY" run -test -config "$T/new.json" >"$T/test.log" 2>&1 \
    || fail "новый конфиг не прошёл xray -test: $(tail -1 "$T/test.log")"

had_prev=0
[ -f "$CFG" ] && cp -a "$CFG" "$PREV" && had_prev=1
mkdir -p "$(dirname "$CFG")"
install -m 644 "$T/new.json" "$CFG"
systemctl restart xray
ok=0
for n in 1 2 3 4 5 6; do
    sleep "${XSUB_WAIT:-5}"
    code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' -x "$PROXY" https://api.telegram.org || true)
    [ -n "$code" ] && [ "$code" != "000" ] && { ok=1; break; }
done
if [ $ok = 1 ]; then
    n=$(python3 -c "import json,sys;print(sum(1 for o in json.load(open(sys.argv[1]))['outbounds'] if str(o.get('tag','')).startswith('proxy')))" "$CFG")
    log "конфиг обновлён из подписки: серверов $n, Telegram через клиент открывается"
    rm -f "$STATE/notified"
    exit 0
fi
if [ $had_prev = 1 ]; then
    cp -a "$PREV" "$CFG"; systemctl restart xray
    fail "через новый конфиг не открылся Telegram — вернул прежний"
fi
mv -f "$CFG" "$CFG.bad"; systemctl stop xray
fail "через конфиг из подписки не открылся Telegram (прежнего конфига не было)"
BODY
    } > "$XRAYC_UPDATER"
    chmod 755 "$XRAYC_UPDATER"
    return 0
}

xrayc_write_url() {
    mkdir -p "$(dirname "$XRAYC_SUB_FILE")"
    ( umask 077; printf '%s\n' "$XRAY_SUB_URL" > "$XRAYC_SUB_FILE" )
    chmod 600 "$XRAYC_SUB_FILE"
    return 0
}

comp_xray_client() {
    echo ">>> Свой xray-клиент для Telegram (конфиг из подписки FixErrorVPN)..."
    ask_xray_sub || return 1
    [[ -d "$GEODATA_DIR" ]] || echo "  [ВНИМАНИЕ] нет $GEODATA_DIR — без geo-баз конфиг не пройдёт проверку (пункт 2 -> 25)"
    xrayc_install_bin || return 1
    xrayc_write_url
    xrayc_write_updater
    xrayc_write_units
    systemctl daemon-reload >>"$SETUP_LOG" 2>&1
    if ! "$XRAYC_UPDATER"; then
        echo "  [СБОЙ] конфиг из подписки не встал (журнал: journalctl -t xray-sub)"
        return 1
    fi
    systemctl enable xray.service >>"$SETUP_LOG" 2>&1 || true
    systemctl enable --now xray-sub-update.timer >>"$SETUP_LOG" 2>&1 || true
    if ! ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -qx '127.0.0.1:10808'; then
        echo "  [СБОЙ] xray не слушает 127.0.0.1:10808"
        return 1
    fi
    echo "  Слушает 127.0.0.1:10808 (socks) и 10809 (http); для Telegram: TG_PROXY=$XRAYC_PROXY"
    echo "  Обновление конфига: раз в 6 часов (xray-sub-update.timer), журнал: journalctl -t xray-sub"
    return 0
}

comp_xray_client_menu() { INSTALL_XRAY_CLIENT="y"; comp_xray_client || return 1; save_state; return 0; }
