#!/bin/sh
# hyper_install.sh — Единый скрипт установки WDTT + nfqws2 + XKeen + Mihomo (Entware)
set -e

REPO_URL="https://raw.githubusercontent.com/redline-keen/wdtt-xkeen/main"
WG_CONF="/opt/etc/wdtt/wg-turn.conf"

echo "════════════════════════════════════════════════════"
echo " 🚀 ЭТАП 1/2: Запуск установки WDTT-клиента"
echo "════════════════════════════════════════════════════"

opkg update
opkg install wget-ssl ca-bundle curl

echo "Скачиваю install-wdtt-old.sh..."
wget --no-check-certificate -O /tmp/install-wdtt.sh "${REPO_URL}/install-wdtt-old.sh"
sh /tmp/install-wdtt.sh < /dev/tty

echo ""
echo "════════════════════════════════════════════════════"
echo " 🚀 ЭТАП 2/2: Запуск установки nfqws2 + XKeen + Mihomo"
echo "════════════════════════════════════════════════════"

echo "Скачиваю install_all.sh..."
curl -sSL -o /tmp/install_all.sh "${REPO_URL}/install_all.sh"
sh /tmp/install_all.sh < /dev/tty

echo ""
echo "════════════════════════════════════════════════════"
echo "🎉 ГИПЕР-УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!"
echo "════════════════════════════════════════════════════"

echo ""
if [ -f "$WG_CONF" ]; then
    echo "📋 Скопируйте WireGuard конфиг для Keenetic:"
    echo "────────────────────────────────────────────────────"
    cat "$WG_CONF"
    echo "────────────────────────────────────────────────────"
else
    echo "⚠️ Файл конфигурации $WG_CONF не найден."
fi
