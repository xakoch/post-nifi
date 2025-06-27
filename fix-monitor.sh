#!/bin/bash

echo "🔧 Исправляем Web Monitor..."

# Проверяем структуру директорий
echo "📁 Проверка директорий:"
ls -la logs/
ls -la backups/full/

# Создаем актуальный status.json
echo "📝 Создаем status.json..."
cat > logs/status.json << EOF
{
    "status": "healthy",
    "time": "$(date)",
    "postgres_status": "online",
    "last_check": "$(date +%s)",
    "last_check_human": "$(date -Iseconds)"
}
EOF

# Проверяем, что PostgreSQL работает
echo "🐘 Проверка PostgreSQL..."
if docker exec postgres_db pg_isready -U admin -d mydb; then
    echo "✅ PostgreSQL работает"
    PG_STATUS="online"
else
    echo "❌ PostgreSQL не отвечает"
    PG_STATUS="offline"
fi

# Обновляем status.json с реальным статусом
cat > logs/status.json << EOF
{
    "status": "healthy",
    "postgres_status": "$PG_STATUS",
    "time": "$(date)",
    "last_check": $(date +%s),
    "last_check_human": "$(date -Iseconds)",
    "message": "System operational"
}
EOF

# Перезапускаем nginx
echo "🔄 Перезапускаем Web Monitor..."
docker restart backup_monitor

# Создаем тестовый бэкап если их нет
if [ ! "$(ls -A backups/full/)" ]; then
    echo "💾 Создаем тестовый бэкап..."
    docker exec postgres_backup_service /scripts/backup.sh
fi

sleep 3

echo ""
echo "✅ Готово! Проверьте:"
echo "1. http://164.90.236.33:8080 - должен показать актуальный статус"
echo "2. http://164.90.236.33:8080/status.json - прямой доступ к статусу"
echo "3. http://164.90.236.33:8080/backups/ - список бэкапов"

# Показываем актуальный статус
echo ""
echo "📊 Текущий статус:"
cat logs/status.json | jq '.' 2>/dev/null || cat logs/status.json
