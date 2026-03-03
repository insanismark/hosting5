#!/bin/bash

#===============================================================================
# create_user.sh - Создание нового пользователя хостинга с Docker-контейнером
# 
# Структура пользователя:
#   /var/www/{username}/
#       ├── site/              # Файлы сайта (доступ через FTP)
#       ├── docker/            # Dockerfile + docker-compose.yml
#       ├── logs/              # Логи сайта
#       ├── credentials/       # SSH и FTP данные (только на сервере!)
#       └── placeholder/      # Приветственная заглушка
#
# Пример использования:
#   sudo ./create_user.sh <username> <domain> [php_version]
#   sudo ./create_user.sh john example.com
#   sudo ./create_user.sh alex mysite.org 8.2
#   sudo ./create_user.sh test blablatest4.tagan.ru 8.1
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Цвета для вывода
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# Конфигурация
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$PROJECT_DIR/templates"
WWW_BASE="/var/www"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
START_PORT=9000
NETWORK_NAME="hosting_net"

#-------------------------------------------------------------------------------
# Вспомогательные функции
#-------------------------------------------------------------------------------

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

#-------------------------------------------------------------------------------
# Генерация случайного пароля
#-------------------------------------------------------------------------------
generate_password() {
    openssl rand -base64 12 | tr -d '\n' | head -c 16
}

#-------------------------------------------------------------------------------
# Поиск свободного порта
#-------------------------------------------------------------------------------
find_available_port() {
    local port=$START_PORT
    while netstat -tuln 2>/dev/null | grep -q ":$port " || \
          docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":$port->" || \
          docker ps -a --format '{{.Ports}}' 2>/dev/null | grep -q ":$port->"; do
        port=$((port + 1))
        # Ограничение порта
        if [ $port -gt 9999 ]; then
            log_error "No available ports in range $START_PORT-9999"
            exit 1
        fi
    done
    echo $port
}

#-------------------------------------------------------------------------------
# Проверка аргументов
#-------------------------------------------------------------------------------

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <username> <domain> [php_version]"
    echo ""
    echo "Arguments:"
    echo "  username     - Linux username (lowercase letters, numbers, underscore)"
    echo "  domain       - Domain name (2nd and 3rd level supported)"
    echo "  php_version  - PHP version (optional, default: 8.2)"
    echo ""
    echo "Examples:"
    echo "  $0 john example.com"
    echo "  $0 alex mysite.org 8.2"
    echo "  $0 test blablatest4.tagan.ru 8.1"
    exit 1
fi

USERNAME="$1"
DOMAIN="$2"
PHP_VERSION="${3:-8.2}"

#-------------------------------------------------------------------------------
# Валидация username
#-------------------------------------------------------------------------------
if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_]*$ ]]; then
    log_error "Username must start with a letter and contain only lowercase letters and numbers"
    exit 1
fi

#-------------------------------------------------------------------------------
# Валидация домена (поддержка 2-го и 3-го уровня, цифры, дефисы)
# Примеры: example.com, mysite.org, blablatest4.tagan.ru
#-------------------------------------------------------------------------------
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
    log_error "Invalid domain format. Use: domain.com, sub.domain.com, my-site123.org"
    exit 1
fi

#-------------------------------------------------------------------------------
# Проверка существования пользователя Linux
#-------------------------------------------------------------------------------
if id "$USERNAME" &>/dev/null; then
    log_error "User '$USERNAME' already exists in system"
    exit 1
fi

#-------------------------------------------------------------------------------
# Проверка существования nginx конфига
#-------------------------------------------------------------------------------
if [ -f "$NGINX_SITES_AVAILABLE/$USERNAME.conf" ]; then
    log_error "Nginx config for '$USERNAME' already exists"
    exit 1
fi

#-------------------------------------------------------------------------------
# Проверка существования директории пользователя
#-------------------------------------------------------------------------------
if [ -d "$WWW_BASE/$USERNAME" ]; then
    log_error "Directory /var/www/$USERNAME already exists"
    exit 1
fi

