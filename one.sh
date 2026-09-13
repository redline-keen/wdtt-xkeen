#!/bin/sh
set -e

# ─────────────────────────── КОНФИГУРАЦИЯ ПУТЕЙ ───────────────────────────

CONF_DIR="/opt/etc/wdtt"
INSTALL_DIR="/opt/etc/wdtt"
BIN_NAME="wdtt-client"
INIT_SCRIPT="/opt/etc/init.d/S99wdtt-client"
CRON_FILE="/opt/var/spool/cron/crontabs/root"
LOG_FILE="/opt/var/log/wdtt.log"
UNINSTALL_SCRIPT="$CONF_DIR/wdtt-uninstall"

echo "════════════════════════════════════════════════════"
echo "   Установка и настройка WDTT-клиента (Keenetic/Entware)"
echo "════════════════════════════════════════════════════"

# 1. Подготовка структуры каталогов в /opt
mkdir -p "$INSTALL_DIR" "$CONF_DIR" /opt/var/log /opt/var/spool/cron/crontabs /opt/etc/init.d

# 2. Установка зависимостей Entware
echo "Обновление пакетов и установка зависимостей..."
opkg update >/dev/null 2>&1 || true
opkg install ca-bundle wget-ssl cron nano >/dev/null 2>&1 || true

# ─────────────────────────── СКРИПТ УДАЛЕНИЯ ───────────────────────────

echo "Создание скрипта удаления $UNINSTALL_SCRIPT..."
cat << 'EOF' > "$UNINSTALL_SCRIPT"
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

# 2. Очистка cron (только в /opt)
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

# 4. Удаление директории и конфигураций
rm -rf "$CONF_DIR"
echo "✓ Файлы программы и конфигурации удалены."

echo "════════════════════════════════════════════════════"
echo "✅ WDTT-клиент полностью снесён с роутера!"
echo "════════════════════════════════════════════════════"
EOF

chmod +x "$UNINSTALL_SCRIPT"

# ─────────────────────────── СЛУЖБА INIT.D ───────────────────────────

echo "Создание службы автозапуска $INIT_SCRIPT..."
cat << 'EOF' > "$INIT_SCRIPT"
#!/bin/sh

ENABLED=yes
PROG="/opt/etc/wdtt/wdtt-client"
CONF="/opt/etc/wdtt/wdtt.json"
ARGS="-c $CONF"
PREARGS=""
DESC="WDTT Client Service"
LOGFILE="/opt/var/log/wdtt.log"

start() {
    echo "Запуск $DESC..."
    if [ ! -f "$PROG" ]; then
        echo "Ошибка: Бинарный файл $PROG не найден!"
        exit 1
    fi
    $PROG $ARGS >> "$LOGFILE" 2>&1 &
    echo "$DESC успешно запущен."
}

stop() {
    echo "Остановка $DESC..."
    killall -9 wdtt-client 2>/dev/null || true
    ip link del wdtt0 2>/dev/null || true
    echo "$DESC остановлен."
}

restart() {
    stop
    sleep 1
    start
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    *)
        echo "Использование: $0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF

chmod +x "$INIT_SCRIPT"

# ─────────────────────────── НАСТРОЙКА CRON ───────────────────────────

echo "Проверка и настройка планировщика cron..."
touch "$CRON_FILE"
if ! grep -q "$INIT_SCRIPT" "$CRON_FILE"; then
    echo "*/5 * * * * [ -x $INIT_SCRIPT ] && $INIT_SCRIPT start >/dev/null 2>&1" >> "$CRON_FILE"
    chmod 600 "$CRON_FILE"
    echo "✓ Задача контроля процессов добавлена в cron."
fi

# Перезапуск службы cron в Entware (если запущен)
[ -x /opt/etc/init.d/S10cron ] && /opt/etc/init.d/S10cron restart >/dev/null 2>&1 || true

echo "════════════════════════════════════════════════════"
echo "✅ Готово! Все пути скорректированы строго под /opt"
echo "Скрипт удаления: $UNINSTALL_SCRIPT"
echo "════════════════════════════════════════════════════"
