#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

# ============================================================
# PUTZOFFICIAL WINGS INSTALLER
# ============================================================
#
# Features:
#
# - Ubuntu/Debian
# - x86_64 / amd64
# - Docker
# - Pterodactyl Wings
# - Panel URL
# - Node ID
# - Node Domain
# - DNS validation
# - Automatic Let's Encrypt SSL
# - Existing SSL detection
# - Cloudflare-aware DNS checking
# - Automatic certificate path
# - Wings config
# - systemd
# - UFW
# - Startup wait
# - Port validation
# - Wings API validation
# - Detailed diagnostics
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

NGINX_WAS_ACTIVE="false"

# ============================================================
# ERROR HANDLER
# ============================================================

wings_fail() {
    error "$*"
    return 1
}

# ============================================================
# COMMAND CHECK
# ============================================================

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
        unzip \
        lsof

    log "Dependency Wings: OK"
}

# ============================================================
# DOCKER
# ============================================================

ensure_docker() {

    info "Memeriksa Docker..."

    if command_exists docker; then

        if systemctl is-active --quiet docker; then

            log "Docker: ACTIVE"

            return 0
        fi

        info "Docker tersedia tetapi belum aktif."

        systemctl enable docker >/dev/null 2>&1 || true
        systemctl start docker

        sleep 2

        if systemctl is-active --quiet docker; then

            log "Docker: ACTIVE"

        else

            echo
            systemctl status docker --no-pager -l || true
            echo

            wings_fail "Docker gagal dijalankan."
        fi

        return 0
    fi

    info "Docker belum tersedia."
    info "Menjalankan installer Docker..."

    if [[ ! -f "$BASE_DIR/lib/docker.sh" ]]; then

        wings_fail \
            "lib/docker.sh tidak ditemukan."
    fi

    bash "$BASE_DIR/lib/docker.sh"

    if ! command_exists docker; then

        wings_fail \
            "Docker gagal diinstall."
    fi

    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker

    sleep 2

    if ! systemctl is-active --quiet docker; then

        systemctl status docker --no-pager -l || true

        wings_fail \
            "Docker tidak aktif."
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

        wings_fail \
            "Binary Wings gagal dibuat."
    fi

    if ! "$WINGS_BINARY" version >/dev/null 2>&1; then

        wings_fail \
            "Binary Wings tidak dapat dijalankan."
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

            warn \
                "Panel URL harus diawali http:// atau https://."

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

        value="${value%"${value##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"

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

        if [[ ! "$value" =~ ^[A-Za-z0-9.-]+$ ]]; then

            warn "Domain mengandung karakter tidak valid."

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
            2>/dev/null ||
            true
    )"

    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

        printf '%s' "$ip"

        return 0
    fi

    ip="$(
        curl \
            -4 \
            -fsS \
            --connect-timeout 5 \
            --max-time 10 \
            https://ifconfig.me \
            2>/dev/null ||
            true
    )"

    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

        printf '%s' "$ip"

        return 0
    fi

    return 1
}

# ============================================================
# DNS LOOKUP
# ============================================================

resolve_node_ipv4() {

    local domain="$1"
    local ip=""

    # --------------------------------------------------------
    # getent
    # --------------------------------------------------------

    ip="$(
        getent ahostsv4 "$domain" 2>/dev/null |
        awk 'NR==1 {print $1}' ||
        true
    )"

    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

        printf '%s' "$ip"

        return 0
    fi

    # --------------------------------------------------------
    # dig system resolver
    # --------------------------------------------------------

    ip="$(
        dig +short A "$domain" 2>/dev/null |
        grep -E \
            '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' |
        head -n1 ||
        true
    )"

    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

        printf '%s' "$ip"

        return 0
    fi

    return 1
}

# ============================================================
# DNS CHECK
# ============================================================

check_node_dns() {

    info "Memeriksa DNS Node..."

    local node_ip=""
    local server_ip=""

    node_ip="$(resolve_node_ipv4 "$NODE_DOMAIN" || true)"

    if [[ -z "$node_ip" ]]; then

        warn "Domain $NODE_DOMAIN belum dapat di-resolve."

        return 1
    fi

    server_ip="$(get_public_ipv4 || true)"

    info "DNS Node : $node_ip"

    if [[ -n "$server_ip" ]]; then

        info "VPS IP   : $server_ip"

        if [[ "$node_ip" != "$server_ip" ]]; then

            warn \
                "DNS Node belum mengarah ke public IP VPS ini."

            return 1
        fi

    else

        warn \
            "Public IPv4 VPS tidak dapat diketahui."

        return 1
    fi

    log "DNS Node: OK"

    return 0
}

