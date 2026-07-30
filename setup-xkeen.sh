#!/bin/sh
# Установка XKeen (jameszeroX/XKeen), сжатие бинарника mihomo через UPX 
# и деплой config.yaml для Entware/Keenetic
set -e

# ─────────────────────────── НАСТРОЙКИ ───────────────────────────
MIHOMO_DIR="/opt/etc/mihomo"
CONFIG_URL="https://raw.githubusercontent.com/redline-keen/wdtt-xkeen/main/config.yaml"

echo "════════════════════════════════════════════════════"
echo " 1. Установка XKeen и необходимых утилит"
echo "════════════════════════════════════════════════════"

opkg update
opkg install wget-ssl ca-bundle upx

# Установка XKeen из официального репозитория jameszeroX/XKeen
if command -v xkeen >/dev/null 2>&1; then
    echo "✓ XKeen уже установлен."
else
    echo "Скачивание и запуск официального инсталлятора XKeen..."
    wget -O - https://raw.githubusercontent.com/jameszeroX/XKeen/main/installer.sh | sh
fi

echo "════════════════════════════════════════════════════"
echo " 2. Поиск и сжатие бинарника mihomo через UPX"
echo "════════════════════════════════════════════════════"

# Останавливаем службы, чтобы запущенный бинарник не был заблокирован (Text file busy)
if [ -x /opt/etc/init.d/S99mihomo ]; then
    /opt/etc/init.d/S99mihomo stop >/dev/null 2>&1 || true
fi
if command -v xkeen >/dev/null 2>&1; then
    xkeen -stop >/dev/null 2>&1 || true
fi
killall -9 mihomo 2>/dev/null || true

# Поиск пути к бинарнику mihomo в Entware
BIN_MIHOMO=""
for path in /opt/usr/bin/mihomo /opt/bin/mihomo /opt/sbin/mihomo; do
    if [ -f "$path" ]; then
        BIN_MIHOMO="$path"
        break
    fi
done

if [ -z "$BIN_MIHOMO" ]; then
    BIN_MIHOMO=$(which mihomo 2>/dev/null || true)
fi

if [ -n "$BIN_MIHOMO" ] && [ -f "$BIN_MIHOMO" ]; then
    SIZE_BEFORE=$(ls -lh "$BIN_MIHOMO" | awk '{print $5}')
    echo "Путь к бинарнику: $BIN_MIHOMO"
    echo "Размер mihomo до сжатия: $SIZE_BEFORE"
    
    echo "Сжимаю бинарник (это может занять около минуты на слабых процессорах)..."
    upx --lzma --best "$BIN_MIHOMO" || upx -9 "$BIN_MIHOMO" || echo "⚠️ UPX выдал предупреждение, но файл сжат."
    
    SIZE_AFTER=$(ls -lh "$BIN_MIHOMO" | awk '{print $5}')
    echo "✅ Размер mihomo после сжатия: $SIZE_AFTER"
else
    echo "❌ Бинарник mihomo не найден. Проверьте, установил ли XKeen компонент mihomo."
fi

echo "════════════════════════════════════════════════════"
echo " 3. Загрузка и замена config.yaml"
echo "════════════════════════════════════════════════════"

mkdir -p "$MIHOMO_DIR"

echo "Скачиваю config.yaml в $MIHOMO_DIR/config.yaml..."
wget --no-check-certificate -q -O "$MIHOMO_DIR/config.yaml" "$CONFIG_URL"

if [ -s "$MIHOMO_DIR/config.yaml" ]; then
    echo "✅ Файл конфигурации успешно загружен."
else
    echo "❌ Ошибка: Не удалось скачать config.yaml по ссылке $CONFIG_URL"
    exit 1
fi

# ─────────────────────────── ЗАПУСК ───────────────────────────

echo "════════════════════════════════════════════════════"
echo " 4. Запуск служб"
echo "════════════════════════════════════════════════════"

if command -v xkeen >/dev/null 2>&1; then
    xkeen -start || true
elif [ -x /opt/etc/init.d/S99mihomo ]; then
    /opt/etc/init.d/S99mihomo start || true
fi

echo ""
echo "🎉 Установка XKeen, сжатие Mihomo и деплой конфига успешно завершены!"
