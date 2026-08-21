#!/bin/sh
# install-raw-with-xkeen.sh — Единый скрипт установки qWDTT-RAW + nfqws2 + XKeen + Mihomo
set -e

REPO_URL="https://raw.githubusercontent.com/redline-keen/wdtt-xkeen/main"

echo "════════════════════════════════════════════════════"
echo " 🚀 ЭТАП 1/2: Запуск установки WDTT-RAW клиента"
echo "════════════════════════════════════════════════════"

opkg update
opkg install wget-ssl ca-bundle curl

echo "Скачиваю install-wdtt.sh..."
wget --no-check-certificate -O /tmp/install-wdtt.sh "${REPO_URL}/install-wdtt.sh"
sh /tmp/install-wdtt.sh < /dev/tty

echo ""
echo "════════════════════════════════════════════════════"
echo " 🚀 ЭТАП 2/2: Запуск установки nfqws2 + XKeen/Mihomo"
echo "════════════════════════════════════════════════════"

echo "Скачиваю install_all-raw.sh..."
curl -sSL -o /tmp/install_all-raw.sh "${REPO_URL}/install_all-raw.sh"
sh /tmp/install_all-raw.sh < /dev/tty

echo ""
echo "════════════════════════════════════════════════════"
echo "🎉 Установка qWDTT+Xkeen УСПЕШНО ЗАВЕРШЕНА!"
echo "════════════════════════════════════════════════════"

