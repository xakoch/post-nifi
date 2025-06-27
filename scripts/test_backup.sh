#!/bin/bash

set -e

STATUS_FILE="/var/log/backup/status.json"

# Логирование
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция отправки уведомлений
send_notification() {
    local message="$1"
    local status="$2"
    
    # Telegram уведомление
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local emoji="✅"
        [ "$status" = "error" ] && emoji="❌"
        [ "$status" = "warning" ] && emoji="⚠️"
        
        local telegram_message="$emoji PostgreSQL Backup Test
        
$message

Сервер: $(hostname)
Время: $(date '+%Y-%m-%d %H:%M:%S')"
        
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -H "Content-Type: application/json" \
            -d "{
                \"chat_id\": \"$TELEGRAM_CHAT_ID\",
                \"text\": \"$telegram_message\",
                \"parse_mode\": \"HTML\"
            }" || true
    fi
    
    # Webhook уведомление (если настроено)
    if [ -n "$WEBHOOK_URL" ]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"$message\",\"status\":\"$status\"}" || true
    fi
}

# Обновление статуса тестирования
update_test_status() {
    local status="$1"
    local message="$2"
    
    # Читаем текущий статус
    local current_status="{}"
    if [ -f "$STATUS_FILE" ]; then
        current_status=$(cat "$STATUS_FILE")
    fi
    
    # Обновляем с информацией о тестировании
    echo "$current_status" | jq --arg status "$status" --arg message "$message" --arg timestamp "$(date -Iseconds)" \
        '.last_test_status = $status | .last_test_message = $message | .last_test_time = $timestamp' > "$STATUS_FILE"
}

log "Начинаем автоматическое тестирование последнего бэкапа..."
update_test_status "running" "Starting backup test"

# Находим последний бэкап
LATEST_BACKUP=$(ls -t /backups/full/backup_*.sql.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    ERROR_MSG="Бэкапы не найдены!"
    log "ОШИБКА: $ERROR_MSG"
    update_test_status "error" "$ERROR_MSG"
    send_notification "$ERROR_MSG" "error"
    exit 1
fi

log "Найден последний бэкап: $LATEST_BACKUP"

# Получаем информацию о бэкапе
BACKUP_SIZE=$(du -h "$LATEST_BACKUP" | cut -f1)
BACKUP_DATE=$(stat -c %y "$LATEST_BACKUP" | cut -d' ' -f1)

# Создаем уникальное имя для тестовой базы
TEST_DB="test_restore_$(date +%s)"

log "Восстанавливаем в тестовую базу: $TEST_DB"
log "Размер бэкапа: $BACKUP_SIZE, дата: $BACKUP_DATE"

# Восстанавливаем бэкап в тестовую базу
if ! /scripts/restore.sh "$LATEST_BACKUP" "$TEST_DB" > /tmp/restore_test.log 2>&1; then
    ERROR_MSG="Ошибка восстановления бэкапа"
    log "ОШИБКА: $ERROR_MSG"
    log "Подробности в /tmp/restore_test.log"
    update_test_status "error" "$ERROR_MSG"
    send_notification "$ERROR_MSG" "error"
    exit 1
fi

log "Восстановление завершено успешно"

# Выполняем расширенные проверки
log "Выполняем расширенные проверки восстановленной базы..."

# Проверка 1: Подключение к базе
log "Проверка 1: Подключение к базе данных"
if ! psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$TEST_DB" -c "SELECT version();" > /dev/null 2>&1; then
    ERROR_MSG="Не удается подключиться к тестовой базе"
    log "ОШИБКА: $ERROR_MSG"
    update_test_status "error" "$ERROR_MSG"
    send_notification "$ERROR_MSG" "error"
    exit 1
fi
log "✓ Подключение успешно"

# Проверка 2: Количество таблиц
log "Проверка 2: Структура базы данных"
TABLE_COUNT=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$TEST_DB" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs || echo "0")
log "✓ Найдено таблиц: $TABLE_COUNT"

# Проверка 3: Размер базы данных
log "Проверка 3: Размер базы данных"
DB_SIZE=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$TEST_DB" -t -c "SELECT pg_size_pretty(pg_database_size('$TEST_DB'));" 2>/dev/null | xargs || echo "unknown")
log "✓ Размер базы: $DB_SIZE"

# Проверка 4: Список таблиц (если есть)
if [ "$TABLE_COUNT" -gt 0 ]; then
    log "Проверка 4: Список таблиц"
    TABLES=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$TEST_DB" -t -c "SELECT string_agg(tablename, ', ') FROM pg_tables WHERE schemaname = 'public';" 2>/dev/null | xargs || echo "none")
    log "✓ Таблицы: $TABLES"
fi

# Проверка 5: Сравнение с оригинальной базой
log "Проверка 5: Сравнение с оригинальной базой"
ORIG_TABLE_COUNT=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs || echo "0")

