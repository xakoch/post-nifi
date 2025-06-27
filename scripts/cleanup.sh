#!/bin/bash

# Скрипт автоматической очистки (запускается раз в неделю)

set -e

BACKUP_DIR="/backups"
LOG_DIR="/var/log/backup"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
LOG_RETENTION_DAYS=30

# Логирование
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Начинаем еженедельную очистку системы"

# Очистка старых бэкапов
log "Очистка бэкапов старше $RETENTION_DAYS дней..."
REMOVED_BACKUPS=$(find "$BACKUP_DIR/full" -name "backup_*.sql.gz" -mtime +$RETENTION_DAYS -print | wc -l)
find "$BACKUP_DIR/full" -name "backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete

REMOVED_WAL=$(find "$BACKUP_DIR/wal" -name "wal_*" -type d -mtime +$RETENTION_DAYS -print | wc -l)
find "$BACKUP_DIR/wal" -name "wal_*" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

log "Удалено бэкапов: $REMOVED_BACKUPS"
log "Удалено WAL архивов: $REMOVED_WAL"

# Очистка старых логов
log "Очистка логов старше $LOG_RETENTION_DAYS дней..."
find "$LOG_DIR" -name "*.log" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true

# Ротация текущих логов если они большие (>100MB)
for logfile in "$LOG_DIR"/*.log; do
    if [ -f "$logfile" ] && [ $(stat -c%s "$logfile") -gt 104857600 ]; then
        log "Ротация большого лог-файла: $(basename "$logfile")"
        mv "$logfile" "${logfile}.$(date +%Y%m%d_%H%M%S)"
        touch "$logfile"
    fi
done

# Очистка временных файлов PostgreSQL
log "Очистка временных файлов..."
find /tmp -name "restore_*.sql" -mtime +1 -delete 2>/dev/null || true

# Анализ использования диска
TOTAL_BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
TOTAL_LOG_SIZE=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
DISK_USAGE=$(df "$BACKUP_DIR" | awk 'NR==2{print $5}')

log "Статистика после очистки:"
log "  Размер бэкапов: $TOTAL_BACKUP_SIZE"
log "  Размер логов: $TOTAL_LOG_SIZE"
log "  Использование диска: $DISK_USAGE"

# Проверка на критическое заполнение диска
DISK_USAGE_NUM=$(echo "$DISK_USAGE" | sed 's/%//')
if [ "$DISK_USAGE_NUM" -gt 90 ]; then
    log "ВНИМАНИЕ: Критическое заполнение диска: $DISK_USAGE"
    
    # Экстренная очистка - удаляем бэкапы старше половины от retention
    EMERGENCY_RETENTION=$((RETENTION_DAYS / 2))
    if [ "$EMERGENCY_RETENTION" -lt 2 ]; then
        EMERGENCY_RETENTION=2
    fi
    
    log "Выполняем экстренную очистку бэкапов старше $EMERGENCY_RETENTION дней"
    find "$BACKUP_DIR/full" -name "backup_*.sql.gz" -mtime +$EMERGENCY_RETENTION -delete
    find "$BACKUP_DIR/wal" -name "wal_*" -type d -mtime +$EMERGENCY_RETENTION -exec rm -rf {} + 2>/dev/null || true
fi

# Обновляем статистику в status.json
CURRENT_BACKUPS=$(ls -1 "$BACKUP_DIR/full"/backup_*.sql.gz 2>/dev/null | wc -l)
cat > "$LOG_DIR/cleanup_stats.json" << EOF
{
    "cleanup_date": "$(date -Iseconds)",
    "removed_backups": $REMOVED_BACKUPS,
    "removed_wal": $REMOVED_WAL,
    "current_backups": $CURRENT_BACKUPS,
    "backup_size": "$TOTAL_BACKUP_SIZE",
    "log_size": "$TOTAL_LOG_SIZE",
    "disk_usage": "$DISK_USAGE"
}
EOF

log "Еженедельная очистка завершена"
