#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# PUTZOFFICIAL FULL PTERODACTYL UNINSTALLER
# ============================================================

VERSION="1.0.0"
NAME="PutzOfficial Full Pterodactyl Uninstaller"

DEVELOPER="PutzOfficial"
TELEGRAM_CHANNEL="https://t.me/PutzOfficial"
COPYRIGHT="© 2026 PutzOfficial. All Rights Reserved."

# ============================================================
# ROOT
# ============================================================

if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Script harus dijalankan sebagai root."
    exit 1
fi

# ============================================================
# FUNCTIONS
# ============================================================

info() {
    echo "[INFO] $*"
}

success() {
    echo "[OK] $*"
}

warn() {
    echo "[WARN] $*"
}

error() {
    echo "[ERROR] $*"
}

# ============================================================
# BANNER
# ============================================================

clear 2>/dev/null || true

echo
echo "╭────────────────────────────────────────────────────╮"
echo "│                                                    │"
echo "│       PUTZOFFICIAL FULL PTERODACTYL UNINSTALLER   │"
echo "│                                                    │"
echo "╰────────────────────────────────────────────────────╯"
echo

echo "  Name      : $NAME"
echo "  Version   : $VERSION"
echo "  Developer : $DEVELOPER"
echo "  Telegram  : $TELEGRAM_CHANNEL"
echo "  $COPYRIGHT"

echo
echo "  DESKRIPSI"
echo "  ──────────────────────────────────────────────────"
echo
echo "  Script ini digunakan untuk membersihkan"
echo "  environment Pterodactyl agar VPS dapat"
echo "  dipersiapkan kembali untuk reinstall."
echo

echo "  YANG AKAN DIHAPUS:"
echo
echo "    • Pterodactyl Panel"
echo "    • Pterodactyl Wings"
echo "    • Panel database"
echo "    • Database user"
echo "    • Nginx"
echo "    • Docker"
echo "    • Redis"
echo "    • MariaDB"
echo "    • PHP 8.3"
echo "    • PHP-FPM 8.3"
echo "    • Composer"
echo "    • Certbot"
echo "    • Pterodactyl configuration"
echo "    • Docker data"
echo "    • Let's Encrypt data"
echo "    • Panel logs"
echo

echo "  YANG DIPERTAHANKAN:"
echo
echo "    • SSH"
echo "    • Sistem operasi"
echo "    • Installer PutzOfficial"
echo

warn "PERINGATAN:"
warn "Script ini bersifat destruktif."
warn "Data Docker dan server Pterodactyl dapat hilang."
warn "Pastikan VPS memang ingin di-reset."
echo

# ============================================================
# FIRST CONFIRMATION
# ============================================================

echo "╭────────────────────────────────────────────────────╮"
echo "│  Ketik REMOVE EVERYTHING untuk melanjutkan        │"
echo "╰────────────────────────────────────────────────────╯"
echo

read -r -p "  Confirmation ❯ " confirmation

if [[ "$confirmation" != "REMOVE EVERYTHING" ]]; then

    echo
    warn "Konfirmasi salah."
    info "Uninstall dibatalkan."
    echo

    exit 0

fi

# ============================================================
# SECOND CONFIRMATION
# ============================================================

echo
echo "╭────────────────────────────────────────────────────╮"
echo "│                 FINAL WARNING                      │"
echo "╰────────────────────────────────────────────────────╯"
echo
warn "SEMUA DATA Pterodactyl/Docker yang dipilih akan dihapus."
warn "Tindakan ini tidak dapat dibatalkan."
echo

read -r -p "  Ketik YES untuk benar-benar menghapus ❯ " final_confirmation

if [[ "$final_confirmation" != "YES" ]]; then

    echo
    warn "Uninstall dibatalkan."
    echo

    exit 0

fi

# ============================================================
# STOP SERVICES
# ============================================================

echo
info "Menghentikan service Pterodactyl..."

systemctl stop pteroq 2>/dev/null || true
systemctl disable pteroq 2>/dev/null || true

info "Menghentikan Wings..."

systemctl stop wings 2>/dev/null || true
systemctl disable wings 2>/dev/null || true

info "Menghentikan Nginx..."

systemctl stop nginx 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true

info "Menghentikan Docker..."

