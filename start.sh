#!/bin/bash

echo "🚀 Запуск сервисов..."
docker compose up -d

echo "⏳ Ждем запуска сервисов..."
sleep 30

echo "📊 Статус контейнеров:"
docker compose ps

echo ""
echo "🔑 ДОСТУПЫ К СЕРВИСАМ:"
echo "================================"
echo "📘 PostgreSQL:"
echo "  Host: 164.90.236.33:5432"
echo "  Пользователь: admin"
echo "  Пароль: mypassword123"
echo "  База данных: mydb"
echo ""
echo "📗 Apache NiFi:"
echo "  URL: https://164.90.236.33:8443/nifi"
echo "  Пользователь: admin"
echo "  Пароль: password123"
echo ""
echo "⚠️  Для доступа извне замените localhost на IP вашего сервера"

# Показать логи NiFi для проверки
echo ""
echo "📝 Проверяем логи NiFi..."
docker logs apache_nifi | tail -10
