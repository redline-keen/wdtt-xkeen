#!/bin/sh
# install-wdtt.sh — установка WDTT-клиента (wdtt-client) на Entware/Keenetic
set -e

run_installer() {

    # ─────────────────────────── НАСТРОЙКИ ───────────────────────────

    GH_OWNER="redline-keen"
    GH_REPO="wdtt-xkeen"
    GH_TAG="1.0"

    ASSET_MIPSLE="wdtt-client-mipsle"
    ASSET_ARM64="wdtt-client-arm64"

    INSTALL_DIR="/opt/usr/bin"
    CONF_DIR="/opt/etc/wdtt"
    BIN_NAME="wdtt-client"
    INIT_SCRIPT="/opt/etc/init.d/S99wdtt-client"

    WORKERS="9"
    DEVICE_ID="$(cat /proc/sys/kernel/hostname 2>/dev/null || echo keenetic)"

    # Вспомогательная функция очистки VK-хеша от ссылок и параметров
    clean_hash() {
        echo "$1" | sed 's|.*vk\.com/call/join/||g; s|.*vk\.me/join/||g; s/[?#].*//' | tr -d ' \r\n\t'
    }

    # ─────────────────────────── АРХИТЕКТУРА ───────────────────────────

    detect_arch() {
        m=$(uname -m)
        case "$m" in
            aarch64|arm64)
                echo "arm64"
                ;;
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
            *)
                echo "unknown"
                ;;
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
    echo "Ассет:       $ASSET_NAME (релиз $GH_TAG)"

    # ─────────────────────────── ОЧИСТКА СТАРЫХ ВЕРСИЙ ───────────────────────────

    echo "Подготовка системы: проверка и остановка прошлых копий..."
    if [ -x "$INIT_SCRIPT" ]; then
        "$INIT_SCRIPT" stop >/dev/null 2>&1 || true
    fi
    killall -9 "$BIN_NAME" 2>/dev/null || true

    # ─────────────────────────── УСТАНОВКА ЗАВИСИМОСТЕЙ  ───────────────────────────

    echo "Обновление пакетов и установка зависимостей..."
    opkg update
    opkg install wireguard-tools ca-bundle wget-ssl cron 2>/dev/null || true

    mkdir -p "$INSTALL_DIR" "$CONF_DIR"

    # ─────────────────────────── СОЗДАНИЕ СКРИПТА WDTT-UNINSTALL ───────────────────────────

    echo "Создание скрипта удаления /opt/usr/bin/wdtt-uninstall..."
    cat << 'EOF' > /opt/usr/bin/wdtt-uninstall
#!/bin/sh
set -e

echo "════════════════════════════════════════════════════"
echo " Начинаю полное удаление WDTT-клиента..."
echo "════════════════════════════════════════════════════"

CONF_DIR="/opt/etc/wdtt"
INSTALL_DIR="/opt/usr/bin"
BIN_NAME="wdtt-client"
INIT_SCRIPT="/opt/etc/init.d/S99wdtt-client"
CRON_FILE="/opt/var/spool/cron/crontabs/root"

# 1. Остановка процессов
if [ -x "$INIT_SCRIPT" ]; then
    "$INIT_SCRIPT" stop >/dev/null 2>&1 || true
fi
killall -9 "$BIN_NAME" 2>/dev/null || true
echo "✓ Процессы остановлены."

# 2. Очистка cron
if [ -f "$CRON_FILE" ] && grep -q "wdtt-client" "$CRON_FILE"; then
    grep -v "wdtt-client" "$CRON_FILE" > "${CRON_FILE}.tmp" || true
    mv "${CRON_FILE}.tmp" "$CRON_FILE"
    chmod 600 "$CRON_FILE"
    [ -x /opt/etc/init.d/S10cron ] && /opt/etc/init.d/S10cron restart >/dev/null 2>&1 || true
    echo "✓ Задачи из cron удалены."
fi

# 3. Удаление службы init.d
rm -f "$INIT_SCRIPT"
echo "✓ Служба автозапуска удалена."

