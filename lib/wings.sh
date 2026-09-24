#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ============================================================
# LOAD COMMON LIBRARY
# ============================================================

if [[ ! -f "$BASE_DIR/lib/common.sh" ]]; then
    echo "[ERROR] lib/common.sh tidak ditemukan."
    exit 1
fi

source "$BASE_DIR/lib/common.sh"

# ============================================================
# PUTZOFFICIAL WINGS INSTALLER
# ============================================================
#
# Fitur:
#
#   - Install dependency Wings
#   - Install Docker jika diperlukan
#   - Install Pterodactyl Wings
#   - Input Panel URL
#   - Input Node ID
#   - Input Node Domain
#   - Validasi DNS
#   - Deteksi public IPv4 VPS
#   - Generate SSL Let's Encrypt otomatis
#   - Support Nginx existing
#   - Backup config Wings lama
#   - Input config dari Pterodactyl Panel
#   - Otomatis memperbaiki path SSL
#   - Membuat systemd service
#   - Enable Wings
#   - Start Wings
#   - Check port 8080
#   - Check port 2022
#   - Check koneksi Node
#   - Menampilkan log apabila Wings gagal
#
# Target:
#   Ubuntu
#   x86_64 / amd64
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

CONFIG_TMP=""
NGINX_WAS_ACTIVE="false"

# ============================================================
# ERROR HANDLER
# ============================================================

wings_fail() {

    error "$*" >&2

    return 1
}

# ============================================================
# CLEANUP
# ============================================================

cleanup_wings_installer() {

    if [[ -n "${CONFIG_TMP:-}" ]]; then
        rm -f "$CONFIG_TMP" 2>/dev/null || true
    fi

    # Jangan biarkan Nginx mati apabila installer gagal.
    if [[ "${NGINX_WAS_ACTIVE:-false}" == "true" ]]; then

        if command_exists nginx 2>/dev/null; then

            if ! systemctl is-active --quiet nginx 2>/dev/null; then

                systemctl start nginx 2>/dev/null || true

            fi

        fi
    fi
}

trap cleanup_wings_installer EXIT

# ============================================================
# COMMAND CHECK
# ============================================================

require_command() {

    local command_name="$1"

    if ! command_exists "$command_name"; then

        wings_fail \
            "Command '$command_name' tidak ditemukan."

        return 1
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
        certbot

    require_command curl
    require_command openssl
    require_command jq
    require_command ss
    require_command certbot

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

            return 0

        fi

        wings_fail "Docker gagal dijalankan."

        return 1
    fi

    info "Docker belum tersedia."
    info "Menjalankan installer Docker..."

    if [[ ! -f "$BASE_DIR/lib/docker.sh" ]]; then

        wings_fail \
            "File lib/docker.sh tidak ditemukan."

        return 1
    fi

    bash "$BASE_DIR/lib/docker.sh"

    if ! command_exists docker; then

        wings_fail \
            "Docker gagal diinstall."

        return 1
    fi

    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker

    sleep 2

    if ! systemctl is-active --quiet docker; then

        wings_fail \
            "Docker tidak aktif."

        return 1
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
    # Existing binary
    # --------------------------------------------------------

    if [[ -x "$WINGS_BINARY" ]]; then

        info "Wings binary sudah tersedia."

        if "$WINGS_BINARY" version >/dev/null 2>&1; then

            log "Wings binary: OK"

            "$WINGS_BINARY" version 2>/dev/null || true

            return 0
        fi

        warn "Binary Wings tidak dapat dijalankan."
        warn "Mengunduh ulang binary Wings..."
    fi

    # --------------------------------------------------------
    # Download
    # --------------------------------------------------------

    info "Mengunduh Pterodactyl Wings v${WINGS_VERSION}..."

    local download_tmp

    download_tmp="/tmp/wings-linux-amd64.$$"

    rm -f "$download_tmp"

    curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --connect-timeout 15 \
        --max-time 300 \
        "$WINGS_DOWNLOAD_URL" \
        -o "$download_tmp"

    if [[ ! -s "$download_tmp" ]]; then

        rm -f "$download_tmp"

        wings_fail \
            "Download Wings kosong."

        return 1
    fi

    chmod 0755 "$download_tmp"

    if ! "$download_tmp" version >/dev/null 2>&1; then

        rm -f "$download_tmp"

        wings_fail \
            "Binary Wings hasil download tidak valid."

        return 1
    fi

    install \
        -m 0755 \
        "$download_tmp" \
        "$WINGS_BINARY"

    rm -f "$download_tmp"

    if [[ ! -x "$WINGS_BINARY" ]]; then

        wings_fail \
            "Wings binary gagal dipasang."

        return 1
    fi

    log "Wings berhasil diinstall."

    "$WINGS_BINARY" version 2>/dev/null || true
}