# ============================================================
# DNS RETRY
# ============================================================

wait_for_dns() {

    info "Menunggu DNS Node..."

    local attempts=12
    local attempt=1

    while [[ "$attempt" -le "$attempts" ]]; do

        if check_node_dns; then

            return 0
        fi

        warn \
            "DNS belum cocok. Percobaan ${attempt}/${attempts}."

        sleep 5

        attempt=$((attempt + 1))
    done

    return 1
}

# ============================================================
# PORT CHECK
# ============================================================

port_is_listening() {

    local port="$1"

    ss -lnt 2>/dev/null |
        grep -Eq ":${port}[[:space:]]"
}

# ============================================================
# PORT 80
# ============================================================

check_port_80() {

    info "Memeriksa port 80..."

    if port_is_listening 80; then

        warn "Port 80 sedang digunakan."

        ss -lntp 2>/dev/null |
            grep -E ':80[[:space:]]' ||
            true

        return 1
    fi

    log "Port 80 tersedia."

    return 0
}

# ============================================================
# NGINX STOP
# ============================================================

stop_nginx_temporarily() {

    NGINX_WAS_ACTIVE="false"

    if ! command_exists nginx; then

        return 0
    fi

    if ! systemctl is-active --quiet nginx; then

        return 0
    fi

    NGINX_WAS_ACTIVE="true"

    info \
        "Menghentikan Nginx sementara untuk Let's Encrypt..."

    systemctl stop nginx

    sleep 1

    if port_is_listening 80; then

        warn \
            "Port 80 masih digunakan setelah Nginx dihentikan."

        return 1
    fi

    log "Nginx dihentikan sementara."

    return 0
}

# ============================================================
# RESTORE NGINX
# ============================================================

restore_nginx() {

    if [[ "$NGINX_WAS_ACTIVE" != "true" ]]; then

        return 0
    fi

    info "Menjalankan kembali Nginx..."

    systemctl start nginx || true

    sleep 2

    if systemctl is-active --quiet nginx; then

        log "Nginx: ACTIVE"

    else

        warn \
            "Nginx tidak berhasil aktif kembali."

        systemctl status nginx \
            --no-pager \
            -l ||
            true
    fi

    NGINX_WAS_ACTIVE="false"
}

# ============================================================
# SSL
# ============================================================

