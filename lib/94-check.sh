# ##########################################################################
#  ДИАГНОСТИКА НОДЫ
#
#  Функция rh_check НИЧЕГО НЕ МЕНЯЕТ — только читает и рассказывает, что нашла.
#  Это сознательное ограничение, и оно проверяется тестом, а не обещанием:
#  диагностику запускают на живой ноде посреди рабочего дня.
#
#  Живёт здесь, а не в отдельном файле, чтобы на сервер приезжал ОДИН скрипт:
#  меню -> «Диагностика», и всё. Из этого же модуля сборщик делает
#  самостоятельный check.sh для тех, кому нужна только проверка.
# ##########################################################################

# Значки и цвета — общие с установщиком (lib/05-ui.sh), чтобы диагностика
# не выглядела отдельной программой.
rhc_ok()   { ui_ok "$*"; }
rhc_warn() { ui_warn "$*"; rhc_warnings=$((rhc_warnings+1)); return 0; }
rhc_bad()  { ui_err "$*";  rhc_problems=$((rhc_problems+1)); return 0; }
rhc_info() { ui_info "$*"; }
rhc_sect() { ui_section "$*"; }
rhc_fix()  { rhc_fixes+=("$*"); }

# Порты, на которых сейчас слушает SSH. При socket-активации слушателем
# выступает systemd, поэтому его тоже засчитываем.
rhc_ports()     { ss -H -ltnp 2>/dev/null | grep -E 'users:\(\("(sshd|systemd)"' \
                  | awk '{print $4}' | sed 's/.*://' | sort -un; return 0; }
rhc_listening() { ss -H -ltn 2>/dev/null | awk '{print $4}' | sed 's/.*://' | sort -un; return 0; }
rhc_hasport()   { grep -qx "$1" <<< "$(rhc_listening)"; }
rhc_perm()      { stat -c '%a' "$1" 2>/dev/null || echo "?"; }
# grep -c при нуле совпадений печатает "0" И возвращает ненулевой код.
# Из-за этого "|| echo 0" дописывал второй ноль, получалось "0\n0",
# и арифметическое сравнение падало с syntax error.
rhc_num()       { local v; v=$(printf '%s' "${1:-}" | head -1 | tr -cd '0-9'); echo "${v:-0}"; }

