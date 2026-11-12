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
