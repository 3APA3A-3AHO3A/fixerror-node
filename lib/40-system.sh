# ##########################################################################
#  СИСТЕМА
#  Базовая подготовка: swap, пакеты, ядро, диск, автообновления
# ##########################################################################

comp_swap() {
    if [ -n "$(swapon --show)" ]; then
        echo ">>> Swap уже есть, пропускаем."
        return 0
    fi
    echo ">>> Создание Swap 2GB..."
    # Раньше команды шли через ';' и запись в fstab добавлялась даже при провале —
    # получался мёртвый swapfile.swap на каждой загрузке и зелёный шаг в сводке.
    if ! fallocate -l 2G /swapfile >>"$SETUP_LOG" 2>&1; then
        rm -f /swapfile
        if ! dd if=/dev/zero of=/swapfile bs=1M count=2048 >>"$SETUP_LOG" 2>&1; then
            echo "  [СБОЙ] не удалось создать /swapfile (нет места или ФС не поддерживает)"
            rm -f /swapfile; return 1
        fi
    fi
    chmod 600 /swapfile
    if ! mkswap /swapfile >>"$SETUP_LOG" 2>&1 || ! swapon /swapfile >>"$SETUP_LOG" 2>&1; then
        echo "  [СБОЙ] mkswap/swapon не отработали (см. $SETUP_LOG)"
        rm -f /swapfile; return 1
    fi
    # В fstab пишем только после того, как swap реально включился
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    return 0
}

# Кто держит apt/dpkg прямо сейчас. Только смотрит.
#
# Смотрим на сами файлы блокировок, а не на имена процессов. Раньше искали
# «unattended-upgrade» по командной строке — а на Ubuntu постоянно висит демон
# unattended-upgrade-shutdown, который ждёт выключения сервера и к apt в данный
# момент отношения не имеет. Поиск считал apt занятым всегда, и установка
# стояла бы по 10 минут на каждом сервере. Так и было, проверено.
RH_APT_LOCKS=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock
              /var/lib/apt/lists/lock /var/cache/apt/archives/lock)

apt_lock_pids() {
    if command -v fuser >/dev/null 2>&1; then
        # fuser печатает PID в stdout, имена файлов — в stderr
        fuser "${RH_APT_LOCKS[@]}" 2>/dev/null | tr -s ' \t' '\n' | grep -E '^[0-9]+$' | sort -u
    else
        # Без fuser — по точному имени процесса, и демон ожидания выключения
        # отсеиваем по полной командной строке
        pgrep -a -x 'apt-get|apt|dpkg|aptitude|unattended-upgr' 2>/dev/null \
            | grep -v 'unattended-upgrade-shutdown' | awk '{print $1}'
    fi
    return 0
}

rh_apt_busy() {
    [[ -n "$(apt_lock_pids)" ]] && return 0
    return 1
}

apt_busy_who() {
    local pid
    for pid in $(apt_lock_pids); do
        ps -o pid=,args= -p "$pid" 2>/dev/null | sed 's/^ *//' | cut -c1-70
    done | head -3
    return 0
}

comp_packages() {
    echo ">>> Обновление системы и установка пакетов (в фоне, лог: $SETUP_LOG)..."
    # На свежем сервере cloud-init только что запустил автообновление, и apt
    # занят. Раньше это был мгновенный сбой; теперь ждём, но говорим, чего ждём.
    local who; who=$(apt_busy_who)
    if [[ -n "$who" ]]; then
        echo "  apt сейчас занят другим процессом — подожду до 10 минут:"
        printf '    %s\n' "$who"
        echo "  Обычно это первое после загрузки автообновление, оно закончится само."
    fi
    local rc=0
    ui_step_status "Пакеты: обновляю список"
    { apt-get "${APT_WAIT[@]}" clean && apt-get "${APT_WAIT[@]}" update; } >>"$SETUP_LOG" 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then
        ui_step_status "Пакеты: обновляю систему"
        { apt-get "${APT_WAIT[@]}" -y upgrade
          apt-get "${APT_WAIT[@]}" -y dist-upgrade
          apt-get "${APT_WAIT[@]}" -y autoremove --purge; } >>"$SETUP_LOG" 2>&1 || rc=$?
    fi
    if [[ $rc -eq 0 ]]; then
        ui_step_status "Пакеты: ставлю нужное скрипту"
        apt-get "${APT_WAIT[@]}" -y install $APT_PACKAGES >>"$SETUP_LOG" 2>&1 || rc=$?
        # Стоковый сайт default уходит сразу после установки пакета. Если dpkg
        # уже успел на нём упасть (IPv6 выключен, а default слушает [::]:80) —
        # доконфигурируем и ставим недоставленное ещё раз. Две попытки: при самой
        # первой настройке пакет может заново создать ссылку на удалённый файл,
        # и вторая попытка её уберёт.
        if nginx_default_remove && [[ $rc -ne 0 ]]; then
            ui_step_status "Пакеты: чиню nginx без стокового сайта"
            echo "  dpkg упал на стоковом сайте nginx — удалил его, доустанавливаю"
            local attempt
            for attempt in 1 2; do
                rc=0
                { dpkg --configure -a && apt-get "${APT_WAIT[@]}" -y install $APT_PACKAGES; } \
                    >>"$SETUP_LOG" 2>&1 || rc=$?
                [[ $rc -eq 0 ]] && break
                nginx_default_remove >/dev/null || true
            done
        fi
    fi
    systemctl enable --now chrony >/dev/null 2>&1 || systemctl enable --now chronyd >/dev/null 2>&1 || true
    if [[ $rc -ne 0 ]]; then
        echo "  [СБОЙ] apt завершился с ошибкой (см. $SETUP_LOG)."
        who=$(apt_busy_who)
        [[ -n "$who" ]] && printf '         apt всё ещё занят: %s\n' "$who"
        return 1
    fi
    # Проверяем не «apt отработал», а что ключевое реально на месте
    # Проверяем по ИМЕНИ КОМАНДЫ, а оно не всегда совпадает с именем пакета:
    # у fail2ban исполняемый файл называется fail2ban-client.
    local miss=""
    for pkg in nginx ufw fail2ban-client jq openssl ping; do
        command -v "$pkg" >/dev/null 2>&1 || miss+=" $pkg"
    done
    if [[ -n "$miss" ]]; then
        echo "  [СБОЙ] после установки не найдены:$miss"
        return 1
    fi
    return 0
}

