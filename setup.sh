#!/bin/bash
# ЭТОТ ФАЙЛ СОБРАН АВТОМАТИЧЕСКИ ИЗ lib/*.sh — НЕ РЕДАКТИРУЙТЕ ЕГО ВРУЧНУЮ.
# Правки вносятся в lib/, затем: python3 build.py
# Любое изменение здесь будет затёрто при следующей сборке.
# Собрано из: 00-header.sh, 05-ui.sh, 06-spinner.sh, 07-probes.sh, 10-helpers.sh, 20-prompts.sh, 30-state.sh, 40-system.sh, 45-preflight.sh, 50-security.sh, 60-node.sh, 62-geodata.sh, 70-web.sh, 80-notify.sh, 85-extras.sh, 86-egress.sh, 90-install.sh, 92-repair.sh, 94-check.sh, 95-menu.sh, 99-main.sh

# ===== lib/00-header.sh ================================================
# ##########################################################################
#  ЗАГОЛОВОК
#  Режимы оболочки, обработчик ошибок и все настройки по умолчанию
# ##########################################################################

# -e  — падать на первой же ошибке, а не идти дальше по сломанному серверу
# -E  — БЕЗ него ERR-трап не наследуется функциями, и падение внутри любой
#       функции обрывает скрипт молча, без единой строки объяснения.
#       Именно поэтому обрыв на Telegram-шаге выглядел как «просто вышел».
set -eE

# Подробный разбор падения: без имени команды такие ошибки ищутся вслепую.
# Классический пример — функция, которая заканчивается проверкой [[ ... ]]:
# при несовпадении она возвращает 1, и set -e молча убивает весь скрипт.
rh_on_error() {
    local code="$1" line="$2"; shift 2
    local cmd="$*"
    {
        echo
        echo "=========================================="
        echo "  ОШИБКА — установка прервана"
        echo "=========================================="
        echo "  команда:      $cmd"
        [[ -n "${FUNCNAME[1]:-}" ]] && echo "  в функции:    ${FUNCNAME[1]}()"
        echo "  строка:       $line"
        echo "  код возврата: $code"
        echo "  полный лог:   ${SETUP_LOG:-(лог ещё не создан)}"
        echo "=========================================="
    } >&2
    exit 1
}
trap 'rh_on_error $? $LINENO "$BASH_COMMAND"' ERR

# === НАСТРОЙКИ ===
REPO_RAW="https://raw.githubusercontent.com/3APA3A-3AHO3A/fixerror-node/main"
# Откуда скачивать сам установщик. Нужен, когда он запущен через bash <(curl ...):
# такой «файл» — временный канал, и перезапустить себя внутри tmux по нему нельзя.
SETUP_URL="$REPO_RAW/setup.sh"
# Ответы установки и копии того, что скрипт заменяет
INSTALL_STATE="/etc/fixerror-node/install.conf"
RH_BACKUP_DIR="/etc/fixerror-node/backup"
# Уведомления: один скрипт на панели и нодах (remnawave-notify) и его настройки
NOTIFY_ENV="/etc/remnawave-notify.env"
NOTIFY_BIN="/usr/local/sbin/remnawave-notify"
NOTIFY_WATCH_UNIT="/etc/systemd/system/remnawave-notify-watch.service"
NOTIFY_CRON="/etc/cron.d/remnawave-notify"
SETUP_LOG="/var/log/node-setup.log"
REPORT_FILE="/root/node-install-report.txt"
SSH_PORT="${SSH_PORT:-8422}"
ADMIN_USER="${ADMIN_USER:-vadim}"
# Каталоги nginx — переменными, чтобы тесты могли подставить временное дерево
NGINX_AVAIL="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
# Признак живого стека IPv6 (переменной — для тестов)
RH_IPV6_PROC="/proc/sys/net/ipv6"
# Метка «этот файл писал установщик». По ней он отличает свой конфиг nginx от
# чужого сайта: чужой не перезаписывается без копии.
NGINX_MARK="# fixerror-node: конфиг ноды, перезаписывается установщиком"
# Наш дроп-ин с харденингом SSH. Имя 00-: читается первым и побеждает
# (sshd берёт первое встреченное значение). Переменной — для тестов.
SSH_HARDEN_FILE="/etc/ssh/sshd_config.d/00-hardening.conf"
SSHD_MAIN="/etc/ssh/sshd_config"
UFW_BEFORE="/etc/ufw/before.rules"
NODE_PORT="2222"        # порт, на который к ноде ходит панель
WARP_PORT="6000"        # локальный прокси-порт Cloudflare WARP
SELFSTEAL_PORT="9443"   # nginx для Reality self-steal (127.0.0.1, PROXY protocol)
PSIPHON_PORT="1080"     # SOCKS5 Psiphon (vps-psiphon), им пользуется Xray ноды
# Сторонние установщики выходов — прямо из их репозиториев на GitHub
WARP_NATIVE_URL="https://raw.githubusercontent.com/distillium/warp-native/main/install.sh"
PSIPHON_URL="https://raw.githubusercontent.com/Chara-Freedom/vps-psiphon/main/psiphon_install.sh"
# Geo-базы для Xray внутри ноды (Loyalsoldier): обновление раз в 3 дня
GEODATA_DIR="/opt/remnanode/geodata"
GEODATA_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
GEODATA_BIN="/usr/local/sbin/geo-update"
GEODATA_UNIT="/etc/systemd/system/geo-update.service"
GEODATA_TIMER="/etc/systemd/system/geo-update.timer"
# node-pull: нода забирает с панели wildcard-сертификат и сайт утилит
NODE_PULL_BIN="/usr/local/sbin/node-pull"
NODE_PULL_DIR="/etc/node-pull"
NODE_PULL_UNIT="/etc/systemd/system/node-pull.service"
NODE_PULL_TIMER="/etc/systemd/system/node-pull.timer"
NODE_PULL_USER="node-pull"
NODE_PULL_BUNDLE="/var/lib/node-pull/bundle.tar.gz"   # путь к набору на панели
NGINX_SSL="/etc/nginx/ssl"
STUB_ROOT="/var/www/stub"
# Сайт на Reality-нодах: имена, на которые отвечает self-steal
STUB_NAMES_DEFAULT="check.safeline24.com gateway.safeline24.com"
# CDN-нода: путь и порт XHTTP за CDN
CDN_PATH_DEFAULT="/api/v1/stream/"
CDN_XHTTP_PORT_DEFAULT="4443"
# Шаблоны, общие для всех нод
SYSCTL_FILE="/etc/sysctl.d/99-vpn-tune.conf"
FAIL2BAN_JAIL="/etc/fail2ban/jail.local"
# Группа, по которой скрипт узнаёт учётки ИИ-агентов (Claude и др. через MCP)
AGENT_GROUP="fx-agents"
# apt с версии 2.0 умеет сам ждать освобождения блокировки dpkg. Без этого на
# свежем сервере установщик встречался с первым после загрузки
# unattended-upgrades, падал на первой же команде — и за ним рушилось всё,
# что зависит от пакетов: нода, nginx, fail2ban, docker.
# confdef/confold: если файл настроек пакета менялся (sshd_config, например),
# dpkg не спрашивает «чей оставить», а оставляет наш. Без этого обновление
# без терминала падало на вопросе, на который некому ответить.
APT_WAIT=(-o DPkg::Lock::Timeout=600
          -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
# Пакеты из apt — один список на установку и на отчёт о версиях
APT_PACKAGES="sudo curl wget unzip git tmux cron ufw fail2ban python3-systemd socat jq nginx openssl dnsutils chrony iproute2 iputils-ping iperf3 btop ncdu"
# =================

# RH_LIB_ONLY=1 — загрузить только функции, ничего не выполняя (используется тестами)
if [[ -z "${RH_LIB_ONLY:-}" && "$EUID" -ne 0 ]]; then
    # Подсказываем рабочую команду: "sudo bash <(curl ...)" НЕ работает, потому
    # что sudo закрывает лишние файловые дескрипторы, а <(...) — это как раз он.
    echo "Нужны права root. Скрипт сам отключает вход под root, поэтому запускать так:"
    echo
    echo "  curl -fsSL https://raw.githubusercontent.com/3APA3A-3AHO3A/fixerror-node/main/setup.sh -o /tmp/setup.sh"
    echo "  sudo bash /tmp/setup.sh"
    echo
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
# Без UTF-8 локали bash считает длину строк в байтах — колонки отчёта разъезжаются
if locale -a 2>/dev/null | grep -qix 'C\.UTF-*8'; then export LC_ALL=C.UTF-8; fi

# Диагностика ничего не меняет — значит и лог прошлой установки не затирает
if [[ -z "${RH_LIB_ONLY:-}" && "${1:-}" != "--check" ]]; then
    : > "$SETUP_LOG" 2>/dev/null || SETUP_LOG="/tmp/node-setup.log"
    # В лог попадает итоговый отчёт вместе с паролем учётки — 0644 тут не годится
    chmod 600 "$SETUP_LOG" 2>/dev/null || true
fi

SUMMARY=()

# ===== lib/05-ui.sh ====================================================
# ##########################################################################
#  ОФОРМЛЕНИЕ
#  Палитра, заголовки, строки-состояния и спиннер с таймером.
#
#  Зачем отдельный модуль: до него каждый шаг печатал ANSI-коды прямо в тексте,
#  и вывод выглядел по-разному в установке, диагностике и починке. Здесь один
#  набор примитивов на всё, и он сам решает, можно ли красить.
#
#  Красим только если вывод действительно в терминал. При перенаправлении в
#  файл или в конвейер (`| tee`, `> log`) escape-последовательности превратили
#  бы лог в мусор, поэтому там все C_* пустые, а спиннер печатает одну строку.
#  Уважается общепринятая переменная NO_COLOR.
# ##########################################################################

RH_TTY=""
[[ -t 1 ]] && RH_TTY=1

# UTF-8 нужен для рамок и кадров спиннера. Без него — ASCII, но всё читается.
RH_UTF=""
case "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" in *[Uu][Tt][Ff]*) RH_UTF=1 ;; esac

if [[ -n "$RH_TTY" && -z "${NO_COLOR:-}" && -z "${RH_NO_COLOR:-}" ]]; then
    # 256 цветов там, где они есть: приглушённые оттенки читаются лучше базовых
    if [[ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]]; then
        C_ACC=$'\033[38;5;80m'    # бирюзовый — акцент, заголовки, активный шаг
        C_OK=$'\033[38;5;78m'     # зелёный
        C_WARN=$'\033[38;5;179m'  # песочный
        C_ERR=$'\033[38;5;203m'   # коралловый
        C_DIM=$'\033[38;5;245m'   # серый — второстепенное
    else
        C_ACC=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'
        C_ERR=$'\033[31m'; C_DIM=$'\033[90m'
    fi
    C_B=$'\033[1m'; C_R=$'\033[0m'
else
    C_ACC=""; C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_B=""; C_R=""
fi

# Символы состояния и рамок
if [[ -n "$RH_UTF" ]]; then
    S_OK="✓"; S_ERR="✗"; S_WARN="!"; S_SKIP="–"; S_DOT="•"; S_H="─"
    RH_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
else
    S_OK="OK"; S_ERR="XX"; S_WARN="!!"; S_SKIP="--"; S_DOT="*"; S_H="-"
    RH_FRAMES=('|' '/' '-' '\')
fi

# Ширина: узкий терминал не растягиваем, широкий не распускаем до края
ui_width() {
    local w="${COLUMNS:-0}"
    [[ "$w" -lt 20 ]] && w=$(tput cols 2>/dev/null || echo 78)
    [[ "$w" -lt 52 ]] && w=52
    [[ "$w" -gt 76 ]] && w=76
    echo "$w"
}

# Подгонка строки под ширину колонки ПО СИМВОЛАМ.
# printf считает точность (%-42.42s) в байтах, а кириллица двухбайтовая —
# метка обрезалась по середине буквы и превращалась в «обновляю списо?».
ui_fit() {
    local s="$1" n="$2" pad
    if [[ "${#s}" -gt "$n" ]]; then
        s="${s:0:n-1}…"
    fi
    pad=$(( n - ${#s} ))
    printf '%s' "$s"
    (( pad > 0 )) && printf '%*s' "$pad" ''
    return 0
}

ui_rule() {
    local w; w=$(ui_width); local line=""
    while [[ "${#line}" -lt "$w" ]]; do line+="$S_H"; done
    printf '%s%s%s\n' "$C_DIM" "$line" "$C_R"
    return 0
}

# Шапка: заголовок между двумя линиями, с необязательным подзаголовком
ui_title() {
    echo
    ui_rule
    printf '%s%s  %s%s\n' "$C_B" "$C_ACC" "$1" "$C_R"
    [[ -n "${2:-}" ]] && printf '%s  %s%s\n' "$C_DIM" "$2" "$C_R"
    ui_rule
    return 0
}

ui_section() { printf '\n%s%s%s %s%s\n' "$C_B" "$C_ACC" "$S_DOT" "$1" "$C_R"; return 0; }

ui_ok()   { printf '  %s%s%s  %s\n' "$C_OK"   "$S_OK"   "$C_R" "$*"; return 0; }
ui_err()  { printf '  %s%s%s  %s\n' "$C_ERR"  "$S_ERR"  "$C_R" "$*"; return 0; }
ui_warn() { printf '  %s%s%s  %s\n' "$C_WARN" "$S_WARN" "$C_R" "$*"; return 0; }
ui_skip() { printf '  %s%s  %s%s\n' "$C_DIM"  "$S_SKIP" "$*" "$C_R"; return 0; }
ui_info() { printf '     %s%s%s\n' "$C_DIM" "$*" "$C_R"; return 0; }
ui_note() { printf '  %s\n' "$*"; return 0; }

# Ключ-значение ровной колонкой. Длина считается в символах, а не байтах —
# при кириллице иначе колонки разъезжаются.
ui_kv() {
    local key="$1"; shift
    local pad=$(( 22 - ${#key} )); (( pad < 1 )) && pad=1
    printf '  %s%s%s%*s%s\n' "$C_DIM" "$key" "$C_R" "$pad" "" "$*"
    return 0
}

# Печать сводки шагов. SUMMARY хранит текстовые метки «[ OK ]» / «[СБОЙ]» /
# «[проп.]» — они же уходят в файл отчёта, а на экран рисуем значками.
ui_summary() {
    local line rest
    for line in "$@"; do
        rest="${line#*]}"
        while [[ "$rest" == " "* ]]; do rest="${rest# }"; done
        case "$line" in
            '[ OK ]'*) printf '  %s%s%s  %s\n' "$C_OK"  "$S_OK"   "$C_R" "$rest" ;;
            '[СБОЙ]'*) printf '  %s%s%s  %s\n' "$C_ERR" "$S_ERR"  "$C_R" "$rest" ;;
            *)         printf '  %s%s  %s%s\n' "$C_DIM" "$S_SKIP" "$rest" "$C_R" ;;
        esac
    done
    return 0
}

# Сколько шагов упало
ui_fail_count() {
    local line n=0
    for line in "$@"; do
        [[ "$line" == '[СБОЙ]'* ]] && n=$(( n + 1 ))
    done
    echo "$n"
    return 0
}

# ===== lib/06-spinner.sh ===============================================
# ##########################################################################
#  СПИННЕР
#
#  Отдельным модулем от остального оформления по одной причине: он создаёт
#  временный файл для живой подписи, а из lib/05-ui.sh собирается ещё и
#  check.sh, который обязан не писать на диск вообще ничего. Тест это проверяет,
#  и правильный ответ на его замечание — разделить модули, а не ослабить тест.
# ##########################################################################

RH_SPIN_PID=""
RH_SPIN_LABEL=""
RH_SPIN_T0=0
# Метка живёт в файле, а не в переменной: анимация крутится в подоболочке и
# изменения переменных родителя не видит. Через файл шаг может рассказывать,
# что он делает прямо сейчас, — иначе двухминутная проверка выглядит зависанием.
RH_SPIN_FILE=""

ui_mmss() { printf '%d:%02d' $(( $1 / 60 )) $(( $1 % 60 )); return 0; }

ui_spin_start() {
    RH_SPIN_LABEL="$1"
    RH_SPIN_T0=$SECONDS
    RH_SPIN_FILE=$(mktemp 2>/dev/null || echo "")
    [[ -n "$RH_SPIN_FILE" ]] && printf '%s' "$1" > "$RH_SPIN_FILE"
    if [[ -z "$RH_TTY" ]]; then
        printf '  %s  %s\n' "$S_DOT" "$1"
        return 0
    fi
    (
        local i=0 el lbl="$RH_SPIN_LABEL"
        while :; do
            el=$(( SECONDS - RH_SPIN_T0 ))
            [[ -n "$RH_SPIN_FILE" ]] && lbl=$(cat "$RH_SPIN_FILE" 2>/dev/null || printf '%s' "$lbl")
            printf '\r\033[K  %s%s%s  %s %s%5s%s' \
                "$C_ACC" "${RH_FRAMES[i % ${#RH_FRAMES[@]}]}" "$C_R" \
                "$(ui_fit "$lbl" 42)" "$C_DIM" "$(ui_mmss "$el")" "$C_R"
            i=$(( i + 1 ))
            sleep 0.12
        done
    ) &
    RH_SPIN_PID=$!
    return 0
}

# Шаг рассказывает, чем занят сейчас. Без спиннера — тихо, чтобы не сорить
# в лог и не мешать подробному выводу в меню.
ui_step_status() {
    [[ -n "$RH_SPIN_FILE" ]] && printf '%s' "$1" > "$RH_SPIN_FILE" 2>/dev/null
    return 0
}

# ui_spin_stop <код> — снимает анимацию и печатает итог той же строкой
ui_spin_stop() {
    local rc="${1:-0}" el mark col
    el=$(( SECONDS - RH_SPIN_T0 ))
    if [[ -n "$RH_SPIN_PID" ]]; then
        kill "$RH_SPIN_PID" 2>/dev/null || true
        wait "$RH_SPIN_PID" 2>/dev/null || true
        RH_SPIN_PID=""
    fi
    [[ -n "$RH_SPIN_FILE" ]] && { rm -f "$RH_SPIN_FILE"; RH_SPIN_FILE=""; }
    if [[ "$rc" -eq 0 ]]; then mark="$S_OK"; col="$C_OK"; else mark="$S_ERR"; col="$C_ERR"; fi
    if [[ -n "$RH_TTY" ]]; then
        printf '\r\033[K  %s%s%s  %s %s%5s%s\n' \
            "$col" "$mark" "$C_R" "$(ui_fit "$RH_SPIN_LABEL" 42)" "$C_DIM" "$(ui_mmss "$el")" "$C_R"
    else
        printf '  %s  %s  (%s)\n' "$mark" "$RH_SPIN_LABEL" "$(ui_mmss "$el")"
    fi
    return 0
}

# ===== lib/07-probes.sh ================================================
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

# ===== lib/10-helpers.sh ===============================================
# ##########################################################################
#  ХЕЛПЕРЫ
#  Сводка шагов и печать итогового отчёта
# ##########################################################################

# Запуск шага.
#
# На экране — одна живая строка: кадр спиннера, что делается, сколько идёт.
# Весь вывод шага уходит в $SETUP_LOG: смотреть, как apt перечисляет двести
# пакетов, никому не нужно, а при сбое причина всё равно печатается сразу,
# последними строками — потому что итоговый отчёт очищает экран, и искать её
# потом в логе было бы лишним шагом.
#
# Шаг выполняется в ТЕКУЩЕЙ оболочке, в фоне только анимация. Через конвейер
# (`"$@" | tee`) шаг ушёл бы в подоболочку, и выставленные им переменные —
# пароль учётки, домен, признак применённого харденинга — не дошли бы до отчёта.
rh_step_exec() {
    local label="$1"; shift
    local out rc=0
    out=$(mktemp)
    { echo; echo "=== ШАГ: $label — $(date '+%H:%M:%S') ==="; } >>"$SETUP_LOG" 2>/dev/null || true
    ui_spin_start "$label"
    # stdin от /dev/null: если какой-то шаг всё же задаст вопрос, read получит
    # конец ввода и шаг упадёт с понятной ошибкой. Иначе вопрос ушёл бы в лог,
    # а на экране крутился бы спиннер — установка «висела» бы без объяснений.
    "$@" >"$out" 2>&1 </dev/null || rc=$?
    ui_spin_stop "$rc"
    cat "$out" >>"$SETUP_LOG" 2>/dev/null || true
    if [[ "$rc" -ne 0 ]]; then
        grep -v '^[[:space:]]*$' "$out" 2>/dev/null | tail -12 \
            | sed "s/^/   ${C_DIM}/; s/\$/${C_R}/"
        SUMMARY+=("[СБОЙ]    $label  (см. $SETUP_LOG)")
    else
        SUMMARY+=("[ OK ]    $label")
    fi
    rm -f "$out"
    return "$rc"
}

# do_step "Метка" функция...  — обычный шаг: сбой не роняет установку
do_step() {
    rh_step_exec "$@" || true
    return 0
}

# Шаг, без которого остальное бессмысленно: установка на нём останавливается,
# а не плодит ещё шесть сбоев по одной и той же причине.
do_step_required() {
    rh_step_exec "$@"
}

skip_step() { SUMMARY+=("[проп.]   $1"); }

# Строка отчёта ровной колонкой. Длина метки считается в символах, а не в
# байтах: при кириллице иначе колонки разъезжаются.
row() { ui_kv "$@"; }

# Версии всего, что поставили: пакеты apt + то, что ставится мимо apt
collect_versions() {
    local p v
    for p in $APT_PACKAGES; do
        v=$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null || true)
        row "$p" "${v:-НЕ УСТАНОВЛЕН}"
    done
    if command -v docker >/dev/null 2>&1; then
        row "docker" "$(docker --version 2>/dev/null | sed 's/^Docker version //' || echo '?')"
        row "docker compose" "$(docker compose version --short 2>/dev/null || echo '?')"
    else
        row "docker" "НЕ УСТАНОВЛЕН"
    fi
    if command -v speedtest >/dev/null 2>&1; then
        row "speedtest" "$(speedtest --version 2>/dev/null | head -1 || echo '?')"
    fi
    if command -v warp-cli >/dev/null 2>&1; then
        row "warp-cli" "$(warp-cli --version 2>/dev/null | head -1 || echo '?')"
    fi
    return 0
}

# Финальный отчёт.
#
# Экран чистим ТОЛЬКО когда всё прошло: при сбоях на нём остались объяснения
# упавших шагов, и стирать их — значит отправить человека искать причину в логе
# ради того, чтобы отчёт выглядел опрятнее.
print_summary() {
    local out node_state fails elapsed
    node_state=$(docker inspect -f '{{.State.Status}} (перезапусков {{.RestartCount}})' remnanode 2>/dev/null | head -1 | tr -d '\r\n')
    [[ -z "$node_state" ]] && node_state="контейнер не найден"
    fails=$(ui_fail_count "${SUMMARY[@]}")
    elapsed=$(ui_mmss $(( SECONDS - ${RH_T0:-0} )))

    if [[ "$fails" -eq 0 && -t 1 ]]; then clear || true; fi

    if [[ "$fails" -eq 0 ]]; then
        ui_title "Нода ${SERVER_LABEL:-$(hostname)} готова" \
                 "заняло $elapsed · $(date '+%Y-%m-%d %H:%M %Z')"
    else
        ui_title "Установка закончилась с ошибками: $fails" \
                 "заняло $elapsed · подробности выше и в $SETUP_LOG"
    fi

    # Вход — по IP: за оранжевым облаком Cloudflare домен ведёт на Cloudflare,
    # и SSH по нему не пройдёт. Отпечаток — тот, что ssh спросит при первом входе.
    local fp outb pline login_host="${SERVER_IP:-$(hostname)}"
    fp=$(hostkey_fingerprint)
    ui_section "Доступ по SSH"
    ui_kv "команда входа" "ssh -p $SSH_PORT $ADMIN_USER@$login_host"
    ui_kv "учётка" "$ADMIN_USER (sudo без пароля)"
    case "$ADMIN_PASS_SOURCE" in
        manual) ui_kv "пароль учётки" "задан вами вручную (в отчёт не пишу)" ;;
        kept)   ui_kv "пароль учётки" "не менялся — пользователь уже существовал" ;;
        *)      ui_kv "пароль учётки" "${ADMIN_PASS:-—}"
                ui_info "нужен только для аварийной консоли хостера" ;;
    esac
    ui_kv "root и пароли" "вход запрещён"
    [[ -n "$fp" ]] && ui_kv "отпечаток сервера" "$fp (ED25519)"
    if [[ -n "$SSH_PENDING_REBOOT" ]]; then
        ui_warn "порт $SSH_PORT заработает только после перезагрузки"
        ui_info "до неё заходите по старому порту — он открыт в UFW"
    elif [[ -z "$SSH_HARDENED" ]]; then
        ui_err "харденинг SSH не применился — смотрите шаги ниже"
    fi

    ui_section "Нода"
    ui_kv "имя" "${SERVER_LABEL:-—}"
    ui_kv "роль" "${NODE_ROLE:-reality}$([[ "${NODE_ROLE:-}" == cdn ]] && echo " ($CDN_DOMAIN, XHTTP $CDN_PATH -> 127.0.0.1:$CDN_XHTTP_PORT)")"
    ui_kv "IP сервера" "${SERVER_IP:-—}"
    ui_kv "контейнер" "$node_state"
    ui_kv "версия ноды" "remnawave/node:${REMNANODE_VERSION:-latest}"
    ui_kv "порт для панели" "$NODE_PORT (только с ${PANEL_IP:-—})"

    ui_section "Фаервол"
    ui_kv "открыто" "${UFW_SSH_PORTS:-$SSH_PORT/tcp} (SSH, rate limit), 80/tcp, 443/tcp, 443/udp"
    ui_kv "" "$NODE_PORT/tcp только с ${PANEL_IP:-—}"

    ui_section "Шаги"
    ui_summary "${SUMMARY[@]}"

    pline=$(node_pull_panel_line 2>/dev/null || true)
    if [[ -n "$pline" ]]; then
        if [[ -n "${NODE_PULL_PENDING:-}" ]]; then
            ui_section "Добавьте ключ ноды на панели — без него не будет сертификата и сайта"
        else
            ui_section "Строка ключа ноды на панели (уже работает)"
        fi
        ui_info "на панели, в Termius — одна команда:"
        printf "  echo '%s' | sudo tee -a /var/lib/node-pull/.ssh/authorized_keys\n" "$pline"
        ui_info "потом здесь, на ноде: sudo node-pull   (должно быть «обновлено: сертификат сайт»)"
        [[ -n "${PANEL_HOSTKEY_FP:-}" ]] && ui_kv "ключ панели" "$PANEL_HOSTKEY_FP — сверьте на панели"
    fi

    outb=$(egress_outbounds_json)
    if [[ -n "$outb" ]]; then
        ui_section "Outbound'ы Xray для профиля ноды"
        printf '%s\n' "$outb" | sed 's/^/  /'
    fi

    ui_section "Профиль для ssh-mcp (config.toml)"
    ssh_mcp_profile | sed 's/^/  /'
    ui_info "keyRef — путь к ключу агента на вашем компьютере"

    ui_section "Где что лежит"
    ui_kv "этот отчёт" "$REPORT_FILE"
    ui_kv "полный лог" "$SETUP_LOG"
    ui_kv "ответы установки" "$INSTALL_STATE"
    ui_kv "compose ноды" "/opt/remnanode/docker-compose.yml"
    [[ -f "$NOTIFY_ENV" ]] && ui_kv "telegram" "$NOTIFY_ENV"
    ui_kv "сайт ноды" "$(web_site_file)"
    ui_kv "node-pull" "$NODE_PULL_BIN, журнал: journalctl -t node-pull"
    ui_rule

    # В файл — то же самое, но без цвета и с версиями пакетов: его читают
    # глазами через неделю, когда экрана уже нет.
    out=$(
        echo "=== ОТЧЁТ ОБ УСТАНОВКЕ — $(date '+%Y-%m-%d %H:%M:%S %Z') ==="
        echo "Заняло: $elapsed, сбоев: $fails"
        echo
        echo "Вход:            ssh -p $SSH_PORT $ADMIN_USER@$login_host"
        echo "Учётка:          $ADMIN_USER (sudo без пароля)"
        case "$ADMIN_PASS_SOURCE" in
            manual) echo "Пароль учётки:   задан вами вручную" ;;
            kept)   echo "Пароль учётки:   не менялся" ;;
            *)      echo "Пароль учётки:   ${ADMIN_PASS:-—}" ;;
        esac
        echo "Нода:            ${SERVER_LABEL:-—} (${NODE_ROLE:-reality})"
        echo "IP сервера:      ${SERVER_IP:-—}"
        echo "Порт панели:     $NODE_PORT (только с ${PANEL_IP:-—})"
        echo "UFW:             ${UFW_SSH_PORTS:-$SSH_PORT/tcp}, 80/tcp, 443/tcp, 443/udp"
        [[ -n "$fp" ]] && echo "Отпечаток:       $fp (ED25519)"
        echo
        echo "--- ШАГИ ---"
        printf '%s\n' "${SUMMARY[@]}"
        if [[ -n "$pline" ]]; then
            echo
            echo "--- КЛЮЧ НОДЫ ДЛЯ ПАНЕЛИ (/var/lib/node-pull/.ssh/authorized_keys) ---"
            echo "$pline"
            [[ -n "${PANEL_HOSTKEY_FP:-}" ]] && echo "Ключ сервера панели: $PANEL_HOSTKEY_FP"
        fi
        if [[ -n "$outb" ]]; then
            echo
            echo "--- OUTBOUND'Ы XRAY ДЛЯ ПРОФИЛЯ НОДЫ ---"
            printf '%s\n' "$outb"
        fi
        echo
        echo "--- ПРОФИЛЬ ДЛЯ SSH-MCP (config.toml) ---"
        ssh_mcp_profile
        echo
        echo "--- ПАКЕТЫ И ВЕРСИИ ---"
        collect_versions
    )
    printf '%s\n' "$out" > "$REPORT_FILE" 2>/dev/null || true
    chmod 600 "$REPORT_FILE" 2>/dev/null || true
    { echo; printf '%s\n' "$out"; } >> "$SETUP_LOG" 2>&1 || true
    return 0
}