# 4. Удаление бинарника и конфигураций
rm -f "$INSTALL_DIR/$BIN_NAME"
rm -rf "$CONF_DIR"
echo "✓ Файлы программы и конфигурации удалены."

# 5. Самоудаление
rm -f /opt/usr/bin/wdtt-uninstall

echo "════════════════════════════════════════════════════"
echo "✅ WDTT-клиент снесён с роутера!"
echo "Внимание: Интерфейс WireGuard в настройках Keenetic необходимо удалить вручную."
echo "════════════════════════════════════════════════════"
EOF

    chmod +x /opt/usr/bin/wdtt-uninstall

    # ─────────────────────────── СКАЧИВАНИЕ БИНАРНИКА ───────────────────────────

    DOWNLOAD_URL="https://github.com/${GH_OWNER}/${GH_REPO}/releases/download/${GH_TAG}/${ASSET_NAME}"
    echo "Скачиваю бинарник напрямую: ${DOWNLOAD_URL}..."

    wget --no-check-certificate -q -O "$INSTALL_DIR/$BIN_NAME" "$DOWNLOAD_URL"

    if [ ! -s "$INSTALL_DIR/$BIN_NAME" ]; then
        echo "Ошибка: Файл не скачался или имеет нулевой размер!" >&2
        exit 1
    fi

    chmod +x "$INSTALL_DIR/$BIN_NAME"
    echo "Успешно скачан: $INSTALL_DIR/$BIN_NAME"

    # ─────────────────────────── ВВОД WDTT-ССЫЛКИ ───────────────────────────

    while :; do
        printf "\nВставьте ссылку вида:\n"
        printf "wdtt://connect?v=1&host=IP&dtls=PORT&wg=PORT&local=PORT&password=XXX&hashes=YYY\n> "
        
        if ! read WDTT_LINK < /dev/tty; then
            echo "Ошибка чтения с /dev/tty. Повторяем попытку..."
            sleep 1
            continue
        fi

        HOST=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]host=\([^&]*\).*/\1/p')
        DTLS=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]dtls=\([^&]*\).*/\1/p')
        LOCAL=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]local=\([^&]*\).*/\1/p')
        PASSWORD=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]password=\([^&]*\).*/\1/p')
        RAW_HASH=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]hashes=\([^&]*\).*/\1/p')

        if [ -z "$HOST" ] || [ -z "$DTLS" ] || [ -z "$LOCAL" ] || [ -z "$PASSWORD" ] || [ -z "$RAW_HASH" ]; then
            echo "❌ Не удалось распарсить ссылку (отсутствуют обязательные параметры). Проверьте ссылку!"
            continue
        fi

        MAIN_HASH=$(clean_hash "$RAW_HASH")
        FINAL_HASHES="$MAIN_HASH"

        echo ""
        echo "================================================================="
        echo "✓ Основной хеш [1/4]: $MAIN_HASH"
        echo "================================================================="
        printf "Хотите добавить дополнительные хеши VK для ускорения? [y/N]: "
        read -r ADD_MORE < /dev/tty || true

        case "$ADD_MORE" in
            [Yy]*|[Дд]*)
                count=2
                while [ $count -le 4 ]; do
                    echo ""
                    printf "Введите хеш #%d (или нажмите Enter, чтобы пропустить): " "$count"
                    read -r INPUT_HASH < /dev/tty || true

                    CLEANED=$(clean_hash "$INPUT_HASH")

                    if [ -z "$CLEANED" ]; then
                        echo "⏩ Пропущено."
                        break
                    fi

                    FINAL_HASHES="${FINAL_HASHES},${CLEANED}"
                    echo "✓ Добавлен хеш #$count: $CLEANED"

                    count=$((count + 1))
                done
                ;;
            *)
                echo "Используется 1 основной хеш."
                ;;
        esac

        echo "================================================================="
        echo "Параметры: host=$HOST dtls=$DTLS local=$LOCAL"
        echo "Итоговые VK-хеши: $FINAL_HASHES"
        echo "Проверяю VK-хеши..."

        if "$INSTALL_DIR/$BIN_NAME" -check-hashes -vk "$FINAL_HASHES"; then
            echo "✅ Хеши валидны, продолжаю установку."
            break
        else
            echo "❌ Хеши не прошли проверку (звонок завершен или ссылка устарела)."
            echo "Сгенерируйте новую ссылку и вставьте её заново."
        fi
    done

    # ─────────────────────────── INIT.D СКРИПТ (ENTWARE) ───────────────────────────

    cat > "$INIT_SCRIPT" << EOF
