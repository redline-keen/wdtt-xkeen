#!/bin/sh
# install_all-raw.sh — Установка зависимостей, nfqws2, XKeen и настройка wdtt
set -e

# Функция безопасного обновления списков пакетов с ретраями
opkg_update_retry() {
    local max_attempts=5
    local attempt=1
    local delay=3

    while [ "$attempt" -le "$max_attempts" ]; do
        echo "Попытка $attempt/$max_attempts: opkg update..."
        if opkg update; then
            echo "✅ Списки пакетов успешно обновлены."
            return 0
        fi
        echo "⚠️ Ошибка сети при обновлении списков. Повтор через ${delay} сек..."
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay + 2))
    done

    echo "❌ Ошибка: не удалось обновить списки пакетов за $max_attempts попыток." >&2
    return 1
}

# Функция установки пакетов с ретраями
opkg_install_retry() {
    local pkgs="$*"
    local max_attempts=3
    local attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
        echo "Установка [$pkgs] (попытка $attempt/$max_attempts)..."
        if opkg install $pkgs; then
            return 0
        fi
        echo "⚠️ Сбой скачивания пакетов. Повтор через 3 сек..."
        sleep 3
        attempt=$((attempt + 1))
    done

    echo "❌ Ошибка: не удалось установить [$pkgs]!" >&2
    return 1
}

echo "=== 1. Подготовка системы и пакетов Entware ==="
opkg_update_retry
opkg_install_retry ca-certificates wget-ssl ca-bundle upx curl tar
opkg remove wget-nossl 2>/dev/null || true

echo "=== 2. Подключение и установка nfqws2-keenetic ==="
mkdir -p /opt/etc/opkg
echo "src/gz nfqws2-keenetic https://nfqws.github.io/nfqws2-keenetic/all" > /opt/etc/opkg/nfqws2-keenetic.conf
opkg_update_retry
opkg_install_retry nfqws2-keenetic

echo "=== 3. Загрузка и запуск основного скрипта setup-xkeen-raw.sh ==="
curl -sSL --retry 3 --retry-delay 2 -o /tmp/setup-xkeen-raw.sh https://raw.githubusercontent.com/redline-keen/wdtt-xkeen/main/setup-xkeen-raw.sh
sh /tmp/setup-xkeen-raw.sh < /dev/tty
