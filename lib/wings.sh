#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

# ============================================================
# PUTZOFFICIAL WINGS INSTALLER
# ============================================================
#
# Pterodactyl Wings installer
#
# Fitur:
#   - Ubuntu amd64/x86_64
#   - Docker otomatis
#   - Wings otomatis
#   - DNS validation
#   - Let's Encrypt otomatis
#   - Nginx tetap berjalan
#   - Reverse proxy Node otomatis
#   - Wings config YAML
#   - systemd service
#   - UFW
#   - Backup config
#   - Validasi Wings
#   - Tidak menghapus PHP
#   - Tidak menghapus Nginx
#
# ============================================================

WINGS_BINARY="/usr/local/bin/wings"
WINGS_CONFIG="/etc/pterodactyl/config.yml"
WINGS_SERVICE="/etc/systemd/system/wings.service"

NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"

WINGS_LOG_DIR="/var/log/pterodactyl"

WINGS_VERSION="${WINGS_VERSION:-1.13.3}"

WINGS_DOWNLOAD_URL="https://github.com/pterodactyl/wings/releases/download/v${WINGS_VERSION}/wings_linux_amd64"

PANEL_URL=""
NODE_ID=""
NODE_DOMAIN=""

SSL_CERT=""
SSL_KEY=""

NGINX_NODE_CONFIG=""
NGINX_NODE_LINK=""

CONFIG_TMP=""

# ============================================================
# ERROR HANDLER
# ============================================================

wings_error_handler() {

    local exit_code=$?
    local line_no="${1:-unknown}"

    echo
    echo "================================================"
    echo "              WINGS INSTALLER ERROR"
    echo "================================================"
    echo
    echo "[ERROR] Installer gagal."
    echo "[ERROR] Line: $line_no"
    echo "[ERROR] Exit code: $exit_code"
    echo

    if [[ -n "${CONFIG_TMP:-}" && -f "$CONFIG_TMP" ]]; then
        rm -f "$CONFIG_TMP" || true
    fi

    if command -v systemctl >/dev/null 2>&1; then

        if systemctl is-enabled wings >/dev/null 2>&1; then
            echo "[INFO] Wings service terdeteksi."
            echo
            echo "Log terakhir:"
            journalctl -u wings -n 30 --no-pager 2>/dev/null || true
        fi
    fi

    echo
    echo "Log installer:"
    echo "  /var/log/putzofficial-installer/install.log"
    echo

    exit "$exit_code"
}

trap 'wings_error_handler $LINENO' ERR

# ============================================================
# HELPERS
# ============================================================

wings_fail() {
    error "$*"
    return 1
}

require_root() {

    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        wings_fail "Installer Wings harus dijalankan sebagai root."
    fi
}

require_command() {

    local cmd="$1"

    if ! command_exists "$cmd"; then
        wings_fail "Command '$cmd' tidak ditemukan."
    fi
}

# ============================================================
# ARCHITECTURE
# ============================================================

check_architecture() {

    info "Memeriksa architecture VPS..."

    local arch

    arch="$(uname -m)"

    case "$arch" in

        x86_64|amd64)
            log "Architecture: $arch"
            ;;

        *)
            wings_fail \
                "Architecture '$arch' tidak didukung. Wings installer ini membutuhkan x86_64/amd64."
            ;;

    esac
}

# ============================================================
# DEPENDENCIES
# ============================================================

install_wings_dependencies() {

    info "Memastikan dependency Wings tersedia..."

    apt_install \
        ca-certificates \
        curl \
        openssl \
        jq \
        iproute2 \
        dnsutils \
        ufw \
        nginx \
        certbot \
        python3-certbot-nginx

    log "Dependency Wings: OK"
}

# ============================================================
# DOCKER
# ============================================================

ensure_docker() {

    info "Memeriksa Docker..."

    if command_exists docker; then

        log "Docker binary: tersedia."

        if systemctl is-active --quiet docker; then

            log "Docker service: ACTIVE"

            return 0
        fi

        info "Docker tersedia tetapi belum aktif."

        systemctl enable docker
        systemctl start docker

        sleep 3

        if systemctl is-active --quiet docker; then

            log "Docker service: ACTIVE"

            return 0
        fi

        wings_fail "Docker gagal dijalankan."
    fi

    info "Docker belum tersedia."

    if [[ ! -f "$BASE_DIR/lib/docker.sh" ]]; then
        wings_fail "lib/docker.sh tidak ditemukan."
    fi

    info "Menjalankan installer Docker..."

    bash "$BASE_DIR/lib/docker.sh"

    if ! command_exists docker; then
        wings_fail "Docker gagal diinstall."
    fi

    systemctl enable docker
    systemctl start docker

    sleep 3

    if ! systemctl is-active --quiet docker; then
        wings_fail "Docker tidak aktif."
    fi

    log "Docker: OK"
}

