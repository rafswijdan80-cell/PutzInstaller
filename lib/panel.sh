#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

install_panel() {

    info "Menginstall dependency Pterodactyl..."

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

    systemctl enable --now mariadb
    systemctl enable --now redis-server
    systemctl enable --now php8.3-fpm
    systemctl enable --now nginx

    if ! command_exists composer; then

        info "Menginstall Composer..."

        apt_install php-cli php-zip

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

    local domain
    local db_pass
    local admin_email

    domain="$(ask_required \
        'Domain Panel, contoh panel.example.com')"

    db_pass="$(ask_required \
        'Password database MariaDB')"

    admin_email="$(ask_required \
        'Email admin Panel')"

    if [[ -d /var/www/pterodactyl &&
          -f /var/www/pterodactyl/artisan ]]; then

        warn "Pterodactyl sudah ditemukan."
        warn "Download source dilewati."

    else

        info "Mengambil release Pterodactyl..."

        local tag
        local url

        tag="$(
            curl -fsSL \
            https://api.github.com/repos/pterodactyl/panel/releases/latest |
            sed -n 's/.*"tag_name": "\(.*\)",/\1/p' |
            head -n 1
        )"

        [[ -n "$tag" ]] ||
            error "Tidak dapat mendapatkan versi Pterodactyl."

        url="https://github.com/pterodactyl/panel/releases/download/${tag}/panel-${tag#v}.tar.gz"

        mkdir -p /var/www/pterodactyl

        info "Downloading: $tag"

        curl -fL "$url" \
            -o /tmp/pterodactyl.tar.gz

        tar -xzf \
            /tmp/pterodactyl.tar.gz \
            -C /var/www/pterodactyl \
            --strip-components=1

        rm -f /tmp/pterodactyl.tar.gz

    fi

    cd /var/www/pterodactyl

    if [[ ! -f .env ]]; then
        cp .env.example .env
    fi

    info "Membuat database..."

    mysql <<SQL
CREATE DATABASE IF NOT EXISTS panel
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS
'pterodactyl'@'127.0.0.1'
IDENTIFIED BY '${db_pass//\'/\'\'}';

ALTER USER
'pterodactyl'@'127.0.0.1'
IDENTIFIED BY '${db_pass//\'/\'\'}';

GRANT ALL PRIVILEGES
ON panel.*
TO 'pterodactyl'@'127.0.0.1';

FLUSH PRIVILEGES;
SQL

    info "Installing Composer dependencies..."

    composer install \
        --no-dev \
        --optimize-autoloader

    info "Generating application key..."

    php artisan key:generate --force

    info "Configuring database..."

    php artisan p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database=panel \
        --username=pterodactyl \
        --password="$db_pass"

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

    info "Migrating database..."

    php artisan migrate \
        --seed \
        --force

    info "Mengatur permission..."

    chown -R www-data:www-data \
        /var/www/pterodactyl

    chmod -R 755 \
        /var/www/pterodactyl

    info "Membuat konfigurasi Nginx..."

    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    listen [::]:80;

    server_name $domain;

    root /var/www/pterodactyl/public;

    index index.php;

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

    nginx -t

    systemctl reload nginx

    if command_exists certbot; then

        info "Mencoba memasang SSL..."

        certbot --nginx \
            -d "$domain" \
            --non-interactive \
            --agree-tos \
            -m "$admin_email" \
            --redirect \
            || warn "SSL belum berhasil. Pastikan DNS domain sudah mengarah ke VPS."

    fi

    info "Membuat Queue Worker..."

    cat > /etc/systemd/system/pteroq.service <<'SERVICE'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload

    systemctl enable --now pteroq

    info "Mengaktifkan scheduler..."

    (
        crontab -u www-data -l 2>/dev/null |
        grep -v 'pterodactyl/artisan schedule:run' ||
        true

        echo '* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1'
    ) | crontab -u www-data -

    log "Pterodactyl Panel selesai."

    echo
    info "Panel:"
    echo "https://$domain"
    echo

    info "Buat administrator dengan:"
    echo
    echo "cd /var/www/pterodactyl"
    echo "php artisan p:user:make"
    echo
}

install_panel
