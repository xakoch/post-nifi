#!/bin/bash

set -e

# Настройки
BACKUP_DIR="/backups"
FULL_BACKUP_DIR="$BACKUP_DIR/full"
WAL_BACKUP_DIR="$BACKUP_DIR/wal"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
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
        
        local telegram_message="$emoji PostgreSQL Backup
        
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

# Обновление статуса
update_status() {
    local status="$1"
    local message="$2"
    cat > "$STATUS_FILE" << EOF
{
    "status": "$status",
    "last_backup": "$(date -Iseconds)",
    "message": "$message",
    "timestamp": "$(date +%s)"
}
EOF
}

# Обработка ошибок
handle_error() {
    local error_msg="Backup failed: $1"
    log "ОШИБКА: $error_msg"
    update_status "error" "$error_msg"
    send_notification "$error_msg" "error"
    exit 1
}

# Создание директорий
mkdir -p "$FULL_BACKUP_DIR" "$WAL_BACKUP_DIR"

update_status "running" "Starting backup process"
log "Начинаем бэкап базы данных $PGDATABASE"

# Проверка подключения к базе
if ! pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" >/dev/null 2>&1; then
    handle_error "Database connection failed"
fi

# Полный бэкап с pg_dump
BACKUP_FILE="$FULL_BACKUP_DIR/backup_${TIMESTAMP}.sql"
log "Создаем полный бэкап: $BACKUP_FILE"

if ! pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" \
    --verbose \
    --clean \
    --if-exists \
    --create \
    --format=plain \
    "$PGDATABASE" > "$BACKUP_FILE" 2>/dev/null; then
    handle_error "pg_dump failed"
fi

# Сжимаем бэкап
log "Сжимаем бэкап..."
if ! gzip "$BACKUP_FILE"; then
    handle_error "Backup compression failed"
fi
BACKUP_FILE="${BACKUP_FILE}.gz"

# Копируем WAL файлы
log "Копируем WAL файлы..."
if [ -d "/var/lib/postgresql/wal_archive" ]; then
    WAL_ARCHIVE_DIR="$WAL_BACKUP_DIR/wal_${TIMESTAMP}"
    mkdir -p "$WAL_ARCHIVE_DIR"
    cp -r /var/lib/postgresql/wal_archive/* "$WAL_ARCHIVE_DIR"/ 2>/dev/null || log "Нет новых WAL файлов"
fi

# Проверяем размер бэкапа
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log "Размер бэкапа: $BACKUP_SIZE"

# Проверяем целостность бэкапа
log "Проверяем целостность бэкапа..."
if ! gunzip -t "$BACKUP_FILE"; then
    handle_error "Backup integrity check failed"
fi

# Удаляем старые бэкапы
log "Удаляем бэкапы старше $RETENTION_DAYS дней..."
find "$FULL_BACKUP_DIR" -name "backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete
find "$WAL_BACKUP_DIR" -name "wal_*" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

# Подсчитываем статистику
TOTAL_BACKUPS=$(ls -1 "$FULL_BACKUP_DIR"/backup_*.sql.gz 2>/dev/null | wc -l)
DISK_USAGE=$(du -sh "$BACKUP_DIR" | cut -f1)

# Список текущих бэкапов
log "Текущие бэкапы: $TOTAL_BACKUPS"
log "Использование диска: $DISK_USAGE"

# Обновляем статус успеха
SUCCESS_MSG="Backup completed successfully. Size: $BACKUP_SIZE, Total backups: $TOTAL_BACKUPS"
update_status "success" "$SUCCESS_MSG"
send_notification "$SUCCESS_MSG" "success"

log "Бэкап завершен успешно!"
