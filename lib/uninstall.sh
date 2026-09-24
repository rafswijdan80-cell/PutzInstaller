#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"


# ============================================================
# PUTZOFFICIAL FULL UNINSTALLER
# ============================================================

uninstall_panel() {

    clear 2>/dev/null || true

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                                                    │"
    echo "│        PUTZOFFICIAL FULL UNINSTALLER              │"
    echo "│                                                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    echo "  PERINGATAN"
    echo "  ──────────────────────────────────────────────────"
    echo
    echo "  Fitur ini akan menghapus komponen Pterodactyl"
    echo "  dan service yang digunakan installer."
    echo
    echo "  Yang akan dihapus:"
    echo
    echo "    • Pterodactyl Panel"
    echo "    • Database Pterodactyl"
    echo "    • User database Pterodactyl"
    echo "    • Nginx configuration Panel"
    echo "    • Pterodactyl Queue Worker"
    echo "    • Pterodactyl Scheduler"
    echo "    • Wings"
    echo "    • Wings configuration"
    echo "    • Docker"
    echo "    • Redis"
    echo "    • MariaDB"
    echo "    • PHP 8.3"
    echo "    • PHP-FPM"
    echo "    • Certbot"
    echo
    echo "  Installer PutzOfficial sendiri TIDAK dihapus."
    echo
    echo "  PERHATIAN:"
    echo "  Jika VPS menggunakan Nginx, MariaDB, Redis,"
    echo "  PHP, atau Docker untuk aplikasi lain, aplikasi"
    echo "  tersebut dapat ikut terdampak."
    echo

    echo "╭────────────────────────────────────────────────────╮"
    echo "│  Ketik REMOVE EVERYTHING untuk melanjutkan        │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    local confirmation

    read -r -p "  Confirmation ❯ " confirmation

    if [[ "$confirmation" != "REMOVE EVERYTHING" ]]; then

        echo
        warn "Konfirmasi salah."
        info "Uninstall dibatalkan."
        echo

        return 0

    fi


    # ========================================================
    # SECOND CONFIRMATION
    # ========================================================

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                 FINAL WARNING                     │"
    echo "╰────────────────────────────────────────────────────╯"
    echo
    warn "Tindakan ini tidak dapat dibatalkan."
    echo

    local final_confirmation

    read -r -p "  Ketik YES untuk benar-benar menghapus ❯ " final_confirmation

    if [[ "$final_confirmation" != "YES" ]]; then

        echo
        warn "Uninstall dibatalkan."
        echo

        return 0

    fi


    # ========================================================
    # START
    # ========================================================

    echo

    info "Memulai full uninstall PutzOfficial..."

    echo


    # ========================================================
    # STOP SERVICES
    # ========================================================

    info "Menghentikan service Pterodactyl..."


    systemctl stop pteroq 2>/dev/null || true
    systemctl disable pteroq 2>/dev/null || true


    info "Menghentikan Wings..."


    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true


    # ========================================================
    # REMOVE SYSTEMD SERVICES
    # ========================================================

    info "Menghapus service Pterodactyl..."


    rm -f \
        /etc/systemd/system/pteroq.service


    rm -f \
        /etc/systemd/system/wings.service


    systemctl daemon-reload


    # ========================================================
    # REMOVE CRON
    # ========================================================

    info "Menghapus scheduler Pterodactyl..."


    if id www-data >/dev/null 2>&1; then

        (
            crontab -u www-data -l 2>/dev/null |
            grep -v 'pterodactyl/artisan schedule:run' ||
            true

        ) | crontab -u www-data - 2>/dev/null || true

    fi


    # ========================================================
    # REMOVE NGINX CONFIG
    # ========================================================

    info "Menghapus konfigurasi Nginx Pterodactyl..."


    rm -f \
        /etc/nginx/sites-enabled/pterodactyl.conf


    rm -f \
        /etc/nginx/sites-available/pterodactyl.conf


    # Remove possible Pterodactyl snippets if created

    rm -f \
        /etc/nginx/conf.d/pterodactyl.conf


    # ========================================================
    # REMOVE PANEL DIRECTORY
    # ========================================================

    info "Menghapus Pterodactyl Panel..."


    rm -rf \
        /var/www/pterodactyl


    # ========================================================
    # REMOVE PTERODACTYL CONFIGURATION
    # ========================================================

    info "Menghapus konfigurasi Pterodactyl..."


    rm -rf \
        /etc/pterodactyl


    # ========================================================
    # REMOVE WINGS CONFIGURATION
    # ========================================================

    rm -rf \
        /var/lib/pterodactyl


    # ========================================================
    # DATABASE
    # ========================================================

    info "Menghapus database Pterodactyl..."


    if systemctl is-active --quiet mariadb 2>/dev/null ||
       systemctl is-active --quiet mysql 2>/dev/null; then

        mysql <<'SQL' 2>/dev/null || true
DROP DATABASE IF EXISTS panel;

DROP USER IF EXISTS
'pterodactyl'@'127.0.0.1';

DROP USER IF EXISTS
'pterodactyl'@'localhost';

FLUSH PRIVILEGES;
SQL

    fi


    # ========================================================
    # REMOVE COMPOSER
    # ========================================================

    info "Menghapus Composer..."


    if [[ -f /usr/local/bin/composer ]]; then

        rm -f \
            /usr/local/bin/composer

    fi


    # ========================================================
    # REMOVE PHP 8.3
    # ========================================================

    info "Menghapus PHP 8.3..."


    systemctl stop php8.3-fpm 2>/dev/null || true
    systemctl disable php8.3-fpm 2>/dev/null || true


    apt-get purge -y \
        php8.3 \
        php8.3-cli \
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
        2>/dev/null || true


    # ========================================================
    # REMOVE REDIS
    # ========================================================

    info "Menghapus Redis..."


    systemctl stop redis-server 2>/dev/null || true
    systemctl disable redis-server 2>/dev/null || true


    apt-get purge -y \
        redis-server \
        redis-tools \
        2>/dev/null || true


    # ========================================================
    # REMOVE MARIADB
    # ========================================================

    info "Menghapus MariaDB..."


    systemctl stop mariadb 2>/dev/null || true
    systemctl disable mariadb 2>/dev/null || true


    apt-get purge -y \
        mariadb-server \
        mariadb-client \
        mariadb-common \
        2>/dev/null || true


    # ========================================================
    # REMOVE DOCKER
    # ========================================================

    info "Menghapus Docker..."


    systemctl stop docker 2>/dev/null || true
    systemctl stop docker.socket 2>/dev/null || true


    systemctl disable docker 2>/dev/null || true
    systemctl disable docker.socket 2>/dev/null || true


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


    # ========================================================
    # REMOVE DOCKER DATA
    # ========================================================

    info "Menghapus data Docker..."


    rm -rf \
        /var/lib/docker


    rm -rf \
        /var/lib/containerd


    rm -rf \
        /etc/docker


    # ========================================================
    # REMOVE WINGS BINARY
    # ========================================================

    info "Menghapus Wings binary..."


    rm -f \
        /usr/local/bin/wings


    rm -f \
        /usr/bin/wings


    rm -f \
        /usr/local/sbin/wings


    # ========================================================
    # REMOVE NGINX
    # ========================================================

    info "Menghapus Nginx..."


    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true


    apt-get purge -y \
        nginx \
        nginx-common \
        nginx-core \
        2>/dev/null || true


    # ========================================================
    # REMOVE CERTBOT
    # ========================================================

    info "Menghapus Certbot..."


    apt-get purge -y \
        certbot \
        python3-certbot-nginx \
        2>/dev/null || true


    # ========================================================
    # REMOVE CERTBOT DATA
    # ========================================================

    rm -rf \
        /etc/letsencrypt


    rm -rf \
        /var/lib/letsencrypt


    rm -rf \
        /var/log/letsencrypt


    # ========================================================
    # REMOVE PHP CONFIG
    # ========================================================

    rm -rf \
        /etc/php/8.3


    # ========================================================
    # REMOVE PTERODACTYL LOGS
    # ========================================================

    rm -rf \
        /var/log/pterodactyl


    rm -rf \
        /var/log/putzofficial-installer


    # ========================================================
    # AUTOREMOVE
    # ========================================================

    info "Membersihkan dependency yang tidak digunakan..."


    apt-get autoremove -y 2>/dev/null || true


    apt-get autoclean -y 2>/dev/null || true


    # ========================================================
    # VERIFY REMOVAL
    # ========================================================

    echo

    info "Memeriksa hasil uninstall..."


    local failed=0


    # Panel

    if [[ -d /var/www/pterodactyl ]]; then

        warn "Pterodactyl directory masih ditemukan."

        failed=1

    else

        log "Pterodactyl Panel: removed"

    fi


    # Pterodactyl config

    if [[ -d /etc/pterodactyl ]]; then

        warn "Konfigurasi /etc/pterodactyl masih ditemukan."

        failed=1

    else

        log "Pterodactyl config: removed"

    fi


    # Pteroq

    if [[ -f /etc/systemd/system/pteroq.service ]]; then

        warn "pteroq.service masih ditemukan."

        failed=1

    else

        log "Pterodactyl Queue: removed"

    fi


    # Wings

    if command -v wings >/dev/null 2>&1; then

        warn "Wings binary masih ditemukan."

        failed=1

    else

        log "Wings: removed"

    fi


    # Docker

    if command -v docker >/dev/null 2>&1; then

        warn "Docker command masih tersedia."

        failed=1

    else

        log "Docker: removed"

    fi


    # ========================================================
    # DATABASE VERIFY
    # ========================================================

    if command -v mysql >/dev/null 2>&1; then

        if mysql \
            -e "SHOW DATABASES;" \
            2>/dev/null |
            grep -qx "panel"; then

            warn "Database panel masih ditemukan."

            failed=1

        else

            log "Pterodactyl database: removed"

        fi

    else

        log "MariaDB/MySQL: removed"

    fi


    # ========================================================
    # FINAL
    # ========================================================

    echo

    if [[ "$failed" -eq 0 ]]; then

        echo "╭────────────────────────────────────────────────────╮"
        echo "│                                                    │"
        echo "│          FULL UNINSTALL COMPLETE                  │"
        echo "│                                                    │"
        echo "╰────────────────────────────────────────────────────╯"
        echo

        info "Pterodactyl Panel : removed"
        info "Database          : removed"
        info "MariaDB           : removed"
        info "Redis             : removed"
        info "Nginx             : removed"
        info "PHP 8.3           : removed"
        info "Docker            : removed"
        info "Wings             : removed"
        info "Certbot            : removed"
        info "Pterodactyl config: removed"

        echo
        info "PutzOfficial Installer tetap tersedia."
        echo

    else

        echo "╭────────────────────────────────────────────────────╮"
        echo "│             UNINSTALL FINISHED                    │"
        echo "╰────────────────────────────────────────────────────╯"
        echo

        warn "Beberapa komponen masih terdeteksi."
        warn "Silakan cek output di atas."

        echo

    fi


    # ========================================================
    # RETURN
    # ========================================================

    return 0
}


# ============================================================
# START
# ============================================================

uninstall_panel