# ============================================================
# PANEL URL
#
# IMPORTANT:
# Semua output selain nilai final dikirim ke STDERR.
#
# Karena dipanggil:
#
# PANEL_URL="$(ask_panel_url)"
#
# maka hanya URL yang boleh masuk ke stdout.
# ============================================================

ask_panel_url() {

    local value=""

    while true; do

        echo >&2

        read -r -p \
            "Panel URL, contoh https://panel.example.com: " \
            value

        value="${value//$'\r'/}"

        # Trim kiri
        value="${value#"${value%%[![:space:]]*}"}"

        # Trim kanan
        value="${value%"${value##*[![:space:]]}"}"

        # Remove trailing slash
        value="${value%/}"

        if [[ -z "$value" ]]; then

            warn \
                "Panel URL tidak boleh kosong." >&2

            continue
        fi

        if [[ "$value" != http://* &&
              "$value" != https://* ]]; then

            warn \
                "Panel URL harus diawali http:// atau https://." >&2

            continue
        fi

        # HANYA nilai final ke stdout.
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

        echo >&2

        read -r -p \
            "Node ID, contoh 1: " \
            value

        value="${value//$'\r'/}"

        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        if [[ "$value" =~ ^[0-9]+$ ]] &&
           [[ "$value" -gt 0 ]]; then

            printf '%s' "$value"

            return 0
        fi

        warn \
            "Node ID harus berupa angka lebih dari 0." >&2
    done
}

# ============================================================
# NODE DOMAIN
# ============================================================

ask_node_domain() {

    local value=""

    while true; do

        echo >&2

        read -r -p \
            "Domain Node/FQDN, contoh node.example.com: " \
            value

        value="${value//$'\r'/}"

        # Trim
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        # Remove protocol
        value="${value#http://}"
        value="${value#https://}"

        # Remove path
        value="${value%%/*}"

        # Remove port
        value="${value%%:*}"

        # Trim lagi
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        if [[ -z "$value" ]]; then

            warn \
                "Domain Node tidak boleh kosong." >&2

            continue
        fi

        if [[ "$value" != *.* ]]; then

            warn \
                "Masukkan domain/FQDN yang valid." >&2

            continue
        fi

        # Validasi karakter dasar hostname.
        if [[ ! "$value" =~ ^[A-Za-z0-9.-]+$ ]]; then

            warn \
                "Domain mengandung karakter yang tidak valid." >&2

            continue
        fi

        # Jangan izinkan domain dimulai/diakhiri titik.
        if [[ "$value" == .* ||
              "$value" == *. ]]; then

            warn \
                "Format domain tidak valid." >&2

            continue
        fi

        # HANYA domain masuk stdout.
        printf '%s' "$value"

        return 0
    done
}

# ============================================================
# PUBLIC IPV4
# ============================================================

get_public_ipv4() {

    local ip=""

    # Provider pertama
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

    if [[ -n "$ip" ]]; then

        printf '%s' "$ip"

        return 0
    fi

    # Provider kedua
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

    printf '%s' "$ip"
}

# ============================================================
# DNS RESOLUTION
# ============================================================

resolve_node_ipv4() {

    local domain="$1"

    local ip=""

    # getent
    ip="$(
        getent ahostsv4 "$domain" 2>/dev/null |
        awk 'NR==1 {print $1}' ||
        true
    )"

    if [[ -n "$ip" ]]; then

        printf '%s' "$ip"

        return 0
    fi

    # dig
    ip="$(
        dig +short A "$domain" 2>/dev/null |
        grep -E \
            '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' |
        head -n1 ||
        true
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

    node_ip="$(resolve_node_ipv4 "$NODE_DOMAIN")"

    if [[ -z "$node_ip" ]]; then

        warn "Domain $NODE_DOMAIN belum dapat di-resolve."

        return 1
    fi

    server_ip="$(get_public_ipv4)"

    if [[ -z "$server_ip" ]]; then

        warn \
            "Public IPv4 VPS tidak dapat diketahui."

        return 1
    fi

    info "DNS Node : $node_ip"
    info "VPS IP   : $server_ip"

    if [[ "$node_ip" != "$server_ip" ]]; then

        warn \
            "DNS Node belum mengarah ke public IP VPS ini."

        return 1
    fi

    log "DNS Node: OK"

    return 0
}

# ============================================================
# SHOW DNS HELP
# ============================================================

show_dns_help() {

    echo
    echo "================================================"
    echo "                 DNS NODE"
    echo "================================================"
    echo
    echo "Buat DNS record berikut:"
    echo
    echo "Type  : A"
    echo "Name  : node / hostname Node"
    echo "Value : $(get_public_ipv4)"
    echo
    echo "Contoh:"
    echo
    echo "node.xenpanelfree.putzoffc.biz.id"
    echo "        -> $(get_public_ipv4)"
    echo
    echo "Jika memakai Cloudflare:"
    echo
    echo "Untuk proses SSL standalone, disarankan"
    echo "gunakan DNS Only terlebih dahulu."
    echo
    echo "================================================"
    echo
}

# ============================================================
# CHECK PORT 80
# ============================================================

check_port_80() {

    if ss -ltn 2>/dev/null |
        grep -Eq ':80[[:space:]]'; then

        return 1
    fi

    return 0
}

# ============================================================
# STOP NGINX
# ============================================================

stop_nginx_temporarily() {

    if ! command_exists nginx; then
        return 0
    fi

    if ! systemctl is-active --quiet nginx 2>/dev/null; then
        return 0
    fi

    NGINX_WAS_ACTIVE="true"

    info \
        "Nginx aktif dan memakai port 80."

    info \
        "Menghentikan Nginx sementara untuk Let's Encrypt..."

    systemctl stop nginx

    sleep 2

    if systemctl is-active --quiet nginx 2>/dev/null; then

        wings_fail \
            "Nginx gagal dihentikan."

        return 1
    fi

    log \
        "Nginx berhasil dihentikan sementara."
}

# ============================================================
# RESTORE NGINX
# ============================================================

restore_nginx() {

    if [[ "$NGINX_WAS_ACTIVE" != "true" ]]; then
        return 0
    fi

    if ! command_exists nginx; then
        return 0
    fi

    info \
        "Menjalankan kembali Nginx..."

    systemctl start nginx

    sleep 2

    if systemctl is-active --quiet nginx; then

        log "Nginx: ACTIVE"

        NGINX_WAS_ACTIVE="false"

        return 0
    fi

    warn \
        "Nginx gagal aktif kembali."

    warn \
        "Periksa: systemctl status nginx"

    return 1
}

# ============================================================
# SSL EXISTING CHECK
# ============================================================

check_existing_ssl() {

    SSL_CERT="/etc/letsencrypt/live/$NODE_DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$NODE_DOMAIN/privkey.pem"

    if [[ -f "$SSL_CERT" &&
          -f "$SSL_KEY" ]]; then

        info "Certificate Node sudah tersedia."

        if openssl x509 \
            -in "$SSL_CERT" \
            -noout \
            >/dev/null 2>&1; then

            log "Existing SSL certificate: VALID"

            return 0
        fi

        warn \
            "Certificate ditemukan tetapi tidak valid."

        return 1
    fi

    return 1
}

# ============================================================
# SSL AUTOMATIC
# ============================================================

setup_node_ssl() {

    info "Menyiapkan SSL Node otomatis..."

    SSL_CERT="/etc/letsencrypt/live/$NODE_DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$NODE_DOMAIN/privkey.pem"

    mkdir -p /etc/letsencrypt

    # --------------------------------------------------------
    # Existing certificate
    # --------------------------------------------------------

    if check_existing_ssl; then

        log "SSL Node: menggunakan certificate existing."

        return 0
    fi

    # --------------------------------------------------------
    # Check Certbot
    # --------------------------------------------------------

    if ! command_exists certbot; then

        info "Certbot belum tersedia."
        info "Menginstall Certbot..."

        apt_install certbot

    fi

    if ! command_exists certbot; then

        wings_fail \
            "Certbot gagal diinstall."

        return 1
    fi

    log "Certbot: OK"

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    if ! check_node_dns; then

        echo >&2

        show_dns_help >&2

        wings_fail \
            "DNS Node belum valid. Perbaiki DNS terlebih dahulu."

        return 1
    fi

    # --------------------------------------------------------
    # Port 80
    # --------------------------------------------------------

    if ! check_port_80; then

        if command_exists nginx &&
           systemctl is-active --quiet nginx 2>/dev/null; then

            stop_nginx_temporarily

        else

            echo >&2

            ss -ltnp 2>/dev/null |
                grep -E ':80[[:space:]]' ||
                true

            wings_fail \
                "Port 80 sedang digunakan service lain."

            return 1
        fi
    fi

    # --------------------------------------------------------
    # Request certificate
    # --------------------------------------------------------

    info \
        "Meminta certificate Let's Encrypt untuk:"
    info \
        "$NODE_DOMAIN"

    local certbot_result=0

    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --keep-until-expiring \
        --register-unsafely-without-email \
        --preferred-challenges http \
        -d "$NODE_DOMAIN" \
        || certbot_result=$?

    # --------------------------------------------------------
    # Restore Nginx immediately
    # --------------------------------------------------------

    if [[ "$NGINX_WAS_ACTIVE" == "true" ]]; then

        restore_nginx || true

    fi

    # --------------------------------------------------------
    # Certbot result
    # --------------------------------------------------------

    if [[ "$certbot_result" -ne 0 ]]; then

        echo >&2

        warn \
            "Let's Encrypt gagal menerbitkan certificate." >&2

        echo >&2

        echo "Kemungkinan penyebab:" >&2
        echo >&2
        echo "  1. DNS Node belum benar-benar mengarah ke VPS." >&2
        echo "  2. Port 80 diblokir firewall/provider." >&2
        echo "  3. Cloudflare Proxy mengganggu validasi." >&2
        echo "  4. DNS masih dalam proses propagasi." >&2
        echo "  5. Domain tidak dapat diakses dari internet." >&2
        echo >&2

        wings_fail \
            "SSL Node gagal dibuat."

        return 1
    fi

    # --------------------------------------------------------
    # Verify files
    # --------------------------------------------------------

    if [[ ! -f "$SSL_CERT" ]]; then

        wings_fail \
            "Certificate tidak ditemukan setelah Certbot selesai."

        return 1
    fi

    if [[ ! -f "$SSL_KEY" ]]; then

        wings_fail \
            "Private key tidak ditemukan setelah Certbot selesai."

        return 1
    fi

    # --------------------------------------------------------
    # Verify certificate
    # --------------------------------------------------------

    if ! openssl x509 \
        -in "$SSL_CERT" \
        -noout \
        >/dev/null 2>&1; then

        wings_fail \
            "Certificate SSL tidak valid."

        return 1
    fi

    chmod 0644 "$SSL_CERT"
    chmod 0600 "$SSL_KEY"

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
# CONFIG BACKUP
# ============================================================

backup_existing_wings_config() {

    if [[ ! -f "$WINGS_CONFIG" ]]; then
        return 0
    fi

    local backup_file

    backup_file="$WINGS_CONFIG.backup.$(date +%Y%m%d-%H%M%S)"

    cp \
        "$WINGS_CONFIG" \
        "$backup_file"

    chmod 0600 "$backup_file"

    log \
        "Backup config Wings dibuat:"
    log \
        "$backup_file"
}

# ============================================================
# READ WINGS CONFIGURATION
# ============================================================
#
# User copy dari:
#
# Admin Panel
# -> Nodes
# -> pilih Node
# -> Configuration
#
# Kemudian paste SELURUH YAML.
#
# Terakhir:
#
# END_CONFIG
#
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
    echo "-> Nodes"
    echo "-> pilih Node"
    echo "-> Configuration"
    echo
    echo "Copy SELURUH konfigurasi YAML Wings."
    echo
    echo "Contoh:"
    echo
    echo "debug: false"
    echo "uuid: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    echo "token_id: xxxxxxxx"
    echo "token: xxxxxxxxxxxxxxxxx"
    echo "api:"
    echo "  host: 0.0.0.0"
    echo "  port: 8080"
    echo "  ssl:"
    echo "    enabled: true"
    echo "    cert: /etc/letsencrypt/live/node.example.com/fullchain.pem"
    echo "    key: /etc/letsencrypt/live/node.example.com/privkey.pem"
    echo "system:"
    echo "  data: /var/lib/pterodactyl/volumes"
    echo "  sftp:"
    echo "    bind_port: 2022"
    echo "allowed_mounts: []"
    echo "remote: 'https://panel.example.com'"
    echo
    echo "------------------------------------------------"
    echo
    echo "Paste konfigurasi sekarang."
    echo
    echo "Setelah selesai, tulis:"
    echo
    echo "END_CONFIG"
    echo
    echo "------------------------------------------------"
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

        wings_fail \
            "Konfigurasi Wings kosong."

        return 1
    fi

    chmod 0600 "$CONFIG_TMP"

    # --------------------------------------------------------
    # Required fields
    # --------------------------------------------------------

    info "Memeriksa struktur konfigurasi..."

    if ! grep -Eq '^uuid:[[:space:]]*[^[:space:]]+' "$CONFIG_TMP"; then

        wings_fail \
            "Field uuid tidak ditemukan."

        return 1
    fi

    if ! grep -Eq '^token_id:[[:space:]]*[^[:space:]]+' "$CONFIG_TMP"; then

        wings_fail \
            "Field token_id tidak ditemukan."

        return 1
    fi

    if ! grep -Eq '^token:[[:space:]]*[^[:space:]]+' "$CONFIG_TMP"; then

        wings_fail \
            "Field token tidak ditemukan."

        return 1
    fi

    if ! grep -Eq '^api:[[:space:]]*$' "$CONFIG_TMP"; then

        wings_fail \
            "Section api tidak ditemukan."

        return 1
    fi

    if ! grep -Eq '^remote:[[:space:]]*[^[:space:]]+' "$CONFIG_TMP"; then

        wings_fail \
            "Field remote tidak ditemukan."

        return 1
    fi

    # --------------------------------------------------------
    # Extract values
    # --------------------------------------------------------

    local uuid=""
    local token_id=""
    local remote=""
    local api_host=""
    local api_port=""
    local sftp_port=""

    uuid="$(
        sed -n \
            's/^uuid:[[:space:]]*//p' \
            "$CONFIG_TMP" |
        head -n1 |
        tr -d "'\"" ||
        true
    )"

    token_id="$(
        sed -n \
            's/^token_id:[[:space:]]*//p' \
            "$CONFIG_TMP" |
        head -n1 |
        tr -d "'\"" ||
        true
    )"

    remote="$(
        sed -n \
            's/^remote:[[:space:]]*//p' \
            "$CONFIG_TMP" |
        head -n1 |
        tr -d "'\"" ||
        true
    )"

    api_host="$(
        awk '
            /^api:[[:space:]]*$/ {
                inside=1
                next
            }

            inside && /^  host:[[:space:]]*/ {
                sub(/^  host:[[:space:]]*/, "")
                print
                exit
            }

            inside && /^[^[:space:]]/ {
                exit
            }
        ' "$CONFIG_TMP" |
        tr -d "'\"" ||
        true
    )"

    api_port="$(
        awk '
            /^api:[[:space:]]*$/ {
                inside=1
                next
            }

            inside && /^  port:[[:space:]]*/ {
                sub(/^  port:[[:space:]]*/, "")
                print
                exit
            }

            inside && /^[^[:space:]]/ {
                exit
            }
        ' "$CONFIG_TMP" |
        tr -d "'\"" ||
        true
    )"

    sftp_port="$(
        awk '
            /^  sftp:[[:space:]]*$/ {
                inside=1
                next
            }

            inside && /^    bind_port:[[:space:]]*/ {
                sub(/^    bind_port:[[:space:]]*/, "")
                print
                exit
            }

            inside && /^  [^[:space:]]/ {
                exit
            }
        ' "$CONFIG_TMP" |
        tr -d "'\"" ||
        true
    )"

    # --------------------------------------------------------
    # Check extracted values
    # --------------------------------------------------------

    if [[ -z "$uuid" ]]; then

        wings_fail "UUID kosong."

        return 1
    fi

    if [[ -z "$token_id" ]]; then

        wings_fail "Token ID kosong."

        return 1
    fi

    if [[ -z "$remote" ]]; then

        wings_fail "Remote kosong."

        return 1
    fi

    if [[ -z "$api_host" ]]; then

        wings_fail "api.host tidak ditemukan."

        return 1
    fi

    if [[ -z "$api_port" ]]; then

        wings_fail "api.port tidak ditemukan."

        return 1
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
        warn \
            "Remote pada konfigurasi berbeda dengan Panel URL."

        echo
        echo "Panel URL : $normalized_panel"
        echo "Config    : $normalized_remote"
        echo

        read -r -p \
            "Tetap gunakan konfigurasi ini? [y/N]: " \
            confirm

        confirm="${confirm,,}"

        if [[ "$confirm" != "y" &&
              "$confirm" != "yes" ]]; then

            wings_fail \
                "Instalasi dibatalkan karena remote berbeda."

            return 1
        fi

    else

        log "Panel remote: OK"
    fi

    # --------------------------------------------------------
    # SSL Detection
    # --------------------------------------------------------

    local ssl_enabled=""

    ssl_enabled="$(
        awk '
            /^api:[[:space:]]*$/ {
                api=1
                next
            }

            api && /^  ssl:[[:space:]]*$/ {
                ssl=1
                next
            }

            ssl && /^    enabled:[[:space:]]*/ {
                sub(/^    enabled:[[:space:]]*/, "")
                print
                exit
            }

            ssl && /^  [^[:space:]]/ {
                exit
            }

            api && /^[^[:space:]]/ {
                exit
            }
        ' "$CONFIG_TMP" |
        tr -d "'\"" |
        tr '[:upper:]' '[:lower:]' ||
        true
    )"

    # Jika format Panel berbeda tetapi ada enabled true di bawah api.
    if [[ "$ssl_enabled" != "true" ]]; then

        ssl_enabled="$(
            awk '
                /^api:[[:space:]]*$/ {
                    api=1
                    next
                }

                api && /^  ssl:/ {
                    ssl=1
                    next
                }

                ssl && /^    enabled:/ {
                    sub(/^    enabled:[[:space:]]*/, "")
                    print
                    exit
                }

                api && /^[^[:space:]]/ {
                    exit
                }
            ' "$CONFIG_TMP" |
            tr -d "'\"" |
            tr '[:upper:]' '[:lower:]' ||
            true
        )"

    fi

    if [[ "$ssl_enabled" != "true" ]]; then

        echo
        warn "SSL pada konfigurasi Node tidak aktif."
        echo
        echo "Untuk Node HTTPS, aktifkan SSL pada:"
        echo
        echo "Admin Panel -> Nodes -> Configuration"
        echo
        echo "Pastikan:"
        echo
        echo "api:"
        echo "  ssl:"
        echo "    enabled: true"
        echo

        wings_fail \
            "SSL Wings tidak aktif."

        return 1
    fi

    info "SSL Wings: ENABLED"

    # --------------------------------------------------------
    # Automatically replace SSL paths
    # --------------------------------------------------------

    if [[ ! -f "$SSL_CERT" ]]; then

        wings_fail \
            "Certificate belum tersedia: $SSL_CERT"

        return 1
    fi

    if [[ ! -f "$SSL_KEY" ]]; then

        wings_fail \
            "Private key belum tersedia: $SSL_KEY"

        return 1
    fi

    # cert:
    if grep -Eq '^[[:space:]]+cert:[[:space:]]*' "$CONFIG_TMP"; then

        sed -i -E \
            "s#^([[:space:]]+cert:).*#\1 ${SSL_CERT}#" \
            "$CONFIG_TMP"

    else

        # Jika cert tidak ada, masukkan setelah enabled.
        sed -i -E \
            "/^[[:space:]]+enabled:[[:space:]]*true[[:space:]]*$/a\\    cert: ${SSL_CERT}" \
            "$CONFIG_TMP"
    fi

    # key:
    if grep -Eq '^[[:space:]]+key:[[:space:]]*' "$CONFIG_TMP"; then

        sed -i -E \
            "s#^([[:space:]]+key:).*#\1 ${SSL_KEY}#" \
            "$CONFIG_TMP"

    else

        sed -i -E \
            "/^[[:space:]]+cert:[[:space:]]*/a\\    key: ${SSL_KEY}" \
            "$CONFIG_TMP"
    fi

    # --------------------------------------------------------
    # Validate SSL paths in config
    # --------------------------------------------------------

    if ! grep -Fq "$SSL_CERT" "$CONFIG_TMP"; then

        wings_fail \
            "Path certificate gagal dimasukkan ke config."

        return 1
    fi

    if ! grep -Fq "$SSL_KEY" "$CONFIG_TMP"; then

        wings_fail \
            "Path private key gagal dimasukkan ke config."

        return 1
    fi

    # --------------------------------------------------------
    # Backup existing config
    # --------------------------------------------------------

    backup_existing_wings_config

    # --------------------------------------------------------
    # Install config
    # --------------------------------------------------------

    mkdir -p /etc/pterodactyl

    install \
        -m 0600 \
        "$CONFIG_TMP" \
        "$WINGS_CONFIG"

    if [[ ! -s "$WINGS_CONFIG" ]]; then

        wings_fail \
            "config.yml gagal dibuat."

        return 1
    fi

    chmod 0600 "$WINGS_CONFIG"

    log "Wings config: OK"

    # --------------------------------------------------------
    # Safe display
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
    info "SSL Cert  : $SSL_CERT"
    info "SSL Key   : $SSL_KEY"
    echo

    warn "Token rahasia tidak ditampilkan."
}