# ============================================================
# WINGS BINARY
# ============================================================

install_wings_binary() {

    info "Memeriksa Pterodactyl Wings..."

    mkdir -p \
        /etc/pterodactyl \
        "$WINGS_LOG_DIR"

    if [[ -x "$WINGS_BINARY" ]]; then

        info "Wings binary sudah tersedia."

        if "$WINGS_BINARY" version >/dev/null 2>&1; then

            log "Wings binary: OK"

            "$WINGS_BINARY" version || true

            return 0
        fi

        warn "Wings binary tidak dapat dijalankan."
        warn "Mengunduh ulang."
    fi

    local tmp_binary

    tmp_binary="/tmp/wings-linux-amd64.$$"

    rm -f "$tmp_binary"

    info "Mengunduh Wings v${WINGS_VERSION}..."

    curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --connect-timeout 15 \
        --max-time 300 \
        "$WINGS_DOWNLOAD_URL" \
        -o "$tmp_binary"

    chmod 0755 "$tmp_binary"

    if ! "$tmp_binary" version >/dev/null 2>&1; then

        rm -f "$tmp_binary"

        wings_fail "Binary Wings yang diunduh tidak valid."
    fi

    install \
        -m 0755 \
        "$tmp_binary" \
        "$WINGS_BINARY"

    rm -f "$tmp_binary"

    log "Wings berhasil diinstall."

    "$WINGS_BINARY" version || true
}

# ============================================================
# PANEL URL
# ============================================================

ask_panel_url() {

    local value=""

    while true; do

        echo
        read -r -p \
            "Panel URL, contoh https://panel.example.com: " value

        value="${value//$'\r'/}"

        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        value="${value%/}"

        if [[ -z "$value" ]]; then
            warn "Panel URL tidak boleh kosong."
            continue
        fi

        if [[ "$value" != http://* &&
              "$value" != https://* ]]; then

            warn "Panel URL harus diawali http:// atau https://."
            continue
        fi

        printf '%s' "$value"

        return 0
    done
}

# ============================================================
# NODE ID
# ============================================================

ask_node_id() {

    local value=""

    while true; do

        echo
        read -r -p "Node ID, contoh 1: " value

        value="${value//$'\r'/}"

        if [[ "$value" =~ ^[0-9]+$ ]] &&
           [[ "$value" -gt 0 ]]; then

            printf '%s' "$value"

            return 0
        fi

        warn "Node ID harus berupa angka lebih dari 0."
    done
}

# ============================================================
# NODE DOMAIN
# ============================================================

ask_node_domain() {

    local value=""

    while true; do

        echo
        read -r -p \
            "Domain Node/FQDN, contoh node.example.com: " value

        value="${value//$'\r'/}"

        value="${value#http://}"
        value="${value#https://}"

        value="${value%%/*}"
        value="${value%%:*}"

        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        if [[ -z "$value" ]]; then
            warn "Domain Node tidak boleh kosong."
            continue
        fi

        if [[ "$value" != *.* ]]; then
            warn "Masukkan domain/FQDN yang valid."
            continue
        fi

        printf '%s' "$value"

        return 0
    done
}

# ============================================================
# PUBLIC IPV4
# ============================================================

get_public_ipv4() {

    local ip=""

    ip="$(
        curl \
            -4 \
            -fsS \
            --connect-timeout 5 \
            --max-time 10 \
            https://api.ipify.org \
            2>/dev/null || true
    )"

    printf '%s' "$ip"
}

# ============================================================
# DNS
# ============================================================

resolve_node_ipv4() {

    local result=""

    result="$(
        getent ahostsv4 "$NODE_DOMAIN" 2>/dev/null |
        awk 'NR==1 {print $1}' ||
        true
    )"

    if [[ -n "$result" ]]; then
        printf '%s' "$result"
        return 0
    fi

    result="$(
        dig +short A "$NODE_DOMAIN" 2>/dev/null |
        grep -E \
            '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' |
        head -n1 ||
        true
    )"

    printf '%s' "$result"
}

check_node_dns() {

    info "Memeriksa DNS Node..."

    local node_ip=""
    local server_ip=""

    node_ip="$(resolve_node_ipv4)"

    if [[ -z "$node_ip" ]]; then

        warn "Domain $NODE_DOMAIN belum dapat di-resolve."

        return 1
    fi

    server_ip="$(get_public_ipv4)"

    if [[ -z "$server_ip" ]]; then

        warn "Public IPv4 VPS tidak dapat diketahui."

        return 1
    fi

    info "DNS Node : $node_ip"
    info "VPS IP   : $server_ip"

    if [[ "$node_ip" != "$server_ip" ]]; then

        warn "DNS Node belum mengarah ke public IP VPS ini."

        return 1
    fi

    log "DNS Node: OK"

    return 0
}

# ============================================================
# NGINX TEST
# ============================================================

