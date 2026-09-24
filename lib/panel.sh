#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

# ============================================================
# PTERODACTYL PANEL INSTALLER
# PUTZOFFICIAL INSTALLER
# ============================================================

install_panel() {

    if [[ "${EUID}" -ne 0 ]]; then
        error "Installer Panel harus dijalankan sebagai root."
        return 1
    fi

    local domain=""
    local db_pass=""
    local admin_email=""
    local tag=""
    local panel_url=""
    local php_version="8.3"

    local archive="/tmp/pterodactyl.tar.gz"
    local extract_dir="/tmp/putzofficial-pterodactyl"

    # ========================================================
    # HEADER
    # ========================================================

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                                                    │"
    echo "│          PUTZOFFICIAL PANEL INSTALLER             │"
    echo "│                                                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    # ========================================================
    # USER INPUT
    # ========================================================

    domain="$(ask_required \
        'Domain Panel, contoh panel.example.com')"

    db_pass="$(ask_required \
        'Password database MariaDB')"

    admin_email="$(ask_required \
        'Email admin Panel')"

    # ========================================================
    # VALIDATE DOMAIN
    # ========================================================

    if [[ ! "$domain" =~ ^[A-Za-z0-9.-]+$ ]]; then
        error "Format domain tidak valid: $domain"
        return 1
    fi

    if [[ "$domain" == .* ||
          "$domain" == *..* ||
          "$domain" == *.-* ||
          "$domain" == *-. ]]; then

        error "Format domain tidak valid: $domain"
        return 1
    fi

    # ========================================================
    # VALIDATE EMAIL
    # ========================================================

    if [[ ! "$admin_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
        error "Format email tidak valid: $admin_email"
        return 1
    fi

    # ========================================================
    # PACKAGE UPDATE
    # ========================================================

    info "Mengupdate package repository..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y

    # ========================================================
    # BASIC DEPENDENCIES
    # ========================================================

    info "Menginstall dependency dasar..."

    apt_install \
        ca-certificates \
        curl \
        wget \
        git \
        unzip \
        tar \
        gzip \
        bzip2 \
        nginx \
        mariadb-server \
        mariadb-client \
        redis-server \
        software-properties-common \
        apt-transport-https \
        lsb-release \
        gnupg \
        gnupg2 \
        certbot \
        python3-certbot-nginx

    # ========================================================
    # PHP REPOSITORY
    # ========================================================

    info "Memeriksa repository PHP ${php_version}..."

    if ! apt-cache show "php${php_version}" >/dev/null 2>&1; then

        warn "PHP ${php_version} belum tersedia."
        info "Menambahkan repository Ondrej PHP..."

        apt_install \
            ca-certificates \
            lsb-release \
            apt-transport-https \
            software-properties-common

        if ! grep -Rqs "ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
            add-apt-repository -y ppa:ondrej/php
        fi

        apt-get update -y
    fi

    # ========================================================
    # PHP PACKAGES
    # ========================================================

    info "Menginstall / memperbaiki PHP ${php_version}..."

    apt-get install -y \
        "php${php_version}" \
        "php${php_version}-cli" \
        "php${php_version}-common" \
        "php${php_version}-fpm" \
        "php${php_version}-mysql" \
        "php${php_version}-gd" \
        "php${php_version}-mbstring" \
        "php${php_version}-bcmath" \
        "php${php_version}-xml" \
        "php${php_version}-curl" \
        "php${php_version}-zip" \
        "php${php_version}-opcache" \
        "php${php_version}-readline"

    # ========================================================
    # FIX BROKEN PHP MODULES
    # ========================================================

    info "Memeriksa konfigurasi PHP..."

    PHP_CONF="/etc/php/${php_version}/cli/conf.d"

    # Hapus konfigurasi pdo_mysql manual/duplikat
    # yang sering menyebabkan:
    # undefined symbol: pdo_parse_params

    if [[ -d "$PHP_CONF" ]]; then

        find "$PHP_CONF" \
            -type f \
            -name "*.ini" \
            -print0 |
        while IFS= read -r -d '' ini; do

            if grep -Eq '^[[:space:]]*(zend_)?extension[[:space:]]*=[[:space:]]*pdo_mysql(\.so)?[[:space:]]*$' "$ini" 2>/dev/null; then

                case "$(basename "$ini")" in
                    20-pdo_mysql.ini)
                        ;;
                    *)
                        warn "Menonaktifkan konfigurasi pdo_mysql duplikat: $ini"
                        mv "$ini" "${ini}.disabled" 2>/dev/null || true
                        ;;
                esac

            fi

        done
    fi

    # ========================================================
    # REINSTALL PHP MYSQL MODULE
    # ========================================================

    info "Memperbaiki PHP PDO/MySQL..."

    apt-get install --reinstall -y \
        "php${php_version}-common" \
        "php${php_version}-mysql"

    # ========================================================
    # PHP MODULE CONFIGURATION
    # ========================================================

    phpenmod \
        mysqlnd \
        mysqli \
        pdo_mysql \
        opcache \
        mbstring \
        xml \
        curl \
        zip \
        gd \
        bcmath \
        2>/dev/null || true

    # ========================================================
    # ENABLE PHP CLI
    # ========================================================

    if command_exists update-alternatives; then

        update-alternatives \
            --set php \
            "/usr/bin/php${php_version}" \
            >/dev/null 2>&1 || true

    fi

    # ========================================================
    # VERIFY PHP
    # ========================================================

    info "Memeriksa PHP..."

    if ! php -v >/dev/null 2>&1; then
        error "PHP ${php_version} tidak dapat dijalankan."
        return 1
    fi

    if ! php -m 2>/dev/null | grep -q "^PDO$"; then
        error "PHP PDO belum aktif."
        return 1
    fi

    if ! php -m 2>/dev/null | grep -qi "^pdo_mysql$"; then
        error "PHP pdo_mysql belum aktif."
        return 1
    fi

    # ========================================================
    # PHAR CHECK
    # ========================================================

    info "Memeriksa PHP Phar..."

    if ! php -r 'exit(class_exists("Phar") ? 0 : 1);' >/dev/null 2>&1; then

        warn "PHP Phar belum aktif."
        info "Memperbaiki PHP CLI..."

        apt-get install --reinstall -y \
            "php${php_version}-cli" \
            "php${php_version}-common"

        phpenmod phar 2>/dev/null || true
    fi

    if ! php -r 'exit(class_exists("Phar") ? 0 : 1);' >/dev/null 2>&1; then

        error "PHP Phar tidak tersedia."
        error "Composer tidak dapat dijalankan."
        return 1

    fi

    log "PHP PDO: OK"
    log "PHP pdo_mysql: OK"
    log "PHP Phar: OK"

    # ========================================================
    # SERVICES
    # ========================================================

    info "Mengaktifkan service..."

    systemctl enable --now mariadb
    systemctl enable --now redis-server
    systemctl enable --now "php${php_version}-fpm"
    systemctl enable --now nginx

    # ========================================================
    # SERVICE CHECK
    # ========================================================

    if ! systemctl is-active --quiet mariadb; then
        error "MariaDB gagal dijalankan."
        return 1
    fi

    if ! systemctl is-active --quiet redis-server; then
        error "Redis gagal dijalankan."
        return 1
    fi

    if ! systemctl is-active --quiet "php${php_version}-fpm"; then
        error "PHP-FPM gagal dijalankan."
        return 1
    fi

    if ! systemctl is-active --quiet nginx; then
        error "Nginx gagal dijalankan."
        return 1
    fi

    # ========================================================
    # COMPOSER
    # ========================================================

    if ! command_exists composer; then

        info "Menginstall Composer..."

        rm -f /tmp/composer-setup.php

        curl -fsSL \
            --retry 5 \
            --retry-delay 2 \
            --connect-timeout 20 \
            --max-time 120 \
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
    # COMPOSER CHECK
    # ========================================================

    if ! command_exists composer; then
        error "Composer gagal diinstall."
        return 1
    fi

    if ! composer --version >/dev/null 2>&1; then
        error "Composer tidak dapat dijalankan."
        return 1
    fi

    log "Composer: OK"

    # ========================================================
    # PANEL DIRECTORY
    # ========================================================

    mkdir -p /var/www

    # ========================================================
    # EXISTING PANEL
    # ========================================================

    if [[ -f /var/www/pterodactyl/artisan &&
          -f /var/www/pterodactyl/composer.json &&
          -d /var/www/pterodactyl/public ]]; then

        warn "Pterodactyl Panel sudah ditemukan."
        info "Source download dilewati."

    else

        # ====================================================
        # CLEAN BROKEN INSTALL
        # ====================================================

        if [[ -d /var/www/pterodactyl ]]; then

            warn "Source Pterodactyl tidak lengkap."
            info "Membersihkan instalasi gagal sebelumnya..."

            rm -rf /var/www/pterodactyl
        fi

        mkdir -p /var/www/pterodactyl

        # ====================================================
        # GET RELEASE
        # ====================================================

        info "Mengambil release Pterodactyl..."

        tag="$(
            curl -fsSL \
                --retry 5 \
                --retry-delay 2 \
                --connect-timeout 20 \
                --max-time 60 \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                https://api.github.com/repos/pterodactyl/panel/releases/latest |
            sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' |
            head -n 1
        )"

        if [[ -z "$tag" ]]; then
            error "Tidak dapat mendapatkan release Pterodactyl."
            return 1
        fi

        info "Release terbaru: $tag"

        # ====================================================
        # OFFICIAL DOWNLOAD
        # ====================================================

        panel_url="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"

        info "Downloading: panel.tar.gz"

        rm -f "$archive"

        curl -fL \
            --retry 5 \
            --retry-delay 3 \
            --connect-timeout 30 \
            --max-time 900 \
            "$panel_url" \
            -o "$archive"

        # ====================================================
        # VERIFY ARCHIVE
        # ====================================================

        if [[ ! -s "$archive" ]]; then
            error "panel.tar.gz kosong."
            return 1
        fi

        if ! tar -tzf "$archive" >/dev/null 2>&1; then
            error "Archive Pterodactyl rusak atau bukan tar.gz."
            return 1
        fi

        # ====================================================
        # EXTRACT TEMP
        # ====================================================

        rm -rf "$extract_dir"
        mkdir -p "$extract_dir"

        info "Extracting Pterodactyl..."

        tar -xzf \
            "$archive" \
            -C "$extract_dir"

        # ====================================================
        # FIND SOURCE
        # ====================================================

        local artisan_file=""
        local source_dir=""

        artisan_file="$(
            find "$extract_dir" \
                -type f \
                -name "artisan" \
                -print \
                -quit
        )"

        if [[ -z "$artisan_file" ]]; then

            error "File artisan tidak ditemukan setelah extraction."

            echo
            info "Isi archive teratas:"

            tar -tzf "$archive" |
                head -30 || true

            echo

            rm -rf "$extract_dir"
            rm -f "$archive"

            return 1
        fi

        source_dir="$(dirname "$artisan_file")"

        # ====================================================
        # SOURCE VALIDATION
        # ====================================================

        if [[ ! -f "$source_dir/composer.json" ]]; then
            error "composer.json tidak ditemukan."
            rm -rf "$extract_dir"
            rm -f "$archive"
            return 1
        fi

        if [[ ! -d "$source_dir/public" ]]; then
            error "Folder public Pterodactyl tidak ditemukan."
            rm -rf "$extract_dir"
            rm -f "$archive"
            return 1
        fi

        # ====================================================
        # COPY SOURCE
        # ====================================================

        info "Menempatkan source Pterodactyl..."

        cp -a \
            "$source_dir"/. \
            /var/www/pterodactyl/

        # ====================================================
        # CLEAN
        # ====================================================

        rm -rf "$extract_dir"
        rm -f "$archive"

        # ====================================================
        # FINAL SOURCE CHECK
        # ====================================================

        if [[ ! -f /var/www/pterodactyl/artisan ]]; then
            error "Source Pterodactyl tidak valid."
            error "File artisan tidak ditemukan."
            return 1
        fi

        if [[ ! -f /var/www/pterodactyl/composer.json ]]; then
            error "composer.json tidak ditemukan."
            return 1
        fi

        if [[ ! -d /var/www/pterodactyl/public ]]; then
            error "Folder public tidak ditemukan."
            return 1
        fi

        log "Pterodactyl source berhasil di-download."
    fi

    # ========================================================
    # PANEL DIRECTORY
    # ========================================================

    cd /var/www/pterodactyl

    # ========================================================
    # ENV
    # ========================================================

    if [[ ! -f .env ]]; then

        info "Membuat .env..."

        cp .env.example .env

    else

        log ".env sudah tersedia."

    fi

    # ========================================================
    # DATABASE PASSWORD
    # ========================================================

    local escaped_db_pass

    escaped_db_pass="${db_pass//\'/\'\'}"

    # ========================================================
    # CREATE DATABASE
    # ========================================================

    info "Membuat database MariaDB..."

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
    # DATABASE TEST
    # ========================================================

    info "Memeriksa koneksi database..."

    if ! mysql \
        -h 127.0.0.1 \
        -u pterodactyl \
        "-p${db_pass}" \
        -e "SELECT 1;" \
        panel >/dev/null 2>&1; then

        error "Koneksi database Pterodactyl gagal."
        return 1
    fi

    log "Database connection: OK"

    # ========================================================
    # COMPOSER INSTALL
    # ========================================================

    info "Installing Composer dependencies..."

    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_MEMORY_LIMIT=-1 \
    composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction

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

    # IMPORTANT:
    # Jangan gunakan --redis-password.
    # Versi Pterodactyl yang digunakan tidak menyediakan
    # option tersebut.

    php artisan p:environment:setup \
        --author="$admin_email" \
        --url="https://$domain" \
        --timezone="Asia/Jakarta" \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=127.0.0.1 \
        --redis-port=6379

    # ========================================================
    # MIGRATION
    # ========================================================

    info "Migrating database..."

    php artisan migrate \
        --seed \
        --force

    # ========================================================
    # STORAGE
    # ========================================================

    info "Membuat storage link..."

    php artisan storage:link \
        >/dev/null 2>&1 || true

    # ========================================================
    # PERMISSION
    # ========================================================

    info "Mengatur permission..."

    chown -R www-data:www-data \
        /var/www/pterodactyl

    chmod -R 755 \
        /var/www/pterodactyl

    if [[ -d /var/www/pterodactyl/storage ]]; then
        chmod -R 775 \
            /var/www/pterodactyl/storage
    fi

    if [[ -d /var/www/pterodactyl/bootstrap/cache ]]; then
        chmod -R 775 \
            /var/www/pterodactyl/bootstrap/cache
    fi

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

        fastcgi_pass unix:/run/php/php${php_version}-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX

    # ========================================================
    # ENABLE NGINX SITE
    # ========================================================

    ln -sf \
        /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/sites-enabled/pterodactyl.conf

    rm -f \
        /etc/nginx/sites-enabled/default

    # ========================================================
    # NGINX TEST
    # ========================================================

    info "Memeriksa konfigurasi Nginx..."

    if ! nginx -t; then
        error "Konfigurasi Nginx tidak valid."
        return 1
    fi

    systemctl reload nginx

    # ========================================================
    # SSL
    # ========================================================

    info "Mencoba mengaktifkan SSL..."

    if command_exists certbot; then

        if certbot --nginx \
            -d "$domain" \
            --non-interactive \
            --agree-tos \
            -m "$admin_email" \
            --redirect; then

            log "SSL berhasil dikonfigurasi."

        else

            warn "SSL otomatis belum berhasil."
            warn "Pastikan DNS $domain sudah mengarah ke VPS."

        fi

    else

        warn "Certbot tidak tersedia."

    fi

    # ========================================================
    # QUEUE WORKER
    # ========================================================

    info "Membuat Pterodactyl Queue Worker..."

    cat > /etc/systemd/system/pteroq.service <<'SERVICE'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
