#!/bin/bash

echo "🛑 Останавливаем ВСЕ контейнеры проекта..."
docker compose down --remove-orphans

# Удаляем старые контейнеры если остались
echo "🧹 Удаляем старые контейнеры..."
docker rm -f postgres_backup apache_nifi 2>/dev/null || true

echo "🧹 Очищаем старые логи..."
rm -f logs/*.log
echo '{"status":"initializing","time":"'$(date)'"}' > logs/status.json

# Проверяем и создаем директории
echo "📁 Проверяем директории..."
mkdir -p backups/full backups/wal logs monitor scripts

echo "🚀 Запускаем PostgreSQL..."
docker compose up -d postgres

echo "⏳ Ждем готовности PostgreSQL (30 сек)..."
sleep 30

# Проверяем PostgreSQL
until docker exec postgres_db pg_isready -U admin -d mydb; do
    echo "Ждем PostgreSQL..."
    sleep 5
done
echo "✅ PostgreSQL готов!"

echo "🚀 Запускаем Backup Service..."
docker compose up -d backup_service

echo "⏳ Ждем инициализации Backup Service (10 сек)..."
sleep 10

echo "🚀 Запускаем Web Monitor..."
docker compose up -d backup_monitor

echo "🚀 Запускаем NiFi..."
docker compose up -d nifi

echo "⏳ Ждем запуска всех сервисов (20 сек)..."
sleep 20

echo ""
echo "📊 Статус контейнеров:"
docker compose ps

echo ""
echo "🔍 Проверка сервисов:"

# Проверка PostgreSQL
if docker exec postgres_db pg_isready -U admin -d mydb > /dev/null 2>&1; then
    echo "✅ PostgreSQL: Работает"
else
    echo "❌ PostgreSQL: Не работает"
fi

# Проверка Backup Service
if docker ps | grep -q postgres_backup_service; then
    echo "✅ Backup Service: Работает"
else
    echo "❌ Backup Service: Не работает"
fi

# Проверка Web Monitor
if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo "✅ Web Monitor: Работает (http://164.90.236.33:8080)"
else
    echo "❌ Web Monitor: Не работает"
fi

# Проверка NiFi
if curl -k https://localhost:8443/nifi/ > /dev/null 2>&1; then
    echo "✅ NiFi: Работает (https://164.90.236.33:8443/nifi)"
else
    echo "⚠️  NiFi: Запускается (подождите 1-2 минуты)"
fi

echo ""
echo "📝 Последние логи backup service:"
docker logs postgres_backup_service --tail 5 2>/dev/null || echo "Логи недоступны"

echo ""
echo "✨ Система запущена!"
echo ""
echo "📌 Доступы:"
echo "  Web Monitor: http://164.90.236.33:8080"
echo "  NiFi: https://164.90.236.33:8443/nifi (admin/password123456789)"
echo "  PostgreSQL: 164.90.236.33:5432 (admin/mypassword123)"