test_nginx_config() {

    info "Memeriksa konfigurasi Nginx..."

    if ! nginx -t; then
        wings_fail "Konfigurasi Nginx tidak valid."
    fi

    log "Nginx configuration: OK"
}

# ============================================================
# NGINX NODE HTTP CONFIG
# ============================================================

create_nginx_http_config() {

    info "Membuat konfigurasi HTTP Node..."

    mkdir -p \
        "$NGINX_AVAILABLE" \
        "$NGINX_ENABLED"

    NGINX_NODE_CONFIG="$NGINX_AVAILABLE/$NODE_DOMAIN"

    NGINX_NODE_LINK="$NGINX_ENABLED/$NODE_DOMAIN"

    cat > "$NGINX_NODE_CONFIG" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $NODE_DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}
EOF

    ln -sfn \
        "$NGINX_NODE_CONFIG" \
        "$NGINX_NODE_LINK"

    mkdir -p /var/www/letsencrypt

    chown -R www-data:www-data /var/www/letsencrypt 2>/dev/null || true

    chmod 0755 /var/www/letsencrypt

    test_nginx_config

    systemctl reload nginx

    log "Nginx Node HTTP: OK"
}

# ============================================================
# SSL
# ============================================================

setup_node_ssl() {

    info "Menyiapkan SSL Let's Encrypt otomatis..."

    SSL_CERT="/etc/letsencrypt/live/$NODE_DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$NODE_DOMAIN/privkey.pem"

    mkdir -p /var/www/letsencrypt

    # --------------------------------------------------------
    # Existing certificate
    # --------------------------------------------------------

    if [[ -f "$SSL_CERT" &&
          -f "$SSL_KEY" ]]; then

        log "SSL certificate sudah tersedia."

        return 0
    fi

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    if ! check_node_dns; then

        wings_fail \
            "SSL tidak dapat dibuat karena DNS Node belum mengarah ke VPS."
    fi

    # --------------------------------------------------------
    # Port 80
    # --------------------------------------------------------

    if ! ss -lnt 2>/dev/null |
        grep -Eq '(^|[[:space:]])0\.0\.0\.0:80([[:space:]]|$)|(^|[[:space:]])\[::\]:80([[:space:]]|$)'; then

        warn "Tidak ada service yang listen di port 80."

        systemctl start nginx 2>/dev/null || true
    fi

    # --------------------------------------------------------
    # Nginx configuration
    # --------------------------------------------------------

    create_nginx_http_config

    # --------------------------------------------------------
    # Certbot
    # --------------------------------------------------------

    if ! command_exists certbot; then

        info "Certbot belum tersedia."

        apt_install certbot

    fi

    require_command certbot

    # --------------------------------------------------------
    # Firewall
    # --------------------------------------------------------

    if command_exists ufw; then

        if ufw status 2>/dev/null |
            grep -q "Status: active"; then

            ufw allow 80/tcp >/dev/null || true
            ufw allow 443/tcp >/dev/null || true

        fi
    fi

    # --------------------------------------------------------
    # HTTP test
    # --------------------------------------------------------

    info "Memeriksa akses HTTP Node..."

    local http_code=""

    http_code="$(
        curl \
            -4 \
            -sS \
            --connect-timeout 10 \
            --max-time 15 \
            -o /dev/null \
            -w '%{http_code}' \
            "http://$NODE_DOMAIN/.well-known/acme-challenge/putzofficial-test" \
            2>/dev/null ||
            true
    )"

    if [[ "$http_code" == "000" || -z "$http_code" ]]; then

        warn "HTTP Node belum dapat diakses dari VPS."

        warn "Certbot mungkin gagal jika port 80 diblokir provider/firewall."

    else

        log "HTTP Node response: $http_code"
    fi

    # --------------------------------------------------------
    # Certbot Webroot
    # --------------------------------------------------------

    info "Meminta certificate Let's Encrypt..."

    local certbot_result=0

    certbot certonly \
        --webroot \
        --webroot-path /var/www/letsencrypt \
        --non-interactive \
        --agree-tos \
        --keep-until-expiring \
        --register-unsafely-without-email \
        -d "$NODE_DOMAIN" \
        || certbot_result=$?

    if [[ "$certbot_result" -ne 0 ]]; then

        echo
        warn "Let's Encrypt gagal."
        echo

        echo "Periksa:"
        echo "  DNS : $NODE_DOMAIN"
        echo "  VPS : $(get_public_ipv4)"
        echo "  Port: 80"
        echo
        echo "Test:"
        echo "  dig +short A $NODE_DOMAIN"
        echo "  curl -I http://$NODE_DOMAIN"
        echo

        wings_fail "SSL Node gagal dibuat."
    fi

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    if [[ ! -f "$SSL_CERT" ]]; then
        wings_fail "Certificate tidak ditemukan: $SSL_CERT"
    fi

    if [[ ! -f "$SSL_KEY" ]]; then
        wings_fail "Private key tidak ditemukan: $SSL_KEY"
    fi

    if ! openssl x509 \
        -in "$SSL_CERT" \
        -noout \
        >/dev/null 2>&1; then

        wings_fail "Certificate SSL tidak valid."
    fi

    log "Let's Encrypt SSL: OK"
}

