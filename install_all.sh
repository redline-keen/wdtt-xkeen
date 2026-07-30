#!/bin/sh
# install_all.sh — Установка зависимостей, nfqws2, XKeen и настройка wdtt
set -e

echo "=== 1. Подготовка системы и пакетов Entware ==="
opkg update
opkg install ca-certificates wget-ssl ca-bundle upx curl tar
opkg remove wget-nossl 2>/dev/null || true

echo "=== 2. Подключение и установка nfqws2-keenetic ==="
mkdir -p /opt/etc/opkg
echo "src/gz nfqws2-keenetic https://nfqws.github.io/nfqws2-keenetic/all" > /opt/etc/opkg/nfqws2-keenetic.conf
opkg update
opkg install nfqws2-keenetic

echo "=== 3. Загрузка и запуск основного скрипта setup-xkeen.sh ==="
curl -sSL -o /tmp/setup-xkeen.sh https://raw.githubusercontent.com/redline-keen/wdtt-xkeen/main/setup-xkeen.sh
sh /tmp/setup-xkeen.sh
