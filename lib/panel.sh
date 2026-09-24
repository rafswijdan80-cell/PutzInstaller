#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

# ============================================================
# PTERODACTYL PANEL INSTALLER
# PutzOfficial Installer
#
# PHP 8.3
# MariaDB
# Redis
# Nginx
# Composer
#
# IMPORTANT:
# - iconv TIDAK dijadikan requirement
# - Composer menggunakan --ignore-platform-req=ext-iconv
# - Admin account dibuat otomatis dari input installer
# ============================================================

install_panel() {

    # ========================================================
    # ROOT CHECK
    # ========================================================

    if [[ "${EUID}" -ne 0 ]]; then
        error "Installer Panel harus dijalankan sebagai root."
        return 1
    fi

    info "Memulai instalasi Pterodactyl Panel..."

    # ========================================================
    # VARIABLES
    # ========================================================

    local php_version="8.3"

    local domain=""
    local db_pass=""

    local admin_email=""
    local admin_username=""
    local admin_name=""
    local admin_first_name=""
    local admin_last_name=""
    local admin_password=""

    local timezone="Asia/Jakarta"

    local tag=""
    local panel_url=""

    local archive="/tmp/pterodactyl.tar.gz"
    local extract_dir="/tmp/putzofficial-pterodactyl"

    local failed=0

    # ========================================================
    # INPUT
    # ========================================================

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│             PTERODACTYL CONFIGURATION              │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    domain="$(ask_required \
        'Domain Panel, contoh panel.example.com')"

    db_pass="$(ask_required \
        'Password database MariaDB')"

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│              ADMIN ACCOUNT CONFIG                  │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    admin_email="$(ask_required \
        'Email administrator')"

    admin_username="$(ask_required \
        'Username administrator')"

    admin_name="$(ask_required \
        'Nama lengkap administrator')"

    admin_first_name="$(ask_required \
        'Nama depan administrator')"

    admin_last_name="$(ask_required \
        'Nama belakang administrator')"

    admin_password="$(ask_required \
        'Password administrator')"

    echo
    info "Timezone default: ${timezone}"
    echo

    # ========================================================
    # VALIDATE DOMAIN
    # ========================================================

    if [[ ! "$domain" =~ ^[A-Za-z0-9.-]+$ ]]; then
        error "Format domain tidak valid: $domain"
        return 1
    fi

    if [[ "$domain" == .* ||
          "$domain" == *..* ||
          "$domain" == -* ||
          "$domain" == *- ]]; then

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
    # VALIDATE USERNAME
    # ========================================================

    if [[ ! "$admin_username" =~ ^[A-Za-z0-9._-]+$ ]]; then
        error "Username hanya boleh mengandung huruf, angka, titik, underscore, dan minus."
        return 1
    fi

    # ========================================================
    # VALIDATE PASSWORD
    # ========================================================

    if [[ ${#admin_password} -lt 8 ]]; then
        error "Password administrator minimal 8 karakter."
        return 1
    fi

    if [[ ${#db_pass} -lt 8 ]]; then
        error "Password database minimal 8 karakter."
        return 1
    fi

    # ========================================================
    # PACKAGE UPDATE
    # ========================================================

    info "Mengupdate package repository..."

    apt-get update -y

    # ========================================================
    # BASE DEPENDENCIES
    # ========================================================

    info "Menginstall dependency dasar..."

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
        software-properties-common \
        apt-transport-https \
        lsb-release \
        gnupg \
        certbot \
        python3-certbot-nginx

    # ========================================================
    # PHP REPOSITORY
    # ========================================================

    info "Memeriksa PHP ${php_version}..."

    if ! apt-cache show "php${php_version}" >/dev/null 2>&1; then

        warn "PHP ${php_version} belum tersedia."
        info "Menambahkan repository PHP..."

        apt_install \
            ca-certificates \
            lsb-release \
            apt-transport-https \
            software-properties-common

        if ! command_exists add-apt-repository; then
            apt_install software-properties-common
        fi

        add-apt-repository -y ppa:ondrej/php

        apt-get update -y
    fi

    # ========================================================
    # PHP PACKAGES
    # ========================================================
    #
    # iconv sengaja TIDAK dicek.
    #
    # ext-iconv merupakan dependency Composer pada beberapa
    # package, tetapi kita akan mengabaikannya melalui:
    #
    # --ignore-platform-req=ext-iconv
    #
    # ========================================================

    info "Menginstall PHP ${php_version}..."

    apt_install \
        "php${php_version}" \
        "php${php_version}-cli" \
        "php${php_version}-fpm" \
        "php${php_version}-common" \
        "php${php_version}-gd" \
        "php${php_version}-mysql" \
        "php${php_version}-mbstring" \
        "php${php_version}-bcmath" \
        "php${php_version}-xml" \
        "php${php_version}-curl" \
        "php${php_version}-zip" \
        "php${php_version}-tokenizer" \
        "php${php_version}-opcache"

    # ========================================================
    # CLEAN DUPLICATE PDO CONFIG
    # ========================================================

    info "Memeriksa konfigurasi PHP..."

    local cli_conf="/etc/php/${php_version}/cli/conf.d"

    if [[ -d "$cli_conf" ]]; then

        local pdo_files=()

        while IFS= read -r file; do
            pdo_files+=("$file")
        done < <(
            grep -rilE '^[[:space:]]*extension[[:space:]]*=[[:space:]]*pdo(\.so)?[[:space:]]*$' \
                "$cli_conf" \
                2>/dev/null || true
        )

        if [[ "${#pdo_files[@]}" -gt 1 ]]; then

            warn "Ditemukan konfigurasi PDO ganda."

            local keep_pdo=""
            local file=""

            for file in "${pdo_files[@]}"; do

                if [[ "$file" == *"/10-pdo.ini" ]]; then
                    keep_pdo="$file"
                    break
                fi

            done

            if [[ -z "$keep_pdo" ]]; then
                keep_pdo="${pdo_files[0]}"
            fi

            for file in "${pdo_files[@]}"; do

                if [[ "$file" != "$keep_pdo" ]]; then
                    rm -f "$file"
                fi

            done

            log "Konfigurasi PDO duplikat CLI dibersihkan."
        fi
    fi

    # ========================================================
    # PHP ALTERNATIVE
    # ========================================================

    if command_exists update-alternatives; then

        update-alternatives \
            --set php \
            "/usr/bin/php${php_version}" \
            >/dev/null 2>&1 || true

    fi

    # ========================================================
    # PHP CHECK
    # ========================================================

    info "Memeriksa PHP..."

    if ! php -r 'exit(extension_loaded("PDO") ? 0 : 1);'; then
        error "PHP PDO belum aktif."
        return 1
    fi

    echo "PDO:OK"

    if ! php -r 'exit(extension_loaded("pdo_mysql") ? 0 : 1);'; then
        error "PHP pdo_mysql belum aktif."
        return 1
    fi

    echo "pdo_mysql:OK"

    info "Memeriksa PHP Phar..."

    if ! php -r 'exit(extension_loaded("Phar") ? 0 : 1);'; then
        error "PHP Phar belum aktif."
        return 1
    fi

    echo "Phar:OK"

    if ! php -r 'exit(extension_loaded("posix") ? 0 : 1);'; then
        error "PHP posix belum aktif."
        return 1
    fi

    echo "posix:OK"

    if ! php -r 'exit(extension_loaded("tokenizer") ? 0 : 1);'; then
        error "PHP tokenizer belum aktif."
        return 1
    fi

    echo "tokenizer:OK"

    if ! php -r 'exit(extension_loaded("fileinfo") ? 0 : 1);'; then
        error "PHP fileinfo belum aktif."
        return 1
    fi

    echo "fileinfo:OK"

    # ========================================================
    # ICONV
    # ========================================================
    #
    # TIDAK ERROR.
    #
    # iconv boleh MISSING.
    #
    # ========================================================

    if php -r 'exit(extension_loaded("iconv") ? 0 : 1);'; then
        echo "iconv:OK"
    else
        warn "PHP iconv tidak aktif. Installer akan menggunakan Composer ignore-platform-req=ext-iconv."
    fi

    # ========================================================
    # SERVICE
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

    if command_exists composer; then

        log "Composer sudah tersedia."

    else

        info "Menginstall Composer..."

        rm -f /tmp/composer-setup.php

        curl -fsSL \
            --retry 5 \
            --retry-delay 3 \
            --connect-timeout 20 \
            --max-time 120 \
            https://getcomposer.org/installer \
            -o /tmp/composer-setup.php

        php /tmp/composer-setup.php \
            --install-dir=/usr/local/bin \
            --filename=composer

        rm -f /tmp/composer-setup.php

    fi

    # ========================================================
    # COMPOSER CHECK
    # ========================================================

    if ! command_exists composer; then
        error "Composer tidak dapat dijalankan."
        return 1
    fi

    info "Memeriksa Composer..."

    if ! composer --version; then
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

    if [[ -f /var/www/pterodactyl/artisan ]]; then

        warn "Pterodactyl Panel sudah ditemukan."
        info "Source download dilewati."

    else

        # ====================================================
        # CLEAN BROKEN INSTALLATION
        # ====================================================

        if [[ -d /var/www/pterodactyl ]]; then

            warn "Folder Pterodactyl tidak lengkap."
            info "Membersihkan instalasi gagal sebelumnya..."

            rm -rf /var/www/pterodactyl
        fi

        mkdir -p /var/www/pterodactyl

        # ====================================================
        # GET LATEST RELEASE
        # ====================================================

        info "Mengambil release Pterodactyl..."

        tag="$(
            curl -fsSL \
                --retry 5 \
                --retry-delay 2 \
                --connect-timeout 20 \
                --max-time 120 \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                https://api.github.com/repos/pterodactyl/panel/releases/latest |
            sed -n 's/.*"tag_name": "\(.*\)",/\1/p' |
            head -n 1
        )"

        if [[ -z "$tag" ]]; then
            error "Tidak dapat mendapatkan release Pterodactyl dari GitHub."
            return 1
        fi

        panel_url="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"

        info "Release terbaru: $tag"
        info "Downloading panel.tar.gz..."

        rm -f "$archive"

        curl -fL \
            --retry 5 \
            --retry-delay 3 \
            --connect-timeout 20 \
            --max-time 600 \
            "$panel_url" \
            -o "$archive"

        if [[ ! -s "$archive" ]]; then
            error "File panel.tar.gz kosong atau gagal didownload."
            return 1
        fi

        info "Memeriksa archive Pterodactyl..."

        if ! tar -tzf "$archive" >/dev/null 2>&1; then
            error "Archive Pterodactyl rusak atau bukan tar.gz yang valid."
            return 1
        fi

        # ====================================================
        # EXTRACTION
        # ====================================================

        rm -rf "$extract_dir"
        mkdir -p "$extract_dir"

        info "Extracting Pterodactyl..."

        tar -xzf "$archive" -C "$extract_dir"

        rm -f "$archive"

        # ====================================================
        # FIND ARTISAN
        # ====================================================

        local artisan_file=""
        local source_dir=""

        artisan_file="$(
            find "$extract_dir" \
                -type f \
                -name artisan \
                -print \
                -quit
        )"

        if [[ -z "$artisan_file" ]]; then

            error "File artisan tidak ditemukan setelah extraction."

            rm -rf "$extract_dir"

            return 1
        fi

        source_dir="$(dirname "$artisan_file")"

        if [[ ! -f "$source_dir/composer.json" ]]; then

            error "composer.json tidak ditemukan bersama artisan."

            rm -rf "$extract_dir"

            return 1
        fi

        if [[ ! -d "$source_dir/public" ]]; then

            error "Folder public Pterodactyl tidak ditemukan."

            rm -rf "$extract_dir"

            return 1
        fi

        # ====================================================
        # COPY SOURCE
        # ====================================================

        info "Menempatkan source Pterodactyl..."

        cp -a \
            "$source_dir"/. \
            /var/www/pterodactyl/

        rm -rf "$extract_dir"

        # ====================================================
        # SOURCE CHECK
        # ====================================================

        if [[ ! -f /var/www/pterodactyl/artisan ]]; then
            error "Source Pterodactyl tidak valid."
            return 1
        fi

        if [[ ! -f /var/www/pterodactyl/composer.json ]]; then
            error "composer.json Pterodactyl tidak ditemukan."
            return 1
        fi

        if [[ ! -d /var/www/pterodactyl/public ]]; then
            error "Folder public Pterodactyl tidak ditemukan."
            return 1
        fi

        log "Pterodactyl source berhasil di-download."
    fi

    # ========================================================
    # PANEL DIRECTORY
    # ========================================================

    cd /var/www/pterodactyl

    # ========================================================
    # ENVIRONMENT
    # ========================================================

    if [[ ! -f .env ]]; then

        info "Membuat .env..."

        if [[ ! -f .env.example ]]; then
            error ".env.example tidak ditemukan."
            return 1
        fi

        cp .env.example .env

    else

        log ".env sudah tersedia."
    fi

    # ========================================================
    # DATABASE PASSWORD ESCAPE
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

    log "Koneksi database: OK"

    # ========================================================
    # COMPOSER DEPENDENCIES
    # ========================================================

    info "Installing Composer dependencies..."

    #
    # iconv sengaja di-ignore.
    #
    # JANGAN menggunakan composer update.
    # Pterodactyl harus menggunakan composer.lock.
    #

    if ! COMPOSER_ALLOW_SUPERUSER=1 \
        composer install \
            --no-dev \
            --optimize-autoloader \
            --no-interaction \
            --ignore-platform-req=ext-iconv; then

        error "Composer dependencies gagal diinstall."

        error "Periksa log:"
        error "/var/log/putzofficial-installer/install.log"

        return 1
    fi

    log "Composer dependencies: OK"

    # ========================================================
    # APPLICATION KEY
    # ========================================================

    info "Generating application key..."

    if ! php artisan key:generate --force; then
        error "Gagal membuat application key."
        return 1
    fi

    # ========================================================
    # DATABASE ENVIRONMENT
    # ========================================================

    info "Configuring database..."

    if ! php artisan p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database=panel \
        --username=pterodactyl \
        --password="$db_pass"; then

        error "Konfigurasi database Pterodactyl gagal."
        return 1
    fi

    # ========================================================
    # APPLICATION ENVIRONMENT
    # ========================================================

    info "Configuring application..."

    if ! php artisan p:environment:setup \
        --author="$admin_email" \
        --url="https://$domain" \
        --timezone="$timezone" \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=127.0.0.1 \
        --redis-port=6379; then

        error "Konfigurasi application environment gagal."
        return 1
    fi

    # ========================================================
    # DATABASE MIGRATION
    # ========================================================

    info "Migrating database..."

    if ! php artisan migrate \
        --seed \
        --force; then

        error "Database migration gagal."
        return 1
    fi

    # ========================================================
    # CREATE ADMIN ACCOUNT
    # ========================================================

    info "Membuat administrator..."

    #
    # Pterodactyl menyediakan command p:user:make.
    #
    # Kita menggunakan input otomatis melalui stdin.
    #

    if ! php artisan p:user:make \
        --email="$admin_email" \
        --username="$admin_username" \
        --name-first="$admin_first_name" \
        --name-last="$admin_last_name" \
        --password="$admin_password" \
        --admin=1; then

        warn "Pembuatan administrator otomatis gagal."
        warn "Coba jalankan manual:"
        echo
        echo "  cd /var/www/pterodactyl"
        echo "  php artisan p:user:make"
        echo

    else

        log "Administrator berhasil dibuat."
    fi

    # ========================================================
    # STORAGE LINK
    # ========================================================

    info "Membuat storage link..."

    php artisan storage:link \
        >/dev/null 2>&1 || true

    # ========================================================
    # PERMISSIONS
    # ========================================================

    info "Mengatur permission..."

    chown -R www-data:www-data \
        /var/www/pterodactyl

    find /var/www/pterodactyl \
        -type d \
        -exec chmod 755 {} \;

    find /var/www/pterodactyl \
        -type f \
        -exec chmod 644 {} \;

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

        warn "Certbot tidak tersedia. SSL dilewati."

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
        failed=1
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
    # FINAL SERVICE CHECK
    # ========================================================

    info "Melakukan pengecekan akhir..."

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
    # FINAL FILE CHECK
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
        error "composer.json Pterodactyl tidak ditemukan."
        return 1
    fi

    # ========================================================
    # CLEANUP
    # ========================================================

    rm -rf "$extract_dir" 2>/dev/null || true
    rm -f "$archive" 2>/dev/null || true

    # ========================================================
    # FINAL RESULT
    # ========================================================

    echo

    if [[ "$failed" -eq 0 ]]; then

        echo "╭────────────────────────────────────────────────────╮"
        echo "│                                                    │"
        echo "│       PUTZOFFICIAL PANEL INSTALLED                │"
        echo "│                                                    │"
        echo "╰────────────────────────────────────────────────────╯"
        echo

        info "Pterodactyl : ${tag:-existing}"
        info "Panel URL   : https://$domain"
        info "Database    : panel"
        info "DB User     : pterodactyl"
        info "PHP         : ${php_version}"
        info "Timezone    : ${timezone}"
        info "Redis       : active"
        info "Queue       : active"
        info "Scheduler   : active"

        echo
        info "Administrator:"
        info "Email       : $admin_email"
        info "Username    : $admin_username"
        info "Name        : $admin_name"

        echo
        log "Instalasi Pterodactyl selesai."

    else

        warn "Panel terpasang tetapi ada service yang perlu diperiksa."

    fi

    echo
}

# ============================================================
# START
# ============================================================

install_panel
