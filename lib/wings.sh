#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

# ============================================================
# PUTZOFFICIAL WINGS INSTALLER
# Compatible with:
#   - common.sh
#   - install.sh
#   - Ubuntu
#   - Pterodactyl Wings 1.13.x
# ============================================================

WINGS_BINARY="/usr/local/bin/wings"
WINGS_CONFIG="/etc/pterodactyl/config.yml"
WINGS_SERVICE="/etc/systemd/system/wings.service"
WINGS_LOG_DIR="/var/log/pterodactyl"

WINGS_VERSION="${WINGS_VERSION:-1.13.3}"
WINGS_DOWNLOAD_URL="https://github.com/pterodactyl/wings/releases/download/v${WINGS_VERSION}/wings_linux_amd64"


# ============================================================
# LOCAL HELPERS
# ============================================================

wings_warn() {
    warn "$*"
}

wings_fail() {
    error "$*"
}

require_command() {
    local cmd="$1"

    if ! command_exists "$cmd"; then
        wings_fail "Command '$cmd' tidak ditemukan."
    fi
}


# ============================================================
# INSTALL DEPENDENCIES
# ============================================================

install_wings_dependencies() {

    info "Memastikan dependency Wings tersedia..."

    apt_install \
        ca-certificates \
        curl \
        openssl \
        jq \
        iproute2 \
        ufw

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
# DOWNLOAD WINGS
# ============================================================

install_wings_binary() {

    info "Memeriksa Pterodactyl Wings..."

    mkdir -p \
        /etc/pterodactyl \
        "$WINGS_LOG_DIR"

    if [[ -x "$WINGS_BINARY" ]]; then

        info "Wings sudah tersedia."

        if "$WINGS_BINARY" version >/dev/null 2>&1; then
            log "Wings binary: OK"
            "$WINGS_BINARY" version || true
            return 0
        fi

        warn "Binary Wings ditemukan tetapi tidak dapat dijalankan."
        warn "Mengunduh ulang Wings..."
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
# INPUT PANEL URL
# ============================================================

ask_panel_url() {

    local value=""

    while true; do

        echo
        read -r -p "Panel URL, contoh https://panel.example.com: " value

        value="${value%/}"

        if [[ -z "$value" ]]; then
            warn "Panel URL tidak boleh kosong."
            continue
        fi

        if [[ "$value" != http://* && "$value" != https://* ]]; then
            warn "Panel URL harus diawali http:// atau https://."
            continue
        fi

        printf '%s' "$value"
        return 0

    done
}


# ============================================================
# INPUT NODE ID
# ============================================================

ask_node_id() {

    local value=""

    while true; do

        read -r -p "Node ID, contoh 1: " value

        if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
            printf '%s' "$value"
            return 0
        fi

        warn "Node ID harus berupa angka lebih dari 0."

    done
}


# ============================================================
# INPUT NODE DOMAIN
# ============================================================

ask_node_domain() {

    local value=""

    while true; do

        read -r -p "Domain Node/FQDN, contoh node.example.com: " value

        value="${value#http://}"
        value="${value#https://}"
        value="${value%%/*}"
        value="${value%%:*}"

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
# READ WINGS CONFIGURATION
#
# User can paste JSON configuration obtained from:
# Admin Panel -> Nodes -> Node -> Configuration
#
# JSON is valid YAML because YAML is a superset of JSON.
# Therefore it can safely be stored as config.yml.
# ============================================================

read_wings_configuration() {

    local config_tmp="/tmp/putzofficial-wings-config.$$.json"
    local line=""

    rm -f "$config_tmp"

    echo
    echo "================================================"
    echo "          WINGS CONFIGURATION"
    echo "================================================"
    echo
    echo "Buka:"
    echo "Admin Panel -> Nodes -> pilih Node -> Configuration"
    echo
    echo "Tempel SELURUH konfigurasi JSON Wings."
    echo
    echo "Contoh:"
    echo '{"debug":false,"uuid":"...","token_id":"...","token":"...","api":{...},"system":{...},"remote":"https://panel.example.com"}'
    echo
    echo "Setelah selesai, ketik END_CONFIG pada baris baru."
    echo
    echo "------------------------------------------------"

    while IFS= read -r line; do

        if [[ "$line" == "END_CONFIG" ]]; then
            break
        fi

        printf '%s\n' "$line" >> "$config_tmp"

    done

    if [[ ! -s "$config_tmp" ]]; then
        rm -f "$config_tmp"
        wings_fail "Konfigurasi Wings kosong."
    fi

    # Remove accidental CRLF
    sed -i 's/\r$//' "$config_tmp"

    # Validate JSON
    if ! jq empty "$config_tmp" >/dev/null 2>&1; then
        rm -f "$config_tmp"

        echo
        warn "Konfigurasi yang ditempel bukan JSON valid."
        echo
        echo "Pastikan kamu menempel SELURUH konfigurasi."
        echo "Jangan menambahkan teks lain."
        echo

        wings_fail "Konfigurasi Wings tidak valid."
    fi

    # Required fields
    local uuid
    local token_id
    local token
    local remote
    local api_host
    local api_port
    local sftp_port

    uuid="$(jq -r '.uuid // empty' "$config_tmp")"
    token_id="$(jq -r '.token_id // empty' "$config_tmp")"
    token="$(jq -r '.token // empty' "$config_tmp")"
    remote="$(jq -r '.remote // empty' "$config_tmp")"
    api_host="$(jq -r '.api.host // empty' "$config_tmp")"
    api_port="$(jq -r '.api.port // empty' "$config_tmp")"
    sftp_port="$(jq -r '.system.sftp.bind_port // empty' "$config_tmp")"

    [[ -n "$uuid" ]] || {
        rm -f "$config_tmp"
        wings_fail "Field uuid tidak ditemukan pada konfigurasi Wings."
    }

    [[ -n "$token_id" ]] || {
        rm -f "$config_tmp"
        wings_fail "Field token_id tidak ditemukan pada konfigurasi Wings."
    }

    [[ -n "$token" ]] || {
        rm -f "$config_tmp"
        wings_fail "Field token tidak ditemukan pada konfigurasi Wings."
    }

    [[ -n "$remote" ]] || {
        rm -f "$config_tmp"
        wings_fail "Field remote tidak ditemukan pada konfigurasi Wings."
    }

    [[ -n "$api_host" ]] || {
        rm -f "$config_tmp"
        wings_fail "Field api.host tidak ditemukan."
    }

    [[ -n "$api_port" ]] || {
        rm -f "$config_tmp"
        wings_fail "Field api.port tidak ditemukan."
    }

    [[ -n "$sftp_port" ]] || {
        rm -f "$config_tmp"
        wings_fail "Field system.sftp.bind_port tidak ditemukan."
    }

    # --------------------------------------------------------
    # Verify panel remote
    # --------------------------------------------------------

    local remote_normalized
    remote_normalized="${remote%/}"

    if [[ "$remote_normalized" != "$PANEL_URL" ]]; then

        warn "Remote pada konfigurasi berbeda dengan Panel URL yang dimasukkan."
        echo
        echo "Panel URL : $PANEL_URL"
        echo "Config    : $remote_normalized"
        echo

        read -r -p "Tetap gunakan konfigurasi ini? [y/N]: " confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            rm -f "$config_tmp"
            wings_fail "Instalasi dibatalkan karena remote berbeda."
        fi

    fi

    # --------------------------------------------------------
    # Verify API settings
    # --------------------------------------------------------

    if [[ "$api_host" != "0.0.0.0" ]]; then
        warn "api.host pada konfigurasi adalah: $api_host"
        warn "Untuk Node publik disarankan menggunakan 0.0.0.0."
    fi

    if [[ "$api_port" != "8080" ]]; then
        warn "api.port pada konfigurasi adalah $api_port."
        warn "Installer ini mengharapkan port Wings 8080."
    fi

    if [[ "$sftp_port" != "2022" ]]; then
        warn "SFTP port pada konfigurasi adalah $sftp_port."
        warn "Installer ini biasanya menggunakan 2022."
    fi

    # --------------------------------------------------------
    # SSL validation
    # --------------------------------------------------------

    local ssl_enabled
    local cert_path
    local key_path

    ssl_enabled="$(jq -r '.api.ssl.enabled // false' "$config_tmp")"
    cert_path="$(jq -r '.api.ssl.cert // empty' "$config_tmp")"
    key_path="$(jq -r '.api.ssl.key // empty' "$config_tmp")"

    if [[ "$ssl_enabled" == "true" ]]; then

        if [[ -z "$cert_path" || -z "$key_path" ]]; then
            rm -f "$config_tmp"
            wings_fail "SSL aktif tetapi path certificate/key tidak ditemukan."
        fi

        info "SSL certificate: $cert_path"
        info "SSL private key: $key_path"

        if [[ ! -f "$cert_path" ]]; then
            rm -f "$config_tmp"

            echo
            warn "Certificate tidak ditemukan:"
            echo "$cert_path"
            echo
            warn "Buat certificate untuk domain Node terlebih dahulu."
            echo

            wings_fail "SSL certificate tidak ditemukan."
        fi

        if [[ ! -f "$key_path" ]]; then
            rm -f "$config_tmp"
            wings_fail "SSL private key tidak ditemukan: $key_path"
        fi

        if [[ ! -r "$cert_path" ]]; then
            rm -f "$config_tmp"
            wings_fail "Certificate tidak dapat dibaca."
        fi

        if [[ ! -r "$key_path" ]]; then
            rm -f "$config_tmp"
            wings_fail "Private key tidak dapat dibaca."
        fi

        log "Wings SSL certificate: OK"

    else

        warn "SSL Wings tidak aktif pada konfigurasi."

        read -r -p "Lanjut tanpa SSL Wings? [y/N]: " confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            rm -f "$config_tmp"
            wings_fail "Instalasi dibatalkan. Aktifkan SSL pada konfigurasi Node."
        fi

    fi

    # --------------------------------------------------------
    # Write config
    # --------------------------------------------------------

    info "Membuat $WINGS_CONFIG..."

    mkdir -p /etc/pterodactyl

    # JSON is valid YAML.
    # Store it directly as config.yml.
    install -m 0600 "$config_tmp" "$WINGS_CONFIG"

    rm -f "$config_tmp"

    if [[ ! -s "$WINGS_CONFIG" ]]; then
        wings_fail "config.yml gagal dibuat."
    fi

    chmod 0600 "$WINGS_CONFIG"

    log "Wings config: OK"

    # --------------------------------------------------------
    # Display safe information
    # Never print token.
    # --------------------------------------------------------

    echo
    echo "================================================"
    echo "             CONFIGURATION CHECK"
    echo "================================================"
    echo
    info "UUID      : $uuid"
    info "Token ID  : $token_id"
    info "Remote    : $remote"
    info "API Host  : $api_host"
    info "API Port  : $api_port"
    info "SFTP Port : $sftp_port"
    info "Node FQDN : $NODE_DOMAIN"
    echo

    log "Secret token tidak ditampilkan untuk keamanan."
}


# ============================================================
# DNS CHECK
# ============================================================

check_node_dns() {

    info "Memeriksa DNS Node..."

    local resolved=""

    if command_exists getent; then
        resolved="$(getent ahostsv4 "$NODE_DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}')"
    fi

    if [[ -z "$resolved" ]]; then
        resolved="$(dig +short A "$NODE_DOMAIN" 2>/dev/null | head -n1 || true)"
    fi

    if [[ -z "$resolved" ]]; then
        warn "Domain Node tidak dapat di-resolve melalui IPv4."
        return 1
    fi

    log "Node DNS: $NODE_DOMAIN -> $resolved"

    return 0
}


# ============================================================
# SSL CHECK
# ============================================================

check_node_ssl() {

    local ssl_enabled
    local cert_path
    local key_path

    ssl_enabled="$(jq -r '.api.ssl.enabled // false' "$WINGS_CONFIG")"

    if [[ "$ssl_enabled" != "true" ]]; then
        warn "SSL Wings tidak aktif."
        return 0
    fi

    cert_path="$(jq -r '.api.ssl.cert // empty' "$WINGS_CONFIG")"
    key_path="$(jq -r '.api.ssl.key // empty' "$WINGS_CONFIG")"

    if [[ ! -f "$cert_path" ]]; then
        wings_fail "Certificate tidak ditemukan: $cert_path"
    fi

    if [[ ! -f "$key_path" ]]; then
        wings_fail "Private key tidak ditemukan: $key_path"
    fi

    # Test certificate readability
    if ! openssl x509 -in "$cert_path" -noout >/dev/null 2>&1; then
        wings_fail "Certificate SSL tidak valid: $cert_path"
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

# Security / process settings
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
        warn "UFW tidak tersedia. Firewall dilewati."
        return 0
    fi

    # Do not force-enable UFW if the server administrator disabled it.
    if ! ufw status | grep -q "Status: active"; then
        warn "UFW tidak aktif. Tidak mengaktifkan UFW secara otomatis."
        return 0
    fi

    ufw allow 8080/tcp >/dev/null || true
    ufw allow 2022/tcp >/dev/null || true

    log "Firewall: port 8080 dan 2022 diperbolehkan"
}


# ============================================================
# VALIDATE WINGS CONFIG
# ============================================================

validate_wings_config() {

    info "Memvalidasi config.yml..."

    if [[ ! -s "$WINGS_CONFIG" ]]; then
        wings_fail "File config.yml tidak ditemukan."
    fi

    if ! jq empty "$WINGS_CONFIG" >/dev/null 2>&1; then
        wings_fail "config.yml bukan konfigurasi JSON/YAML yang valid."
    fi

    if ! "$WINGS_BINARY" --config "$WINGS_CONFIG" --help >/dev/null 2>&1; then
        # Do not treat help failure as fatal because Wings CLI versions
        # can differ. The actual service test below is authoritative.
        true
    fi

    log "config.yml: valid"
}


# ============================================================
# START WINGS
# ============================================================

start_wings() {

    info "Menjalankan Wings..."

    systemctl daemon-reload

    systemctl restart wings

    sleep 3

    if systemctl is-active --quiet wings; then
        log "Wings service: active"
    else

        echo
        warn "Wings gagal aktif."
        echo

        journalctl \
            -u wings \
            -n 60 \
            --no-pager \
            -l || true

        echo

        wings_fail "Wings gagal dijalankan."
    fi
}


# ============================================================
# WAIT FOR PORT
# ============================================================

wait_for_port() {

    local port="$1"
    local attempts=15
    local i=1

    info "Menunggu port $port..."

    while [[ "$i" -le "$attempts" ]]; do

        if ss -lnt 2>/dev/null | grep -Eq ":${port}[[:space:]]"; then
            log "Port $port: listening"
            return 0
        fi

        sleep 1
        i=$((i + 1))

    done

    warn "Port $port belum listening."

    return 1
}


# ============================================================
# TEST NODE HTTP
# ============================================================

test_node_http() {

    local ssl_enabled
    local scheme
    local url
    local http_code

    ssl_enabled="$(jq -r '.api.ssl.enabled // false' "$WINGS_CONFIG")"

    if [[ "$ssl_enabled" == "true" ]]; then
        scheme="https"
    else
        scheme="http"
    fi

    url="${scheme}://${NODE_DOMAIN}:8080/"

    info "Menguji koneksi Wings:"
    info "$url"

    # 401 is EXPECTED when requesting "/" without Wings Authorization.
    # 200/401 both mean the server responded.
    http_code="$(
        curl \
            -4 \
            -k \
            -sS \
            --connect-timeout 10 \
            --max-time 15 \
            -o /tmp/putzofficial-wings-http-response \
            -w '%{http_code}' \
            "$url" \
            2>/dev/null || true
    )"

    case "$http_code" in

        200|401|403|404)
            log "Wings API: reachable (HTTP $http_code)"
            ;;

        "")
            warn "Tidak mendapatkan HTTP response dari Node."
            return 1
            ;;

        *)
            warn "Wings memberikan HTTP $http_code."
            return 1
            ;;

    esac

    rm -f /tmp/putzofficial-wings-http-response
}


