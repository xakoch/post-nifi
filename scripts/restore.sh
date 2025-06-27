#!/bin/bash

set -e

# Проверяем аргументы
if [ $# -eq 0 ]; then
    echo "Использование: $0 <backup_file.sql.gz> [test_db_name]"
    echo "Пример: $0 /backups/full/backup_20241226_020000.sql.gz"
    echo "Или для тестового восстановления: $0 /backups/full/backup_20241226_020000.sql.gz test_restore"
    exit 1
fi

BACKUP_FILE="$1"
TEST_DB="${2:-}"

# Логирование
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Проверяем существование файла бэкапа
if [ ! -f "$BACKUP_FILE" ]; then
    log "ОШИБКА: Файл бэкапа не найден: $BACKUP_FILE"
    exit 1
fi

log "Начинаем восстановление из: $BACKUP_FILE"

# Определяем базу данных для восстановления
if [ -n "$TEST_DB" ]; then
    TARGET_DB="$TEST_DB"
    log "Режим: ТЕСТОВОЕ восстановление в базу '$TARGET_DB'"
    
    # Создаем тестовую базу данных
    log "Создаем тестовую базу данных '$TARGET_DB'..."
    createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$TARGET_DB" || true
else
    TARGET_DB="$PGDATABASE"
    log "Режим: ПОЛНОЕ восстановление в основную базу '$TARGET_DB'"
    
    # Предупреждение для полного восстановления
    echo "ВНИМАНИЕ! Вы собираетесь восстановить ОСНОВНУЮ базу данных!"
    echo "Это удалит все текущие данные в базе '$TARGET_DB'"
    echo "Введите 'YES' для подтверждения:"
    read -r confirmation
    if [ "$confirmation" != "YES" ]; then
        log "Восстановление отменено пользователем"
        exit 1
    fi
fi

# Распаковываем бэкап если он сжат
TEMP_FILE=""
if [[ "$BACKUP_FILE" == *.gz ]]; then
    log "Распаковываем сжатый бэкап..."
    TEMP_FILE="/tmp/restore_$(date +%s).sql"
    gunzip -c "$BACKUP_FILE" > "$TEMP_FILE"
    SQL_FILE="$TEMP_FILE"
else
    SQL_FILE="$BACKUP_FILE"
fi

# Выполняем восстановление
log "Восстанавливаем данные в базу '$TARGET_DB'..."

if [ -n "$TEST_DB" ]; then
    # Для тестовой базы - восстанавливаем без DROP DATABASE
    sed 's/DROP DATABASE IF EXISTS.*;//g' "$SQL_FILE" | \
    sed "s/CREATE DATABASE $PGDATABASE/CREATE DATABASE $TARGET_DB/g" | \
    sed "s/\\\\connect $PGDATABASE/\\\\connect $TARGET_DB/g" | \
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres
else
    # Для основной базы - полное восстановление
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres < "$SQL_FILE"
fi

# Удаляем временный файл
if [ -n "$TEMP_FILE" ]; then
    rm -f "$TEMP_FILE"
fi

# Проверяем восстановление
log "Проверяем восстановленную базу данных..."
TABLE_COUNT=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$TARGET_DB" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)

log "Восстановление завершено!"
log "База данных: $TARGET_DB"
log "Количество таблиц: $TABLE_COUNT"

if [ -n "$TEST_DB" ]; then
    log "Тестовая база данных '$TEST_DB' создана и готова для проверки"
    log "Для удаления тестовой базы выполните: dropdb -h $PGHOST -p $PGPORT -U $PGUSER $TEST_DB"
fi