# Общий для всех нод шаблон ядра. Отдельной функцией — тесты проверяют текст,
# ничего не применяя. Зарезервированные порты: ядро не отдаст их исходящим
# соединениям (иначе на загруженной ноде исходящий сокет мог занять порт SSH,
# ноды или WARP, и служба не поднялась бы после перезапуска).
sysctl_render() {
    local reserved
    reserved=$(printf '%s\n' "$SSH_PORT" "$NODE_PORT" "$SELFSTEAL_PORT" "$WARP_PORT" | awk '!s[$0]++' | paste -sd, -)
    cat <<EOF
# Общий образец для нод FixError (fixerror-node)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 16384 16777216
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.ip_local_reserved_ports = $reserved
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.netfilter.nf_conntrack_max = 262144
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
fs.file-max = 1048576
vm.swappiness = 10
net.ipv4.icmp_echo_ignore_all = 1
EOF
    # Ключи ipv6 существуют, только пока стек IPv6 в ядре жив
    if [[ -d "$RH_IPV6_PROC" ]]; then
        cat <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
    fi
    return 0
}

comp_sysctl() {
    echo ">>> Тюнинг ядра (sysctl)..."
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
    modprobe tcp_bbr || true
    # Ключи nf_conntrack существуют, только пока модуль загружен. При загрузке
    # sysctl применяется раньше, чем ufw подтянет модуль, — поэтому грузим его
    # сами (modules-load срабатывает до sysctl), иначе лимит молча не встанет.
    echo "nf_conntrack" > /etc/modules-load.d/conntrack.conf
    modprobe nf_conntrack || true
    sysctl_render > "$SYSCTL_FILE"
    sysctl --system >>"$SETUP_LOG" 2>&1 || true
    # Проверяем то, ради чего всё делалось
    if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" != "bbr" ]]; then
        echo "  [СБОЙ] BBR не включился (ядро без tcp_bbr?)"
        return 1
    fi
    echo "  BBR включён, зарезервированы порты: $(sysctl -n net.ipv4.ip_local_reserved_ports 2>/dev/null)"
    return 0
}

# Время на всех серверах — UTC и синхронизировано: по нему сверяются журналы
# панели и нод, по UTC же расписаны обновления баз.
comp_time() {
    echo ">>> Время: UTC + синхронизация..."
    timedatectl set-timezone Etc/UTC >>"$SETUP_LOG" 2>&1 || ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
    systemctl enable --now chrony >>"$SETUP_LOG" 2>&1 || systemctl enable --now chronyd >>"$SETUP_LOG" 2>&1 || true
    local i
    for i in $(seq 1 10); do
        ui_step_status "Время: жду синхронизации ($i/10)"
        [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == "yes" ]] && break
        sleep 2
    done
    echo "  Часовой пояс: $(timedatectl show -p Timezone --value 2>/dev/null), синхронизация: $(timedatectl show -p NTPSynchronized --value 2>/dev/null)"
    return 0
}

