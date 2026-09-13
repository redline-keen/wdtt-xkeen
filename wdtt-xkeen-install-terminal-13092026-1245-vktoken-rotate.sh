#!/bin/sh
# ═══════════════════════════════════════════════════════════════════
#  WDTT-клиент (RAW-TUN + VK-токен) — ВАРИАНТ ДЛЯ ВСТАВКИ В ТЕРМИНАЛ
# ═══════════════════════════════════════════════════════════════════
#  Как пользоваться: скопируйте ВЕСЬ этот файл целиком и вставьте
#  в SSH-сессию роутера (Entware/Keenetic). Установщик запишется в
#  /tmp и запустится; бинарник скачается с GitHub-релиза
#  redline-keen/wdtt-xkeen (тег 1.2), при недоступности GitHub —
#  из файла wdtt-client-arm64/wdtt-client-mipsle в текущем каталоге.
#  Всё ставится в /opt/etc/wdtt (бинарник, uninstall — там же).
#  Дальше отвечайте интерактивно: VK-токен → ссылка → звонков в пуле
#  (Enter = 2) → воркеров (Enter = 36). Сессию не закрывает.
# ═══════════════════════════════════════════════════════════════════

cat > /tmp/wdtt-install.sh <<'WDTT_PASTE_2335_EOF'
#!/bin/sh
tr -d '\r' < "$0" > "$0.clean" && mv "$0.clean" "$0" && chmod +x "$0"
# install-wdtt-vktoken.sh — установка WDTT-клиента (RAW-TUN + VK-токен) на Entware/Keenetic
#
# Отличия от install-wdtt-raw.sh (1.1):
#  - окно ввода ВЕЧНОГО VK access token при установке (с проверкой реальным
#    запросом к VK); хеши вручную не вводятся — клиент сам создаёт VK-звонки
#    и держит пул (vk_pool);
#  - ежедневная авто-ротация ВНУТРИ клиента: раз в сутки в случайный момент
#    окна 09:17–15:23 один случайный хеш пула заменяется свежим звонком,
#    без рестарта. Принудительно: touch /opt/etc/wdtt/rotate.now
#    (или перезапуск клиента — тогда ротация случится в ближайший тик окна).
#  - вопрос "сколько VK-звонков в пуле" (1..4, Enter = 2);
#  - TUN-интерфейс wdtt0 клиент создаёт сам (mihomo: interface-name: wdtt0).
set -e

