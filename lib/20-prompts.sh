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
