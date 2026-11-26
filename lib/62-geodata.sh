# ##########################################################################
#  GEO-БАЗЫ
#  geoip.dat и geosite.dat от Loyalsoldier для Xray внутри ноды. Установщик
#  кладёт их один раз, дальше их обновляет само ядро Xray — без перезапуска.
# ##########################################################################

# Встроенные в образ ноды базы обновляются только вместе с образом. Свежие базы
# Loyalsoldier выходят каждый день; в них то, по чему маршрутизирует ядро
# (category-ru, geoip ru и т.д.). Поэтому подключаем свои.
#
# Обновляет их ядро: в конфиг-профиле панели блок geodata (cron, outbound,
# assets). Xray качает файл во временный рядом, переименовывает на место и
# перечитывает базы на лету, клиенты не рвутся. Для этого в контейнер
# подключается весь каталог и с записью: в пофайловый том :ro ядро не запишет,
# а замену файла через переименование пофайловый том не увидит.

geodata_present() {
    [[ -s "$GEODATA_DIR/geoip.dat" && -s "$GEODATA_DIR/geosite.dat" ]] && return 0
    return 1
}

# Подключён каталог целиком (как надо), а не отдельные файлы
geodata_mounted() {
    grep -qE "^[[:space:]]*-[[:space:]]*$GEODATA_DIR:/usr/local/share/xray[[:space:]]*$" \
        /opt/remnanode/docker-compose.yml 2>/dev/null
}

# Старая схема: пофайловые тома :ro и таймер geo-update с перезапуском ноды
geodata_legacy_mount() {
    grep -q "$GEODATA_DIR/geosite.dat:" /opt/remnanode/docker-compose.yml 2>/dev/null
}

geodata_legacy_timer() {
    systemctl is-enabled --quiet geo-update.timer 2>/dev/null
}

# Том баз в compose ноды: пофайловые строки старой схемы заменяются одной
# строкой каталога; если томов нет вовсе — секция дописывается в конец.
# Бэкап compose — рядом, с датой.
geodata_compose_fix() {
    local c="$1" line="      - $GEODATA_DIR:/usr/local/share/xray"
    cp -a "$c" "$c.bak.$(date +%Y%m%d%H%M%S)"
    if grep -q "$GEODATA_DIR/geo" "$c"; then
        awk -v line="$line" -v d="$GEODATA_DIR/geo" '
            index($0, d) { if (!done) { print line; done=1 }; next }
            { print }' "$c" > "$c.new" || return 1
    elif grep -qE '^[[:space:]]+volumes:' "$c"; then
        awk -v line="$line" '{ print } /^[[:space:]]+volumes:/ { print line }' "$c" > "$c.new" || return 1
    else
        { cat "$c"; echo "    volumes:"; echo "$line"; } > "$c.new" || return 1
    fi
    chmod 600 "$c.new"; mv -f "$c.new" "$c"
    grep -qxF -- "$line" "$c"
}

# Первая загрузка баз. Сверяет sha256 с опубликованной суммой: база, не
# прошедшая проверку, в ноду не попадёт. Кладёт через переименование, как и
# само ядро, — нода, если уже работает, читает либо старый файл, либо новый.
geodata_download() {
    local tmp f want got changed=0
    mkdir -p "$GEODATA_DIR"
    tmp=$(mktemp -d "$GEODATA_DIR/.dl.XXXXXX") || return 1
    for f in geoip.dat geosite.dat; do
        if ! curl -fsSL --retry 3 --max-time 300 -o "$tmp/$f" "$GEODATA_URL/$f" \
           || ! curl -fsSL --retry 3 --max-time 60 -o "$tmp/$f.sha256sum" "$GEODATA_URL/$f.sha256sum"; then
            echo "  ОШИБКА: не удалось скачать $f, базы не тронуты"
            rm -rf "$tmp"; return 1
        fi
        want=$(awk '{print $1}' "$tmp/$f.sha256sum")
        got=$(sha256sum "$tmp/$f" | awk '{print $1}')
        if [[ -z "$want" || "$want" != "$got" ]]; then
            echo "  ОШИБКА: $f не прошёл проверку sha256, базы не тронуты"
            rm -rf "$tmp"; return 1
        fi
    done
    for f in geoip.dat geosite.dat; do
        if cmp -s "$tmp/$f" "$GEODATA_DIR/$f"; then continue; fi
        chmod 644 "$tmp/$f"
        mv -f "$tmp/$f" "$GEODATA_DIR/$f"
        changed=1
    done
    rm -rf "$tmp"
    if [[ $changed -eq 1 ]]; then echo "  Базы скачаны и проверены"
    else echo "  Базы не изменились"; fi
    return 0
}