# ============================================================
# CHECK NODE SSL
# ============================================================

check_node_ssl() {

    info "Memeriksa SSL Node..."

    if [[ ! -f "$SSL_CERT" ]]; then

        wings_fail \
            "Certificate tidak ditemukan: $SSL_CERT"

        return 1
    fi

    if [[ ! -f "$SSL_KEY" ]]; then

        wings_fail \
            "Private key tidak ditemukan: $SSL_KEY"

        return 1
    fi

    if ! openssl x509 \
        -in "$SSL_CERT" \
        -noout \
        >/dev/null 2>&1; then

        wings_fail \
            "Certificate SSL tidak valid."

        return 1
    fi

    # Check private key readable
    if [[ ! -r "$SSL_KEY" ]]; then

        wings_fail \
            "Private key tidak dapat dibaca."

        return 1
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
        warn "UFW tidak diaktifkan otomatis."

        return 0
    fi

    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
    ufw allow 8080/tcp >/dev/null 2>&1 || true
    ufw allow 2022/tcp >/dev/null 2>&1 || true

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

        return 1
    fi

    if ! grep -Eq '^uuid:[[:space:]]*[^[:space:]]+' \
        "$WINGS_CONFIG"; then

        wings_fail \
            "config.yml tidak memiliki uuid."

        return 1
    fi

    if ! grep -Eq '^token_id:[[:space:]]*[^[:space:]]+' \
        "$WINGS_CONFIG"; then

        wings_fail \
            "config.yml tidak memiliki token_id."

        return 1
    fi

    if ! grep -Eq '^token:[[:space:]]*[^[:space:]]+' \
        "$WINGS_CONFIG"; then

        wings_fail \
            "config.yml tidak memiliki token."

        return 1
    fi

    if ! grep -Eq '^api:[[:space:]]*$' \
        "$WINGS_CONFIG"; then

        wings_fail \
            "config.yml tidak memiliki api."

        return 1
    fi

    if ! grep -Eq '^remote:[[:space:]]*[^[:space:]]+' \
        "$WINGS_CONFIG"; then

        wings_fail \
            "config.yml tidak memiliki remote."

        return 1
    fi

    if ! grep -Fq "$SSL_CERT" \
        "$WINGS_CONFIG"; then

        wings_fail \
            "Certificate path tidak ditemukan dalam config."

        return 1
    fi

    if ! grep -Fq "$SSL_KEY" \
        "$WINGS_CONFIG"; then

        wings_fail \
            "Private key path tidak ditemukan dalam config."

        return 1
    fi

    log "Struktur config.yml: OK"
}