#!/bin/sh
# Автозапуск wdtt-client на Entware (Keenetic)

ENABLED=yes
PROG="/opt/usr/bin/wdtt-client"
CONF_DIR="/opt/etc/wdtt"
PIDFILE="\$CONF_DIR/wdtt-client.pid"
LOGFILE="\$CONF_DIR/wdtt-client.log"

start() {
    mkdir -p "\$CONF_DIR"
    cd "\$CONF_DIR"
    
    PATH=/opt/bin:/opt/sbin:/opt/usr/bin:/bin:/usr/bin:/sbin
    export PATH

    if pidof wdtt-client >/dev/null 2>&1; then
        echo "wdtt-client уже запущен в системе"
        exit 0
    fi

    echo "Starting wdtt-client..."
    
    \$PROG \\
        -listen 127.0.0.1:${LOCAL} \\
        -peer ${HOST}:${DTLS} \\
        -password '${PASSWORD}' \\
        -vk '${FINAL_HASHES}' \\
        -device-id '${DEVICE_ID}' \\
        -n ${WORKERS} \\
        < /dev/null >> "\$LOGFILE" 2>&1 &

    echo \$! > "\$PIDFILE"
    echo "wdtt-client запущен (PID: \$!)"
}

stop() {
    echo "Stopping wdtt-client..."
    killall -9 wdtt-client 2>/dev/null || true
    rm -f "\$PIDFILE"
    sleep 2
}

