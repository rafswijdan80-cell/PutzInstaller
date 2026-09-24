#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"


# ============================================================
# PTERODACTYL PANEL INSTALLER
# ============================================================

install_panel() {

    info "Memulai instalasi Pterodactyl Panel..."


    # ========================================================
    # ROOT CHECK
    # ========================================================

    if [[ "${EUID}" -ne 0 ]]; then
        error "Installer Panel harus dijalankan sebagai root."
        return 1
    fi


    # ========================================================
    # VARIABLES
    # ========================================================

    local domain=""
    local db_pass=""
    local admin_email=""
    local tag=""
    local panel_url=""
    local php_version="8.3"

    local archive="/tmp/pterodactyl.tar.gz"
    local extract_dir="/tmp/putzofficial-pterodactyl"


    # ========================================================
    # USER INPUT
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

    admin_email="$(ask_required \
        'Email admin Panel')"

    echo


    # ========================================================
    # VALIDATE DOMAIN
    # ========================================================

    if [[ ! "$domain" =~ ^[A-Za-z0-9.-]+$ ]]; then
        error "Format domain tidak valid: $domain"
        return 1
    fi


    if [[ "$domain" == .* || "$domain" == *..* ]]; then
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

    apt-get update -y


    # ========================================================
    # DEPENDENCIES
    # ========================================================

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

        warn "PHP ${php_version} belum tersedia di repository saat ini."
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

    info "Menginstall PHP ${php_version}..."

    apt_install \
        "php${php_version}" \
        "php${php_version}-cli" \
        "php${php_version}-fpm" \
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
    # PHP DEFAULT
    # ========================================================

    if command_exists update-alternatives; then

        update-alternatives \
            --set php \
            "/usr/bin/php${php_version}" \
            >/dev/null 2>&1 || true

    fi


    # ========================================================
    # PHP-FPM SERVICE
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
            --retry 3 \
            --retry-delay 2 \
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
                --retry 3 \
                --retry-delay 2 \
                --connect-timeout 20 \
                --max-time 60 \
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


        # ====================================================
        # OFFICIAL RELEASE
        # ====================================================

        panel_url="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"


        info "Release terbaru: $tag"
        info "Downloading: panel.tar.gz"


        rm -f "$archive"


        # ====================================================
        # DOWNLOAD
        # ====================================================

        curl -fL \
            --retry 5 \
            --retry-delay 2 \
            --connect-timeout 20 \
            --max-time 600 \
            "$panel_url" \
            -o "$archive"


        # ====================================================
        # ARCHIVE CHECK
        # ========================================================

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
        # TEMP EXTRACTION
        # ====================================================

        rm -rf "$extract_dir"

        mkdir -p "$extract_dir"


        info "Extracting Pterodactyl..."


        tar -xzf \
            "$archive" \
            -C "$extract_dir"


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
            error "Archive Pterodactyl tidak memiliki struktur source yang valid."

            rm -rf "$extract_dir"

            return 1

        fi


        # ====================================================
        # DETERMINE SOURCE DIRECTORY
        # ====================================================

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


        # ====================================================
        # CLEAN TEMP
        # ====================================================

        rm -rf "$extract_dir"


        # ====================================================
        # FINAL SOURCE CHECK
        # ====================================================

        if [[ ! -f /var/www/pterodactyl/artisan ]]; then

            error "Source Pterodactyl tidak valid."
            error "File /var/www/pterodactyl/artisan tidak ditemukan."

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
    # DATABASE
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
    # COMPOSER INSTALL
    # ========================================================

    info "Installing Composer dependencies..."


    COMPOSER_ALLOW_SUPERUSER=1 \
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
    # DATABASE ENVIRONMENT
    # ========================================================

    info "Configuring database..."


    php artisan p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database=panel \
        --username=pterodactyl \
        --password="$db_pass"


    # ========================================================
    # APPLICATION ENVIRONMENT
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
    # NGINX CONFIG
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
    # ENABLE NGINX
    # ========================================================

    ln -sf \
        /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/sites-enabled/pterodactyl.conf


    # Remove default Nginx website

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


    # ========================================================
    # QUEUE CHECK
    # ========================================================

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
    # FINAL SERVICE CHECK
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
    # CREATE ADMIN
    # ========================================================

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                ADMIN ACCOUNT                      │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    info "Panel sudah terinstall."
    info "Buat akun administrator dengan perintah berikut:"
    echo

    echo "  cd /var/www/pterodactyl"
    echo "  php artisan p:user:make"

    echo


    # ========================================================
    # FINAL RESULT
    # ========================================================

    if [[ "$failed" -eq 0 ]]; then

        echo
        echo "╭────────────────────────────────────────────────────╮"
        echo "│                                                    │"
        echo "│       PUTZOFFICIAL PANEL INSTALLED                │"
        echo "│                                                    │"
        echo "╰────────────────────────────────────────────────────╯"
        echo

        info "Pterodactyl : $tag"
        info "Panel URL   : https://$domain"
        info "Database    : panel"
        info "DB User     : pterodactyl"
        info "PHP         : ${php_version}"
        info "Redis       : active"
        info "Queue       : active"
        info "Scheduler   : active"

        echo

    else

        warn "Panel selesai dipasang tetapi ada service yang perlu diperiksa."

    fi


    # ========================================================
    # CLEANUP
    # ========================================================

    rm -rf "$extract_dir" 2>/dev/null || true
    rm -f "$archive" 2>/dev/null || true


    echo

}


# ============================================================
# START
# ============================================================

install_panel