# ============================================================
# NGINX HTTPS CONFIG
# ============================================================

create_nginx_https_config() {

    info "Mengkonfigurasi HTTPS Node..."

    cat > "$NGINX_NODE_CONFIG" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $NODE_DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name $NODE_DOMAIN;

    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8080;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}
EOF

    test_nginx_config

    systemctl reload nginx

    log "Nginx HTTPS Node: OK"
}

# ============================================================
# WINGS CONFIGURATION
# ============================================================
#
# Pterodactyl Panel menghasilkan configuration YAML.
#
# Installer menerima:
#
# END_CONFIG
#
# Tidak memaksa JSON.
#
# SSL path akan diganti otomatis.
# ============================================================

read_wings_configuration() {

    CONFIG_TMP="/tmp/putzofficial-wings-config.$$.yml"

    rm -f "$CONFIG_TMP"

    echo
    echo "================================================"
    echo "          WINGS CONFIGURATION"
    echo "================================================"
    echo
    echo "Buka:"
    echo
    echo "Admin Panel"
    echo "  -> Nodes"
    echo "  -> pilih Node"
    echo "  -> Configuration"
    echo
    echo "Copy SELURUH konfigurasi Wings."
    echo
    echo "Contoh struktur:"
    echo
    echo "debug: false"
    echo "uuid: ..."
    echo "token_id: ..."
    echo "token: ..."
    echo "api:"
    echo "  host: 0.0.0.0"
    echo "  port: 8080"
    echo "  ssl:"
    echo "    enabled: true"
    echo "    cert: ..."
    echo "    key: ..."
    echo "system:"
    echo "  data: /var/lib/pterodactyl/volumes"
    echo "  sftp:"
    echo "    bind_port: 2022"
    echo "remote: 'https://panel.example.com'"
    echo
    echo "Paste semuanya."
    echo
    echo "Setelah selesai ketik:"
    echo
    echo "END_CONFIG"
    echo
    echo "================================================"
    echo

    local line=""

    while IFS= read -r line; do

        line="${line//$'\r'/}"

        if [[ "$line" == "END_CONFIG" ]]; then
            break
        fi

        printf '%s\n' "$line" >> "$CONFIG_TMP"

    done

    if [[ ! -s "$CONFIG_TMP" ]]; then

        rm -f "$CONFIG_TMP"

        wings_fail "Konfigurasi Wings kosong."
    fi

    info "Memeriksa struktur konfigurasi..."

    # --------------------------------------------------------
    # Required fields
    # --------------------------------------------------------

    if ! grep -Eq '^uuid:[[:space:]]*[^[:space:]]+' "$CONFIG_TMP"; then
        rm -f "$CONFIG_TMP"
        wings_fail "Field uuid tidak ditemukan."
    fi

    if ! grep -Eq '^token_id:[[:space:]]*[^[:space:]]+' "$CONFIG_TMP"; then
        rm -f "$CONFIG_TMP"
        wings_fail "Field token_id tidak ditemukan."
    fi

    if ! grep -Eq '^token:[[:space:]]*[^[:space:]]+' "$CONFIG_TMP"; then
        rm -f "$CONFIG_TMP"
        wings_fail "Field token tidak ditemukan."
    fi

    if ! grep -Eq '^api:' "$CONFIG_TMP"; then
        rm -f "$CONFIG_TMP"
        wings_fail "Section api tidak ditemukan."
    fi

    if ! grep -Eq '^remote:' "$CONFIG_TMP"; then
        rm -f "$CONFIG_TMP"
        wings_fail "Field remote tidak ditemukan."
    fi

    # --------------------------------------------------------
    # Normalize remote
    # --------------------------------------------------------

    local remote=""

    remote="$(
        awk -F': ' '
            $1=="remote" {
                print $2
                exit
            }
        ' "$CONFIG_TMP" |
        sed "s/^['\"]//; s/['\"]$//"
    )"

    remote="${remote%/}"

    local panel_normalized="${PANEL_URL%/}"

    if [[ "$remote" != "$panel_normalized" ]]; then

        echo
        warn "Remote pada konfigurasi berbeda dengan Panel URL."
        echo
        echo "Panel URL : $panel_normalized"
        echo "Config    : $remote"
        echo

        read -r -p \
            "Tetap gunakan konfigurasi ini? [y/N]: " confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then

            rm -f "$CONFIG_TMP"

            wings_fail \
                "Instalasi dibatalkan karena remote berbeda."
        fi

    else

        log "Panel remote: OK"
    fi

    # --------------------------------------------------------
    # API host
    # --------------------------------------------------------

    local api_host=""

    api_host="$(
        awk '
            /^api:/ {
                inside=1
                next
            }

            inside && /^  host:/ {
                sub(/^  host:[[:space:]]*/, "")
                print
                exit
            }

            inside && /^[^[:space:]]/ {
                exit
            }
        ' "$CONFIG_TMP" |
        sed "s/^['\"]//; s/['\"]$//"
    )"

    if [[ -z "$api_host" ]]; then

        rm -f "$CONFIG_TMP"

        wings_fail "api.host tidak ditemukan."
    fi

    # --------------------------------------------------------
    # API port
    # --------------------------------------------------------

    local api_port=""

    api_port="$(
        awk '
            /^api:/ {
                inside=1
                next
            }

            inside && /^  port:/ {
                sub(/^  port:[[:space:]]*/, "")
                print
                exit
            }

            inside && /^[^[:space:]]/ {
                exit
            }
        ' "$CONFIG_TMP" |
        sed "s/^['\"]//; s/['\"]$//"
    )"

    if [[ -z "$api_port" ]]; then

        rm -f "$CONFIG_TMP"

        wings_fail "api.port tidak ditemukan."
    fi

    # --------------------------------------------------------
    # Force API host
    # --------------------------------------------------------

    if [[ "$api_host" != "0.0.0.0" ]]; then

        info "Mengubah api.host menjadi 0.0.0.0..."

        sed -i \
            -E \
            's/^([[:space:]]*host:).*/\1 0.0.0.0/' \
            "$CONFIG_TMP"
    fi

    # --------------------------------------------------------
    # Force Wings internal port
    # --------------------------------------------------------

    if [[ "$api_port" != "8080" ]]; then

        warn "api.port saat ini: $api_port"
        info "Mengubah Wings internal port menjadi 8080..."

        sed -i \
            -E \
            's/^([[:space:]]*port:).*/\1 8080/' \
            "$CONFIG_TMP"
    fi

    # --------------------------------------------------------
    # SSL
    # --------------------------------------------------------
    #
    # Karena Nginx menangani SSL publik, Wings cukup listen
    # HTTP pada localhost/public 8080.
    #
    # Tetapi konfigurasi Panel biasanya memiliki SSL enabled.
    #
    # Kita disable SSL internal Wings agar tidak bentrok dengan
    # reverse proxy Nginx.
    #
    # --------------------------------------------------------

    if grep -Eq '^    enabled:[[:space:]]*true' "$CONFIG_TMP"; then

        info "SSL internal Wings terdeteksi."

        info "SSL internal Wings akan dinonaktifkan."
        info "HTTPS publik ditangani Nginx."

        sed -i \
            -E \
            's/^([[:space:]]*enabled:)[[:space:]]*true/\1 false/' \
            "$CONFIG_TMP"

    fi

    # --------------------------------------------------------
    # Remove certificate path is not necessary when disabled.
    # --------------------------------------------------------

    # --------------------------------------------------------
    # SFTP
    # --------------------------------------------------------

    local sftp_port=""

    sftp_port="$(
        awk '
            /^  sftp:/ {
                inside=1
                next
            }

            inside && /^    bind_port:/ {
                sub(/^    bind_port:[[:space:]]*/, "")
                print
                exit
            }

            inside && /^  [^[:space:]]/ {
                exit
            }
        ' "$CONFIG_TMP" |
        sed "s/^['\"]//; s/['\"]$//"
    )"

    if [[ -z "$sftp_port" ]]; then

        warn "system.sftp.bind_port tidak ditemukan."
        warn "SFTP port akan mengikuti konfigurasi Panel."

    fi

    # --------------------------------------------------------
    # Backup existing config
    # --------------------------------------------------------

    if [[ -f "$WINGS_CONFIG" ]]; then

        local backup_file

        backup_file="$WINGS_CONFIG.backup.$(date +%Y%m%d-%H%M%S)"

        cp \
            "$WINGS_CONFIG" \
            "$backup_file"

        chmod 0600 "$backup_file"

        log "Backup Wings config dibuat:"
        log "$backup_file"
    fi

    # --------------------------------------------------------
    # Install config
    # --------------------------------------------------------

    install \
        -m 0600 \
        "$CONFIG_TMP" \
        "$WINGS_CONFIG"

    rm -f "$CONFIG_TMP"

    CONFIG_TMP=""

    if [[ ! -s "$WINGS_CONFIG" ]]; then

        wings_fail \
            "Gagal membuat $WINGS_CONFIG."
    fi

    log "Wings config: OK"

    echo
    echo "================================================"
    echo "             CONFIGURATION CHECK"
    echo "================================================"
    echo

    local uuid=""
    local token_id=""

    uuid="$(
        awk -F': ' '$1=="uuid" {print $2; exit}' "$WINGS_CONFIG" |
        sed "s/^['\"]//; s/['\"]$//"
    )"

    token_id="$(
        awk -F': ' '$1=="token_id" {print $2; exit}' "$WINGS_CONFIG" |
        sed "s/^['\"]//; s/['\"]$//"
    )"

    info "UUID      : $uuid"
    info "Token ID  : $token_id"
    info "Remote    : $remote"
    info "API Host  : 0.0.0.0"
    info "API Port  : 8080"

    if [[ -n "$sftp_port" ]]; then
        info "SFTP Port : $sftp_port"
    fi

    info "Node FQDN : $NODE_DOMAIN"

    echo
    log "Token Wings tidak ditampilkan."
}

