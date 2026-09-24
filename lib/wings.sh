#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

# ============================================================
# PUTZOFFICIAL WINGS INSTALLER
# ============================================================
#
# Fungsi:
#   - Install dependency Wings
#   - Install Docker jika diperlukan
#   - Install Pterodactyl Wings
#   - Input Panel URL
#   - Input Node ID
#   - Input Node Domain
#   - Cek DNS Node
#   - Generate SSL Let's Encrypt otomatis
#   - Membuat /etc/pterodactyl/config.yml
#   - Membuat systemd service
#   - Start Wings
#   - Verify service, port dan SSL
#
# Target:
#   Ubuntu x86_64 / amd64
#
# ============================================================

WINGS_BINARY="/usr/local/bin/wings"
WINGS_CONFIG="/etc/pterodactyl/config.yml"
WINGS_SERVICE="/etc/systemd/system/wings.service"
WINGS_LOG_DIR="/var/log/pterodactyl"

WINGS_VERSION="${WINGS_VERSION:-1.13.3}"

WINGS_DOWNLOAD_URL="https://github.com/pterodactyl/wings/releases/download/v${WINGS_VERSION}/wings_linux_amd64"

PANEL_URL=""
NODE_ID=""
NODE_DOMAIN=""

SSL_CERT=""
SSL_KEY=""

# ============================================================
# HELPERS
# ============================================================

wings_fail() {
    error "$*"
    return 1
}

require_command() {

    local command_name="$1"

    if ! command_exists "$command_name"; then
        wings_fail "Command '$command_name' tidak ditemukan."
    fi
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
        tar \
        unzip

    log "Dependency Wings: OK"
}

# ============================================================
# DOCKER
# ============================================================

ensure_docker() {

    info "Memeriksa Docker..."

    if command_exists docker; then

        if systemctl is-active --quiet docker; then
            log "Docker: active"
            return 0
        fi

        info "Docker tersedia tetapi belum aktif."

        systemctl enable docker
        systemctl start docker

        sleep 2

        if systemctl is-active --quiet docker; then
            log "Docker: active"
        else
            wings_fail "Docker gagal dijalankan."
        fi

        return 0
    fi

    info "Docker belum tersedia."
    info "Menjalankan installer Docker..."

    if [[ ! -f "$BASE_DIR/lib/docker.sh" ]]; then
        wings_fail "lib/docker.sh tidak ditemukan."
    fi

    bash "$BASE_DIR/lib/docker.sh"

    if ! command_exists docker; then
        wings_fail "Docker gagal diinstall."
    fi

    systemctl enable docker
    systemctl start docker

    if ! systemctl is-active --quiet docker; then
        wings_fail "Docker tidak aktif."
    fi

    log "Docker: OK"
}