# В Ubuntu 22.10+ SSH поднимается по требованию через ssh.socket, и каталог
# /run/sshd существует, только пока служба запущена. Без него sshd -t и sshd -T
# падают с «Missing privilege separation directory», хотя конфиг в порядке, —
# и харденинг откатывался как будто из-за битого конфига. Создаём каталог так
# же, как его создаёт сама служба (RuntimeDirectory=sshd, права 755).
sshd_rundir() {
    [[ -d /run/sshd ]] || install -d -m 755 /run/sshd 2>/dev/null || true
    return 0
}

# ===== lib/20-prompts.sh ===============================================
# ##########################################################################
#  ОПРОС
#  Всё, что спрашивается у пользователя, и проверка введённого
# ##########################################################################

ask_panel_ip() {
    PANEL_IP=$(echo "${PANEL_IP:-}" | tr -d '[:space:]')
    while [[ ! "$PANEL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
        [[ -n "$NONINTERACTIVE" ]] && { echo "  [СБОЙ] PANEL_IP в конфиге не задан или некорректен"; return 1; }
        read -ep "Введите IP-адрес мастер-панели (для UFW): " PANEL_IP
        PANEL_IP=$(echo "$PANEL_IP" | tr -d '[:space:]')
        [[ "$PANEL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || echo -e "\e[31m[Ошибка]\e[0m Введите корректный IPv4."
    done
    return 0
}

ask_secret() {
    REMNA_SECRET=$(echo "${REMNA_SECRET:-}" | tr -d '[:space:]')
    while [[ -z "$REMNA_SECRET" ]]; do
        [[ -n "$NONINTERACTIVE" ]] && { echo "  [СБОЙ] REMNA_SECRET в конфиге не задан или некорректен"; return 1; }
        read -ep "Введите SECRET_KEY для Remnanode: " REMNA_SECRET
        REMNA_SECRET=$(echo "$REMNA_SECRET" | tr -d '[:space:]')
    done
    return 0
}

# --- Имя ноды ---------------------------------------------------------------
# Как ноду зовут в Telegram и в строке ключа на панели: «Finland 3 hshp».
# Нужно всегда: по этому имени строка node-pull на панели отличается от других.
validate_node_label() {
    SERVER_LABEL=$(printf '%s' "${SERVER_LABEL:-}" | tr -d '"\\`$\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [[ -n "$SERVER_LABEL" ]] && (( ${#SERVER_LABEL} <= 48 )) && return 0
    return 1
}

ask_node_label() {
    while ! validate_node_label; do
        [[ -n "$NONINTERACTIVE" ]] && { echo "  [СБОЙ] SERVER_LABEL в конфиге не задан (или длиннее 48 символов)"; return 1; }
        read -ep "Имя ноды для Telegram и панели (например, Finland 3 hshp): " SERVER_LABEL
    done
    return 0
}

# --- Роль ноды ---------------------------------------------------------------
# reality — обычная нода: Xray на 443, self-steal на сайт утилит (stub.conf).
# cdn     — origin за CDN: nginx на 443 отдаёт сайт и проксирует XHTTP в Xray.
validate_role() {
    NODE_ROLE=$(printf '%s' "${NODE_ROLE:-}" | tr -d '[:space:]' | tr 'A-Z' 'a-z')
    [[ -z "$NODE_ROLE" ]] && NODE_ROLE="reality"
    [[ "$NODE_ROLE" == "reality" || "$NODE_ROLE" == "cdn" ]] || return 1
    STUB_NAMES=$(printf '%s' "${STUB_NAMES:-$STUB_NAMES_DEFAULT}" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
    [[ "$STUB_NAMES" =~ ^[a-zA-Z0-9.\ -]+$ ]] || return 1
    CDN_PATH="${CDN_PATH:-$CDN_PATH_DEFAULT}"
    CDN_XHTTP_PORT="${CDN_XHTTP_PORT:-$CDN_XHTTP_PORT_DEFAULT}"
    if [[ "$NODE_ROLE" == "cdn" ]]; then
        CDN_DOMAIN=$(printf '%s' "${CDN_DOMAIN:-}" | tr -d '[:space:]')
        [[ "$CDN_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || return 1
        [[ "$CDN_PATH" =~ ^/[A-Za-z0-9/_.-]*/$ ]] || return 1
        [[ "$CDN_XHTTP_PORT" =~ ^[0-9]+$ ]] && (( CDN_XHTTP_PORT > 0 && CDN_XHTTP_PORT < 65536 )) || return 1
    fi
    return 0
}

ask_role() {
    if [[ -n "$NONINTERACTIVE" ]]; then
        validate_role && return 0
        echo "  [СБОЙ] NODE_ROLE должен быть reality или cdn; для cdn нужны CDN_DOMAIN, CDN_PATH (/…/), CDN_XHTTP_PORT"
        return 1
    fi
    local r
    if [[ -z "${ROLE_ASKED:-}" ]]; then
        echo "  reality — обычная нода (Xray на 443, сайт утилит через self-steal)"
        echo "  cdn     — origin за CDN (nginx на 443: сайт + XHTTP в Xray)"
        read -ep "Роль ноды [${NODE_ROLE:-reality}]: " r || r=""
        r=$(echo "$r" | tr -d '[:space:]')
        [[ -n "$r" ]] && NODE_ROLE="$r"
    fi
    validate_role || true
    if [[ "$NODE_ROLE" == "cdn" ]]; then
        while ! validate_role; do
            read -ep "Домен origin за CDN (например, origin.safeline24.com) [${CDN_DOMAIN:-}]: " r || r=""
            r=$(echo "$r" | tr -d '[:space:]'); [[ -n "$r" ]] && CDN_DOMAIN="$r"
            read -ep "Путь XHTTP [${CDN_PATH}]: " r || r=""
            r=$(echo "$r" | tr -d '[:space:]'); [[ -n "$r" ]] && CDN_PATH="$r"
            read -ep "Порт XHTTP в Xray (127.0.0.1) [${CDN_XHTTP_PORT}]: " r || r=""
            r=$(echo "$r" | tr -d '[:space:]'); [[ -n "$r" ]] && CDN_XHTTP_PORT="$r"
            validate_role || echo -e "\e[31m[Ошибка]\e[0m Домен вида origin.example.com, путь вида /api/v1/stream/, порт 1–65535."
        done
    elif [[ "$NODE_ROLE" != "reality" ]]; then
        echo "  Неизвестная роль «$NODE_ROLE» — ставлю reality."
        NODE_ROLE="reality"
    fi
    ROLE_ASKED=1
    return 0
}

# --- MTU ---------------------------------------------------------------------
# auto — замерить путь и закрепить, если меньше 1500; число — закрепить его;
# off — не трогать. Вопрос не задаётся: значение берётся из файла ответов.
validate_mtu() {
    MTU_MODE=$(printf '%s' "${MTU_MODE:-auto}" | tr -d '[:space:]' | tr 'A-Z' 'a-z')
    if [[ "$MTU_MODE" =~ ^[0-9]+$ ]]; then
        (( MTU_MODE >= 1280 && MTU_MODE <= 1500 )) && return 0
        echo "  [ВНИМАНИЕ] MTU_MODE=$MTU_MODE вне 1280–1500 — замеряю сам."
        MTU_MODE="auto"
    fi
    [[ "$MTU_MODE" == "auto" || "$MTU_MODE" == "off" ]] || MTU_MODE="auto"
    return 0
}

# Проверяет, что строка — действительно публичный SSH-ключ.
# Без этой проверки опечатка или обрезанный при копировании ключ приводит к тому,
# что скрипт отключает вход по паролю и запирает сервер: ключ-то "непустой".
ssh_key_valid() {
    local key="$1"
    [[ -z "$key" ]] && return 1
    command -v ssh-keygen >/dev/null 2>&1 || return 0   # нечем проверить — не мешаем
    local tmp; tmp=$(mktemp)
    printf '%s\n' "$key" > "$tmp"
    if ssh-keygen -l -f "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"; return 0
    fi
    rm -f "$tmp"; return 1
}

ask_ssh_key() {
    while ! ssh_key_valid "$SSH_PUBLIC_KEY"; do
        if [[ -n "$SSH_PUBLIC_KEY" ]]; then
            echo -e "\e[31m[Ошибка]\e[0m Это не похоже на публичный SSH-ключ."
            echo "  Нужна одна строка целиком, например: ssh-ed25519 AAAAC3Nza... you@host"
            SSH_PUBLIC_KEY=""
        fi
        [[ -n "$NONINTERACTIVE" ]] && { echo "  [СБОЙ] SSH_PUBLIC_KEY в конфиге некорректен"; return 1; }
        read -ep "Публичный SSH-ключ (ssh-ed25519 AAA...): " SSH_PUBLIC_KEY
    done
    return 0
}

# Дополнительные ключи той же учётке: второй компьютер, коллега, Claude.
# Хранятся в SSH_EXTRA_KEYS по одному на строку. Основной ключ остаётся
# обязательным, эти — по желанию; спрашиваем, только если их ещё нет.
ask_extra_keys() {
    [[ -n "$NONINTERACTIVE" || -n "${SSH_EXTRA_KEYS:-}" ]] && return 0
    local k
    while true; do
        read -ep "Ещё один публичный ключ для этой учётки (Enter — не нужно): " k || k=""
        k=$(echo "$k" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -z "$k" ]] && break
        if ssh_key_valid "$k"; then
            SSH_EXTRA_KEYS+="${SSH_EXTRA_KEYS:+$'\n'}$k"
            echo "  Ключ добавлен."
        else
            echo -e "\e[31m[Ошибка]\e[0m Это не похоже на публичный SSH-ключ — пропускаю."
        fi
    done
    return 0
}

# --- Версия ноды ------------------------------------------------------------
# Тег образа remnawave/node: latest или конкретная версия (3.4.3). Конкретная
# нужна, когда свежая версия что-то ломает и ноду откатывают: с latest любая
# переустановка вернула бы сломанную версию обратно.
validate_node_version() {
    REMNANODE_VERSION=$(echo "${REMNANODE_VERSION:-}" | tr -d '[:space:]')
    if [[ -n "$REMNANODE_VERSION" && ! "$REMNANODE_VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "  [ВНИМАНИЕ] REMNANODE_VERSION='$REMNANODE_VERSION' — не похоже на тег образа, ставлю latest."
        REMNANODE_VERSION=""
    fi
    [[ -z "$REMNANODE_VERSION" ]] && REMNANODE_VERSION="latest"
    return 0
}

# Спрашивается при каждой интерактивной установке. Если нода уже стоит на
# закреплённой версии, она предлагается по умолчанию — чтобы Enter не отменил
# откат. На чистом сервере Enter — latest.
ask_node_version() {
    [[ -n "$NONINTERACTIVE" ]] && { validate_node_version; return 0; }
    local v def="${REMNANODE_VERSION:-latest}"
    read -ep "Версия ноды Remnawave, например 3.4.3 (Enter — $def): " v || v=""
    v=$(echo "$v" | tr -d '[:space:]')
    REMNANODE_VERSION="${v:-$def}"
    validate_node_version
    return 0
}

# --- Учётка ИИ-агента -----------------------------------------------------
# Отдельный вход для Claude и других агентов, которые ходят на сервер по MCP.
# Зачем отдельный: в уведомлении о входе видно, кто зашёл — человек или агент,
# а доступ агента можно закрыть, не трогая свою учётку.
validate_agent_params() {
    # Запасное имя не должно совпасть с админ-учёткой, если её саму назвали agent
    local fallback="claude"
    [[ "${ADMIN_USER:-}" == "claude" ]] && fallback="ai-agent"
    AGENT_USER=$(echo "${AGENT_USER:-}" | tr -d '[:space:]')
    [[ -z "$AGENT_USER" ]] && AGENT_USER="$fallback"
    if [[ ! "$AGENT_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || [[ "$AGENT_USER" == "root" ]] \
       || [[ "$AGENT_USER" == "$ADMIN_USER" ]] || (( ${#AGENT_USER} > 32 )); then
        echo "  [ВНИМАНИЕ] Некорректное AGENT_USER='$AGENT_USER' (или совпадает с админ-учёткой) — использую '$fallback'."
        AGENT_USER="$fallback"
    fi
    return 0
}

ask_agent_key() {
    [[ -n "$NONINTERACTIVE" || -n "${AGENT_SSH_KEYS:-}" ]] && return 0
    local k
    echo "  Учётка для ИИ-агентов (Claude и др. по MCP): свой ключ, sudo, в уведомлениях"
    echo "  вход подписан как вход агента. Не нужна — просто Enter."
    while true; do
        read -ep "Публичный ключ агента (Enter — не создавать): " k || k=""
        k=$(echo "$k" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -z "$k" ]] && break
        if ssh_key_valid "$k"; then
            AGENT_SSH_KEYS="$k"
            read -ep "Имя учётки агента [${AGENT_USER:-claude}]: " k || k=""
            k=$(echo "$k" | tr -d '[:space:]')
            [[ -n "$k" ]] && AGENT_USER="$k"
            validate_agent_params
            break
        fi
        echo -e "\e[31m[Ошибка]\e[0m Это не похоже на публичный SSH-ключ."
    done
    return 0
}

# --- Имя админ-учётки и порт SSH -------------------------------------------
# Проверка значений, пришедших из окружения/конфига (неинтерактивный режим).
validate_ssh_params() {
    ADMIN_USER=$(echo "${ADMIN_USER:-}" | tr -d '[:space:]')
    if [[ ! "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || [[ "$ADMIN_USER" == "root" ]] || (( ${#ADMIN_USER} > 32 )); then
        [[ -n "$ADMIN_USER" ]] && echo "  [ВНИМАНИЕ] Некорректное ADMIN_USER='$ADMIN_USER' — использую 'vadim'."
        ADMIN_USER="vadim"
    fi
    SSH_PORT=$(echo "${SSH_PORT:-}" | tr -d '[:space:]')
    if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
        [[ -n "$SSH_PORT" ]] && echo "  [ВНИМАНИЕ] Некорректный SSH_PORT='$SSH_PORT' — использую 8422."
        SSH_PORT="8422"
    fi
    return 0
}

ask_admin_user() {
    local input yn
    while true; do
        read -ep "Имя администраторской учётки [$ADMIN_USER]: " input
        input=$(echo "$input" | tr -d '[:space:]')
        [[ -z "$input" ]] && break                      # Enter — оставить как есть
        if [[ ! "$input" =~ ^[a-z_][a-z0-9_-]*$ ]] || (( ${#input} > 32 )); then
            echo -e "\e[31m[Ошибка]\e[0m Строчные латинские буквы, цифры, _ и -; первым символом буква или _ (до 32 символов)."
            continue
        fi
        if [[ "$input" == "root" ]]; then
            echo -e "\e[31m[Ошибка]\e[0m root не подходит — скрипт как раз закрывает вход под root."
            continue
        fi
        if id "$input" &>/dev/null; then
            read -ep "  Пользователь '$input' в системе уже есть. Использовать его (добавлю ключ и sudo)? [y/N]: " yn
            [[ "$yn" =~ ^[Yy]$ ]] || continue
        fi
        ADMIN_USER="$input"
        break
    done
    return 0
}

ask_ssh_port() {
    local input
    while true; do
        read -ep "Порт SSH [$SSH_PORT]: " input
        input=$(echo "$input" | tr -d '[:space:]')
        [[ -z "$input" ]] && break                      # Enter — оставить как есть
        if [[ ! "$input" =~ ^[0-9]+$ ]] || (( input < 1 || input > 65535 )); then
            echo -e "\e[31m[Ошибка]\e[0m Порт — целое число от 1 до 65535."
            continue
        fi
        if [[ " 80 443 $NODE_PORT $WARP_PORT $SELFSTEAL_PORT " == *" $input "* ]]; then
            echo -e "\e[31m[Ошибка]\e[0m Порт $input уже занят: 80/443 — веб, $NODE_PORT — API ноды, $WARP_PORT — WARP, $SELFSTEAL_PORT — self-steal."
            continue
        fi
        if (( input < 1024 )) && [[ "$input" != "22" ]]; then
            echo -e "\e[33m[Внимание]\e[0m $input — системный порт (<1024), его могут занять другие сервисы."
        fi
        if [[ "$input" != "22" ]] && ss -H -ltn 2>/dev/null | awk '{print $4}' | sed 's/.*://' | grep -qx "$input"; then
            echo -e "\e[33m[Внимание]\e[0m Порт $input уже кто-то слушает. Если это не ваш sshd — SSH не поднимется."
        fi
        SSH_PORT="$input"
        break
    done
    return 0
}

ask_admin_password() {
    local p1 p2 yn
    # Если учётка уже есть, решение про пароль принимаем СЕЙЧАС, а не во время
    # установки: иначе скрипт замрёт с вопросом посреди работ.
    if id "$ADMIN_USER" &>/dev/null; then
        echo "  Пользователь $ADMIN_USER уже существует."
        read -ep "  Сменить ему пароль? [y/N]: " yn
        if [[ ! "$yn" =~ ^[Yy]$ ]]; then
            ADMIN_PASS=""; ADMIN_PASS_SOURCE="kept"
            echo "  Пароль останется прежним."
            return 0
        fi
    fi
    while true; do
        read -s -p "Пароль для учётки $ADMIN_USER (Enter — сгенерировать случайный): " p1; echo
        if [[ -z "$p1" ]]; then
            ADMIN_PASS=""; ADMIN_PASS_SOURCE="generated"
            echo "  Пароль будет сгенерирован и показан в итоговом отчёте."
            return 0
        fi
        if (( ${#p1} < 8 )); then
            echo -e "\e[31m[Ошибка]\e[0m Минимум 8 символов."
            continue
        fi
        read -s -p "Повторите пароль: " p2; echo
        if [[ "$p1" != "$p2" ]]; then
            echo -e "\e[31m[Ошибка]\e[0m Пароли не совпали, ещё раз."
            continue
        fi
        ADMIN_PASS="$p1"; ADMIN_PASS_SOURCE="manual"
        break
    done
}

# Спрашивает параметры один раз за запуск; в неинтерактиве только проверяет.
ask_ssh_params() {
    [[ -n "$SSH_PARAMS_ASKED" ]] && return 0
    if [[ -z "$NONINTERACTIVE" ]]; then
        validate_ssh_params
        echo "Enter — оставить значение, указанное в квадратных скобках."
        ask_admin_user
        ask_admin_password
        ask_ssh_port
    else
        [[ -n "$ADMIN_PASS" ]] && ADMIN_PASS_SOURCE="manual" || ADMIN_PASS_SOURCE="generated"
    fi
    validate_ssh_params
    SSH_PARAMS_ASKED=1
}

# ВАЖНО: заканчивается явным "return 0".
# Без него последняя строка ([[ -z ... ]] без совпадения) вернула бы 1,
# и вызов "[[ ... ]] && ask_telegram" убивал бы весь скрипт из-за set -e.
ask_telegram() {
    [[ -n "$TG_ASKED" || -n "$NONINTERACTIVE" ]] && return 0
    [[ -z "$TG_BOT_TOKEN" ]] && read -ep "Telegram BOT_TOKEN: " TG_BOT_TOKEN
    [[ -z "$TG_CHAT_ID" ]]   && read -ep "Telegram CHAT_ID (супергруппа: начинается с -100): " TG_CHAT_ID
    [[ -z "$TG_TOPIC_ID" ]]  && read -ep "Topic ID темы супергруппы (Enter — если без топиков): " TG_TOPIC_ID
    # Прокси нужен, если сервер не достаёт api.telegram.org напрямую (ноды в РФ).
    # Спрашиваем здесь, а не в момент установки: все вопросы должны быть заданы заранее.
    if [[ -z "$TG_PROXY" ]]; then
        echo "  Если сервер не достаёт api.telegram.org напрямую (ноды в РФ), укажите прокси."
        echo "  Формат: socks5h://127.0.0.1:10808 или http://host:port. Enter — без прокси."
        read -ep "Прокси для Telegram: " TG_PROXY
    fi
    TG_ASKED=1
    return 0
}

# ===== lib/30-state.sh =================================================
# ##########################################################################
#  СОСТОЯНИЕ
#  Сохранение ответов между запусками, IP сервера, отправка в Telegram
# ##########################################################################

get_server_ip() {
    SERVER_IP=$(curl -fs --max-time 10 https://api.ipify.org 2>/dev/null || true)
    [[ -z "$SERVER_IP" ]] && SERVER_IP=$(curl -fs --max-time 10 https://ifconfig.me 2>/dev/null || true)
    [[ -z "$SERVER_IP" ]] && SERVER_IP=$(wget -qO- --timeout=10 https://api.ipify.org 2>/dev/null || true)
    SERVER_IP=$(echo "$SERVER_IP" | tr -d '[:space:]')
    if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "  [ВНИМАНИЕ] Не удалось определить внешний IP сервера."
        SERVER_IP=""
        return 1
    fi
    return 0
}

# Значение VAR="..." из файла настроек (кавычки снимаются). Только чтение.
env_value() {
    grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- | sed 's/^"//; s/"$//'
    return 0
}

# Восстановление ответов с уже настроенной ноды.
#
# Ноды, поставленные до появления install.conf (руками или старым скриптом),
# при запуске меню спрашивали бы всё заново — и человек по памяти вводил бы
# IP панели и секрет. Одна опечатка на рабочем сервере обходится дорого.
# Поэтому вычитываем то, что уже настроено, и подставляем как значения по
# умолчанию. Только чтение: ничего не меняет.
detect_existing_setup() {
    local v

    # IP панели — из правила ufw, открывающего порт ноды
    if [[ -z "${PANEL_IP:-}" ]]; then
        PANEL_IP=$(ufw status 2>/dev/null | grep -w "$NODE_PORT" \
                   | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | head -1)
    fi
    # ...или из скрипта node-pull
    if [[ -z "${PANEL_IP:-}" && -f "$NODE_PULL_BIN" ]]; then
        PANEL_IP=$(grep -m1 -E '^PANEL=' "$NODE_PULL_BIN" | cut -d= -f2 | tr -d '"'"'"' ')
    fi

    # Версия ноды — тег образа из compose (чтобы не потерять откат на старую)
    if [[ -z "${REMNANODE_VERSION:-}" && -f /opt/remnanode/docker-compose.yml ]]; then
        v=$(grep -m1 -E '^[[:space:]]*image:[[:space:]]*remnawave/node' /opt/remnanode/docker-compose.yml 2>/dev/null \
            | sed -E 's/.*remnawave\/node:?//' | tr -d '"'"'"'" \r\n')
        REMNANODE_VERSION="${v:-latest}"
    fi

    # Секрет ноды — из compose (кавычки вокруг значения снимаем)
    if [[ -z "${REMNA_SECRET:-}" && -f /opt/remnanode/docker-compose.yml ]]; then
        REMNA_SECRET=$(grep -m1 'SECRET_KEY=' /opt/remnanode/docker-compose.yml 2>/dev/null \
                       | sed 's/.*SECRET_KEY=//' | tr -d '"'"'"'" \r\n')
    fi

    # Роль — по опубликованному сайту: stub.conf у Reality, *.conf с XHTTP у CDN
    if [[ -z "${NODE_ROLE:-}" ]]; then
        local f
        for f in "$NGINX_ENABLED"/*; do
            [[ -e "$f" ]] || continue
            if grep -q 'xhttp_backend' "$f" 2>/dev/null; then
                NODE_ROLE="cdn"
                CDN_DOMAIN=$(awk '/server_name/{gsub(/;/,""); print $2; exit}' "$f")
                v=$(grep -oE 'location[[:space:]]+/[^[:space:]]+/' "$f" | awk '$2 != "/assets/" {print $2; exit}')
                [[ -n "$v" ]] && CDN_PATH="$v"
                v=$(grep -m1 -oE 'server 127\.0\.0\.1:[0-9]+' "$f" | cut -d: -f2)
                [[ -n "$v" ]] && CDN_XHTTP_PORT="$v"
                break
            fi
            [[ "$(basename "$f")" == "stub.conf" ]] && NODE_ROLE="reality"
        done
    fi

    # Порт SSH и админ-учётка — из живой конфигурации
    if [[ -z "${SSH_PORT_DETECTED:-}" ]]; then
        # Источник истины — наш файл харденинга, а не sshd -T: чужой дроп-ин,
        # читающийся раньше, перебил бы порт, и починка закрепила бы чужое.
        # Именно через if: без файла awk вернёт 2, и set -e убьёт скрипт до меню.
        v=""
        if [[ -f "$SSH_HARDEN_FILE" ]]; then
            v=$(awk '/^[[:space:]]*Port[[:space:]]/{print $2; exit}' "$SSH_HARDEN_FILE" 2>/dev/null || true)
        fi
        [[ "$v" =~ ^[0-9]+$ ]] || v=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')
        [[ "$v" =~ ^[0-9]+$ ]] && SSH_PORT="$v"
        SSH_PORT_DETECTED=1
    fi
    if [[ -z "${ADMIN_USER_DETECTED:-}" ]]; then
        v=$(find /etc/sudoers.d -maxdepth 1 -name '90-*' -printf '%f\n' 2>/dev/null | head -1)
        v="${v#90-}"
        [[ -n "$v" ]] && id "$v" &>/dev/null && ADMIN_USER="$v"
        ADMIN_USER_DETECTED=1
    fi

    # Telegram и имя ноды — из настроек remnawave-notify
    if [[ -f "$NOTIFY_ENV" ]]; then
        local key
        for key in TG_BOT_TOKEN TG_CHAT_ID TG_TOPIC_ID TG_PROXY SERVER_LABEL; do
            [[ -n "${!key:-}" ]] && continue
            v=$(env_value "$NOTIFY_ENV" "$key")
            [[ -n "$v" ]] && printf -v "$key" '%s' "$v"
        done
        [[ -n "$TG_BOT_TOKEN" && -z "${SETUP_TG:-}" ]] && SETUP_TG="y"
    fi
    # Имя ноды — ещё и из комментария ключа node-pull
    if [[ -z "${SERVER_LABEL:-}" && -f "$NODE_PULL_DIR/key.pub" ]]; then
        SERVER_LABEL=$(awk '{ $1=""; $2=""; sub(/^  /,""); sub(/^node-pull /,""); print }' "$NODE_PULL_DIR/key.pub")
    fi

    return 0
}

# Сохранение введённых данных для будущих обновлений (chmod 600 — внутри секреты/токены)
save_state() {
    mkdir -p "$(dirname "$INSTALL_STATE")"
    # Значения экранируются через %q: файл потом читается через "source" от root,
    # и секрет вида a$(команда) иначе выполнился бы, а пароль с $ — молча испортился.
    {
        for _v in PANEL_IP PANEL_HOSTKEY REMNA_SECRET REMNANODE_VERSION SERVER_LABEL \
                  NODE_ROLE STUB_NAMES CDN_DOMAIN CDN_PATH CDN_XHTTP_PORT MTU_MODE UFW_EXTRA_PORTS \
                  SSH_PUBLIC_KEY SSH_EXTRA_KEYS SSH_PORT ADMIN_USER \
                  AGENT_USER AGENT_SSH_KEYS GEODATA INSTALL_WARP INSTALL_WARP_NATIVE \
                  INSTALL_PSIPHON PSIPHON_REGION INSTALL_SPEEDTEST SETUP_TG \
                  TG_BOT_TOKEN TG_CHAT_ID TG_TOPIC_ID TG_PROXY; do
            printf '%s=%q\n' "$_v" "${!_v-}"
        done
        unset _v
    } > "$INSTALL_STATE"
    chmod 600 "$INSTALL_STATE"
}

# Сообщение в Telegram через remnawave-notify: шапка с именем ноды, прокси и
# топик — его забота. Нет скрипта или настроек — молча ничего.
notify_telegram() {
    [[ -x "$NOTIFY_BIN" && -f "$NOTIFY_ENV" ]] || return 0
    "$NOTIFY_BIN" "$1" >/dev/null 2>&1 || true
    return 0
}

# Предупредить сторожа ноды: сейчас remnanode перезапустят намеренно —
# «нода упала» в Telegram не нужно, придёт одно спокойное сообщение.
node_planned() {
    [[ -x "$NOTIFY_BIN" ]] && docker inspect remnanode >/dev/null 2>&1 \
        && "$NOTIFY_BIN" --planned "$1" >/dev/null 2>&1
    return 0
}

# ===== lib/40-system.sh ================================================
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

# ===== lib/45-preflight.sh =============================================
# ##########################################################################
#  ПРОВЕРКИ ПЕРЕД СТАРТОМ И УСТОЙЧИВОСТЬ К ОБРЫВУ СВЯЗИ
#
#  Два разных урока, оба с живых нод.
#
#  Первый: на только что созданном сервере cloud-init ещё дорабатывает и держит
#  apt первым автообновлением. Установщик падал на первой же команде, а за ним
#  сыпалось всё, что зависит от пакетов. Лечится ожиданием, а не спешкой.
#
#  Второй: установка идёт минуты, а ssh рвётся. Если процесс висит на терминале,
#  обрыв уносит установку на середине — пакеты доставлены, нода нет, sshd уже
#  перезапущен на новом порту. Поэтому работаем внутри tmux: сессия переживает
#  обрыв, и к ней можно вернуться.
# ##########################################################################

RH_SESSION="fixerror"
RH_LOCK="/run/fixerror-node.lock"


# Ждём чужой apt. Молча ждать нельзя: человек должен понимать, почему пауза.
rh_wait_apt() {
    local max="${1:-600}" waited=0
    rh_apt_busy || return 0
    ui_spin_start "Ждём чужой apt (автообновление сервера)"
    while rh_apt_busy && [[ "$waited" -lt "$max" ]]; do
        ui_step_status "Ждём чужой apt — $(apt_busy_who | head -1 | cut -c1-40)"
        sleep 3
        waited=$(( waited + 3 ))
    done
    if rh_apt_busy; then
        ui_spin_stop 1
        ui_info "apt занят уже $(ui_mmss "$waited") — дальше пойдём с ожиданием блокировки"
        return 1
    fi
    ui_spin_stop 0
    return 0
}

# cloud-init на облачных образах сам ставит обновления при первой загрузке.
# Дождаться его — самый честный способ не драться с ним за dpkg.
rh_wait_cloud_init() {
    command -v cloud-init >/dev/null 2>&1 || return 0
    cloud-init status 2>/dev/null | grep -q 'status: done' && return 0
    ui_spin_start "Ждём cloud-init (первичная настройка сервера)"
    timeout 420 cloud-init status --wait >/dev/null 2>&1 || true
    ui_spin_stop 0
    return 0
}

# Проверки, после которых понятно, можно ли вообще начинать.
# Только читает: ничего не ставит и не правит.
rh_preflight() {
    local rc=0 v
    ui_section "Проверка сервера"

    if ! command -v apt-get >/dev/null 2>&1; then
        ui_err "нет apt-get — скрипт рассчитан на Debian/Ubuntu"
        return 1
    fi
    ui_ok "система: $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") | ядро $(uname -r)"

    # Диск. Docker с образом ноды и пакеты — это единицы гигабайт.
    v=$(df -BM --output=avail / 2>/dev/null | tail -1 | tr -cd '0-9')
    v="${v:-0}"
    if [[ "$v" -lt 2048 ]]; then
        ui_err "на / свободно ${v} МБ — этого не хватит даже на пакеты"
        rc=1
    elif [[ "$v" -lt 5120 ]]; then
        ui_warn "на / свободно ${v} МБ — впритык, образ ноды и логи могут упереться"
    else
        ui_ok "на / свободно ${v} МБ"
    fi

    v=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    v="${v:-0}"
    if [[ "$v" -lt 700 ]]; then
        ui_warn "памяти ${v} МБ — мало, но swap 2 ГБ скрипт создаст сам"
    else
        ui_ok "памяти ${v} МБ"
    fi

    if getent hosts archive.ubuntu.com >/dev/null 2>&1 \
       || getent hosts deb.debian.org >/dev/null 2>&1; then
        ui_ok "DNS и сеть отвечают"
    else
        ui_err "не резолвятся репозитории — без сети ставить нечего"
        rc=1
    fi

    if command -v sshd >/dev/null 2>&1; then
        ui_ok "sshd на месте"
    else
        ui_warn "sshd не найден — харденинг SSH будет нечего настраивать"
    fi

    # Съехавшие часы — это сертификат «ещё не действует» и отказ TLS у клиентов
    v=$(date +%Y)
    if [[ "$v" -lt 2024 ]]; then
        ui_warn "часы показывают $v год — TLS и сертификат не заработают, поправьте время"
    fi

    rh_wait_cloud_init
    rh_wait_apt 600 || true

    if [[ "$rc" -ne 0 ]]; then
        ui_note ""
        ui_err "Сервер к установке не готов — смотрите строки выше."
        return 1
    fi
    return 0
}

# ##########################################################################
#  Один запуск на сервер и жизнь после обрыва ssh
# ##########################################################################

# Второй установщик на том же сервере — это два apt, два перезапуска sshd и
# гонка за одни и те же файлы. Пускаем ровно один.
rh_take_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    # Фигурные скобки обязательны. «exec 9>файл 2>/dev/null» без них значит не
    # «открой файл, скрыв ошибку», а «отправь stderr всего скрипта в никуда
    # навсегда» — и пропадают все приглашения read (bash пишет их в stderr) и
    # аварийные сообщения. Так и было, проверено.
    { exec 9>"$RH_LOCK"; } 2>/dev/null || return 0
    if ! flock -n 9; then
        echo
        echo "  На этом сервере уже работает другой запуск установщика."
        echo "  Если он идёт в отключённой сессии — подключитесь к ней:"
        echo "      sudo tmux attach -t $RH_SESSION"
        echo "  Если это остаток от оборвавшегося запуска — проверьте: pgrep -a setup.sh"
        echo
        exit 1
    fi
    return 0
}

rh_in_multiplexer() {
    [[ -n "${TMUX:-}" || -n "${STY:-}" ]] && return 0
    return 1
}

# Перезапуск себя внутри tmux. Вопросы при этом работают как обычно — это
# тот же терминал, просто пережимающий обрыв связи.
rh_session_guard() {
    [[ -n "${RH_LIB_ONLY:-}" || -n "${RH_NO_TMUX:-}" ]] && return 0
    [[ -t 0 && -t 1 ]] || return 0
    rh_in_multiplexer && return 0
    # На «тупом» терминале tmux не запустится, а exec уже заменил бы процесс —
    # и установка не началась бы вовсе. Лучше без tmux, чем никак.
    [[ -n "${TERM:-}" && "${TERM:-}" != "dumb" ]] || return 0

    if ! command -v tmux >/dev/null 2>&1; then
        # Короткий таймаут: ждать десять минут ради tmux бессмысленно,
        # без него установка тоже пройдёт — просто менее живучей.
        ui_info "ставлю tmux, чтобы установка пережила обрыв ssh (до минуты)..."
        apt-get -o DPkg::Lock::Timeout=30 install -y tmux >/dev/null 2>&1 \
            || { apt-get -o DPkg::Lock::Timeout=30 update -qq >/dev/null 2>&1 \
                 && apt-get -o DPkg::Lock::Timeout=30 install -y tmux >/dev/null 2>&1; } \
            || true
    fi
    if ! command -v tmux >/dev/null 2>&1; then
        ui_warn "tmux поставить не удалось — установка не переживёт обрыв ssh"
        ui_info "не закрывайте окно до конца установки"
        return 0
    fi

    # bash <(curl ...) — «файл» здесь временный канал /dev/fd/NN. Сервер tmux
    # его не унаследует, и установка внутри tmux не стартовала вовсе (проверено
    # на сервере). Поэтому в таком случае сохраняем установщик в файл.
    local self="$0"
    if [[ ! -f "$self" ]]; then
        self="/root/fixerror-node-setup.sh"
        if ! curl -fsSL --max-time 60 "$SETUP_URL" -o "$self" 2>/dev/null || ! bash -n "$self" 2>/dev/null; then
            rm -f "$self"
            ui_warn "не смог сохранить установщик в файл — работаю без tmux"
            ui_info "не закрывайте окно до конца установки"
            return 0
        fi
        chmod 700 "$self"
    fi

    local cmd a
    cmd="bash $(printf '%q' "$self")"
    for a in "$@"; do cmd+=" $(printf '%q' "$a")"; done
    # После выхода скрипта окно не закрываем: иначе итоговый отчёт с паролем
    # учётки мелькнёт и исчезнет вместе с сессией.
    cmd+='; printf "\n  Готово. Enter — закрыть окно. "; read -r _'

    ui_title "Работаю внутри tmux" "если ssh оборвётся: sudo tmux attach -t $RH_SESSION"
    sleep 2
    exec tmux new-session -A -s "$RH_SESSION" "$cmd"
}

# ===== lib/50-security.sh ==============================================
# ##########################################################################
#  БЕЗОПАСНОСТЬ
#  Пользователь, харденинг SSH, фаервол, fail2ban
# ##########################################################################

# ##########################################################################
#  КОМПОНЕНТЫ  (тяжёлый вывод уходит в $SETUP_LOG, на экране — только шаги)
# ##########################################################################
comp_user() {
    if [[ -z "$SSH_PUBLIC_KEY" && -n "$NONINTERACTIVE" ]]; then
        echo "  [СБОЙ] SSH_PUBLIC_KEY не задан в конфиге"; return 1
    fi
    ask_ssh_params
    ask_ssh_key
    echo ">>> Пользователь $ADMIN_USER..."
    if ! id "$ADMIN_USER" &>/dev/null; then
        adduser --disabled-password --gecos "" "$ADMIN_USER"
        if [[ -z "$ADMIN_PASS" ]]; then
            ADMIN_PASS=$(openssl rand -base64 18); ADMIN_PASS_SOURCE="generated"
        fi
        echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
        [[ "$ADMIN_PASS_SOURCE" == "generated" ]] && \
            echo "!!! ПАРОЛЬ $ADMIN_USER@$(hostname): $ADMIN_PASS  (повторю в итоговом отчёте)"
    else
        # Согласие на смену пароля уже получено в ask_admin_password
        if [[ "$ADMIN_PASS_SOURCE" == "manual" && -n "$ADMIN_PASS" ]]; then
            echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
            echo "  Пароль пользователя $ADMIN_USER изменён."
        else
            ADMIN_PASS=""; ADMIN_PASS_SOURCE="kept"
            echo "  Пользователь $ADMIN_USER уже существует — пароль не трогаю."
        fi
    fi
    usermod -aG sudo "$ADMIN_USER"

    echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$ADMIN_USER"
    chmod 440 "/etc/sudoers.d/90-$ADMIN_USER"
    if ! visudo -c >/dev/null 2>>"$SETUP_LOG"; then
        # Битый sudoers.d ломает sudo целиком, а следом comp_ssh закроет вход под root
        echo "  [СБОЙ] sudoers не проходит проверку — убираю свой файл"
        rm -f "/etc/sudoers.d/90-$ADMIN_USER"
        return 1
    fi

    local H; H=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
    install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$H/.ssh"
    touch "$H/.ssh/authorized_keys"
    grep -qxF "$SSH_PUBLIC_KEY" "$H/.ssh/authorized_keys" || echo "$SSH_PUBLIC_KEY" >> "$H/.ssh/authorized_keys"
    chmod 600 "$H/.ssh/authorized_keys"
    chown -R "$ADMIN_USER:$ADMIN_USER" "$H/.ssh"
    # Дополнительные ключи. Кривой пропускаем с предупреждением, а не роняем
    # установку: вход уже обеспечен основным ключом.
    [[ -n "${SSH_EXTRA_KEYS:-}" ]] && { add_keys_to_user "$ADMIN_USER" "$SSH_EXTRA_KEYS" || true; }

    [[ -s "$H/.ssh/authorized_keys" ]] || { echo "  [СБОЙ] authorized_keys пуст"; return 1; }
    echo "Пользователь готов."
}

# Порты, на которых СЕЙЧАС слушает именно sshd (а не кто попало).
# ss -ltnp показывает процесс; при socket-активации слушателем выступает systemd,
# поэтому его тоже засчитываем — иначе решим, что SSH мёртв, и зря откатимся.
current_sshd_ports() {
    ss -H -ltnp 2>/dev/null \
        | grep -E 'users:\(\("(sshd|systemd)"' \
        | awk '{print $4}' | sed 's/.*://' | sort -un
    return 0
}

sshd_listens_on() {
    grep -qx "$1" <<< "$(current_sshd_ports)"
}

ssh_daemon_active() {
    systemctl is-active --quiet ssh 2>/dev/null && return 0
    systemctl is-active --quiet sshd 2>/dev/null && return 0
    systemctl is-active --quiet ssh.socket 2>/dev/null && return 0
    return 1
}

# sshd применяет ПЕРВОЕ встреченное значение директивы. Если выше строки
# Include в основном sshd_config уже стоит PermitRootLogin yes (так делают
# образы некоторых хостеров), наш файл харденинга лежит ниже и проигрывает:
# порт меняется, а root и пароли остаются открытыми. Такие строки гасим.
ssh_neutralize_conflicts() {
    local inc_line conflicts n
    inc_line=$(grep -nE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' \
               /etc/ssh/sshd_config 2>/dev/null | head -1 | cut -d: -f1)
    [[ -z "$inc_line" ]] && return 0
    conflicts=$(awk -v n="$inc_line" \
        'NR<n && /^[[:space:]]*(PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication)[[:space:]]/ {print NR}' \
        "$SSHD_MAIN" 2>/dev/null)
    if [[ -n "$conflicts" ]]; then
        cp -a /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
        for n in $conflicts; do
            sed -i "${n}s|^|# отключено харденингом fixerror-node: |" /etc/ssh/sshd_config
        done
        echo "  Выше Include нашлись строки, перебивавшие харденинг — закомментированы (строки: $(echo $conflicts | tr '\n' ' '))"
    fi

    # Дроп-ины читаются по алфавиту, и тот же принцип «первое значение
    # побеждает» действует между ними. Наш файл называется 01-hardening.conf,
    # значит всё, что сортируется раньше (00-*.conf и подобное), перебивает его.
    local f base
    for f in /etc/ssh/sshd_config.d/*.conf; do
        [[ -e "$f" ]] || continue
        base=$(basename "$f")
        [[ "$base" < "$(basename "$SSH_HARDEN_FILE")" ]] || continue
        grep -qE '^[[:space:]]*(PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication)[[:space:]]' "$f" || continue
        cp -a "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
        sed -i -E 's|^([[:space:]]*(PermitRootLogin\|PasswordAuthentication\|KbdInteractiveAuthentication\|ChallengeResponseAuthentication)[[:space:]])|# отключено харденингом fixerror-node: \1|' "$f"
        echo "  $base читается раньше нашего файла и перебивал харденинг — строки закомментированы"
    done
    return 0
}

# Файл харденинга — общий образец нод FixError. Port пишем, только если его
# не задаёт основной sshd_config: Port в sshd не «первый побеждает», а
# накапливается — два одинаковых Port дают «Address already in use», и sshd
# не поднимается. Отдельной функцией, чтобы тесты проверяли текст.
ssh_harden_render() {
    echo "# Общий образец для нод FixError (fixerror-node). Файл 00- читается первым и имеет приоритет"
    if ! grep -qE "^[[:space:]]*Port[[:space:]]+${SSH_PORT}[[:space:]]*$" "$SSHD_MAIN" 2>/dev/null; then
        echo "Port $SSH_PORT"
    fi
    cat <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
EOF
    return 0
}

# Port в основном sshd_config, отличный от нашего, гасим: иначе sshd слушал бы
# и его (Port накапливается), и порт 22 оставался бы открыт для перебора.
# Тот же порт оставляем — тогда его не пишет наш файл.
ssh_main_port_fix() {
    local bad
    bad=$(grep -nE '^[[:space:]]*Port[[:space:]]+[0-9]+' "$SSHD_MAIN" 2>/dev/null \
          | grep -vE "Port[[:space:]]+${SSH_PORT}[[:space:]]*$" | cut -d: -f1)
    [[ -z "$bad" ]] && return 0
    cp -a "$SSHD_MAIN" "$SSHD_MAIN.bak.$(date +%Y%m%d%H%M%S)"
    local n
    for n in $bad; do
        sed -i "${n}s|^|# отключено харденингом fixerror-node: |" "$SSHD_MAIN"
    done
    echo "  В sshd_config был другой Port — закомментирован (бэкап рядом)."
    return 0
}

comp_ssh() {
    ask_ssh_params
    echo ">>> Харденинг SSH: порт $SSH_PORT, root закрыт..."
    local H; H=$(getent passwd "$ADMIN_USER" 2>/dev/null | cut -d: -f6)
    if [[ -z "$H" || ! -s "$H/.ssh/authorized_keys" ]]; then
        echo "  [СБОЙ] У $ADMIN_USER нет SSH-ключа — харденинг отменён, иначе потеряете доступ."
        return 1
    fi
    # Без этой строки основной sshd_config вообще не читает каталог sshd_config.d:
    # наш файл лёг бы «в стол», sshd -t прошёл бы, а порт и root остались бы прежними.
    if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_MAIN"; then
        echo "  В sshd_config нет Include для sshd_config.d — добавляю первой строкой (бэкап рядом)."
        cp -a "$SSHD_MAIN" "$SSHD_MAIN.bak.$(date +%Y%m%d%H%M%S)"
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$SSHD_MAIN"
    fi

    mkdir -p /etc/ssh/sshd_config.d
    ssh_main_port_fix
    ssh_harden_render > "$SSH_HARDEN_FILE"
    chmod 644 "$SSH_HARDEN_FILE"
    # Облачные образы включают вход по паролю своими дроп-инами. Наш файл сортируется
    # первым и всё равно выигрывает, но глушим и их — на случай нестандартных имён.
    sed -i 's/^PasswordAuthentication/#PasswordAuthentication/' \
        /etc/ssh/sshd_config.d/*cloudimg*.conf /etc/ssh/sshd_config.d/*cloud-init*.conf 2>/dev/null || true

    ssh_neutralize_conflicts

    sshd_rundir
    sshd -t || {
        echo "  [СБОЙ] sshd -t не прошёл — убираю свой файл, SSH не трогаю"
        rm -f "$SSH_HARDEN_FILE"
        return 1
    }

    # Какой порт sshd возьмёт из конфига при следующем старте (читает файлы, не демон)
    local want_port
    want_port=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)

    # Socket-активация (Ubuntu 22.10+): порт держит systemd через ssh.socket,
    # sshd его вообще не открывает, и строка Port в конфиге игнорируется.
    if systemctl cat ssh.socket >/dev/null 2>&1; then
        systemctl disable --now ssh.socket >>"$SETUP_LOG" 2>&1 || true
    fi
    systemctl enable ssh >>"$SETUP_LOG" 2>&1 || systemctl enable sshd >>"$SETUP_LOG" 2>&1 || true
    # Именно restart: "enable --now" НЕ перезапускает уже запущенный демон,
    # поэтому старый порт продолжал жить до перезагрузки.
    systemctl restart ssh >>"$SETUP_LOG" 2>&1 || systemctl restart sshd >>"$SETUP_LOG" 2>&1 || true

    # Проверяем фактом, а не надеждой. Важно: «порт кем-то занят» — это НЕ успех.
    # Если на порту сидит чужой сервис, а sshd не поднялся, старый доступ уже закрыт.
    local i ok=""
    for i in $(seq 1 10); do
        ui_step_status "SSH: жду порт $SSH_PORT ($i/10)"
        if sshd_listens_on "$SSH_PORT"; then ok=1; break; fi
        sleep 1
    done

    if [[ -n "$ok" ]] && ssh_daemon_active; then
        # Порт мог быть таким и до нас — это ничего не доказывает. Проверяем
        # то, ради чего всё затевалось: закрыты ли root и вход по паролю.
        local eff_root eff_pass
        eff_root=$(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2}')
        eff_pass=$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')
        if [[ "$eff_root" != "no" || "$eff_pass" != "no" ]]; then
            echo "  [СБОЙ] порт применился, но харденинг — нет: root=$eff_root, пароли=$eff_pass"
            echo "         кто задаёт эти значения:"
            grep -rniE '^[[:space:]]*(PermitRootLogin|PasswordAuthentication)' \
                /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null | head -5 | sed 's/^/           /'
            SSH_HARDENED=""
            return 1
        fi
        SSH_HARDENED=1; SSH_PENDING_REBOOT=""
        echo "  Проверено: sshd слушает порт $SSH_PORT, root и вход по паролю закрыты."
        return 0
    fi

    # Демон не работает вообще — это авария, откатываемся немедленно
    if ! ssh_daemon_active; then
        echo "  [СБОЙ] служба sshd не запущена после перезапуска. Откатываю харденинг."
        rm -f "$SSH_HARDEN_FILE"
        systemctl restart ssh >>"$SETUP_LOG" 2>&1 || systemctl restart sshd >>"$SETUP_LOG" 2>&1 || true
        SSH_HARDENED=""; SSH_PENDING_REBOOT=""
        return 1
    fi

    if [[ "$want_port" == "$SSH_PORT" ]] && [[ -n "$(current_sshd_ports)" ]]; then
        # Конфиг принят, но демон не перебиндился. Не откатываем — применится на ребуте,
        # а UFW ниже оставит открытым и старый порт, чтобы не потерять доступ.
        SSH_HARDENED=1; SSH_PENDING_REBOOT=1
        echo "  [ВНИМАНИЕ] sshd принял конфиг (sshd -T показывает порт $SSH_PORT), но пока слушает старый порт."
        echo "             Новый порт заработает после перезагрузки. Старый порт останется открыт в UFW."
        return 0
    fi

    echo "  [СБОЙ] sshd не видит порт $SSH_PORT в своём конфиге (sshd -T показывает '${want_port:-?}')."
    echo "         Значит файл харденинга не читается. Откатываю, чтобы не потерять доступ."
    rm -f "$SSH_HARDEN_FILE"
    systemctl restart ssh >>"$SETUP_LOG" 2>&1 || systemctl restart sshd >>"$SETUP_LOG" 2>&1 || true
    SSH_HARDENED=""; SSH_PENDING_REBOOT=""
    return 1
}

comp_ufw() {
    ask_panel_ip
    echo ">>> Настройка UFW..."
    # Открываем целевой порт + все, на которых SSH может быть прямо сейчас.
    # Иначе при отложенном применении порта фаервол запер бы нас снаружи.
    local ssh_ports p
    ssh_ports="$SSH_PORT"                                       # куда переезжаем
    for p in $(sshd -T 2>/dev/null | awk '/^port /{print $2}'); do ssh_ports+=" $p"; done
    for p in $(current_sshd_ports); do ssh_ports+=" $p"; done   # где sshd сидит прямо сейчас
    ssh_ports=$(printf '%s\n' $ssh_ports | sort -un)
    UFW_SSH_PORTS=""
    for p in $ssh_ports; do UFW_SSH_PORTS+="${UFW_SSH_PORTS:+, }$p/tcp"; done
    echo "  SSH-порты в правилах: $UFW_SSH_PORTS"

    # IPV6=no означает, что ufw вообще не трогает ip6tables: политика остаётся
    # ACCEPT и все порты открыты миру по IPv6. Отключаем фильтрацию, только если
    # стека IPv6 уже нет в ядре — иначе пусть ufw его фильтрует.
    if [[ -d /proc/sys/net/ipv6 ]]; then
        sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw
        echo "  IPv6 ещё активен — фаервол будет фильтровать и его."
    else
        sed -i 's/^IPV6=yes/IPV6=no/' /etc/default/ufw
    fi
    sed -i 's|net/ipv4/icmp_echo_ignore_all=0|net/ipv4/icmp_echo_ignore_all=1|' /etc/ufw/sysctl.conf
    # Сброс ufw возвращает before.rules к заводскому — правила против торрентов
    # вписываем после сброса и до включения.
    {
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        for p in $ssh_ports; do ufw limit "$p/tcp" comment 'SSH'; done
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
        ufw allow 443/udp comment 'QUIC / Hysteria2'
        ufw allow from "$PANEL_IP" to any port "$NODE_PORT" proto tcp comment 'API panel'
        for p in ${UFW_EXTRA_PORTS:-}; do ufw allow "$p" comment 'extra'; done
    } >>"$SETUP_LOG" 2>&1
    torrent_rules_apply || return 1
    ufw --force enable >>"$SETUP_LOG" 2>&1
    if ! ufw status 2>/dev/null | head -1 | grep -q 'active'; then
        echo "  [СБОЙ] ufw не включился (см. $SETUP_LOG)"
        return 1
    fi
    echo "  Правил против торрентов: $(torrent_rules_count)"
    return 0
}

# Блокировка торрентов: исходящие пакеты с сигнатурами BitTorrent/DHT в
# первых 300 байтах отбрасываются. В before.rules — до правила ESTABLISHED,
# иначе уже открытые соединения шли бы мимо.
TORRENT_MARK="# блокировка торрентов (fixerror-node)"
torrent_rules_render() {
    local sig
    echo "$TORRENT_MARK"
    for sig in "BitTorrent protocol" "announce_peer" "get_peers" "find_node" "info_hash=" "peer_id="; do
        printf -- '-A ufw-before-output -m string --algo bm --from 0 --to 300 --string "%s" -j DROP\n' "$sig"
    done
    return 0
}

torrent_rules_apply() {
    [[ -f "$UFW_BEFORE" ]] || { echo "  [СБОЙ] нет $UFW_BEFORE"; return 1; }
    local tmp; tmp=$(mktemp)
    # Старые строки (свои и прежних ручных правок) убираем, потом вставляем
    # блок сразу после «# End required lines» — до ESTABLISHED
    grep -v -e '--algo bm --from 0 --to 300 --string' -e '^# блокировка торрентов' "$UFW_BEFORE" \
        | awk -v blk="$(torrent_rules_render)" '
            { print }
            /^# End required lines/ && !done { print blk; done=1 }
            END { if (!done) exit 3 }' > "$tmp" || {
        rm -f "$tmp"
        echo "  [СБОЙ] в $UFW_BEFORE нет строки «# End required lines» — правила не вставлены"
        return 1
    }
    cat "$tmp" > "$UFW_BEFORE"
    rm -f "$tmp"
    return 0
}

comp_fail2ban() {
    echo ">>> Настройка fail2ban..."
    # python3-systemd нужен для backend=systemd ниже; без него джейл sshd молча не стартует
    apt-get "${APT_WAIT[@]}" install -y fail2ban python3-systemd >>"$SETUP_LOG" 2>&1 || true
    cat <<EOF > "$FAIL2BAN_JAIL"
# Общий образец для нод FixError (fixerror-node). Баны через nftables (по умолчанию в Ubuntu)
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled  = true
backend  = systemd
port     = $SSH_PORT
maxretry = 4
bantime  = 24h

[recidive]
enabled  = true
backend  = auto
logpath  = /var/log/fail2ban.log
bantime  = 1w
findtime = 1d
maxretry = 5
EOF
    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban >>"$SETUP_LOG" 2>&1
    # С backend=systemd fail2ban при старте вычитывает журнал за findtime/bantime,
    # на сервере с большим журналом это заметно дольше двух секунд.
    local i
    for i in $(seq 1 15); do
        ui_step_status "fail2ban: жду джейл sshd ($i/15)"
        if fail2ban-client status sshd >>"$SETUP_LOG" 2>&1; then
            return 0
        fi
        sleep 2
    done
    echo "  [СБОЙ] джейл sshd в fail2ban не поднялся за 30 сек (см. $SETUP_LOG)"
    return 1
}

# Добавляет в authorized_keys учётки ключи из многострочной переменной: по
# одному на строку, пустые и закомментированные строки пропускаются, кривые —
# с предупреждением. Возвращает 0, если в файле есть хотя бы один ключ.
add_keys_to_user() {
    local user="$1" keys="$2" H k
    H=$(getent passwd "$user" | cut -d: -f6)
    [[ -n "$H" ]] || return 1
    install -d -m 700 -o "$user" -g "$user" "$H/.ssh"
    touch "$H/.ssh/authorized_keys"
    while IFS= read -r k; do
        k=$(echo "$k" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -z "$k" || "$k" == \#* ]] && continue
        if ssh_key_valid "$k"; then
            grep -qxF "$k" "$H/.ssh/authorized_keys" || echo "$k" >> "$H/.ssh/authorized_keys"
        else
            echo "  [!] Строка не похожа на SSH-ключ, пропущена: ${k:0:40}..."
        fi
    done <<< "$keys"
    chmod 600 "$H/.ssh/authorized_keys"
    chown -R "$user:$user" "$H/.ssh"
    [[ -s "$H/.ssh/authorized_keys" ]] && return 0
    return 1
}

# Учётка ИИ-агента. Без пароля (вход только по ключу), sudo без пароля — агент
# ставит и чинит то же, что и человек. Узнаётся по группе $AGENT_GROUP: по ней
# уведомление о входе пишет «ИИ-агент», а не обычный вход. Файл sudoers назван
# 91-agent-*, а не 90-*: по 90-* установщик находит админ-учётку человека.
comp_agent() {
    validate_agent_params
    if [[ -z "${AGENT_SSH_KEYS:-}" ]]; then
        echo "  Ключ агента не задан (AGENT_SSH_KEYS) — учётку не создаю."
        return 0
    fi
    echo ">>> Учётка ИИ-агента $AGENT_USER..."
    getent group "$AGENT_GROUP" >/dev/null 2>&1 || groupadd "$AGENT_GROUP"
    if ! id "$AGENT_USER" &>/dev/null; then
        adduser --disabled-password --gecos "AI agent (fixerror-node)" "$AGENT_USER" >>"$SETUP_LOG" 2>&1
    fi
    usermod -aG "$AGENT_GROUP" "$AGENT_USER"
    getent group docker >/dev/null 2>&1 && usermod -aG docker "$AGENT_USER"

    local sf="/etc/sudoers.d/91-agent-$AGENT_USER"
    echo "$AGENT_USER ALL=(ALL) NOPASSWD:ALL" > "$sf"
    chmod 440 "$sf"
    if ! visudo -c >/dev/null 2>>"$SETUP_LOG"; then
        echo "  [СБОЙ] sudoers не проходит проверку — убираю файл агента"
        rm -f "$sf"
        return 1
    fi
    if ! add_keys_to_user "$AGENT_USER" "$AGENT_SSH_KEYS"; then
        echo "  [СБОЙ] у $AGENT_USER не оказалось ни одного рабочего ключа"
        return 1
    fi
    echo "  Готово: вход ssh -p $SSH_PORT $AGENT_USER@сервер, sudo без пароля."
    return 0
}

# Ключи сервера, доставшиеся от образа хостера.
#
# Пример с живого сервера: ключи RSA и DSA были подписаны root@ns31561980 —
# именем машины, на которой собирали образ. Значит, у всех серверов из этого
# образа они одинаковые, и любой такой сервер может выдать себя за ваш.
# Признак — имя хоста в подписи ключа не совпадает с именем этого сервера.
# Делается один раз за жизнь сервера (метка в /etc/fixerror-node): иначе после
# смены hostname ключи перевыпускались бы при каждом запуске.
comp_hostkeys() {
    local marker="/etc/fixerror-node/hostkeys.done" f c bad="" stamp hn
    if [[ -f "$marker" ]]; then
        echo "  Ключи сервера уже проверялись — не трогаю."
        return 0
    fi
    mkdir -p "$(dirname "$marker")"
    hn=$(hostname)
    for f in /etc/ssh/ssh_host_*_key.pub; do
        [[ -e "$f" ]] || continue
        c=$(awk '{print $3}' "$f"); c="${c#*@}"
        [[ -z "$c" || "$c" == "$hn" || "$c" == "${hn%%.*}" ]] && continue
        bad+=" $(basename "$f" .pub)(${c})"
    done
    if [[ -z "$bad" ]]; then
        echo "  Ключи сервера выпущены на этом сервере — менять не нужно."
        touch "$marker"
        return 0
    fi
    echo ">>> Ключи сервера достались от образа хостера:$bad"
    echo "    У всех серверов из этого образа они одинаковые — выпускаю свои."
    stamp=$(date +%Y%m%d%H%M%S)
    mkdir -p "$RH_BACKUP_DIR/ssh-hostkeys.$stamp"
    cp -a /etc/ssh/ssh_host_* "$RH_BACKUP_DIR/ssh-hostkeys.$stamp/"
    chmod 700 "$RH_BACKUP_DIR/ssh-hostkeys.$stamp"
    rm -f /etc/ssh/ssh_host_*
    ssh-keygen -A >>"$SETUP_LOG" 2>&1 || true
    if [[ ! -s /etc/ssh/ssh_host_ed25519_key ]]; then
        echo "  [СБОЙ] новые ключи не создались — возвращаю прежние"
        cp -a "$RH_BACKUP_DIR/ssh-hostkeys.$stamp/"ssh_host_* /etc/ssh/
        return 1
    fi
    touch "$marker"
    # Уже открытые сессии не рвутся; новые подключения видят новые ключи
    systemctl try-restart ssh >>"$SETUP_LOG" 2>&1 || true
    echo "  Готово, прежние ключи — в $RH_BACKUP_DIR/ssh-hostkeys.$stamp"
    echo "  Новые отпечатки (при первом входе ssh спросит подтверждение):"
    for f in /etc/ssh/ssh_host_*_key.pub; do
        ssh-keygen -lf "$f" 2>/dev/null | awk '{print "    " $2 "  " $NF}'
    done
    return 0
}

# Отпечаток ключа сервера ED25519 — тот, что ssh покажет при первом входе
hostkey_fingerprint() {
    ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null | awk '{print $2}'
    return 0
}

# Готовый профиль для ssh-mcp (config.toml) — входить агентом, а если учётки
# агента нет, то админ-учёткой. Хост — IP, а не домен: за оранжевым облаком
# Cloudflare домен ведёт на Cloudflare, и SSH по нему не пройдёт.
ssh_mcp_profile() {
    local user="$ADMIN_USER" fp name
    if [[ -n "${AGENT_USER:-}" ]] && id "$AGENT_USER" &>/dev/null \
       && id -nG "$AGENT_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$AGENT_GROUP"; then
        user="$AGENT_USER"
    fi
    fp=$(hostkey_fingerprint)
    name="fx-$(printf '%s' "${SERVER_LABEL:-$(hostname -s)}" | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9-')"
    cat <<EOF
[[profiles]]
name = "$name"
host = "${SERVER_IP:-IP_СЕРВЕРА}"
port = $SSH_PORT
user = "$user"
auth = "key"
keyRef = 'C:\Users\ВАШ_ПОЛЬЗОВАТЕЛЬ\.ssh\КЛЮЧ_АГЕНТА'
role = "admin"
approvalPolicy = "auto"
trustedHostKey = "${fp:-неизвестен}"
EOF
    return 0
}

# ===== lib/60-node.sh ==================================================
# ##########################################################################
#  НОДА
#  Docker и контейнер Remnanode
# ##########################################################################

# Точное совпадение порта. Раньше было grep ":$NODE_PORT" — подстрока,
# из-за неё слушатель на 22220 засчитывался за 2222 и нода считалась живой.
port_is_listening() {
    ss -H -ltn 2>/dev/null | awk '{print $4}' | sed 's/.*://' | grep -qx "$1"
}

# Без группы docker обычный пользователь получает "permission denied" на
# /var/run/docker.sock и вынужден писать sudo перед каждой командой. Прав это
# не добавляет: у админ-учётки и так sudo без пароля — только удобство.
# Вынесено отдельно, потому что на старых нодах Docker уже стоит, и раньше
# comp_docker в этом случае выходил сразу, не дойдя до usermod.
docker_group_member() {
    if [[ -z "${ADMIN_USER:-}" ]] || ! id "$ADMIN_USER" &>/dev/null; then
        return 0
    fi
    if ! getent group docker >/dev/null 2>&1; then
        echo "  Группы docker нет — пропускаю."
        return 0
    fi
    if id -nG "$ADMIN_USER" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
        echo "  $ADMIN_USER уже в группе docker."
        return 0
    fi
    usermod -aG docker "$ADMIN_USER"
    echo "  $ADMIN_USER добавлен в группу docker — подхватится в НОВОЙ сессии SSH."
    return 0
}

# Каталог ноды: 750 и группа docker. Заходить в него и смотреть geo-базы могут
# админ-учётка и агент (оба в группе docker), а сам docker-compose.yml с
# SECRET_KEY остаётся 600 — секрет защищён на уровне файла. Раньше каталог был
# 700, и даже своя учётка упиралась в Permission denied. Прав это не добавляет:
# участник группы docker и так фактически root. Владельца не трогаем — если вы
# сделали владельцем себя, так и останется.
node_dir_perms() {
    [[ -d /opt/remnanode ]] || return 0
    getent group docker >/dev/null 2>&1 && chgrp docker /opt/remnanode
    chmod 750 /opt/remnanode
    [[ -f /opt/remnanode/docker-compose.yml ]] && chmod 600 /opt/remnanode/docker-compose.yml
    return 0
}

comp_docker() {
    echo ">>> Установка Docker..."
    if command -v docker >/dev/null 2>&1; then
        echo "  Docker уже установлен."
    else
        ui_step_status "Docker: ставлю с get.docker.com"
        curl -fsSL https://get.docker.com | sh >>"$SETUP_LOG" 2>&1 || true
    fi
    # Проверяем фактом. Скрипт get.docker.com ставит пакеты через apt и при
    # занятой блокировке возвращает успех, ничего не установив: шаг светился
    # зелёным, а следом «docker: command not found» и нода не разворачивалась.
    if ! command -v docker >/dev/null 2>&1; then
        echo "  [СБОЙ] docker не установился (см. $SETUP_LOG)"
        return 1
    fi
    systemctl enable --now docker >>"$SETUP_LOG" 2>&1 || true
    if ! docker info >/dev/null 2>&1; then
        echo "  [СБОЙ] docker установлен, но демон не отвечает (см. $SETUP_LOG)"
        return 1
    fi
    docker_group_member
    local a
    for a in $(getent group "$AGENT_GROUP" 2>/dev/null | cut -d: -f4 | tr ',' ' '); do
        id -nG "$a" | tr ' ' '\n' | grep -qx docker || usermod -aG docker "$a"
    done
    return 0
}

node_status() {
    echo "----- Статус ноды -----"
    docker inspect -f 'Контейнер: {{.State.Status}} (running={{.State.Running}}, restarts={{.RestartCount}}, oom={{.State.OOMKilled}})' remnanode 2>/dev/null || echo "Контейнер remnanode не найден."
    if port_is_listening "$NODE_PORT"; then
        echo "Порт $NODE_PORT (API, к нему подключается панель): СЛУШАЕТ — связь с панелью возможна"
    else
        echo "Порт $NODE_PORT (API, к нему подключается панель): НЕ слушает — панель НЕ подключится к ноде"
    fi
    echo "----- Последние 30 строк логов -----"
    docker logs --tail=30 remnanode 2>&1 || echo "Логи недоступны."
}

comp_node() {
    ask_secret
    validate_node_version
    echo ">>> Разворачивание Remnanode..."
    mkdir -p /opt/remnanode
    cat <<EOF > /opt/remnanode/docker-compose.yml
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:$REMNANODE_VERSION
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=$NODE_PORT
      - SECRET_KEY="${REMNA_SECRET}"
EOF
    # Свои geo-базы подключаем, только если они уже скачаны: том на
    # несуществующий файл docker создал бы каталогом, и Xray не стартовал бы.
    if geodata_present; then
        cat <<EOF >> /opt/remnanode/docker-compose.yml
    volumes:
      - $GEODATA_DIR/geoip.dat:/usr/local/share/xray/geoip.dat:ro
      - $GEODATA_DIR/geosite.dat:/usr/local/share/xray/geosite.dat:ro
EOF
        echo "  Подключены geo-базы из $GEODATA_DIR"
    fi
    node_dir_perms   # compose — 600 (внутри SECRET_KEY), каталог — 750 с группой docker
    node_planned "передеплой ноды установщиком"
    if ! ( cd /opt/remnanode && docker compose up -d ) >>"$SETUP_LOG" 2>&1; then
        echo "  [СБОЙ] docker compose up не отработал (см. $SETUP_LOG)"
        node_status
        return 1
    fi
    echo "  Ожидание запуска ноды (порт $NODE_PORT, до 30 сек)..."
    local i up=""
    for i in $(seq 1 30); do
        ui_step_status "Нода: жду порт $NODE_PORT ($i/30)"
        if port_is_listening "$NODE_PORT"; then up=1; break; fi
        sleep 1
    done
    node_status
    if [[ -z "$up" ]]; then
        echo "  [СБОЙ] нода не начала слушать порт $NODE_PORT — панель её не увидит"
        return 1
    fi
    return 0
}

comp_node_update() {
    echo ">>> Обновление ноды Remnanode..."
    if [[ -f /opt/remnanode/docker-compose.yml ]]; then
        # Обновляется ровно тот тег, что записан в compose: закреплённая версия
        # так и останется, сменить её — пункт «Нода (передеплой)»
        grep -m1 -E '^[[:space:]]*image:' /opt/remnanode/docker-compose.yml | sed 's/^[[:space:]]*/  Образ: /' 
        node_planned "обновление образа ноды"
        if ! ( cd /opt/remnanode && docker compose pull && docker compose up -d ) >>"$SETUP_LOG" 2>&1; then
            echo "  [СБОЙ] обновление не прошло (см. $SETUP_LOG)"
            node_status
            notify_telegram "❌ Обновление ноды НЕ удалось ($(date '+%H:%M:%S'))"
            return 1
        fi
        node_status
        notify_telegram "⬆️ Нода обновлена: $(docker inspect -f '{{.Config.Image}}' remnanode 2>/dev/null) ($(date '+%H:%M:%S'))"
    else
        echo "  Нода не установлена (/opt/remnanode/docker-compose.yml не найден)."
        return 1
    fi
}

# ===== lib/62-geodata.sh ===============================================
# ##########################################################################
#  GEO-БАЗЫ
#  geoip.dat и geosite.dat от Loyalsoldier для Xray внутри ноды и их
#  обновление раз в 3 дня (systemd-таймер geo-update.timer)
# ##########################################################################

# Встроенные в образ ноды базы обновляются только вместе с образом. Свежие базы
# Loyalsoldier выходят каждый день; в них то, по чему маршрутизирует ядро
# (category-ru, geoip ru и т.д.). Поэтому качаем их сами и подключаем томами.

geodata_present() {
    [[ -s "$GEODATA_DIR/geoip.dat" && -s "$GEODATA_DIR/geosite.dat" ]] && return 0
    return 1
}

geodata_mounted() {
    grep -q "$GEODATA_DIR/geosite.dat" /opt/remnanode/docker-compose.yml 2>/dev/null
}

# Скрипт обновления — тот же, что на всех нодах FixError. Он же качает базы
# при установке (--no-restart): один код на оба случая. Сверяет sha256 с
# опубликованной суммой; база, не прошедшая проверку, в ноду не попадёт.
geodata_write_updater() {
    cat <<SCRIPT > "$GEODATA_BIN"
#!/bin/bash
# Обновление баз Loyalsoldier для remnanode (fixerror-node).
# Запуск: geo-update              обновить и при изменении перезапустить remnanode
#         geo-update --check      только скачать и проверить, ничего не менять
#         geo-update --no-restart обновить файлы, ноду не перезапускать (установка)
set -u
DIR=$GEODATA_DIR
URL=$GEODATA_URL
CHECK=0; NO_RESTART=0
case "\${1:-}" in --check) CHECK=1 ;; --no-restart) NO_RESTART=1 ;; esac
log(){ echo "\$*"; logger -t geo-update "\$*"; }

mkdir -p "\$DIR"
TMP=\$(mktemp -d /var/tmp/geo.XXXXXX); trap 'rm -rf "\$TMP"' EXIT
changed=0
for f in geoip.dat geosite.dat; do
  if ! curl -fsSL --retry 3 --max-time 300 -o "\$TMP/\$f" "\$URL/\$f" \\
     || ! curl -fsSL --retry 3 --max-time 60 -o "\$TMP/\$f.sha256sum" "\$URL/\$f.sha256sum"; then
    log "ОШИБКА: не удалось скачать \$f, базы не тронуты"; exit 1
  fi
  want=\$(awk '{print \$1}' "\$TMP/\$f.sha256sum"); got=\$(sha256sum "\$TMP/\$f" | awk '{print \$1}')
  if [ -z "\$want" ] || [ "\$want" != "\$got" ]; then
    log "ОШИБКА: \$f не прошёл проверку sha256, базы не тронуты"; exit 1
  fi
  if ! cmp -s "\$TMP/\$f" "\$DIR/\$f"; then
    changed=1; log "\$f: есть новая версия (\$(du -h "\$TMP/\$f" | cut -f1))"
  fi
done

[ \$CHECK -eq 1 ] && { log "проверка: скачано и проверено, изменения=\$changed, ничего не менял"; exit 0; }
[ \$changed -eq 0 ] && { log "базы не изменились, перезапуск не нужен"; exit 0; }

# Пишем поверх тех же файлов: в контейнер они подключены пофайлово,
# замена файла через mv контейнер бы не увидел
for f in geoip.dat geosite.dat; do cp "\$TMP/\$f" "\$DIR/\$f"; chmod 644 "\$DIR/\$f"; done
[ \$NO_RESTART -eq 1 ] && { log "базы обновлены, нода не перезапускалась (--no-restart)"; exit 0; }
[ -x $NOTIFY_BIN ] && $NOTIFY_BIN --planned "обновление баз Loyalsoldier"
docker restart remnanode >/dev/null
sleep 10
st=\$(docker inspect -f '{{.State.Status}}' remnanode 2>/dev/null)
log "базы обновлены, remnanode перезапущен, статус: \$st"
[ "\$st" = running ]
SCRIPT
    chmod 755 "$GEODATA_BIN"
    return 0
}

geodata_write_units() {
    cat <<'UNIT' > "$GEODATA_UNIT"
[Unit]
Description=Обновление баз Loyalsoldier для remnanode
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/geo-update
UNIT
    # Раз в 3 дня в 04:00 МСК; разброс 15 минут — чтобы ноды не ломились на
    # GitHub разом и не перезапускались одновременно
    cat <<'UNIT' > "$GEODATA_TIMER"
[Unit]
Description=Обновление баз Loyalsoldier раз в 3 дня в 04:00 МСК

[Timer]
OnCalendar=*-*-01/3 01:00:00 UTC
RandomizedDelaySec=15min
Persistent=false

[Install]
WantedBy=timers.target
UNIT
    return 0
}

comp_geodata() {
    echo ">>> Geo-базы Loyalsoldier..."
    mkdir -p "$GEODATA_DIR"
    geodata_write_updater
    if ! "$GEODATA_BIN" --no-restart; then
        echo "  [СБОЙ] не удалось скачать базы (журнал: journalctl -t geo-update)"
        geodata_present || return 1
        echo "  Прежние базы на месте — продолжаю с ними."
    fi
    geodata_present || { echo "  [СБОЙ] баз нет после скачивания"; return 1; }
    echo "  Базы на месте: $(du -ch "$GEODATA_DIR"/*.dat | tail -1 | cut -f1)"

    geodata_write_units
    systemctl daemon-reload >>"$SETUP_LOG" 2>&1
    systemctl enable --now geo-update.timer >>"$SETUP_LOG" 2>&1 || true
    if ! systemctl is-enabled --quiet geo-update.timer 2>/dev/null; then
        echo "  [СБОЙ] таймер geo-update.timer не включился"
        return 1
    fi
    echo "  Обновление: раз в 3 дня в 01:00 UTC (04:00 МСК), плюс до 15 минут"

    # Нода уже стоит, а тома в compose нет — передеплоим её с томами.
    # В полной установке не нужно: следующим шагом нода и так передеплоится.
    if [[ -z "${RH_FULL_INSTALL:-}" && -f /opt/remnanode/docker-compose.yml ]] && ! geodata_mounted; then
        echo "  Подключаю базы к уже установленной ноде..."
        comp_node || return 1
    fi
    return 0
}

# ===== lib/70-web.sh ===================================================
# ##########################################################################
#  ВЕБ
#  Сайт ноды в nginx и node-pull: wildcard-сертификат и сайт утилит
#  нода забирает с панели, своих сертификатов на ноде нет
# ##########################################################################

# Как это устроено. На панели лежит набор bundle.tar.gz: wildcard-сертификат
# и файлы сайта. У ноды свой ключ, на панели в authorized_keys пользователя
# node-pull — строка этого ключа с from="IP ноды" и command="cat набора":
# ключ умеет только забрать набор и только с адреса ноды. Таймер node-pull
# раз в 6 часов забирает набор и ставит, если что-то изменилось.
#
# Строку на панель добавляет человек: установщик печатает её готовой.

PANEL_SSH_PORT="${PANEL_SSH_PORT:-8422}"

web_site_file() {
    if [[ "${NODE_ROLE:-reality}" == "cdn" ]]; then
        echo "$NGINX_AVAIL/${CDN_DOMAIN}.conf"
    else
        echo "$NGINX_AVAIL/stub.conf"
    fi
    return 0
}

# Общий хвост: сайт утилит, как safeline24.com на панели
web_render_site_body() {
    cat <<'EOF'
    root /var/www/stub;
    index index.html;
    charset utf-8;

    add_header Content-Security-Policy "default-src 'self'; img-src 'self' data:; connect-src 'none'" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;

    error_page 404 /404.html;

    # Адреса файлов с ?v=версия — кэшируем надолго
    location /assets/ {
        add_header Cache-Control "public, max-age=31536000, immutable" always;
        add_header Content-Security-Policy "default-src 'self'; img-src 'self' data:; connect-src 'none'" always;
        add_header X-Content-Type-Options "nosniff" always;
    }

    location / {
        add_header Cache-Control "no-cache" always;
        add_header Content-Security-Policy "default-src 'self'; img-src 'self' data:; connect-src 'none'" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer" always;
        try_files $uri $uri/ =404;
    }
EOF
    return 0
}

web_render_site() {
    echo "$NGINX_MARK"
    if [[ "${NODE_ROLE:-reality}" == "cdn" ]]; then
        cat <<EOF
# $CDN_DOMAIN — origin за CDN: сайт утилит + XHTTP в Xray (127.0.0.1:$CDN_XHTTP_PORT).
# Сертификат и сайт приходят с панели: node-pull (таймер node-pull.timer).

# Пул соединений nginx -> Xray (XHTTP). Без него nginx открывает
# новое TCP-соединение к Xray на каждый запрос packet-up.
upstream xhttp_backend {
    server 127.0.0.1:$CDN_XHTTP_PORT;
    keepalive 64;
    keepalive_requests 100000;
    keepalive_timeout 60s;
}

server {
    listen 80;
    server_name $CDN_DOMAIN;
    server_tokens off;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $CDN_DOMAIN;
    server_tokens off;

    # Wildcard-сертификат с панели (node-pull)
    ssl_certificate     $NGINX_SSL/fullchain.pem;
    ssl_certificate_key $NGINX_SSL/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # Через CDN в packet-up идёт очень много запросов на одно соединение
    keepalive_requests 100000;

    # Заголовки отправки XHTTP ~23 КБ (данные в X-Data-N) — с запасом
    large_client_header_buffers 8 16k;

    # 1. Сайт утилит (файлы приходят через node-pull)
EOF
        web_render_site_body
        cat <<EOF

    # 2. Транспорт XHTTP за CDN
    location $CDN_PATH {
        proxy_pass http://xhttp_backend;

        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;

        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        client_max_body_size 0;

        access_log off;

        add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header Expires "0" always;
    }
}
EOF
    else
        cat <<EOF
# $STUB_NAMES — сайт утилит.
# Файлы и сертификат приходят с панели: node-pull (таймер node-pull.timer).
# Xray отдаёт сюда трафик Reality (self-steal) через PROXY protocol.

server {
    listen 80;
    server_name _;
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# Всё, что пришло не на наши имена: обрываем TLS, сертификат не показываем.
# Слушаем только 127.0.0.1 — сюда ходит Xray с этой же машины.
server {
    listen 127.0.0.1:$SELFSTEAL_PORT ssl http2 proxy_protocol default_server;
    server_name _;
    ssl_reject_handshake on;
}

server {
    listen 127.0.0.1:$SELFSTEAL_PORT ssl http2 proxy_protocol;
    server_name $STUB_NAMES;

    ssl_certificate     $NGINX_SSL/fullchain.pem;
    ssl_certificate_key $NGINX_SSL/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;

    # Дальше — как у сайта на панели
EOF
        web_render_site_body
        echo "}"
    fi
    return 0
}

# До первого забора с панели nginx нужен хоть какой-то сертификат — иначе
# nginx -t не пройдёт и конфиг не встанет. Самоподписанный на 30 дней;
# node-pull заменит его настоящим при первом же заборе.
web_placeholder() {
    install -d -m 755 "$NGINX_SSL"
    if [[ ! -s "$NGINX_SSL/fullchain.pem" || ! -s "$NGINX_SSL/privkey.pem" ]]; then
        openssl req -x509 -nodes -newkey rsa:2048 -days 30 -subj "/CN=placeholder.invalid" \
            -keyout "$NGINX_SSL/privkey.pem" -out "$NGINX_SSL/fullchain.pem" >>"$SETUP_LOG" 2>&1 || return 1
        chmod 600 "$NGINX_SSL/privkey.pem"; chmod 644 "$NGINX_SSL/fullchain.pem"
        echo "  Временный сертификат положен — его заменит node-pull."
    fi
    if [[ ! -f "$STUB_ROOT/index.html" ]]; then
        install -d -m 755 "$STUB_ROOT"
        printf '<!doctype html><meta charset="utf-8"><title>…</title>\n' > "$STUB_ROOT/index.html"
        chmod 644 "$STUB_ROOT/index.html"
    fi
    return 0
}

# Пишет конфиг сайта, публикует, проверяет nginx -t; при провале — откат.
# Чужой файл с тем же именем (без нашей метки) сначала копируется в бэкап.
comp_web_site() {
    validate_role || { echo "  [СБОЙ] роль ноды задана неверно (NODE_ROLE/CDN_*)"; return 1; }
    echo ">>> Сайт ноды в nginx ($NODE_ROLE)..."
    command -v nginx >/dev/null 2>&1 || { echo "  [СБОЙ] nginx не установлен"; return 1; }
    web_placeholder || { echo "  [СБОЙ] не создать временный сертификат"; return 1; }
    nginx_default_remove || true

    local f name bak="" new
    f=$(web_site_file); name=$(basename "$f")
    new=$(mktemp)
    web_render_site > "$new"
    if [[ -f "$f" ]] && ! head -1 "$f" | grep -qF "$NGINX_MARK"; then
        mkdir -p "$RH_BACKUP_DIR"
        bak="$RH_BACKUP_DIR/$name.$(date +%Y%m%d%H%M%S)"
        cp -a "$f" "$bak"
        echo "  $name был не наш — копия в $bak"
    elif [[ -f "$f" ]]; then
        bak=$(mktemp); cp -a "$f" "$bak"
    fi
    install -m 644 "$new" "$f"; rm -f "$new"
    ln -sf "$f" "$NGINX_ENABLED/$name"

    if nginx -t >>"$SETUP_LOG" 2>&1; then
        systemctl enable nginx >>"$SETUP_LOG" 2>&1 || true
        systemctl reload nginx >>"$SETUP_LOG" 2>&1 || systemctl restart nginx >>"$SETUP_LOG" 2>&1 || true
        systemctl is-active --quiet nginx || { echo "  [СБОЙ] nginx не запустился (см. $SETUP_LOG)"; return 1; }
        echo "  Опубликован $name, nginx -t прошёл."
        return 0
    fi
    echo "  [СБОЙ] nginx -t не прошёл с новым конфигом:"
    nginx -t 2>&1 | tail -3 | sed 's/^/    /'
    if [[ -n "$bak" ]]; then
        cp -a "$bak" "$f"; echo "  Прежний $name возвращён."
    else
        rm -f "$NGINX_ENABLED/$name"; echo "  $name снят с публикации, чтобы nginx остался рабочим."
    fi
    return 1
}

# ---------------------------------------------------------------------------
#  node-pull
# ---------------------------------------------------------------------------

# Скрипт забора — тот же, что на всех нодах FixError; меняется только адрес
# и порт панели.
node_pull_write_script() {
    cat <<SCRIPT > "$NODE_PULL_BIN"
#!/bin/bash
# Забирает с панели набор (wildcard-сертификат + сайт утилит) и ставит, если что-то изменилось.
# Запуск: таймер node-pull.timer (раз в 6 часов и после загрузки) или вручную: node-pull
# Ключ и ключ хоста панели — в /etc/node-pull. Сайт — /var/www/stub, сертификат — /etc/nginx/ssl.
set -u
PANEL=$PANEL_IP
PORT=$PANEL_SSH_PORT
C=$NODE_PULL_DIR
SSL=$NGINX_SSL
WWW=$STUB_ROOT
STATE=/var/lib/node-pull; mkdir -p \$STATE
log(){ echo "\$*"; logger -t node-pull "\$*"; }

# Только один забор за раз: таймер и ручной запуск не должны мешать друг другу
exec 9>/run/node-pull.lock
flock -n 9 || { echo "забор уже идёт — дождитесь: journalctl -t node-pull -n 5"; exit 0; }
rm -rf "\$WWW".new.*   # остатки прерванного забора

# Ошибка: в журнал всегда, в Telegram — не чаще раза в 12 часов
fail(){
    log "ОШИБКА: \$*"
    if [ -z "\$(find \$STATE/notified -mmin -720 2>/dev/null)" ] && [ -x $NOTIFY_BIN ]; then
        $NOTIFY_BIN "⚠️ <b>Не обновился сертификат/сайт с панели</b>: \$*" && touch \$STATE/notified
    fi
    exit 1
}

T=\$(mktemp -d); trap 'rm -rf "\$T"' EXIT
ssh -p \$PORT -i \$C/key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes \\
    -o UserKnownHostsFile=\$C/known_hosts -o ConnectTimeout=15 -o LogLevel=ERROR \\
    $NODE_PULL_USER@\$PANEL > \$T/b.tgz 2>\$T/err || fail "панель не отдала набор (\$(head -c 200 \$T/err))"
mkdir \$T/x && tar -xzf \$T/b.tgz -C \$T/x 2>/dev/null || fail "набор повреждён"

# Проверки до установки: сертификат действует ещё сутки и подходит к ключу, сайт на месте
openssl x509 -in \$T/x/ssl/fullchain.pem -noout -checkend 86400 >/dev/null 2>&1 || fail "сертификат в наборе просрочен или битый"
a=\$(openssl x509 -in \$T/x/ssl/fullchain.pem -noout -pubkey 2>/dev/null | sha256sum)
b=\$(openssl pkey -in \$T/x/ssl/privkey.pem -pubout 2>/dev/null | sha256sum)
[ "\$a" = "\$b" ] || fail "ключ не подходит к сертификату"
[ -f \$T/x/site/index.html ] || fail "в наборе нет сайта"

changed=""
mkdir -p \$T/old
cmp -s \$T/x/ssl/fullchain.pem \$SSL/fullchain.pem && cmp -s \$T/x/ssl/privkey.pem \$SSL/privkey.pem || changed="\$changed сертификат"
diff -rq \$T/x/site \$WWW >/dev/null 2>&1 || changed="\$changed сайт"
[ -z "\$changed" ] && { log "без изменений"; exit 0; }

# Ставим, держа прежнее для отката
if [ -f \$SSL/fullchain.pem ]; then cp -p \$SSL/fullchain.pem \$SSL/privkey.pem \$T/old/ || fail "не сохранить прежний сертификат"; fi
install -d -m 755 \$SSL
install -m 644 \$T/x/ssl/fullchain.pem \$SSL/fullchain.pem || fail "не записать сертификат"
install -m 600 \$T/x/ssl/privkey.pem \$SSL/privkey.pem || fail "не записать ключ"
NEW=\$WWW.new.\$\$
rm -rf "\$NEW"
cp -a \$T/x/site "\$NEW" && chmod -R u=rwX,go=rX "\$NEW" || fail "не скопировать сайт"
# Подмена папки: старая уходит в \$T/old только когда новая готова, затем новая встаёт на место
if [ -d \$WWW ]; then mv \$WWW \$T/old/www || fail "не убрать старый сайт"; fi
if ! mv "\$NEW" \$WWW; then
    [ -d \$T/old/www ] && mv \$T/old/www \$WWW
    fail "не поставить новый сайт, прежний возвращён"
fi
[ -f \$WWW/index.html ] || fail "после подмены нет index.html"

if nginx -t >/dev/null 2>&1 && systemctl reload nginx; then
    log "обновлено:\$changed (сертификат до \$(openssl x509 -in \$SSL/fullchain.pem -noout -enddate | cut -d= -f2))"
    rm -f \$STATE/notified
else
    [ -f \$T/old/fullchain.pem ] && cp -p \$T/old/fullchain.pem \$T/old/privkey.pem \$SSL/
    [ -d \$T/old/www ] && { rm -rf \$WWW; mv \$T/old/www \$WWW; }
    nginx -t >/dev/null 2>&1 && systemctl reload nginx
    fail "nginx не принял новое, вернул прежнее"
fi
SCRIPT
    chmod 755 "$NODE_PULL_BIN"
    return 0
}

node_pull_write_units() {
    cat <<'UNIT' > "$NODE_PULL_UNIT"
[Unit]
Description=Сертификат и сайт с панели (node-pull)
Wants=network-online.target
After=network-online.target nginx.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/node-pull
UNIT
    cat <<'UNIT' > "$NODE_PULL_TIMER"
[Unit]
Description=Забор сертификата и сайта с панели раз в 6 часов

[Timer]
OnBootSec=3min
OnUnitActiveSec=6h
RandomizedDelaySec=20min

[Install]
WantedBy=timers.target
UNIT
    return 0
}

# Ключ ноды. Создаётся один раз: строка на панели привязана к нему, и новый
# ключ потребовал бы менять строку. Комментарий — имя ноды.
node_pull_key() {
    install -d -m 700 "$NODE_PULL_DIR"
    if [[ ! -s "$NODE_PULL_DIR/key" ]]; then
        ssh-keygen -q -t ed25519 -N "" -C "node-pull $SERVER_LABEL" -f "$NODE_PULL_DIR/key" <<< y >/dev/null 2>&1 || return 1
        echo "  Создан ключ ноды $NODE_PULL_DIR/key"
    fi
    chmod 600 "$NODE_PULL_DIR/key"
    return 0
}

# Ключ сервера панели. Если задан PANEL_HOSTKEY — берём его (надёжнее: подмену
# по дороге не принять). Иначе спрашиваем у самой панели и печатаем отпечаток,
# чтобы человек сверил его с панелью.
node_pull_known_hosts() {
    local kh="$NODE_PULL_DIR/known_hosts" host="[$PANEL_IP]:$PANEL_SSH_PORT" line
    if [[ -n "${PANEL_HOSTKEY:-}" ]]; then
        line="$host $(awk '{print $1, $2}' <<< "$PANEL_HOSTKEY")"
    else
        line=$(ssh-keyscan -T 10 -p "$PANEL_SSH_PORT" -t ed25519 "$PANEL_IP" 2>/dev/null | grep -v '^#' | head -1)
        [[ -n "$line" ]] || { echo "  [СБОЙ] панель $PANEL_IP:$PANEL_SSH_PORT не ответила на ssh-keyscan"; return 1; }
        PANEL_HOSTKEY_FP=$(ssh-keygen -lf <(echo "$line") 2>/dev/null | awk '{print $2}')
        echo "  Ключ сервера панели получен у неё самой: $PANEL_HOSTKEY_FP"
        echo "  Сверьте на панели: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"
    fi
    printf '%s\n' "$line" > "$kh"
    chmod 600 "$kh"
    return 0
}

# Готовая строка для authorized_keys пользователя node-pull на панели
node_pull_panel_line() {
    local pub
    pub=$(awk '{print $1, $2}' "$NODE_PULL_DIR/key.pub" 2>/dev/null)
    [[ -n "$pub" ]] || return 1
    printf 'restrict,from="%s",command="/bin/cat %s" %s node-pull %s\n' \
        "${SERVER_IP:-IP_НОДЫ}" "$NODE_PULL_BUNDLE" "$pub" "$SERVER_LABEL"
    return 0
}

# Пускает ли панель уже этот ключ. Без node-pull: тот при неудаче пишет в
# Telegram, а первая неудача до добавления строки — штатная.
node_pull_allowed() {
    ssh -p "$PANEL_SSH_PORT" -i "$NODE_PULL_DIR/key" -o IdentitiesOnly=yes -o BatchMode=yes \
        -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$NODE_PULL_DIR/known_hosts" \
        -o ConnectTimeout=15 -o LogLevel=ERROR "$NODE_PULL_USER@$PANEL_IP" 2>/dev/null | head -c 2 | grep -q .
}

comp_node_pull() {
    ask_panel_ip || return 1
    ask_node_label || return 1
    [[ -n "${SERVER_IP:-}" ]] || get_server_ip || true
    echo ">>> node-pull: сертификат и сайт с панели $PANEL_IP..."
    node_pull_key || { echo "  [СБОЙ] не создать ключ ноды"; return 1; }
    node_pull_known_hosts || return 1
    node_pull_write_script
    node_pull_write_units
    systemctl daemon-reload >>"$SETUP_LOG" 2>&1
    systemctl enable node-pull.timer >>"$SETUP_LOG" 2>&1 || true
    systemctl start node-pull.timer >>"$SETUP_LOG" 2>&1 || true

    NODE_PULL_PENDING=""
    if node_pull_allowed; then
        if "$NODE_PULL_BIN"; then
            echo "  Сертификат и сайт получены с панели."
            return 0
        fi
        echo "  [СБОЙ] панель пустила, но набор не встал (journalctl -t node-pull -n 5)"
        return 1
    fi
    NODE_PULL_PENDING=1
    echo "  Панель пока не знает ключ этой ноды — это ожидаемо на новой ноде."
    echo "  Строка для панели будет в отчёте; после её добавления: sudo node-pull"
    return 0
}

# ===== lib/80-notify.sh ================================================
# ##########################################################################
#  УВЕДОМЛЕНИЯ
#  remnawave-notify — один скрипт для панели и всех нод: вход по SSH,
#  загрузка сервера, падение/подъём ноды, плановые перезапуски
# ##########################################################################

# Скрипт кладётся байт в байт таким же, как на панели и остальных нодах:
# правка в одном месте — значит правка здесь и там. Тест сверяет его с копией.
notify_write_script() {
    cat <<'NOTIFY_SCRIPT' > "$NOTIFY_BIN"
#!/bin/bash
# Уведомления в Telegram — один скрипт для панели и нод.
# Ставится в /usr/local/sbin/remnawave-notify (владелец root: его вызывает PAM).
#
#   remnawave-notify "текст"           — отправить сообщение
#   remnawave-notify --ssh-login       — из PAM при входе по SSH
#   remnawave-notify --boot            — из cron при загрузке сервера
#   remnawave-notify --run-backup      — панель: запустить бэкап и сообщить, если он не удался
#   remnawave-notify --watch           — нода: следить за контейнером remnanode (служба systemd)
#   remnawave-notify --planned "что"   — нода: предупредить, что remnanode сейчас перезапустят
#                                        намеренно; --watch тогда не шлёт «нода упала»
#
# Настройки (TG_BOT_TOKEN, TG_CHAT_ID, TG_TOPIC_ID, TG_PROXY, SERVER_LABEL, NOTIFY_ENABLED):
#   на панели — /opt/remnawave/host/notify.env, на ноде — /etc/remnawave-notify.env.
# NOTIFY_ENABLED=0 выключает отправку (режим обкатки).

if [ -r /opt/remnawave/host/notify.env ]; then ENV_FILE=/opt/remnawave/host/notify.env
else ENV_FILE=/etc/remnawave-notify.env; fi
[ -r "$ENV_FILE" ] && . "$ENV_FILE"

PLANNED=/run/remnawave-notify.planned   # метка планового перезапуска
DOWN=/run/remnawave-notify.down         # метка «нода лежит, уже сообщили»

send() {
    [ "${NOTIFY_ENABLED:-1}" = 1 ] || return 0
    [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ] || return 0
    local args=(-s --max-time 15 --retry 2 -X POST)
    [ -n "${TG_PROXY:-}" ] && args+=(-x "$TG_PROXY")
    args+=(-d "chat_id=$TG_CHAT_ID" -d "parse_mode=HTML"
           --data-urlencode "text=🖥 <b>${SERVER_LABEL:-$(hostname)}</b>
$1")
    [ -n "${TG_TOPIC_ID:-}" ] && args+=(-d "message_thread_id=$TG_TOPIC_ID")
    curl "${args[@]}" "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" >/dev/null 2>&1
}

now() { date '+%Y-%m-%d %H:%M:%S %Z'; }
hm()  { date '+%H:%M:%S'; }

# Плановая метка действует 10 минут: если перезапуск затянулся дольше, это уже авария
planned_reason() {
    [ -f "$PLANNED" ] && [ -n "$(find "$PLANNED" -mmin -10 2>/dev/null)" ] && cat "$PLANNED"
}

case "${1:-}" in
    --ssh-login)
        [ "${PAM_TYPE:-}" = open_session ] || exit 0
        # node-pull — ноды забирают сертификат и сайт, это не вход человека
        [ "${PAM_USER:-}" = node-pull ] && exit 0
        send "🔐 <b>Вход по SSH</b>
Пользователь: <code>${PAM_USER:-?}</code>
IP: <code>${PAM_RHOST:-?}</code>
Время: $(now)" &
        exit 0 ;;
    --boot)
        sleep 8
        send "♻️ Сервер загрузился ($(now))" ;;
    --run-backup)
        # Сам бэкап делает rw-backup-restore; здесь только проверяем, что он удался
        LOG=/var/log/rw_backup_cron.log
        out=$(/opt/rw-backup-restore/backup-restore.sh backup 2>&1)
        rc=$?
        printf '%s\n%s\n' "=== $(now)" "$out" >> "$LOG"
        if [ $rc -ne 0 ] || printf '%s' "$out" | grep -q -e '\[ERROR\]' -e '❌'; then
            send "❌ <b>Бэкап не удался</b> ($(now))
Подробности: <code>$LOG</code>"
        fi
        fresh=$(find /opt/rw-backup-restore/backup -maxdepth 1 -name '*.tar.gz' -mmin -120 2>/dev/null | head -n 1)
        [ -n "$fresh" ] || send "⚠️ <b>Нет свежего бэкапа</b>: нового архива нет больше 2 часов" ;;
    --planned)
        printf '%s' "${2:-плановые работы}" > "$PLANNED" ;;
    --watch)
        # docker events отдаёт события контейнера remnanode; при падении — тревога,
        # при плановом перезапуске — одно спокойное сообщение после подъёма
        docker events --filter container=remnanode --filter event=start --filter event=die \
            --format '{{.Action}}' 2>/dev/null |
        while read -r ev; do
            case "$ev" in
                die)
                    [ -n "$(planned_reason)" ] && continue
                    [ -f "$DOWN" ] || { send "⚠️ <b>Нода упала</b>: remnanode остановился ($(hm))"; touch "$DOWN"; } ;;
                start)
                    reason=$(planned_reason)
                    if [ -n "$reason" ]; then
                        send "🔄 Плановый перезапуск ноды: ${reason}. Нода снова работает ($(hm))"
                        rm -f "$PLANNED" "$DOWN"
                    elif [ -f "$DOWN" ]; then
                        send "✅ <b>Нода поднялась</b>: remnanode запущен ($(hm))"; rm -f "$DOWN"
                    fi ;;
            esac
        done
        exit 1 ;;   # docker events завершился (перезапуск docker) — systemd запустит заново
    "")
        echo "Использование: $0 \"текст\" | --ssh-login | --boot | --run-backup | --watch | --planned \"что\"" >&2
        exit 1 ;;
    *)
        send "$1" ;;
esac
exit 0
NOTIFY_SCRIPT
    chown root:root "$NOTIFY_BIN"
    chmod 755 "$NOTIFY_BIN"
    return 0
}

notify_write_env() {
    # Значения — в двойных кавычках; кавычки и $ внутри экранируем, файл
    # читается через «.» от root
    local k v
    {
        echo "# Уведомления сервера в Telegram (fixerror-node)"
        for k in TG_BOT_TOKEN TG_CHAT_ID TG_TOPIC_ID TG_PROXY SERVER_LABEL; do
            v="${!k:-}"
            v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//\$/\\\$}; v=${v//\`/\\\`}
            printf '%s="%s"\n' "$k" "$v"
        done
        echo "NOTIFY_ENABLED=1"
    } > "$NOTIFY_ENV"
    chmod 600 "$NOTIFY_ENV"
    return 0
}

notify_write_units() {
    cat <<'UNIT' > "$NOTIFY_WATCH_UNIT"
[Unit]
Description=Уведомления: следит за контейнером remnanode
After=docker.service network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/sbin/remnawave-notify --watch
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
    cat <<'CRON' > "$NOTIFY_CRON"
# Уведомление о загрузке сервера (fixerror-node)
@reboot root /usr/local/sbin/remnawave-notify --boot
CRON
    chmod 644 "$NOTIFY_CRON"
    # Вход по SSH: строку переписываем, а не дописываем, — чтобы не двоилась
    sed -i '\|remnawave-notify --ssh-login|d' /etc/pam.d/sshd
    echo "session optional pam_exec.so seteuid /usr/local/sbin/remnawave-notify --ssh-login" >> /etc/pam.d/sshd
    return 0
}

comp_telegram() {
    ask_telegram          # все вопросы заданы здесь же, если ещё не заданы раньше
    ask_node_label || return 1
    if [[ -z "${TG_BOT_TOKEN:-}" || -z "${TG_CHAT_ID:-}" ]]; then
        echo "  [СБОЙ] не заданы TG_BOT_TOKEN и TG_CHAT_ID"
        return 1
    fi
    echo ">>> Настройка Telegram-уведомлений (remnawave-notify)..."
    notify_write_script
    notify_write_env
    notify_write_units
    systemctl daemon-reload >>"$SETUP_LOG" 2>&1
    systemctl enable remnawave-notify-watch.service >>"$SETUP_LOG" 2>&1 || true
    systemctl restart remnawave-notify-watch.service >>"$SETUP_LOG" 2>&1 || true

    # Проверяем ответ Telegram, а не просто факт запуска curl: неверный токен,
    # не добавленный в группу бот и недоступный api.telegram.org выглядели как успех.
    local tg_args=(-s --max-time 20)
    [[ -n "$TG_PROXY" ]] && tg_args+=(-x "$TG_PROXY")
    local resp
    resp=$(curl "${tg_args[@]}" -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" -d "parse_mode=HTML" \
        ${TG_TOPIC_ID:+-d "message_thread_id=${TG_TOPIC_ID}"} \
        --data-urlencode "text=🖥 <b>${SERVER_LABEL}</b>
✅ Уведомления настроены (SSH-входы, загрузка, падение/подъём ноды)" 2>/dev/null || true)
    if grep -q '"ok":true' <<< "$resp"; then
        echo "  Тестовое сообщение доставлено в Telegram."
        return 0
    fi
    echo "  [СБОЙ] Telegram не принял сообщение. Ответ API:"
    echo "    $(head -c 300 <<< "${resp:-пустой ответ}")"
    echo "    Проверьте BOT_TOKEN, CHAT_ID, прокси и что бот добавлен в группу."
    return 1
}

# ===== lib/85-extras.sh ================================================
# ##########################################################################
#  ДОПОЛНЕНИЯ
#  Необязательные компоненты и диагностика
# ##########################################################################

comp_warp() {
    echo ">>> Установка/переустановка Cloudflare WARP..."
    {
        curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflare-client.list

        apt-get "${APT_WAIT[@]}" update
        apt-get "${APT_WAIT[@]}" install -y cloudflare-warp

        warp-cli --accept-tos registration new || echo "y" | warp-cli registration new
        # На случай, если служба после регистрации подключилась сама
        warp-cli --accept-tos disconnect || true

        warp-cli --accept-tos mode proxy || warp-cli mode proxy
        warp-cli --accept-tos proxy port "$WARP_PORT" || warp-cli proxy port "$WARP_PORT"
    } >>"$SETUP_LOG" 2>&1 || { echo "  Ошибка установки WARP (см. $SETUP_LOG)"; return 1; }

    # connect разрешаем только в режиме прокси. В обычном режиме WARP заворачивает
    # в туннель весь трафик сервера, включая ответы SSH, — и сервер пропадает
    # из сети насовсем. Раньше команды шли подряд, и неудачное переключение
    # режима молча заканчивалось именно этим.
    if ! warp-cli --accept-tos settings 2>>"$SETUP_LOG" | grep -qiE 'mode:.*proxy'; then
        echo "  [СБОЙ] WARP не переключился в режим прокси — не подключаю, иначе пропадёт доступ к серверу"
        warp-cli --accept-tos settings 2>&1 | grep -i 'mode' >>"$SETUP_LOG" || true
        return 1
    fi
    warp-cli --accept-tos connect >>"$SETUP_LOG" 2>&1 \
        || { echo "  Ошибка подключения WARP (см. $SETUP_LOG)"; return 1; }
    return 0
}

comp_speedtest() {
    echo ">>> Установка Speedtest CLI..."
    {
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
        if grep -q "noble" /etc/apt/sources.list.d/ookla_speedtest-cli.list 2>/dev/null; then
            sed -i 's/noble/jammy/g' /etc/apt/sources.list.d/ookla_speedtest-cli.list; apt-get "${APT_WAIT[@]}" update
        fi
        apt-get "${APT_WAIT[@]}" install -y speedtest
    } >>"$SETUP_LOG" 2>&1 || { echo "  Speedtest не установился (см. $SETUP_LOG)"; return 1; }
}

run_bench() { echo ">>> bench.sh..."; wget -qO- bench.sh | bash || true; }

run_geo()   { echo ">>> ipregion.sh..."; bash <(wget -qO- https://raw.githubusercontent.com/Davoyan/ipregion/main/ipregion.sh) || true; }

run_censor() { echo ">>> Проверка блокировок/DPI/DNS (censorcheck)..."; bash <(wget -qO- https://raw.githubusercontent.com/vernette/censorcheck/master/censorcheck.sh) || true; }

# ===== lib/86-egress.sh ================================================
# ##########################################################################
#  ВЫХОДЫ ДЛЯ XRAY
#  warp-native (WARP интерфейсом warp через WireGuard) и Psiphon (SOCKS5)
# ##########################################################################

# Оба ставятся их собственными установщиками с GitHub — скрипт их не
# переписывает, а только запускает с нужными ответами и проверяет результат.
# Так обновления авторов приходят сами, а у нас нет второй копии чужого кода.

# Страна сервера — двумя буквами. Спрашиваем у Cloudflare: он отдаёт страну
# того, кто обратился (loc=), без сторонних сервисов геолокации.
node_country() {
    local c
    c=$(curl -fsS --max-time 10 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
        | awk -F= '$1=="loc"{print $2}' | tr -d '\r\n')
    [[ "$c" =~ ^[A-Z]{2}$ ]] && echo "$c"
    return 0
}

warp_native_active() {
    ip link show warp >/dev/null 2>&1 && systemctl is-active --quiet wg-quick@warp && return 0
    return 1
}

# Через интерфейс warp трафик должен выходить из Cloudflare (warp=on)
warp_native_works() {
    curl -fsS --max-time 15 --interface warp https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
        | grep -q '^warp=on' && return 0
    return 1
}

comp_warp_native() {
    echo ">>> warp-native (WARP интерфейсом warp)..."
    local cc; cc=$(node_country)
    if [[ "$cc" == "RU" ]]; then
        echo "  Сервер в России — warp-native здесь не работает, пропускаю."
        echo "  Для RU-нод остаётся WARP на порту $WARP_PORT."
        return 0
    fi
    if warp_native_active && [[ -z "${RH_FORCE:-}" ]]; then
        echo "  Уже установлен и работает — не трогаю."
    else
        local f; f=$(mktemp)
        if ! curl -fsSL --max-time 60 "$WARP_NATIVE_URL" -o "$f" || ! bash -n "$f"; then
            rm -f "$f"; echo "  [СБОЙ] не удалось скачать установщик warp-native"; return 1
        fi
        # Ответы установщику: язык — русский, лицензии WARP+ нет, watchdog — 5 мин
        ui_step_status "warp-native: ставлю (wgcf, WireGuard, watchdog)"
        printf '2\n\n1\n' | bash "$f" >>"$SETUP_LOG" 2>&1 || true
        rm -f "$f"
    fi
    if ! warp_native_active; then
        echo "  [СБОЙ] интерфейс warp не поднялся (см. $SETUP_LOG)"
        return 1
    fi
    if warp_native_works; then
        echo "  Готово: интерфейс warp работает, выход через Cloudflare (warp=on)."
        echo "  В Xray: outbound freedom с sockopt.interface=\"warp\", mark 51888."
        return 0
    fi
    echo "  [СБОЙ] интерфейс warp поднят, но трафик через него не выходит в Cloudflare"
    return 1
}

psiphon_active() {
    systemctl is-active --quiet vps-psiphon 2>/dev/null && return 0
    return 1
}

# Адрес, на котором vps-psiphon опубликовал SOCKS: шлюз docker0 или 127.0.0.1
psiphon_socks_addr() {
    local a
    a=$(ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -E ":${PSIPHON_PORT}\$" | head -1)
    a="${a%:*}"
    [[ -z "$a" || "$a" == "0.0.0.0" || "$a" == "*" ]] && a="127.0.0.1"
    echo "$a"
    return 0
}

comp_psiphon() {
    echo ">>> Psiphon (SOCKS5 на порту $PSIPHON_PORT)..."
    if ! command -v docker >/dev/null 2>&1; then
        echo "  [СБОЙ] Psiphon работает в контейнере, а docker не установлен"
        return 1
    fi
    local region
    region=$(echo "${PSIPHON_REGION:-}" | tr -d '[:space:]' | tr 'a-z' 'A-Z')
    # Одна страна или пул через запятую: DE или DE,NL,FR
    if [[ -n "$region" && ! "$region" =~ ^[A-Z]{2}(,[A-Z]{2})*$ ]]; then
        echo "  [ВНИМАНИЕ] PSIPHON_REGION='$region' — не код страны (нужно, например, DE или DE,NL), беру страну сервера."
        region=""
    fi
    if [[ -z "$region" ]]; then
        region=$(node_country)
        # vps-psiphon сам не выходит через RU (и ещё ряд стран): для таких
        # серверов страну не задаём — Psiphon выберет выход сам
        if [[ " RU BY IR SY CU KP CN VE " == *" $region "* ]]; then
            echo "  Сервер в $region — выход в этой стране Psiphon запрещён, регион выберет сам."
            region=""
        fi
    fi
    if psiphon_active && [[ -z "${RH_FORCE:-}" ]]; then
        echo "  Уже установлен и работает — не переустанавливаю."
    else
        local f args=(--no-http --bulk-test-mb 0)
        [[ -n "$region" ]] && args+=(--region "$region")
        f=$(mktemp)
        if ! curl -fsSL --max-time 60 "$PSIPHON_URL" -o "$f" || ! bash -n "$f"; then
            rm -f "$f"; echo "  [СБОЙ] не удалось скачать установщик vps-psiphon"; return 1
        fi
        echo "  Флаги: ${args[*]}"
        ui_step_status "Psiphon: ставлю и жду первый туннель"
        bash "$f" "${args[@]}" </dev/null >>"$SETUP_LOG" 2>&1 || true
        rm -f "$f"
    fi
    # Порог скорости в вотчдоге отключаем: на части нод он ложно браковал выходы
    if [[ -f /etc/default/vps-psiphon ]]; then
        if grep -q '^MIN_THROUGHPUT_KBPS=' /etc/default/vps-psiphon; then
            sed -i 's/^MIN_THROUGHPUT_KBPS=.*/MIN_THROUGHPUT_KBPS=0/' /etc/default/vps-psiphon
        else
            echo 'MIN_THROUGHPUT_KBPS=0' >> /etc/default/vps-psiphon
        fi
    fi
    if ! psiphon_active; then
        echo "  [СБОЙ] служба vps-psiphon не запущена (см. $SETUP_LOG)"
        return 1
    fi
    local addr i
    addr=$(psiphon_socks_addr)
    for i in $(seq 1 12); do
        ui_step_status "Psiphon: проверяю SOCKS $addr:$PSIPHON_PORT ($i/12)"
        if curl -fsS --max-time 15 --socks5-hostname "$addr:$PSIPHON_PORT" \
                https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q '^loc='; then
            echo "  Готово: SOCKS5 $addr:$PSIPHON_PORT отвечает, регион ${region:-auto}."
            return 0
        fi
        sleep 5
    done
    echo "  [СБОЙ] служба работает, но через SOCKS $addr:$PSIPHON_PORT ничего не открывается"
    echo "         состояние: vps-psiphon; журнал: vps-psiphon logs"
    return 1
}

# Из меню — переустановка по требованию, даже если уже работает
comp_warp_native_menu() { local RH_FORCE=1; comp_warp_native; }
comp_psiphon_menu()     { local RH_FORCE=1; comp_psiphon; }

# Готовые outbound'ы Xray для тех выходов, что реально работают на этой ноде —
# чтобы вставить в профиль ноды в панели, не вспоминая адреса и порты.
# Теги — предложение, переименуйте под свои правила маршрутизации.
egress_outbounds_json() {
    local items=() addr
    if ip link show warp >/dev/null 2>&1; then
        items+=('{ "tag": "warp-native", "protocol": "freedom",
    "settings": { "domainStrategy": "ForceIPv4" },
    "streamSettings": { "sockopt": { "interface": "warp", "mark": 51888, "tcpFastOpen": true } } }')
    fi
    if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -qx "127.0.0.1:$WARP_PORT"; then
        items+=('{ "tag": "warp-socks", "protocol": "socks",
    "settings": { "servers": [ { "address": "127.0.0.1", "port": '"$WARP_PORT"' } ] } }')
    fi
    if systemctl is-active --quiet vps-psiphon 2>/dev/null; then
        addr=$(psiphon_socks_addr)
        items+=('{ "tag": "psiphon", "protocol": "socks",
    "settings": { "servers": [ { "address": "'"$addr"'", "port": '"$PSIPHON_PORT"' } ] } }')
    fi
    [[ ${#items[@]} -eq 0 ]] && return 0
    local i
    echo "["
    for i in "${!items[@]}"; do
        printf '  %s' "${items[$i]}"
        [[ $i -lt $(( ${#items[@]} - 1 )) ]] && echo "," || echo
    done
    echo "]"
    return 0
}

# ===== lib/90-install.sh ===============================================
# ##########################################################################
#  ПОЛНАЯ УСТАНОВКА
#  Порядок шагов при установке с нуля
# ##########################################################################

# ##########################################################################
#  ПОЛНАЯ УСТАНОВКА
# ##########################################################################
full_install() {
    ui_title "Установка ноды FixError" "вопросы сейчас, потом работа без участия"
    # Проверки до вопросов: незачем тратить время человека, если сервер не готов
    if ! rh_preflight; then
        return 1
    fi
    RH_T0=$SECONDS
    if [[ -n "$STATE_LOADED" && -z "$NONINTERACTIVE" ]]; then
        ui_section "Найдены ответы прошлой установки"
        ui_kv "нода" "${SERVER_LABEL:-—} (${NODE_ROLE:-reality})"
        ui_kv "панель" "${PANEL_IP:-—}"
        ui_kv "учётка и порт" "${ADMIN_USER}, ${SSH_PORT}"
        read -ep "Обновить с этими данными (без повторного ввода)? [Y/n]: " USE_SAVED || USE_SAVED=""
        if [[ "$USE_SAVED" =~ ^[Nn]$ ]]; then
            PANEL_IP=""; PANEL_HOSTKEY=""; REMNA_SECRET=""; SERVER_LABEL=""
            NODE_ROLE=""; CDN_DOMAIN=""; ROLE_ASKED=""
            SSH_PUBLIC_KEY=""; SSH_EXTRA_KEYS=""; INSTALL_WARP=""; INSTALL_SPEEDTEST=""
            AGENT_SSH_KEYS=""; GEODATA=""; INSTALL_WARP_NATIVE=""; INSTALL_PSIPHON=""; PSIPHON_REGION=""
            REMNANODE_VERSION=""
            SSH_PORT="8422"; ADMIN_USER="vadim"
            SETUP_TG=""; TG_BOT_TOKEN=""; TG_CHAT_ID=""; TG_TOPIC_ID=""; TG_PROXY=""
        else
            ROLE_ASKED=1
        fi
    fi
    # --- сбор всех ответов заранее ---
    ui_section "Нода и панель"
    # Без || return 1 сбой ask_* потерялся бы: full_install вызывается из if,
    # а там set -e не действует.
    ask_panel_ip || return 1; ask_secret || return 1
    ask_node_label || return 1; ask_role || return 1
    ask_node_version
    validate_mtu

    ui_section "Доступ по SSH"
    ask_ssh_params
    ui_info "учётка «$ADMIN_USER», порт $SSH_PORT; вход под root и по паролю будут закрыты"

    if [[ -z "$NONINTERACTIVE" ]]; then
        ask_ssh_key
        ask_extra_keys
        ask_agent_key

        ui_section "Выходы для Xray и дополнения"
        [[ -z "$INSTALL_WARP" ]]      && read -ep "Cloudflare WARP (SOCKS5 на $WARP_PORT)? [Y/n]: " INSTALL_WARP
        [[ -z "$INSTALL_WARP" ]] && INSTALL_WARP="y"
        [[ -z "$INSTALL_WARP_NATIVE" ]] && read -ep "warp-native (WARP интерфейсом warp; на нодах в РФ пропускается)? [Y/n]: " INSTALL_WARP_NATIVE
        [[ -z "$INSTALL_WARP_NATIVE" ]] && INSTALL_WARP_NATIVE="y"
        [[ -z "$INSTALL_PSIPHON" ]]   && read -ep "Psiphon (SOCKS5 на $PSIPHON_PORT)? [Y/n]: " INSTALL_PSIPHON
        [[ -z "$INSTALL_PSIPHON" ]] && INSTALL_PSIPHON="y"
        if [[ "$INSTALL_PSIPHON" =~ ^[Yy]$ && -z "$PSIPHON_REGION" ]]; then
            read -ep "Страна выхода Psiphon, две буквы (Enter — страна сервера): " PSIPHON_REGION
            PSIPHON_REGION=$(echo "$PSIPHON_REGION" | tr -d '[:space:]' | tr 'a-z' 'A-Z')
        fi
        [[ -z "$INSTALL_SPEEDTEST" ]] && read -ep "Speedtest CLI? [Y/n]: " INSTALL_SPEEDTEST
        [[ -z "$INSTALL_SPEEDTEST" ]] && INSTALL_SPEEDTEST="y"
        [[ -z "$GEODATA" ]]           && read -ep "Geo-базы Loyalsoldier с обновлением раз в 3 дня? [Y/n]: " GEODATA
        [[ -z "$GEODATA" ]] && GEODATA="y"

        ui_section "Telegram-уведомления"
        [[ -z "$SETUP_TG" && -z "$TG_BOT_TOKEN" ]] && read -ep "Настроить Telegram-уведомления? [Y/n]: " SETUP_TG
        [[ -z "$SETUP_TG" && -z "$TG_BOT_TOKEN" ]] && SETUP_TG="y"
        [[ "$SETUP_TG" =~ ^[Yy]$ || -n "$TG_BOT_TOKEN" ]] && ask_telegram
    fi
    [[ "$SETUP_TG" =~ ^[Yy]$ || -n "$TG_BOT_TOKEN" ]] && TG_ON=1 || TG_ON=""

    save_state   # запомнить ответы для будущих обновлений
    get_server_ip || true
    ui_title "Ставлю ноду $SERVER_LABEL" "вопросов больше не будет · подробный лог: $SETUP_LOG"
    sleep 1

    # --- выполнение (каждый шаг пишет результат в сводку) ---
    RH_FULL_INSTALL=1
    do_step "Swap" comp_swap
    # Пакеты — фундамент. Без них не встанут ни нода, ни сертификат, ни fail2ban,
    # ни docker, и человек получает шесть сбоев по одной причине плюс отчёт,
    # в котором половина строк врёт. Останавливаемся здесь: SSH ещё не тронут,
    # сервер в том же состоянии, что и до запуска.
    if ! do_step_required "Пакеты и обновление системы" comp_packages; then
        # Скрипт сам смотрит, в apt ли дело, а не отправляет человека набирать
        # команды. Прежняя подсказка «pgrep -a '...'» к тому же искала apt по
        # имени процесса и показывала бы постоянный демон ожидания выключения
        # как держателя блокировки — ждать пришлось бы вечно.
        local who; who=$(apt_busy_who)
        ui_title "Установка остановлена" "пакеты не установились — без них не будет ни ноды, ни сертификата"
        if [[ -n "$who" ]]; then
            ui_warn "apt до сих пор занят другим процессом:"
            printf '%s\n' "$who" | sed 's/^/        /'
            ui_info "обычно это автообновление после первой загрузки; дождитесь его"
            ui_info "или притормозите на время установки:"
            ui_info "  systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer"
        else
            ui_ok "apt сейчас свободен — значит, дело не в блокировке"
            ui_info "причина — в строках под упавшим шагом выше; целиком в логе:"
            ui_info "  grep -A40 '=== ШАГ: Пакеты' $SETUP_LOG"
        fi
        echo
        ui_info "ничего не сломано: SSH не менялся, сервер в том же состоянии,"
        ui_info "что и до запуска. Разберитесь с причиной и запустите установку заново."
        ui_rule
        return 1
    fi
    do_step "Время UTC + синхронизация" comp_time
    do_step "Пользователь $ADMIN_USER" comp_user
    [[ -n "${AGENT_SSH_KEYS:-}" ]] && do_step "Учётка ИИ-агента" comp_agent || skip_step "Учётка ИИ-агента (ключ не задан)"
    do_step "Ключи сервера" comp_hostkeys
    do_step "Харденинг SSH" comp_ssh
    do_step "fail2ban" comp_fail2ban
    do_step "Автообновления безопасности" comp_autoupdates
    do_step "UFW-фаервол + блокировка торрентов" comp_ufw
    do_step "Sysctl-тюнинг" comp_sysctl
    do_step "MTU" comp_mtu
    do_step "Docker" comp_docker
    do_step "Защита диска (лог-ротация)" comp_disk
    [[ "$INSTALL_SPEEDTEST" =~ ^[Yy]$ ]] && do_step "Speedtest CLI" comp_speedtest || skip_step "Speedtest CLI"
    [[ "$INSTALL_WARP" =~ ^[Yy]$ ]] && do_step "Cloudflare WARP" comp_warp || skip_step "Cloudflare WARP"
    [[ "${INSTALL_WARP_NATIVE:-n}" =~ ^[Yy]$ ]] && do_step "warp-native" comp_warp_native || skip_step "warp-native"
    [[ "${INSTALL_PSIPHON:-n}" =~ ^[Yy]$ ]] && do_step "Psiphon" comp_psiphon || skip_step "Psiphon"
    # Telegram — до ноды: тогда сторож и плановые перезапуски работают с самого начала
    [[ -n "$TG_ON" ]] && do_step "Telegram-уведомления" comp_telegram || skip_step "Telegram-уведомления"
    # Базы — до ноды: тогда compose сразу пишется с томами
    [[ "${GEODATA:-y}" =~ ^[Yy]$ ]] && do_step "Geo-базы (Loyalsoldier)" comp_geodata || skip_step "Geo-базы (Loyalsoldier)"
    do_step "Нода Remnanode" comp_node
    do_step "Сайт ноды в nginx" comp_web_site
    do_step "node-pull (сертификат и сайт с панели)" comp_node_pull

    local fails; fails=$(ui_fail_count "${SUMMARY[@]}")
    if [[ "$fails" -eq 0 ]]; then
        notify_telegram "🚀 Нода установлена ($(date '+%H:%M:%S %Z'))"
    else
        notify_telegram "⚠️ Нода установлена с ошибками: $fails ($(date '+%H:%M:%S %Z')). Отчёт: $REPORT_FILE"
    fi

    print_summary

    if [[ -z "$NONINTERACTIVE" ]]; then
        echo
        ui_info "отчёт сохранён в $REPORT_FILE, там же пароль учётки и строка для панели"
        if [[ -n "${NODE_PULL_PENDING:-}" ]]; then
            ui_warn "не забудьте добавить строку node-pull на панели (она выше, в отчёте)"
        fi
        read -ep "Доустановить/переустановить что-то в меню перед ребутом? [y/N]: " ADDC || ADDC=""
        [[ "$ADDC" =~ ^[Yy]$ ]] && components_menu
        read -ep "Перезагрузить сервер сейчас? [Y/n]: " RB || RB=""
        if [[ "$RB" =~ ^[Nn]$ ]]; then
            echo "Ок. Позже перезагрузи вручную (новое ядро и порт SSH): reboot"
            return
        fi
    fi
    echo "Перезагрузка через 10 секунд (Ctrl+C — отменить)..."
    sleep 10
    reboot
}

# ===== lib/92-repair.sh ================================================
# ##########################################################################
#  ПОЧИНКА УЖЕ НАСТРОЕННОЙ НОДЫ
#  Один проход без вопросов: sudo bash setup.sh --repair
# ##########################################################################

# Зачем отдельный режим. При обходе парка нод находки повторяются: права на
# файлы с секретами, слетевший харденинг SSH, сломанные служебные скрипты,
# выключенные таймеры. Ходить по меню на каждой ноде и вводить домен с токеном руками —
# долго и есть риск опечататься на рабочем сервере.
#
# Режим ничего не переустанавливает: не трогает ufw, не пересоздаёт контейнер,
# не перезагружает сервер. Все ответы берутся с самой ноды.

# Хостеры после ремонта сервера кладут свои дроп-ины в /etc/ssh/sshd_config.d/.
# Имена вида 00-*.conf сортируются раньше нашего 01-hardening.conf, а sshd
# берёт ПЕРВОЕ встреченное значение — и root с паролями снова открыты, хотя
# файл харденинга на месте и порт правильный. Проверяем фактом (sshd -T) и
# трогаем конфиг ТОЛЬКО если он действительно разъехался.
repair_ssh_hardening() {
    local eff_root eff_pass eff_port

    # Впервые харденинг не накатываем: он отключает вход по паролю и требует
    # проверенный SSH-ключ, а это разговор с человеком. Только восстанавливаем.
    if [[ ! -f "$SSH_HARDEN_FILE" ]]; then
        echo "  Харденинг на этой ноде не применялся — пропускаю."
        echo "  Первичная настройка спросит ключ: меню, пункт 2 -> 8."
        return 0
    fi

    sshd_rundir
    eff_root=$(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2}')
    eff_pass=$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')
    eff_port=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')
    if [[ -z "$eff_root$eff_pass" ]]; then
        echo "  [СБОЙ] sshd не отвечает на sshd -T — вслепую чинить SSH опасно."
        return 1
    fi

    if [[ "$eff_root" == "no" && "$eff_pass" == "no" ]] && sshd_listens_on "$SSH_PORT"; then
        echo "  Харденинг на месте: порт $SSH_PORT, root и вход по паролю закрыты. Не трогаю."
        return 0
    fi

    echo "  Харденинг разъехался: root=$eff_root, пароли=$eff_pass, порт в конфиге=${eff_port:-?}"
    echo "  Восстанавливаю на порт $SSH_PORT. Бэкапы конфигов останутся рядом,"
    echo "  при неудаче харденинг откатится, пока текущая сессия жива."
    comp_ssh
}

# nginx лежит, потому что IPv6 выключен, а стоковый сайт default слушает [::].
# Это следствие нашего же шага «Отключение IPv6», поэтому чиним — но только
# стоковый default и только после подтверждения плана.
repair_nginx_default() {
    nginx_default_remove || true
    if ! nginx -t >>"$SETUP_LOG" 2>&1; then
        echo "  [СБОЙ] nginx -t всё ещё не проходит:"
        nginx -t 2>&1 | tail -3 | sed 's/^/    /'
        local other; other=$(nginx_ipv6_listeners | tr '\n' ' ')
        if [[ -n "$other" ]]; then
            echo "  listen [::] остался в ваших сайтах: $other — их скрипт не правит"
        fi
        return 1
    fi
    dpkg --configure -a >>"$SETUP_LOG" 2>&1 || true
    systemctl restart nginx >>"$SETUP_LOG" 2>&1 || true
    if ! systemctl is-active --quiet nginx; then
        echo "  [СБОЙ] nginx так и не запустился (см. $SETUP_LOG)"
        return 1
    fi
    echo "  nginx снова работает."
    return 0
}

repair_node_pull() {
    node_pull_write_script
    node_pull_write_units
    systemctl daemon-reload >>"$SETUP_LOG" 2>&1
    systemctl enable --now node-pull.timer >>"$SETUP_LOG" 2>&1 || true
    if "$NODE_PULL_BIN"; then
        echo "  node-pull отработал."
        return 0
    fi
    echo "  [СБОЙ] node-pull не забрал набор: journalctl -t node-pull -n 5"
    echo "         есть ли строка ключа на панели? $(node_pull_panel_line 2>/dev/null | cut -c1-60)…"
    return 1
}

repair_geodata_timer() {
    geodata_write_updater
    geodata_write_units
    systemctl daemon-reload >>"$SETUP_LOG" 2>&1
    systemctl enable --now geo-update.timer >>"$SETUP_LOG" 2>&1 || true
    systemctl is-enabled --quiet geo-update.timer 2>/dev/null || { echo "  [СБОЙ] таймер не включился"; return 1; }
    echo "  Таймер geo-update включён: $(systemctl show -p NextElapseUSecRealtime --value geo-update.timer 2>/dev/null)"
    return 0
}

repair_perms() {
    local rc=0 f
    node_dir_perms || rc=1
    for f in "$SETUP_LOG" "$INSTALL_STATE" "$NOTIFY_ENV" "$REPORT_FILE" \
             "$NODE_PULL_DIR/key" "$NODE_PULL_DIR/known_hosts" "$NGINX_SSL/privkey.pem"; do
        [[ -f "$f" ]] && { chmod 600 "$f" || rc=1; }
    done
    [[ -d "$NODE_PULL_DIR" ]] && { chmod 700 "$NODE_PULL_DIR" || rc=1; }
    echo "  Права приведены к 600 (каталог ноды — 750 с группой docker)."
    return $rc
}

# Проверка, что служебные скрипты действительно годные: файл без первой строки
# исполняется через /bin/sh, где нет [[ ]], и молча не работает.
repair_verify() {
    local f bad=""
    for f in "$NOTIFY_BIN" "$GEODATA_BIN" "$NODE_PULL_BIN"; do
        [[ -f "$f" ]] || continue
        head -1 "$f" | grep -q '^#!' || bad+=" $(basename "$f")"
    done
    if [[ -n "$bad" ]]; then
        echo "  [СБОЙ] без первой строки (#!/bin/bash):$bad"
        return 1
    fi
    echo "  Служебные скрипты на месте и начинаются с #!/bin/bash."
    return 0
}

# ##########################################################################
#  ПЛАН
#  Сначала показываем, что именно будет сделано, и только потом делаем.
#  Пункт меню — это одна кнопка; человек имеет право знать, что за ней.
# ##########################################################################

# Каждый шаг — строка "функция|метка|что именно меняет"
repair_add()  { REPAIR_PLAN+=("$1|$2|$3"); }
repair_note() { REPAIR_SKIPS+=("$1"); }

repair_build_plan() {
    REPAIR_PLAN=()
    REPAIR_SKIPS=()

    repair_add repair_perms "Права на файлы с секретами" \
        "chmod 600 на install.conf, notify.env, ключ node-pull, ключ сертификата, лог, отчёт и compose; каталог ноды — 750 с группой docker"

    if [[ -f "$SSH_HARDEN_FILE" ]]; then
        repair_add repair_ssh_hardening "Харденинг SSH" \
            "только если sshd -T показывает открытый root или вход по паролю: перезальёт $(basename "$SSH_HARDEN_FILE") и перезапустит sshd"
    else
        repair_note "Харденинг SSH — на этой ноде не применялся, первичный делается пунктом 2 -> 8"
    fi

    if getent group docker >/dev/null 2>&1 && [[ -n "${ADMIN_USER:-}" ]] && id "$ADMIN_USER" &>/dev/null; then
        repair_add docker_group_member "Группа docker у $ADMIN_USER" \
            "usermod -aG docker, если его там ещё нет (нужно, чтобы docker ps работал без sudo)"
    else
        repair_note "Группа docker — Docker не установлен или учётка не определена"
    fi

    if [[ -f "$NOTIFY_ENV" ]]; then
        repair_add comp_telegram "Уведомления (remnawave-notify)" \
            "перезапишет remnawave-notify, его службу, @reboot и строку PAM; пришлёт тестовое сообщение"
    else
        repair_note "Уведомления — Telegram на этой ноде не настроен (пункт 2 -> 11)"
    fi

    if [[ -f "$NODE_PULL_DIR/key" && -n "${PANEL_IP:-}" ]]; then
        repair_add repair_node_pull "node-pull" \
            "перезапишет скрипт и таймер node-pull (ключ ноды не меняется), включит таймер и заберёт набор"
    else
        repair_note "node-pull — ключа ноды нет, ставится пунктом 2 -> 4"
    fi

    if [[ -f "$GEODATA_DIR/geosite.dat" ]]; then
        repair_add repair_geodata_timer "Обновление geo-баз" \
            "перезапишет geo-update и его таймер (раз в 3 дня), включит таймер; базы не перекачивает"
    fi

    if ipv6_off_or_pending && nginx_ipv6_listeners | grep -qx default; then
        repair_add repair_nginx_default "nginx: убрать стоковый сайт default" \
            "удалит default из sites-available и sites-enabled (копия в $RH_BACKUP_DIR): без IPv6 nginx из-за него не стартует; перезапустит nginx"
    fi

    repair_add repair_verify "Проверка служебных скриптов" \
        "ничего не меняет, только читает первую строку каждого скрипта"
    return 0
}

repair_print_plan() {
    local line fn label what n=0
    ui_section "БУДЕТ СДЕЛАНО"
    for line in "${REPAIR_PLAN[@]}"; do
        n=$((n+1))
        IFS='|' read -r fn label what <<< "$line"
        printf '   %d) %s\n' "$n" "$label"
        printf '      %s\n' "$what"
    done
    if [[ ${#REPAIR_SKIPS[@]} -gt 0 ]]; then
        ui_section "ПРОПУЩУ"
        local s
        for s in "${REPAIR_SKIPS[@]}"; do ui_skip "$s"; done
    fi
    echo
    ui_info "не тронет: фаервол, контейнер ноды, пакеты, ваши сайты nginx; перезагрузки не будет"
    echo
    return 0
}

# Выбор шагов по одному. Отдельной функцией, чтобы вопрос не оказался
# внутри шага установки — там ждать ввода нельзя.
repair_pick_steps() {
    local line fn label what ans kept=()
    echo
    for line in "${REPAIR_PLAN[@]}"; do
        IFS='|' read -r fn label what <<< "$line"
        read -ep "  $label — делать? [Y/n]: " ans || ans=""
        if [[ "$ans" =~ ^[Nn]$ ]]; then
            REPAIR_SKIPS+=("$label — отказались")
        else
            kept+=("$line")
        fi
    done
    REPAIR_PLAN=("${kept[@]}")
    return 0
}

run_repair() {
    SUMMARY=()
    ui_title "Починка настроенной ноды" "типовые поломки; конфиг сайта nginx не трогается"

    ui_kv "нода" "${SERVER_LABEL:-не определена} (${NODE_ROLE:-?})"
    ui_kv "панель" "${PANEL_IP:-не определена}"
    ui_kv "учётка и порт" "${ADMIN_USER:-?}, ${SSH_PORT:-?}"
    ui_kv "telegram" "$([[ -n "${TG_BOT_TOKEN:-}" ]] && echo "настроен" || echo "не настроен")"

    repair_build_plan
    repair_print_plan

    if [[ -z "$NONINTERACTIVE" ]]; then
        local ans
        read -ep "  Выполнить? [y — всё / s — выбрать по шагам / N — отмена]: " ans || ans=""
        case "$ans" in
            [Yy]) ;;
            [Ss]) repair_pick_steps ;;
            *)    echo "  Отменено. Ничего не изменено."; return 0 ;;
        esac
    fi

    # Дальше — работа без вопросов. Шаги идут под спиннером, их вывод уходит
    # в лог, и приглашение ввода было бы невидимо: установка просто встала бы.
    # Все ответы уже либо вычитаны с ноды, либо заданы.
    local NONINTERACTIVE=1

    if [[ ${#REPAIR_PLAN[@]} -eq 0 ]]; then
        echo "  Не выбрано ни одного шага. Ничего не изменено."
        return 0
    fi

    echo
    local line fn label what
    for line in "${REPAIR_PLAN[@]}"; do
        IFS='|' read -r fn label what <<< "$line"
        do_step "$label" "$fn"
    done

    local skipped
    for skipped in "${REPAIR_SKIPS[@]}"; do skip_step "$skipped"; done

    # Конфиг сайта nginx починка не переписывает: рядом может жить чужой
    # сайт. Переписать свой — пункт 2 -> 4, он покажет, что пишет.
    skip_step "Конфиг сайта nginx — не трогаю (переписать: пункт 2 -> 4)"

    save_state || true

    ui_section "Итог"
    ui_summary "${SUMMARY[@]}"
    echo
    ui_kv "ответы ноды" "$INSTALL_STATE"
    ui_kv "проверить" "sudo bash /tmp/setup.sh --check"
    ui_kv "сертификат" "sudo node-pull (журнал: journalctl -t node-pull)"
    return 0
}

# ===== lib/94-check.sh =================================================
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

# ===== lib/95-menu.sh ==================================================
# ##########################################################################
#  МЕНЮ
#  Главное меню и меню компонентов
# ##########################################################################

# ##########################################################################
#  МЕНЮ
# ##########################################################################
# Запуск компонента из меню.
# Обязательно через "if", а не напрямую: ERR-трап срабатывает даже при set +e,
# и любая ненулевая команда внутри comp_* убивала бы весь установщик.
# Внутри условия и set -e, и ERR-трап подавлены для всего поддерева вызова.
menu_step() {
    local label="$1"; shift
    if "$@"; then
        echo; ui_ok "$label"
    else
        echo; ui_err "$label — подробности в $SETUP_LOG"
    fi
    # Ответы, которые человек только что ввёл, надо запомнить: иначе на ноде
    # без install.conf их придётся вводить заново при каждой следующей правке.
    save_state || true
    return 0
}

# Передеплой из меню — с вопросом о версии: так ноду и откатывают, и возвращают
comp_node_menu() {
    ask_node_version
    comp_node
}

# Из меню ключ спрашиваем на месте: в полной установке его спросили заранее
comp_agent_menu() {
    ask_agent_key
    comp_agent
}

# Пункт 8 делает два шага подряд — оборачиваем, чтобы тоже шло через menu_step
comp_user_and_ssh() { comp_user && comp_ssh; }

# Диагностика из меню. Обязательно в подоболочке и обязательно внутри "if":
# rh_check штатно возвращает 1, когда нашла проблемы, и снимает себе set -e.
menu_check() {
    if ( rh_check "$@" ); then
        echo
        echo "Проблем не найдено."
    else
        echo
        echo "Найденное чинится пунктом 4 — он сам разберётся, что именно."
    fi
    return 0
}

# Починка из меню. NONINTERACTIVE НЕ выставляем: из меню починка обязана
# показать план и спросить подтверждение, иначе это кнопка вслепую.
menu_repair() {
    if run_repair; then
        echo
        echo "Проверить результат: пункт 3."
    else
        echo
        echo "Починка завершилась с ошибкой — подробности в $SETUP_LOG"
    fi
    return 0
}

# Пункт 4: сайт nginx и node-pull. Конфиг показывается целиком до записи —
# рядом с нодой может жить чужой сайт, и человек вправе видеть, что пишется.
comp_web_menu() {
    ask_role || return 1
    ask_panel_ip || return 1
    ask_node_label || return 1
    local f ans
    f=$(web_site_file)
    ui_section "Конфиг, который будет записан в $f"
    web_render_site | sed 's/^/    /'
    if [[ -f "$f" ]]; then
        ui_section "Отличия от текущего"
        diff -u "$f" <(web_render_site) | sed 's/^/    /' || true
    fi
    echo
    read -ep "  Записать конфиг и настроить node-pull? [y/N]: " ans || ans=""
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "  Отменено, ничего не записано."; return 0; }
    comp_web_site && comp_node_pull
}

# Пункт 22: строка ключа этой ноды для панели — когда её надо добавить заново
show_panel_line() {
    get_server_ip || true
    ask_node_label || return 1
    if ! node_pull_panel_line >/dev/null 2>&1; then
        echo "  Ключа ноды нет ($NODE_PULL_DIR/key) — настройте node-pull пунктом 4."
        return 1
    fi
    echo "  На панели, в Termius:"
    printf "  echo '%s' | sudo tee -a /var/lib/node-pull/.ssh/authorized_keys\n" "$(node_pull_panel_line)"
    echo "  Потом здесь: sudo node-pull"
    return 0
}

components_menu() {
    while true; do
        ui_title "Компоненты" "доустановить или переустановить по одному"
        echo " 1) Cloudflare WARP        2) Docker          3) Нода (передеплой)"
        echo " 4) Сайт nginx + node-pull (покажет и спросит)"
        echo " 5) UFW + торренты         6) Sysctl-тюнинг"
        echo " 7) Swap                   8) Юзер + SSH-харденинг   9) Speedtest"
        echo "10) MTU (замер и закрепление)"
        echo "--- Безопасность / обслуживание ---"
        echo "11) Telegram-уведомления  12) fail2ban       13) Автообновления"
        echo "21) Время UTC + синхронизация   22) Строка ключа ноды для панели"
        echo "24) Учётка ИИ-агента"
        echo "25) Geo-базы Loyalsoldier + обновление раз в 3 дня"
        echo "26) warp-native (WARP интерфейсом)  27) Psiphon (SOCKS5)"
        echo "14) Защита диска          15) Обновить ноду  16) Статус ноды"
        echo "20) Обновить систему (apt upgrade + перезагрузка)"
        echo "--- Диагностика ---"
        echo "17) bench.sh   18) ipregion   19) проверка блокировок (censorcheck)"
        echo "  0) Назад"
        printf '\n'; read -ep "  Выбор: " c
        case "$c" in
             1) menu_step "Cloudflare WARP"      comp_warp ;;
             2) menu_step "Docker"               comp_docker ;;
             3) menu_step "Нода (передеплой)"    comp_node_menu ;;
             4) menu_step "Сайт nginx + node-pull" comp_web_menu ;;
             5) menu_step "UFW + торренты"       comp_ufw ;;
             6) menu_step "Sysctl-тюнинг"        comp_sysctl ;;
             7) menu_step "Swap"                 comp_swap ;;
             8) menu_step "Юзер + SSH-харденинг" comp_user_and_ssh ;;
             9) menu_step "Speedtest"            comp_speedtest ;;
            10) menu_step "MTU"                  comp_mtu ;;
            11) menu_step "Telegram-уведомления" comp_telegram ;;
            12) menu_step "fail2ban"             comp_fail2ban ;;
            13) menu_step "Автообновления"       comp_autoupdates ;;
            14) menu_step "Защита диска"         comp_disk ;;
            15) menu_step "Обновление ноды"      comp_node_update ;;
            16) menu_step "Статус ноды"          node_status ;;
            17) menu_step "bench.sh"             run_bench ;;
            18) menu_step "ipregion"             run_geo ;;
            19) menu_step "censorcheck"          run_censor ;;
            20) menu_step "Обновление системы"   comp_os_update ;;
            21) menu_step "Время UTC"            comp_time ;;
            22) menu_step "Строка для панели"    show_panel_line ;;
            24) menu_step "Учётка ИИ-агента"      comp_agent_menu ;;
            25) menu_step "Geo-базы"              comp_geodata ;;
            26) menu_step "warp-native"           comp_warp_native_menu ;;
            27) menu_step "Psiphon"               comp_psiphon_menu ;;
             0) return ;;
             *) echo "Нет такого пункта." ;;
        esac
    done
}

main_menu() {
    while true; do
        ui_title "Установщик ноды FixError" "нода Remnawave: установка, диагностика, починка"
        echo " 1) Полная установка (чистый сервер)"
        echo " 2) Доустановить/переустановить компонент"
        echo " 3) Диагностика — что не так с этой нодой (ничего не меняет)"
        echo " 4) Починка по итогам диагностики"
        echo " 5) Диагностика + проверка забора с панели (node-pull --dry)"
        echo " 0) Выход"
        printf '\n'; read -ep "  Выбор: " m
        case "$m" in
            1) full_install || true ;;   # остановка уже объяснена, меню живёт дальше
            2) components_menu ;;
            3) menu_check ;;
            4) menu_repair ;;
            5) menu_check --deep ;;
            0) exit 0 ;;
            *) echo "Нет такого пункта." ;;
        esac
    done
}