run_installer() {

    # Жестко задаем пути, чтобы скрипт точно находил системные утилиты
    export PATH="/opt/bin:/opt/sbin:/opt/etc/wdtt:/bin:/usr/bin:/sbin:/usr/sbin"

    # ─────────────────────────── НАСТРОЙКИ ───────────────────────────

    GH_OWNER="redline-keen"
    GH_REPO="wdtt-xkeen"
    GH_TAG="1.2"

    ASSET_MIPSLE="wdtt-client-mipsle"
    ASSET_ARM64="wdtt-client-arm64"

    INSTALL_DIR="/opt/etc/wdtt"
    CONF_DIR="/opt/etc/wdtt"
    BIN_NAME="wdtt-client"
    INIT_SCRIPT="/opt/etc/init.d/S99wdtt-client"
    WATCHDOG_SCRIPT="$CONF_DIR/wdtt-watchdog.sh"

    WORKERS="36"
    RAW_PORT="56003"
    VK_CALLS="2"
    DEVICE_ID="$(cat /proc/sys/kernel/hostname 2>/dev/null || echo keenetic)"

    # read_tty: интерактивный ввод с терминала; если tty нет (curl | sh,
    # e2e) — читаем из stdin. На роутере поведение то же самое. Если нет
    # ни tty, ни stdin — завершаемся с внятной ошибкой (не крутим цикл).
    read_tty() {
        if read -r "$1" < /dev/tty 2>/dev/null; then return 0; fi
        if read -r "$1"; then return 0; fi
        echo "❌ Нет терминала и stdin закрыт — вставьте скрипт в интерактивную SSH-сессию или запустите файлом: wget -O /tmp/i.sh URL && sh /tmp/i.sh" >&2
        exit 1
    }

    # ─────────────────────────── АРХИТЕКТУРА ───────────────────────────

    detect_arch() {
        m=$(uname -m)
        case "$m" in
            aarch64|arm64) echo "arm64" ;;
            mips|mipsel|mips32)
                if command -v opkg >/dev/null 2>&1; then
                    oa=$(opkg print-architecture 2>/dev/null | grep -m1 -o 'mips[a-z0-9_]*' || true)
                    case "$oa" in
                        *mipsel*|*mipsle*) echo "mipsle" ;;
                        *) echo "mipsle" ;;
                    esac
                else
                    echo "mipsle"
                fi
                ;;
            *) echo "unknown" ;;
        esac
    }

    ARCH=$(detect_arch)
    if [ "$ARCH" = "unknown" ]; then
        echo "Не удалось определить архитектуру (uname -m: $(uname -m)). Прерываю." >&2
        exit 1
    fi

    case "$ARCH" in
        arm64)  ASSET_NAME="$ASSET_ARM64" ;;
        mipsle) ASSET_NAME="$ASSET_MIPSLE" ;;
    esac

    echo "Архитектура: $ARCH"
    echo "Ассет:        $ASSET_NAME (релиз $GH_TAG)"

    # ─────────────────────────── ОЧИСТКА СТАРЫХ ВЕРСИЙ ───────────────────────────

    echo "Подготовка системы: проверка и остановка прошлых копий..."
    if [ -x "$INIT_SCRIPT" ]; then
        "$INIT_SCRIPT" stop >/dev/null 2>&1 || true
    fi
    killall -9 "$BIN_NAME" 2>/dev/null || true
    ip link del wdtt0 2>/dev/null || true

    # ─────────────────────────── УСТАНОВКА ЗАВИСИМОСТЕЙ ───────────────────────────

    echo "Обновление пакетов и установка зависимостей..."
    opkg update >/dev/null 2>&1 || true
    opkg install ca-bundle wget-ssl cron nano >/dev/null 2>&1 || true

    mkdir -p "$INSTALL_DIR" "$CONF_DIR" /opt/var/log

    # ─────────────────────────── СКРИПТ WDTT-UNINSTALL ───────────────────────────

    echo "Создание скрипта удаления /opt/etc/wdtt/wdtt-uninstall..."
    cat << 'EOF' > /opt/etc/wdtt/wdtt-uninstall
#!/bin/sh
set -e

echo "════════════════════════════════════════════════════"
echo " Начинаю полное удаление WDTT-клиента (RAW + VK-токен)..."
echo "════════════════════════════════════════════════════"

CONF_DIR="/opt/etc/wdtt"
INSTALL_DIR="/opt/etc/wdtt"
BIN_NAME="wdtt-client"
INIT_SCRIPT="/opt/etc/init.d/S99wdtt-client"
CRON_FILE="/opt/var/spool/cron/crontabs/root"

# 1. Остановка процессов и удаление интерфейса
if [ -x "$INIT_SCRIPT" ]; then
    "$INIT_SCRIPT" stop >/dev/null 2>&1 || true
fi
killall -9 "$BIN_NAME" 2>/dev/null || true
ip link del wdtt0 2>/dev/null || true
echo "✓ Процессы остановлены, интерфейс wdtt0 удален."

# 2. Очистка cron
if [ -f "$CRON_FILE" ] && grep -E -q "wdtt-client|wdtt-watchdog" "$CRON_FILE"; then
    grep -E -v "wdtt-client|wdtt-watchdog" "$CRON_FILE" > "${CRON_FILE}.tmp" || true
    mv "${CRON_FILE}.tmp" "$CRON_FILE"
    chmod 600 "$CRON_FILE"
    [ -x /opt/etc/init.d/S10cron ] && /opt/etc/init.d/S10cron restart >/dev/null 2>&1 || true
    echo "✓ Задачи из cron удалены."
