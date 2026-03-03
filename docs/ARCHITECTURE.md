# Architecture Documentation

## Overview

This hosting solution uses a container-based architecture where each customer website runs in its own isolated Docker container. Nginx acts as a reverse proxy, forwarding requests to the appropriate container.

## Components

### 1. Nginx (Reverse Proxy)

- **Location**: Host system
- **Purpose**: Main web server, SSL termination, reverse proxy
- **Port**: 80 (HTTP), 443 (HTTPS)
- **Configuration**: `/etc/nginx/sites-available/{username}.conf`

**How it works:**
1. Receives HTTP/HTTPS requests
2. Matches request by domain (server_name)
3. Forwards to Docker container via fastcgi_pass
4. Container processes PHP and returns response

### 2. Docker

- **Location**: Host system
- **Purpose**: Container runtime
- **Network**: hosting_net (bridge)

**Container naming:**
- `{username}_php` - PHP-FPM container

### 3. PHP-FPM Containers

Each user gets their own container:

```yaml
# Resource limits
cpus: 0.5        # Max 50% CPU
memory: 256M     # Max 256MB RAM
```

**Container features:**
- Alpine-based (lightweight)
- Non-root user (security)
- Read-only site volume
- Persistent logs volume

### 4. Docker Network

```
Network Name: hosting_net
Driver: bridge
Subnet: Auto-assigned (172.17-19.x.x)
```

All containers connect to this network for inter-container communication.

### 5. Portainer

- **Purpose**: Web UI for Docker management
- **Port**: 9001 (HTTP), 9443 (HTTPS)
- **Network**: hosting_net

## Data Flow

```
User Request
    │
    ▼
DNS Resolution
    │
    ▼
Nginx (Port 80/443)
    │
    ├── Parse domain
    │
    ▼
Match server_name
    │
    ▼
fastcgi_pass to container
    │
    ▼
Docker Network (hosting_net)
    │
    ▼
PHP-FPM Container
    │
    ├── Process PHP
    │
    ▼
Return response
    │
    ▼
Nginx → User
```

## Directory Structure

### Host System

```
/var/www/
├── john/
│   ├── site/              # Website files (via FTP)
│   │   ├── index.php
│   │   └── ...
│   ├── docker/            # Container config
│   │   ├── Dockerfile
│   │   ├── docker-compose.yml
│   │   └── .env (generated)
│   └── logs/              # Web logs
│       ├── access.log
│       └── error.log

/etc/nginx/
├── sites-available/
│   ├── default
│   ├── john.conf
│   └── alice.conf
└── sites-enabled/
    ├── default -> ../sites-available/default
    ├── john.conf -> ../sites-available/john.conf
    └── alice.conf -> ../sites-available/alice.conf
```

### Inside Container

```
/var/www/html/     # Site files (read-only mount)
/var/log/php/     # PHP logs (persistent volume)
```

## Security Architecture

### 1. User Isolation

- Each user is a separate Linux user
- FTP chroot to `/var/www/{username}`
- Cannot access other users' files

### 2. Container Security

- **Non-root user**: Container runs as `appuser` (UID 1000)
- **Read-only volumes**: Site files mounted as read-only
- **Resource limits**: CPU and memory caps
- **No privileged mode**: Containers cannot escape isolation

### 3. Network Security

- Isolated Docker network
- Only Nginx can reach containers (via internal network)
- External access only through Nginx

### 4. File Permissions

```bash
/var/www/john/          # owner: john:john
├── site/               # 755 (readable, not writable via FTP)
├── docker/             # 755 (config files)
└── logs/               # 777 (writable for log rotation)
```

## Port Allocation

| Service | Port | Protocol |
|---------|------|----------|
| Nginx HTTP | 80 | TCP |
| Nginx HTTPS | 443 | TCP |
| Portainer | 9001 | TCP |
| Portainer SSL | 9443 | TCP |
| PHP-FPM (user1) | 9000 | Internal |
| PHP-FPM (user2) | 9001* | Internal |
| FTP | 21 | TCP |

*Internal ports are Docker-internal only, not exposed to host.

## Backup Strategy

### Manual Backup

```bash
# Backup all user data
sudo tar -czf /backup/www-$(date +%Y%m%d).tar.gz /var/www/

# Backup nginx configs
sudo tar -czf /backup/nginx-$(date +%Y%m%d).tar.gz /etc/nginx/

# Backup Docker volumes
docker run --rm \
  -v portainer_data:/data \
  -v $(pwd):/backup \
  alpine \
  tar czf /backup/portainer-$(date +%Y%m%d).tar.gz /data
```

### What to Back Up

1. `/var/www/` - All user websites
2. `/etc/nginx/` - Nginx configurations
3. Docker volumes - Portainer data
4. SSL certificates (if using Let's Encrypt)

## Monitoring

### Container Health

```bash
# Check container health
docker inspect --format='{{.State.Health.Status}}' john_php

# Container stats
docker stats john_php

# View logs
docker logs -f john_php
```

### System Resources

```bash
# Docker usage
docker system df

# Container resource usage
docker stats --no-stream
```

## Scaling Considerations

### Vertical Scaling

- Increase resource limits in docker-compose.yml
- Monitor with Portainer
- Adjust based on traffic patterns

### Horizontal Scaling

This architecture is designed for single-server use. For horizontal scaling:

1. Add load balancer (Nginx/HAProxy)
2. Use shared storage (NFS/GlusterFS)
3. Implement Docker Swarm or Kubernetes

## Troubleshooting Flow

```
Site not loading
    │
    ▼
1. Check Nginx status
   systemctl status nginx
    │
    ▼
2. Check DNS resolution
   ping domain.com
    │
    ▼
3. Check container running
   docker ps | grep username
    │
    ▼
4. Check container logs
   docker logs username_php
    │
    ▼
5. Check nginx error log
   tail -f /var/www/username/logs/error.log
    │
    ▼
6. Check docker network
   docker network inspect hosting_net
```

## Future Enhancements

Potential improvements:

1. **Automatic SSL** - Let's Encrypt auto-renewal
2. **Backups** - Automated backup scripts
3. **Monitoring** - Prometheus + Grafana
4. **Log rotation** - Logrotate configuration
5. **Multi-container** - PHP + MySQL per user
6. **Custom domains** - Automated domain validation
7. **Billing** - Usage tracking