# ============================================================
# INSTALL WINGS BINARY
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

        warn "Binary Wings tidak dapat dijalankan."
        warn "Mengunduh ulang..."
    fi

    info "Mengunduh Pterodactyl Wings v${WINGS_VERSION}..."

    curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --connect-timeout 15 \
        --max-time 300 \
        "$WINGS_DOWNLOAD_URL" \
        -o "$WINGS_BINARY"

    chmod 0755 "$WINGS_BINARY"

    if [[ ! -x "$WINGS_BINARY" ]]; then
        wings_fail "Binary Wings gagal dibuat."
    fi

    if ! "$WINGS_BINARY" version >/dev/null 2>&1; then
        wings_fail "Binary Wings tidak dapat dijalankan."
    fi

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
        value="${value%"${value##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
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

        value="${value%"${value##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"

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
# PUBLIC IP
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
# DNS CHECK
# ============================================================

check_node_dns() {

    info "Memeriksa DNS Node..."

    local node_ip=""
    local server_ip=""

    node_ip="$(
        getent ahostsv4 "$NODE_DOMAIN" 2>/dev/null |
        awk 'NR==1 {print $1}' ||
        true
    )"

    if [[ -z "$node_ip" ]]; then

        node_ip="$(
            dig +short A "$NODE_DOMAIN" 2>/dev/null |
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' |
            head -n1 ||
            true
        )"

    fi

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
# PORT 80
# ============================================================

check_port_80() {

    info "Memeriksa port 80..."

    if ! ss -ltn 2>/dev/null | grep -Eq ':80[[:space:]]'; then

        log "Port 80 tersedia."

        return 0
    fi

    warn "Port 80 sedang digunakan."

    ss -ltnp 2>/dev/null |
        grep ':80 ' ||
        true

    return 1
}

# ============================================================
# STOP NGINX TEMPORARILY
# ============================================================

stop_nginx_temporarily() {

    if ! command_exists nginx; then
        return 0
    fi

    if ! systemctl is-active --quiet nginx; then
        return 0
    fi

    info "Menghentikan Nginx sementara untuk validasi Let's Encrypt..."

    systemctl stop nginx

    log "Nginx dihentikan sementara."

    return 0
}

# ============================================================
# START NGINX
# ============================================================

restore_nginx() {

    if ! command_exists nginx; then
        return 0
    fi

    if systemctl is-enabled nginx >/dev/null 2>&1; then

        info "Menjalankan kembali Nginx..."

        systemctl start nginx 2>/dev/null || true

        if systemctl is-active --quiet nginx; then
            log "Nginx: active"
        else
            warn "Nginx tidak berhasil aktif kembali."
        fi
    fi
}

# ============================================================
# AUTOMATIC SSL
# ============================================================

setup_node_ssl() {

    info "Menyiapkan SSL Node otomatis..."

    SSL_CERT="/etc/letsencrypt/live/$NODE_DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$NODE_DOMAIN/privkey.pem"

    mkdir -p /etc/letsencrypt

    # --------------------------------------------------------
    # Existing certificate
    # --------------------------------------------------------

    if [[ -f "$SSL_CERT" &&
          -f "$SSL_KEY" ]]; then

        log "SSL Node sudah tersedia."

        return 0
    fi

    # --------------------------------------------------------
    # Certbot
    # --------------------------------------------------------

    if ! command_exists certbot; then

        info "Certbot belum tersedia."
        info "Menginstall Certbot..."

        apt_install certbot

        if ! command_exists certbot; then
            wings_fail "Certbot gagal diinstall."
        fi

        log "Certbot: OK"

    else

        log "Certbot: tersedia."
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

    local nginx_was_active="false"

    if systemctl is-active --quiet nginx 2>/dev/null; then
        nginx_was_active="true"
    fi

    if ! check_port_80; then

        if [[ "$nginx_was_active" == "true" ]]; then

            info "Nginx menggunakan port 80."
            info "Nginx akan dihentikan sementara."

            stop_nginx_temporarily

        else

            wings_fail \
                "Port 80 sedang digunakan oleh service lain."
        fi
    fi

    # --------------------------------------------------------
    # Cleanup trap
    # --------------------------------------------------------

    local certbot_result=0

    info "Meminta SSL Let's Encrypt..."

    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --keep-until-expiring \
        --register-unsafely-without-email \
        -d "$NODE_DOMAIN" \
        || certbot_result=$?

    # Restore Nginx
    if [[ "$nginx_was_active" == "true" ]]; then
        restore_nginx
    fi

    if [[ "$certbot_result" -ne 0 ]]; then

        echo
        warn "Let's Encrypt gagal menerbitkan certificate."
        echo
        warn "Pastikan:"
        echo "  1. DNS $NODE_DOMAIN mengarah ke VPS."
        echo "  2. Port 80 terbuka."
        echo "  3. VPS dapat diakses dari internet."
        echo "  4. Tidak ada Cloudflare/Proxy yang menghalangi HTTP-01."
        echo

        wings_fail "SSL Node gagal dibuat."
    fi

    # --------------------------------------------------------
    # Verify files
    # --------------------------------------------------------

    if [[ ! -f "$SSL_CERT" ]]; then
        wings_fail "Certificate tidak ditemukan setelah Certbot selesai."
    fi

    if [[ ! -f "$SSL_KEY" ]]; then
        wings_fail "Private key tidak ditemukan setelah Certbot selesai."
    fi

    chmod 0644 "$SSL_CERT"
    chmod 0600 "$SSL_KEY"

    # --------------------------------------------------------
    # Verify certificate
    # --------------------------------------------------------

    if ! openssl x509 \
        -in "$SSL_CERT" \
        -noout \
        >/dev/null 2>&1; then

        wings_fail "Certificate SSL tidak valid."
    fi

    log "SSL Node: OK"

    echo
    echo "Certificate:"
    echo "  $SSL_CERT"
    echo
    echo "Private Key:"
    echo "  $SSL_KEY"
    echo
}

# ============================================================
# READ WINGS CONFIG
# ============================================================
#
# IMPORTANT:
# Pterodactyl Configuration adalah YAML.
#
# User cukup copy seluruh konfigurasi dari:
#
# Admin Panel
# -> Nodes
# -> pilih Node
# -> Configuration
#
# Paste semuanya.
#
# Selesai dengan:
#
# END_CONFIG
#
# Token tidak pernah ditampilkan ulang oleh installer.
# ============================================================

read_wings_configuration() {

    local config_tmp="/tmp/putzofficial-wings-config.$$.yml"

    local line=""

    rm -f "$config_tmp"

    echo
    echo "================================================"
    echo "          WINGS CONFIGURATION"
    echo "================================================"
    echo
    echo "Buka:"
    echo
    echo "Admin Panel -> Nodes -> pilih Node -> Configuration"
    echo
    echo "Copy SELURUH konfigurasi Wings."
    echo
    echo "Contoh:"
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
    echo "    cert: /etc/letsencrypt/live/node.example.com/fullchain.pem"
    echo "    key: /etc/letsencrypt/live/node.example.com/privkey.pem"
    echo
    echo "Selesai paste:"
    echo
    echo "END_CONFIG"
    echo
    echo "------------------------------------------------"
    echo

    while IFS= read -r line; do

        # Remove CRLF
        line="${line//$'\r'/}"

        if [[ "$line" == "END_CONFIG" ]]; then
            break
        fi

        printf '%s\n' "$line" >> "$config_tmp"

    done

    if [[ ! -s "$config_tmp" ]]; then

        rm -f "$config_tmp"

        wings_fail "Konfigurasi Wings kosong."
    fi

    # --------------------------------------------------------
    # Basic validation
    # --------------------------------------------------------

    info "Memeriksa struktur konfigurasi..."

    local uuid=""
    local token_id=""
    local token=""
    local remote=""
    local api_host=""
    local api_port=""
    local sftp_port=""

    uuid="$(
        awk -F': ' '$1=="uuid" {print $2; exit}' "$config_tmp" |
        tr -d "'\""
    )"

    token_id="$(
        awk -F': ' '$1=="token_id" {print $2; exit}' "$config_tmp" |
        tr -d "'\""
    )"

    token="$(
        awk -F': ' '$1=="token" {print $2; exit}' "$config_tmp" |
        tr -d "'\""
    )"

    remote="$(
        awk -F': ' '$1=="remote" {print $2; exit}' "$config_tmp" |
        tr -d "'\""
    )"

    api_host="$(
        awk '
            /^api:/ { inside=1; next }
            inside && /^  host:/ {
                sub(/^  host:[[:space:]]*/, "")
                print
                exit
            }
            /^[^[:space:]]/ && !/^api:/ { inside=0 }
        ' "$config_tmp" |
        tr -d "'\""
    )"

    api_port="$(
        awk '
            /^api:/ { inside=1; next }
            inside && /^  port:/ {
                sub(/^  port:[[:space:]]*/, "")
                print
                exit
            }
            /^[^[:space:]]/ && !/^api:/ { inside=0 }
        ' "$config_tmp" |
        tr -d "'\""
    )"

    sftp_port="$(
        awk '
            /^  sftp:/ { inside=1; next }
            inside && /^    bind_port:/ {
                sub(/^    bind_port:[[:space:]]*/, "")
                print
                exit
            }
            /^  [^[:space:]]/ && !/^  sftp:/ { inside=0 }
        ' "$config_tmp" |
        tr -d "'\""
    )"

    # --------------------------------------------------------
    # Required fields
    # --------------------------------------------------------

    if [[ -z "$uuid" ]]; then
        rm -f "$config_tmp"
        wings_fail "Field uuid tidak ditemukan."
    fi

    if [[ -z "$token_id" ]]; then
        rm -f "$config_tmp"
        wings_fail "Field token_id tidak ditemukan."
    fi

    if [[ -z "$token" ]]; then
        rm -f "$config_tmp"
        wings_fail "Field token tidak ditemukan."
    fi

    if [[ -z "$remote" ]]; then
        rm -f "$config_tmp"
        wings_fail "Field remote tidak ditemukan."
    fi

    if [[ -z "$api_host" ]]; then
        rm -f "$config_tmp"
        wings_fail "Field api.host tidak ditemukan."
    fi

    if [[ -z "$api_port" ]]; then
        rm -f "$config_tmp"
        wings_fail "Field api.port tidak ditemukan."
    fi

    # --------------------------------------------------------
    # Normalize remote
    # --------------------------------------------------------

    local normalized_remote=""
    local normalized_panel=""

    normalized_remote="${remote%/}"
    normalized_panel="${PANEL_URL%/}"

    if [[ "$normalized_remote" != "$normalized_panel" ]]; then

        echo
        warn "Remote pada konfigurasi berbeda dengan Panel URL."
        echo
        echo "Panel URL : $normalized_panel"
        echo "Config    : $normalized_remote"
        echo

        read -r -p \
            "Tetap gunakan konfigurasi ini? [y/N]: " confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then

            rm -f "$config_tmp"

            wings_fail \
                "Instalasi dibatalkan karena remote berbeda."
        fi

    else

        log "Panel remote: OK"
    fi

    # --------------------------------------------------------
    # SSL
    # --------------------------------------------------------

    local ssl_enabled="false"

    ssl_enabled="$(
        awk '
            /^    enabled:/ {
                sub(/^    enabled:[[:space:]]*/, "")
                print
                exit
            }
        ' "$config_tmp" |
        tr -d "'\""
    )"

    # --------------------------------------------------------
    # Automatically replace certificate paths
    # --------------------------------------------------------

    if [[ "$ssl_enabled" == "true" ]]; then

        info "SSL Wings: ENABLED"

        # Replace cert path
        sed -i -E \
            "s#^([[:space:]]*cert:).*#\1 ${SSL_CERT}#" \
            "$config_tmp"

        # Replace key path
        sed -i -E \
            "s#^([[:space:]]*key:).*#\1 ${SSL_KEY}#" \
            "$config_tmp"

        log "SSL certificate path otomatis dikonfigurasi."

    else

        warn "SSL Wings tidak aktif pada konfigurasi."

        echo
        echo "Installer ini membutuhkan SSL untuk Node publik."
        echo

        rm -f "$config_tmp"

        wings_fail \
            "Aktifkan SSL pada Node Configuration di Panel."
    fi

    # --------------------------------------------------------
    # Write configuration
    # --------------------------------------------------------

    mkdir -p /etc/pterodactyl

    install \
        -m 0600 \
        "$config_tmp" \
        "$WINGS_CONFIG"

    rm -f "$config_tmp"

    if [[ ! -s "$WINGS_CONFIG" ]]; then
        wings_fail "config.yml gagal dibuat."
    fi

    chmod 0600 "$WINGS_CONFIG"

    log "Wings config: OK"

    # --------------------------------------------------------
    # Safe output
    # --------------------------------------------------------

    echo
    echo "================================================"
    echo "             CONFIGURATION CHECK"
    echo "================================================"
    echo
    info "UUID      : $uuid"
    info "Token ID  : $token_id"
    info "Remote    : $normalized_remote"
    info "API Host  : $api_host"
    info "API Port  : $api_port"

    if [[ -n "$sftp_port" ]]; then
        info "SFTP Port : $sftp_port"
    fi

    info "Node FQDN : $NODE_DOMAIN"

    echo
    info "Secret token tidak ditampilkan."
}