setup_node_ssl() {

    info "Menyiapkan SSL Node otomatis..."

    SSL_CERT="/etc/letsencrypt/live/$NODE_DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$NODE_DOMAIN/privkey.pem"

    mkdir -p /etc/letsencrypt

    echo
    info "SSL Cert : $SSL_CERT"
    info "SSL Key  : $SSL_KEY"
    echo

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

    fi

    if ! command_exists certbot; then

        wings_fail \
            "Certbot gagal diinstall."
    fi

    log "Certbot: OK"

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    if ! wait_for_dns; then

        echo
        echo "================================================"
        echo "                 DNS ERROR"
        echo "================================================"
        echo
        echo "Domain:"
        echo "  $NODE_DOMAIN"
        echo
        echo "Pastikan DNS:"
        echo
        echo "Type : A"
        echo "Name : node / sesuai hostname"
        echo "Value: $(get_public_ipv4 || echo 'PUBLIC-IP-VPS')"
        echo
        echo "Jika menggunakan Cloudflare:"
        echo "  SSL HTTP-01 sebaiknya gunakan DNS-only"
        echo "  untuk proses penerbitan certificate."
        echo
        echo "================================================"
        echo

        wings_fail \
            "DNS Node belum valid."
    fi

    # --------------------------------------------------------
    # Check port 80
    # --------------------------------------------------------

    if port_is_listening 80; then

        if command_exists nginx &&
           systemctl is-active --quiet nginx; then

            stop_nginx_temporarily

        else

            echo
            warn "Port 80 digunakan service lain."

            ss -lntp 2>/dev/null |
                grep -E ':80[[:space:]]' ||
                true

            wings_fail \
                "Port 80 sedang digunakan."
        fi
    fi

    # --------------------------------------------------------
    # Certbot
    # --------------------------------------------------------

    local certbot_result=0

    info "Meminta certificate Let's Encrypt..."

    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --keep-until-expiring \
        --register-unsafely-without-email \
        -d "$NODE_DOMAIN" \
        || certbot_result=$?

    # --------------------------------------------------------
    # Restore Nginx
    # --------------------------------------------------------

    restore_nginx

    # --------------------------------------------------------
    # Certbot error
    # --------------------------------------------------------

    if [[ "$certbot_result" -ne 0 ]]; then

        echo
        echo "================================================"
        echo "             LET'S ENCRYPT ERROR"
        echo "================================================"
        echo

        warn "Certbot gagal menerbitkan SSL."

        echo
        echo "Cek berikut:"
        echo
        echo "  Domain : $NODE_DOMAIN"
        echo "  Port   : 80"
        echo "  DNS    : $(resolve_node_ipv4 "$NODE_DOMAIN" || echo 'tidak terdeteksi')"
        echo "  VPS IP : $(get_public_ipv4 || echo 'tidak terdeteksi')"
        echo

        wings_fail \
            "SSL Node gagal dibuat."
    fi

    # --------------------------------------------------------
    # Verify certificate
    # --------------------------------------------------------

    if [[ ! -f "$SSL_CERT" ]]; then

        wings_fail \
            "Certificate tidak ditemukan: $SSL_CERT"
    fi

    if [[ ! -f "$SSL_KEY" ]]; then

        wings_fail \
            "Private key tidak ditemukan: $SSL_KEY"
    fi

    chmod 0644 "$SSL_CERT"
    chmod 0600 "$SSL_KEY"

    if ! openssl x509 \
        -in "$SSL_CERT" \
        -noout \
        >/dev/null 2>&1; then

        wings_fail \
            "Certificate SSL tidak valid."
    fi

    log "SSL Node: OK"
}

# ============================================================
# READ WINGS CONFIG
# ============================================================

