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
