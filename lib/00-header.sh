#!/bin/bash
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