Wants=redis-server.service

[Service]
User=www-data
Group=www-data

WorkingDirectory=/var/www/pterodactyl

Restart=always
RestartSec=5

ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
SERVICE

    # ========================================================
    # ENABLE QUEUE
    # ========================================================

    systemctl daemon-reload

    systemctl enable --now pteroq

    if systemctl is-active --quiet pteroq; then
        log "Pterodactyl Queue Worker: OK"
    else
        warn "Pterodactyl Queue Worker belum aktif."
    fi

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

    local failed=0

    if systemctl is-active --quiet nginx; then
        log "Nginx: OK"
    else
        warn "Nginx: FAILED"
        failed=1
    fi

    if systemctl is-active --quiet "php${php_version}-fpm"; then
        log "PHP-FPM: OK"
    else
        warn "PHP-FPM: FAILED"
        failed=1
    fi

    if systemctl is-active --quiet mariadb; then
        log "MariaDB: OK"
    else
        warn "MariaDB: FAILED"
        failed=1
    fi

    if systemctl is-active --quiet redis-server; then
        log "Redis: OK"
    else
        warn "Redis: FAILED"
        failed=1
    fi

    if systemctl is-active --quiet pteroq; then
        log "Pterodactyl Queue: OK"
    else
        warn "Pterodactyl Queue: FAILED"
        failed=1
    fi

    # ========================================================
    # FILE CHECK
    # ========================================================

    if [[ ! -f /var/www/pterodactyl/artisan ]]; then
        error "File artisan tidak ditemukan."
        return 1
    fi

    if [[ ! -f /var/www/pterodactyl/.env ]]; then
        error ".env Pterodactyl tidak ditemukan."
        return 1
    fi

    if [[ ! -f /var/www/pterodactyl/composer.json ]]; then
        error "composer.json tidak ditemukan."
        return 1
    fi

    # ========================================================
    # SUCCESS
    # ========================================================

    echo

    if [[ "$failed" -eq 0 ]]; then

        echo "╭────────────────────────────────────────────────────╮"
        echo "│                                                    │"
        echo "│       PUTZOFFICIAL PANEL INSTALLED                │"
        echo "│                                                    │"
        echo "╰────────────────────────────────────────────────────╯"

    else

        echo "╭────────────────────────────────────────────────────╮"
        echo "│                                                    │"
        echo "│     PANEL INSTALLED - CHECK SERVICES              │"
        echo "│                                                    │"
        echo "╰────────────────────────────────────────────────────╯"

    fi

    echo

    info "Pterodactyl : ${tag:-installed}"
    info "Panel URL   : https://$domain"
    info "Database    : panel"
    info "DB User     : pterodactyl"
    info "PHP         : ${php_version}"
    info "Redis       : active"
    info "Queue       : active"
    info "Scheduler   : active"

    echo

    echo "╭────────────────────────────────────────────────────╮"
    echo "│                 ADMIN ACCOUNT                     │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    info "Buat akun administrator dengan:"
    echo
    echo "  cd /var/www/pterodactyl"
    echo "  php artisan p:user:make"
    echo

    # ========================================================
    # CLEANUP
    # ========================================================

    rm -rf "$extract_dir" 2>/dev/null || true
    rm -f "$archive" 2>/dev/null || true

    return 0
}

# ============================================================
# START
# ============================================================

install_panel