# ============================================================
# VALIDATE WINGS CONFIG
# ============================================================

validate_wings_config() {

    info "Memvalidasi config.yml..."

    if [[ ! -s "$WINGS_CONFIG" ]]; then
        wings_fail "config.yml tidak ditemukan."
    fi

    if ! grep -Eq '^uuid:' "$WINGS_CONFIG"; then
        wings_fail "uuid tidak ditemukan."
    fi

    if ! grep -Eq '^token_id:' "$WINGS_CONFIG"; then
        wings_fail "token_id tidak ditemukan."
    fi

    if ! grep -Eq '^token:' "$WINGS_CONFIG"; then
        wings_fail "token tidak ditemukan."
    fi

    if ! grep -Eq '^api:' "$WINGS_CONFIG"; then
        wings_fail "api tidak ditemukan."
    fi

    if ! grep -Eq '^remote:' "$WINGS_CONFIG"; then
        wings_fail "remote tidak ditemukan."
    fi

    # Wings itself parses the YAML.
    #
    # Use Wings configtest when available.
    if "$WINGS_BINARY" --help 2>&1 |
        grep -q "configtest"; then

        if ! "$WINGS_BINARY" configtest \
            --config "$WINGS_CONFIG" \
            >/tmp/putzofficial-wings-configtest.log \
            2>&1; then

            cat /tmp/putzofficial-wings-configtest.log || true

            wings_fail \
                "Wings menolak konfigurasi config.yml."
        fi

        rm -f /tmp/putzofficial-wings-configtest.log
    fi

    log "Wings config: valid"
}