systemctl stop docker 2>/dev/null || true
systemctl stop docker.socket 2>/dev/null || true

systemctl disable docker 2>/dev/null || true
systemctl disable docker.socket 2>/dev/null || true

info "Menghentikan Redis..."

systemctl stop redis-server 2>/dev/null || true
systemctl disable redis-server 2>/dev/null || true

info "Menghentikan MariaDB..."

systemctl stop mariadb 2>/dev/null || true
systemctl disable mariadb 2>/dev/null || true

info "Menghentikan PHP-FPM..."

systemctl stop php8.3-fpm 2>/dev/null || true
systemctl disable php8.3-fpm 2>/dev/null || true

# ============================================================
# SYSTEMD
# ============================================================

info "Menghapus systemd service..."

rm -f /etc/systemd/system/pteroq.service
rm -f /etc/systemd/system/wings.service

rm -f /usr/lib/systemd/system/pteroq.service
rm -f /usr/lib/systemd/system/wings.service

systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

success "Systemd cleanup selesai."

# ============================================================
# CRON
# ============================================================

info "Menghapus Pterodactyl scheduler..."

if id www-data >/dev/null 2>&1; then

    existing_cron="$(
        crontab -u www-data -l 2>/dev/null || true
    )"

    if [[ -n "$existing_cron" ]]; then

        printf '%s\n' "$existing_cron" |
            grep -v 'pterodactyl/artisan schedule:run' |
            crontab -u www-data - 2>/dev/null || true

    fi

fi

success "Scheduler cleanup selesai."

# ============================================================
# PANEL
# ============================================================

info "Menghapus Pterodactyl Panel..."

rm -rf /var/www/pterodactyl

success "Panel directory dihapus."

# ============================================================
# PTERODACTYL CONFIG
# ============================================================

info "Menghapus konfigurasi Pterodactyl..."

rm -rf /etc/pterodactyl

success "Pterodactyl configuration dihapus."

# ============================================================
# PTERODACTYL LOGS
# ============================================================

info "Menghapus log Pterodactyl..."

rm -rf /var/log/pterodactyl
rm -rf /var/log/putzofficial-installer

success "Pterodactyl logs dihapus."

# ============================================================
# NGINX CONFIG
# ============================================================

info "Menghapus konfigurasi Nginx Pterodactyl..."

rm -f /etc/nginx/sites-enabled/pterodactyl.conf
rm -f /etc/nginx/sites-available/pterodactyl.conf
rm -f /etc/nginx/conf.d/pterodactyl.conf

success "Nginx configuration Pterodactyl dihapus."

# ============================================================
# WINGS BINARY
# ============================================================

info "Menghapus Wings binary..."

rm -f /usr/local/bin/wings
rm -f /usr/bin/wings
rm -f /usr/local/sbin/wings

success "Wings binary dihapus."

# ============================================================
# DATABASE
# ============================================================

info "Menghapus database Pterodactyl..."

if command -v mysql >/dev/null 2>&1; then

    mysql <<'SQL' 2>/dev/null || true

DROP DATABASE IF EXISTS panel;

DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';

DROP USER IF EXISTS 'pterodactyl'@'localhost';

FLUSH PRIVILEGES;

SQL

fi

success "Database Panel dihapus."

# ============================================================
# COMPOSER
# ============================================================

info "Menghapus Composer yang dipasang installer..."

if [[ -f /usr/local/bin/composer ]]; then
    rm -f /usr/local/bin/composer
fi

success "Composer cleanup selesai."

# ============================================================
# PHP 8.3
# ============================================================

info "Menghapus PHP 8.3..."

apt-get purge -y \
    php8.3 \
    php8.3-cli \
    php8.3-common \
    php8.3-fpm \
    php8.3-gd \
    php8.3-mysql \
    php8.3-mbstring \
    php8.3-bcmath \
    php8.3-xml \
    php8.3-curl \
    php8.3-zip \
    php8.3-tokenizer \
    php8.3-opcache \
    php8.3-intl \
    2>/dev/null || true

rm -rf /etc/php/8.3

success "PHP 8.3 cleanup selesai."

# ============================================================
# REDIS
# ============================================================

info "Menghapus Redis..."

apt-get purge -y \
    redis-server \
    redis-tools \
    2>/dev/null || true

