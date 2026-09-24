#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# PUTZOFFICIAL WINGS INSTALLER
# ============================================================
#
# Installer Pterodactyl Wings
#
# Compatible:
#   - Ubuntu
#   - x86_64 / amd64
#   - Pterodactyl Wings 1.13.x
#
# Fungsi:
#   - Install dependency Wings
#   - Install/ensure Docker
#   - Install Wings binary
#   - Input Panel URL
#   - Input Node ID
#   - Input Node Domain
#   - Input konfigurasi YAML Wings
#   - Validasi struktur config
#   - Membuat systemd service
#   - Menjalankan Wings
#   - Memeriksa port Wings
#   - Memeriksa status service
#
# ============================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

# ============================================================
# CONFIGURATION
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

# ============================================================
# HELPERS
# ============================================================

wings_fail() {
    error "$*"
    return 1
}

wings_warn() {
    warn "$*"
}

require_command() {

    local command_name="$1"

    if ! command_exists "$command_name"; then
        wings_fail "Command '$command_name' tidak ditemukan."
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
        dnsutils \
        ufw

    log "Dependency Wings berhasil disiapkan."
}

# ============================================================
# DOCKER
# ============================================================

ensure_docker() {

    info "Memeriksa Docker..."

    # --------------------------------------------------------
    # Docker command sudah ada
    # --------------------------------------------------------

    if command_exists docker; then

        log "Docker binary ditemukan."

        # ----------------------------------------------------
        # Pastikan service aktif
        # ----------------------------------------------------

        if systemctl is-active --quiet docker; then

            log "Docker service: ACTIVE"

            return 0

        fi

        info "Docker tersedia tetapi service belum aktif."

        systemctl enable docker >/dev/null 2>&1 || true
        systemctl start docker

        sleep 2

        if systemctl is-active --quiet docker; then

            log "Docker service berhasil dijalankan."

            return 0

        fi

        wings_fail "Docker gagal dijalankan."

    fi

    # --------------------------------------------------------
    # Docker belum ada
    # --------------------------------------------------------

    info "Docker belum tersedia."

    if [[ ! -f "$BASE_DIR/lib/docker.sh" ]]; then

        wings_fail \
            "lib/docker.sh tidak ditemukan."

    fi

    info "Menjalankan installer Docker PutzOfficial..."

    bash "$BASE_DIR/lib/docker.sh"

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    if ! command_exists docker; then

        wings_fail \
            "Docker gagal diinstall."

    fi

    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker

    sleep 2

    if ! systemctl is-active --quiet docker; then

        wings_fail \
            "Docker service tidak aktif."

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

    # --------------------------------------------------------
    # Existing Wings
    # --------------------------------------------------------

    if [[ -x "$WINGS_BINARY" ]]; then

        info "Wings binary sudah ditemukan."

        if "$WINGS_BINARY" version >/dev/null 2>&1; then

            log "Wings binary: OK"

            echo
            "$WINGS_BINARY" version || true
            echo

            return 0

        fi

        wings_warn \
            "Wings binary tidak dapat dijalankan."

        info "Mengunduh ulang Wings..."

    fi

    # --------------------------------------------------------
    # Download
    # --------------------------------------------------------

    info \
        "Mengunduh Pterodactyl Wings v${WINGS_VERSION}..."

    curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --connect-timeout 15 \
        --max-time 300 \
        "$WINGS_DOWNLOAD_URL" \
        -o "$WINGS_BINARY"

    # --------------------------------------------------------
    # Permission
    # --------------------------------------------------------

    chmod 0755 "$WINGS_BINARY"

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    if [[ ! -x "$WINGS_BINARY" ]]; then

        wings_fail \
            "Binary Wings gagal dibuat."

    fi

    if ! "$WINGS_BINARY" version >/dev/null 2>&1; then

        wings_fail \
            "Binary Wings tidak dapat dijalankan."

    fi

    log "Wings binary berhasil diinstall."

    echo
    "$WINGS_BINARY" version || true
    echo
}

# ============================================================
# PANEL URL
# ============================================================