# ============================================================
# SYSTEMD
# ============================================================

create_wings_service() {

    info "Membuat systemd service Wings..."

    cat > "$WINGS_SERVICE" <<'SERVICE'
[Unit]
Description=Pterodactyl Wings Daemon
Documentation=https://pterodactyl.io/wings/1.0/installing.html

After=docker.service
Requires=docker.service

[Service]
Type=simple

User=root

WorkingDirectory=/etc/pterodactyl

ExecStart=/usr/local/bin/wings

Restart=on-failure
RestartSec=5

LimitNOFILE=4096

KillMode=process

TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
SERVICE

    chmod 0644 "$WINGS_SERVICE"

    systemctl daemon-reload

    systemctl enable wings

    log "systemd Wings: OK"
}

# ============================================================
# FIREWALL
# ============================================================

configure_firewall() {

    info "Memeriksa firewall..."

    if ! command_exists ufw; then

        warn "UFW tidak tersedia."

        return 0
    fi

    if ! ufw status 2>/dev/null |
        grep -q "Status: active"; then

        warn "UFW tidak aktif."
        warn "Tidak mengaktifkan UFW otomatis."

        return 0
    fi

    ufw allow 80/tcp >/dev/null || true
    ufw allow 443/tcp >/dev/null || true
    ufw allow 2022/tcp >/dev/null || true

    # Wings 8080 is intentionally not required publicly
    # because Nginx proxies to it locally.
    #
    # If your Pterodactyl setup requires public access to
    # Wings API, open it manually.

    log "Firewall: 80, 443 dan 2022 diperbolehkan."
}

# ============================================================
# START WINGS
# ============================================================

start_wings() {

    info "Menjalankan Wings..."

    systemctl daemon-reload

    systemctl restart wings

    sleep 5

    if systemctl is-active --quiet wings; then

        log "Wings service: ACTIVE"

        return 0
    fi

    echo
    warn "Wings gagal aktif."
    echo

    journalctl \
        -u wings \
        -n 100 \
        --no-pager \
        -l ||
        true

    echo

    wings_fail "Wings gagal dijalankan."
}

# ============================================================
# PORT CHECK
# ============================================================

wait_for_port() {

    local port="$1"

    local attempts=20
    local i=1

    info "Menunggu port $port..."

    while [[ "$i" -le "$attempts" ]]; do

        if ss -lnt 2>/dev/null |
            grep -Eq ":${port}[[:space:]]"; then

            log "Port $port: LISTENING"

            return 0
        fi

        sleep 1

        i=$((i + 1))
    done

    warn "Port $port belum listening."

    return 1
}