read_wings_configuration() {

    local config_tmp="/tmp/putzofficial-wings-config.$$.yml"

    local line=""

    rm -f "$config_tmp"

    echo
    echo "================================================"
    echo "             WINGS CONFIGURATION"
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
    echo "Paste di bawah."
    echo
    echo "Selesai dengan:"
    echo
    echo "END_CONFIG"
    echo
    echo "------------------------------------------------"
    echo

    while IFS= read -r line; do

        line="${line//$'\r'/}"

        if [[ "$line" == "END_CONFIG" ]]; then

            break
        fi

        printf '%s\n' "$line" >> "$config_tmp"

    done

    if [[ ! -s "$config_tmp" ]]; then

        rm -f "$config_tmp"

        wings_fail \
            "Konfigurasi Wings kosong."
    fi

    info "Memeriksa struktur konfigurasi..."

    # --------------------------------------------------------
    # Basic values
    # --------------------------------------------------------

    local uuid=""
    local token_id=""
    local token=""
    local remote=""
    local api_host=""
    local api_port=""
    local sftp_port=""

    uuid="$(
        awk -F': ' '$1=="uuid" {print $2; exit}' \
            "$config_tmp" |
        tr -d "'\""
    )"

    token_id="$(
        awk -F': ' '$1=="token_id" {print $2; exit}' \
            "$config_tmp" |
        tr -d "'\""
    )"

    token="$(
        awk -F': ' '$1=="token" {print $2; exit}' \
            "$config_tmp" |
        tr -d "'\""
    )"

    remote="$(
        awk -F': ' '$1=="remote" {print $2; exit}' \
            "$config_tmp" |
        tr -d "'\""
    )"

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

            /^[^[:space:]]/ && !/^api:/ {
                inside=0
            }
        ' "$config_tmp" |
        tr -d "'\""
    )"

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

            /^[^[:space:]]/ && !/^api:/ {
                inside=0
            }
        ' "$config_tmp" |
        tr -d "'\""
    )"

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

            /^  [^[:space:]]/ && !/^  sftp:/ {
                inside=0
            }
        ' "$config_tmp" |
        tr -d "'\""
    )"

    # --------------------------------------------------------
    # Required
    # --------------------------------------------------------

    if [[ -z "$uuid" ]]; then

        rm -f "$config_tmp"

        wings_fail \
            "Field uuid tidak ditemukan."
    fi

    if [[ -z "$token_id" ]]; then

        rm -f "$config_tmp"

        wings_fail \
            "Field token_id tidak ditemukan."
    fi

    if [[ -z "$token" ]]; then

        rm -f "$config_tmp"

        wings_fail \
            "Field token tidak ditemukan."
    fi

    if [[ -z "$remote" ]]; then

        rm -f "$config_tmp"

        wings_fail \
            "Field remote tidak ditemukan."
    fi

    if [[ -z "$api_host" ]]; then

        rm -f "$config_tmp"

        wings_fail \
            "Field api.host tidak ditemukan."
    fi

    if [[ -z "$api_port" ]]; then

        rm -f "$config_tmp"

        wings_fail \
            "Field api.port tidak ditemukan."
    fi

    # --------------------------------------------------------
    # Normalize
    # --------------------------------------------------------

    local normalized_remote=""
    local normalized_panel=""

    normalized_remote="${remote%/}"
    normalized_panel="${PANEL_URL%/}"

    if [[ "$normalized_remote" != "$normalized_panel" ]]; then

        echo
        warn \
            "Remote pada konfigurasi berbeda dengan Panel URL."

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
    # SSL Detection
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
        tr -d "'\"" |
        tr '[:upper:]' '[:lower:]'
    )"

    if [[ "$ssl_enabled" == "true" ]]; then

        info "SSL Wings: ENABLED"

        # ----------------------------------------------------
        # Replace certificate paths
        # ----------------------------------------------------

        if grep -Eq '^[[:space:]]*cert:' "$config_tmp"; then

            sed -i -E \
                "s#^([[:space:]]*cert:).*#\1 ${SSL_CERT}#" \
                "$config_tmp"

        else

            warn \
                "Field cert tidak ditemukan pada konfigurasi."
        fi

        if grep -Eq '^[[:space:]]*key:' "$config_tmp"; then

            sed -i -E \
                "s#^([[:space:]]*key:).*#\1 ${SSL_KEY}#" \
                "$config_tmp"

        else

            warn \
                "Field key tidak ditemukan pada konfigurasi."
        fi

        log "SSL certificate path dikonfigurasi otomatis."

    else

        rm -f "$config_tmp"

        wings_fail \
            "SSL Wings tidak aktif pada konfigurasi Node."
    fi

    # --------------------------------------------------------
    # Write
    # --------------------------------------------------------

    mkdir -p /etc/pterodactyl

    install \
        -m 0600 \
        "$config_tmp" \
        "$WINGS_CONFIG"

    rm -f "$config_tmp"

    if [[ ! -s "$WINGS_CONFIG" ]]; then

        wings_fail \
            "config.yml gagal dibuat."
    fi

    chmod 0600 "$WINGS_CONFIG"

    log "Wings config: OK"

    # --------------------------------------------------------
    # Safe information
    # --------------------------------------------------------

    echo
    echo "================================================"
    echo "            CONFIGURATION CHECK"
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
    warn "Token rahasia tidak ditampilkan."

    echo
    info "SSL Cert  : $SSL_CERT"
    info "SSL Key   : $SSL_KEY"
}

# ============================================================
# VERIFY SSL
# ============================================================

check_node_ssl() {

    info "Memeriksa SSL Node..."

    if [[ ! -f "$SSL_CERT" ]]; then

        wings_fail \
            "Certificate tidak ditemukan: $SSL_CERT"
    fi

    if [[ ! -f "$SSL_KEY" ]]; then

        wings_fail \
            "Private key tidak ditemukan: $SSL_KEY"
    fi

    if ! openssl x509 \
        -in "$SSL_CERT" \
        -noout \
        >/dev/null 2>&1; then

        wings_fail \
            "Certificate SSL tidak valid."
    fi

    log "Node SSL: OK"
}

# ============================================================
# SYSTEMD SERVICE
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

    systemctl enable wings >/dev/null 2>&1

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

    log \
        "Firewall: 80, 443, 8080 dan 2022 diperbolehkan."
}

# ============================================================
# CONFIG VALIDATION
# ============================================================