ask_panel_url() {

    local value=""

    while true; do

        echo

        read -r \
            -p "Panel URL, contoh https://panel.example.com: " \
            value

        value="${value%/}"

        if [[ -z "$value" ]]; then

            wings_warn \
                "Panel URL tidak boleh kosong."

            continue

        fi

        if [[ "$value" != http://* &&
              "$value" != https://* ]]; then

            wings_warn \
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

        read -r \
            -p "Node ID, contoh 1: " \
            value

        if [[ "$value" =~ ^[0-9]+$ ]] &&
           [[ "$value" -gt 0 ]]; then

            printf '%s' "$value"

            return 0

        fi

        wings_warn \
            "Node ID harus berupa angka lebih dari 0."

    done
}

# ============================================================
# NODE DOMAIN
# ============================================================

ask_node_domain() {

    local value=""

    while true; do

        echo

        read -r \
            -p "Domain Node/FQDN, contoh node.example.com: " \
            value

        # ----------------------------------------------------
        # Remove protocol
        # ----------------------------------------------------

        value="${value#http://}"
        value="${value#https://}"

        # ----------------------------------------------------
        # Remove path
        # ----------------------------------------------------

        value="${value%%/*}"

        # ----------------------------------------------------
        # Remove port
        # ----------------------------------------------------

        value="${value%%:*}"

        # ----------------------------------------------------
        # Validation
        # ----------------------------------------------------

        if [[ -z "$value" ]]; then

            wings_warn \
                "Domain Node tidak boleh kosong."

            continue

        fi

        if [[ "$value" != *.* ]]; then

            wings_warn \
                "Masukkan domain/FQDN yang valid."

            continue

        fi

        printf '%s' "$value"

        return 0

    done
}

# ============================================================
# READ WINGS YAML
# ============================================================
#
# Penting:
#
# Pterodactyl Wings menggunakan YAML.
#
# Jangan menggunakan:
#
#     jq empty config.yml
#
# karena jq hanya cocok untuk JSON.
#
# Installer ini menerima YAML langsung.
#
# ============================================================

read_wings_configuration() {

    local config_tmp
    local line=""

    config_tmp="$(mktemp /tmp/putzofficial-wings-config.XXXXXX)"

    trap 'rm -f "$config_tmp"' RETURN

    echo
    echo "================================================"
    echo "          WINGS CONFIGURATION"
    echo "================================================"
    echo
    echo "Buka:"
    echo
    echo "Admin Panel"
    echo "   -> Nodes"
    echo "   -> Pilih Node"
    echo "   -> Configuration"
    echo
    echo "Tempel SELURUH konfigurasi Wings."
    echo
    echo "Format yang diterima:"
    echo
    echo "YAML"
    echo
    echo "Contoh:"
    echo
    echo "debug: false"
    echo "uuid: xxxxx"
    echo "token_id: xxxxx"
    echo "token: xxxxx"
    echo "api:"
    echo "  host: 0.0.0.0"
    echo "  port: 8080"
    echo
    echo "Ketik END_CONFIG pada baris baru"
    echo "setelah seluruh konfigurasi selesai."
    echo
    echo "------------------------------------------------"
    echo

    # --------------------------------------------------------
    # Read multiline configuration
    # --------------------------------------------------------

    while IFS= read -r line; do

        if [[ "$line" == "END_CONFIG" ]]; then
            break
        fi

        printf '%s\n' "$line" >> "$config_tmp"

    done

    # --------------------------------------------------------
    # Remove Windows CRLF
    # --------------------------------------------------------

    sed -i 's/\r$//' "$config_tmp"

    # --------------------------------------------------------
    # Empty config
    # --------------------------------------------------------

    if [[ ! -s "$config_tmp" ]]; then

        rm -f "$config_tmp"

        wings_fail \
            "Konfigurasi Wings kosong."

        return 1
    fi

    # ========================================================
    # BASIC YAML STRUCTURE
    # ========================================================

    info "Memeriksa struktur konfigurasi..."

    # --------------------------------------------------------
    # UUID
    # --------------------------------------------------------

    if ! grep -Eq \
        '^[[:space:]]*uuid:[[:space:]]*[^[:space:]]+' \
        "$config_tmp"; then

        rm -f "$config_tmp"

        wings_fail \
            "Field uuid tidak ditemukan."

        return 1
    fi

    # --------------------------------------------------------
    # TOKEN ID
    # --------------------------------------------------------

    if ! grep -Eq \
        '^[[:space:]]*token_id:[[:space:]]*[^[:space:]]+' \
        "$config_tmp"; then

        rm -f "$config_tmp"

        wings_fail \
            "Field token_id tidak ditemukan."

        return 1
    fi

    # --------------------------------------------------------
    # TOKEN
    # --------------------------------------------------------

    if ! grep -Eq \
        '^[[:space:]]*token:[[:space:]]*[^[:space:]]+' \
        "$config_tmp"; then

        rm -f "$config_tmp"

        wings_fail \
            "Field token tidak ditemukan."

        return 1
    fi

    # --------------------------------------------------------
    # REMOTE
    # --------------------------------------------------------

    if ! grep -Eq \
        '^[[:space:]]*remote:[[:space:]]*' \
        "$config_tmp"; then

        rm -f "$config_tmp"

        wings_fail \
            "Field remote tidak ditemukan."

        return 1
    fi

    # --------------------------------------------------------
    # API
    # --------------------------------------------------------

    if ! grep -Eq \
        '^[[:space:]]*api:[[:space:]]*$' \
        "$config_tmp"; then

        rm -f "$config_tmp"

        wings_fail \
            "Section api tidak ditemukan."

        return 1
    fi

    # --------------------------------------------------------
    # API HOST
    # --------------------------------------------------------

    if ! grep -Eq \
        '^[[:space:]]+host:[[:space:]]*' \
        "$config_tmp"; then

        rm -f "$config_tmp"

        wings_fail \
            "api.host tidak ditemukan."

        return 1
    fi

    # --------------------------------------------------------
    # API PORT
    # --------------------------------------------------------

    if ! grep -Eq \
        '^[[:space:]]+port:[[:space:]]*[0-9]+' \
        "$config_tmp"; then

        rm -f "$config_tmp"

        wings_fail \
            "api.port tidak ditemukan."

        return 1
    fi

    # ========================================================
    # SAFE INFORMATION EXTRACTION
    # ========================================================
    #
    # Hanya mengambil informasi non-secret.
    #
    # TOKEN tidak pernah ditampilkan.
    #
    # ========================================================

    local uuid=""
    local token_id=""
    local remote=""
    local api_host=""
    local api_port=""
    local sftp_port=""
    local ssl_enabled=""
    local cert_path=""
    local key_path=""

    uuid="$(
        awk '
        /^[[:space:]]*uuid:/ {
            sub(/^[[:space:]]*uuid:[[:space:]]*/, "")
            print
            exit
        }' "$config_tmp"
    )"

    token_id="$(
        awk '
        /^[[:space:]]*token_id:/ {
            sub(/^[[:space:]]*token_id:[[:space:]]*/, "")
            print
            exit
        }' "$config_tmp"
    )"

    remote="$(
        awk '
        /^[[:space:]]*remote:/ {
            sub(/^[[:space:]]*remote:[[:space:]]*/, "")
            gsub(/^'\''|'\''$/, "")
            print
            exit
        }' "$config_tmp"
    )"

    api_host="$(
        awk '
        /^[[:space:]]+host:/ {
            sub(/^[[:space:]]*host:[[:space:]]*/, "")
            print
            exit
        }' "$config_tmp"
    )"

    api_port="$(
        awk '
        /^[[:space:]]+port:/ {
            sub(/^[[:space:]]*port:[[:space:]]*/, "")
            print
            exit
        }' "$config_tmp"
    )"

    sftp_port="$(
        awk '
        /bind_port:/ {
            sub(/^[[:space:]]*bind_port:[[:space:]]*/, "")
            print
            exit
        }' "$config_tmp"
    )"

    ssl_enabled="$(
        awk '
        /^[[:space:]]*enabled:/ {
            sub(/^[[:space:]]*enabled:[[:space:]]*/, "")
            print
            exit
        }' "$config_tmp"
    )"

    cert_path="$(
        awk '
        /^[[:space:]]*cert:/ {
            sub(/^[[:space:]]*cert:[[:space:]]*/, "")
            print
            exit
        }' "$config_tmp"
    )"

    key_path="$(
        awk '
        /^[[:space:]]*key:/ {
            sub(/^[[:space:]]*key:[[:space:]]*/, "")
            print
            exit
        }' "$config_tmp"
    )"

    # ========================================================
    # REMOTE CHECK
    # ========================================================

    local remote_normalized
    local panel_normalized

    remote_normalized="${remote%/}"
    panel_normalized="${PANEL_URL%/}"

    if [[ -n "$remote_normalized" ]] &&
       [[ "$remote_normalized" != "$panel_normalized" ]]; then

        echo
        wings_warn \
            "Remote pada konfigurasi berbeda dengan Panel URL."

        echo
        echo "Panel URL : $PANEL_URL"
        echo "Config    : $remote_normalized"
        echo

        local confirm=""

        read -r \
            -p "Tetap gunakan konfigurasi ini? [y/N]: " \
            confirm

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then

            rm -f "$config_tmp"

            wings_fail \
                "Instalasi dibatalkan karena remote berbeda."

            return 1
        fi
    fi

    # ========================================================
    # API CHECK
    # ========================================================

    if [[ "$api_host" != "0.0.0.0" ]]; then

        wings_warn \
            "api.host saat ini: $api_host"

        wings_warn \
            "Untuk Wings yang menerima koneksi eksternal biasanya menggunakan 0.0.0.0."

    fi

    if [[ "$api_port" != "8080" ]]; then

        wings_warn \
            "api.port saat ini: $api_port"

        wings_warn \
            "Port umum Wings adalah 8080."

    fi

    if [[ -n "$sftp_port" ]] &&
       [[ "$sftp_port" != "2022" ]]; then

        wings_warn \
            "SFTP port saat ini: $sftp_port"

        wings_warn \
            "Port umum SFTP Wings adalah 2022."

    fi

    # ========================================================
    # SSL CHECK
    # ========================================================

    if [[ "$ssl_enabled" == "true" ]]; then

        info "SSL Wings: ENABLED"

        if [[ -z "$cert_path" ]]; then

            rm -f "$config_tmp"

            wings_fail \
                "SSL aktif tetapi path certificate tidak ditemukan."

            return 1
        fi

        if [[ -z "$key_path" ]]; then

            rm -f "$config_tmp"

            wings_fail \
                "SSL aktif tetapi path private key tidak ditemukan."

            return 1
        fi

        info "Certificate: $cert_path"
        info "Private key : $key_path"

        if [[ ! -f "$cert_path" ]]; then

            rm -f "$config_tmp"

            wings_fail \
                "Certificate tidak ditemukan: $cert_path"

            return 1
        fi

        if [[ ! -f "$key_path" ]]; then

            rm -f "$config_tmp"

            wings_fail \
                "Private key tidak ditemukan: $key_path"

            return 1
        fi

        if [[ ! -r "$cert_path" ]]; then

            rm -f "$config_tmp"

            wings_fail \
                "Certificate tidak dapat dibaca."

            return 1
        fi

        if [[ ! -r "$key_path" ]]; then

            rm -f "$config_tmp"

            wings_fail \
                "Private key tidak dapat dibaca."

            return 1
        fi

        if ! openssl x509 \
            -in "$cert_path" \
            -noout >/dev/null 2>&1; then

            rm -f "$config_tmp"

            wings_fail \
                "Certificate SSL tidak valid."

            return 1
        fi

        log "Wings SSL certificate: OK"

    else

        wings_warn \
            "SSL Wings tidak aktif."

        local confirm_ssl=""

        read -r \
            -p "Lanjut tanpa SSL Wings? [y/N]: " \
            confirm_ssl

        if [[ ! "$confirm_ssl" =~ ^[Yy]$ ]]; then

            rm -f "$config_tmp"

            wings_fail \
                "Instalasi dibatalkan."

            return 1
        fi
    fi

    # ========================================================
    # SAVE CONFIG
    # ========================================================

    info \
        "Menyimpan konfigurasi ke $WINGS_CONFIG..."

    mkdir -p \
        /etc/pterodactyl

    install \
        -m 0600 \
        "$config_tmp" \
        "$WINGS_CONFIG"

    rm -f "$config_tmp"

    chmod 0600 \
        "$WINGS_CONFIG"

    if [[ ! -s "$WINGS_CONFIG" ]]; then

        wings_fail \
            "config.yml gagal dibuat."

        return 1
    fi

    log "Wings config: OK"

    # ========================================================
    # SAFE DISPLAY
    # ========================================================

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
    info "SFTP Port : ${sftp_port:-not-set}"
    info "Node FQDN : $NODE_DOMAIN"

    echo

    log \
        "Secret token tidak ditampilkan."

    return 0
}

