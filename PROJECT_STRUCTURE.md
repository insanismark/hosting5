# Minimalistic Self-Hosted Web Hosting - Project Structure

## Directory Structure

```
/home/mark/Документы/hosting5/
├── README.md
├── INSTALL.md
├── docker-compose.yml          # Main docker-compose for Portainer
├── templates/
│   ├── nginx.conf.template     # Nginx site template
│   ├── docker-compose.yml      # User docker-compose template
│   └── Dockerfile.php          # PHP-FPM Dockerfile template
├── scripts/
│   ├── create_user.sh          # Create new hosting user
│   ├── delete_user.sh          # Delete hosting user
│   ├── list_users.sh           # List active sites
│   ├── setup.sh                # Initial server setup
│   └── install.sh              # Main installation script
└── docs/
    └── ARCHITECTURE.md         # Architecture documentation
```

## Key Components to Create

1. **templates/nginx.conf.template** - Nginx configuration template
2. **templates/Dockerfile.php** - PHP-FPM Dockerfile
3. **templates/docker-compose.yml** - Docker Compose template
4. **scripts/create_user.sh** - User creation script
5. **scripts/delete_user.sh** - User deletion script
6. **scripts/list_users.sh** - List active sites
7. **scripts/setup.sh** - Initial server setup
8. **docker-compose.yml** - Portainer and hosting network
9. **INSTALL.md** - Installation instructions
10. **README.md** - Project documentation