validate_wings_config() {

    info "Memvalidasi config.yml..."

    if [[ ! -s "$WINGS_CONFIG" ]]; then

        wings_fail \
            "config.yml tidak ditemukan."
    fi

    if ! grep -q '^uuid:' "$WINGS_CONFIG"; then

        wings_fail \
            "config.yml tidak memiliki uuid."
    fi

    if ! grep -q '^token_id:' "$WINGS_CONFIG"; then

        wings_fail \
            "config.yml tidak memiliki token_id."
    fi

    if ! grep -q '^token:' "$WINGS_CONFIG"; then

        wings_fail \
            "config.yml tidak memiliki token."
    fi

    if ! grep -q '^api:' "$WINGS_CONFIG"; then

        wings_fail \
            "config.yml tidak memiliki api."
    fi

    if ! grep -q '^remote:' "$WINGS_CONFIG"; then

        wings_fail \
            "config.yml tidak memiliki remote."
    fi

    log "Struktur config.yml: OK"
}

# ============================================================
# WINGS DIAGNOSTIC
# ============================================================

show_wings_diagnostics() {

    echo
    echo "================================================"
    echo "                 WINGS STATUS"
    echo "================================================"
    echo

    systemctl status wings \
        --no-pager \
        -l ||
        true

    echo
    echo "================================================"
    echo "                 WINGS JOURNAL"
    echo "================================================"
    echo

    journalctl \
        -u wings \
        -n 100 \
        --no-pager \
        -l ||
        true

    echo
    echo "================================================"
    echo "                   PORTS"
    echo "================================================"
    echo

    ss -lntp 2>/dev/null |
        grep -E ':8080|:2022' ||
        true
}

# ============================================================
# START WINGS
# ============================================================

start_wings() {

    info "Menjalankan Wings..."

    systemctl daemon-reload

    systemctl enable wings >/dev/null 2>&1 || true

    systemctl restart wings

    info "Menunggu Wings selesai startup..."

    local max_attempts=30
    local attempt=1

    while [[ "$attempt" -le "$max_attempts" ]]; do

        # ----------------------------------------------------
        # Service state
        # ----------------------------------------------------

        if systemctl is-active --quiet wings; then

            # Give Wings time to initialize.
            sleep 2

            # ------------------------------------------------
            # API port
            # ------------------------------------------------

            if port_is_listening 8080; then

                log "Wings Service : ACTIVE"
                log "Wings API     : 8080 LISTENING"

                # ------------------------------------------------
                # SFTP
                # ------------------------------------------------

                if port_is_listening 2022; then

                    log "Wings SFTP    : 2022 LISTENING"

                else

                    warn \
                        "Wings aktif tetapi port SFTP 2022 belum listening."
                fi

                return 0
            fi
        fi

        info \
            "Menunggu Wings... ${attempt}/${max_attempts}"

        sleep 2

        attempt=$((attempt + 1))
    done

    echo

    warn \
        "Wings belum selesai startup dalam waktu yang ditentukan."

    show_wings_diagnostics

    # --------------------------------------------------------
    # Important:
    # Jangan langsung menganggap gagal hanya karena systemd
    # masih activating. Periksa apakah process Wings hidup.
    # --------------------------------------------------------

    if systemctl is-active --quiet wings; then

        if pgrep -x wings >/dev/null 2>&1; then

            warn \
                "Process Wings masih berjalan."

            warn \
                "Namun port 8080 belum terbuka."

            wings_fail \
                "Wings startup timeout."
        fi
    fi

    wings_fail \
        "Wings gagal dijalankan."
}

# ============================================================
# WAIT FOR PORT
# ============================================================

wait_for_port() {

    local port="$1"

    local attempts=30
    local attempt=1

    info "Menunggu port $port..."

    while [[ "$attempt" -le "$attempts" ]]; do

        if port_is_listening "$port"; then

            log "Port $port: LISTENING"

            return 0
        fi

        sleep 1

        attempt=$((attempt + 1))
    done

    warn \
        "Port $port tidak listening."

    return 1
}

# ============================================================
# TEST WINGS HTTP
# ============================================================