# Блок для конфиг-профиля панели: его вставляют в профиль сами, установщик
# в панель не ходит. Одна строка на вывод — чтобы скопировать целиком.
geodata_profile_block() {
    printf '"geodata": {"cron": "17 1 * * *", "outbound": "DIRECT", "assets": [{"url": "%s/geoip.dat", "file": "geoip.dat"}, {"url": "%s/geosite.dat", "file": "geosite.dat"}]}\n' \
        "$GEODATA_URL" "$GEODATA_URL"
}

# Возраст баз — для мониторинга: раз в 15 минут cron кладёт время изменения
# файлов в текстовый сборщик node_exporter. Обновление сломалось (пропал блок
# geodata в профиле, нода не видит GitHub) — мониторинг узнает об этом сам.
GEODATA_AGE_CRON="/etc/cron.d/rwmon-geodata"
GEODATA_PROM_DIR="/var/lib/prometheus/node-exporter"

geodata_age_cron() {
    cat > "$GEODATA_AGE_CRON" <<EOF
# fixerror-node: возраст geo-баз для node_exporter (алерт мониторинга «Geo-базы не обновляются»)
*/15 * * * * root d=$GEODATA_PROM_DIR; [ -d \$d ] && { for f in geoip geosite; do echo "rwmon_geodata_mtime_seconds{file=\"\$f.dat\"} \$(stat -c \%Y $GEODATA_DIR/\$f.dat 2>/dev/null || echo 0)"; done > \$d/rwmon-geodata.prom.tmp && mv \$d/rwmon-geodata.prom.tmp \$d/rwmon-geodata.prom; }
EOF
    chmod 644 "$GEODATA_AGE_CRON"
}

comp_geodata() {
    echo ">>> Geo-базы Loyalsoldier..."
    if ! geodata_download; then
        geodata_present || { echo "  [СБОЙ] баз нет — нода работала бы на встроенных"; return 1; }
        echo "  Прежние базы на месте — продолжаю с ними."
    fi
    geodata_present || { echo "  [СБОЙ] баз нет после скачивания"; return 1; }
    echo "  Базы на месте: $(du -ch "$GEODATA_DIR"/*.dat | tail -1 | cut -f1)"
    node_dir_perms
    geodata_age_cron

    # Прежнее обновление таймером перезапускало ноду. Теперь базы обновляет
    # ядро — таймер выключаем, чтобы не было двух обновлений и лишних
    # перезапусков. Файлы таймера и скрипт не удаляем.
    if geodata_legacy_timer; then
        systemctl disable --now geo-update.timer >>"$SETUP_LOG" 2>&1 || true
        echo "  Старый таймер geo-update выключен (файлы оставлены)"
    fi

    # Нода уже стоит, а каталог в compose не подключён — правим том в её
    # compose (остальное, и SECRET_KEY, не трогаем) и пересоздаём контейнер.
    # В полной установке не нужно: следующим шагом нода и так передеплоится.
    if [[ -z "${RH_FULL_INSTALL:-}" && -f /opt/remnanode/docker-compose.yml ]] && ! geodata_mounted; then
        echo "  Подключаю каталог баз к уже установленной ноде..."
        geodata_compose_fix /opt/remnanode/docker-compose.yml || return 1
        node_planned "подключение каталога geo-баз"
        if ! ( cd /opt/remnanode && docker compose up -d ) >>"$SETUP_LOG" 2>&1; then
            echo "  [СБОЙ] docker compose up не отработал (см. $SETUP_LOG)"
            return 1
        fi
        echo "  Нода пересоздана с каталогом баз"
    fi
    echo "  Обновлять базы будет ядро Xray. Добавьте в конфиг-профиль ноды в панели"
    echo "  (верхний уровень, рядом с \"inbounds\") этот блок:"
    echo "    $(geodata_profile_block)"
    return 0
}