# ============================================================
# DNS CHECK
# ============================================================

check_node_dns() {

    info "Memeriksa DNS Node..."

    local resolved=""

    # --------------------------------------------------------
    # getent
    # --------------------------------------------------------

    if command_exists getent; then

        resolved="$(
            getent ahostsv4 \
                "$NODE_DOMAIN" \
                2>/dev/null |
                awk 'NR==1 {print $1}'
        )"

    fi

    # --------------------------------------------------------
    # dig
    # --------------------------------------------------------

    if [[ -z "$resolved" ]] &&
       command_exists dig; then

        resolved="$(
            dig +short \
                A \
                "$NODE_DOMAIN" \
                2>/dev/null |
                head -n1
        )"

    fi

    # --------------------------------------------------------
    # Result
    # --------------------------------------------------------

    if [[ -z "$resolved" ]]; then

        wings_warn \
            "Domain Node tidak dapat di-resolve melalui IPv4."

        return 1
    fi

    log \
        "Node DNS: $NODE_DOMAIN -> $resolved"

    return 0
}

# ============================================================
# SSL CHECK
# ============================================================

check_node_ssl() {

    if [[ ! -f "$WINGS_CONFIG" ]]; then

        wings_fail \
            "config.yml tidak ditemukan."

        return 1
    fi

    # --------------------------------------------------------
    # Ambil nilai SSL menggunakan awk.
    # Tidak menggunakan jq.
    # --------------------------------------------------------

    local ssl_enabled=""
    local cert_path=""
    local key_path=""

    ssl_enabled="$(
        awk '
        /^[[:space:]]*enabled:/ {
            sub(/^[[:space:]]*enabled:[[:space:]]*/, "")
            print
            exit
        }' "$WINGS_CONFIG"
    )"

    cert_path="$(
        awk '
        /^[[:space:]]*cert:/ {
            sub(/^[[:space:]]*cert:[[:space:]]*/, "")
            print
            exit
        }' "$WINGS_CONFIG"
    )"

    key_path="$(
        awk '
        /^[[:space:]]*key:/ {
            sub(/^[[:space:]]*key:[[:space:]]*/, "")
            print
            exit
        }' "$WINGS_CONFIG"
    )"

    if [[ "$ssl_enabled" != "true" ]]; then

        wings_warn \
            "SSL Wings tidak aktif."

        return 0
    fi

    if [[ -z "$cert_path" ]]; then

        wings_fail \
            "SSL aktif tetapi certificate path kosong."

        return 1
    fi

    if [[ -z "$key_path" ]]; then

        wings_fail \
            "SSL aktif tetapi private key path kosong."

        return 1
    fi

    if [[ ! -f "$cert_path" ]]; then

        wings_fail \
            "Certificate tidak ditemukan: $cert_path"

        return 1
    fi

    if [[ ! -f "$key_path" ]]; then

        wings_fail \
            "Private key tidak ditemukan: $key_path"

        return 1
    fi

    if ! openssl x509 \
        -in "$cert_path" \
        -noout >/dev/null 2>&1; then

        wings_fail \
            "Certificate SSL tidak valid."

        return 1
    fi

    log "Node SSL: OK"

    return 0
}