# ============================================================
# WINGS CONFIG TEST
# ============================================================

test_wings_binary() {

    info "Memeriksa binary Wings..."

    if ! "$WINGS_BINARY" version \
        >/dev/null 2>&1; then

        wings_fail \
            "Binary Wings tidak dapat dijalankan."

        return 1
    fi

    log "Wings binary: OK"
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

    echo "================================================"
    echo "                 WINGS LOG"
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
    echo

    wings_fail \
        "Wings gagal dijalankan."

    return 1
}

# ============================================================
# WAIT PORT
# ============================================================

wait_for_port() {

    local port="$1"

    local attempts=20
    local i=1

    info \
        "Menunggu port $port..."

    while [[ "$i" -le "$attempts" ]]; do

        if ss -lnt 2>/dev/null |
            grep -Eq ":${port}[[:space:]]"; then

            log \
                "Port $port: LISTENING"

            return 0
        fi

        sleep 1

        i=$((i + 1))
    done

    warn \
        "Port $port belum listening."

    return 1
}

# ============================================================
# NODE HTTP TEST
# ============================================================

test_node_http() {

    local url=""

    url="https://${NODE_DOMAIN}:8080/"

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
            -o /tmp/putzofficial-wings-response.$$ \
            -w '%{http_code}' \
            "$url" \
            2>/dev/null ||
            true
    )"

    rm -f \
        /tmp/putzofficial-wings-response.$$ \
        2>/dev/null ||
        true

    case "$http_code" in

        200|401|403|404)

            log \
                "Wings API reachable: HTTP $http_code"

            return 0
            ;;

        000|"")
            warn \
                "Tidak mendapatkan HTTP response dari Wings."

            return 1
            ;;

        *)
            warn \
                "Wings memberikan HTTP $http_code."

            return 1
            ;;
    esac
}

