#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"


# ============================================================
# PTERODACTYL PANEL INSTALLER
# PUTZOFFICIAL INSTALLER
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

    local archive="/tmp/pterodactyl-panel.tar.gz"
    local extract_dir="/tmp/putzofficial-pterodactyl"

    local panel_dir="/var/www/pterodactyl"

    local failed=0


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
    # VALIDATE DATABASE PASSWORD
    # ========================================================

    if [[ -z "$db_pass" ]]; then
        error "Password database tidak boleh kosong."
        return 1
    fi


    # ========================================================
    # PACKAGE UPDATE
    # ========================================================

    info "Mengupdate package repository..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y


    # ========================================================
    # BASE DEPENDENCIES
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

        warn "PHP ${php_version} belum tersedia di repository."

        info "Menambahkan repository PHP Ondrej..."

        if ! command_exists add-apt-repository; then
            apt_install software-properties-common
        fi

        add-apt-repository -y ppa:ondrej/php

        apt-get update -y

    fi


    # ========================================================
    # PHP PACKAGES
    # ========================================================

    info "Menginstall PHP ${php_version} dan extension..."

    apt_install \
        "php${php_version}" \
        "php${php_version}-cli" \
        "php${php_version}-common" \
        "php${php_version}-fpm" \
        "php${php_version}-gd" \
        "php${php_version}-mysql" \
        "php${php_version}-mbstring" \
        "php${php_version}-bcmath" \
        "php${php_version}-xml" \
        "php${php_version}-curl" \
        "php${php_version}-zip" \
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
    # PHP CONFIGURATION CLEANUP
    # ========================================================

    info "Memeriksa konfigurasi PHP..."


    # --------------------------------------------------------
    # IMPORTANT
    # --------------------------------------------------------
    # Jangan membuat file PDO manual jika sudah disediakan
    # oleh paket PHP.
    #
    # Ini mencegah:
    #
    # Module "PDO" is already loaded
    #
    # Tidak menghapus konfigurasi bawaan PHP.
    # --------------------------------------------------------


    # Remove only duplicate custom PDO configuration
    # if installer sebelumnya membuatnya.
    #
    # We only remove manually duplicated 20-pdo.ini when
    # 10-pdo.ini already exists.
    if [[ \
        -f "/etc/php/${php_version}/cli/conf.d/10-pdo.ini" && \
        -f "/etc/php/${php_version}/cli/conf.d/20-pdo.ini" \
    ]]; then

        warn "Ditemukan konfigurasi PDO ganda."

        rm -f \
            "/etc/php/${php_version}/cli/conf.d/20-pdo.ini"

        log "Konfigurasi PDO duplikat CLI dibersihkan."

    fi


    # ========================================================
    # PHP MODULE CHECK
    # ========================================================

    info "Memeriksa PHP..."

    local php_check_output=""

    php_check_output="$(
        php -r '
        $required = [
            "PDO",
            "pdo_mysql",
            "Phar",
            "posix",
            "tokenizer",
            "fileinfo",
            "iconv"
        ];

        $failed = false;

        foreach ($required as $ext) {
            echo $ext . ":" . (extension_loaded($ext) ? "OK" : "MISSING") . PHP_EOL;

            if (!extension_loaded($ext)) {
                $failed = true;
            }
        }

        exit($failed ? 1 : 0);
        ' 2>&1
    )" || true


    echo "$php_check_output"


    # ========================================================
    # PHP WARNING DETECTION
    # ========================================================

    if echo "$php_check_output" | grep -q 'already loaded'; then

        warn "PHP memiliki konfigurasi extension yang terduplikasi."

        warn "Periksa:"
        warn "/etc/php/${php_version}/cli/conf.d/"

    fi


    # ========================================================
    # INDIVIDUAL PHP CHECK
    # ========================================================

    local ext
    local ext_status

    for ext in PDO pdo_mysql Phar posix tokenizer fileinfo iconv; do

        if php -r "exit(extension_loaded('$ext') ? 0 : 1);" \
            >/dev/null 2>&1; then

            log "PHP ${ext}: OK"

        else

            error "PHP ${ext} belum aktif."

            failed=1

        fi

    done


    if [[ "$failed" -ne 0 ]]; then

        error "PHP extension yang dibutuhkan belum lengkap."
        error "Perbaiki PHP terlebih dahulu sebelum melanjutkan."

        return 1

    fi


    # ========================================================
    # PHAR CHECK
    # ========================================================

    info "Memeriksa PHP Phar..."

    if php -r 'exit(extension_loaded("Phar") ? 0 : 1);' \
        >/dev/null 2>&1; then

        log "PHP Phar: OK"

    else

        error "PHP Phar belum aktif."

        return 1

    fi


    # ========================================================
    # PHP CLI VERSION
    # ========================================================

    local current_php

    current_php="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"

    if [[ -z "$current_php" ]]; then

        error "PHP CLI tidak dapat dijalankan."

        return 1

    fi

    log "PHP CLI: ${current_php}"


    # ========================================================
    # SERVICE
    # ========================================================

    info "Mengaktifkan service..."

    systemctl enable --now mariadb
    systemctl enable --now redis-server
    systemctl enable --now "php${php_version}-fpm"
    systemctl enable --now nginx


    # ========================================================
    # VERIFY SERVICES
    # ========================================================

    if ! systemctl is-active --quiet mariadb; then

        error "MariaDB gagal dijalankan."

        systemctl status mariadb \
            --no-pager \
            -l \
            || true

        return 1

    fi


    if ! systemctl is-active --quiet redis-server; then

        error "Redis gagal dijalankan."

        systemctl status redis-server \
            --no-pager \
            -l \
            || true

        return 1

    fi


    if ! systemctl is-active --quiet "php${php_version}-fpm"; then

        error "PHP-FPM gagal dijalankan."

        systemctl status "php${php_version}-fpm" \
            --no-pager \
            -l \
            || true

        return 1

    fi


    if ! systemctl is-active --quiet nginx; then

        error "Nginx gagal dijalankan."

        systemctl status nginx \
            --no-pager \
            -l \
            || true

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
            --max-time 180 \
            https://getcomposer.org/installer \
            -o /tmp/composer-setup.php


        if [[ ! -s /tmp/composer-setup.php ]]; then

            error "Composer installer gagal didownload."

            return 1

        fi


        php /tmp/composer-setup.php \
            --install-dir=/usr/local/bin \
            --filename=composer


        rm -f /tmp/composer-setup.php

    fi


    # ========================================================
    # COMPOSER CHECK
    # ========================================================

    info "Memeriksa Composer..."

    if ! command_exists composer; then

        error "Composer tidak ditemukan."

        return 1

    fi


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

    if [[ -f "$panel_dir/artisan" ]]; then

        warn "Pterodactyl Panel sudah ditemukan."
        info "Source download dilewati."

    else

        # ====================================================
        # CLEAN BROKEN INSTALLATION
        # ====================================================

        if [[ -d "$panel_dir" ]]; then

            warn "Folder Pterodactyl tidak lengkap."

            info "Membersihkan instalasi gagal sebelumnya..."

            rm -rf "$panel_dir"

        fi


        mkdir -p "$panel_dir"


        # ====================================================
        # GET LATEST RELEASE
        # ====================================================

        info "Mengambil release Pterodactyl..."


        tag="$(
            curl -fsSL \
                --retry 5 \
                --retry-delay 3 \
                --connect-timeout 20 \
                --max-time 90 \
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


        # ====================================================
        # DOWNLOAD
        # ====================================================

        curl -fL \
            --retry 5 \
            --retry-delay 3 \
            --connect-timeout 20 \
            --max-time 900 \
            "$panel_url" \
            -o "$archive"


        if [[ ! -s "$archive" ]]; then

            error "File panel.tar.gz kosong atau gagal didownload."

            return 1

        fi


        # ====================================================
        # VERIFY ARCHIVE
        # ====================================================

        info "Memeriksa archive Pterodactyl..."


        if ! tar -tzf "$archive" >/dev/null 2>&1; then

            error "Archive Pterodactyl rusak."

            rm -f "$archive"

            return 1

        fi


        # ====================================================
        # TEMP EXTRACTION
        # ====================================================

        rm -rf "$extract_dir"

        mkdir -p "$extract_dir"


        info "Extracting Pterodactyl..."


        tar \
            -xzf "$archive" \
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

            error "File artisan tidak ditemukan."

            rm -rf "$extract_dir"

            return 1

        fi


        source_dir="$(dirname "$artisan_file")"


        # ====================================================
        # SOURCE VALIDATION
        # ====================================================

        if [[ ! -f "$source_dir/composer.json" ]]; then

            error "composer.json tidak ditemukan."

            rm -rf "$extract_dir"

            return 1

        fi


        if [[ ! -f "$source_dir/composer.lock" ]]; then

            error "composer.lock tidak ditemukan."

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
            "$panel_dir/"


        # ====================================================
        # CLEAN TEMP
        # ====================================================

        rm -rf "$extract_dir"


        # ====================================================
        # FINAL SOURCE CHECK
        # ====================================================

        if [[ ! -f "$panel_dir/artisan" ]]; then

            error "Source Pterodactyl tidak valid."

            return 1

        fi


        log "Pterodactyl source berhasil didownload."

    fi


    # ========================================================
    # PANEL DIRECTORY
    # ========================================================

    cd "$panel_dir"


    # ========================================================
    # ENVIRONMENT FILE
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
    # DATABASE CONNECTION TEST
    # ========================================================

    info "Memeriksa koneksi database..."


    if ! mysql \
        -h 127.0.0.1 \
        -u pterodactyl \
        "-p${db_pass}" \
        -e "SELECT 1;" \
        panel \
        >/dev/null 2>&1; then

        error "Koneksi database Pterodactyl gagal."

        return 1

    fi


    log "Koneksi database: OK"


    # ========================================================
    # COMPOSER CACHE / TIMEOUT
    # ========================================================

    export COMPOSER_ALLOW_SUPERUSER=1
    export COMPOSER_PROCESS_TIMEOUT=1200


    # ========================================================
    # COMPOSER DEPENDENCIES
    # ========================================================

    info "Installing Composer dependencies..."

    info "Proses ini bisa membutuhkan beberapa menit."


    if ! composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction \
        --prefer-dist; then

        error "Composer dependencies gagal diinstall."

        error "Jangan gunakan composer update."

        error "Periksa extension PHP dengan:"

        echo
        echo "php -m"
        echo

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


    # IMPORTANT:
    #
    # Jangan menggunakan:
    #
    # --redis-password
    #
    # Karena versi Pterodactyl yang digunakan tidak mempunyai
    # option tersebut.
    #

    if ! php artisan p:environment:setup \
        --author="$admin_email" \
        --url="https://$domain" \
        --timezone="Asia/Jakarta" \
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


    log "Database migration: OK"


    # ========================================================
    # STORAGE LINK
    # ========================================================

    info "Membuat storage link..."


    php artisan storage:link \
        >/dev/null 2>&1 \
        || true


    # ========================================================
    # PERMISSIONS
    # ========================================================

    info "Mengatur permission..."


    chown -R www-data:www-data "$panel_dir"


    find "$panel_dir" \
        -type d \
        -exec chmod 755 {} \;


    find "$panel_dir" \
        -type f \
        -exec chmod 644 {} \;


    if [[ -d "$panel_dir/storage" ]]; then

        chmod -R 775 "$panel_dir/storage"

    fi


    if [[ -d "$panel_dir/bootstrap/cache" ]]; then

        chmod -R 775 "$panel_dir/bootstrap/cache"

    fi


    # ========================================================
    # NGINX CONFIGURATION
    # ========================================================

    info "Membuat konfigurasi Nginx..."


    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    listen [::]:80;

    server_name $domain;

    root $panel_dir/public;

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
    # ENABLE SITE
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


    # ========================================================
    # QUEUE CHECK
    # ========================================================

    if systemctl is-active --quiet pteroq; then

        log "Pterodactyl Queue Worker: OK"

    else

        warn "Pterodactyl Queue Worker belum aktif."

        systemctl status pteroq \
            --no-pager \
            -l \
            || true

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


    failed=0


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

    if [[ ! -f "$panel_dir/artisan" ]]; then

        error "File artisan tidak ditemukan."

        return 1

    fi


    if [[ ! -f "$panel_dir/.env" ]]; then

        error ".env Pterodactyl tidak ditemukan."

        return 1

    fi


    if [[ ! -f "$panel_dir/composer.json" ]]; then

        error "composer.json tidak ditemukan."

        return 1

    fi


    if [[ ! -f "$panel_dir/composer.lock" ]]; then

        error "composer.lock tidak ditemukan."

        return 1

    fi


    # ========================================================
    # ADMIN INFORMATION
    # ========================================================

    echo

    echo "╭────────────────────────────────────────────────────╮"
    echo "│                 ADMIN ACCOUNT                     │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    info "Panel sudah berhasil dikonfigurasi."

    info "Buat akun administrator dengan:"

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

        info "Pterodactyl : ${tag:-existing}"
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

        echo

    fi


    # ========================================================
    # CLEANUP
    # ========================================================

    rm -rf "$extract_dir" \
        2>/dev/null \
        || true

    rm -f "$archive" \
        2>/dev/null \
        || true


    echo

    return 0
}


# ============================================================
# START
# ============================================================

install_panel