#-------------------------------------------------------------------------------
# Проверка существования домена в nginx
#-------------------------------------------------------------------------------
if grep -r "server_name.*$DOMAIN" "$NGINX_SITES_AVAILABLE"/*.conf 2>/dev/null; then
    log_error "Domain '$DOMAIN' is already configured"
    exit 1
fi

#===============================================================================
# ОСНОВНАЯ ЧАСТЬ - СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
#===============================================================================

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Creating Hosting User${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

log_info "Username: $USERNAME"
log_info "Domain: $DOMAIN"
log_info "PHP Version: $PHP_VERSION"

#-------------------------------------------------------------------------------
# ШАГ 1: Создание Linux-пользователя
#-------------------------------------------------------------------------------
log_step "1/9 - Creating Linux user..."

# Генерируем пароль
FTP_PASSWORD=$(generate_password)
SSH_PASSWORD=$(generate_password)

# Создаём пользователя с домашней директорией
useradd -m -s /bin/bash -G docker "$USERNAME" 2>/dev/null || true

# Устанавливаем пароль для FTP/SSH
echo "$USERNAME:$FTP_PASSWORD" | chpasswd

log_info "Linux user created: $USERNAME"

#-------------------------------------------------------------------------------
# ШАГ 2: Создание структуры директорий
#-------------------------------------------------------------------------------
log_step "2/9 - Creating directory structure..."

USER_WWW="$WWW_BASE/$USERNAME"

# Создаём все необходимые директории
mkdir -p "$USER_WWW"/{site,docker,logs,credentials,placeholder}

# Права доступа:
# - site: 755 (читаем/выполняем, пишет только владелец)
# - docker: 755
# - logs: 777 (для записи логов)
# - credentials: 700 (только root!)
# - placeholder: 755
chown -R "$USERNAME:$USERNAME" "$USER_WWW"
chmod 755 "$USER_WWW"/{site,docker,placeholder}
chmod 777 "$USER_WWW"/logs
chmod 700 "$USER_WWW"/credentials

log_info "Directory structure created at: $USER_WWW"

#-------------------------------------------------------------------------------
# ШАГ 3: Создание приветственной заглушки (placeholder)
#-------------------------------------------------------------------------------
log_step "3/9 - Creating welcome placeholder..."

cat > "$USER_WWW/placeholder/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Сайт создаётся</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 60px 40px;
            text-align: center;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
            max-width: 500px;
            width: 100%;
        }
        .icon {
            font-size: 64px;
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
            font-size: 28px;
            margin-bottom: 16px;
            font-weight: 600;
        }
        p {
            color: #666;
            font-size: 16px;
            line-height: 1.6;
        }
        .domain {
            background: #f3f4f6;
            padding: 12px 20px;
            border-radius: 8px;
            margin-top: 24px;
            font-family: monospace;
            color: #4b5563;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">🚀</div>
        <h1>Ваш сайт создан!</h1>
        <p>Скоро тут будет контент.</p>
        <div class="domain">DOMAIN_PLACEHOLDER</div>
    </div>
</body>
</html>
EOF

# Заменяем плейсхолдер на реальный домен
sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" "$USER_WWW/placeholder/index.html"

# Также копируем в site как временную заглушку
cp "$USER_WWW/placeholder/index.html" "$USER_WWW/site/index.html"

chown "$USERNAME:$USERNAME" "$USER_WWW/placeholder/index.html"
chown "$USERNAME:$USERNAME" "$USER_WWW/site/index.html"

log_info "Placeholder created"

#-------------------------------------------------------------------------------
# ШАГ 4: Копирование Docker-шаблонов
#-------------------------------------------------------------------------------
log_step "4/9 - Copying Docker templates..."

cp "$TEMPLATES_DIR/Dockerfile.php" "$USER_WWW/docker/Dockerfile"
cp "$TEMPLATES_DIR/docker-compose.yml" "$USER_WWW/docker/docker-compose.yml"

# Заменяем плейсхолдеры в docker-compose.yml
sed -i "s/{{USERNAME}}/$USERNAME/g" "$USER_WWW/docker/docker-compose.yml"

log_info "Docker templates copied"

#-------------------------------------------------------------------------------
# ШАГ 5: Назначение уникального порта для контейнера
#-------------------------------------------------------------------------------
log_step "5/9 - Assigning unique container port..."

CONTAINER_PORT=$(find_available_port)
log_info "Assigned internal port: $CONTAINER_PORT"

# Обновляем docker-compose.yml с портом
sed -i "s/{{PORT}}/$CONTAINER_PORT/g" "$USER_WWW/docker/docker-compose.yml"

#-------------------------------------------------------------------------------
# ШАГ 6: Создание Nginx конфигурации
#-------------------------------------------------------------------------------
log_step "6/9 - Creating Nginx configuration..."

FASTCGI_PASS="127.0.0.1:$CONTAINER_PORT"

# Создаём nginx конфиг из шаблона
sed -e "s/{{DOMAIN}}/$DOMAIN/g" \
    -e "s/{{USERNAME}}/$USERNAME/g" \
    -e "s|{{ROOT_DIR}}|$USER_WWW/site|g" \
    -e "s|{{FASTCGI_PASS}}|$FASTCGI_PASS|g" \
    "$TEMPLATES_DIR/nginx.conf.template" > "$NGINX_SITES_AVAILABLE/$USERNAME.conf"

# Создаём симлинк
ln -sf "$NGINX_SITES_AVAILABLE/$USERNAME.conf" "$NGINX_SITES_ENABLED/$USERNAME.conf"

log_info "Nginx config created: /etc/nginx/sites-available/$USERNAME.conf"

#-------------------------------------------------------------------------------
# ШАГ 7: Сохранение учётных данных
#-------------------------------------------------------------------------------
log_step "7/9 - Saving credentials..."

# Файл с учётными данными (только для админа!)
cat > "$USER_WWW/credentials/access.txt" << EOF
============================================
Учётные данные для пользователя: $USERNAME
Домен: $DOMAIN
Дата создания: $(date '+%Y-%m-%d %H:%M:%S')
============================================

FTP ДОСТУП:
  Host: \$(hostname -I | awk '{print \$1}')
  Port: 21
  Username: $USERNAME
  Password: $FTP_PASSWORD
  Directory: /var/www/$USERNAME/site

SSH ДОСТУП К КОНТЕЙНЕРУ:
  docker exec -it ${USERNAME}_php sh
  
  Или через ssh (если настроен):
  ssh $USERNAME@\$ (hostname -I | awk '{print \$1}')

ПОРТ КОНТЕЙНЕРА: $CONTAINER_PORT

NGINX КОНФИГ:
  /etc/nginx/sites-available/$USERNAME.conf

ЛОГИ:
  /var/www/$USERNAME/logs/access.log
  /var/www/$USERNAME/logs/error.log
  
  Контейнер:
  docker logs ${USERNAME}_php

УПРАВЛЕНИЕ:
  docker start ${USERNAME}_php
  docker stop ${USERNAME}_php
  docker logs -f ${USERNAME}_php
  docker exec -it ${USERNAME}_php sh

============================================
ВНИМАНИЕ: Храните эти данные в безопасности!
============================================
EOF

# Права только для root
chmod 600 "$USER_WWW/credentials/access.txt"
chown root:root "$USER_WWW/credentials/access.txt"

# Также сохраняем FTP пароль отдельно
echo "$FTP_PASSWORD" > "$USER_WWW/credentials/ftp_password.txt"
chmod 600 "$USER_WWW/credentials/ftp_password.txt"
chown root:root "$USER_WWW/credentials/ftp_password.txt"

log_info "Credentials saved to: $USER_WWW/credentials/"

#-------------------------------------------------------------------------------
# ШАГ 8: Запуск Docker-контейнера
#-------------------------------------------------------------------------------
log_step "8/9 - Building and starting Docker container..."

cd "$USER_WWW/docker"

# Собираем и запускаем контейнер
chown -R "$USERNAME:$USERNAME" "$USER_WWW/docker"

# Запускаем от имени пользователя
sudo -u "$USERNAME" docker compose build --no-cache 2>&1 || {
    log_warn "Docker build failed, starting anyway..."
}

sudo -u "$USERNAME" docker compose up -d

# Проверяем, что контейнер запустился
sleep 2
if docker ps | grep -q "${USERNAME}_php"; then
    log_info "Container ${USERNAME}_php is running"
else
    log_warn "Container may not be running properly"
fi

#-------------------------------------------------------------------------------
# ШАГ 9: Перезагрузка Nginx
#-------------------------------------------------------------------------------
log_step "9/9 - Reloading Nginx..."

if nginx -t; then
    systemctl reload nginx
    log_info "Nginx reloaded successfully"
else
    log_error "Nginx configuration test failed"
    # Удаляем проблемный конфиг
    rm -f "$NGINX_SITES_AVAILABLE/$USERNAME.conf"
    rm -f "$NGINX_SITES_ENABLED/$USERNAME.conf"
    exit 1
fi

#===============================================================================
# РЕЗУЛЬТАТ
#===============================================================================

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  User Created Successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${BLUE}Информация о пользователе:${NC}"
echo "  Username: $USERNAME"
echo "  Domain: $DOMAIN"
echo "  PHP Version: $PHP_VERSION"
echo ""
echo -e "${BLUE}Директории:${NC}"
echo "  Web Root:    $USER_WWW/site"
echo "  Docker:     $USER_WWW/docker"
echo "  Logs:       $USER_WWW/logs"
echo "  Credentials: $USER_WWW/credentials (только для root!)"
echo "  Placeholder: $USER_WWW/placeholder"
echo ""
echo -e "${BLUE}Доступ:${NC}"
echo "  Container Port: $CONTAINER_PORT"
echo "  Nginx Config: /etc/nginx/sites-available/$USERNAME.conf"
echo ""
echo -e "${YELLOW}Учётные данные сохранены в:${NC}"
echo "  $USER_WWW/credentials/access.txt"
echo ""
echo -e "${YELLOW}Для просмотра учётных данных выполните:${NC}"
echo "  sudo cat $USER_WWW/credentials/access.txt"
echo ""
echo -e "${BLUE}Следующие шаги:${NC}"
echo "  1. Настройте DNS записи для домена $DOMAIN"
echo "  2. Для SSL: sudo certbot --nginx -d $DOMAIN"
echo ""
echo -e "${GREEN}============================================================${NC}"
echo ""