fi

# 3. Удаление службы init.d
rm -f "$INIT_SCRIPT"
echo "✓ Служба автозапуска удалена."

# 4. Самоудаление (деинсталлятор лежит в $CONF_DIR — удаляем себя
#    до rm -rf; работающий скрипт продолжит выполняться)
rm -f "$CONF_DIR/wdtt-uninstall"

# 5. Удаление бинарника и конфигураций (включая пул и токен)
rm -f "$INSTALL_DIR/$BIN_NAME"
rm -rf "$CONF_DIR"
echo "✓ Файлы программы и конфигурации удалены."

echo "════════════════════════════════════════════════════"
echo "✅ WDTT-клиент (RAW + VK-токен) полностью снесён с роутера!"
echo "════════════════════════════════════════════════════"
EOF

    chmod +x /opt/etc/wdtt/wdtt-uninstall

    # ─────────────────────────── СКАЧИВАНИЕ БИНАРНИКА ───────────────────────────

    # Бинарник: сначала GitHub-релиз (основной путь), при неудаче —
    # локальный файл рядом со скриптом (оффлайн-установка).
    DOWNLOAD_URL="https://github.com/${GH_OWNER}/${GH_REPO}/releases/download/${GH_TAG}/${ASSET_NAME}"
    echo "Скачиваю бинарник: ${DOWNLOAD_URL}..."
    wget --no-check-certificate -q -O "$INSTALL_DIR/$BIN_NAME" "$DOWNLOAD_URL" || true

    if [ ! -s "$INSTALL_DIR/$BIN_NAME" ]; then
        for cand in "./wdtt-client-$ARCH" "$(dirname "$0")/wdtt-client-$ARCH" "./wdtt-client" "$(dirname "$0")/wdtt-client"; do
            if [ -s "$cand" ]; then
                echo "GitHub недоступен — использую локальный бинарник: $cand"
                cp "$cand" "$INSTALL_DIR/$BIN_NAME"
                break
            fi
        done
    fi

    if [ ! -s "$INSTALL_DIR/$BIN_NAME" ]; then
        echo "Ошибка: не удалось скачать бинарник с GitHub и локального файла нет!" >&2
        exit 1
    fi

    chmod +x "$INSTALL_DIR/$BIN_NAME"
    echo "Успешно: $INSTALL_DIR/$BIN_NAME"

    # ─────────────────────────── ВВОД И ПРОВЕРКА VK-ТОКЕНА ───────────────────────────

    # Вечный токен получается в браузере (ссылка в INSTALL-документе):
    # oauth.vk.com/authorize?client_id=6287487&display=mobile&redirect_uri=
    # https%3A%2F%2Foauth.vk.com%2Fblank.html&response_type=token&scope=messages&v=5.199
    # после редиректа скопируйте access_token=vk1.a... из адресной строки.

    TOKEN_FILE="$CONF_DIR/vk_token"
    while :; do
        if [ -s "$TOKEN_FILE" ]; then
            printf "\n══════════════ VK ACCESS TOKEN ══════════════\n"
            printf "Токен уже сохранён (%s). Enter = оставить его,\n" "$TOKEN_FILE"
            printf "или вставьте новый:\n> "
        else
            printf "\n══════════════ VK ACCESS TOKEN ══════════════\n"
            printf "Вставьте ВЕЧНЫЙ VK access token (vk1.a...):\n> "
        fi
        read_tty VK_TOKEN || true

        if [ -z "$VK_TOKEN" ] && [ -s "$TOKEN_FILE" ]; then
            echo "✓ Использую сохранённый токен"
        else
            [ -n "$VK_TOKEN" ] || continue
            case "$VK_TOKEN" in
                *'"'*|*"'"*)
                    echo "❌ Токен содержит недопустимые символы (кавычки)."
                    continue
                    ;;
            esac
            printf '%s' "$VK_TOKEN" > "$TOKEN_FILE"
        fi
        chmod 600 "$TOKEN_FILE"

        echo "Проверяю токен (создаётся один тестовый звонок VK)..."
        if "$INSTALL_DIR/$BIN_NAME" -vk-regen-call -vk-token "$TOKEN_FILE" 2>/dev/null | grep -q "^CALL_HASH:"; then
            echo "✅ Токен принят. Хеши VK клиент будет создавать сам из этого токена."
            break
        else
            echo "❌ Токен не принят VK. Проверьте, что скопирован access_token целиком (vk1.a...)."
        fi
    done

    # ─────────────────────────── ВВОД И ПАРСИНГ WDTT-ССЫЛКИ ───────────────────────────

    while :; do
        printf "\nВставьте ссылку конфигурации WDTT/QWDTT:\n> "

        if ! read_tty WDTT_LINK; then
            sleep 1
            continue
        fi

        HOST=""
        PASSWORD=""
        RAW_HASH=""

        case "$WDTT_LINK" in
            wdtt://connect\?*)
                HOST=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]host=\([^&]*\).*/\1/p')
                PASSWORD=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]password=\([^&]*\).*/\1/p')
                RAW_HASH=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]hashes=\([^&]*\).*/\1/p')
                ;;
            qwdtt://config\?*)
                peer_enc=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]peer=\([^&]*\).*/\1/p')
                peer=$(echo "$peer_enc" | sed 's/%3A/:/g; s/%3a/:/g')
                HOST=$(echo "$peer" | cut -d':' -f1)
                PASSWORD=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]pass=\([^&]*\).*/\1/p')
                RAW_HASH=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]hashes=\([^&]*\).*/\1/p')

                req_workers=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]workers=\([^&]*\).*/\1/p')
                if [ -n "$req_workers" ]; then
                    WORKERS="$req_workers"
                fi
                ;;
            wdtt://*:*:*:*:*:*)
                temp_link=$(echo "$WDTT_LINK" | sed 's|^wdtt://||')
                HOST=$(echo "$temp_link" | cut -d':' -f1)
                PASSWORD=$(echo "$temp_link" | cut -d':' -f5)
                RAW_HASH=$(echo "$temp_link" | cut -d':' -f6-)
                ;;
            *)
                echo "❌ Неизвестный формат ссылки."
                continue
                ;;
        esac

        if [ -z "$HOST" ] || [ -z "$PASSWORD" ]; then
            echo "❌ Не удалось распарсить ссылку (нужны host и password). Проверьте ссылку!"
            continue
        fi

        if [ -n "$RAW_HASH" ]; then
            echo "ℹ️  Хеши из ссылки не используются: пул создаётся из VK-токена."
        fi
        break
    done

    # ─────────────────────────── ПАРАМЕТРЫ ПУЛА И ВОКЕРОВ ───────────────────────────

    printf "\nСколько VK-звонков в пуле [1..4] (Enter = 2): "
    read_tty INPUT_CALLS || true
    case "$INPUT_CALLS" in
        '') : ;;
        *[!0-9]*)
            echo "⚠️ Не число, оставляем: $VK_CALLS"
            ;;
        *)
            if [ "$INPUT_CALLS" -ge 1 ] && [ "$INPUT_CALLS" -le 4 ]; then
                VK_CALLS="$INPUT_CALLS"
            else
                echo "⚠️ Вне диапазона 1..4, оставляем: $VK_CALLS"
            fi
            ;;
    esac
    echo "✓ Звонков в пуле: $VK_CALLS (пул переживает рестарты; ротация 1 раз/сутки заменяет один случайный)"

    MAX_WORKERS=$((VK_CALLS * 27))
    printf "Введите количество воркеров [по умолчанию: %s, потолок для %s звонков: %s]: " "$WORKERS" "$VK_CALLS" "$MAX_WORKERS"
    read_tty INPUT_WORKERS || true
    if [ -n "$INPUT_WORKERS" ]; then
        case "$INPUT_WORKERS" in
            ''|*[!0-9]*)
                echo "⚠️ Введено не число, оставляем значение: $WORKERS"
                ;;
            *)
                WORKERS="$INPUT_WORKERS"
                echo "✓ Установлено воркеров: $WORKERS"
                ;;
        esac
    else
        echo "✓ Используется значение по умолчанию: $WORKERS"
    fi
    if [ "$WORKERS" -gt "$MAX_WORKERS" ]; then
        echo "⚠️ Воркеров $WORKERS → $MAX_WORKERS (правило 27 на звонок, $VK_CALLS звонков)"
        WORKERS="$MAX_WORKERS"
    fi
    WORKERS=$((WORKERS / 9 * 9))
    [ "$WORKERS" -ge 9 ] || WORKERS=9
    echo "✓ Итог: воркеров $WORKERS"

    # ─────────────────────────── INIT.D СКРИПТ (ENTWARE) ───────────────────────────

    cat > "$INIT_SCRIPT" << EOF