# ============================================================
# VERIFY WINGS LOGS
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

    if echo "$logs" |
        grep -qi \
        "failed to fetch"; then

        warn \
            "Wings mengalami masalah komunikasi dengan Panel."

        return 0
    fi

    warn \
        "Belum menemukan log komunikasi Panel."

    warn \
        "Periksa: journalctl -u wings -n 100 --no-pager"

    return 0
}

# ============================================================
# FINAL STATUS
# ============================================================

final_status() {

    echo
    echo "================================================"
    echo "             WINGS INSTALLATION"
    echo "================================================"
    echo

    if systemctl is-active --quiet wings; then

        log \
            "Wings Service : ACTIVE"

    else

        warn \
            "Wings Service : NOT ACTIVE"
    fi

    if ss -lnt 2>/dev/null |
        grep -Eq ':8080[[:space:]]'; then

        log \
            "Wings Port    : 8080 LISTENING"

    else

        warn \
            "Wings Port    : 8080 NOT LISTENING"
    fi

    if ss -lnt 2>/dev/null |
        grep -Eq ':2022[[:space:]]'; then

        log \
            "SFTP Port     : 2022 LISTENING"

    else

        warn \
            "SFTP Port     : 2022 NOT LISTENING"
    fi

    echo
    echo "Node Domain:"
    echo "  $NODE_DOMAIN"

    echo
    echo "Panel:"
    echo "  $PANEL_URL"

    echo
    echo "SSL Certificate:"
    echo "  $SSL_CERT"

    echo
    echo "Wings Config:"
    echo "  $WINGS_CONFIG"

    echo
    echo "Wings Service:"
    echo "  $WINGS_SERVICE"

    echo
    echo "================================================"
    echo

    if systemctl is-active --quiet wings; then

        log \
            "Wings installation selesai."

        echo
        echo "Perintah berguna:"
        echo
        echo "  systemctl status wings"
        echo "  journalctl -u wings -f"
        echo "  systemctl restart wings"
        echo

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
    echo "          PUTZOFFICIAL WINGS INSTALLER"
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
    echo "  7. Validasi DNS"
    echo "  8. Generate SSL otomatis"
    echo "  9. Input config Wings"
    echo " 10. Otomatis konfigurasi SSL"
    echo " 11. Backup config lama"
    echo " 12. Membuat systemd service"
    echo " 13. Menjalankan Wings"
    echo " 14. Check port 8080"
    echo " 15. Check SFTP 2022"
    echo " 16. Check koneksi Node"
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

    test_wings_binary

    # --------------------------------------------------------
    # Input
    #
    # Karena fungsi input sudah memperbaiki stdout/stderr,
    # hasil command substitution hanya nilai bersih.
    # --------------------------------------------------------

    PANEL_URL="$(ask_panel_url)"

    NODE_ID="$(ask_node_id)"

    NODE_DOMAIN="$(ask_node_domain)"

    export PANEL_URL
    export NODE_ID
    export NODE_DOMAIN

    # --------------------------------------------------------
    # Show node configuration
    # --------------------------------------------------------

    echo
    echo "================================================"
    echo "             NODE CONFIGURATION"
    echo "================================================"
    echo
    echo "Panel URL :"
    echo "$PANEL_URL"
    echo
    echo "Node ID   :"
    echo "$NODE_ID"
    echo
    echo "Node FQDN :"
    echo "$NODE_DOMAIN"
    echo
    echo "================================================"
    echo

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    if ! check_node_dns; then

        echo
        show_dns_help

        echo
        echo "Installer tidak akan membuat SSL"
        echo "sebelum DNS Node valid."
        echo

        wings_fail \
            "DNS Node belum valid. Perbaiki DNS terlebih dahulu."

        return 1
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
    # Systemd
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