# Стоковый сайт default из пакета nginx удаляем целиком, из обоих каталогов:
#  * он слушает [::]:80, и без IPv6 nginx из-за него не стартует вовсе — а dpkg
#    бросает пакет недонастроенным, и встаёт вся установка пакетов (так и было);
#  * он занимает default_server на 80 и отдаёт «Welcome to nginx» по голому IP.
#
# Проверено по пакету nginx-common: sites-available/default — его conffile, и
# удалённый conffile dpkg при обновлениях обратно не кладёт. Ссылку в
# sites-enabled пакет создаёт только при самой первой настройке, не проверяя,
# есть ли файл, — висячую ссылку тоже убираем.
# Копия — в $RH_BACKUP_DIR: вдруг default кто-то переделал под себя.
# Возвращает 0, если что-то удалил, 1 — если удалять было нечего.
nginx_default_remove() {
    local avail="$NGINX_AVAIL/default" enabled="$NGINX_ENABLED/default" stamp
    [[ -e "$avail" || -e "$enabled" || -L "$enabled" ]] || return 1
    stamp=$(date +%Y%m%d%H%M%S)
    mkdir -p "$RH_BACKUP_DIR"
    if [[ -f "$avail" ]]; then
        cp -a "$avail" "$RH_BACKUP_DIR/nginx-default.$stamp"
    fi
    # Отдельный файл (не ссылка) в sites-enabled — сохраняем и его
    if [[ -f "$enabled" && ! -L "$enabled" ]]; then
        cp -a "$enabled" "$RH_BACKUP_DIR/nginx-default-enabled.$stamp"
    fi
    rm -f "$enabled" "$avail"
    echo "  Стоковый сайт nginx default удалён (копия в $RH_BACKUP_DIR)."
    return 0
}

# daemon.json: ротация логов контейнеров и, если путь уже 1500, MTU мостов
# docker. Чужие ключи (data-root, dns, registry-mirrors) сохраняются: правим
# через jq, а не перезаписываем.
docker_daemon_json() {
    local mtu="${1:-}" tmp patch
    mkdir -p /etc/docker
    patch='{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}'
    [[ -n "$mtu" ]] && patch=$(jq -c --argjson m "$mtu" '. + {mtu: $m}' <<< "$patch")
    if [[ -f /etc/docker/daemon.json ]]; then
        if ! command -v jq >/dev/null 2>&1; then
            echo "  [СБОЙ] /etc/docker/daemon.json уже есть, а jq нет — не рискую его перезаписывать"
            return 1
        fi
        tmp=$(mktemp)
        if jq --argjson p "$patch" '. + $p' /etc/docker/daemon.json > "$tmp" 2>/dev/null; then
            cmp -s "$tmp" /etc/docker/daemon.json && { rm -f "$tmp"; return 0; }
            mv "$tmp" /etc/docker/daemon.json
        else
            rm -f "$tmp"
            echo "  [СБОЙ] /etc/docker/daemon.json не разбирается как JSON — не трогаю его"
            return 1
        fi
    else
        jq . <<< "$patch" > /etc/docker/daemon.json
    fi
    # Перезапуск docker перезапускает и ноду — только если docker уже работает
    if systemctl is-active --quiet docker 2>/dev/null; then
        node_planned "перезапуск docker (настройки daemon.json)"
        systemctl restart docker >>"$SETUP_LOG" 2>&1 || true
    fi
    return 0
}

comp_disk() {
    echo ">>> Защита диска: ротация логов Docker + journald..."
    docker_daemon_json "$(mtu_current_pinned)" || return 1
    mkdir -p /etc/systemd/journald.conf.d
    cat <<'EOF' > /etc/systemd/journald.conf.d/99-size.conf
[Journal]
SystemMaxUse=1G
EOF
    systemctl restart systemd-journald >>"$SETUP_LOG" 2>&1 || true
    return 0
}

# --- MTU ---------------------------------------------------------------------
# У части хостеров путь до интернета уже 1500 (туннели, PPPoE у провайдера
# хостера). Пакет в 1500 байт с флагом «не фрагментировать» там теряется, и
# крупные ответы Reality/Hysteria застревают — у клиента «всё грузится, но
# через раз». Замеряем путь пингом с DF и закрепляем найденное значение
# службой mtu-<интерфейс>; docker получает то же значение для своих мостов.

# Самый большой проходящий без фрагментации пакет до цели (MTU = payload+28).
# Двоичный поиск 1280..1500; печатает MTU или ничего, если не прошёл и 1280.
mtu_probe_target() {
    local t="$1" lo=1280 hi=1500 mid
    ping -c1 -W2 -M "do" -s $((lo-28)) "$t" >/dev/null 2>&1 || return 0
    if ping -c1 -W2 -M "do" -s $((hi-28)) "$t" >/dev/null 2>&1; then echo "$hi"; return 0; fi
    while (( hi - lo > 1 )); do
        mid=$(( (lo + hi) / 2 ))
        if ping -c1 -W2 -M "do" -s $((mid-28)) "$t" >/dev/null 2>&1; then lo=$mid; else hi=$mid; fi
    done
    echo "$lo"
    return 0
}