# ============================================================
# SYSTEMD SERVICE
# ============================================================

create_wings_service() {

    info "Membuat systemd service Wings..."

    mkdir -p \
        /etc/pterodactyl \
        "$WINGS_LOG_DIR"

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

    chmod 0644 \
        "$WINGS_SERVICE"

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

        wings_warn \
            "UFW tidak tersedia."

        return 0
    fi

    # --------------------------------------------------------
    # Jangan mengaktifkan UFW secara paksa.
    # --------------------------------------------------------

    if ! ufw status |
        grep -q "Status: active"; then

        wings_warn \
            "UFW tidak aktif."

        wings_warn \
            "Tidak mengaktifkan UFW secara otomatis."

        return 0
    fi

    # --------------------------------------------------------
    # Wings API
    # --------------------------------------------------------

    ufw allow 8080/tcp >/dev/null 2>&1 || true

    # --------------------------------------------------------
    # SFTP
    # --------------------------------------------------------

    ufw allow 2022/tcp >/dev/null 2>&1 || true

    log \
        "Firewall: port 8080 dan 2022 diperbolehkan."
}

# ============================================================
# VALIDATE CONFIG
# ============================================================

validate_wings_config() {

    info "Memeriksa config.yml..."

    # --------------------------------------------------------
    # File exists
    # --------------------------------------------------------

    if [[ ! -s "$WINGS_CONFIG" ]]; then

        wings_fail \
            "File config.yml tidak ditemukan."

        return 1
    fi

    # --------------------------------------------------------
    # File readable
    # --------------------------------------------------------

    if [[ ! -r "$WINGS_CONFIG" ]]; then

        wings_fail \
            "config.yml tidak dapat dibaca."

        return 1
    fi

    # --------------------------------------------------------
    # Required fields
    # --------------------------------------------------------

    grep -Eq \
        '^[[:space:]]*uuid:[[:space:]]*[^[:space:]]+' \
        "$WINGS_CONFIG" ||
        wings_fail "uuid tidak ditemukan."

    grep -Eq \
        '^[[:space:]]*token_id:[[:space:]]*[^[:space:]]+' \
        "$WINGS_CONFIG" ||
        wings_fail "token_id tidak ditemukan."

    grep -Eq \
        '^[[:space:]]*token:[[:space:]]*[^[:space:]]+' \
        "$WINGS_CONFIG" ||
        wings_fail "token tidak ditemukan."

    grep -Eq \
        '^[[:space:]]*api:[[:space:]]*$' \
        "$WINGS_CONFIG" ||
        wings_fail "section api tidak ditemukan."

    grep -Eq \
        '^[[:space:]]*remote:[[:space:]]*' \
        "$WINGS_CONFIG" ||
        wings_fail "remote tidak ditemukan."

    # --------------------------------------------------------
    # Permission
    # --------------------------------------------------------

    chmod 0600 \
        "$WINGS_CONFIG"

    log \
        "config.yml struktur dasar: OK"
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

        log \
            "Wings service: ACTIVE"

        return 0
    fi

    # --------------------------------------------------------
    # Failed
    # --------------------------------------------------------

    echo

    wings_warn \
        "Wings gagal aktif."

    echo

    echo "================================================"
    echo "              WINGS LOG"
    echo "================================================"
    echo

    journalctl \
        -u wings \
        -n 80 \
        --no-pager \
        -l || true

    echo

    wings_fail \
        "Wings gagal dijalankan."

    return 1
}