# ============================================================
# VERIFY SSL
# ============================================================

check_node_ssl() {

    info "Memeriksa SSL Node..."

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

    log "Node SSL: OK"
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
    ufw allow 8080/tcp >/dev/null || true
    ufw allow 2022/tcp >/dev/null || true

    log "Firewall: 80, 443, 8080 dan 2022 diperbolehkan."
}

# ============================================================
# CONFIG VALIDATION
# ============================================================

validate_wings_config() {

    info "Memvalidasi config.yml..."

    if [[ ! -s "$WINGS_CONFIG" ]]; then

        wings_fail "config.yml tidak ditemukan."
    fi

    if ! grep -q '^uuid:' "$WINGS_CONFIG"; then
        wings_fail "config.yml tidak memiliki uuid."
    fi

    if ! grep -q '^token_id:' "$WINGS_CONFIG"; then
        wings_fail "config.yml tidak memiliki token_id."
    fi

    if ! grep -q '^token:' "$WINGS_CONFIG"; then
        wings_fail "config.yml tidak memiliki token."
    fi

    if ! grep -q '^api:' "$WINGS_CONFIG"; then
        wings_fail "config.yml tidak memiliki api."
    fi

    if ! grep -q '^remote:' "$WINGS_CONFIG"; then
        wings_fail "config.yml tidak memiliki remote."
    fi

    log "Struktur config.yml: OK"
}

