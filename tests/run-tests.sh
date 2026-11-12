#!/bin/bash
# Прогон всех проверок, которые можно сделать без сервера.
# Запуск:  bash tests/run-tests.sh
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
FAILED=0
PASSED=0

# На Windows "python3" обычно существует как заглушка Microsoft Store:
# она ничего не запускает и возвращает ошибку. Поэтому мало найти команду в
# PATH — надо убедиться, что она реально работает.
# Такая же проверка есть в .githooks/pre-commit; менять надо оба места.
PY=""
for _cand in python3 python py; do
    if command -v "$_cand" >/dev/null 2>&1 && "$_cand" -c "import sys" >/dev/null 2>&1; then
        PY="$_cand"; break
    fi
done
if [[ -z "$PY" ]]; then
    printf '\033[31mНе найден работающий python\033[0m — он нужен для build.py и части тестов.\n'
    printf 'Пробовал: python3, python, py\n'
    exit 1
fi

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASSED=$((PASSED+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILED=$((FAILED+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Тестовый SSH-ключ. Проверка ключа в скрипте настоящая (через ssh-keygen),
# поэтому строка-пустышка не годится: с ней тесты проходили только там, где
# ssh-keygen не установлен, и падали на любой машине, где он есть.
TESTKEY=""
if command -v ssh-keygen >/dev/null 2>&1; then
    _kf=$(mktemp -u)
    ssh-keygen -q -t ed25519 -N "" -f "$_kf" <<< y >/dev/null 2>&1
    TESTKEY=$(cat "$_kf.pub" 2>/dev/null || true)
    rm -f "$_kf" "$_kf.pub"
fi
# Без ssh-keygen проверка ключа пропускается, поэтому годится любая непустая строка
TESTKEY="${TESTKEY:-ssh-ed25519 AAAAtest test@no-keygen}"

# --------------------------------------------------------------------------
head_ "1. Синтаксис"
# --------------------------------------------------------------------------
for f in lib/*.sh check.sh; do
    if bash -n "$f" 2>/dev/null; then ok "bash -n $f"; else bad "bash -n $f"; bash -n "$f"; fi
done

# --------------------------------------------------------------------------
head_ "2. Сборка"
# --------------------------------------------------------------------------
# Порядок важен: сначала проверяем ЗАКОММИЧЕННЫЙ setup.sh и только потом
# пересобираем. Если собрать первым, проверка сравнит файл сам с собой и
# будет проходить всегда — именно так она и работала вхолостую.
if "$PY" build.py --check >/dev/null 2>&1; then
    ok "setup.sh и check.sh собраны из текущего lib/"
else
    bad "собранные файлы устарели — пересоберите (python build.py) и закоммитьте"
fi
if "$PY" build.py >/dev/null 2>&1; then ok "build.py отработал"; else bad "build.py упал"; fi
if bash -n setup.sh 2>/dev/null; then ok "bash -n setup.sh"; else bad "bash -n setup.sh"; bash -n setup.sh; fi
if head -1 setup.sh | grep -q '^#!/bin/bash'; then ok "shebang на первой строке"; else bad "нет shebang"; fi

# Модули генерируют на сервере служебные скрипты, и внутри heredoc'ов лежат
# их собственные shebang'и. Сборщик однажды вырезал их все разом — файлы
# получались без первой строки, исполнялись через /bin/sh (где нет [[ ]])
# и молча не работали. Считаем: сборка убирает ровно один shebang и добавляет
# свой, значит количество обязано совпадать.
LIBSHE=$(grep -c '^#!/bin/bash' lib/*.sh 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
SETSHE=$(grep -c '^#!/bin/bash' setup.sh 2>/dev/null || echo 0)
if [[ "$LIBSHE" -eq "$SETSHE" ]]; then
    ok "shebang'и генерируемых скриптов на месте ($SETSHE)"
else
    bad "сборка потеряла shebang'и: в lib/ $LIBSHE, в setup.sh $SETSHE"
fi
# И структурно: первая строка каждого генерируемого скрипта — shebang
NOSHE=$(awk '/cat <<.*> \/usr\/local\/bin\// { f=NR; getline; if ($0 !~ /^#!\//) print f": "$0 }' setup.sh)
if [[ -n "$NOSHE" ]]; then
    bad "генерируемый скрипт начинается не с shebang:"
    echo "$NOSHE" | sed 's/^/      /'
else
    ok "каждый генерируемый скрипт начинается с shebang"
fi
if grep -qU $'\r' setup.sh; then bad "в setup.sh есть CRLF — на сервере сломается"; else ok "переводы строк LF"; fi

# --------------------------------------------------------------------------
head_ "3. Статическая проверка кодов возврата"
# --------------------------------------------------------------------------
if "$PY" tests/check_returns.py; then ok "ни одна функция не заканчивается голым условием"
else bad "есть функции, которые молча убьют скрипт"; fi

# Установка обязана задать все вопросы заранее: человек отвечает и уходит.
# Один read внутри comp_* — и скрипт замирает посреди работ, ожидая ввода.
if "$PY" tests/check_no_prompts.py; then ok "шаги установки не задают вопросов"
else bad "шаг установки остановится и будет ждать ввода"; fi

# --------------------------------------------------------------------------
head_ "4. Функции реально возвращают 0, когда спрашивать нечего"
# --------------------------------------------------------------------------
# Это тот самый сценарий повторной установки: все ответы уже сохранены,
# ни один вопрос не задаётся, и функция не должна вернуть ненулевой код.
RH_TEST_OUT=$(mktemp)
RH_LIB_ONLY=1 bash -c '
    set -e
    source "'"$ROOT"'/setup.sh"
    # всё заполнено — ни один read не должен сработать
    SERVER_LABEL="Finland 3 test"; PANEL_IP="1.2.3.4"; NODE_ROLE="reality"
    REMNA_SECRET="secret"; SSH_PUBLIC_KEY="'"$TESTKEY"'"
    ADMIN_USER="deploy"; SSH_PORT="45123"; ADMIN_PASS="pass"
    TG_BOT_TOKEN="123:ABC"; TG_CHAT_ID="-100123"; TG_TOPIC_ID="7"
    NONINTERACTIVE=1
    for fn in ask_panel_ip ask_secret ask_node_label ask_role validate_mtu ask_ssh_key \
              validate_ssh_params ask_ssh_params ask_telegram skip_step; do
        if ! "$fn" "проверка" >/dev/null 2>&1; then
            echo "НЕНУЛЕВОЙ КОД: $fn"
        fi
    done
    row "метка" "значение" >/dev/null || echo "НЕНУЛЕВОЙ КОД: row"
' > "$RH_TEST_OUT" 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    bad "загрузка функций упала (код $RC)"; sed 's/^/      /' "$RH_TEST_OUT"
elif grep -q "НЕНУЛЕВОЙ КОД" "$RH_TEST_OUT"; then
    bad "функции возвращают ненулевой код при заполненных ответах"
    sed 's/^/      /' "$RH_TEST_OUT"
else
    ok "все опросные функции возвращают 0"
fi
rm -f "$RH_TEST_OUT"

# --------------------------------------------------------------------------
head_ "5. Проверка ввода"
# --------------------------------------------------------------------------
VAL=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    NONINTERACTIVE=1
    ADMIN_USER="root"; SSH_PORT="99999"; validate_ssh_params >/dev/null 2>&1
    echo "$ADMIN_USER:$SSH_PORT"
')
if [[ "$VAL" == "vadim:8422" ]]; then ok "мусор в ADMIN_USER/SSH_PORT откатывается на дефолты"
else bad "validate_ssh_params вернула '$VAL', ожидалось 'vadim:8422'"; fi

# --------------------------------------------------------------------------
head_ "6. Нет хардкода портов в обход переменных"
# --------------------------------------------------------------------------
# Числа портов должны встречаться только там, где переменные объявляются.
# Иначе при смене порта половина скрипта продолжит смотреть на старый.
HARDCODED=$(grep -nwE '2222|6000|9443' lib/*.sh \
            | grep -v '^lib/00-header.sh' \
            | grep -v 'NODE_PORT\|WARP_PORT\|SELFSTEAL_PORT' \
            | grep -v ':[0-9]*:[[:space:]]*#' || true)
if [[ -n "$HARDCODED" ]]; then
    bad "порты зашиты мимо переменных:"
    echo "$HARDCODED" | sed 's/^/      /'
else
    ok "порты ноды и WARP везде через переменные"
fi

# --------------------------------------------------------------------------
head_ "7. Повторная установка доходит до конца (регрессия)"
# --------------------------------------------------------------------------
# Сценарий, который ломался: все ответы уже сохранены с прошлого раза,
# Telegram настроен, скрипт не задаёт ни одного вопроса — и обрывался молча
# сразу после "--- Telegram-уведомления ---", не дойдя до установки.
E2E=$(mktemp)
# Важно: режим именно ИНТЕРАКТИВНЫЙ (NONINTERACTIVE пустой) — в неинтерактивном
# блок с вызовом ask_telegram пропускается, и баг не воспроизводится.
# На stdin Enter на каждый вопрос (учётка/пароль/порт, ключи, warp-native,
# Psiphon и его страна, geo-базы) и "n" в конце.
printf '\n\n\n\n\n\n\n\n\n\n\n\n\n\n\nn\nn\nn\n' | RH_LIB_ONLY=1 bash -c '
    set -e
    source "'"$ROOT"'/setup.sh"
    SERVER_LABEL="Finland 3 test"; PANEL_IP="1.2.3.4"
    REMNA_SECRET="secret"; SSH_PUBLIC_KEY="'"$TESTKEY"'"
    ADMIN_USER="deploy"; SSH_PORT="45123"
    INSTALL_WARP="n"; INSTALL_SPEEDTEST="n"
    SETUP_TG="y"; TG_BOT_TOKEN="123:ABC"; TG_CHAT_ID="-100123"; TG_TOPIC_ID="7"; TG_PROXY=""
    INSTALL_STATE=$(mktemp); SETUP_LOG=$(mktemp); REPORT_FILE=$(mktemp)
    # rh_preflight тоже заглушка: он честно проверяет, что под ногами Ubuntu,
    # а тесты гоняются и на Windows, где apt-get нет вовсе
    for f in rh_preflight comp_swap comp_packages comp_user comp_agent comp_hostkeys comp_ssh comp_fail2ban comp_autoupdates \
             comp_geodata comp_warp_native comp_psiphon comp_time comp_mtu comp_ufw comp_sysctl comp_docker comp_disk comp_speedtest \
             comp_warp comp_node comp_web_site comp_node_pull comp_telegram notify_telegram get_server_ip reboot \
             components_menu; do
        eval "$f(){ return 0; }"
    done
    full_install >/dev/null
    echo "ДОШЛИ ДО КОНЦА"
' > "$E2E" 2>&1
if grep -q "ДОШЛИ ДО КОНЦА" "$E2E"; then
    ok "повторная установка с заполненным Telegram не обрывается"
else
    bad "повторная установка обрывается (тот самый баг):"
    tail -15 "$E2E" | sed 's/^/      /'
fi
rm -f "$E2E"

# --------------------------------------------------------------------------
head_ "8. Авария внутри функции объясняется, а не проходит молча"
# --------------------------------------------------------------------------
# Без "set -E" ERR-трап не наследуется функциями: скрипт просто исчезал,
# не написав ни строки о том, что и где сломалось.
TRAP_OUT=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SETUP_LOG=/tmp/rh-test.log
    broken() { ls /definitely-no-such-path-here; }
    broken
' 2>&1 || true)
if grep -q "ОШИБКА — установка прервана" <<< "$TRAP_OUT" \
   && grep -q "в функции:    broken()" <<< "$TRAP_OUT"; then
    ok "падение внутри функции печатает команду и имя функции"
else
    bad "трап не объясняет падение внутри функции:"
    sed 's/^/      /' <<< "$TRAP_OUT"
fi

# --------------------------------------------------------------------------
head_ "9. Меню переживает падение компонента"
# --------------------------------------------------------------------------
# ERR-трап срабатывает даже при set +e, поэтому раньше любая ненулевая команда
# внутри comp_* убивала весь установщик прямо из меню. menu_step вызывает
# компонент через "if" — там подавлены и set -e, и трап.
MENU=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SETUP_LOG=/tmp/rh-test.log
    broken_component() { false; }
    menu_step "тестовый компонент" broken_component
    echo "МЕНЮ ВЫЖИЛО"
' 2>&1 || true)
if grep -q "МЕНЮ ВЫЖИЛО" <<< "$MENU"; then
    ok "падение компонента не убивает меню"
else
    bad "падение компонента обрывает установщик:"; sed 's/^/      /' <<< "$MENU"
fi

# --------------------------------------------------------------------------
head_ "10. Сохранённые ответы не выполняются как команды"
# --------------------------------------------------------------------------
# install.conf читается через source от root. Значение вида a$(команда) раньше
# выполнялось при следующем запуске, а пароль с $ молча портился.
# Значения передаём через окружение в одинарных кавычках, иначе подстановка
# сработает ещё в самом тесте и мы проверим не то.
INJ=$(RH_LIB_ONLY=1 \
      TESTSECRET='a$(id -u)b' \
      TESTPROXY='socks5h://user:pa$$word@host:1080' \
      bash -c '
    source "'"$ROOT"'/setup.sh"
    INSTALL_STATE=$(mktemp)
    DOMAIN="example.com"; SUBDOMAIN="n1"; PANEL_IP="1.2.3.4"
    REMNA_SECRET="$TESTSECRET"
    TG_PROXY="$TESTPROXY"
    save_state
    ( source "$INSTALL_STATE"; echo "SECRET=$REMNA_SECRET"; echo "PROXY=$TG_PROXY" )
    rm -f "$INSTALL_STATE"
' 2>&1 || true)
if grep -q 'SECRET=a$(id -u)b' <<< "$INJ" && grep -q 'PROXY=socks5h://user:pa$$word@host:1080' <<< "$INJ"; then
    ok "значения сохраняются дословно, подстановка команд не срабатывает"
else
    bad "сохранённые значения портятся или выполняются:"; sed 's/^/      /' <<< "$INJ"
fi

# --------------------------------------------------------------------------
head_ "11. Порт сверяется точно, а не по подстроке"
# --------------------------------------------------------------------------
PORTCHK=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    ss() { printf "LISTEN 0 128 0.0.0.0:22220 0.0.0.0:*\n"; }
    if port_is_listening 2222; then echo "ЛОЖНОЕ СРАБАТЫВАНИЕ"; else echo "ТОЧНО"; fi
    ss() { printf "LISTEN 0 128 0.0.0.0:2222 0.0.0.0:*\n"; }
    if port_is_listening 2222; then echo "НАШЁЛ"; else echo "НЕ НАШЁЛ"; fi
' 2>&1 || true)
if grep -q "ТОЧНО" <<< "$PORTCHK" && grep -q "НАШЁЛ" <<< "$PORTCHK"; then
    ok "22220 не засчитывается за 2222"
else
    bad "проверка порта работает по подстроке:"; sed 's/^/      /' <<< "$PORTCHK"
fi

# --------------------------------------------------------------------------
head_ "12. Битый SSH-ключ отбраковывается"
# --------------------------------------------------------------------------
# Раньше проверкой было «строка непустая»: обрезанный при копировании ключ
# проходил, скрипт отключал пароли и запирал сервер.
if ! command -v ssh-keygen >/dev/null 2>&1; then
    printf '  — ssh-keygen не установлен, пропускаю\n'
else
    GOODKEY="$TESTKEY"
    KEYCHK=$(RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        ssh_key_valid "ssh-ed25519 AAAAOBREZANNYY" && echo "ПЛОХОЙ ПРИНЯТ" || echo "плохой отклонён"
        ssh_key_valid "" && echo "ПУСТОЙ ПРИНЯТ" || echo "пустой отклонён"
        ssh_key_valid "'"$GOODKEY"'" && echo "хороший принят" || echo "ХОРОШИЙ ОТКЛОНЁН"
    ' 2>&1 || true)
    if grep -q "плохой отклонён" <<< "$KEYCHK" && grep -q "пустой отклонён" <<< "$KEYCHK" \
       && grep -q "хороший принят" <<< "$KEYCHK"; then
        ok "проверка SSH-ключа отличает настоящий от мусора"
    else
        bad "проверка SSH-ключа работает неверно:"; sed 's/^/      /' <<< "$KEYCHK"
    fi
fi

# --------------------------------------------------------------------------
head_ "13. Диагностика ничего не меняет"
# --------------------------------------------------------------------------
# check.sh запускают на живых нодах в рабочее время. Любая изменяющая команда
# внутри него превращает безобидную проверку в незапланированную правку.
if "$PY" tests/check_readonly.py; then ok "check.sh только читает"
else bad "в check.sh просочились изменяющие команды"; fi

# grep -c при нуле совпадений печатает "0" И возвращает ненулевой код, поэтому
# "|| echo 0" даёт "0\n0" и ломает арифметику уже во время работы скрипта.
BADCOUNT=$(grep -nE 'grep -c[^|]*\|\| *echo' check.sh lib/*.sh 2>/dev/null || true)
if [[ -n "$BADCOUNT" ]]; then
    bad "grep -c с '|| echo' — при нуле совпадений получится две строки:"
    echo "$BADCOUNT" | sed 's/^/      /'
else
    ok "счётчики grep -c не ломаются на нуле совпадений"
fi

# --------------------------------------------------------------------------
head_ "14. Общие шаблоны нод FixError"
# --------------------------------------------------------------------------
TPLD=$(mktemp -d)
# remnawave-notify — байт в байт как на панели и остальных нодах
RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    NOTIFY_BIN="'"$TPLD"'/rn"; chown(){ :; }
    notify_write_script
' >/dev/null 2>&1
if cmp -s "$TPLD/rn" tests/remnawave-notify.ref; then
    ok "remnawave-notify совпадает с эталоном (tests/remnawave-notify.ref)"
else
    bad "remnawave-notify разошёлся с эталоном — правка должна идти и на панель"
fi

# sysctl: резерв портов из переменных, IPv6-ключи только при живом стеке
SYS=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SSH_PORT=8422; RH_IPV6_PROC="'"$TPLD"'/no-ipv6"
    sysctl_render
')
if grep -qx 'net.ipv4.ip_local_reserved_ports = 8422,2222,9443,6000' <<< "$SYS"; then
    ok "sysctl резервирует порты SSH, ноды, self-steal и WARP"
else
    bad "резерв портов неверен: $(grep reserved <<< "$SYS")"
fi
grep -q 'disable_ipv6' <<< "$SYS" && bad "ключи ipv6 пишутся без стека ipv6 (sysctl --system упадёт)" \
                                    || ok "без стека IPv6 его ключи не пишутся"

# Харденинг SSH: Port не дублируется, если он уже в основном конфиге
HARD=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SSHD_MAIN="'"$TPLD"'/sshd_config"; SSH_PORT=8422
    printf "Include /etc/ssh/sshd_config.d/*.conf\n#Port 22\n" > "$SSHD_MAIN"
    echo "--- без Port"; ssh_harden_render
    printf "Port 8422\n" >> "$SSHD_MAIN"
    echo "--- с Port"; ssh_harden_render
')
if [[ $(awk '/--- без Port/{f=1;next} /--- с Port/{f=0} f' <<< "$HARD" | grep -c '^Port 8422$') -eq 1 \
   && $(awk '/--- с Port/{f=1;next} f' <<< "$HARD" | grep -c '^Port') -eq 0 ]]; then
    ok "Port пишется, только если его нет в sshd_config (иначе «Address already in use»)"
else
    bad "Port в харденинге задвоится:"; sed 's/^/      /' <<< "$HARD"
fi
# Чужой Port в основном конфиге гасится, свой остаётся
PFIX=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SSHD_MAIN="'"$TPLD"'/sshd2"; SSH_PORT=8422
    printf "Port 22\nPermitRootLogin yes\n" > "$SSHD_MAIN"
    ssh_main_port_fix >/dev/null; cat "$SSHD_MAIN"
')
grep -q '^# отключено харденингом fixerror-node: Port 22' <<< "$PFIX" \
    && ok "чужой Port 22 в sshd_config закомментирован" || bad "Port 22 остался: $PFIX"

# Торренты: вставляются после «End required lines», повторный запуск не плодит строк
cat > "$TPLD/before.rules" <<'RULES'
*filter
:ufw-before-input - [0:0]
:ufw-before-output - [0:0]
# End required lines

# allow all on loopback
-A ufw-before-input -i lo -j ACCEPT
-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
COMMIT
RULES
TOR=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    UFW_BEFORE="'"$TPLD"'/before.rules"
    torrent_rules_apply && torrent_rules_apply && torrent_rules_count
')
if [[ "$TOR" == "6" ]]; then ok "правила против торрентов: 6 строк и после повторного запуска"
else bad "правил против торрентов $TOR вместо 6"; fi
if awk '/BitTorrent protocol/{t=NR} /ESTABLISHED/{e=NR} END{exit !(t && e && t<e)}' "$TPLD/before.rules"; then
    ok "торренты режутся до правила ESTABLISHED"
else
    bad "правила против торрентов стоят после ESTABLISHED — открытые соединения пройдут"
fi

# Сайт: оба варианта проходят базовые проверки и не путают роли
SITE_R=$(RH_LIB_ONLY=1 bash -c 'source "'"$ROOT"'/setup.sh"; NODE_ROLE=reality; validate_role; web_render_site')
SITE_C=$(RH_LIB_ONLY=1 bash -c 'source "'"$ROOT"'/setup.sh"; NODE_ROLE=cdn; CDN_DOMAIN=origin.example.com; validate_role; web_render_site')
if head -1 <<< "$SITE_R" | grep -qF 'fixerror-node:' \
   && grep -q 'listen 127.0.0.1:9443 ssl http2 proxy_protocol default_server' <<< "$SITE_R" \
   && grep -q 'server_name check.safeline24.com gateway.safeline24.com;' <<< "$SITE_R" \
   && ! grep -q 'xhttp_backend' <<< "$SITE_R"; then
    ok "сайт Reality-ноды: self-steal на 127.0.0.1:9443, метка установщика первой строкой"
else
    bad "сайт Reality-ноды собран неверно"
fi
if grep -q 'server 127.0.0.1:4443;' <<< "$SITE_C" && grep -q 'location /api/v1/stream/ {' <<< "$SITE_C" \
   && grep -q 'server_name origin.example.com;' <<< "$SITE_C" && ! grep -q '9443' <<< "$SITE_C"; then
    ok "сайт CDN-ноды: XHTTP проксируется в Xray, self-steal не объявлен"
else
    bad "сайт CDN-ноды собран неверно"
fi
# Скобки сбалансированы — грубая, но полезная защита от сломанного heredoc
for v in R C; do
    eval "body=\$SITE_$v"
    o=$(tr -cd '{' <<< "$body" | wc -c); c=$(tr -cd '}' <<< "$body" | wc -c)
    [[ "$o" -eq "$c" ]] && ok "сайт ($v): фигурные скобки сбалансированы" || bad "сайт ($v): { $o, } $c"
done
ROLE_BAD=$(RH_LIB_ONLY=1 bash -c 'source "'"$ROOT"'/setup.sh"; NONINTERACTIVE=1; NODE_ROLE=cdn; CDN_DOMAIN=""; ask_role >/dev/null 2>&1 && echo ПРИНЯЛ || echo ОТКАЗ')
[[ "$ROLE_BAD" == "ОТКАЗ" ]] && ok "CDN-нода без домена в файле ответов останавливает установку" \
                             || bad "CDN-нода без домена принята"
rm -rf "$TPLD"

# --------------------------------------------------------------------------
head_ "15. Строка ключа ноды для панели"
# --------------------------------------------------------------------------
NPD=$(mktemp -d)
if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "  — ssh-keygen не установлен, проверки ключа ноды пропускаю"
else
LINE=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    NODE_PULL_DIR="'"$NPD"'"; SERVER_LABEL="Finland 3 hshp"; SERVER_IP="203.0.113.7"
    node_pull_key >/dev/null && node_pull_panel_line
' 2>/dev/null)
if [[ "$LINE" =~ ^restrict,from=\"203\.0\.113\.7\",command=\"/bin/cat\ /var/lib/node-pull/bundle\.tar\.gz\"\ ssh-ed25519\ [A-Za-z0-9+/=]+\ node-pull\ Finland\ 3\ hshp$ ]]; then
    ok "строка для authorized_keys панели: restrict, from=IP ноды, только cat набора"
else
    bad "строка для панели неверна: $LINE"
fi
P1=$(stat -c %a "$NPD/key" 2>/dev/null); KEY1=$(cat "$NPD/key.pub" 2>/dev/null)
RH_LIB_ONLY=1 bash -c 'source "'"$ROOT"'/setup.sh"; NODE_PULL_DIR="'"$NPD"'"; SERVER_LABEL=x; node_pull_key' >/dev/null 2>&1
[[ -n "$KEY1" && "$KEY1" == "$(cat "$NPD/key.pub")" ]] && ok "ключ ноды не пересоздаётся (строка на панели осталась бы чужой)" \
                                        || bad "повторный запуск сменил ключ ноды"
[[ "$P1" == "600" ]] && ok "ключ ноды с правами 600" || bad "ключ ноды с правами $P1"
fi
LBL=$(RH_LIB_ONLY=1 bash -c 'source "'"$ROOT"'/setup.sh"; SERVER_LABEL="Fin\"land \$(id) 3"; validate_node_label; echo "$SERVER_LABEL"')
[[ "$LBL" == "Finland (id) 3" ]] && ok "из имени ноды вырезаются кавычки и \$ (оно попадает в файлы)" \
                                 || bad "имя ноды не очищено: $LBL"
# Скрипт node-pull собирается с адресом панели и проходит bash -n
RH_LIB_ONLY=1 bash -c 'source "'"$ROOT"'/setup.sh"; NODE_PULL_BIN="'"$NPD"'/np"; PANEL_IP=198.51.100.9; node_pull_write_script' >/dev/null 2>&1
if bash -n "$NPD/np" 2>/dev/null && grep -qx 'PANEL=198.51.100.9' "$NPD/np" && grep -qx 'PORT=8422' "$NPD/np"; then
    ok "node-pull собран с адресом и портом панели и синтаксически корректен"
else
    bad "node-pull собран неверно"
fi
rm -rf "$NPD"

# --------------------------------------------------------------------------
head_ "16. Диагностика в меню и в check.sh — один и тот же код"
# --------------------------------------------------------------------------
# Смысл всей затеи: человек качает ОДИН скрипт и тыкает меню. Если бы
# диагностика жила в двух файлах, копии разошлись бы, и «проверил одним,
# починил другим» перестало бы работать.
BODY_A=$(awk '/^rh_check\(\) \{/,/^\}/' setup.sh | md5sum | cut -d' ' -f1)
BODY_B=$(awk '/^rh_check\(\) \{/,/^\}/' check.sh | md5sum | cut -d' ' -f1)
if [[ -n "$BODY_A" && "$BODY_A" == "$BODY_B" ]]; then
    ok "rh_check в setup.sh и check.sh совпадают байт в байт"
else
    bad "rh_check разъехался между setup.sh и check.sh (пересоберите: python build.py)"
fi

# --------------------------------------------------------------------------
head_ "17. Диагностика не ломает установщик"
# --------------------------------------------------------------------------
# rh_check снимает себе set -e и ERR-трап: без этого половина её проверок,
# штатно возвращающих ненулевой код, роняла бы установщик. Поэтому её
# ОБЯЗАНЫ звать в подоболочке — иначе она разоружит обработчик ошибок
# на весь оставшийся сеанс, и следующая настоящая авария пройдёт молча.
DIAG=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SETUP_LOG=/tmp/rh-test.log
    rh_check() { set +e; trap - ERR; echo "диагностика"; return 1; }
    menu_check >/dev/null 2>&1
    echo "МЕНЮ ВЫЖИЛО"
    broken() { ls /definitely-no-such-path-here; }
    broken
' 2>&1 || true)
if grep -q "МЕНЮ ВЫЖИЛО" <<< "$DIAG" && grep -q "ОШИБКА — установка прервана" <<< "$DIAG"; then
    ok "диагностика не роняет меню и не разоружает обработчик ошибок"
else
    bad "диагностика зовётся не в подоболочке:"; sed 's/^/      /' <<< "$DIAG"
fi

# --------------------------------------------------------------------------
head_ "18. Починка трогает SSH только когда харденинг слетел"
# --------------------------------------------------------------------------
# Хостер переписывает конфиг sshd своим дроп-ином, root и пароли снова
# открыты. Починка обязана это заметить и вернуть харденинг — но на здоровой
# ноде не перезапускать sshd впустую, а на ноде без харденинга не накатывать
# его молча (он отключает вход по паролю и требует проверенный ключ).
SSHREP=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    TMPD=$(mktemp -d)
    SSH_HARDEN_FILE="$TMPD/01-hardening.conf"
    SSH_PORT=8422
    sshd_listens_on() { return 0; }
    comp_ssh() { echo "ЧИНИТ"; return 0; }

    echo "== без файла харденинга"
    sshd() { printf "port 22\npermitrootlogin yes\npasswordauthentication yes\n"; }
    repair_ssh_hardening

    echo "Port 8422" > "$SSH_HARDEN_FILE"
    echo "== харденинг на месте"
    sshd() { printf "port 8422\npermitrootlogin no\npasswordauthentication no\n"; }
    repair_ssh_hardening

    echo "== харденинг слетел"
    sshd() { printf "port 8422\npermitrootlogin yes\npasswordauthentication no\n"; }
    repair_ssh_hardening
    rm -rf "$TMPD"
' 2>&1 || true)
S1=$(sed -n '/== без файла/,/== харденинг на месте/p' <<< "$SSHREP")
S2=$(sed -n '/== харденинг на месте/,/== харденинг слетел/p' <<< "$SSHREP")
S3=$(sed -n '/== харденинг слетел/,$p' <<< "$SSHREP")
if grep -q "ЧИНИТ" <<< "$S1"; then
    bad "починка молча накатывает харденинг на ноду, где его не было:"; sed 's/^/      /' <<< "$SSHREP"
elif grep -q "ЧИНИТ" <<< "$S2"; then
    bad "починка дёргает sshd на здоровой ноде:"; sed 's/^/      /' <<< "$SSHREP"
elif ! grep -q "ЧИНИТ" <<< "$S3"; then
    bad "починка НЕ заметила, что харденинг слетел:"; sed 's/^/      /' <<< "$SSHREP"
else
    ok "SSH чинится ровно тогда, когда сломан"
fi

# Порт для восстановления берётся из НАШЕГО файла харденинга, а не из sshd -T:
# чужой дроп-ин, читающийся раньше, перебивает Port — и починка закрепила бы
# чужой порт вместо того, чтобы вернуть свой.
PORTSRC=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    TMPD=$(mktemp -d)
    SSH_HARDEN_FILE="$TMPD/01-hardening.conf"; echo "Port 8422" > "$SSH_HARDEN_FILE"
    sshd() { printf "port 22\n"; }          # чужой дроп-ин перебил наш Port
    ufw() { :; }; find() { :; }; ls() { :; }
    detect_existing_setup >/dev/null 2>&1
    echo "SSH_PORT=$SSH_PORT"
    rm -rf "$TMPD"
' 2>&1 || true)
if grep -q "SSH_PORT=8422" <<< "$PORTSRC"; then
    ok "порт для восстановления берётся из файла харденинга, а не из чужого дроп-ина"
else
    bad "починка взяла чужой порт: $PORTSRC"
fi

# А на ноде, где харденинга никогда не было, файла нет — и чтение порта не
# должно ронять скрипт. Ровно так и было: awk без файла возвращает 2, set -e
# убивал установщик ещё до показа меню.
NOFILE=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SSH_HARDEN_FILE="/nonexistent/01-hardening.conf"
    sshd() { printf "port 2222\n"; }
    ufw() { :; }; find() { :; }; ls() { :; }
    detect_existing_setup >/dev/null 2>&1
    echo "ДОШЛИ: SSH_PORT=$SSH_PORT"
' 2>&1 || true)
if grep -q "ДОШЛИ: SSH_PORT=2222" <<< "$NOFILE"; then
    ok "без файла харденинга чтение порта не роняет установщик"
else
    bad "чтение порта падает, когда файла харденинга нет:"; sed 's/^/      /' <<< "$NOFILE"
fi

# --------------------------------------------------------------------------
head_ "19. Конфиг сайта nginx: чужое не теряется, сломанное откатывается"
# --------------------------------------------------------------------------
WT=$(mktemp -d)
web_run() {   # $1 — что вернёт nginx -t (0/1); печатает итог и состояние дерева
    RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        T="'"$WT"'"
        NGINX_AVAIL="$T/avail"; NGINX_ENABLED="$T/enabled"; RH_BACKUP_DIR="$T/backup"
        NGINX_SSL="$T/ssl"; STUB_ROOT="$T/www"; SETUP_LOG=/dev/null
        mkdir -p "$NGINX_AVAIL" "$NGINX_ENABLED"
        NODE_ROLE=reality
        nginx(){ [[ "$1" == "-t" ]] && return '"$1"'; return 0; }
        systemctl(){ return 0; }
        openssl(){ local o; while [[ $# -gt 0 ]]; do case "$1" in -keyout|-out) o="$2"; echo x > "$o"; shift;; esac; shift; done; return 0; }
        if comp_web_site >/dev/null 2>&1; then echo "ИТОГ=OK"; else echo "ИТОГ=FAIL"; fi
        [[ -L "$NGINX_ENABLED/stub.conf" ]] && echo "ОПУБЛИКОВАН"
        head -1 "$NGINX_AVAIL/stub.conf" 2>/dev/null
        ls "$RH_BACKUP_DIR" 2>/dev/null | sed "s/^/БЭКАП:/"
    ' 2>&1
}
# Чистый сервер: пишет, публикует, кладёт временный сертификат и заглушку
rm -rf "$WT"/*; R=$(web_run 0)
if grep -q "ИТОГ=OK" <<< "$R" && grep -q "ОПУБЛИКОВАН" <<< "$R" && [[ -s "$WT/ssl/fullchain.pem" && -f "$WT/www/index.html" ]]; then
    ok "чистый сервер: конфиг записан и опубликован, временный сертификат на месте"
else
    bad "чистый сервер: $R"
fi
# Чужой stub.conf без метки: копия в бэкап, потом перезапись
rm -rf "$WT"/*; mkdir -p "$WT/avail"; echo "server { listen 81; } # чужой" > "$WT/avail/stub.conf"
R=$(web_run 0)
if grep -q "^БЭКАП:stub.conf\." <<< "$R" && grep -q "чужой" "$WT"/backup/stub.conf.* 2>/dev/null; then
    ok "чужой stub.conf перед перезаписью скопирован в бэкап"
else
    bad "чужой конфиг затёрт без копии: $R"
fi
# nginx -t не прошёл: прежний файл возвращается
rm -rf "$WT"/*; mkdir -p "$WT/avail"; echo "ПРЕЖНИЙ" > "$WT/avail/stub.conf"
R=$(web_run 1)
if grep -q "ИТОГ=FAIL" <<< "$R" && grep -qx "ПРЕЖНИЙ" "$WT/avail/stub.conf"; then
    ok "nginx -t не прошёл — прежний конфиг возвращён"
else
    bad "после провала nginx -t конфиг не вернулся: $R"
fi
# Своего конфига не было, nginx -t не прошёл — снимаем с публикации
rm -rf "$WT"/*; R=$(web_run 1)
if grep -q "ИТОГ=FAIL" <<< "$R" && ! grep -q "ОПУБЛИКОВАН" <<< "$R"; then
    ok "новый конфиг, который nginx не принял, снят с публикации"
else
    bad "сломанный конфиг остался опубликованным: $R"
fi
rm -rf "$WT"

# --------------------------------------------------------------------------
head_ "20. Ответы с уже настроенной ноды"
# --------------------------------------------------------------------------
DT=$(mktemp -d)
mkdir -p "$DT/enabled"
cat > "$DT/enabled/origin.example.com.conf" <<'NGX'
upstream xhttp_backend {
    server 127.0.0.1:4443;
}
server {
    listen 443 ssl http2;
    server_name origin.example.com;
    location /assets/ { }
    location /api/v1/stream/ {
        proxy_pass http://xhttp_backend;
    }
}
NGX
cat > "$DT/notify.env" <<'ENV'
TG_BOT_TOKEN="1:AA"
TG_CHAT_ID="-1001"
TG_TOPIC_ID="16920"
TG_PROXY=""
SERVER_LABEL="CDN 1 Switzerland"
ENV
DET=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    NGINX_ENABLED="'"$DT"'/enabled"; NOTIFY_ENV="'"$DT"'/notify.env"; NODE_PULL_DIR="'"$DT"'/np"
    NODE_PULL_BIN="'"$DT"'/none"
    ufw(){ echo "2222/tcp ALLOW 198.51.100.20"; }; sshd(){ :; }
    SSH_PORT_DETECTED=1; ADMIN_USER_DETECTED=1
    detect_existing_setup
    echo "$NODE_ROLE|$CDN_DOMAIN|$CDN_PATH|$CDN_XHTTP_PORT|$PANEL_IP|$SERVER_LABEL|$TG_TOPIC_ID|$SETUP_TG"
' 2>&1)
if [[ "$DET" == "cdn|origin.example.com|/api/v1/stream/|4443|198.51.100.20|CDN 1 Switzerland|16920|y" ]]; then
    ok "роль, домен CDN, путь XHTTP, панель и Telegram вычитаны с ноды"
else
    bad "вычитано не то: $DET"
fi
rm -rf "$DT"

# --------------------------------------------------------------------------
head_ "21. Группа docker у админ-учётки"
# --------------------------------------------------------------------------
# На ноде, где Docker стоял ДО установщика, comp_docker выходил сразу после
# "Docker уже установлен" и не доходил до usermod. Пользователь получал
# permission denied на /var/run/docker.sock, а диагностика молчала.
dg() {   # $1 — группы пользователя; печатает, что сделала функция
    RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        ADMIN_USER="vadim"
        id() { [[ "$1" == "-nG" ]] && echo "'"$1"'"; return 0; }
        getent() { return 0; }
        usermod() { echo "USERMOD: $*"; }
        docker_group_member
    ' 2>&1 || true
}
R=$(dg "vadim sudo")
if grep -q "USERMOD: -aG docker vadim" <<< "$R"; then
    ok "учётку без группы docker добавляют в группу"
else
    bad "в группу docker не добавили: $R"
fi
R=$(dg "vadim sudo docker")
if grep -q "USERMOD" <<< "$R"; then
    bad "usermod зовётся повторно, хотя пользователь уже в группе: $R"
else
    ok "повторно в группу не добавляют"
fi

# Docker уже установлен — это НЕ повод пропустить группу
R=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SETUP_LOG=/dev/null
    command() { [[ "${2:-}" == "docker" ]] && return 0; return 1; }
    systemctl() { return 0; }
    docker() { return 0; }          # демон отвечает
    docker_group_member() { echo "ГРУППА ПРОВЕРЕНА"; }
    comp_docker
' 2>&1 || true)
if grep -q "ГРУППА ПРОВЕРЕНА" <<< "$R"; then
    ok "при уже установленном Docker группа всё равно проверяется"
else
    bad "comp_docker выходит, не проверив группу:"; sed 's/^/      /' <<< "$R"
fi

# Скрипт get.docker.com возвращает успех, ничего не установив, если apt занят.
# Шаг светился зелёным, а следом «docker: command not found».
R=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SETUP_LOG=/dev/null
    curl() { return 0; }; sh() { return 0; }; systemctl() { return 0; }
    command() { return 1; }          # docker так и не появился
    comp_docker && echo "ЗЕЛЁНЫЙ" || echo "КРАСНЫЙ"
' 2>&1 || true)
if grep -q "КРАСНЫЙ" <<< "$R"; then
    ok "шаг Docker краснеет, если докера в системе так и нет"
else
    bad "шаг Docker зелёный без докера:"; sed 's/^/      /' <<< "$R"
fi

# И починка обязана это чинить: на старых нодах это типовая находка
R=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SETUP_LOG=$(mktemp); NONINTERACTIVE=1
    SUBDOMAIN="n1"; DOMAIN="example.com"; SUMMARY=()
    repair_perms() { return 0; }; repair_ssh_hardening() { return 0; }
    repair_verify() { return 0; }; comp_telegram() { return 0; }
    comp_panel_watch() { return 0; }; save_state() { return 0; }
    nginx_advise() { return 0; }
    nginx_needs_attention() { return 1; }
    getent() { return 0; }
    id() { return 0; }
    docker_group_member() { echo "ЧИНИЛ ГРУППУ"; }
    ADMIN_USER="vadim"
    run_repair
    cat "$SETUP_LOG"; rm -f "$SETUP_LOG"
' 2>&1 || true)
if grep -q "ЧИНИЛ ГРУППУ" <<< "$R"; then
    ok "починка проверяет группу docker"
else
    bad "починка не трогает группу docker"
fi

# --------------------------------------------------------------------------
head_ "22. Починка показывает план и спрашивает"
# --------------------------------------------------------------------------
# Пункт меню — одна кнопка. Раньше по ней сразу начинались правки, и человек
# узнавал о них по факту. Теперь сначала план, потом вопрос.
repair_run() {   # $1 — что подать на stdin, $2 — доп. код перед запуском
    printf '%b' "$1" | RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        SETUP_LOG=$(mktemp); NONINTERACTIVE=""
        SUBDOMAIN="n1"; DOMAIN="example.com"; ADMIN_USER="vadim"
        SSH_HARDEN_FILE=$(mktemp); SUMMARY=()
        NOTIFY_ENV=/nonexistent; PANEL_ENV=/nonexistent
        getent() { return 0; }; id() { return 0; }
        save_state() { return 0; }
        nginx_needs_attention() { return 1; }
        repair_perms() { echo "ВЫПОЛНЕН: права"; }
        repair_ssh_hardening() { echo "ВЫПОЛНЕН: ssh"; }
        docker_group_member() { echo "ВЫПОЛНЕН: docker"; }
        repair_verify() { echo "ВЫПОЛНЕН: проверка"; }
        '"${2:-}"'
        run_repair
        cat "$SETUP_LOG"          # вывод шагов теперь оседает в логе
        rm -f "$SSH_HARDEN_FILE" "$SETUP_LOG"
    ' 2>&1 || true
}

R=$(repair_run 'n\n')
if grep -q "БУДЕТ СДЕЛАНО" <<< "$R" && grep -q "не тронет" <<< "$R"; then
    ok "план печатается до вопроса"
else
    bad "плана нет:"; sed 's/^/      /' <<< "$R"
fi
if grep -q "ВЫПОЛНЕН" <<< "$R"; then
    bad "починка начала работать, хотя ответили «нет»:"; grep ВЫПОЛНЕН <<< "$R" | sed 's/^/      /'
else
    ok "на «нет» ни один шаг не выполняется"
fi

R=$(repair_run 'y\n')
if grep -q "ВЫПОЛНЕН: права" <<< "$R" && grep -q "ВЫПОЛНЕН: проверка" <<< "$R"; then
    ok "на «да» выполняются все шаги плана"
else
    bad "шаги не выполнились:"; sed 's/^/      /' <<< "$R"
fi

# s — пройтись по шагам; отказываемся от первого, соглашаемся на остальные
R=$(repair_run 's\nn\ny\ny\ny\n')
if ! grep -q "ВЫПОЛНЕН: права" <<< "$R" && grep -q "ВЫПОЛНЕН: проверка" <<< "$R"; then
    ok "по шагам можно отключить отдельный пункт"
else
    bad "выбор по шагам не работает:"; grep -E 'ВЫПОЛНЕН|делать' <<< "$R" | sed 's/^/      /'
fi

# А неинтерактивный --repair обязан работать молча и делать всё
R=$(repair_run '' 'NONINTERACTIVE=1')
if grep -q "ВЫПОЛНЕН: права" <<< "$R" && ! grep -q "Выполнить?" <<< "$R"; then
    ok "--repair не спрашивает и делает всё"
else
    bad "неинтерактивный режим сломан:"; sed 's/^/      /' <<< "$R"
fi

# План обязан называть то, чего на ноде нет, а не молча это скрывать
if grep -q "ПРОПУЩУ" <<< "$R"; then
    ok "пропущенные шаги названы в плане"
else
    bad "план не показывает, что пропускается"
fi

# --------------------------------------------------------------------------
head_ "23. Объяснение сбоя попадает в лог"
# --------------------------------------------------------------------------
# Настоящий случай: харденинг SSH не применился, объяснение напечаталось на
# экран, print_summary экран очистил — и в сводке осталось «см. лог», а в логе
# про sshd ни строчки. Вывод шага обязан оседать в логе.
LOGT=$(mktemp)
STEP=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SETUP_LOG="'"$LOGT"'"; SUMMARY=()
    падучий() { echo "  [СБОЙ] порт применился, но харденинг — нет"; return 1; }
    do_step "Харденинг SSH" падучий
    printf "%s\n" "${SUMMARY[@]}"
' 2>&1 || true)
sleep 1   # tee пишет в отдельном процессе
if grep -q "харденинг — нет" "$LOGT"; then
    ok "вывод упавшего шага сохраняется в логе"
else
    bad "объяснение сбоя в лог не попало:"; sed 's/^/      /' "$LOGT"
fi
if grep -q "харденинг — нет" <<< "$STEP"; then
    ok "и на экране он тоже остаётся"
else
    bad "вывод шага пропал с экрана"
fi
rm -f "$LOGT"

# Переменные, которые шаг выставил, обязаны дожить до отчёта: если запускать
# шаг через конвейер, он уйдёт в подоболочку и отчёт получит пустоту.
VARS=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SETUP_LOG=/dev/null; SUMMARY=()
    ставит_переменную() { SSH_HARDENED=1; ADMIN_PASS="секрет"; return 0; }
    do_step "шаг" ставит_переменную
    echo "HARDENED=${SSH_HARDENED:-пусто} PASS=${ADMIN_PASS:-пусто}"
' 2>&1 || true)
if grep -q "HARDENED=1 PASS=секрет" <<< "$VARS"; then
    ok "переменные шага доживают до отчёта"
else
    bad "шаг выполняется в подоболочке, отчёт останется пустым: $VARS"
fi

# --------------------------------------------------------------------------
head_ "24. Провал пакетов останавливает установку"
# --------------------------------------------------------------------------
# На свежем сервере apt был занят автообновлением. Пакеты не встали, а
# установка пошла дальше и выдала шесть сбоев по одной причине плюс отчёт,
# в котором половина строк неправда.
INST=$(printf '\n\n\n\n\n\nn\nn\nn\n' | RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    DOMAIN="example.com"; SUBDOMAIN="n1"; PANEL_IP="1.2.3.4"
    REMNA_SECRET="s"; SSH_PUBLIC_KEY="'"$TESTKEY"'"
    ADMIN_USER="deploy"; SSH_PORT="45123"
    INSTALL_WARP="n"; INSTALL_SPEEDTEST="n"; SETUP_CF="n"; CF_PROXY_CHOICE="n"
    SETUP_TG="n"
    INSTALL_STATE=$(mktemp); SETUP_LOG=$(mktemp); REPORT_FILE=$(mktemp)
    rh_preflight() { return 0; }     # см. тест 7: на Windows apt-get нет
    comp_swap() { return 0; }
    comp_packages() { echo "  [СБОЙ] apt занят"; return 1; }
    for f in comp_user comp_ssh comp_fail2ban comp_autoupdates comp_ipv6 comp_ufw \
             comp_sysctl comp_docker comp_disk comp_node comp_web comp_telegram \
             notify_telegram print_summary reboot components_menu; do
        eval "$f(){ echo \"НЕ ДОЛЖНО ВЫПОЛНЯТЬСЯ: $f\"; return 0; }"
    done
    full_install || true
' 2>&1 || true)
if grep -q "Установка остановлена" <<< "$INST"; then
    ok "установка останавливается на провале пакетов"
else
    bad "установка пошла дальше:"; tail -12 <<< "$INST" | sed 's/^/      /'
fi
if grep -q "НЕ ДОЛЖНО ВЫПОЛНЯТЬСЯ" <<< "$INST"; then
    bad "после провала пакетов продолжились шаги:"; grep "НЕ ДОЛЖНО" <<< "$INST" | sed 's/^/      /'
else
    ok "ни один следующий шаг не запустился"
fi
# Останов обязан случиться ДО того, как тронут SSH
if grep -q "НЕ ДОЛЖНО ВЫПОЛНЯТЬСЯ: comp_ssh" <<< "$INST"; then
    bad "SSH успели тронуть до останова"
else
    ok "доступ по SSH при останове не менялся"
fi

# --------------------------------------------------------------------------
head_ "25. Оформление и тихий вывод"
# --------------------------------------------------------------------------
# printf считает точность (%-42.42s) в БАЙТАХ. На кириллице метка обрезалась
# по середине буквы: «Пакеты: обновляю списо?».
FIT=$(RH_LIB_ONLY=1 LC_ALL=C.UTF-8 bash -c '
    source "'"$ROOT"'/setup.sh"
    s=$(ui_fit "Пакеты: обновляю список пакетов" 20)
    echo "[$s] символов=${#s}"
' 2>&1 || true)
if grep -q "символов=20" <<< "$FIT" && ! grep -qP '\xef\xbf\xbd' <<< "$FIT"; then
    ok "метка обрезается по символам, а не по байтам"
else
    bad "обрезка рвёт кириллицу: $FIT"
fi

# Человек не должен видеть, как apt перечисляет двести пакетов: вывод шага
# уходит в лог, на экране — одна строка состояния.
QUIET=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SETUP_LOG=$(mktemp); SUMMARY=()
    болтливый() { echo "ДВЕСТИ СТРОК ВЫВОДА"; return 0; }
    do_step "Пакеты" болтливый
    echo "--- в логе: $(grep -c "ДВЕСТИ СТРОК ВЫВОДА" "$SETUP_LOG") ---"
    rm -f "$SETUP_LOG"
' 2>&1 || true)
if ! grep -q '^ *ДВЕСТИ СТРОК ВЫВОДА' <<< "$QUIET" && grep -q 'в логе: 1' <<< "$QUIET"; then
    ok "вывод успешного шага виден только в логе"
else
    bad "вывод шага сыплется на экран:"; sed 's/^/      /' <<< "$QUIET"
fi

# --------------------------------------------------------------------------
head_ "26. Проверки перед установкой"
# --------------------------------------------------------------------------
# Смысл: не начинать работу на сервере, где она заведомо не доедет до конца.
pre() {   # $1 — код, подменяющий окружение
    RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        rh_wait_cloud_init() { return 0; }
        rh_wait_apt() { return 0; }
        command() { return 0; }          # «всё установлено» — даже на Windows
        getent() { return 0; }
        free() { echo "Mem: 2048"; }
        df() { echo Avail; echo 20000M; }
        '"$1"'
        rh_preflight >/dev/null 2>&1 && echo НАЧАЛ || echo ОСТАНОВИЛ
    ' 2>&1 || true
}
R=$(pre 'true')
if grep -q "НАЧАЛ" <<< "$R"; then ok "исправный сервер проверку проходит"
else bad "проверка не пускает исправный сервер: $R"; fi

R=$(pre 'command() { [[ "${2:-}" == "apt-get" ]] && return 1; return 0; }')
if grep -q "ОСТАНОВИЛ" <<< "$R"; then ok "без apt-get установка не начинается"
else bad "скрипт готов ставить ноду не на Debian/Ubuntu"; fi

R=$(pre 'df() { echo Avail; echo 900M; }')
if grep -q "ОСТАНОВИЛ" <<< "$R"; then ok "на переполненном диске установка не начинается"
else bad "скрипт начинает установку без места на диске"; fi

R=$(pre 'getent() { return 1; }')
if grep -q "ОСТАНОВИЛ" <<< "$R"; then ok "без DNS установка не начинается"
else bad "скрипт начинает установку без сети"; fi

# --------------------------------------------------------------------------
head_ "27. Живучесть при обрыве ssh"
# --------------------------------------------------------------------------
# Установка идёт минуты, ssh рвётся. Внутри tmux сессия переживает обрыв.
# Но перезапускать себя можно только на живом терминале: в неинтерактивном
# запуске (cron, ssh -c, --repair по списку нод) это сломало бы всё.
guard() {
    RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        RH_LIB_ONLY=""            # дальше ведём себя как настоящий запуск
        '"$1"'
        tmux() { echo "УШЁЛ В TMUX"; }
        exec() { echo "УШЁЛ В TMUX"; }
        rh_session_guard
        echo "ПРОДОЛЖИЛ БЕЗ TMUX"
    ' 2>&1 || true
}
R=$(guard 'true')                      # stdout не терминал
if grep -q "ПРОДОЛЖИЛ БЕЗ TMUX" <<< "$R" && ! grep -q "УШЁЛ В TMUX" <<< "$R"; then
    ok "без терминала себя не перезапускает"
else
    bad "в неинтерактивном запуске лезет в tmux:"; sed 's/^/      /' <<< "$R"
fi
R=$(guard 'TMUX=/tmp/fake')            # уже внутри tmux
if ! grep -q "УШЁЛ В TMUX" <<< "$R"; then ok "внутри tmux второй раз не заходит"
else bad "плодит сессии tmux внутри tmux"; fi
R=$(guard 'RH_NO_TMUX=1')
if ! grep -q "УШЁЛ В TMUX" <<< "$R"; then ok "RH_NO_TMUX отключает перезапуск"
else bad "RH_NO_TMUX не работает"; fi

# Два установщика на одном сервере — это два apt и два перезапуска sshd.
if ! command -v flock >/dev/null 2>&1; then
    printf '  — flock не установлен, пропускаю\n'
else
    LK=$(mktemp -u)
    RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        RH_LOCK="'"$LK"'"; rh_take_lock; sleep 3
    ' >/dev/null 2>&1 &
    sleep 1
    SECOND=$(RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        RH_LOCK="'"$LK"'"; rh_take_lock; echo "ВТОРОЙ ЗАПУСТИЛСЯ"
    ' 2>&1 || true)
    wait 2>/dev/null || true
    rm -f "$LK"
    if grep -q "уже работает другой запуск" <<< "$SECOND"; then
        ok "второй одновременный запуск отбивается"
    else
        bad "два установщика могут работать разом:"; sed 's/^/      /' <<< "$SECOND"
    fi
fi

# --------------------------------------------------------------------------
head_ "28. Ошибки, найденные при проверке кода"
# --------------------------------------------------------------------------
# Каждая из них прошла все тесты выше и сломала бы установку на живом сервере.

# «exec 9>файл 2>/dev/null» отправлял stderr ВСЕГО скрипта в никуда: пропадали
# приглашения read (bash пишет их в stderr) и аварийные сообщения.
ERRV=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    RH_LOCK=$(mktemp -u); rh_take_lock
    echo "ВИДНО В STDERR" >&2
    rm -f "$RH_LOCK"
' 2>&1 || true)
if grep -q "ВИДНО В STDERR" <<< "$ERRV"; then
    ok "замок не глушит stderr — вопросы и ошибки видны"
else
    bad "после замка stderr пропадает: вопросы установщика станут невидимы"
fi

# Замок, взятый ДО перехода в tmux, наследует клиент tmux — и установщик
# внутри tmux упирается в собственный замок: «уже работает другой запуск».
L_GUARD=$(grep -n '^rh_session_guard' lib/99-main.sh | head -1 | cut -d: -f1)
L_LOCK=$(grep -n '^rh_take_lock' lib/99-main.sh | head -1 | cut -d: -f1)
if [[ -n "$L_GUARD" && -n "$L_LOCK" && "$L_GUARD" -lt "$L_LOCK" ]]; then
    ok "сначала tmux, потом замок"
else
    bad "замок берётся до tmux (строки $L_LOCK и $L_GUARD) — установка откажет сама себе"
fi

# На Ubuntu постоянно висит unattended-upgrade-shutdown. Поиск по имени
# процесса считал apt занятым всегда — ожидание по 10 минут на каждом сервере.
busy() {   # $1 — код, подменяющий окружение
    RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        '"$1"'
        if rh_apt_busy; then echo ЗАНЯТ; else echo СВОБОДЕН; fi
    ' 2>&1 || true
}
R=$(busy 'fuser() { return 1; }')
[[ "$R" == *СВОБОДЕН* ]] && ok "fuser никого не видит — apt свободен" \
                         || bad "занятость apt определяется неверно: $R"
R=$(busy 'fuser() { echo " 4242"; }')
[[ "$R" == *ЗАНЯТ* ]] && ok "fuser видит держателя блокировки — apt занят" \
                      || bad "держателя блокировки не видит: $R"
R=$(busy 'command() { [[ "${2:-}" == fuser ]] && return 1; return 0; }
          pgrep() { echo "812 /usr/bin/python3 /usr/share/unattended-upgrades/unattended-upgrade-shutdown --wait-for-signal"; }')
[[ "$R" == *СВОБОДЕН* ]] && ok "демон unattended-upgrade-shutdown занятостью не считается" \
                         || bad "постоянный демон считается занятым apt — ждать будем всегда"
R=$(busy 'command() { [[ "${2:-}" == fuser ]] && return 1; return 0; }
          pgrep() { echo "901 apt-get -y install nginx"; }')
[[ "$R" == *ЗАНЯТ* ]] && ok "без fuser настоящий apt-get всё равно замечается" \
                      || bad "без fuser apt-get не замечается: $R"

# Остановленная установка уже объяснила причину. Голый вызов под set -e
# рисовал поверх её объяснения красную рамку «ОШИБКА — установка прервана,
# команда: return 1» и убивал меню.
MENU=$(printf '1\n0\n' | RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    rh_preflight() { echo "  (проверка сервера не прошла)"; return 1; }
    main_menu
' 2>&1; echo "КОД=$?")
if ! grep -q "ОШИБКА — установка прервана" <<< "$MENU" && grep -q "КОД=0" <<< "$MENU"; then
    ok "остановленная установка не рисует аварию и не убивает меню"
else
    bad "остановка установки выглядит как авария:"; tail -8 <<< "$MENU" | sed 's/^/      /'
fi

# Шаг под спиннером не должен ждать ввода с терминала: вопрос ушёл бы в лог,
# и установка «висела» бы без объяснений.
HANG=$(sleep 30 | timeout 8 env RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    SETUP_LOG=$(mktemp); SUMMARY=()
    спрашивает() { read -r x; return 0; }
    do_step "шаг с вопросом" спрашивает
    echo "НЕ ЗАВИС"; rm -f "$SETUP_LOG"
' 2>&1 || true)
if grep -q "НЕ ЗАВИС" <<< "$HANG"; then
    ok "шаг с неожиданным вопросом не вешает установку"
else
    bad "шаг ждёт ввода с терминала под спиннером — установка зависнет"
fi

# Сообщение об остановке само говорит, в apt ли дело. Раньше оно предлагало
# набрать «pgrep -a '...'», а тот искал apt по имени процесса и показал бы
# постоянный демон ожидания выключения — человек ждал бы вечно.
stopmsg() {   # $1 — что вернёт apt_busy_who
    RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        SERVER_LABEL="Test 1"; PANEL_IP="1.2.3.4"; REMNA_SECRET="s"
        SSH_PUBLIC_KEY="'"$TESTKEY"'"; ADMIN_USER="deploy"; SSH_PORT="45123"
        INSTALL_WARP="n"; INSTALL_SPEEDTEST="n"; SETUP_TG="n"
        NONINTERACTIVE=1
        INSTALL_STATE=$(mktemp); SETUP_LOG=$(mktemp); REPORT_FILE=$(mktemp)
        rh_preflight() { return 0; }; comp_swap() { return 0; }
        comp_packages() { return 1; }
        apt_busy_who() { printf "%s" "'"$1"'"; }
        full_install || true
    ' 2>&1 || true
}
R=$(stopmsg "")
if grep -q "apt сейчас свободен" <<< "$R" && ! grep -q "pgrep -a" <<< "$R"; then
    ok "при свободном apt сообщение так и говорит — ждать нечего"
else
    bad "сообщение об остановке не говорит, свободен ли apt:"; tail -8 <<< "$R" | sed 's/^/      /'
fi
R=$(stopmsg "4242 apt-get -y upgrade")
if grep -q "4242 apt-get -y upgrade" <<< "$R"; then
    ok "при занятом apt сообщение называет, кто держит"
else
    bad "сообщение не называет держателя apt"
fi

# --------------------------------------------------------------------------
head_ "29. Стоковый сайт nginx default"
# --------------------------------------------------------------------------
# Живая нода: IPv6 выключен в ядре, apt ставит nginx, пакет стартует его со
# стоковым сайтом, где «listen [::]:80», — «Address family not supported»,
# dpkg бросает nginx недонастроенным, встаёт вся установка пакетов.
# На свежей установке то же случалось бы после финальной перезагрузки.
# Решение — стоковый default удаляется целиком из обоих каталогов.
v6tree() {   # $1 — каталог; стоковый default как в пакете Ubuntu
    mkdir -p "$1/avail" "$1/enabled" "$1/proc_v6"
    printf 'server {\n\tlisten 80 default_server;\n\tlisten [::]:80 default_server;\n\troot /var/www/html;\n}\n' \
        > "$1/avail/default"
    ln -sf "$1/avail/default" "$1/enabled/default"
    : > "$1/sysctl"
}
v6run() {    # $1 — каталог, $2 — "off" | "pending" | "on", $3 — код
    RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        T="'"$1"'"
        NGINX_AVAIL="$T/avail"; NGINX_ENABLED="$T/enabled"; SYSCTL_FILE="$T/sysctl"
        RH_BACKUP_DIR="$T/backup"
        case "'"$2"'" in
            off)     RH_IPV6_PROC="$T/нет-такого" ;;
            pending) RH_IPV6_PROC="$T/proc_v6"; echo "net.ipv6.conf.all.disable_ipv6 = 1" > "$T/sysctl" ;;
            on)      RH_IPV6_PROC="$T/proc_v6" ;;
        esac
        SETUP_LOG=/dev/null
        '"$3"'
    ' 2>&1 || true
}

T=$(mktemp -d); v6tree "$T"
v6run "$T" on 'nginx_default_remove' >/dev/null
if [[ ! -e "$T/avail/default" && ! -e "$T/enabled/default" && ! -L "$T/enabled/default" ]]; then
    ok "стоковый default удалён из sites-available и sites-enabled"
else
    bad "стоковый default остался:"; ls -la "$T/avail" "$T/enabled" | sed 's/^/      /'
fi
if ls "$T/backup"/nginx-default.* >/dev/null 2>&1 \
   && ! ls "$T/avail"/*default* "$T/enabled"/*default* >/dev/null 2>&1; then
    ok "копия лежит вне каталогов nginx"
else
    bad "копии нет или она в каталоге, который читает nginx"
fi
R=$(v6run "$T" on 'nginx_default_remove && echo УДАЛИЛ || echo НЕЧЕГО')
[[ "$R" == *НЕЧЕГО* ]] && ok "повторный вызов ничего не делает" \
                       || bad "повторное удаление ведёт себя странно: $R"
rm -rf "$T"

# Пакет при первой настройке создаёт ссылку, не проверяя, есть ли файл.
# Висячая ссылка роняет nginx так же, как [::] — её тоже убираем.
T=$(mktemp -d); mkdir -p "$T/avail" "$T/enabled"
ln -sf "$T/avail/default" "$T/enabled/default"
v6run "$T" on 'nginx_default_remove' >/dev/null
if [[ ! -L "$T/enabled/default" ]]; then ok "висячая ссылка на удалённый default убирается"
else bad "висячая ссылка осталась — nginx на ней упадёт"; fi
rm -rf "$T"

# Настоящий случай с fr-1: первая установка dpkg бросила, повтор обязан дожить
T=$(mktemp -d); v6tree "$T"
R=$(v6run "$T" off '
    APT_PACKAGES="nginx"
    apt-get() { case "$*" in *install*) [[ -e "$NGINX_ENABLED/default" ]] && return 100; return 0 ;; esac; return 0; }
    dpkg() { return 0; }
    systemctl() { return 0; }
    command() { return 0; }      # финальная проверка «всё ли встало» — не про это
    comp_packages && echo "ПАКЕТЫ ВСТАЛИ" || echo "ПАКЕТЫ УПАЛИ"')
if grep -q "ПАКЕТЫ ВСТАЛИ" <<< "$R"; then
    ok "установка пакетов доживает до конца, когда nginx падает на стоковом сайте"
else
    bad "пакеты не встают из-за стокового сайта:"; sed 's/^/      /' <<< "$R"
fi
rm -rf "$T"

# Свежая установка: стоковый default уходит сразу после установки пакетов,
# а не только когда что-то сломалось
T=$(mktemp -d); v6tree "$T"
R=$(v6run "$T" on 'APT_PACKAGES="nginx"; apt-get() { return 0; }; systemctl() { return 0; }
    command() { return 0; }
    comp_packages && echo OK || echo FAIL')
if [[ ! -e "$T/avail/default" ]] && grep -q OK <<< "$R"; then
    ok "на свежей установке стоковый default удаляется сразу"
else
    bad "после установки пакетов стоковый default остался — nginx умрёт после перезагрузки"
fi
rm -rf "$T"

# Починка предлагает шаг ровно тогда, когда nginx из-за default лежит
T=$(mktemp -d); v6tree "$T"
R=$(v6run "$T" pending 'SSH_HARDEN_FILE=/нет; NOTIFY_ENV=/нет; NODE_PULL_DIR=/нет; GEODATA_DIR=/нет; getent() { return 1; }
    repair_build_plan; printf "%s\n" "${REPAIR_PLAN[@]}"')
if grep -q repair_nginx_default <<< "$R"; then
    ok "при выключенном IPv6 починка предлагает убрать стоковый default"
else
    bad "починка не видит упавший из-за стокового сайта nginx"
fi
: > "$T/sysctl"                # предыдущий прогон выключил IPv6 в sysctl
R=$(v6run "$T" on 'SSH_HARDEN_FILE=/нет; NOTIFY_ENV=/нет; NODE_PULL_DIR=/нет; GEODATA_DIR=/нет; getent() { return 1; }
    repair_build_plan; printf "%s\n" "${REPAIR_PLAN[@]}"')
if ! grep -q repair_nginx_default <<< "$R"; then
    ok "при живом IPv6 починка nginx не трогает"
else
    bad "починка лезет в nginx, хотя ничего не сломано"
fi
rm -rf "$T"

# --------------------------------------------------------------------------
head_ "31. Geo-базы: обновление без риска"
# --------------------------------------------------------------------------
# «Сервер» с базами — локальный каталог, curl ходит в него через file://.
# Проверяем три вещи: первая загрузка кладёт файлы; повторная без изменений
# их не трогает; битый файл (сумма не сходится) не подменяет рабочий.
if command -v sha256sum >/dev/null 2>&1 && curl -fsS "file:///dev/null" >/dev/null 2>&1; then
    GD=$(mktemp -d); SRV="$GD/srv"; DST="$GD/dst"; mkdir -p "$SRV" "$DST"
    for f in geoip.dat geosite.dat; do
        head -c 4096 /dev/urandom > "$SRV/$f"
        (cd "$SRV" && sha256sum "$f" > "$f.sha256sum")
    done
    RH_LIB_ONLY=1 bash -c '
        source "'"$ROOT"'/setup.sh"
        GEODATA_DIR="'"$DST"'"; GEODATA_URL="file://'"$SRV"'"; GEODATA_BIN="'"$GD"'/upd.sh"
        geodata_write_updater
    ' >/dev/null 2>&1
    # Журнал скрипта — logger и stdout; в тесте берём stdout
    bash "$GD/upd.sh" --no-restart > "$GD/log" 2>&1
    if cmp -s "$SRV/geoip.dat" "$DST/geoip.dat" && cmp -s "$SRV/geosite.dat" "$DST/geosite.dat"; then
        ok "первая загрузка кладёт обе базы"
    else
        bad "базы не скачались:"; sed 's/^/      /' "$GD/log" 2>/dev/null
    fi
    : > "$GD/log"; bash "$GD/upd.sh" --no-restart > "$GD/log" 2>&1
    if grep -q 'не изменились' "$GD/log" && ! grep -q 'новая версия' "$GD/log"; then ok "без изменений на сервере ничего не перекачивает"
    else bad "перекачивает одинаковые базы"; fi
    cp "$DST/geosite.dat" "$GD/good"
    # На сервере объявлена новая сумма, а лежит файл, который ей не соответствует
    head -c 4096 /dev/urandom > "$SRV/geosite.dat"
    printf '%064d  geosite.dat\n' 1 > "$SRV/geosite.dat.sha256sum"
    : > "$GD/log"; bash "$GD/upd.sh" --no-restart > "$GD/log" 2>&1 || true
    if cmp -s "$GD/good" "$DST/geosite.dat" && grep -q 'не прошёл проверку sha256' "$GD/log"; then
        ok "битый файл не подменяет рабочий"
    else
        bad "битая база попала в ноду"
    fi
    rm -rf "$GD"
else
    printf '  — нет sha256sum или curl без file://, пропускаю\n'
fi

# --------------------------------------------------------------------------
head_ "32. Учётка ИИ-агента и версия ноды"
# --------------------------------------------------------------------------
R=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    ADMIN_USER="vadim"
    AGENT_USER="vadim"; validate_agent_params >/dev/null; echo "1:$AGENT_USER"
    AGENT_USER="";      validate_agent_params >/dev/null; echo "2:$AGENT_USER"
    AGENT_USER="claude"; validate_agent_params >/dev/null; echo "3:$AGENT_USER"
    AGENT_USER="root";  validate_agent_params >/dev/null; echo "4:$AGENT_USER"
    ADMIN_USER="claude"; AGENT_USER=""; validate_agent_params >/dev/null; echo "5:$AGENT_USER"
    ADMIN_USER="vadim"; AGENT_USER="bot1"; validate_agent_params >/dev/null; echo "6:$AGENT_USER"
' 2>&1)
if grep -qx '1:claude' <<< "$R" && grep -qx '2:claude' <<< "$R" && grep -qx '3:claude' <<< "$R" && grep -qx '4:claude' <<< "$R" && grep -qx '5:ai-agent' <<< "$R" && grep -qx '6:bot1' <<< "$R"; then
    ok "имя учётки агента проверяется (не root и не админ-учётка)"
else
    bad "проверка имени агента:"; sed 's/^/      /' <<< "$R"
fi
# Учётку агента ищут по группе, а sudoers у неё 91-*: админ-учётку человека
# установщик находит по 90-*, и агент не должен её подменить.
if grep -q '91-agent-' lib/50-security.sh && ! grep -q '/etc/sudoers.d/90-agent' lib/50-security.sh; then
    ok "sudoers агента не путается с админ-учёткой"
else
    bad "sudoers агента назван так, что его примут за админ-учётку"
fi
# Вход node-pull (ноды забирают сертификат) — не повод будить человека
if grep -q '\[ "${PAM_USER:-}" = node-pull \] && exit 0' tests/remnawave-notify.ref; then
    ok "вход node-pull не шлёт уведомление «Вход по SSH»"
else
    bad "уведомление о входе сработает на каждый забор node-pull"
fi

# Версия ноды: пусто — latest, мусор — latest, тег — как есть; с ноды,
# откатанной на старую версию, версия вычитывается из compose.
R=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    REMNANODE_VERSION="";       validate_node_version >/dev/null; echo "1:$REMNANODE_VERSION"
    REMNANODE_VERSION="3.4.3";  validate_node_version >/dev/null; echo "2:$REMNANODE_VERSION"
    REMNANODE_VERSION="3.4;rm"; validate_node_version >/dev/null; echo "3:$REMNANODE_VERSION"
' 2>&1)
if grep -qx '1:latest' <<< "$R" && grep -qx '2:3.4.3' <<< "$R" && grep -qx '3:latest' <<< "$R"; then
    ok "версия ноды: пусто и мусор — latest, тег — как есть"
else
    bad "проверка версии ноды:"; sed 's/^/      /' <<< "$R"
fi
CV=$(mktemp -d)
printf 'services:\n  remnanode:\n    image: remnawave/node:3.4.3\n' > "$CV/c.yml"
R=$(RH_LIB_ONLY=1 bash -c '
    source "'"$ROOT"'/setup.sh"
    v=$(grep -m1 -E "^[[:space:]]*image:[[:space:]]*remnawave/node" "'"$CV/c.yml"'" \
        | sed -E "s/.*remnawave\/node:?//" | tr -d "\"'"'"' \r\n")
    echo "${v:-latest}"
' 2>&1)
rm -rf "$CV"
if [[ "$R" == "3.4.3" ]]; then ok "закреплённая версия вычитывается из compose"
else bad "версия из compose прочиталась как '$R'"; fi

# --------------------------------------------------------------------------
head_ "30. shellcheck (если установлен)"
# --------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -s bash -S warning -e SC1090,SC1091,SC2034 setup.sh check.sh; then
        ok "shellcheck без замечаний"
    else
        bad "shellcheck нашёл проблемы"
    fi
else
    printf '  — shellcheck не установлен, пропускаю\n'
fi

# --------------------------------------------------------------------------
printf '\n=========================================\n'
printf '  Пройдено: %s   Провалено: %s\n' "$PASSED" "$FAILED"
printf '=========================================\n'
[[ $FAILED -eq 0 ]]
