# PutzOfficial Pterodactyl Installer

Installer Bash modular untuk Pterodactyl Panel dan Wings.

## Target

- Ubuntu
- x86_64 / amd64

## Komponen

- Pterodactyl Panel
- PHP
- MariaDB
- Redis
- Nginx
- Composer
- Let's Encrypt
- Docker
- Pterodactyl Wings
- systemd
- UFW

## Struktur

```text
putz-installer/
├── install.sh
├── lib/
│   ├── common.sh
│   ├── panel.sh
│   ├── docker.sh
│   └── wings.sh
└── README.md
