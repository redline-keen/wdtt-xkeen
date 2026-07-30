#!/bin/sh
# Установка XKeen, сжатие mihomo через UPX и деплой config.yaml
set -e

CONFIG_URL="https://raw.githubusercontent.com/redline-keen/wdtt-xkeen/main/config.yaml"
MIHOMO_DIR="/opt/etc/mihomo"

echo "=== 1. Установка XKeen ==="
opkg update && opkg upgrade && opkg install curl tar upx wget-ssl ca-bundle && cd /tmp
sh -c "$(curl -sSL https://raw.githubusercontent.com/jameszeroX/XKeen/main/install.sh)"

echo "=== 2. Сжатие бинарника mihomo через UPX ==="
# Глушим процессы перед сжатием
if command -v xkeen >/dev/null 2>&1; then
    xkeen -stop >/dev/null 2>&1 || true
fi
if [ -x /opt/etc/init.d/S99mihomo ]; then
    /opt/etc/init.d/S99mihomo stop >/dev/null 2>&1 || true
fi
killall -9 mihomo 2>/dev/null || true

# Ищем бинарник mihomo
BIN_MIHOMO=""
for path in /opt/usr/bin/mihomo /opt/bin/mihomo /opt/sbin/mihomo; do
    if [ -f "$path" ]; then
        BIN_MIHOMO="$path"
        break
    fi
done

if [ -n "$BIN_MIHOMO" ]; then
    echo "Найден бинарник: $BIN_MIHOMO"
    upx --lzma --best "$BIN_MIHOMO" || upx -9 "$BIN_MIHOMO" || echo "⚠️ Предупреждение UPX (файл обработан)"
else
    echo "❌ Бинарник mihomo не найден!"
fi

echo "=== 3. Загрузка config.yaml ==="
mkdir -p "$MIHOMO_DIR"

# Пробуем скачать через curl, а если его нет — через wget с жесткими таймаутами
if command -v curl >/dev/null 2>&1; then
    curl -sSL --connect-timeout 10 -o "$MIHOMO_DIR/config.yaml" "$CONFIG_URL"
else
    wget --no-check-certificate -T 15 -t 3 -O "$MIHOMO_DIR/config.yaml" "$CONFIG_URL"
fi

if [ -s "$MIHOMO_DIR/config.yaml" ]; then
    echo "✅ Конфиг успешно загружен в $MIHOMO_DIR/config.yaml"
else
    echo "❌ Ошибка: файл $CONFIG_URL не скачался или пуст!"
    exit 1
fi

echo "=== 4. Запуск ==="
if command -v xkeen >/dev/null 2>&1; then
    xkeen -start || true
elif [ -x /opt/etc/init.d/S99mihomo ]; then
    /opt/etc/init.d/S99mihomo start || true
fi

echo "🎉 Готово!"
