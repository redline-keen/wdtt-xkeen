#!/bin/sh
# install-wdtt.sh — установка WDTT-клиента (wdtt-client) на Entware/Keenetic с автонастройкой
set -e

run_installer() {

    # Жестко задаем пути, чтобы скрипт точно находил системные утилиты
    export PATH="/opt/bin:/opt/sbin:/opt/usr/bin:/bin:/usr/bin:/sbin:/usr/sbin"

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
    WATCHDOG_SCRIPT="$CONF_DIR/wdtt-watchdog.sh"

    WORKERS="12"
    DEVICE_ID="$(cat /proc/sys/kernel/hostname 2>/dev/null || echo keenetic)"

    # Вспомогательная функция очистки VK-хеша от ссылок и параметров
    clean_hash() {
        echo "$1" | sed 's|.*vk\.com/call/join/||g; s|.*vk\.me/join/||g; s/[?#].*//' | tr -d ' \r\n\t'
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
    echo "Ассет:       $ASSET_NAME (релиз $GH_TAG)"

    # ─────────────────────────── ОЧИСТКА СТАРЫХ ВЕРСИЙ ───────────────────────────

    echo "Подготовка системы: проверка и остановка прошлых копий..."
    if [ -x "$INIT_SCRIPT" ]; then
        "$INIT_SCRIPT" stop >/dev/null 2>&1 || true
    fi
    killall -9 "$BIN_NAME" 2>/dev/null || true

    # ─────────────────────────── УСТАНОВКА ЗАВИСИМОСТЕЙ  ───────────────────────────

    echo "Обновление пакетов и установка зависимостей..."
    opkg update >/dev/null 2>&1 || true
    opkg install wireguard-tools ca-bundle wget-ssl cron ndmq >/dev/null 2>&1 || true

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

    # ─────────────────────────── ВВОД И ПАРСИНГ WDTT-ССЫЛКИ ───────────────────────────

    while :; do
        printf "\nВставьте ссылку конфигурации WDTT/QWDTT:\n> "
        
        if ! read WDTT_LINK < /dev/tty; then
            sleep 1
            continue
        fi

        HOST=""
        DTLS=""
        LOCAL=""
        PASSWORD=""
        RAW_HASH=""

        case "$WDTT_LINK" in
            wdtt://connect\?*)
                # Формат 1: wdtt://connect?host=...&dtls=...&local=...
                HOST=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]host=\([^&]*\).*/\1/p')
                DTLS=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]dtls=\([^&]*\).*/\1/p')
                LOCAL=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]local=\([^&]*\).*/\1/p')
                PASSWORD=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]password=\([^&]*\).*/\1/p')
                RAW_HASH=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]hashes=\([^&]*\).*/\1/p')
                ;;
            qwdtt://config\?*)
                # Формат 2: qwdtt://config?peer=...&port=...&pass=...
                peer_enc=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]peer=\([^&]*\).*/\1/p')
                peer=$(echo "$peer_enc" | sed 's/%3A/:/g; s/%3a/:/g') # Декодируем %3A в :
                
                HOST=$(echo "$peer" | cut -d':' -f1)
                DTLS=$(echo "$peer" | cut -d':' -f2)
                LOCAL=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]port=\([^&]*\).*/\1/p')
                PASSWORD=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]pass=\([^&]*\).*/\1/p')
                RAW_HASH=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]hashes=\([^&]*\).*/\1/p')
                
                req_workers=$(echo "$WDTT_LINK" | sed -n 's/.*[?&]workers=\([^&]*\).*/\1/p')
                if [ -n "$req_workers" ]; then
                    WORKERS="$req_workers"
                fi
                ;;
            wdtt://*:*:*:*:*:*)
                # Формат 3: wdtt://ip:port:wg_port:local_port:password:hash
                temp_link=$(echo "$WDTT_LINK" | sed 's|^wdtt://||')
                HOST=$(echo "$temp_link" | cut -d':' -f1)
                DTLS=$(echo "$temp_link" | cut -d':' -f2)
                # Третий параметр WG порт мы пропускаем (не используется для старта)
                LOCAL=$(echo "$temp_link" | cut -d':' -f4)
                PASSWORD=$(echo "$temp_link" | cut -d':' -f5)
                RAW_HASH=$(echo "$temp_link" | cut -d':' -f6-)
                ;;
            *)
                echo "❌ Неизвестный формат ссылки. Поддерживаются форматы wdtt://connect?..., qwdtt://config?..., wdtt://ip:port:..."
                continue
                ;;
        esac

        if [ -z "$HOST" ] || [ -z "$DTLS" ] || [ -z "$LOCAL" ] || [ -z "$PASSWORD" ] || [ -z "$RAW_HASH" ]; then
            echo "❌ Не удалось распарсить ссылку (отсутствуют обязательные параметры). Проверьте ссылку!"
            continue
        fi

        MAIN_HASH=$(clean_hash "$RAW_HASH")
        FINAL_HASHES="$MAIN_HASH"

        echo "================================================================="
        echo "✓ Основной хеш [1/4]: $MAIN_HASH"
        echo "================================================================="
        printf "Хотите добавить дополнительные хеши VK для ускорения? [y/N]: "
        read -r ADD_MORE < /dev/tty || true

        case "$ADD_MORE" in
            [Yy]*|[Дд]*)
                count=2
                while [ $count -le 4 ]; do
                    printf "Введите хеш #%d (или Enter, чтобы пропустить): " "$count"
                    read -r INPUT_HASH < /dev/tty || true
                    CLEANED=$(clean_hash "$INPUT_HASH")
                    if [ -z "$CLEANED" ]; then break; fi
                    FINAL_HASHES="${FINAL_HASHES},${CLEANED}"
                    echo "✓ Добавлен хеш #$count: $CLEANED"
                    count=$((count + 1))
                done
                ;;
        esac

        if "$INSTALL_DIR/$BIN_NAME" -check-hashes -vk "$FINAL_HASHES"; then
            echo "✅ Хеши валидны, продолжаю установку."
            break
        else
            echo "❌ Хеши не прошли проверку."
        fi
    done

    # ─────────────────────────── ОПРЕДЕЛЕНИЕ ИНТЕРФЕЙСА ───────────────────────────
    
    echo "Поиск свободного интерфейса Wireguard (через ядро Linux)..."
    IFACE_NUM=0
    while ip link show dev "nwg${IFACE_NUM}" >/dev/null 2>&1; do
        IFACE_NUM=$((IFACE_NUM+1))
    done
    WG_IFACE="Wireguard${IFACE_NUM}"
    KERNEL_WG_IFACE="nwg${IFACE_NUM}"
    echo "Выбран интерфейс: $WG_IFACE (ядро: $KERNEL_WG_IFACE)"

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

    while ! ping -c 1 -W 2 77.88.8.8 >/dev/null 2>&1; do
        sleep 5
    done

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
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 10; start ;;
    *) echo "Usage: \$0 {start|stop|restart}"; exit 1 ;;