# ============================================================
# VERIFY WINGS API CONNECTION
# ============================================================

verify_wings_logs() {

    info "Memeriksa log Wings..."

    sleep 2

    local logs

    logs="$(journalctl -u wings -n 80 --no-pager 2>/dev/null || true)"

    if echo "$logs" | grep -q "fetching list of servers from API"; then
        log "Wings berhasil berkomunikasi dengan Panel."
        return 0
    fi

    if echo "$logs" | grep -q "processing servers returned by the API"; then
        log "Wings berhasil menerima response dari Panel."
        return 0
    fi

    warn "Belum menemukan log komunikasi Panel pada output terbaru."

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

    if ss -lnt 2>/dev/null | grep -Eq ':8080[[:space:]]'; then
        log "Wings Port    : 8080 LISTENING"
    else
        warn "Wings Port    : 8080 NOT LISTENING"
    fi

    if ss -lnt 2>/dev/null | grep -Eq ':2022[[:space:]]'; then
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
    echo "Config:"
    echo "  $WINGS_CONFIG"

    echo
    echo "================================================"
    echo

    if systemctl is-active --quiet wings; then
        log "Wings installation selesai."
    else
        wings_fail "Wings installation belum berhasil."
    fi
}


# ============================================================
# MAIN INSTALL FUNCTION
# ============================================================

