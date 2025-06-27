#!/bin/bash

echo "🔍 ДИАГНОСТИКА СИСТЕМЫ БЭКАПОВ"
echo "=============================="
echo ""

# Проверка контейнеров
echo "📦 Статус контейнеров:"
docker compose ps
echo ""

# Проверка портов
echo "🔌 Проверка портов:"
echo -n "  5432 (PostgreSQL): "
nc -zv localhost 5432 2>&1 | grep -q succeeded && echo "✅ Открыт" || echo "❌ Закрыт"
echo -n "  8080 (Web Monitor): "
nc -zv localhost 8080 2>&1 | grep -q succeeded && echo "✅ Открыт" || echo "❌ Закрыт"
echo -n "  8443 (NiFi): "
nc -zv localhost 8443 2>&1 | grep -q succeeded && echo "✅ Открыт" || echo "❌ Закрыт"
echo ""

# Проверка логов контейнеров с ошибками
echo "❌ Поиск ошибок в логах:"
echo ""

echo "PostgreSQL:"
docker logs postgres_db 2>&1 | grep -i error | tail -5
echo ""

echo "Backup Service:"
docker logs postgres_backup_service 2>&1 | grep -i error | tail -5
echo ""

echo "Web Monitor:"
docker logs backup_monitor 2>&1 | grep -i error | tail -5
echo ""

echo "NiFi:"
docker logs apache_nifi 2>&1 | grep -i error | tail -5
echo ""

# Проверка файловой системы
echo "📁 Проверка директорий:"
echo -n "  ./backups: "
[ -d "./backups" ] && echo "✅ Существует" || echo "❌ Не найдена"
echo -n "  ./logs: "
[ -d "./logs" ] && echo "✅ Существует" || echo "❌ Не найдена"
echo -n "  ./scripts: "
[ -d "./scripts" ] && echo "✅ Существует" || echo "❌ Не найдена"
echo -n "  ./monitor: "
[ -d "./monitor" ] && echo "✅ Существует" || echo "❌ Не найдена"
echo ""

# Проверка прав доступа
echo "🔐 Права на скрипты:"
ls -la scripts/*.sh 2>/dev/null || echo "Скрипты не найдены"
echo ""

# Проверка использования ресурсов
echo "💾 Использование ресурсов:"
docker stats --no-stream
echo ""

# Проверка сети Docker
echo "🌐 Docker сети:"
docker network ls
echo ""

# Рекомендации
echo "💡 РЕКОМЕНДАЦИИ:"
echo "==============="

# Проверяем каждый контейнер
if ! docker ps | grep -q postgres_db; then
    echo "⚠️  PostgreSQL не запущен. Выполните: docker compose up -d postgres"
fi

if ! docker ps | grep -q postgres_backup_service; then
    echo "⚠️  Backup Service не запущен. Выполните: docker compose up -d backup_service"
fi

if ! docker ps | grep -q backup_monitor; then
    echo "⚠️  Web Monitor не запущен. Выполните: docker compose up -d backup_monitor"
fi

if ! docker ps | grep -q apache_nifi; then
    echo "⚠️  NiFi не запущен. Выполните: docker compose up -d nifi"
fi

# Проверка конфигурации
if [ ! -f ".env" ]; then
    echo "⚠️  Файл .env не найден. Создайте его из примера выше."
fi

if [ ! -f "nginx.conf" ]; then
    echo "⚠️  Файл nginx.conf не найден. Создайте его из примера выше."
fi

echo ""
echo "Для полного перезапуска используйте: ./restart.sh"
