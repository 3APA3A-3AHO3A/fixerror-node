# ##########################################################################
#  ЗОНДЫ
#  Проверки состояния сервера, которые ТОЛЬКО ЧИТАЮТ. Общие для установщика и
#  диагностики: check.sh собирается и из этого модуля, и тест следит, чтобы
#  сюда не просочилось ничего пишущего.
# ##########################################################################

# IPv6 выключен: стека нет в ядре или его выключает наш sysctl-шаблон.
ipv6_off_or_pending() {
    [[ ! -d "$RH_IPV6_PROC" ]] && return 0
    grep -qE '^[[:space:]]*net\.ipv6\.conf\.all\.disable_ipv6[[:space:]]*=[[:space:]]*1' "$SYSCTL_FILE" 2>/dev/null && return 0
    return 1
}

# Включённые сайты nginx, которые слушают [::]. Без IPv6 такой сайт может не
# подняться — стоковый default установщик поэтому удаляет.
nginx_ipv6_listeners() {
    local f
    for f in "$NGINX_ENABLED"/*; do
        [[ -e "$f" ]] || continue
        grep -qE '^[[:space:]]*listen[[:space:]]+\[::\]' "$f" 2>/dev/null && basename "$f"
    done
    return 0
}

# Основной интерфейс — тот, через который идёт маршрут по умолчанию
default_iface() {
    ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
    return 0
}

# Строки правил против торрентов в before.rules ufw (сколько их там)
torrent_rules_count() {
    local n
    n=$(grep -c -- '--algo bm --from 0 --to 300 --string' "$UFW_BEFORE" 2>/dev/null)
    echo "${n:-0}"
    return 0
}
