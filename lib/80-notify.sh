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