esac
EOF

    chmod +x "$INIT_SCRIPT"

    # ─────────────────────────── СКРИПТ WATCHDOG ───────────────────────────

    echo "Создание скрипта watchdog..."
    cat > "$WATCHDOG_SCRIPT" << EOF
#!/bin/sh

PATH=/opt/bin:/opt/sbin:/opt/usr/bin:/bin:/usr/bin:/sbin
export PATH

LOG_FILE="${CONF_DIR}/wdtt-client.log"
MAX_SIZE_KB=1024
WG_IFACE="${KERNEL_WG_IFACE}"
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

# 2. ПРОВЕРКА: Запущен ли процесс вообще?
if ! pidof wdtt-client >/dev/null 2>&1; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [WATCHDOG] Процесс не найден. Запуск..." >> /opt/var/log/watchdog.log
    \$INIT_SCRIPT start
else
    # 3. ПРОВЕРКА: Если процесс жив, идет ли через него трафик?
    if ! ping -c 2 -W 3 -I "\$WG_IFACE" "\$PING_TARGET" > /dev/null 2>&1; then
        echo "\$(date '+%Y-%m-%d %H:%M:%S') [WATCHDOG] Процесс висит (пинг до Яндекса через \$WG_IFACE не прошел). Перезапуск..." >> /opt/var/log/watchdog.log
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

    echo "Запуск 1/2: Запускаю клиент для получения wg-turn.conf..."
    "$INIT_SCRIPT" start

    if ! wait_for_conf_with_log; then
        echo "⚠️ Попытка 1: Конфиг не появился за 60 секунд. Пробую перезапуск (2/2)..."
        "$INIT_SCRIPT" restart
        if ! wait_for_conf_with_log; then
            echo "⚠️ Внимание: Конфиг wg-turn.conf пока не получен."
            exit 0
        fi
    fi

    # ─────────────────────────── АВТОМАТИЧЕСКАЯ НАСТРОЙКА KEENETIC ───────────────────────────

    echo "✅ Конфиг успешно получен! Начинаю настройку KeeneticOS..."

    PRIV_KEY=$(grep -i '^PrivateKey' "$CONF_FILE" | sed 's/^[^=]*=//' | tr -d ' \r\n\t')
    PUB_KEY=$(grep -i '^PublicKey' "$CONF_FILE" | sed 's/^[^=]*=//' | tr -d ' \r\n\t')
    ADDRESS_CIDR=$(grep -i '^Address' "$CONF_FILE" | sed 's/^[^=]*=//' | cut -d ',' -f 1 | tr -d ' \r\n\t')
    ENDPOINT_FULL=$(grep -i '^Endpoint' "$CONF_FILE" | sed 's/^[^=]*=//' | tr -d ' \r\n\t')
    ALLOWED_IPS_CONF=$(grep -i '^AllowedIPs' "$CONF_FILE" | sed 's/^[^=]*=//' | cut -d ',' -f 1 | tr -d ' \r\n\t')
    DNS_CONF=$(grep -i '^DNS' "$CONF_FILE" | sed 's/^[^=]*=//' | tr -d ' \r\n\t')

    IP_ADDR=${ADDRESS_CIDR%/*}
    CIDR=${ADDRESS_CIDR#*/}
    if [ "$CIDR" = "32" ]; then IP_MASK="255.255.255.255"
    elif [ "$CIDR" = "24" ]; then IP_MASK="255.255.255.0"
    else IP_MASK="255.255.255.0"; fi

    ENDPOINT_ADDR=${ENDPOINT_FULL%:*}
    ENDPOINT_PORT=${ENDPOINT_FULL##*:}

    A_IP=${ALLOWED_IPS_CONF%/*}
    A_CIDR=${ALLOWED_IPS_CONF#*/}
    if [ "$A_CIDR" = "0" ]; then A_MASK="0.0.0.0"
    elif [ "$A_CIDR" = "32" ]; then A_MASK="255.255.255.255"
    elif [ "$A_CIDR" = "24" ]; then A_MASK="255.255.255.0"
    else A_MASK="0.0.0.0"; fi

    echo "Применяю настройки в NDM..."
    ndmq -p "interface $WG_IFACE" < /dev/null
    ndmq -p "interface $WG_IFACE description \"WDTT_Turn\"" < /dev/null
    ndmq -p "interface $WG_IFACE wireguard private-key $PRIV_KEY" < /dev/null
    ndmq -p "interface $WG_IFACE ip address $IP_ADDR $IP_MASK" < /dev/null
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY" < /dev/null
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY endpoint $ENDPOINT_ADDR $ENDPOINT_PORT" < /dev/null
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY endpoint $ENDPOINT_FULL" < /dev/null
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY endpoint $ENDPOINT_ADDR port $ENDPOINT_PORT" < /dev/null
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY allow-ips $A_IP $A_MASK" < /dev/null
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY allowed-ips $A_IP $A_MASK" < /dev/null
    ndmq -p "interface $WG_IFACE wireguard peer $PUB_KEY keepalive 25" < /dev/null

    if [ -n "$DNS_CONF" ]; then
        DNS_1=$(echo "$DNS_CONF" | cut -d ',' -f 1)
        DNS_2=$(echo "$DNS_CONF" | cut -d ',' -f 2)
        if [ -n "$DNS_1" ]; then
            ndmq -p "ip name-server $DNS_1 \"\" on $WG_IFACE" < /dev/null
            ndmq -p "ip name-server $DNS_1 on $WG_IFACE" < /dev/null
        fi
        if [ -n "$DNS_2" ] && [ "$DNS_2" != "$DNS_1" ]; then
            ndmq -p "ip name-server $DNS_2 \"\" on $WG_IFACE" < /dev/null
            ndmq -p "ip name-server $DNS_2 on $WG_IFACE" < /dev/null
        fi
    fi

    ndmq -p "interface $WG_IFACE ip global 10000" < /dev/null
    ndmq -p "interface $WG_IFACE up" < /dev/null
    ndmq -p "system configuration save" < /dev/null

    echo "════════════════════════════════════════════════════"
    echo "🎉 Все компоненты установлены, интерфейс $WG_IFACE создан!"
    echo "════════════════════════════════════════════════════"
}

run_installer "$@"
