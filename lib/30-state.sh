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