# ============================================================
# WAIT FOR PORT
# ============================================================

wait_for_port() {

    local port="$1"

    local attempts=15
    local i=1

    info \
        "Menunggu port $port..."

    while [[ "$i" -le "$attempts" ]]; do

        if ss -lnt 2>/dev/null |
            grep -Eq \
                ":${port}[[:space:]]"; then

            log \
                "Port $port: LISTENING"

            return 0
        fi

        sleep 1

        i=$((i + 1))

    done

    wings_warn \
        "Port $port belum listening."

    return 1
}

# ============================================================
# TEST NODE HTTP
# ============================================================

test_node_http() {

    local ssl_enabled=""
    local scheme=""
    local url=""
    local http_code=""

    # --------------------------------------------------------
    # Get SSL status
    # --------------------------------------------------------

    ssl_enabled="$(
        awk '
        /^[[:space:]]*enabled:/ {
            sub(/^[[:space:]]*enabled:[[:space:]]*/, "")
            print
            exit
        }' "$WINGS_CONFIG"
    )"

    if [[ "$ssl_enabled" == "true" ]]; then
        scheme="https"
    else
        scheme="http"
    fi

    url="${scheme}://${NODE_DOMAIN}:8080/"

    info \
        "Menguji koneksi Wings:"

    info \
        "$url"

    # --------------------------------------------------------
    # Curl
    # --------------------------------------------------------
    #
    # 200 / 401 / 403 / 404 = server merespons.
    #
    # --------------------------------------------------------

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
            2>/dev/null ||
            true
    )"

    case "$http_code" in

        200|401|403|404)

            log \
                "Wings API: reachable (HTTP $http_code)"

            ;;

        "")

            wings_warn \
                "Tidak mendapatkan HTTP response dari Node."

            rm -f \
                /tmp/putzofficial-wings-http-response

            return 1

            ;;

        *)

            wings_warn \
                "Wings memberikan HTTP $http_code."

            rm -f \
                /tmp/putzofficial-wings-http-response

            return 1

            ;;

    esac

    rm -f \
        /tmp/putzofficial-wings-http-response
}