# Путь — по нескольким целям: берём наибольшее найденное. Одна цель может
# резать большие ICMP сама, и по ней MTU вышел бы заниженным.
mtu_measure() {
    local t v best=""
    for t in 1.1.1.1 8.8.8.8 9.9.9.9; do
        v=$(mtu_probe_target "$t")
        [[ -n "$v" ]] && { [[ -z "$best" ]] || (( v > best )); } && best="$v"
    done
    echo "$best"
    return 0
}

# MTU, закреплённый нашей службой (если она есть)
mtu_current_pinned() {
    local f
    f=$(ls /etc/systemd/system/mtu-*.service 2>/dev/null | head -1)
    [[ -n "$f" ]] || return 0
    grep -oE 'mtu [0-9]+' "$f" | awk '{print $2; exit}'
    return 0
}

mtu_unit_render() {
    local ifc="$1" mtu="$2" why="$3"
    cat <<EOF
[Unit]
Description=MTU $mtu на $ifc ($why)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ip link set dev $ifc mtu $mtu

[Install]
WantedBy=multi-user.target
EOF
    return 0
}

comp_mtu() {
    validate_mtu
    if [[ "$MTU_MODE" == "off" ]]; then
        echo "  MTU_MODE=off — MTU не трогаю."
        return 0
    fi
    local ifc mtu why cur
    ifc=$(default_iface)
    [[ -n "$ifc" ]] || { echo "  [СБОЙ] не нашёл интерфейс с маршрутом по умолчанию"; return 1; }
    cur=$(cat "/sys/class/net/$ifc/mtu" 2>/dev/null)
    if [[ "$MTU_MODE" == "auto" ]]; then
        echo ">>> Замер MTU пути через $ifc (сейчас $cur)..."
        ui_step_status "MTU: замеряю путь"
        mtu=$(mtu_measure)
        if [[ -z "$mtu" ]]; then
            echo "  Замерить не удалось (ICMP режется по пути) — MTU не трогаю."
            return 0
        fi
        why="замер пути $(date +%d.%m.%Y)"
    else
        mtu="$MTU_MODE"; why="задано вручную"
    fi
    if (( mtu >= 1500 )) && [[ "$MTU_MODE" == "auto" ]]; then
        echo "  Путь пропускает 1500 — закреплять нечего."
        return 0
    fi
    echo "  MTU $mtu на $ifc ($why)"
    local unit="/etc/systemd/system/mtu-$ifc.service"
    mtu_unit_render "$ifc" "$mtu" "$why" > "$unit"
    systemctl daemon-reload >>"$SETUP_LOG" 2>&1
    systemctl enable mtu-"$ifc".service >>"$SETUP_LOG" 2>&1 || true
    systemctl restart mtu-"$ifc".service >>"$SETUP_LOG" 2>&1 || true
    if [[ "$(cat "/sys/class/net/$ifc/mtu" 2>/dev/null)" != "$mtu" ]]; then
        echo "  [СБОЙ] MTU на $ifc не применился"
        return 1
    fi
    # docker-мосты — с тем же MTU, иначе контейнеры шлют пакеты больше пути
    if command -v jq >/dev/null 2>&1; then
        docker_daemon_json "$mtu" || return 1
    fi
    return 0
}

comp_autoupdates() {
    echo ">>> Автообновления безопасности..."
    apt-get "${APT_WAIT[@]}" install -y unattended-upgrades >>"$SETUP_LOG" 2>&1 || true
    cat <<'EOF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    cat <<'EOF' > /etc/apt/apt.conf.d/52unattended-upgrades-local
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
    systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
    if ! command -v unattended-upgrade >/dev/null 2>&1; then
        echo "  [СБОЙ] unattended-upgrades не установлен — автообновлений безопасности не будет"
        return 1
    fi
    return 0
}

comp_os_update() {
    echo ">>> Полное обновление системы (apt). Вывод — на экран."
    if apt-get "${APT_WAIT[@]}" clean && apt-get "${APT_WAIT[@]}" update \
       && apt-get "${APT_WAIT[@]}" -y upgrade && apt-get "${APT_WAIT[@]}" -y dist-upgrade \
       && apt-get "${APT_WAIT[@]}" -y autoremove --purge; then
        echo "  Обновление завершено успешно."
        notify_telegram "🧰 ОС обновлена, ухожу в перезагрузку ($(date '+%H:%M:%S'))"
        echo "  Перезагрузка через 5 секунд (Ctrl+C — отменить)..."
        sleep 5
        reboot
    else
        echo "  [СБОЙ] apt-обновление завершилось с ошибкой — перезагрузка отменена."
        return 1
    fi
}