# ===== lib/99-main.sh ==================================================
# ##########################################################################
#  ТОЧКА ВХОДА
#  Три режима: только загрузка функций (тесты), неинтерактивный, меню
# ##########################################################################

# Режим «только функции»: используется tests/, чтобы вызывать функции по одной
# без запуска установки. Работает и при source, и при обычном запуске.
if [[ -n "${RH_LIB_ONLY:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

# Диагностика без меню: тот же код, что в пункте 3. Ничего не меняет.
if [[ "${1:-}" == "--check" ]]; then
    if [[ -f "$INSTALL_STATE" ]]; then
        # shellcheck disable=SC1090
        source "$INSTALL_STATE"
    fi
    # Через "if": rh_check штатно возвращает 1, когда нашла проблемы, и без
    # этого set -e с ERR-трапом напечатали бы поверх отчёта аварийную простыню.
    if ( rh_check "${2:-}" ); then exit 0; else exit 1; fi
fi

# Дальше начинается работа, а не чтение: уходим в tmux, чтобы обрыв ssh не
# бросил установку на середине, и берём замок от второго запуска.
#
# Порядок важен. Если взять замок ДО tmux, дескриптор замка унаследует клиент
# tmux и продержит его всю сессию — и установщик внутри tmux упрётся в
# собственный замок: «уже работает другой запуск». Так и было, проверено.
# А второй интерактивный запуск при таком порядке просто подключится к уже
# идущей сессии tmux (new-session -A) — это ровно то, что нужно.
rh_session_guard "$@"
rh_take_lock

# Починка уже настроенной ноды: без вопросов, без переустановки
if [[ "${1:-}" == "--repair" ]]; then
    NONINTERACTIVE=1
    if [[ -f "$INSTALL_STATE" ]]; then
        # shellcheck disable=SC1090
        source "$INSTALL_STATE"
    fi
    detect_existing_setup
    validate_ssh_params
    run_repair
    exit 0
fi

# Конфиг-файл первым аргументом — неинтерактивная установка
if [[ -n "$1" && -f "$1" ]]; then
    echo "Загружаю конфигурацию из файла: $1"
    # shellcheck disable=SC1090
    source "$1"
    NONINTERACTIVE=1
    validate_ssh_params
fi

if [[ -n "$NONINTERACTIVE" ]]; then
    NONINTERACTIVE=1
    # Через if: остановленная установка уже объяснила причину сама, а голый
    # вызов под set -e поверх её объяснения напечатал бы аварийную рамку.
    if ! full_install; then exit 1; fi
else
    # Интерактив: подхватить сохранённые данные прошлой установки как значения по умолчанию
    if [[ -f "$INSTALL_STATE" ]]; then
        # shellcheck disable=SC1090
        source "$INSTALL_STATE"
        STATE_LOADED=1
    fi
    # Дополняем тем, что можно вычитать с самого сервера. Вызывается всегда:
    # install.conf может существовать, но быть неполным — например, создан
    # ранней версией или после точечной правки через меню.
    detect_existing_setup
    if [[ -z "$STATE_LOADED" && -n "${PANEL_IP:-}${REMNA_SECRET:-}${TG_BOT_TOKEN:-}" ]]; then
        echo "Файла с ответами нет, но нода настроена — вычитал с сервера:"
        [[ -n "${SERVER_LABEL:-}" ]]         && echo "  нода:     $SERVER_LABEL (${NODE_ROLE:-?})"
        [[ -n "${PANEL_IP:-}" ]]             && echo "  панель:   $PANEL_IP"
        [[ -n "${REMNA_SECRET:-}" ]]         && echo "  секрет:   найден в docker-compose.yml"
        [[ -n "${TG_BOT_TOKEN:-}" ]]         && echo "  Telegram: токен и chat_id найдены"
        echo "  Значения подставлены в вопросы — проверьте их там."
        STATE_LOADED=1
    fi
    validate_ssh_params
    main_menu
fi