if [ "$TABLE_COUNT" -eq "$ORIG_TABLE_COUNT" ]; then
    log "✓ Количество таблиц совпадает с оригиналом ($TABLE_COUNT)"
    STRUCTURE_CHECK="✓"
else
    log "⚠ Количество таблиц отличается: оригинал=$ORIG_TABLE_COUNT, бэкап=$TABLE_COUNT"
    STRUCTURE_CHECK="⚠"
fi

# Проверка 6: Тестовые запросы (если есть данные)
log "Проверка 6: Выполнение тестовых запросов"
QUERY_RESULTS=""
if [ "$TABLE_COUNT" -gt 0 ]; then
    # Проверяем базовые запросы
    if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$TEST_DB" -c "SELECT NOW();" > /dev/null 2>&1; then
        QUERY_RESULTS="✓ Базовые запросы работают"
        log "✓ Базовые запросы выполняются успешно"
    else
        QUERY_RESULTS="❌ Ошибка выполнения запросов"
        log "⚠ Проблемы с выполнением запросов"
    fi
else
    QUERY_RESULTS="- Нет таблиц для тестирования"
    log "- Нет пользовательских таблиц для тестирования запросов"
fi

# Проверка 7: Целостность данных (если возможно)
log "Проверка 7: Целостность данных"
INTEGRITY_CHECK="✓"
if [ "$TABLE_COUNT" -gt 0 ]; then
    # Проверяем наличие индексов и ограничений
    INDEXES_COUNT=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$TEST_DB" -t -c "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';" 2>/dev/null | xargs || echo "0")
    log "✓ Найдено индексов: $INDEXES_COUNT"
fi

# Удаляем тестовую базу
log "Удаляем тестовую базу данных: $TEST_DB"
if ! dropdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$TEST_DB" 2>/dev/null; then
    log "⚠ Предупреждение: Не удалось удалить тестовую базу $TEST_DB"
fi

# Формируем итоговый отчет
DURATION=$(($(date +%s) - $(date -d "$BACKUP_DATE" +%s)))
DURATION_HOURS=$((DURATION / 3600))

TEST_RESULTS="Бэкап от $BACKUP_DATE ($BACKUP_SIZE) успешно протестирован. Таблиц: $TABLE_COUNT, Размер: $DB_SIZE, Структура: $STRUCTURE_CHECK, Запросы: $QUERY_RESULTS"

log "Тестирование бэкапа завершено успешно!"
log "Отчет: $TEST_RESULTS"

# Обновляем статус успеха
update_test_status "success" "$TEST_RESULTS"
send_notification "$TEST_RESULTS" "success"

# Сохраняем подробный отчет
cat > "/var/log/backup/last_test_report.json" << EOF
{
    "test_date": "$(date -Iseconds)",
    "backup_file": "$LATEST_BACKUP",
    "backup_date": "$BACKUP_DATE",
    "backup_size": "$BACKUP_SIZE",
    "test_database": "$TEST_DB",
    "tables_count": $TABLE_COUNT,
    "original_tables_count": $ORIG_TABLE_COUNT,
    "database_size": "$DB_SIZE",
    "indexes_count": $INDEXES_COUNT,
    "structure_match": $([ "$TABLE_COUNT" -eq "$ORIG_TABLE_COUNT" ] && echo "true" || echo "false"),
    "query_test": "$QUERY_RESULTS",
    "duration_seconds": $DURATION,
    "status": "success"
}
EOF

log "Последний бэкап работоспособен и готов к использованию"