#!/bin/sh
# Автозапуск wdtt-client (RAW-TUN + VK-токен) на Entware (Keenetic)

ENABLED=yes
PROG="/opt/etc/wdtt/wdtt-client"
CONF_DIR="/opt/etc/wdtt"
PIDFILE="\$CONF_DIR/wdtt-client.pid"
LOGFILE="\$CONF_DIR/wdtt-client.log"

start() {
    mkdir -p "\$CONF_DIR"
    cd "\$CONF_DIR"

    PATH=/opt/bin:/opt/sbin:/opt/etc/wdtt:/bin:/usr/bin:/sbin
    export PATH

    while ! ping -c 1 -W 2 77.88.8.8 >/dev/null 2>&1; do
        sleep 5
    done

    killall -9 wdtt-client 2>/dev/null || true

    echo "Starting wdtt-client (RAW-TUN + VK-токен)..."

    \$PROG \\
        -mode rawtun \\
        -turn-tcp \\
        -peer ${HOST}:${RAW_PORT} \\
        -password '${PASSWORD}' \\
        -device-id '${DEVICE_ID}' \\
        -n ${WORKERS} \\
        -tun-name wdtt0 \\
        -vk-token "\$CONF_DIR/vk_token" \\
        -vk-pool "\$CONF_DIR/vk_pool" \\
        -vk-calls ${VK_CALLS} \\
        < /dev/null >> "\$LOGFILE" 2>&1 &

    echo \$! > "\$PIDFILE"
    echo "wdtt-client запущен (PID: \$!)"
}