# ============================================================
# START WINGS
# ============================================================

start_wings() {

    info "Menjalankan Wings..."

    systemctl daemon-reload

    systemctl restart wings

    sleep 4

    if systemctl is-active --quiet wings; then

        log "Wings service: ACTIVE"

        return 0
    fi

    echo
    warn "Wings gagal aktif."
    echo

    journalctl \
        -u wings \
        -n 80 \
        --no-pager \
        -l ||
        true

    echo

    wings_fail "Wings gagal dijalankan."
}

# ============================================================
# WAIT PORT
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
# NODE HTTP TEST
# ============================================================

test_node_http() {

    local ssl_enabled="false"
    local scheme="http"

    ssl_enabled="$(
        awk '
            /^    enabled:/ {
                sub(/^    enabled:[[:space:]]*/, "")
                print
                exit
            }
        ' "$WINGS_CONFIG" |
        tr -d "'\""
    )"

    if [[ "$ssl_enabled" == "true" ]]; then
        scheme="https"
    fi

    local url="${scheme}://${NODE_DOMAIN}:8080/"

    echo
    info "Menguji koneksi Wings:"
    info "$url"

    local http_code=""

    http_code="$(
        curl \
            -4 \
            -k \
            -sS \
            --connect-timeout 10 \
            --max-time 15 \
            -o /tmp/putzofficial-wings-response \
            -w '%{http_code}' \
            "$url" \
            2>/dev/null ||
            true
    )"

    case "$http_code" in

        200|401|403|404)

            log "Wings API reachable: HTTP $http_code"

            ;;

        "")

            warn "Tidak mendapatkan HTTP response."

            return 1

            ;;

        *)

            warn "Wings memberikan HTTP $http_code."

            return 1

            ;;
    esac

    rm -f /tmp/putzofficial-wings-response
}

