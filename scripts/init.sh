#!/bin/bash

# Скрипт инициализации системы бэкапов

# Не останавливаемся при ошибках
set +e

LOG_DIR="/var/log/backup"
BACKUP_DIR="/backups"
STATUS_FILE="$LOG_DIR/status.json"

# Логирование
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Инициализация системы автоматических бэкапов..."

# Создание необходимых директорий
mkdir -p "$BACKUP_DIR/full" "$BACKUP_DIR/wal" "$LOG_DIR"

# Ожидание доступности PostgreSQL
log "Ожидание PostgreSQL..."
POSTGRES_READY=false
for i in {1..60}; do
    if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" >/dev/null 2>&1; then
        log "PostgreSQL доступен"
        POSTGRES_READY=true
        break
    fi
    log "Ожидание PostgreSQL... ($i/60)"
    sleep 5
done

if [ "$POSTGRES_READY" = false ]; then
    log "ПРЕДУПРЕЖДЕНИЕ: PostgreSQL недоступен, но продолжаем инициализацию"
fi

# Проверка WAL архивирования (если PostgreSQL доступен)
if [ "$POSTGRES_READY" = true ]; then
    log "Проверка настроек WAL архивирования..."
    WAL_LEVEL=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -c "SHOW wal_level;" 2>/dev/null | xargs || echo "unknown")
    ARCHIVE_MODE=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -c "SHOW archive_mode;" 2>/dev/null | xargs || echo "unknown")
    
    log "WAL Level: $WAL_LEVEL"
    log "Archive Mode: $ARCHIVE_MODE"
else
    WAL_LEVEL="unknown"
    ARCHIVE_MODE="unknown"
fi

# Создание первоначального статуса
cat > "$STATUS_FILE" << EOF
{
    "system_status": "initialized",
    "postgres_status": "$([ "$POSTGRES_READY" = true ] && echo "online" || echo "offline")",
    "initialization_date": "$(date -Iseconds)",
    "wal_level": "$WAL_LEVEL",
    "archive_mode": "$ARCHIVE_MODE",
    "message": "Backup system initialized"
}
EOF

# Попытка создать тестовый бэкап (если PostgreSQL доступен)
if [ "$POSTGRES_READY" = true ]; then
    log "Попытка создания тестового бэкапа..."
    if /scripts/backup.sh 2>/dev/null; then
        log "Тестовый бэкап успешно создан"
        
        # Попытка тестирования восстановления
        log "Попытка тестирования восстановления..."
        if /scripts/test_backup.sh 2>/dev/null; then
            log "Тестирование восстановления прошло успешно"
        else
            log "ПРЕДУПРЕЖДЕНИЕ: Тестирование восстановления не удалось"
        fi
    else
        log "ПРЕДУПРЕЖДЕНИЕ: Не удалось создать тестовый бэкап"
    fi
else
    log "Пропускаем создание тестового бэкапа - PostgreSQL недоступен"
fi

# Проверка настройки cron
log "Проверка настройки cron задач..."
crontab -l 2>/dev/null || log "Cron задачи не настроены"

# Информация о дисковом пространстве
DISK_INFO=$(df -h "$BACKUP_DIR" 2>/dev/null || echo "Информация о диске недоступна")
log "Информация о дисковом пространстве:"
echo "$DISK_INFO"

# Отправка уведомления об инициализации
if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    local telegram_message="✅ PostgreSQL Backup System инициализирован

✓ PostgreSQL: $([ "$POSTGRES_READY" = true ] && echo "онлайн" || echo "офлайн")
✓ WAL Level: $WAL_LEVEL
✓ Archive Mode: $ARCHIVE_MODE

Сервер: $(hostname)
Мониторинг: http://$(hostname):8080
Время: $(date '+%Y-%m-%d %H:%M:%S')"
    
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"$TELEGRAM_CHAT_ID\",
            \"text\": \"$telegram_message\",
            \"parse_mode\": \"HTML\"
        }" 2>/dev/null || log "Не удалось отправить Telegram уведомление"
fi

log "Инициализация системы автоматических бэкапов завершена!"
log "Мониторинг доступен по адресу: http://$(hostname):8080"
log "Статус системы сохраняется в: $STATUS_FILE"