stop() {
    echo "Stopping wdtt-client..."
    start-stop-daemon -K -q -p "\$PIDFILE" 2>/dev/null || true
    killall -9 wdtt-client 2>/dev/null || true
    rm -f "\$PIDFILE"
    ip link del wdtt0 2>/dev/null || true
    sleep 1
}

case "\$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 2; start ;;
    *) echo "Usage: \$0 {start|stop|restart}"; exit 1 ;;
esac
EOF

    chmod +x "$INIT_SCRIPT"

    # ─────────────────────────── СКРИПТ WATCHDOG ───────────────────────────

    echo "Создание скрипта watchdog..."
    cat > "$WATCHDOG_SCRIPT" << EOF
#!/bin/sh

PATH=/opt/bin:/opt/sbin:/opt/etc/wdtt:/bin:/usr/bin:/sbin
export PATH

LOG_FILE="${CONF_DIR}/wdtt-client.log"
MAX_SIZE_KB=1024
WG_IFACE="wdtt0"
INIT_SCRIPT="${INIT_SCRIPT}"
PING_TARGET="77.88.8.8"

# 1. БЕЗУСЛОВНАЯ РОТАЦИЯ ЛОГА
if [ -f "\$LOG_FILE" ]; then
    FILE_SIZE=\$(du -k "\$LOG_FILE" | awk '{print \$1}')
    if [ "\$FILE_SIZE" -gt "\$MAX_SIZE_KB" ]; then
        tail -n 500 "\$LOG_FILE" > "\$LOG_FILE.tmp" && mv "\$LOG_FILE.tmp" "\$LOG_FILE"
        echo "\$(date '+%Y-%m-%d %H:%M:%S') [WATCHDOG] Лог превысил \$MAX_SIZE_KB КБ и был обрезан." >> "\$LOG_FILE"
    fi