# ============================================================
# VERIFY LOG
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

    warn "Belum menemukan log komunikasi Panel."
    warn "Periksa journalctl -u wings jika diperlukan."

    return 0
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

    if ss -lnt 2>/dev/null |
        grep -Eq ':8080[[:space:]]'; then

        log "Wings Port    : 8080 LISTENING"

    else

        warn "Wings Port    : 8080 NOT LISTENING"
    fi

    if ss -lnt 2>/dev/null |
        grep -Eq ':2022[[:space:]]'; then

        log "SFTP Port     : 2022 LISTENING"

    else

        warn "SFTP Port     : 2022 NOT LISTENING"
    fi

    echo
    echo "Node Domain:"
    echo "  $NODE_DOMAIN"

    echo
    echo "Panel:"
    echo "  $PANEL_URL"

    echo
    echo "SSL:"
    echo "  $SSL_CERT"

    echo
    echo "Config:"
    echo "  $WINGS_CONFIG"

    echo
    echo "================================================"
    echo

    if systemctl is-active --quiet wings; then

        log "Wings installation selesai."

    else

        wings_fail \
            "Wings installation belum berhasil."
    fi
}

# ============================================================
# MAIN INSTALL
# ============================================================

install_wings() {

    require_root

    echo
    echo "================================================"
    echo "           PUTZOFFICIAL WINGS INSTALLER"
    echo "================================================"
    echo
    echo "Installer akan:"
    echo
    echo "  1. Memastikan dependency"
    echo "  2. Memastikan Docker"
    echo "  3. Install Wings"
    echo "  4. Input Panel URL"
    echo "  5. Input Node ID"
    echo "  6. Input Node Domain"
    echo "  7. Check DNS"
    echo "  8. Generate SSL otomatis"
    echo "  9. Input konfigurasi Wings"
    echo " 10. Konfigurasi SSL"
    echo " 11. Membuat systemd service"
    echo " 12. Menjalankan Wings"
    echo " 13. Check port"
    echo " 14. Check koneksi Node"
    echo
    echo "================================================"
    echo

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
    # Input
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

        read -r -p \
            "Tetap lanjut ke SSL? [y/N]: " confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then

            wings_fail \
                "Instalasi dibatalkan karena DNS."
        fi
    fi

    # --------------------------------------------------------
    # SSL
    # --------------------------------------------------------

    setup_node_ssl

    check_node_ssl

    # --------------------------------------------------------
    # Config
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
    # Start
    # --------------------------------------------------------

    start_wings

    # --------------------------------------------------------
    # Ports
    # --------------------------------------------------------

    wait_for_port 8080 || true

    wait_for_port 2022 || true

    # --------------------------------------------------------
    # HTTP
    # --------------------------------------------------------

    test_node_http || true

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
