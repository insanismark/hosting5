#!/bin/bash

#===============================================================================
# setup.sh - Initial server setup for self-hosted web hosting
# Usage: sudo ./setup.sh
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

#-------------------------------------------------------------------------------
# Check if running as root
#-------------------------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    log_error "Please run this script as root (sudo)"
    exit 1
fi

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WWW_BASE="/var/www"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NETWORK_NAME="hosting_net"

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Self-Hosted Web Hosting - Initial Setup${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# Step 1: Update system
#-------------------------------------------------------------------------------

log_step "1/7 - Updating system packages..."
apt update && apt upgrade -y

#-------------------------------------------------------------------------------
# Step 2: Install required packages
#-------------------------------------------------------------------------------

log_step "2/7 - Installing required packages..."
apt install -y \
    curl \
    wget \
    git \
    vim \
    net-tools \
    rsync \
    openssl \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

#-------------------------------------------------------------------------------
# Step 3: Install Docker
#-------------------------------------------------------------------------------

log_step "3/7 - Installing Docker..."

if command -v docker &> /dev/null; then
    log_warn "Docker is already installed"
else
    # Add Docker GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Enable Docker
    systemctl enable docker
    systemctl start docker
fi

log_info "Docker version: $(docker --version)"
log_info "Docker Compose version: $(docker compose version)"

#-------------------------------------------------------------------------------
# Step 4: Create Docker network
#-------------------------------------------------------------------------------

log_step "4/7 - Creating Docker network..."

if docker network ls | grep -q "$NETWORK_NAME"; then
    log_warn "Network $NETWORK_NAME already exists"
else
    docker network create "$NETWORK_NAME"
    log_info "Created network: $NETWORK_NAME"
fi

#-------------------------------------------------------------------------------
# Step 5: Configure Nginx
#-------------------------------------------------------------------------------

log_step "5/7 - Configuring Nginx..."

# Install Nginx
if ! command -v nginx &> /dev/null; then
    apt install -y nginx
fi

# Create directories
mkdir -p "$WWW_BASE"
mkdir -p "$NGINX_SITES_AVAILABLE"
mkdir -p "$NGINX_SITES_ENABLED"

# Create default nginx config if not exists
if [ ! -f "$NGINX_SITES_AVAILABLE/default" ]; then
    cat > "$NGINX_SITES_AVAILABLE/default" << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    
    root /var/www/html;
    index index.html index.htm;
    
    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
    ln -sf "$NGINX_SITES_AVAILABLE/default" "$NGINX_SITES_ENABLED/default"
fi

# Test and reload Nginx
nginx -t && systemctl reload nginx

#-------------------------------------------------------------------------------
# Step 6: Create management scripts
#-------------------------------------------------------------------------------

log_step "6/7 - Creating management scripts..."

# Make scripts executable
chmod +x "$SCRIPT_DIR"/*.sh
chmod +x "$PROJECT_DIR"/*.sh 2>/dev/null || true

# Copy scripts to /usr/local/bin
cp "$SCRIPT_DIR/create_user.sh" /usr/local/bin/
cp "$SCRIPT_DIR/delete_user.sh" /usr/local/bin/
cp "$SCRIPT_DIR/list_users.sh" /usr/local/bin/

chmod +x /usr/local/bin/create_user.sh
chmod +x /usr/local/bin/delete_user.sh
chmod +x /usr/local/bin/list_users.sh

#-------------------------------------------------------------------------------
# Step 7: Install Portainer
#-------------------------------------------------------------------------------

log_step "7/7 - Installing Portainer..."

# Create Portainer data directory
mkdir -p /var/lib/portainer

# Check if Portainer is already running
if docker ps | grep -q portainer; then
    log_warn "Portainer is already running"
else
    # Run Portainer
    docker run -d \
        --name portainer \
        --restart=always \
        -p 9001:9000 \
        -p 9443:9443 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /var/lib/portainer:/data \
        --network "$NETWORK_NAME" \
        portainer/portainer-ce:latest
    
    log_info "Portainer installed"
    log_info "Access Portainer at: http://localhost:9001"
fi

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo "Installed components:"
echo "  ✓ Docker $(docker --version)"
echo "  ✓ Docker Compose $(docker compose version)"
echo "  ✓ Nginx $(nginx -v 2>&1)"
echo "  ✓ Portainer (port 9001)"
echo "  ✓ Docker network: $NETWORK_NAME"
echo ""
echo "Management scripts:"
echo "  ✓ /usr/local/bin/create_user.sh"
echo "  ✓ /usr/local/bin/delete_user.sh"
echo "  ✓ /usr/local/bin/list_users.sh"
echo ""
echo "Next steps:"
echo "  1. Access Portainer: http://your-server-ip:9001"
echo "  2. Create admin user for Portainer"
echo "  3. Create your first hosting user:"
echo "     sudo create_user.sh <username> <domain>"
echo ""
echo "Examples:"
echo "  sudo create_user.sh john example.com"
echo "  sudo create_user.sh alice mysite.org 8.1"
echo ""
echo -e "${YELLOW}Note: Add your user to 'docker' group to manage containers:${NC}"
echo "  usermod -aG docker <username>"
echo ""