test_node_http() {

    info "Menguji koneksi Wings..."

    local url="https://${NODE_DOMAIN}:8080/"

    echo
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

            log \
                "Wings API reachable: HTTP $http_code"

            rm -f \
                /tmp/putzofficial-wings-response

            return 0
            ;;

        "")

            warn \
                "Tidak mendapatkan HTTP response."

            rm -f \
                /tmp/putzofficial-wings-response

            return 1
            ;;

        *)

            warn \
                "Wings memberikan HTTP $http_code."

            rm -f \
                /tmp/putzofficial-wings-response

            return 1
            ;;
    esac
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

        log \
            "Wings berhasil berkomunikasi dengan Panel."

        return 0
    fi

    if echo "$logs" |
        grep -qi \
        "processing servers returned by the API"; then

        log \
            "Wings menerima response dari Panel."

        return 0
    fi

    warn \
        "Belum menemukan log komunikasi Panel."

    warn \
        "Periksa journalctl -u wings jika diperlukan."

    return 0
}

# ============================================================
# FINAL STATUS
# ============================================================

final_status() {

    echo
    echo "================================================"
    echo "           WINGS INSTALLATION RESULT"
    echo "================================================"
    echo

    # --------------------------------------------------------
    # Service
    # --------------------------------------------------------

    if systemctl is-active --quiet wings; then

        log "Wings Service : ACTIVE"

    else

        warn "Wings Service : NOT ACTIVE"
    fi

    # --------------------------------------------------------
    # API
    # --------------------------------------------------------

    if port_is_listening 8080; then

        log "Wings API     : 8080 LISTENING"

    else

        warn "Wings API     : 8080 NOT LISTENING"
    fi

    # --------------------------------------------------------
    # SFTP
    # --------------------------------------------------------

    if port_is_listening 2022; then

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
    echo "Service:"
    echo "  $WINGS_SERVICE"

    echo
    echo "================================================"
    echo

    # --------------------------------------------------------
    # Final validation
    # --------------------------------------------------------

    if systemctl is-active --quiet wings &&
       port_is_listening 8080 &&
       port_is_listening 2022; then

        log "Wings installation selesai."
        log "Wings aktif dan port utama tersedia."

        return 0
    fi

    wings_fail \
        "Wings installation belum berhasil."
}

# ============================================================
# MAIN INSTALL
# ============================================================

install_wings() {

    require_root

    echo
    echo "================================================"
    echo "        PUTZOFFICIAL WINGS INSTALLER"
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
    echo " 13. Menunggu port 8080"
    echo " 14. Menunggu port 2022"
    echo " 15. Test koneksi Wings"
    echo " 16. Check komunikasi Panel"
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

    if ! wait_for_dns; then

        echo
        echo "================================================"
        echo "                 DNS ERROR"
        echo "================================================"
        echo

        warn \
            "DNS Node belum valid."

        echo
        echo "Contoh:"
        echo
        echo "Type : A"
        echo "Name : node"
        echo "Value: $(get_public_ipv4 || echo '168.144.104.186')"
        echo
        echo "Node:"
        echo "  $NODE_DOMAIN"
        echo

        wings_fail \
            "Perbaiki DNS Node terlebih dahulu."
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

    wait_for_port 8080

    wait_for_port 2022

    # --------------------------------------------------------
    # HTTP
    # --------------------------------------------------------

    if ! test_node_http; then

        warn \
            "HTTP test tidak mendapatkan response normal."

        warn \
            "Wings service dan port tetap akan diverifikasi."
    fi

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

Setelah mengganti file

Jalankan:

chmod +x lib/wings.sh

Kalau installer utama memanggil file ini, jalankan installer utama seperti biasa.

Kalau mau mengetes Wings yang sekarang tanpa install ulang:

systemctl restart wings

for i in {1..30}; do
    if systemctl is-active --quiet wings; then
        echo "[OK] Wings ACTIVE"
        break
    fi
    echo "[INFO] Menunggu Wings... $i/30"
    sleep 2
done

ss -lntp | grep -E ':8080|:2022'

Dengan versi ini, installer tidak akan langsung menyimpulkan gagal hanya karena Wings masih "activating" beberapa detik. Dia menunggu sampai service aktif dan "8080"/"2022" benar-benar listening.

Catatan: "TLS handshake error: client sent an HTTP request to an HTTPS server" yang muncul di log sebelumnya tidak perlu dianggap sebagai crash Wings. Itu adalah request HTTP yang masuk ke listener HTTPS.
