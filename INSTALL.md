# Installation Guide - Self-Hosted Web Hosting

## System Requirements

- Ubuntu 22.04 LTS (Server)
- Root access (sudo)
- Minimum 2GB RAM
- 20GB+ disk space
- Static IP address

## Quick Start

### Step 1: Download the project

```bash
cd /opt
git clone https://github.com/your-repo/hosting5.git
cd hosting5
```

### Step 2: Run the setup script

```bash
sudo chmod +x scripts/setup.sh
sudo ./scripts/setup.sh
```

The setup script will:
1. Update system packages
2. Install Docker & Docker Compose
3. Create Docker network (hosting_net)
4. Configure Nginx
5. Install Portainer
6. Install management scripts

### Step 3: Access Portainer

Open your browser and navigate to:
- **http://your-server-ip:9001**

Create an admin user when prompted.

### Step 4: Create your first hosting user

```bash
sudo create_user.sh username domain.com
```

Example:
```bash
sudo create_user.sh john example.com
sudo create_user.sh alice mywebsite.org 8.2
```

## Management Commands

### Create a new user

```bash
sudo create_user.sh <username> <domain> [php_version]
```

Parameters:
- `username` - Linux username (lowercase, starts with letter)
- `domain` - Your domain name
- `php_version` - PHP version (optional, default: 8.2)

Examples:
```bash
sudo create_user.sh john example.com
sudo create_user.sh alice mysite.org 8.1
sudo create_user.sh bob test.com 8.0
```

### Delete a user

```bash
sudo delete_user.sh <username>
```

Example:
```bash
sudo delete_user.sh john
```

**Warning:** This will permanently delete all user data!

### List all users

```bash
sudo list_users.sh
```

Shows:
- All configured sites
- Container status
- Domain names
- Ports

## Directory Structure

After creating users, the following structure is created:

```
/var/www/
├── john/
│   ├── site/              # Website files (upload via FTP)
│   │   ├── index.php
│   │   └── ...
│   ├── docker/
│   │   ├── Dockerfile
│   │   ├── docker-compose.yml
│   │   └── (built images)
│   └── logs/
│       ├── access.log
│       └── error.log
│
├── alice/
│   └── ...
```

### Nginx Configuration

Each user gets an Nginx configuration:
- `/etc/nginx/sites-available/john.conf`
- Symlink: `/etc/nginx/sites-enabled/john.conf`

## FTP Access

Each user can access their home directory via FTP:

```
Host: your-server-ip
Port: 21
Username: john
Password: (set during user creation)
```

The user is chrooted to their home directory (`/var/www/john`) and cannot access other directories.

## Docker Containers

Each website runs in its own container:

```bash
# List running containers
docker ps

# View container logs
docker logs john_php

# Stop container
docker stop john_php

# Start container
docker start john_php

# Restart container
docker restart john_php

# Access container shell
docker exec -it john_php sh
```

## SSL/HTTPS Setup

### Using Certbot (Let's Encrypt)

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Generate SSL certificate
sudo certbot --nginx -d example.com

# Test auto-renewal
sudo certbot renew --dry-run
```

### Manual SSL Configuration

After getting certificates, update the nginx config:

```bash
sudo vim /etc/nginx/sites-available/john.conf
```

Uncomment the SSL section and update paths:

```nginx
listen 443 ssl http2;
listen [::]:443 ssl http2;
ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
```

Then reload Nginx:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Resource Limits

Each container has these limits (configurable in docker-compose.yml):

```yaml
deploy:
  resources:
    limits:
      cpus: '0.5'
      memory: 256M
```

Adjust these values based on your server resources and user needs.

## Troubleshooting

### Nginx not reloading

```bash
# Check nginx configuration
sudo nginx -t

# View nginx error logs
sudo tail -f /var/log/nginx/error.log

# Manual reload
sudo systemctl reload nginx
```

### Container not starting

```bash
# Check container logs
docker logs john_php

# Check docker-compose.yml
cat /var/www/john/docker/docker-compose.yml

# Rebuild container
cd /var/www/john/docker
sudo -u john docker compose build
sudo -u john docker compose up -d
```

### Port already in use

```bash
# Find what's using the port
sudo netstat -tulpn | grep :9000

# Or use lsof
sudo lsof -i :9000
```

### Permission issues

```bash
# Fix ownership
sudo chown -R john:john /var/www/john

# Fix permissions
sudo chmod -R 755 /var/www/john
sudo chmod -R 777 /var/www/john/logs
```

### Network issues

```bash
# Check Docker network
docker network ls
docker network inspect hosting_net

# Recreate network if needed
docker network rm hosting_net
docker network create hosting_net
```

## Maintenance

### Update Portainer

```bash
docker stop portainer
docker rm portainer
docker pull portainer/portainer-ce:latest

# Run with same parameters as before
docker run -d \
    --name portainer \
    --restart=always \
    -p 9001:9000 \
    -p 9443:9443 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /var/lib/portainer:/data \
    --network hosting_net \
    portainer/portainer-ce:latest
```

### Backup user data

```bash
# Backup all users
sudo tar -czf backup-$(date +%Y%m%d).tar.gz /var/www/

# Backup nginx configs
sudo tar -czf nginx-backup-$(date +%Y%m%d).tar.gz /etc/nginx/
```

### Monitor Docker

```bash
# Docker stats
docker stats

# Container resource usage
docker stats john_php

# View container logs
docker logs -f john_php
```

## Security Recommendations

1. **Firewall**: Configure UFW
   ```bash
   sudo ufw allow 22
   sudo ufw allow 80
   sudo ufw allow 443
   sudo ufw allow 9001
   sudo ufw enable
   ```

2. **Fail2ban**: Install to prevent brute force attacks
   ```bash
   sudo apt install fail2ban
   ```

3. **Regular updates**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

4. **Disable root login** (after creating admin user):
   ```bash
   sudo vim /etc/ssh/sshd_config
   # Set PermitRootLogin no
   sudo systemctl restart sshd
   ```

## Additional Features

### Adding custom PHP extensions

Edit the Dockerfile template:

```dockerfile
RUN docker-php-ext-install <extension>
# Example:
RUN docker-php-ext-install gd mysql zip
```

### Adding Node.js support

Create a custom Dockerfile:

```dockerfile
FROM node:18-alpine

WORKDIR /var/www/html
COPY . .

RUN npm install

CMD ["npm", "start"]
```

Then update the docker-compose.yml to use the custom Dockerfile.

## Support

For issues and questions:
- Check Portainer logs: `docker logs portainer`
- Check system logs: `journalctl -u nginx`
- Review Nginx error logs in each user's logs directory