success "Redis dihapus."

# ============================================================
# MARIADB
# ============================================================

info "Menghapus MariaDB..."

apt-get purge -y \
    mariadb-server \
    mariadb-client \
    mariadb-common \
    2>/dev/null || true

success "MariaDB dihapus."

# ============================================================
# DOCKER PACKAGES
# ============================================================

info "Menghapus Docker..."

apt-get purge -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker.io \
    docker-compose \
    containerd \
    runc \
    2>/dev/null || true

success "Docker package dihapus."

# ============================================================
# DOCKER DATA
# ============================================================

info "Menghapus data Docker..."

rm -rf /var/lib/docker
rm -rf /var/lib/containerd
rm -rf /etc/docker

success "Docker data dihapus."

# ============================================================
# CERTBOT
# ============================================================

info "Menghapus Certbot..."

apt-get purge -y \
    certbot \
    python3-certbot-nginx \
    2>/dev/null || true

success "Certbot package dihapus."

# ============================================================
# LET'S ENCRYPT
# ============================================================

info "Menghapus data Let's Encrypt..."

rm -rf /etc/letsencrypt
rm -rf /var/lib/letsencrypt
rm -rf /var/log/letsencrypt

success "Let's Encrypt data dihapus."

# ============================================================
# APT CLEANUP
# ============================================================

info "Membersihkan dependency..."

apt-get autoremove -y 2>/dev/null || true
apt-get autoclean -y 2>/dev/null || true

success "APT cleanup selesai."

# ============================================================
# VERIFY
# ============================================================

echo
echo "╭────────────────────────────────────────────────────╮"
echo "│                  VERIFY CLEANUP                    │"
echo "╰────────────────────────────────────────────────────╯"
echo

FAILED=0

# Panel

if [[ -d /var/www/pterodactyl ]]; then

    warn "Panel directory masih ditemukan."
    FAILED=1

else

    success "Pterodactyl Panel: removed"

fi

# Config

if [[ -d /etc/pterodactyl ]]; then

    warn "Pterodactyl config masih ditemukan."
    FAILED=1

else

    success "Pterodactyl config: removed"

fi

# Wings

if [[ -f /usr/local/bin/wings ]] ||
   [[ -f /usr/bin/wings ]] ||
   [[ -f /usr/local/sbin/wings ]]; then

    warn "Wings binary masih ditemukan."
    FAILED=1

else

    success "Wings: removed"

fi

# Docker

if command -v docker >/dev/null 2>&1; then

    warn "Docker command masih tersedia."
    FAILED=1

else

    success "Docker: removed"

fi

# Nginx

if command -v nginx >/dev/null 2>&1; then

    warn "Nginx command masih tersedia."
    FAILED=1

else

    success "Nginx: removed"

fi

# ============================================================
# FINAL
# ============================================================

echo

if [[ "$FAILED" -eq 0 ]]; then

    echo "╭────────────────────────────────────────────────────╮"
    echo "│                                                    │"
    echo "│          FULL UNINSTALL COMPLETE                  │"
    echo "│                                                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    echo "  ✓ Pterodactyl Panel"
    echo "  ✓ Pterodactyl Wings"
    echo "  ✓ Nginx"
    echo "  ✓ Docker"
    echo "  ✓ MariaDB"
    echo "  ✓ Redis"
    echo "  ✓ PHP 8.3"
    echo "  ✓ PHP-FPM"
    echo "  ✓ Certbot"
    echo "  ✓ Pterodactyl configuration"
    echo "  ✓ Docker data"

    echo
    echo "  Installer PutzOfficial tetap tersedia."
    echo
    echo "  VPS siap dipersiapkan untuk reinstall Pterodactyl."
    echo
    echo "  Developer : $DEVELOPER"
    echo "  Telegram  : $TELEGRAM_CHANNEL"
    echo "  Version   : $VERSION"
    echo "  $COPYRIGHT"
    echo

else

    echo "╭────────────────────────────────────────────────────╮"
    echo "│           UNINSTALL FINISHED WITH WARNINGS        │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    warn "Beberapa komponen masih terdeteksi."
    warn "Silakan periksa output VERIFY CLEANUP di atas."

    exit 1

fi

exit 0
