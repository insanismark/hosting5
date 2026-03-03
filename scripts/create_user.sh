#!/bin/bash

#===============================================================================
# create_user.sh - Create new hosting user with Docker container
# Usage: ./create_user.sh <username> <domain> [php_version]
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$PROJECT_DIR/templates"
WWW_BASE="/var/www"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
START_PORT=9000
NETWORK_NAME="hosting_net"

#-------------------------------------------------------------------------------
# Helper functions
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

#-------------------------------------------------------------------------------
# Validation
#-------------------------------------------------------------------------------

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <username> <domain> [php_version]"
    echo "Example: $0 john example.com 8.2"
    exit 1
fi

USERNAME="$1"
DOMAIN="$2"
PHP_VERSION="${3:-8.2}"

# Validate username
if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    log_error "Username must start with a letter and contain only lowercase letters, numbers, and underscores"
    exit 1
fi

# Validate domain
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z]{2,}$ ]]; then
    log_error "Invalid domain format"
    exit 1
fi

# Check if user exists
if id "$USERNAME" &>/dev/null; then
    log_error "User '$USERNAME' already exists"
    exit 1
fi

# Check if nginx config exists
if [ -f "$NGINX_SITES_AVAILABLE/$USERNAME.conf" ]; then
    log_error "Nginx config for '$USERNAME' already exists"
    exit 1
fi

#-------------------------------------------------------------------------------
# Find available port
#-------------------------------------------------------------------------------

find_available_port() {
    local port=$START_PORT
    while netstat -tuln 2>/dev/null | grep -q ":$port " || \
          docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":$port->"; do
        port=$((port + 1))
    done
    echo $port
}

#-------------------------------------------------------------------------------
# Main installation
#-------------------------------------------------------------------------------

log_info "Creating user: $USERNAME"
log_info "Domain: $DOMAIN"
log_info "PHP Version: $PHP_VERSION"

# 1. Create Linux user
log_info "Creating Linux user..."
useradd -m -s /bin/bash -G docker "$USERNAME" 2>/dev/null || true
echo "$USERNAME:$(openssl rand -base64 12)" | chpasswd

# 2. Create directory structure
log_info "Creating directory structure..."
USER_WWW="$WWW_BASE/$USERNAME"
mkdir -p "$USER_WWW"/{site,docker,logs}
chown -R "$USERNAME:$USERNAME" "$USER_WWW"

# 3. Copy templates
log_info "Copying Docker templates..."
cp "$TEMPLATES_DIR/Dockerfile.php" "$USER_WWW/docker/Dockerfile"
cp "$TEMPLATES_DIR/docker-compose.yml" "$USER_WWW/docker/docker-compose.yml"

# 4. Replace placeholders in docker-compose.yml
log_info "Configuring docker-compose.yml..."
sed -i "s/{{USERNAME}}/$USERNAME/g" "$USER_WWW/docker/docker-compose.yml"

# 5. Create sample PHP site
log_info "Creating sample PHP site..."
cat > "$USER_WWW/site/index.php" << 'EOF'
<?php
echo "<h1>Welcome to PHP Hosting</h1>";
echo "<p>Server: " . gethostname() . "</p>";
echo "<p>PHP Version: " . PHP_VERSION . "</p>";
echo "<p>Time: " . date('Y-m-d H:i:s') . "</p>";
EOF
chown "$USERNAME:$USERNAME" "$USER_WWW/site/index.php"

# 6. Find available port and create nginx config
PORT=$(find_available_port)
log_info "Assigned port: $PORT"

log_info "Creating Nginx configuration..."
FASTCGI_PASS="${USERNAME}_php:9000"

# Create nginx config from template
sed -e "s/{{DOMAIN}}/$DOMAIN/g" \
    -e "s/{{USERNAME}}/$USERNAME/g" \
    -e "s|{{ROOT_DIR}}|$USER_WWW/site|g" \
    -e "s|{{FASTCGI_PASS}}|$FASTCGI_PASS|g" \
    "$TEMPLATES_DIR/nginx.conf.template" > "$NGINX_SITES_AVAILABLE/$USERNAME.conf"

# Create symlink
ln -sf "$NGINX_SITES_AVAILABLE/$USERNAME.conf" "$NGINX_SITES_ENABLED/$USERNAME.conf"

# 7. Build and start Docker container
log_info "Building and starting Docker container..."
cd "$USER_WWW/docker"
chown -R "$USERNAME:$USERNAME" "$USER_WWW/docker"
sudo -u "$USERNAME" docker compose build --no-cache
sudo -u "$USERNAME" docker compose up -d

# 8. Reload Nginx
log_info "Reloading Nginx..."
nginx -t && systemctl reload nginx

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------

echo ""
echo "========================================"
echo -e "${GREEN}User created successfully!${NC}"
echo "========================================"
echo "Username: $USERNAME"
echo "Domain: $DOMAIN"
echo "Web Root: $USER_WWW/site"
echo "Docker Dir: $USER_WWW/docker"
echo "Logs Dir: $USER_WWW/logs"
echo "PHP-FPM Port: $PORT (internal)"
echo "Container: ${USERNAME}_php"
echo ""
echo "FTP Access:"
echo "  Host: your-server-ip"
echo "  User: $USERNAME"
echo "  Password: (set during creation)"
echo ""
echo "Next steps:"
echo "  1. Point your domain DNS to server IP"
echo "  2. Configure SSL with certbot:"
echo "     sudo certbot --nginx -d $DOMAIN"
echo "========================================"