install_wings() {

    require_root

    echo
    echo "================================================"
    echo "           PUTZOFFICIAL WINGS INSTALLER"
    echo "================================================"
    echo
    echo "Installer ini akan:"
    echo
    echo "  1. Memastikan Docker"
    echo "  2. Menginstall Wings"
    echo "  3. Meminta Panel URL"
    echo "  4. Meminta Node ID"
    echo "  5. Meminta Domain Node"
    echo "  6. Meminta konfigurasi Wings"
    echo "  7. Memvalidasi SSL"
    echo "  8. Membuat systemd service"
    echo "  9. Menjalankan Wings"
    echo " 10. Menguji port 8080/2022"
    echo " 11. Menguji koneksi Node"
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
    # Wings binary
    # --------------------------------------------------------

    install_wings_binary

    # --------------------------------------------------------
    # User input
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
    echo "Panel URL  : $PANEL_URL"
    echo "Node ID    : $NODE_ID"
    echo "Node FQDN  : $NODE_DOMAIN"
    echo
    echo "================================================"
    echo

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    if ! check_node_dns; then

        warn "DNS Node belum dapat di-resolve."

        read -r -p \
            "Tetap lanjut? [y/N]: " confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            wings_fail "Instalasi dibatalkan karena DNS Node."
        fi
    fi

    # --------------------------------------------------------
    # Configuration
    # --------------------------------------------------------

    read_wings_configuration

    # --------------------------------------------------------
    # SSL
    # --------------------------------------------------------

    check_node_ssl

    # --------------------------------------------------------
    # Firewall
    # --------------------------------------------------------

    configure_firewall

    # --------------------------------------------------------
    # Validate config
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
    # HTTP test
    # --------------------------------------------------------

    test_node_http || true

    # --------------------------------------------------------
    # Panel communication
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