# ============================================================
# HTTPS TEST
# ============================================================

test_node_https() {

    info "Menguji HTTPS Node..."

    local http_code=""

    http_code="$(
        curl \
            -4 \
            -k \
            -sS \
            --connect-timeout 10 \
            --max-time 20 \
            -o /tmp/putzofficial-node-response \
            -w '%{http_code}' \
            "https://$NODE_DOMAIN/" \
            2>/dev/null ||
            true
    )"

    case "$http_code" in

        200|301|302|401|403|404)

            log "HTTPS Node reachable: HTTP $http_code"

            ;;

        ""|000)

            warn "HTTPS Node belum dapat diakses."

            return 1

            ;;

        *)

            warn "HTTPS Node memberikan HTTP $http_code."

            return 1

            ;;
    esac

    rm -f /tmp/putzofficial-node-response
}

# ============================================================
# WINGS LOCAL TEST
# ============================================================

test_wings_local() {

    info "Menguji Wings lokal..."

    local code=""

    code="$(
        curl \
            -sS \
            --connect-timeout 5 \
            --max-time 10 \
            -o /tmp/putzofficial-wings-local \
            -w '%{http_code}' \
            http://127.0.0.1:8080/ \
            2>/dev/null ||
            true
    )"

    case "$code" in

        200|401|403|404)

            log "Wings lokal reachable: HTTP $code"

            ;;

        ""|000)

            warn "Wings lokal tidak memberikan response."

            return 1

            ;;

        *)

            warn "Wings lokal memberikan HTTP $code."

            return 1

            ;;
    esac

    rm -f /tmp/putzofficial-wings-local
}

# ============================================================
# LOG CHECK
# ============================================================

verify_wings_logs() {

    info "Memeriksa log Wings..."

    sleep 2

    local logs=""

    logs="$(
        journalctl \
            -u wings \
            -n 100 \
            --no-pager \
            2>/dev/null ||
            true
    )"

    if echo "$logs" |
        grep -qi \
        "fetching list of servers from API"; then

        log "Wings berhasil berkomunikasi dengan Panel."

        return 0
    fi

    if echo "$logs" |
        grep -qi \
        "processing servers returned by the API"; then

        log "Wings menerima response dari Panel."

        return 0
    fi

    if echo "$logs" |
        grep -qi \
        "error"; then

        warn "Ditemukan pesan error pada log Wings."
        warn "Periksa: journalctl -u wings -n 100 --no-pager"

        return 0
    fi

    warn "Belum menemukan log komunikasi Panel."
    warn "Ini belum tentu berarti Wings gagal."

    return 0
}

# ============================================================
# AUTO RENEWAL
# ============================================================

enable_certbot_renewal() {

    info "Memastikan auto-renewal SSL..."

    if systemctl list-timers 2>/dev/null |
        grep -q certbot; then

        log "Certbot renewal timer: tersedia."

        return 0
    fi

    if systemctl list-timers 2>/dev/null |
        grep -q snap.certbot; then

        log "Certbot snap renewal timer: tersedia."

        return 0
    fi

    systemctl enable --now certbot.timer \
        >/dev/null 2>&1 ||
        true

    log "Certbot renewal: dikonfigurasi."
}

# ============================================================
# FINAL STATUS
# ============================================================

final_status() {

    echo
    echo "================================================"
    echo "              WINGS INSTALLATION"
    echo "================================================"
    echo

    if systemctl is-active --quiet wings; then
        log "Wings Service : ACTIVE"
    else
        warn "Wings Service : NOT ACTIVE"
    fi

    if systemctl is-active --quiet nginx; then
        log "Nginx Service : ACTIVE"
    else
        warn "Nginx Service : NOT ACTIVE"
    fi

    if systemctl is-active --quiet docker; then
        log "Docker        : ACTIVE"
    else
        warn "Docker        : NOT ACTIVE"
    fi

    echo

    if ss -lnt 2>/dev/null |
        grep -Eq ':8080[[:space:]]'; then

        log "Wings API     : 8080 LISTENING"

    else

        warn "Wings API     : 8080 NOT LISTENING"
    fi

    if ss -lnt 2>/dev/null |
        grep -Eq ':2022[[:space:]]'; then

        log "SFTP          : 2022 LISTENING"

    else

        warn "SFTP          : 2022 NOT LISTENING"
    fi

    if ss -lnt 2>/dev/null |
        grep -Eq ':443[[:space:]]'; then

        log "HTTPS         : 443 LISTENING"

    else

        warn "HTTPS         : 443 NOT LISTENING"
    fi

    echo
    echo "Panel:"
    echo "  $PANEL_URL"

    echo
    echo "Node:"
    echo "  $NODE_DOMAIN"

    echo
    echo "Node HTTPS:"
    echo "  https://$NODE_DOMAIN"

    echo
    echo "Wings Config:"
    echo "  $WINGS_CONFIG"

    echo
    echo "SSL Certificate:"
    echo "  $SSL_CERT"

    echo
    echo "Nginx Config:"
    echo "  $NGINX_NODE_CONFIG"

    echo
    echo "================================================"
    echo

    if systemctl is-active --quiet wings &&
       systemctl is-active --quiet nginx; then

        log "Wings installation selesai."

        return 0
    fi

    wings_fail \
        "Wings installation belum sepenuhnya berhasil."
}

