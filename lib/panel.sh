#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"


# ============================================================
# INSTALL PTERODACTYL PANEL
# ============================================================

install_panel() {

    info "Menginstall dependency Pterodactyl..."

    # --------------------------------------------------------
    # BASIC DEPENDENCIES
    # --------------------------------------------------------

    apt_install \
        ca-certificates \
        curl \
        git \
        unzip \
        tar \
        nginx \
        mariadb-server \
        mariadb-client \
        redis-server \
        software-properties-common

    # --------------------------------------------------------
    # PHP 8.3
    # --------------------------------------------------------

    info "Menginstall PHP 8.3..."

    apt_install \
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
        php8.3-opcache

    # --------------------------------------------------------
    # ENABLE SERVICES
    # --------------------------------------------------------

    info "Mengaktifkan service..."

    systemctl enable --now mariadb
    systemctl enable --now redis-server
    systemctl enable --now php8.3-fpm
    systemctl enable --now nginx


    # ========================================================
    # COMPOSER
    # ========================================================

    if ! command_exists composer; then

        info "Menginstall Composer..."

        apt_install \
            php-cli \
            php-zip

        curl -fsSL \
            https://getcomposer.org/installer \
            -o /tmp/composer-setup.php

        php /tmp/composer-setup.php \
            --install-dir=/usr/local/bin \
            --filename=composer

        rm -f /tmp/composer-setup.php

    else

        log "Composer sudah tersedia."

    fi


    # ========================================================
    # USER INPUT
    # ========================================================

    local domain
    local db_pass
    local admin_email

    domain="$(ask_required \
        'Domain Panel, contoh panel.example.com')"

    db_pass="$(ask_required \
        'Password database MariaDB')"

    admin_email="$(ask_required \
        'Email admin Panel')"


    # ========================================================
    # CHECK EXISTING PANEL
    # ========================================================

    if [[ -d /var/www/pterodactyl &&
          -f /var/www/pterodactyl/artisan ]]; then

        warn "Pterodactyl sudah ditemukan."
        warn "Download source dilewati."

    else

        # ====================================================
        # DOWNLOAD PTERODACTYL
        # ====================================================

        info "Mengambil release Pterodactyl..."

        local tag
        local url

        tag="$(
            curl -fsSL \
                -H "Accept: application/vnd.github+json" \
                https://api.github.com/repos/pterodactyl/panel/releases/latest |
            sed -n 's/.*"tag_name": "\(.*\)",/\1/p' |
            head -n 1
        )"

        if [[ -z "$tag" ]]; then
            error "Tidak dapat mendapatkan versi Pterodactyl dari GitHub."
            return 1
        fi

        # Official release asset
        url="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"

        info "Release terbaru: $tag"
        info "Downloading: panel.tar.gz"

        mkdir -p /var/www/pterodactyl

        rm -f /tmp/pterodactyl.tar.gz

        curl -fL \
            --retry 3 \
            --retry-delay 2 \
            "$url" \
            -o /tmp/pterodactyl.tar.gz

        if [[ ! -s /tmp/pterodactyl.tar.gz ]]; then
            error "Download Pterodactyl gagal."
            return 1
        fi

        info "Extracting Pterodactyl..."

        tar -xzf \
            /tmp/pterodactyl.tar.gz \
            -C /var/www/pterodactyl \
            --strip-components=1

        rm -f /tmp/pterodactyl.tar.gz

        if [[ ! -f /var/www/pterodactyl/artisan ]]; then
            error "Source Pterodactyl tidak valid. File artisan tidak ditemukan."
            return 1
        fi

        log "Pterodactyl source berhasil di-download."

    fi


    # ========================================================
    # ENTER PANEL DIRECTORY
    # ========================================================

    cd /var/www/pterodactyl


    # ========================================================
    # ENVIRONMENT
    # ========================================================

    if [[ ! -f .env ]]; then

        info "Membuat konfigurasi .env..."

        cp .env.example .env

    else

        log ".env sudah tersedia."

    fi


    # ========================================================
    # DATABASE
    # ========================================================

    info "Membuat database MariaDB..."


    # Escape single quote untuk SQL
    local escaped_db_pass

    escaped_db_pass="${db_pass//\'/\'\'}"


    mysql <<SQL
CREATE DATABASE IF NOT EXISTS panel
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS
'pterodactyl'@'127.0.0.1'
IDENTIFIED BY '${escaped_db_pass}';

ALTER USER
'pterodactyl'@'127.0.0.1'
IDENTIFIED BY '${escaped_db_pass}';

