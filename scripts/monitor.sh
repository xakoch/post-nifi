#!/bin/bash

# Скрипт мониторинга состояния системы бэкапов
# Запускается каждые 10 минут

STATUS_FILE="/var/log/backup/status.json"
MONITOR_LOG="/var/log/backup/monitor.log"
BACKUP_DIR="/backups"

# Логирование
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$MONITOR_LOG"
}

# Проверка доступности PostgreSQL
check_postgres() {
    if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" >/dev/null 2>&1; then
        echo "online"
    else
        echo "offline"
    fi
}

# Проверка свободного места
check_disk_space() {
    local usage=$(df "$BACKUP_DIR" | awk 'NR==2{print $5}' | sed 's/%//')
    echo "$usage"
}

# Проверка последнего бэкапа
check_last_backup() {
    local last_backup=$(ls -t "$BACKUP_DIR/full"/backup_*.sql.gz 2>/dev/null | head -1)
    if [ -n "$last_backup" ]; then
        local backup_age=$(($(date +%s) - $(stat -c %Y "$last_backup")))
        echo "$backup_age"
    else
        echo "none"
    fi
}

# Подсчет статистики
get_backup_stats() {
    local total_backups=$(ls -1 "$BACKUP_DIR/full"/backup_*.sql.gz 2>/dev/null | wc -l)
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    echo "{\"count\":$total_backups,\"size\":\"$total_size\"}"
}

# Основная проверка
main() {
    local postgres_status=$(check_postgres)
    local disk_usage=$(check_disk_space)
    local last_backup_age=$(check_last_backup)
    local backup_stats=$(get_backup_stats)
    local current_time=$(date +%s)
    
    # Определяем общий статус системы
    local system_status="healthy"
    local alerts=()
    
    # Проверки и алерты
    if [ "$postgres_status" = "offline" ]; then
        system_status="critical"
        alerts+=("PostgreSQL offline")
    fi
    
    if [ "$disk_usage" -gt 85 ]; then
        system_status="warning"
        alerts+=("Disk usage high: ${disk_usage}%")
    fi
    
    if [ "$last_backup_age" != "none" ] && [ "$last_backup_age" -gt 172800 ]; then # 48 часов
        system_status="warning"
        alerts+=("Last backup is older than 48 hours")
    fi
    
    if [ "$last_backup_age" = "none" ]; then
        system_status="critical"
        alerts+=("No backups found")
    fi
    
    # Формируем JSON статус
    local alerts_json=$(printf '%s\n' "${alerts[@]}" | jq -R . | jq -s .)
    
    cat > "$STATUS_FILE" << EOF
{
    "system_status": "$system_status",
    "postgres_status": "$postgres_status",
    "disk_usage": $disk_usage,
    "last_backup_age": "$last_backup_age",
    "backup_stats": $backup_stats,
    "alerts": $alerts_json,
    "last_check": $current_time,
    "last_check_human": "$(date -Iseconds)"
}
EOF
    
    # Логируем критические проблемы
    if [ "$system_status" = "critical" ]; then
        log "CRITICAL: ${alerts[*]}"
        
        # Отправляем критическое уведомление в Telegram
        if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
            local telegram_message="🚨 КРИТИЧЕСКАЯ ОШИБКА PostgreSQL Backup System

${alerts[*]}

Сервер: $(hostname)
Время: $(date '+%Y-%m-%d %H:%M:%S')

Требуется немедленное вмешательство!"
            
            curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                -H "Content-Type: application/json" \
                -d "{
                    \"chat_id\": \"$TELEGRAM_CHAT_ID\",
                    \"text\": \"$telegram_message\",
                    \"parse_mode\": \"HTML\"
                }" || true
        fi
        
        # Webhook уведомление
        if [ -n "$WEBHOOK_URL" ]; then
            curl -s -X POST "$WEBHOOK_URL" \
                -H "Content-Type: application/json" \
                -d "{\"text\":\"🚨 CRITICAL: PostgreSQL Backup System Alert: ${alerts[*]}\",\"status\":\"critical\"}" || true
        fi
    elif [ "$system_status" = "warning" ]; then
        log "WARNING: ${alerts[*]}"
    fi
}

main