# ============================================================
# MAIN
# ============================================================

install_wings() {

    require_root

    echo
    echo "================================================"
    echo "           PUTZOFFICIAL WINGS INSTALLER"
    echo "================================================"
    echo
    echo "Fitur:"
    echo
    echo "  - Docker"
    echo "  - Pterodactyl Wings"
    echo "  - DNS validation"
    echo "  - Let's Encrypt SSL"
    echo "  - Nginx reverse proxy"
    echo "  - systemd"
    echo "  - UFW"
    echo "  - SSL auto renewal"
    echo
    echo "PHP tidak akan dihapus."
    echo "Nginx tidak akan dihapus."
    echo
    echo "================================================"
    echo

    # --------------------------------------------------------
    # Architecture
    # --------------------------------------------------------

    check_architecture

    # --------------------------------------------------------
    # Dependencies
    # --------------------------------------------------------

    install_wings_dependencies

    # --------------------------------------------------------
    # Docker
    # --------------------------------------------------------

    ensure_docker

    # --------------------------------------------------------
    # Wings
    # --------------------------------------------------------

    install_wings_binary

    # --------------------------------------------------------
    # Inputs
    # --------------------------------------------------------

    PANEL_URL="$(ask_panel_url)"

    NODE_ID="$(ask_node_id)"

    NODE_DOMAIN="$(ask_node_domain)"

    export PANEL_URL
    export NODE_ID
    export NODE_DOMAIN

    echo
    echo "================================================"
    echo "             NODE CONFIGURATION"
    echo "================================================"
    echo
    echo "Panel URL : $PANEL_URL"
    echo "Node ID   : $NODE_ID"
    echo "Node FQDN : $NODE_DOMAIN"
    echo
    echo "================================================"
    echo

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    if ! check_node_dns; then

        echo
        warn "DNS Node belum mengarah ke VPS."

        echo
        echo "Contoh DNS:"
        echo
        echo "Type : A"
        echo "Name : node"
        echo "Value: $(get_public_ipv4)"
        echo
        echo "Pastikan proxy Cloudflare untuk Node"
        echo "tidak mengganggu validasi HTTP-01."
        echo

        wings_fail \
            "DNS Node belum valid. Perbaiki DNS terlebih dahulu."
    fi

    # --------------------------------------------------------
    # Nginx HTTP
    # --------------------------------------------------------

    create_nginx_http_config

    # --------------------------------------------------------
    # SSL
    # --------------------------------------------------------

    setup_node_ssl

    check_node_ssl() {

        if [[ ! -f "$SSL_CERT" ]]; then
            wings_fail "Certificate tidak ditemukan."
        fi

        if [[ ! -f "$SSL_KEY" ]]; then
            wings_fail "Private key tidak ditemukan."
        fi

        if ! openssl x509 \
            -in "$SSL_CERT" \
            -noout \
            >/dev/null 2>&1; then

            wings_fail "Certificate SSL tidak valid."
        fi

        log "SSL certificate: valid"
    }

    check_node_ssl

    # --------------------------------------------------------
    # HTTPS Nginx
    # --------------------------------------------------------

    create_nginx_https_config

    # --------------------------------------------------------
    # Wings Config
    # --------------------------------------------------------

    read_wings_configuration

    # --------------------------------------------------------
    # Firewall
    # --------------------------------------------------------

    configure_firewall

    # --------------------------------------------------------
    # Validate
    # --------------------------------------------------------

    validate_wings_config

    # --------------------------------------------------------
    # Service
    # --------------------------------------------------------

    create_wings_service

    # --------------------------------------------------------
    # Start Wings
    # --------------------------------------------------------

    start_wings

    # --------------------------------------------------------
    # Ports
    # --------------------------------------------------------

    wait_for_port 8080 || true

    wait_for_port 2022 || true

    # --------------------------------------------------------
    # Local Wings
    # --------------------------------------------------------

    test_wings_local || true

    # --------------------------------------------------------
    # HTTPS
    # --------------------------------------------------------

    test_node_https || true

    # --------------------------------------------------------
    # Renewal
    # --------------------------------------------------------

    enable_certbot_renewal

    # --------------------------------------------------------
    # Logs
    # --------------------------------------------------------

    verify_wings_logs

    # --------------------------------------------------------
    # Final
    # --------------------------------------------------------

    final_status
}

# ============================================================
# START
# ============================================================

install_wings