# rh_check [--deep]   — вызывать ТОЛЬКО в подоболочке: ( rh_check )
rh_check() {
    # Диагностика перебирает десятки проверок, половина из которых штатно
    # возвращает ненулевой код. Внутри установщика это поймал бы ERR-трап.
    set +e
    trap - ERR

    local rhc_problems=0 rhc_warnings=0
    local rhc_fixes=()
    local rhc_deep="" rhc_compose="/opt/remnanode/docker-compose.yml"
    [[ "${1:-}" == "--deep" ]] && rhc_deep=1

    if [[ "$EUID" -ne 0 ]]; then
        echo "Нужны права root."
        return 1
    fi

    ui_title "Диагностика ноды" "$(date '+%Y-%m-%d %H:%M:%S %Z') · ничего не меняется"

    # ----------------------------------------------------------------------
    rhc_sect "Система"
    # ----------------------------------------------------------------------
    rhc_info "$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") | ядро $(uname -r)"
    rhc_info "хост $(hostname) | uptime $(uptime -p 2>/dev/null || echo '?')"
    rhc_info "внешний IP: $(curl -fs --max-time 8 https://api.ipify.org 2>/dev/null || echo 'не определился')"

    local rhc_tz rhc_sync
    rhc_tz=$(timedatectl show -p Timezone --value 2>/dev/null)
    rhc_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [[ "$rhc_tz" == "Etc/UTC" || "$rhc_tz" == "UTC" ]]; then
        rhc_ok "часовой пояс UTC"
    else
        rhc_warn "часовой пояс ${rhc_tz:-?}, а на всех серверах UTC"
        rhc_fix "время: меню, пункт 2 -> 21"
    fi
    if [[ "$rhc_sync" == "yes" ]]; then
        rhc_ok "время синхронизировано"
    else
        rhc_warn "время не синхронизировано (NTP)"
        rhc_fix "время: меню, пункт 2 -> 21"
    fi

    if [[ -f "$INSTALL_STATE" ]]; then
        rhc_ok "install.conf найден — нода ставилась этим скриптом"
        # shellcheck disable=SC1090
        source "$INSTALL_STATE" 2>/dev/null || true
    else
        # Не проблема: установщик умеет вычитывать настройки с самого сервера,
        # а файл создаётся при первой же правке через меню.
        rhc_info "нет $INSTALL_STATE — нода ставилась ранней версией"
        rhc_info "настройки будут вычитаны с сервера; файл появится после первой правки через меню"
    fi
    local rhc_np="${NODE_PORT:-2222}"

    if [[ -z "$(swapon --show 2>/dev/null)" ]]; then
        rhc_warn "swap не подключён"
        rhc_fix "swap: меню, пункт 2 -> 7"
    else
        rhc_ok "swap: $(swapon --show=SIZE --noheadings 2>/dev/null | tr -d ' \n')"
    fi

    # ----------------------------------------------------------------------
    rhc_sect "SSH"
    # ----------------------------------------------------------------------
    local rhc_inc rhc_hard="$SSH_HARDEN_FILE" rhc_conflict
    rhc_inc=$(grep -nE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' \
              /etc/ssh/sshd_config 2>/dev/null | head -1 | cut -d: -f1)

    if [[ -z "$rhc_inc" ]]; then
        if [[ -f "$rhc_hard" ]]; then
            rhc_bad "файл харденинга есть, но sshd_config его НЕ ЧИТАЕТ — настройки не применены"
            rhc_fix "SSH: меню, пункт 4 (починка) — вернёт Include и перезальёт харденинг"
        else
            rhc_info "sshd_config.d не подключён, и файла харденинга нет"
        fi
    else
        rhc_ok "sshd_config читает каталог sshd_config.d (строка $rhc_inc)"
        # sshd берёт ПЕРВОЕ встреченное значение. Если Include стоит не в начале,
        # директивы выше него побеждают — и харденинг применяется лишь частично.
        rhc_conflict=$(awk -v n="$rhc_inc" \
            'NR<n && /^[[:space:]]*(PermitRootLogin|PasswordAuthentication)[[:space:]]/ {print "    строка "NR": "$0}' \
            /etc/ssh/sshd_config 2>/dev/null)
        if [[ -n "$rhc_conflict" ]]; then
            rhc_bad "выше Include заданы настройки, которые перебивают харденинг:"
            echo "$rhc_conflict"
            rhc_info "sshd берёт первое встреченное значение, поэтому файл харденинга ниже игнорируется"
            rhc_fix "SSH: меню, пункт 4 (починка) — закомментирует эти строки"
        fi
    fi

    # Дроп-ины читаются по алфавиту, и между ними действует тот же принцип.
    # Хостеры кладут файлы вида 00-*.conf — они сортируются раньше нашего.
    local rhc_f rhc_base rhc_early=""
    for rhc_f in /etc/ssh/sshd_config.d/*.conf; do
        [[ -e "$rhc_f" ]] || continue
        rhc_base=$(basename "$rhc_f")
        [[ "$rhc_base" < "$(basename "$SSH_HARDEN_FILE")" ]] || continue
        grep -qE '^[[:space:]]*(PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication)[[:space:]]' \
             "$rhc_f" || continue
        rhc_early+=" $rhc_base"
    done
    if [[ -n "$rhc_early" ]]; then
        rhc_bad "чужие дроп-ины читаются раньше нашего и перебивают харденинг:$rhc_early"
        rhc_info "такое оставляет хостер после ремонта сервера — настройки возвращаются к своим"
        rhc_fix "SSH: меню, пункт 4 (починка) — закомментирует эти строки и перезапустит sshd"
    fi

    if [[ -f "$rhc_hard" ]]; then
        rhc_ok "файл харденинга на месте"
    else
        rhc_bad "нет $rhc_hard — харденинг SSH на этой ноде не применялся"
        rhc_fix "SSH: меню, пункт 2 -> 8 (первичный харденинг спросит ключ)"
    fi

    local rhc_cfgport rhc_live
    rhc_cfgport=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')
    rhc_live=$(rhc_ports | tr '\n' ' ')
    rhc_info "порт в конфиге: ${rhc_cfgport:-?} | слушает сейчас: ${rhc_live:-никто}"
    if [[ -n "$rhc_cfgport" ]] && grep -qx "$rhc_cfgport" <<< "$(rhc_ports)"; then
        rhc_ok "sshd слушает тот порт, что указан в конфиге"
    elif [[ -n "$rhc_live" ]]; then
        rhc_warn "порт из конфига не совпадает с рабочим — настройки применятся после перезагрузки"
    else
        rhc_bad "sshd не слушает вообще ничего"
    fi

    local rhc_root rhc_pass
    rhc_root=$(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2}')
    rhc_pass=$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')
    if [[ -z "$rhc_root$rhc_pass" ]]; then
        if [[ ! -d /run/sshd ]] && systemctl is-active --quiet ssh.socket 2>/dev/null; then
            # Диагностика ничего не меняет, поэтому каталог не создаём, а объясняем
            rhc_warn "настройки sshd не прочитать: SSH запущен по требованию (ssh.socket), а без /run/sshd sshd -T не работает — это не поломка"
        else
            rhc_warn "не удалось прочитать настройки sshd (sshd -T) — sshd не установлен?"
        fi
    else
        if [[ "$rhc_root" == "no" ]]; then
            rhc_ok "вход под root запрещён"
        else
            rhc_bad "вход под root разрешён ($rhc_root)"
            rhc_fix "SSH: меню, пункт 4 (починка)"
        fi
        if [[ "$rhc_pass" == "no" ]]; then
            rhc_ok "вход по паролю запрещён"
        else
            rhc_bad "вход по паролю разрешён ($rhc_pass)"
            rhc_fix "SSH: меню, пункт 4 (починка)"
        fi
    fi

    local rhc_home rhc_keys
    if [[ -n "${ADMIN_USER:-}" ]] && id "$ADMIN_USER" &>/dev/null; then
        rhc_home=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
        rhc_keys=$(rhc_num "$(grep -cvE '^[[:space:]]*(#|$)' "$rhc_home/.ssh/authorized_keys" 2>/dev/null)")
        if [[ "$rhc_keys" -gt 0 ]]; then
            rhc_ok "у $ADMIN_USER ключей: $rhc_keys"
        else
            rhc_bad "у $ADMIN_USER нет ни одного SSH-ключа"
        fi
    fi

    # Учётки ИИ-агентов: узнаются по группе, а не по имени
    local rhc_agents rhc_a
    rhc_agents=$(getent group "$AGENT_GROUP" 2>/dev/null | cut -d: -f4 | tr ',' ' ')
    if [[ -z "$rhc_agents" ]]; then
        rhc_info "учёток ИИ-агентов нет"
    fi
    for rhc_a in $rhc_agents; do
        rhc_home=$(getent passwd "$rhc_a" | cut -d: -f6)
        rhc_keys=$(rhc_num "$(grep -cvE '^[[:space:]]*(#|$)' "$rhc_home/.ssh/authorized_keys" 2>/dev/null)")
        if [[ "$rhc_keys" -eq 0 ]]; then
            rhc_warn "учётка агента $rhc_a без ключей — войти в неё нельзя"
        elif [[ -f "/etc/sudoers.d/91-agent-$rhc_a" ]]; then
            rhc_ok "учётка ИИ-агента $rhc_a: ключей $rhc_keys, sudo есть"
        else
            rhc_warn "учётка ИИ-агента $rhc_a без sudo — чинить и ставить ничего не сможет"
            rhc_fix "агент: меню, пункт 2 -> 24"
        fi
    done

    # Ключи сервера от образа хостера (одинаковые у всех его серверов)
    local rhc_f rhc_c rhc_tpl=""
    for rhc_f in /etc/ssh/ssh_host_*_key.pub; do
        [[ -e "$rhc_f" ]] || continue
        rhc_c=$(awk '{print $3}' "$rhc_f"); rhc_c="${rhc_c#*@}"
        [[ -z "$rhc_c" || "$rhc_c" == "$(hostname)" || "$rhc_c" == "$(hostname -s)" ]] && continue
        rhc_tpl+=" $(basename "$rhc_f" .pub)"
    done
    if [[ -n "$rhc_tpl" && ! -f /etc/fixerror-node/hostkeys.done ]]; then
        rhc_warn "ключи сервера, похоже, от образа хостера (подписаны чужим именем):$rhc_tpl"
        rhc_fix "ключи сервера: полная установка перевыпустит их (шаг «Ключи сервера»)"
    fi

    # ----------------------------------------------------------------------
    rhc_sect "Фаервол"
    # ----------------------------------------------------------------------
    local rhc_p rhc_ipv6
    if ufw status 2>/dev/null | head -1 | grep -q 'active'; then
        rhc_ok "ufw включён"
        for rhc_p in $(rhc_ports); do
            if ufw status 2>/dev/null | grep -qE "(^| )$rhc_p/tcp"; then
                rhc_ok "SSH-порт $rhc_p открыт в ufw"
            else
                rhc_bad "SSH-порт $rhc_p НЕ открыт в ufw — после разрыва сессии не зайти"
                rhc_fix "ufw: ufw limit $rhc_p/tcp"
            fi
        done
        if ufw status 2>/dev/null | grep -q "$rhc_np"; then
            rhc_ok "порт ноды $rhc_np есть в правилах"
        else
            rhc_bad "порт ноды $rhc_np не открыт — панель не достучится"
            rhc_fix "ufw: меню, пункт 2 -> 5"
        fi
        # TCP-порты, которые слушает ядро ноды на всех адресах, но которых нет в
        # ufw: клиенты на них не достучатся. Только TCP: UDP-сокеты ядро держит
        # и для исходящих соединений на случайных портах, и отличить по ним
        # входящий порт (Hysteria2) от исходящего снаружи нельзя.
        local rhc_l rhc_closed=""
        while read -r rhc_l; do
            [[ -z "$rhc_l" ]] && continue
            ufw status 2>/dev/null | grep -qE "^${rhc_l}([[:space:]]|$)" && continue
            # ufw allow 443 (без протокола) открывает и tcp, и udp
            ufw status 2>/dev/null | grep -qE "^${rhc_l%/*}([[:space:]]|$)" && continue
            rhc_closed+=" $rhc_l"
        done < <(ss -H -lntp 2>/dev/null | sed 's/^/tcp /' | grep -E 'users:\(\("(rw-core|xray)"' \
                 | awk '$5 ~ /^(0\.0\.0\.0|\*|\[::\]):/ {split($5,a,":"); print a[length(a)] "/" $1}' | sort -u)
        if [[ -n "$rhc_closed" ]]; then
            rhc_warn "ядро ноды слушает TCP-порты, закрытые фаерволом:$rhc_closed — клиенты на них не подключатся"
            rhc_fix "ufw: sudo ufw allow <порт>/<tcp|udp> (учтите: шаг UFW при переустановке сбросит ручные правила)"
        fi
        # Заполненность таблицы соединений: при переполнении ядро молча
        # отбрасывает новые подключения клиентов
        local rhc_ct rhc_ctmax
        rhc_ct=$(rhc_num "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)")
        rhc_ctmax=$(rhc_num "$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)")
        if [[ "$rhc_ctmax" -gt 0 ]]; then
            if (( rhc_ct * 100 / rhc_ctmax >= 80 )); then
                rhc_bad "таблица соединений заполнена на $(( rhc_ct * 100 / rhc_ctmax ))% ($rhc_ct из $rhc_ctmax) — скоро начнутся отказы клиентам"
                rhc_fix "conntrack: меню, пункт 2 -> 6 (Sysctl-тюнинг поднимет лимит)"
            elif [[ "$rhc_ctmax" -lt 262144 ]]; then
                rhc_warn "лимит таблицы соединений $rhc_ctmax (занято $rhc_ct) — для VPN-ноды мало"
                rhc_fix "conntrack: меню, пункт 2 -> 6 (Sysctl-тюнинг)"
            else
                rhc_ok "таблица соединений: занято $rhc_ct из $rhc_ctmax"
            fi
        fi
        rhc_ipv6=$(grep -E '^IPV6=' /etc/default/ufw 2>/dev/null | cut -d= -f2)
        if [[ -d /proc/sys/net/ipv6 ]]; then
            if [[ "$rhc_ipv6" == "yes" ]]; then
                rhc_ok "IPv6 живой и фильтруется фаерволом"
            else
                rhc_bad "IPv6 активен, но ufw его НЕ фильтрует (IPV6=$rhc_ipv6) — все порты открыты по IPv6"
                rhc_fix "IPv6: меню, пункт 2 -> 5 (перенастроит ufw) либо 6 (sysctl выключит IPv6)"
            fi
        else
            rhc_ok "IPv6 отключён в ядре — фильтровать нечего"
        fi
        local rhc_tor
        rhc_tor=$(rhc_num "$(torrent_rules_count)")
        if [[ "$rhc_tor" -ge 6 ]]; then
            if iptables -S ufw-before-output 2>/dev/null | grep -q 'BitTorrent protocol'; then
                rhc_ok "блокировка торрентов: $rhc_tor правил, действуют"
            else
                rhc_warn "правила против торрентов в before.rules есть, но не загружены (ufw reload)"
            fi
        else
            rhc_warn "правил против торрентов нет (в before.rules: $rhc_tor)"
            rhc_fix "торренты: меню, пункт 2 -> 5 (UFW + торренты)"
        fi
    else
        rhc_bad "ufw выключен"
        rhc_fix "ufw: меню, пункт 2 -> 5"
    fi

    local rhc_banned
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        if fail2ban-client status sshd >/dev/null 2>&1; then
            rhc_banned=$(fail2ban-client status sshd 2>/dev/null | awk -F: '/Currently banned/{print $2}' | tr -d '[:space:]')
            rhc_ok "fail2ban работает, джейл sshd активен (забанено сейчас: ${rhc_banned:-0})"
        else
            rhc_bad "fail2ban запущен, но джейл sshd НЕ поднялся — брутфорс никто не блокирует"
            dpkg -l python3-systemd 2>/dev/null | grep -q '^ii' \
                || rhc_fix "fail2ban: меню, пункт 2 -> 12 (доставит python3-systemd)"
        fi
    else
        rhc_bad "fail2ban не запущен"
        rhc_fix "fail2ban: меню, пункт 2 -> 12"
    fi

    # ----------------------------------------------------------------------
    rhc_sect "Ядро и сеть"
    # ----------------------------------------------------------------------
    if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" == "bbr" ]]; then
        rhc_ok "BBR включён"
    else
        rhc_warn "BBR не включён"
        rhc_fix "sysctl: меню, пункт 2 -> 6"
    fi
    if [[ -f "$SYSCTL_FILE" ]] && grep -q 'ip_local_reserved_ports' "$SYSCTL_FILE"; then
        local rhc_res
        rhc_res=$(sysctl -n net.ipv4.ip_local_reserved_ports 2>/dev/null)
        if grep -qw "$rhc_np" <<< "${rhc_res//,/ }"; then
            rhc_ok "порты служб зарезервированы: $rhc_res"
        else
            rhc_warn "в sysctl есть резерв портов, но ядро его не применило ($rhc_res)"
        fi
    else
        rhc_warn "нет общего шаблона sysctl ($SYSCTL_FILE) — нода отличается от остальных"
        rhc_fix "sysctl: меню, пункт 2 -> 6"
    fi
    local rhc_ifc rhc_mtu rhc_unit rhc_want
    rhc_ifc=$(default_iface)
    rhc_mtu=$(cat "/sys/class/net/$rhc_ifc/mtu" 2>/dev/null)
    rhc_unit="/etc/systemd/system/mtu-$rhc_ifc.service"
    if [[ -f "$rhc_unit" ]]; then
        rhc_want=$(grep -oE 'mtu [0-9]+' "$rhc_unit" | awk '{print $2; exit}')
        if [[ "$rhc_mtu" == "$rhc_want" ]]; then
            rhc_ok "MTU $rhc_ifc закреплён: $rhc_mtu"
        else
            rhc_bad "MTU $rhc_ifc сейчас $rhc_mtu, а служба задаёт $rhc_want"
            rhc_fix "MTU: systemctl restart mtu-$rhc_ifc"
        fi
    else
        rhc_info "MTU $rhc_ifc: ${rhc_mtu:-?} (не закреплялся; замер — меню, пункт 2 -> 10)"
    fi

    # ----------------------------------------------------------------------
    rhc_sect "Нода"
    # ----------------------------------------------------------------------
    local rhc_perms rhc_state rhc_restarts rhc_img
    if [[ -f "$rhc_compose" ]]; then
        rhc_perms=$(rhc_perm "$rhc_compose")
        if [[ "$rhc_perms" == "600" ]]; then
            rhc_ok "docker-compose.yml с правами 600"
        else
            rhc_bad "docker-compose.yml с правами $rhc_perms — SECRET_KEY ноды читает любой пользователь"
            rhc_fix "права: меню, пункт 4 (починка)"
        fi
    else
        rhc_bad "нет $rhc_compose — нода не развёрнута"
    fi

    if command -v docker >/dev/null 2>&1; then
        rhc_state=$(docker inspect -f '{{.State.Status}}' remnanode 2>/dev/null | head -1 | tr -d '\n')
        [[ -z "$rhc_state" ]] && rhc_state="контейнера нет"
        rhc_restarts=$(docker inspect -f '{{.RestartCount}}' remnanode 2>/dev/null || echo "?")
        rhc_img=$(docker inspect -f '{{.Config.Image}}' remnanode 2>/dev/null || echo "?")
        if [[ "$rhc_state" == "running" ]]; then
            rhc_ok "контейнер remnanode: running (перезапусков: $rhc_restarts, образ $rhc_img)"
            [[ "${rhc_restarts:-0}" -gt 5 ]] && rhc_warn "много перезапусков — смотри docker logs remnanode"
        else
            rhc_bad "контейнер remnanode: $rhc_state"
            rhc_fix "нода: меню, пункт 2 -> 3 (передеплой)"
        fi
        if rhc_hasport "$rhc_np"; then
            rhc_ok "порт $rhc_np слушает — панель сможет подключиться"
        else
            rhc_bad "порт $rhc_np не слушает — панель ноду не увидит"
        fi
        # На нодах, где Docker стоял раньше установщика, учётка оставалась вне
        # группы docker: команды работали только через sudo.
        if [[ -n "${ADMIN_USER:-}" ]] && id "$ADMIN_USER" &>/dev/null; then
            if id -nG "$ADMIN_USER" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
                rhc_ok "$ADMIN_USER в группе docker — docker ps работает без sudo"
            else
                rhc_warn "$ADMIN_USER не в группе docker — docker ps ответит permission denied"
                rhc_fix "docker: меню, пункт 4 (починка); применится в новой сессии SSH"
            fi
        fi

        # Geo-базы: свои (Loyalsoldier, обновляются cron) или встроенные в образ
        local rhc_age f
        if grep -q "$GEODATA_DIR/geosite.dat" "$rhc_compose" 2>/dev/null; then
            for f in geoip.dat geosite.dat; do
                if [[ ! -s "$GEODATA_DIR/$f" ]]; then
                    rhc_bad "в compose подключён $GEODATA_DIR/$f, а файла нет — Xray не стартует"
                    rhc_fix "geo-базы: меню, пункт 2 -> 25"
                    continue
                fi
                rhc_age=$(( ( $(date +%s) - $(stat -c %Y "$GEODATA_DIR/$f") ) / 86400 ))
                if [[ "$rhc_age" -gt 7 ]]; then
                    rhc_warn "$f не обновлялся $rhc_age дн. — журнал: journalctl -t geo-update"
                else
                    rhc_ok "$f свежий (обновлён $rhc_age дн. назад)"
                fi
            done
            if [[ -x "$GEODATA_BIN" ]] && systemctl is-enabled --quiet geo-update.timer 2>/dev/null; then
                rhc_ok "обновление geo-баз раз в 3 дня включено"
            else
                rhc_warn "geo-базы подключены, но таймер geo-update.timer не включён"
                rhc_fix "geo-базы: меню, пункт 4 (починка)"
            fi
        else
            rhc_info "geo-базы: встроенные в образ ноды (свои не подключены)"
        fi

        # Выходы для Xray: warp-native (интерфейс warp) и Psiphon (SOCKS)
        if [[ -d /opt/warp-native ]] || systemctl cat wg-quick@warp >/dev/null 2>&1; then
            if ip link show warp >/dev/null 2>&1 && systemctl is-active --quiet wg-quick@warp; then
                if curl -fsS --max-time 10 --interface warp https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q '^warp=on'; then
                    rhc_ok "warp-native: интерфейс warp работает (warp=on)"
                else
                    rhc_warn "warp-native: интерфейс warp поднят, но выход не через Cloudflare"
                fi
            else
                rhc_bad "warp-native установлен, но интерфейс warp не работает"
                rhc_fix "warp-native: меню, пункт 2 -> 26"
            fi
        else
            rhc_info "warp-native не установлен"
        fi
        if [[ -f /etc/default/vps-psiphon ]]; then
            if systemctl is-active --quiet vps-psiphon && rhc_hasport "$PSIPHON_PORT"; then
                rhc_ok "Psiphon работает, SOCKS на порту $PSIPHON_PORT"
            else
                rhc_bad "Psiphon установлен, но служба или порт $PSIPHON_PORT не работают"
                rhc_fix "Psiphon: меню, пункт 2 -> 27; состояние: vps-psiphon"
            fi
        else
            rhc_info "Psiphon не установлен"
        fi
    else
        rhc_bad "docker не установлен"
    fi

    # ----------------------------------------------------------------------
    rhc_sect "Сертификат, сайт и node-pull"
    # ----------------------------------------------------------------------
    local rhc_end rhc_days rhc_subj rhc_ngx
    if [[ -s "$NGINX_SSL/fullchain.pem" ]]; then
        rhc_subj=$(openssl x509 -in "$NGINX_SSL/fullchain.pem" -noout -subject 2>/dev/null)
        rhc_end=$(openssl x509 -enddate -noout -in "$NGINX_SSL/fullchain.pem" 2>/dev/null | cut -d= -f2)
        rhc_days=$(( ( $(date -d "$rhc_end" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
        if grep -q 'placeholder.invalid' <<< "$rhc_subj"; then
            rhc_bad "стоит временный сертификат установщика — с панели набор ещё не приходил"
            rhc_fix "node-pull: добавьте строку ключа на панели (меню, пункт 2 -> 22), потом sudo node-pull"
        elif [[ "$rhc_days" -gt 20 ]]; then
            rhc_ok "сертификат ($(sed 's/.*CN *= *//' <<< "$rhc_subj")): осталось $rhc_days дн."
        elif [[ "$rhc_days" -gt 0 ]]; then
            rhc_bad "сертификат истекает через $rhc_days дн. — node-pull не приносит новый"
            rhc_fix "node-pull: sudo node-pull; журнал: journalctl -t node-pull -n 10"
        else
            rhc_bad "сертификат ПРОСРОЧЕН"
            rhc_fix "node-pull: sudo node-pull; журнал: journalctl -t node-pull -n 10"
        fi
        rhc_perms=$(rhc_perm "$NGINX_SSL/privkey.pem")
        [[ "$rhc_perms" == "600" ]] || { rhc_bad "privkey.pem с правами $rhc_perms"; rhc_fix "права: меню, пункт 4 (починка)"; }
    else
        rhc_bad "нет сертификата в $NGINX_SSL"
        rhc_fix "сайт: меню, пункт 2 -> 4"
    fi

    if [[ -s "$NODE_PULL_DIR/key" && -s "$NODE_PULL_DIR/known_hosts" && -x "$NODE_PULL_BIN" ]]; then
        rhc_ok "node-pull настроен (ключ ноды и ключ панели на месте)"
        if systemctl is-enabled --quiet node-pull.timer 2>/dev/null; then
            rhc_ok "таймер node-pull включён"
        else
            rhc_bad "таймер node-pull.timer не включён — сертификат не будет обновляться"
            rhc_fix "node-pull: меню, пункт 4 (починка)"
        fi
        local rhc_last
        rhc_last=$(journalctl -t node-pull -n 1 --no-pager -o cat 2>/dev/null | tail -1)
        [[ -n "$rhc_last" ]] && rhc_info "последний забор: $rhc_last"
        grep -q '^ОШИБКА' <<< "$rhc_last" && rhc_warn "последний забор с панели закончился ошибкой"
        if [[ -n "$rhc_deep" ]]; then
            local rhc_pp rhc_pport
            rhc_pp=$(grep -m1 '^PANEL=' "$NODE_PULL_BIN" | cut -d= -f2)
            rhc_pport=$(grep -m1 '^PORT=' "$NODE_PULL_BIN" | cut -d= -f2)
            rhc_info "проверяю, пускает ли панель $rhc_pp ключ этой ноды..."
            if ssh -p "${rhc_pport:-8422}" -i "$NODE_PULL_DIR/key" -o IdentitiesOnly=yes -o BatchMode=yes \
                   -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$NODE_PULL_DIR/known_hosts" \
                   -o ConnectTimeout=15 -o LogLevel=ERROR "$NODE_PULL_USER@$rhc_pp" 2>/dev/null | head -c 2 | grep -q .; then
                rhc_ok "панель отдаёт набор этой ноде"
            else
                rhc_bad "панель НЕ отдаёт набор: нет строки ключа на панели, сменился IP или ключ панели"
                rhc_fix "node-pull: меню, пункт 2 -> 22 (строка для панели)"
            fi
        fi
    else
        rhc_bad "node-pull не настроен — сертификат и сайт с панели не приходят"
        rhc_fix "node-pull: меню, пункт 2 -> 4"
    fi

    if systemctl is-active --quiet nginx 2>/dev/null; then
        if nginx -t >/dev/null 2>&1; then
            rhc_ok "nginx работает, конфиг валиден"
        else
            rhc_bad "nginx работает, но конфиг невалиден (nginx -t)"
        fi
    else
        rhc_bad "nginx не запущен"
    fi

    local rhc_site rhc_name rhc_ours=""
    for rhc_site in "$NGINX_ENABLED"/*; do
        [[ -e "$rhc_site" ]] || continue
        rhc_name=$(basename "$rhc_site")
        if head -1 "$rhc_site" 2>/dev/null | grep -qF "$NGINX_MARK"; then
            rhc_info "сайт $rhc_name — наш"; rhc_ours=1
        elif [[ "$rhc_name" == "stub.conf" ]] || grep -q 'xhttp_backend' "$rhc_site" 2>/dev/null; then
            rhc_info "сайт $rhc_name — конфиг ноды, поставлен до установщика"; rhc_ours=1
        else
            rhc_info "сайт $rhc_name — не наш, установщик его не трогает"
        fi
    done
    if [[ -z "$rhc_ours" ]]; then
        rhc_bad "конфига сайта ноды в sites-enabled нет — self-steal/CDN отвечать не будут"
        rhc_fix "сайт: меню, пункт 2 -> 4"
    fi
    if [[ "${NODE_ROLE:-reality}" != "cdn" ]]; then
        if rhc_hasport "$SELFSTEAL_PORT"; then
            rhc_ok "self-steal: nginx слушает 127.0.0.1:$SELFSTEAL_PORT"
        else
            rhc_bad "nginx не слушает $SELFSTEAL_PORT — Reality отдаёт self-steal в пустоту"
        fi
    fi
    if [[ ! -f "$STUB_ROOT/index.html" ]]; then
        rhc_bad "нет сайта в $STUB_ROOT"
        rhc_fix "node-pull: sudo node-pull"
    fi
    local rhc_v6=""
    if ipv6_off_or_pending; then
        rhc_v6=$(nginx_ipv6_listeners | tr '\n' ' ')
        if [[ -n "$rhc_v6" ]]; then
            rhc_warn "IPv6 выключен, а listen [::] есть в: $rhc_v6— nginx может не подняться"
            rhc_fix "nginx: меню, пункт 4 (починка) удалит стоковый default; в своих сайтах уберите listen [::]"
        fi
    fi

    # ----------------------------------------------------------------------
    rhc_sect "Уведомления"
    # ----------------------------------------------------------------------
    local rhc_conns
    if [[ -f "$NOTIFY_ENV" ]]; then
        rhc_perms=$(rhc_perm "$NOTIFY_ENV")
        if [[ "$rhc_perms" == "600" ]]; then
            rhc_ok "$(basename "$NOTIFY_ENV") с правами 600"
        else
            rhc_bad "$(basename "$NOTIFY_ENV") с правами $rhc_perms — токен бота читает любой"
            rhc_fix "права: меню, пункт 4 (починка)"
        fi
        if [[ -x "$NOTIFY_BIN" ]]; then
            rhc_ok "remnawave-notify на месте"
        else
            rhc_bad "нет $NOTIFY_BIN — уведомлений нет"
            rhc_fix "уведомления: меню, пункт 4 (починка)"
        fi
        if systemctl is-active --quiet remnawave-notify-watch.service 2>/dev/null; then
            rhc_ok "сторож ноды (remnawave-notify-watch) работает"
        else
            rhc_bad "remnawave-notify-watch не работает — о падении ноды не узнаете"
            rhc_fix "уведомления: меню, пункт 4 (починка)"
        fi
        if grep -q 'remnawave-notify --boot' "$NOTIFY_CRON" 2>/dev/null; then
            rhc_ok "уведомление о загрузке сервера настроено"
        else
            rhc_warn "нет уведомления о загрузке сервера ($NOTIFY_CRON)"
        fi
        if grep -q 'remnawave-notify --ssh-login' /etc/pam.d/sshd 2>/dev/null; then
            rhc_ok "уведомление о входе по SSH подключено"
        else
            rhc_warn "уведомление о входе по SSH не подключено"
        fi
        rhc_conns=$(rhc_num "$(ss -H -tn state established "( sport = :$rhc_np )" 2>/dev/null | grep -c .)")
        if [[ "$rhc_conns" -gt 0 ]]; then
            rhc_ok "панель сейчас держит $rhc_conns соединений с нодой"
        else
            rhc_bad "панель НЕ подключена к этой ноде прямо сейчас"
        fi
    else
        rhc_warn "Telegram-уведомления не настроены — о падении ноды никто не сообщит"
        rhc_fix "уведомления: меню, пункт 2 -> 11"
    fi

    # ----------------------------------------------------------------------
    rhc_sect "Права на файлы с секретами"
    # ----------------------------------------------------------------------
    for rhc_f in "$INSTALL_STATE" "$SETUP_LOG" "$REPORT_FILE"; do
        [[ -f "$rhc_f" ]] || continue
        rhc_perms=$(rhc_perm "$rhc_f")
        if [[ "$rhc_perms" == "600" ]]; then
            rhc_ok "$(basename "$rhc_f"): $rhc_perms"
        else
            rhc_bad "$(basename "$rhc_f"): права $rhc_perms, внутри секреты"
            rhc_fix "права: меню, пункт 4 (починка)"
        fi
    done

    # ----------------------------------------------------------------------
    rhc_sect "Обновления"
    # ----------------------------------------------------------------------
    local rhc_sec
    if command -v unattended-upgrade >/dev/null 2>&1; then
        rhc_ok "автообновления безопасности установлены"
    else
        rhc_warn "unattended-upgrades не установлен"
        rhc_fix "автообновления: меню, пункт 2 -> 13"
    fi
    rhc_sec=$(rhc_num "$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst.*security')")
    if [[ "$rhc_sec" -gt 0 ]]; then
        rhc_warn "ждут установки обновлений безопасности: $rhc_sec"
    else
        rhc_ok "обновления безопасности установлены"
    fi

    # ----------------------------------------------------------------------
    if [[ "$rhc_problems" -eq 0 && "$rhc_warnings" -eq 0 ]]; then
        ui_title "Проблем не найдено"
    else
        ui_title "Проблем: $rhc_problems, предупреждений: $rhc_warnings"
    fi
    if [[ ${#rhc_fixes[@]} -gt 0 ]]; then
        ui_section "Что чинить, по убыванию важности"
        local f
        for f in "${rhc_fixes[@]}"; do printf '  %s%s%s  %s\n' "$C_ACC" "$S_DOT" "$C_R" "$f"; done
        echo
        ui_info "полную установку заново запускать не нужно: она сбрасывает ufw,"
        ui_info "пересоздаёт контейнер и уходит в перезагрузку. Лечите точечно."
    fi

    [[ "$rhc_problems" -eq 0 ]] && return 0
    return 1
}