GRANT ALL PRIVILEGES
ON panel.*
TO 'pterodactyl'@'127.0.0.1';

FLUSH PRIVILEGES;
SQL


    # ========================================================
    # COMPOSER
    # ========================================================

    info "Installing Composer dependencies..."

    composer install \
        --no-dev \
        --optimize-autoloader


    # ========================================================
    # APPLICATION KEY
    # ========================================================

    info "Generating application key..."

    php artisan key:generate --force


    # ========================================================
    # DATABASE CONFIGURATION
    # ========================================================

    info "Configuring database..."

    php artisan p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database=panel \
        --username=pterodactyl \
        --password="$db_pass"


    # ========================================================
    # APPLICATION CONFIGURATION
    # ========================================================

    info "Configuring application..."

    php artisan p:environment:setup \
        --author="$admin_email" \
        --url="https://$domain" \
        --timezone="Asia/Jakarta" \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=127.0.0.1 \
        --redis-port=6379 \
        --redis-password=null


    # ========================================================
    # DATABASE MIGRATION
    # ========================================================

    info "Migrating database..."

    php artisan migrate \
        --seed \
        --force


    # ========================================================
    # PERMISSIONS
    # ========================================================

    info "Mengatur permission..."

    chown -R www-data:www-data \
        /var/www/pterodactyl

    chmod -R 755 \
        /var/www/pterodactyl


    # ========================================================
    # NGINX
    # ========================================================

    info "Membuat konfigurasi Nginx..."

    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    listen [::]:80;

    server_name $domain;

    root /var/www/pterodactyl/public;

    index index.php index.html;

    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX


    ln -sf \
        /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/sites-enabled/pterodactyl.conf


    # Remove default nginx site if present
    if [[ -L /etc/nginx/sites-enabled/default ||
          -f /etc/nginx/sites-enabled/default ]]; then

        rm -f /etc/nginx/sites-enabled/default

    fi


    # Validate nginx
    nginx -t

    systemctl reload nginx


    # ========================================================
    # SSL
    # ========================================================

    if command_exists certbot; then

        info "Mencoba memasang SSL..."

        if certbot --nginx \
            -d "$domain" \
            --non-interactive \
            --agree-tos \
            -m "$admin_email" \
            --redirect; then

            log "SSL berhasil dikonfigurasi."

        else

            warn "SSL belum berhasil."
            warn "Pastikan DNS domain sudah mengarah ke VPS."

        fi

    else

        warn "Certbot belum tersedia."
        warn "SSL otomatis dilewati."

    fi


    # ========================================================
    # QUEUE WORKER
    # ========================================================

    info "Membuat Queue Worker..."

    cat > /etc/systemd/system/pteroq.service <<'SERVICE'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
Wants=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
RestartSec=5

WorkingDirectory=/var/www/pterodactyl

ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
SERVICE


    systemctl daemon-reload

    systemctl enable --now pteroq


    # ========================================================
    # SCHEDULER
    # ========================================================

    info "Mengaktifkan scheduler..."

    (
        crontab -u www-data -l 2>/dev/null |
        grep -v 'pterodactyl/artisan schedule:run' ||
        true

        echo '* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1'

    ) | crontab -u www-data -


    # ========================================================
    # FINAL CHECK
    # ========================================================

    info "Melakukan pengecekan akhir..."

    if [[ ! -f /var/www/pterodactyl/artisan ]]; then
        error "Pterodactyl Panel gagal dipasang."
        return 1
    fi

    if ! systemctl is-active --quiet nginx; then
        warn "Nginx tidak aktif."
    fi

    if ! systemctl is-active --quiet php8.3-fpm; then
        warn "PHP-FPM tidak aktif."
    fi

    if ! systemctl is-active --quiet mariadb; then
        warn "MariaDB tidak aktif."
    fi

    if ! systemctl is-active --quiet redis-server; then
        warn "Redis tidak aktif."
    fi


    # ========================================================
    # COMPLETE
    # ========================================================

    log "Pterodactyl Panel selesai."

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│              PANEL INSTALL COMPLETE                │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    info "Panel:"
    echo "https://$domain"

    echo
    info "Database:"
    echo "Database : panel"
    echo "Username : pterodactyl"
    echo "Host     : 127.0.0.1"
    echo

    info "Buat administrator dengan:"
    echo
    echo "cd /var/www/pterodactyl"
    echo "php artisan p:user:make"
    echo

}


# ============================================================
# START
# ============================================================

install_panel
