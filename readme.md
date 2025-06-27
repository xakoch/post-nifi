# PostgreSQL + NiFi Backup System 🚀

Автоматическая система бэкапов PostgreSQL с Apache NiFi и Telegram уведомлениями.

## 🎯 Быстрый запуск

```bash
git clone <your-repo-url>
cd my-nifi-project
mkdir -p logs backups/full
chmod +x scripts/*.sh
docker-compose up -d
```

## 📊 Доступы

- **Web Monitor**: http://164.90.236.33:8080
- **NiFi**: https://164.90.236.33:8443/nifi (admin/password123456789)
- **PostgreSQL**: 164.90.236.33:5432 (admin/mypassword123)

## ⚙️ Управление

```bash
# Ручной бэкап
docker exec postgres_backup /scripts/manual_backup.sh

# Логи
docker logs postgres_backup

# Перезапуск
docker-compose restart
```

## 📱 Функции

- ✅ Ежедневные автобэкапы в 2:00
- ✅ Telegram уведомления  
- ✅ Веб-мониторинг
- ✅ Автоочистка старых бэкапов

## 🛠️ Компоненты

- PostgreSQL 15 с WAL архивированием
- Apache NiFi 1.25.0 
- Backup система с Telegram ботом
- Современный веб-интерфейс мониторинга
