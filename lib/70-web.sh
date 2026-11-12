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