case "\$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 10
        start
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF

    chmod +x "$INIT_SCRIPT"
    echo "Автозапуск настроен: $INIT_SCRIPT"

    # ─────────────────────────── НАСТРОИКА CRON WATCHDOG ───────────────────────────

    echo "Настраиваю CRON сторожевой таймер..."
    CRON_DIR="/opt/var/spool/cron/crontabs"
    CRON_FILE="$CRON_DIR/root"
    
    CRON_CMD="*/2 * * * * PATH=/opt/bin:/opt/sbin:/opt/usr/bin:\$PATH pidof wdtt-client >/dev/null 2>&1 || /opt/etc/init.d/S99wdtt-client start"

    mkdir -p "$CRON_DIR"
    chmod 755 "$CRON_DIR"

    if [ -f "$CRON_FILE" ]; then
        sed -i '/S99wdtt-client/d' "$CRON_FILE" 2>/dev/null || true
    fi

    echo "$CRON_CMD" >> "$CRON_FILE"
    chmod 600 "$CRON_FILE"
    echo "✓ Задача успешно добавлена в cron."

    if [ -x /opt/etc/init.d/S10cron ]; then
        /opt/etc/init.d/S10cron restart >/dev/null 2>&1 || true
    fi

    # ─────────────────────────── ОЖИДАНИЕ КОНФИГА ───────────────────────────

    CONF_FILE="$CONF_DIR/wg-turn.conf"
    LOG_FILE="$CONF_DIR/wdtt-client.log"

    rm -f "$CONF_FILE"

    wait_for_conf_with_log() {
        touch "$LOG_FILE"
        
        tail -f -n 0 "$LOG_FILE" &
        TAIL_PID=$!

        i=0
        while [ ! -f "$CONF_FILE" ] && [ "$i" -lt 60 ]; do
            sleep 1
            i=$((i + 1))
        done

        kill $TAIL_PID 2>/dev/null || true
        wait $TAIL_PID 2>/dev/null || true

        [ -f "$CONF_FILE" ]
    }

    echo ""
    echo "Запуск 1/2: Запускаю клиент для получения wg-turn.conf (вывод логов в реальном времени)..."
    echo "────────────────────────────────────────────────────────────────────────────"
    "$INIT_SCRIPT" start

    if ! wait_for_conf_with_log; then
        echo "────────────────────────────────────────────────────────────────────────────"
        echo "⚠️ Попытка 1: Конфиг не появился за 60 секунд. Пробую перезапуск (2/2)..."
        echo "────────────────────────────────────────────────────────────────────────────"
        "$INIT_SCRIPT" restart
        
        if ! wait_for_conf_with_log; then
            echo "────────────────────────────────────────────────────────────────────────────"
            echo "⚠️ Внимание: Конфиг wg-turn.conf пока не получен за 2 минуты."
            echo "Установка завершена. Cron настроен."
            exit 0
        fi
    fi
    echo "────────────────────────────────────────────────────────────────────────────"

    # ─────────────────────────── АВТОМАТИЧЕСКАЯ НАСТРОЙКА KEENETIC ───────────────────────────

    echo ""
    echo "════════════════════════════════════════════════════"
    echo "✅ Конфиг успешно получен! Начинаю настройку KeeneticOS..."
    echo "════════════════════════════════════════════════════"

    PRIV_KEY=$(grep -i '^PrivateKey' "$CONF_FILE" | cut -d '=' -f 2 | tr -d ' \r')
    PUB_KEY=$(grep -i '^PublicKey' "$CONF_FILE" | cut -d '=' -f 2 | tr -d ' \r')
    ADDRESS_CIDR=$(grep -i '^Address' "$CONF_FILE" | cut -d '=' -f 2 | tr -d ' \r' | cut -d ',' -f 1)
    ENDPOINT_FULL=$(grep -i '^Endpoint' "$CONF_FILE" | cut -d '=' -f 2 | tr -d ' \r')

    IP_ADDR=${ADDRESS_CIDR%/*}
    CIDR=${ADDRESS_CIDR#*/}

    if [ "$CIDR" = "32" ]; then
        IP_MASK="255.255.255.255"
    elif [ "$CIDR" = "24" ]; then
        IP_MASK="255.255.255.0"
    else
        IP_MASK="255.255.255.0"
    fi

    ENDPOINT_ADDR=${ENDPOINT_FULL%:*}
    ENDPOINT_PORT=${ENDPOINT_FULL##*:}

    echo "Поиск свободного интерфейса Wireguard..."
    
    # Делаем ровно один запрос к системе, чтобы не повесить шину
    ALL_INTERFACES=$(ndmq -p "show interface" 2>/dev/null)
    
    IFACE_NUM=0
    # Ищем первый свободный номер исключительно в памяти скрипта
    while echo "$ALL_INTERFACES" | grep -q "Wireguard${IFACE_NUM}"; do
        IFACE_NUM=$((IFACE_NUM+1))
    done

    WG_IFACE="Wireguard${IFACE_NUM}"
    echo "Выбран интерфейс: $WG_IFACE"

    echo "Применяю настройки в NDM..."
    ndmq -p "interface $WG_IFACE description \"WDTT_Turn\""
    ndmq -p "interface $WG_IFACE wireguard private-key $PRIV_KEY"
    ndmq -p "interface $WG_IFACE ip address $IP_ADDR $IP_MASK"
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY"
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY endpoint $ENDPOINT_ADDR $ENDPOINT_PORT"
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY allowed-ips 0.0.0.0 0.0.0.0"
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY keepalive 25"
    ndmq -p "interface $WG_IFACE ip global"
    ndmq -p "interface $WG_IFACE up"
    ndmq -p "system configuration save"

    echo "════════════════════════════════════════════════════"
    echo "🎉 Все компоненты установлены, интерфейс $WG_IFACE создан в роутере!"
    echo "✅ Галочка 'Использовать для выхода в интернет' установлена."
    echo "💡 В случае удаления клиента, интерфейс $WG_IFACE потребуется удалить в Web-интерфейсе вручную."
    echo "════════════════════════════════════════════════════"
}

run_installer "$@"
