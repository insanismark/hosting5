#!/bin/bash

#===============================================================================
# delete_user.sh - Delete hosting user and all associated resources
# Usage: ./delete_user.sh <username>
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
WWW_BASE="/var/www"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

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

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <username>"
    echo "Example: $0 john"
    exit 1
fi

USERNAME="$1"

# Check if user exists
if ! id "$USERNAME" &>/dev/null; then
    log_error "User '$USERNAME' does not exist"
    exit 1
fi

#-------------------------------------------------------------------------------
# Confirmation
#-------------------------------------------------------------------------------

echo "========================================"
log_warn "This will PERMANENTLY delete:"
echo "========================================"
echo "  - Linux user: $USERNAME"
echo "  - Web files: $WWW_BASE/$USERNAME"
echo "  - Docker container: ${USERNAME}_php"
echo "  - Nginx config: $NGINX_SITES_AVAILABLE/$USERNAME.conf"
echo "========================================"
echo ""

read -p "Are you sure you want to delete user '$USERNAME'? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Deletion cancelled"
    exit 0
fi

#-------------------------------------------------------------------------------
# Stop and remove Docker container
#-------------------------------------------------------------------------------

log_info "Stopping Docker container..."
cd "$WWW_BASE/$USERNAME/docker" 2>/dev/null && \
    sudo -u "$USERNAME" docker compose down --volumes --remove-orphans 2>/dev/null || \
    docker stop "${USERNAME}_php" 2>/dev/null || true

log_info "Removing Docker container..."
docker rm -f "${USERNAME}_php" 2>/dev/null || true

#-------------------------------------------------------------------------------
# Remove Docker volume (if exists)
#-------------------------------------------------------------------------------

log_info "Removing Docker volumes..."
docker volume rm "${USERNAME}_php" 2>/dev/null || true

#-------------------------------------------------------------------------------
# Remove Nginx configuration
#-------------------------------------------------------------------------------

log_info "Removing Nginx configuration..."
rm -f "$NGINX_SITES_AVAILABLE/$USERNAME.conf"
rm -f "$NGINX_SITES_ENABLED/$USERNAME.conf"

#-------------------------------------------------------------------------------
# Reload Nginx
#-------------------------------------------------------------------------------

log_info "Reloading Nginx..."
nginx -t && systemctl reload nginx

#-------------------------------------------------------------------------------
# Remove user directory
#-------------------------------------------------------------------------------

log_info "Removing user directory..."
rm -rf "$WWW_BASE/$USERNAME"

#-------------------------------------------------------------------------------
# Remove Linux user
#-------------------------------------------------------------------------------

log_info "Removing Linux user..."
userdel -r "$USERNAME" 2>/dev/null || userdel "$USERNAME" 2>/dev/null || true

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------

echo ""
echo "========================================"
echo -e "${GREEN}User deleted successfully!${NC}"
echo "========================================"
echo "Removed:"
echo "  - Linux user: $USERNAME"
echo "  - Web files: $WWW_BASE/$USERNAME"
echo "  - Docker container"
echo "  - Nginx configuration"
echo "========================================"

