#!/bin/sh
# hyper-install.sh — Единый скрипт установки WDTT + nfqws2 + XKeen + Mihomo (Entware)
set -e

REPO_URL="https://raw.githubusercontent.com/redline-keen/wdtt-xkeen/main"
WG_CONF="/opt/etc/wdtt/wg-turn.conf"

echo "════════════════════════════════════════════════════"
echo " 🚀 ЭТАП 1/2: Установка WDTT-клиента"
echo "════════════════════════════════════════════════════"

opkg update >/dev/null 2>&1 || true
opkg install wget-ssl ca-bundle curl >/dev/null 2>&1 || true

echo "Выберите вариант установки WDTT:"
echo "  1) RAW-режим (v1.1 — интерфейс wdtt0, прямое TCP/rawtun)"
echo "  2) Classic WireGuard (v1.0 — автонастройка через Keenetic NDM)"
echo "  3) Пропустить установку WDTT"

while :; do
    printf "\nВаш выбор [1-3] (по умолчанию: 1): "
    read -r WDTT_CHOICE < /dev/tty || true
    [ -z "$WDTT_CHOICE" ] && WDTT_CHOICE="1"

    case "$WDTT_CHOICE" in
        1)
            echo "Скачиваю install-wdtt.sh (RAW режим)..."
            wget --no-check-certificate -q -O /tmp/install-wdtt.sh "${REPO_URL}/install-wdtt.sh"
            sh /tmp/install-wdtt.sh < /dev/tty
            break
            ;;
        2)
            echo "Скачиваю install-wdtt-old.sh (WireGuard режим)..."
            wget --no-check-certificate -q -O /tmp/install-wdtt-old.sh "${REPO_URL}/install-wdtt-old.sh"
            sh /tmp/install-wdtt-old.sh < /dev/tty
            break
            ;;
        3)
            echo "Пропуск установки WDTT."
            break
            ;;
        *)
            echo "❌ Неверный ввод, введите 1, 2 или 3."
            ;;
    esac
done

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
if [ "$WDTT_CHOICE" = "1" ]; then
    if ip link show wdtt0 >/dev/null 2>&1; then
        echo "✅ Интерфейс wdtt0 (RAW) активен и готов к работе."
    else
        echo "⚠️ Интерфейс wdtt0 не обнаружен. Проверьте: cat /opt/etc/wdtt/wdtt-client.log"
    fi
elif [ "$WDTT_CHOICE" = "2" ]; then
    if [ -f "$WG_CONF" ]; then
        echo "📋 Конфигурация WireGuard для Keenetic:"
        echo "────────────────────────────────────────────────────"
        cat "$WG_CONF"
        echo "────────────────────────────────────────────────────"
    else
        echo "⚠️ Файл конфигурации $WG_CONF не найден."
    fi
fi
