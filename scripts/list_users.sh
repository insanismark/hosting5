#!/bin/bash

#===============================================================================
# list_users.sh - List all active hosting users and their sites
# Usage: ./list_users.sh
#===============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
WWW_BASE="/var/www"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

echo_header() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  Active Hosting Sites${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
    printf "${GREEN}%-15s %-25s %-15s %-12s %-10s${NC}\n" \
        "USERNAME" "DOMAIN" "CONTAINER" "STATUS" "PORT"
    echo "------------------------------------------------------------------------"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

# Check if nginx sites-enabled directory exists
if [ ! -d "$NGINX_SITES_ENABLED" ]; then
    echo -e "${RED}Nginx sites-enabled directory not found${NC}"
    exit 1
fi

# Check if www base directory exists
if [ ! -d "$WWW_BASE" ]; then
    echo -e "${RED}Web directory $WWW_BASE not found${NC}"
    exit 1
fi

echo_header

TOTAL_USERS=0
ACTIVE_USERS=0

# Iterate through all nginx configs
for config in "$NGINX_SITES_ENABLED"/*.conf; do
    [ -f "$config" ] || continue
    
    # Extract username from config filename
    USERNAME=$(basename "$config" .conf)
    
    # Skip default configs
    if [ "$USERNAME" = "default" ] || [ "$USERNAME" = "nginx" ]; then
        continue
    fi
    
    TOTAL_USERS=$((TOTAL_USERS + 1))
    
    # Get domain from nginx config
    DOMAIN=$(grep -m1 "server_name" "$config" 2>/dev/null | awk '{print $2}' | tr -d ';')
    if [ -z "$DOMAIN" ]; then
        DOMAIN="N/A"
    fi
    
    # Check if container is running
    CONTAINER_NAME="${USERNAME}_php"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        STATUS="✓ Running"
        ACTIVE_USERS=$((ACTIVE_USERS + 1))
    else
        STATUS="✗ Stopped"
    fi
    
    # Get container port (internal)
    PORT=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} {{end}}' "$CONTAINER_NAME" 2>/dev/null | head -1)
    if [ -z "$PORT" ]; then
        PORT="N/A"
    fi
    
    printf "%-15s %-25s %-15s %-12s %-10s\n" \
        "$USERNAME" "$DOMAIN" "$CONTAINER_NAME" "$STATUS" "$PORT"
done

echo "------------------------------------------------------------------------"
echo ""
echo -e "Total configured: ${YELLOW}$TOTAL_USERS${NC}"
echo -e "Active containers: ${GREEN}$ACTIVE_USERS${NC}"
echo ""

#-------------------------------------------------------------------------------
# Docker network info
#-------------------------------------------------------------------------------

echo -e "${BLUE}Docker Network Info:${NC}"
if docker network ls | grep -q "hosting_net"; then
    CONTAINERS_IN_NETWORK=$(docker network inspect hosting_net --format='{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
    echo -e "  Network: ${GREEN}hosting_net exists${NC}"
    echo -e "  Connected containers: $CONTAINERS_IN_NETWORK"
else
    echo -e "  Network: ${RED}hosting_net not found${NC}"
fi

echo ""

