#!/bin/bash

echo "⚠️  ПОЛНАЯ ОЧИСТКА СИСТЕМЫ"
echo "Это удалит ВСЕ контейнеры и volumes!"
echo "Введите 'YES' для подтверждения:"
read -r confirmation

if [ "$confirmation" != "YES" ]; then
    echo "Отменено"
    exit 1
fi

echo "🛑 Останавливаем все контейнеры..."
docker compose down -v --remove-orphans

echo "🗑️  Удаляем оставшиеся контейнеры..."
docker rm -f postgres_backup apache_nifi postgres_db backup_monitor postgres_backup_service 2>/dev/null || true

echo "🧹 Очищаем Docker volumes..."
docker volume prune -f

echo "📁 Создаем чистые директории..."
rm -rf backups/* logs/*
mkdir -p backups/full backups/wal logs monitor scripts

echo "✅ Система очищена!"
echo ""
echo "Теперь запустите: ./restart.sh"