fi

# 2. ПРОВЕРКА: Запущен ли процесс и поднят ли интерфейс?
if ! pidof wdtt-client >/dev/null 2>&1 || ! ip link show wdtt0 2>/dev/null | grep -q "UP"; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [WATCHDOG] Клиент неактивен или интерфейс упал. Перезапуск..." >> /opt/var/log/watchdog.log
    \$INIT_SCRIPT restart
else
    # 3. ПРОВЕРКА: Пинг через интерфейс
    if ! ping -c 2 -W 3 -I "\$WG_IFACE" "\$PING_TARGET" > /dev/null 2>&1; then
        echo "\$(date '+%Y-%m-%d %H:%M:%S') [WATCHDOG] Пинг через \$WG_IFACE не прошел. Перезапуск..." >> /opt/var/log/watchdog.log
        \$INIT_SCRIPT restart
    fi
fi
EOF

    chmod +x "$WATCHDOG_SCRIPT"

    # ─────────────────────────── НАСТРОЙКА CRON WATCHDOG ───────────────────────────

    echo "Настраиваю CRON для watchdog..."
    CRON_DIR="/opt/var/spool/cron/crontabs"
    CRON_FILE="$CRON_DIR/root"

    CRON_CMD="*/2 * * * * $WATCHDOG_SCRIPT"

    mkdir -p "$CRON_DIR"
    chmod 755 "$CRON_DIR"

    if [ -f "$CRON_FILE" ]; then
        sed -i '/wdtt-watchdog/d' "$CRON_FILE" 2>/dev/null || true
        sed -i '/wdtt-client/d' "$CRON_FILE" 2>/dev/null || true
    fi

    echo "$CRON_CMD" >> "$CRON_FILE"
    chmod 600 "$CRON_FILE"

    if [ -x /opt/etc/init.d/S10cron ]; then
        /opt/etc/init.d/S10cron restart >/dev/null 2>&1 || true
    fi

    # ─────────────────────────── ЗАПУСК И ПРОВЕРКА ───────────────────────────

    echo "Запуск службы wdtt-client..."
    "$INIT_SCRIPT" start

    echo "Ожидание поднятия интерфейса wdtt0..."
    i=0
    while ! ip link show wdtt0 2>/dev/null | grep -q "UP" && [ "$i" -lt 30 ]; do
        sleep 1
        i=$((i + 1))
    done

    echo "════════════════════════════════════════════════════"
    if ip link show wdtt0 2>/dev/null | grep -q "UP"; then
        echo "🎉 Установка завершена успешно! Интерфейс wdtt0 активен."
        echo "mihomo/XKeen: proxies: [ { name: WDTT, type: direct, interface-name: wdtt0 } ]"
    else
        echo "⚠️ Внимание: Интерфейс wdtt0 еще поднимается или требует проверки логов."
        echo "Посмотреть логи можно командой: cat /opt/etc/wdtt/wdtt-client.log"
    fi
    echo "Ротация хешей: ежедневно 09:17–15:23 (1 случайный хеш), без рестарта."
    echo "Принудительная ротация: touch $CONF_DIR/rotate.now"
    echo "════════════════════════════════════════════════════"
}

run_installer "$@"
WDTT_PASTE_2335_EOF

sh /tmp/wdtt-install.sh
rm -f /tmp/wdtt-install.sh