# ============================================================
# VERIFY WINGS LOG
# ============================================================

verify_wings_logs() {

    info "Memeriksa log komunikasi Wings..."

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

    # --------------------------------------------------------
    # Known communication messages
    # --------------------------------------------------------

    if echo "$logs" |
        grep -q \
        "fetching list of servers from API"; then

        log \
            "Wings berhasil berkomunikasi dengan Panel."

        return 0
    fi

    if echo "$logs" |
        grep -q \
        "processing servers returned by the API"; then

        log \
            "Wings menerima response dari Panel."

        return 0
    fi

    # --------------------------------------------------------
    # Don't fail installation merely because log text differs.
    # --------------------------------------------------------

    wings_warn \
        "Belum menemukan pesan komunikasi Panel pada log terbaru."

    wings_warn \
        "Periksa journal Wings jika diperlukan."

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

    # --------------------------------------------------------
    # Service
    # --------------------------------------------------------

    if systemctl is-active --quiet wings; then

        log \
            "Wings Service : ACTIVE"

    else

        wings_warn \
            "Wings Service : NOT ACTIVE"

    fi

    # --------------------------------------------------------
    # API Port
    # --------------------------------------------------------

    if ss -lnt 2>/dev/null |
        grep -Eq ':8080[[:space:]]'; then

        log \
            "Wings Port    : 8080 LISTENING"

    else

        wings_warn \
            "Wings Port    : 8080 NOT LISTENING"

    fi

    # --------------------------------------------------------
    # SFTP
    # --------------------------------------------------------

    if ss -lnt 2>/dev/null |
        grep -Eq ':2022[[:space:]]'; then

        log \
            "SFTP Port     : 2022 LISTENING"

    else

        wings_warn \
            "SFTP Port     : 2022 NOT LISTENING"

    fi

    echo

    echo "Node Domain:"
    echo "  $NODE_DOMAIN"

    echo

    echo "Panel:"
    echo "  $PANEL_URL"

    echo

    echo "Node ID:"
    echo "  $NODE_ID"

    echo

    echo "Config:"
    echo "  $WINGS_CONFIG"

    echo

    echo "Service:"
    echo "  $WINGS_SERVICE"

    echo

    echo "================================================"
    echo

    if systemctl is-active --quiet wings; then

        log \
            "Wings installation selesai."

        return 0

    fi

    wings_fail \
        "Wings installation belum berhasil."

    return 1
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

    echo "Installer ini akan:"
    echo
    echo "  1. Memastikan dependency Wings"
    echo "  2. Memastikan Docker"
    echo "  3. Menginstall Wings"
    echo "  4. Meminta Panel URL"
    echo "  5. Meminta Node ID"
    echo "  6. Meminta Domain Node"
    echo "  7. Meminta konfigurasi YAML Wings"
    echo "  8. Memeriksa SSL"
    echo "  9. Membuat systemd service"
    echo " 10. Menjalankan Wings"
    echo " 11. Memeriksa port Wings"
    echo " 12. Menguji koneksi Node"
    echo " 13. Memeriksa komunikasi Panel"
    echo
    echo "================================================"
    echo

    # ========================================================
    # DEPENDENCIES
    # ========================================================

    install_wings_dependencies

    # ========================================================
    # DOCKER
    # ========================================================

    ensure_docker

    # ========================================================
    # WINGS BINARY
    # ========================================================

    install_wings_binary

    # ========================================================
    # INPUT
    # ========================================================

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

    # ========================================================
    # DNS
    # ========================================================

    if ! check_node_dns; then

        echo

        wings_warn \
            "DNS Node belum dapat di-resolve."

        echo

        local confirm_dns=""

        read -r \
            -p "Tetap lanjut? [y/N]: " \
            confirm_dns

        if [[ ! "$confirm_dns" =~ ^[Yy]$ ]]; then

            wings_fail \
                "Instalasi dibatalkan karena DNS Node."

            return 1
        fi
    fi

    # ========================================================
    # CONFIGURATION
    # ========================================================

    read_wings_configuration

    # ========================================================
    # SSL
    # ========================================================

    check_node_ssl

    # ========================================================
    # FIREWALL
    # ========================================================

    configure_firewall

    # ========================================================
    # VALIDATE
    # ========================================================

    validate_wings_config

    # ========================================================
    # SYSTEMD
    # ========================================================

    create_wings_service

    # ========================================================
    # START
    # ========================================================

    start_wings

    # ========================================================
    # PORT CHECK
    # ========================================================

    wait_for_port 8080 || true

    wait_for_port 2022 || true

    # ========================================================
    # HTTP TEST
    # ========================================================

    test_node_http || true

    # ========================================================
    # PANEL COMMUNICATION
    # ========================================================

    verify_wings_logs

    # ========================================================
    # FINAL
    # ========================================================

    final_status
}

# ============================================================
# START
# ============================================================

install_wings
