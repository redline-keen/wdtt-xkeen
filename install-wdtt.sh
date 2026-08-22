#!/bin/sh
# install-wdtt-raw.sh — установка WDTT-клиента в RAW-режиме (rawtun + TCP) на Entware/Keenetic
set -e

run_installer() {

    # Жестко задаем пути, чтобы скрипт точно находил системные утилиты
    export PATH="/opt/bin:/opt/sbin:/opt/usr/bin:/bin:/usr/bin:/sbin:/usr/sbin"

    # ─────────────────────────── НАСТРОЙКИ ───────────────────────────

    GH_OWNER="redline-keen"
    GH_REPO="wdtt-xkeen"
    GH_TAG="1.1"

    ASSET_MIPSLE="wdtt-client-mipsle"
    ASSET_ARM64="wdtt-client-arm64"

    INSTALL_DIR="/opt/usr/bin"
    CONF_DIR="/opt/etc/wdtt"
    BIN_NAME="wdtt-client"
    INIT_SCRIPT="/opt/etc/init.d/S99wdtt-client"
    WATCHDOG_SCRIPT="$CONF_DIR/wdtt-watchdog.sh"

    WORKERS="36"
    RAW_PORT="56003"
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

    mkdir -p "$INSTALL_DIR" "$CONF_DIR"

    # ─────────────────────────── СОЗДАНИЕ СКРИПТА WDTT-UNINSTALL ───────────────────────────

    echo "Создание скрипта удаления /opt/usr/bin/wdtt-uninstall..."
    cat << 'EOF' > /opt/usr/bin/wdtt-uninstall
#!/bin/sh
set -e

echo "════════════════════════════════════════════════════"
echo " Начинаю полное удаление WDTT-клиента (RAW)..."
echo "════════════════════════════════════════════════════"

CONF_DIR="/opt/etc/wdtt"
INSTALL_DIR="/opt/usr/bin"
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

# 4. Удаление бинарника и конфигураций
rm -f "$INSTALL_DIR/$BIN_NAME"
rm -rf "$CONF_DIR"
echo "✓ Файлы программы и конфигурации удалены."

# 5. Самоудаление
rm -f /opt/usr/bin/wdtt-uninstall

echo "════════════════════════════════════════════════════"
echo "✅ WDTT-клиент (RAW) полностью снесён с роутера!"
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

        if [ -z "$HOST" ] || [ -z "$PASSWORD" ] || [ -z "$RAW_HASH" ]; then
            echo "❌ Не удалось распарсить ссылку (отсутствуют обязательные параметры). Проверьте ссылку!"
            continue
        fi

        # Интерактивный ввод количества воркеров
        printf "Введите количество воркеров [текущее/по умолчанию: %s]: " "$WORKERS"
        read -r INPUT_WORKERS < /dev/tty || true
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

    # ─────────────────────────── INIT.D СКРИПТ (ENTWARE) ───────────────────────────

    cat > "$INIT_SCRIPT" << EOF
#!/bin/sh
# Автозапуск wdtt-client (RAW mode) на Entware (Keenetic)

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

    killall -9 wdtt-client 2>/dev/null || true

    echo "Starting wdtt-client (RAW mode)..."
    
    \$PROG \\
        -mode rawtun \\
        -turn-tcp \\
        -peer ${HOST}:${RAW_PORT} \\
        -password '${PASSWORD}' \\
        -vk '${FINAL_HASHES}' \\
        -device-id '${DEVICE_ID}' \\
        -n ${WORKERS} \\
        -tun-name wdtt0 \\
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

PATH=/opt/bin:/opt/sbin:/opt/usr/bin:/bin:/usr/bin:/sbin
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
    else
        echo "⚠️ Внимание: Интерфейс wdtt0 еще поднимается или требует проверки логов."
        echo "Посмотреть логи можно командой: cat /opt/etc/wdtt/wdtt-client.log"
    fi
    echo "════════════════════════════════════════════════════"
}

run_installer "$@"
