# Minimalistic Self-Hosted Web Hosting

A lightweight, Docker-based web hosting solution for Linux servers (Ubuntu 22.04).

## Features

- **Docker-based isolation** - Each website runs in its own container
- **PHP-FPM support** - FastCGI processing via Nginx
- **Portainer integration** - Web-based container management
- **FTP access** - User isolation with chroot
- **Nginx reverse proxy** - Centralized web server configuration
- **Resource limits** - CPU and memory constraints per container
- **SSL support** - Let's Encrypt / Certbot compatible
- **Simple management** - Bash scripts for all operations

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Ubuntu 22.04 Server                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────┐      ┌──────────────────────────────┐ │
│  │   Nginx     │      │     Docker Network           │ │
│  │  (Reverse   │──────│  ┌─────────┐ ┌─────────┐    │ │
│  │   Proxy)    │      │  │ user1   │ │ user2   │    │ │
│  │   :80, :443 │      │  │ _php    │ │ _php    │    │ │
│  └─────────────┘      │  │ :9000   │ │ :9001   │    │ │
│                       │  └─────────┘ └─────────┘    │ │
│                       │         hosting_net        │ │
│                       └──────────────────────────────┘ │
│                                                          │
│  ┌─────────────┐                                        │
│  │  Portainer  │  (Port 9001)                           │
│  └─────────────┘                                        │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# 1. Run setup (as root)
sudo ./scripts/setup.sh

# 2. Create first user
sudo create_user.sh john example.com

# 3. Access the site
# http://example.com
```

## Requirements

- Ubuntu 22.04 LTS
- Root/sudo access
- 2GB+ RAM
- 20GB+ disk space

## Project Structure

```
hosting5/
├── README.md              # This file
├── INSTALL.md             # Detailed installation guide
├── docker-compose.yml     # Portainer setup
├── templates/
│   ├── nginx.conf.template    # Nginx site template
│   ├── Dockerfile.php         # PHP-FPM container
│   └── docker-compose.yml     # Container template
└── scripts/
    ├── setup.sh           # Initial server setup
    ├── create_user.sh    # Create hosting user
    ├── delete_user.sh    # Delete hosting user
    └── list_users.sh     # List active sites
```

## User Management

### Create User

```bash
sudo create_user.sh <username> <domain> [php_version]

# Examples
sudo create_user.sh john example.com
sudo create_user.sh alice mysite.org 8.1
```

### Delete User

```bash
sudo delete_user.sh john
```

### List Users

```bash
sudo list_users.sh
```

## Container Access

Each website runs in an isolated container:

| Username | Container Name | Internal Port |
|----------|---------------|---------------|
| john     | john_php      | 9000          |
| alice    | alice_php     | 9001          |

### Docker Commands

```bash
# List containers
docker ps

# View logs
docker logs john_php

# Access shell
docker exec -it john_php sh

# Restart container
docker restart john_php
```

## Portainer

Web-based Docker management:

- **URL**: http://your-server-ip:9001
- **Initial setup**: Create admin user on first access

## FTP Access

```
Host: your-server-ip
Port: 21
Username: john
Password: (set during user creation)
```

Users are chrooted to `/var/www/username`

## SSL/HTTPS

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Generate certificate
sudo certbot --nginx -d example.com
```

## Security Features

- Non-root Docker containers
- Resource limits (CPU/RAM)
- FTP chroot isolation
- Separate Docker network
- Nginx process isolation

## License

MIT License

## Author

Created for minimalistic self-hosted web hosting needs.

