#!/usr/bin/env bash

# ============================================================
# PUTZOFFICIAL WINGS INSTALLER
# FULL REPLACEMENT
# ============================================================
#
# Target:
#   Ubuntu / Debian
#   x86_64 / amd64
#
# Features:
#   - Dependency installation
#   - Docker check/install
#   - Wings installation
#   - Panel URL
#   - Node ID
#   - Node FQDN
#   - DNS verification
#   - Multiple DNS resolver verification
#   - Public IPv4 verification
#   - Automatic Let's Encrypt SSL
#   - Existing certificate reuse
#   - Safe config backup
#   - YAML/token validation
#   - Wings config validation
#   - systemd service
#   - Correct service readiness check
#   - Port 8080/2022 verification
#   - Wings API verification
#   - Detailed failure logs
#
# ============================================================

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ------------------------------------------------------------
# Common library
# ------------------------------------------------------------

if [[ -f "$BASE_DIR/lib/common.sh" ]]; then
    # shellcheck disable=SC1091
    source "$BASE_DIR/lib/common.sh"
else

    info() {
        echo "[INFO] $*"
    }

    log() {
        echo "[OK] $*"
    }

    warn() {
        echo "[WARN] $*" >&2
    }

    error() {
        echo "[ERROR] $*" >&2
    }

    command_exists() {
        command -v "$1" >/dev/null 2>&1
    }

    require_root() {
        if [[ "${EUID}" -ne 0 ]]; then
            error "Installer harus dijalankan sebagai root."
            exit 1
        fi
    }

    apt_install() {
        export DEBIAN_FRONTEND=noninteractive

        apt-get update -y

        apt-get install -y "$@"
    }

fi

# ============================================================
# VARIABLES
# ============================================================

WINGS_VERSION="${WINGS_VERSION:-1.13.3}"

WINGS_BINARY="/usr/local/bin/wings"
WINGS_CONFIG="/etc/pterodactyl/config.yml"
WINGS_SERVICE="/etc/systemd/system/wings.service"

WINGS_LOG_DIR="/var/log/pterodactyl"
WINGS_DATA_DIR="/var/lib/pterodactyl"

INSTALL_LOG_DIR="/var/log/putzofficial-installer"
INSTALL_LOG="${INSTALL_LOG_DIR}/wings-install.log"

BACKUP_DIR="/var/backups/putzofficial-wings"

WINGS_DOWNLOAD_URL="https://github.com/pterodactyl/wings/releases/download/v${WINGS_VERSION}/wings_linux_amd64"

PANEL_URL=""
NODE_ID=""
NODE_DOMAIN=""

SSL_CERT=""
SSL_KEY=""

PUBLIC_IPV4=""

# ============================================================
# LOGGING
# ============================================================

mkdir -p "$INSTALL_LOG_DIR"

touch "$INSTALL_LOG"

chmod 0600 "$INSTALL_LOG"

exec > >(tee -a "$INSTALL_LOG") 2>&1

# ============================================================
# ERROR HANDLER
# ============================================================

on_error() {

    local exit_code="$?"

    echo
    echo "================================================"
    echo "             WINGS INSTALLER ERROR"
    echo "================================================"
    echo

    error "Installer gagal."
    error "Exit code: ${exit_code}"
    error "Log: ${INSTALL_LOG}"

    echo
    error "Perintah terakhir:"
    error "${BASH_COMMAND}"

    echo

    if [[ -f "$WINGS_CONFIG" ]]; then

        echo "================================================"
        echo "          WINGS CONFIG CHECK"
        echo "================================================"

        "$WINGS_BINARY" --debug 2>&1 || true

        echo
    fi

    if systemctl list-unit-files 2>/dev/null |
        grep -q '^wings.service'; then

        echo "================================================"
        echo "             WINGS JOURNAL"
        echo "================================================"

        journalctl \
            -u wings \
            -n 80 \
            --no-pager \
            -l 2>&1 || true

        echo
    fi

    exit "$exit_code"
}

trap on_error ERR

# ============================================================
# GENERIC HELPERS
# ============================================================

fail() {

    error "$*"

    return 1
}

require_command() {

    local cmd="$1"

    if ! command_exists "$cmd"; then
        fail "Command '$cmd' tidak ditemukan."
    fi
}

trim() {

    local value="$1"

    value="${value//$'\r'/}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "$value"
}

# ============================================================
# ARCHITECTURE
# ============================================================

check_architecture() {

    info "Memeriksa arsitektur VPS..."

    local arch

    arch="$(uname -m)"

    case "$arch" in

        x86_64|amd64)

            log "Architecture: $arch"

            ;;

        *)

            fail \
                "Arsitektur $arch belum didukung installer ini. Target: x86_64/amd64."

            ;;

    esac
}

# ============================================================
# DEPENDENCIES
# ============================================================

install_dependencies() {

    info "Memastikan dependency tersedia..."

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
        socat \
        python3

    log "Dependency: OK"
}

# ============================================================
# DOCKER
# ============================================================

ensure_docker() {

    info "Memeriksa Docker..."

    if command_exists docker; then

        log "Docker binary tersedia."

        if systemctl is-active --quiet docker; then

            log "Docker service: ACTIVE"

            return 0
        fi

        info "Docker tersedia tetapi tidak aktif."

        systemctl enable docker
        systemctl start docker

        sleep 2

        if systemctl is-active --quiet docker; then

            log "Docker service: ACTIVE"

            return 0

        fi

        fail "Docker gagal dijalankan."
    fi

    info "Docker belum tersedia."

    if [[ -f "$BASE_DIR/lib/docker.sh" ]]; then

        info "Menjalankan installer Docker internal..."

        bash "$BASE_DIR/lib/docker.sh"

    else

        info "Menginstall Docker dari repository resmi..."

        curl \
            -fsSL \
            https://get.docker.com \
            -o /tmp/get-docker.sh

        sh /tmp/get-docker.sh

        rm -f /tmp/get-docker.sh
    fi

    if ! command_exists docker; then
        fail "Docker gagal diinstall."
    fi

    systemctl enable docker
    systemctl start docker

    sleep 2

    if ! systemctl is-active --quiet docker; then
        fail "Docker tidak aktif."
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
        "$WINGS_LOG_DIR" \
        "$WINGS_DATA_DIR" \
        /tmp/pterodactyl

    if [[ -x "$WINGS_BINARY" ]]; then

        info "Wings binary sudah tersedia."

        if "$WINGS_BINARY" version >/dev/null 2>&1; then

            log "Wings binary: OK"

            "$WINGS_BINARY" version || true

            return 0
        fi

        warn "Binary Wings yang ada tidak dapat dijalankan."

    fi

    info "Mengunduh Wings v${WINGS_VERSION}..."

    local tmp_binary

    tmp_binary="/tmp/wings-${WINGS_VERSION}-$$"

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

        fail "Binary Wings hasil download tidak valid."

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

        value="$(trim "$value")"

        value="${value%/}"

        if [[ -z "$value" ]]; then

            warn "Panel URL tidak boleh kosong."

            continue
        fi

        if [[ "$value" != http://* &&
              "$value" != https://* ]]; then

            warn "Panel URL harus menggunakan http:// atau https://."

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

        value="$(trim "$value")"

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

        value="$(trim "$value")"

        value="${value#http://}"
        value="${value#https://}"

        value="${value%%/*}"
        value="${value%%:*}"

        value="$(trim "$value")"

        if [[ -z "$value" ]]; then

            warn "Domain Node tidak boleh kosong."

            continue
        fi

        if [[ "$value" != *.* ]]; then

            warn "Masukkan domain/FQDN yang valid."

            continue
        fi

        if [[ "$value" == *" "* ]]; then

            warn "Domain tidak boleh mengandung spasi."

            continue
        fi

        if [[ "$value" == .* ||
              "$value" == *. ]]; then

            warn "Format domain tidak valid."

            continue
        fi

        printf '%s' "$value"

        return 0
    done
}

# ============================================================
# PUBLIC IPv4
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

    ip="$(trim "$ip")"

    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then

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

    ip="$(trim "$ip")"

    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then

        printf '%s' "$ip"

        return 0
    fi

    return 1
}

# ============================================================
# DNS LOOKUP - IMPROVED
# ============================================================

DNS_STATUS="unknown"
DNS_RESOLVED_IPS=""

is_ipv4() {

    local ip="$1"

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

get_dns_records() {

    local domain="$1"
    local resolver="$2"

    dig \
        +short \
        A \
        "$domain" \
        "@${resolver}" \
        2>/dev/null |
        grep -E \
            '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |
        sort -u ||
        true
}

get_all_dns_ips() {

    local domain="$1"

    local records=""

    # --------------------------------------------------------
    # Cloudflare DNS
    # --------------------------------------------------------

    records="$(
        get_dns_records "$domain" "1.1.1.1"
    )"

    # --------------------------------------------------------
    # Google DNS
    # --------------------------------------------------------

    records="$(
        {
            printf '%s\n' "$records"

            get_dns_records "$domain" "8.8.8.8"

        } |
        grep -E \
            '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |
        sort -u
    )"

    printf '%s\n' "$records"
}

# ============================================================
# CLOUDFLARE DETECTION
# ============================================================

is_cloudflare_ip() {

    local ip="$1"

    # --------------------------------------------------------
    # Cloudflare IPv4 ranges
    # --------------------------------------------------------

    case "$ip" in

        173.245.*)
            return 0
            ;;

        103.*)
            # Cloudflare commonly uses 103.x.x.x
            # We don't blindly accept every 103.x address.
            ;;

        104.*)
            ;;

        172.64.*|172.65.*|172.66.*|172.67.*)
            return 0
            ;;

        141.101.*)
            return 0
            ;;

        108.162.*)
            return 0
            ;;

        162.158.*)
            return 0
            ;;

        198.41.*)
            return 0
            ;;

    esac

    return 1
}

# ============================================================
# CLOUDFLARE DNS CHECK
# ============================================================

detect_cloudflare_proxy() {

    local domain="$1"

    local ips=""

    ips="$(
        get_all_dns_ips "$domain"
    )"

    if [[ -z "$ips" ]]; then

        return 1
    fi

    local ip

    while IFS= read -r ip; do

        [[ -z "$ip" ]] && continue

        if is_cloudflare_ip "$ip"; then

            return 0
        fi

    done <<< "$ips"

    return 1
}

# ============================================================
# DNS CHECK
# ============================================================

check_node_dns() {

    info "Memeriksa DNS Node..."

    local server_ip="${PUBLIC_IPV4:-}"
    local dns_ips=""

    if [[ -z "$server_ip" ]]; then

        server_ip="$(
            get_public_ipv4 || true
        )"
    fi

    if [[ -z "$server_ip" ]]; then

        warn "Public IPv4 VPS tidak dapat diketahui."

        DNS_STATUS="unknown"

        return 1
    fi

    info "VPS IP: $server_ip"

    # --------------------------------------------------------
    # Get DNS records
    # --------------------------------------------------------

    dns_ips="$(
        get_all_dns_ips "$NODE_DOMAIN"
    )"

    dns_ips="$(trim "$dns_ips")"

    if [[ -z "$dns_ips" ]]; then

        warn "Domain $NODE_DOMAIN belum mempunyai A record yang dapat di-resolve."

        DNS_STATUS="not_found"

        return 1
    fi

    echo
    info "DNS A record yang ditemukan:"

    while IFS= read -r ip; do

        [[ -z "$ip" ]] && continue

        echo "  -> $ip"

    done <<< "$dns_ips"

    echo

    DNS_RESOLVED_IPS="$dns_ips"

    # --------------------------------------------------------
    # Direct DNS
    # --------------------------------------------------------

    if echo "$dns_ips" |
        grep -Fxq "$server_ip"; then

        DNS_STATUS="direct"

        log "DNS Node: VALID"
        log "DNS mengarah langsung ke IP VPS."

        return 0
    fi

    # --------------------------------------------------------
    # Cloudflare Proxy
    # --------------------------------------------------------

    if detect_cloudflare_proxy "$NODE_DOMAIN"; then

        DNS_STATUS="cloudflare"

        warn "Domain menggunakan Cloudflare Proxy / Orange Cloud."

        warn "DNS berhasil di-resolve, tetapi IP yang terlihat bukan IP VPS."

        echo
        echo "VPS IP:"
        echo "  $server_ip"

        echo
        echo "DNS IP:"
        echo "$dns_ips"

        echo
        warn "DNS dianggap VALID karena domain aktif melalui Cloudflare."

        echo
        warn "Untuk Wings direct connection, disarankan:"
        echo "  Cloudflare -> DNS -> node domain -> DNS only"
        echo
        warn "Port Wings 8080 dan SFTP 2022 tidak diproxy oleh Cloudflare DNS biasa."

        return 0
    fi

    # --------------------------------------------------------
    # DNS exists but points elsewhere
    # --------------------------------------------------------

    DNS_STATUS="wrong"

    warn "DNS ditemukan tetapi tidak mengarah ke IP VPS."

    echo
    echo "Expected:"
    echo "  $server_ip"

    echo
    echo "Found:"
    echo "$dns_ips"

    echo

    return 1
}

# ============================================================
# WAIT DNS
# ============================================================

wait_for_dns() {

    info "Memeriksa DNS Node..."

    # --------------------------------------------------------
    # IMPORTANT:
    # Jangan terlalu agresif melakukan retry.
    # DNS valid langsung lanjut.
    # --------------------------------------------------------

    local attempts=5
    local delay=4

    local i

    for ((i=1; i<=attempts; i++)); do

        if check_node_dns; then

            case "$DNS_STATUS" in

                direct)

                    log "DNS Node valid dan mengarah langsung ke VPS."

                    return 0
                    ;;

                cloudflare)

                    log "DNS Node valid melalui Cloudflare Proxy."

                    return 0
                    ;;

            esac

        fi

        if [[ "$DNS_STATUS" == "wrong" ]]; then

            warn "DNS memang ditemukan tetapi IP-nya berbeda."

        elif [[ "$DNS_STATUS" == "not_found" ]]; then

            warn "DNS A record belum terlihat."

        else

            warn "DNS belum dapat diverifikasi."

        fi

        if [[ "$i" -lt "$attempts" ]]; then

            warn "Percobaan ${i}/${attempts}. Menunggu ${delay} detik..."

            sleep "$delay"

        fi

    done

    echo
    echo "================================================"
    echo "                  DNS ERROR"
    echo "================================================"
    echo

    error "Domain:"
    error "$NODE_DOMAIN"

    error "VPS IP:"
    error "$PUBLIC_IPV4"

    echo
    echo "DNS yang dibutuhkan:"
    echo
    echo "Type : A"
    echo "Name : node"
    echo "Value: $PUBLIC_IPV4"
    echo

    echo "Cek manual:"
    echo
    echo "dig +short A $NODE_DOMAIN @1.1.1.1"
    echo
    echo "dig +short A $NODE_DOMAIN @8.8.8.8"
    echo

    echo "DNS yang ditemukan:"
    echo

    if [[ -n "$DNS_RESOLVED_IPS" ]]; then

        echo "$DNS_RESOLVED_IPS"

    else

        echo "(tidak ada)"
    fi

    echo
    echo "================================================"
    echo

    fail "DNS Node belum dapat diverifikasi."
}

# ============================================================
# PORT CHECK
# ============================================================

port_is_listening() {

    local port="$1"

    ss -H -ltn 2>/dev/null |
        awk -v p=":${port}" '
            $4 ~ p"$" {
                found=1
            }
            END {
                exit(found ? 0 : 1)
            }
        '
}

# ============================================================
# PORT 80
# ============================================================

check_port_80() {

    info "Memeriksa port 80..."

    if port_is_listening 80; then

        warn "Port 80 sedang digunakan."

        ss -lntp 2>/dev/null |
            grep -E '(^|:)80[[:space:]]' ||
            true

        return 1
    fi

    log "Port 80 tersedia."

    return 0
}

# ============================================================
# NGINX STATE
# ============================================================

NGINX_WAS_ACTIVE="false"

stop_nginx_temporarily() {

    if ! command_exists nginx; then
        return 0
    fi

    if systemctl is-active --quiet nginx 2>/dev/null; then

        NGINX_WAS_ACTIVE="true"

        info "Menghentikan Nginx sementara untuk Let's Encrypt..."

        systemctl stop nginx

        sleep 2

        if port_is_listening 80; then

            fail "Port 80 masih digunakan setelah Nginx dihentikan."

        fi

        log "Nginx dihentikan sementara."
    fi
}

restore_nginx() {

    if [[ "$NGINX_WAS_ACTIVE" != "true" ]]; then
        return 0
    fi

    info "Menjalankan kembali Nginx..."

    systemctl start nginx

    sleep 2

    if systemctl is-active --quiet nginx; then

        log "Nginx: ACTIVE"

    else

        warn "Nginx gagal aktif kembali."

        journalctl \
            -u nginx \
            -n 50 \
            --no-pager \
            -l ||
            true
    fi
}

# ============================================================
# SSL
# ============================================================

setup_node_ssl() {

    info "Menyiapkan SSL Node otomatis..."

    SSL_CERT="/etc/letsencrypt/live/${NODE_DOMAIN}/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/${NODE_DOMAIN}/privkey.pem"

    mkdir -p /etc/letsencrypt

    # --------------------------------------------------------
    # Existing certificate
    # --------------------------------------------------------

    if [[ -f "$SSL_CERT" &&
          -f "$SSL_KEY" ]]; then

        info "Certificate SSL sudah tersedia."

        if openssl x509 \
            -in "$SSL_CERT" \
            -noout \
            >/dev/null 2>&1; then

            log "SSL certificate valid."

            return 0

        fi

        warn "Certificate lama tidak valid."
    fi

    # --------------------------------------------------------
    # Certbot
    # --------------------------------------------------------

    if ! command_exists certbot; then

        info "Menginstall Certbot..."

        apt_install certbot

        if ! command_exists certbot; then

            fail "Certbot gagal diinstall."

        fi

    fi

    log "Certbot: tersedia."

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    if ! wait_for_dns; then

        fail \
            "SSL tidak dapat dibuat karena DNS Node belum mengarah ke VPS."
    fi

    # --------------------------------------------------------
    # Port 80
    # --------------------------------------------------------

    if port_is_listening 80; then

        if command_exists nginx &&
           systemctl is-active --quiet nginx 2>/dev/null; then

            stop_nginx_temporarily

        else

            fail \
                "Port 80 sedang digunakan service lain. Hentikan service tersebut terlebih dahulu."

        fi

    fi

    # --------------------------------------------------------
    # Certbot
    # --------------------------------------------------------

    info "Meminta certificate Let's Encrypt..."

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

    restore_nginx

    if [[ "$certbot_result" -ne 0 ]]; then

        echo
        warn "Let's Encrypt gagal."
        echo

        warn "Pastikan:"
        echo "  - DNS A $NODE_DOMAIN -> $PUBLIC_IPV4"
        echo "  - Port TCP 80 terbuka"
        echo "  - VPS dapat diakses dari internet"
        echo "  - Tidak ada firewall/provider ACL yang memblokir port 80"
        echo

        fail "SSL Node gagal dibuat."
    fi

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    if [[ ! -f "$SSL_CERT" ]]; then

        fail \
            "Certificate tidak ditemukan: $SSL_CERT"
    fi

    if [[ ! -f "$SSL_KEY" ]]; then

        fail \
            "Private key tidak ditemukan: $SSL_KEY"
    fi

    if ! openssl x509 \
        -in "$SSL_CERT" \
        -noout \
        >/dev/null 2>&1; then

        fail "Certificate SSL tidak valid."
    fi

    chmod 0644 "$SSL_CERT"
    chmod 0600 "$SSL_KEY"

    log "SSL Node: OK"

    echo
    info "SSL Cert : $SSL_CERT"
    info "SSL Key  : $SSL_KEY"
}

# ============================================================
# BACKUP CONFIG
# ============================================================

backup_existing_config() {

    if [[ ! -f "$WINGS_CONFIG" ]]; then
        return 0
    fi

    mkdir -p "$BACKUP_DIR"

    local timestamp

    timestamp="$(date '+%Y%m%d-%H%M%S')"

    local backup

    backup="${BACKUP_DIR}/config-${timestamp}.yml"

    cp -a "$WINGS_CONFIG" "$backup"

    chmod 0600 "$backup"

    log "Backup config dibuat:"
    log "$backup"
}

# ============================================================
# READ WINGS CONFIG
# ============================================================

read_wings_configuration() {

    local config_tmp

    config_tmp="$(mktemp /tmp/putzofficial-wings-config.XXXXXX.yml)"

    chmod 0600 "$config_tmp"

    rm -f "$config_tmp"

    touch "$config_tmp"

    chmod 0600 "$config_tmp"

    echo
    echo "================================================"
    echo "          WINGS CONFIGURATION"
    echo "================================================"
    echo
    echo "Di Panel:"
    echo
    echo "Admin Panel"
    echo " -> Nodes"
    echo " -> Node #${NODE_ID}"
    echo " -> Configuration"
    echo
    echo "Copy SELURUH konfigurasi Wings."
    echo
    echo "PENTING:"
    echo "Jangan kosongkan token_id atau token."
    echo "Jangan mengubah remote."
    echo "Jangan mengubah struktur YAML."
    echo
    echo "Paste seluruh config di bawah."
    echo
    echo "Setelah selesai, ketik:"
    echo
    echo "END_CONFIG"
    echo
    echo "================================================"
    echo

    local line

    while IFS= read -r line; do

        line="${line//$'\r'/}"

        if [[ "$line" == "END_CONFIG" ]]; then
            break
        fi

        printf '%s\n' "$line" >> "$config_tmp"

    done

    if [[ ! -s "$config_tmp" ]]; then

        rm -f "$config_tmp"

        fail "Konfigurasi Wings kosong."
    fi

    # --------------------------------------------------------
    # Remove accidental blank EOF only
    # --------------------------------------------------------

    sed -i \
        -e '${/^$/d;}' \
        "$config_tmp"

    # --------------------------------------------------------
    # Basic required fields
    # --------------------------------------------------------

    info "Memeriksa field konfigurasi..."

    local uuid=""
    local token_id=""
    local token=""
    local remote=""

    uuid="$(
        sed -n \
            -E \
            's/^uuid:[[:space:]]*["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\1/p' \
            "$config_tmp" |
        head -n1
    )"

    token_id="$(
        sed -n \
            -E \
            's/^token_id:[[:space:]]*["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\1/p' \
            "$config_tmp" |
        head -n1
    )"

    token="$(
        sed -n \
            -E \
            's/^token:[[:space:]]*["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\1/p' \
            "$config_tmp" |
        head -n1
    )"

    remote="$(
        sed -n \
            -E \
            's/^remote:[[:space:]]*["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\1/p' \
            "$config_tmp" |
        head -n1
    )"

    uuid="$(trim "$uuid")"
    token_id="$(trim "$token_id")"
    token="$(trim "$token")"
    remote="$(trim "$remote")"

    if [[ -z "$uuid" ]]; then

        rm -f "$config_tmp"

        fail "Field uuid kosong/tidak ditemukan."

    fi

    if [[ -z "$token_id" ]]; then

        rm -f "$config_tmp"

        fail "Field token_id kosong/tidak ditemukan."

    fi

    if [[ -z "$token" ]]; then

        rm -f "$config_tmp"

        fail "Field token kosong/tidak ditemukan."
    fi

    if [[ -z "$remote" ]]; then

        rm -f "$config_tmp"

        fail "Field remote kosong/tidak ditemukan."
    fi

    # --------------------------------------------------------
    # Remote validation
    # --------------------------------------------------------

    local normalized_remote
    local normalized_panel

    normalized_remote="${remote%/}"
    normalized_panel="${PANEL_URL%/}"

    if [[ "$normalized_remote" != "$normalized_panel" ]]; then

        echo
        warn "Remote pada config berbeda dari Panel URL."
        echo
        echo "Panel URL:"
        echo "$normalized_panel"
        echo
        echo "Config remote:"
        echo "$normalized_remote"
        echo

        rm -f "$config_tmp"

        fail \
            "Remote berbeda. Ambil ulang konfigurasi dari Node yang benar."
    fi

    log "Panel remote: OK"

    # --------------------------------------------------------
    # API SSL
    # --------------------------------------------------------

    local ssl_enabled=""

    ssl_enabled="$(
        awk '
            /^api:/ {
                api=1
                next
            }

            api && /^  ssl:/ {
                ssl=1
                next
            }

            api && ssl && /^    enabled:/ {
                sub(/^    enabled:[[:space:]]*/, "")
                print
                exit
            }

            api && /^[^[:space:]]/ {
                exit
            }
        ' "$config_tmp" |
        tr -d "'\""
    )"

    ssl_enabled="$(trim "$ssl_enabled")"

    if [[ "$ssl_enabled" != "true" ]]; then

        warn "SSL Wings pada config belum aktif."

        echo
        echo "Installer akan mengaktifkan SSL otomatis."
        echo

        if grep -qE '^    enabled:' "$config_tmp"; then

            sed -i \
                -E \
                's/^([[:space:]]{4}enabled:).*/\1 true/' \
                "$config_tmp"

        else

            # ------------------------------------------------
            # Add SSL block if missing
            # ------------------------------------------------

            local api_tmp

            api_tmp="$(mktemp)"

            awk '
                /^  port:/ {
                    print
                    print "  ssl:"
                    print "    enabled: true"
                    print "    cert: PLACEHOLDER_CERT"
                    print "    key: PLACEHOLDER_KEY"
                    next
                }
                {
                    print
                }
            ' "$config_tmp" > "$api_tmp"

            mv "$api_tmp" "$config_tmp"
        fi
    fi

    # --------------------------------------------------------
    # SSL paths
    # --------------------------------------------------------

    if grep -qE '^    cert:' "$config_tmp"; then

        sed -i \
            -E \
            "s#^([[:space:]]{4}cert:).*#\\1 ${SSL_CERT}#" \
            "$config_tmp"

    else

        fail "Field api.ssl.cert tidak ditemukan."

    fi

    if grep -qE '^    key:' "$config_tmp"; then

        sed -i \
            -E \
            "s#^([[:space:]]{4}key:).*#\\1 ${SSL_KEY}#" \
            "$config_tmp"

    else

        fail "Field api.ssl.key tidak ditemukan."

    fi

    # --------------------------------------------------------
    # Verify SSL paths
    # --------------------------------------------------------

    if [[ ! -f "$SSL_CERT" ]]; then

        fail "SSL certificate tidak ditemukan: $SSL_CERT"

    fi

    if [[ ! -f "$SSL_KEY" ]]; then

        fail "SSL private key tidak ditemukan: $SSL_KEY"

    fi

    # --------------------------------------------------------
    # Backup
    # --------------------------------------------------------

    backup_existing_config

    # --------------------------------------------------------
    # Install config
    # --------------------------------------------------------

    install \
        -m 0600 \
        "$config_tmp" \
        "$WINGS_CONFIG"

    rm -f "$config_tmp"

    chmod 0600 "$WINGS_CONFIG"

    if [[ ! -s "$WINGS_CONFIG" ]]; then

        fail "config.yml gagal dibuat."

    fi

    log "config.yml berhasil dibuat."

    # --------------------------------------------------------
    # DO NOT SHOW TOKEN
    # --------------------------------------------------------

    echo
    echo "================================================"
    echo "             CONFIGURATION CHECK"
    echo "================================================"
    echo

    info "UUID      : $uuid"
    info "Token ID  : tersedia"
    info "Token     : tersedia"
    info "Remote    : $normalized_remote"
    info "Node FQDN : $NODE_DOMAIN"
    info "SSL       : enabled"

    echo
    warn "Token rahasia tidak ditampilkan."
}

# ============================================================
# YAML / WINGS VALIDATION
# ============================================================

validate_wings_config() {

    info "Memvalidasi config.yml..."

    if [[ ! -s "$WINGS_CONFIG" ]]; then

        fail "config.yml kosong."

    fi

    # --------------------------------------------------------
    # Required fields
    # --------------------------------------------------------

    local required_fields=(
        "^uuid:"
        "^token_id:"
        "^token:"
        "^api:"
        "^system:"
        "^remote:"
    )

    local pattern

    for pattern in "${required_fields[@]}"; do

        if ! grep -qE "$pattern" "$WINGS_CONFIG"; then

            fail \
                "config.yml tidak memiliki field wajib: $pattern"

        fi

    done

    # --------------------------------------------------------
    # Token must not be empty
    # --------------------------------------------------------

    local token_id
    local token

    token_id="$(
        sed -n \
            -E \
            's/^token_id:[[:space:]]*["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\1/p' \
            "$WINGS_CONFIG" |
        head -n1 |
        tr -d '\r'
    )"

    token="$(
        sed -n \
            -E \
            's/^token:[[:space:]]*["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\1/p' \
            "$WINGS_CONFIG" |
        head -n1 |
        tr -d '\r'
    )"

    token_id="$(trim "$token_id")"
    token="$(trim "$token")"

    if [[ -z "$token_id" ]]; then

        fail "token_id kosong."

    fi

    if [[ -z "$token" ]]; then

        fail "token kosong."

    fi

    # --------------------------------------------------------
    # Remote
    # --------------------------------------------------------

    local remote

    remote="$(
        sed -n \
            -E \
            's/^remote:[[:space:]]*["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\1/p' \
            "$WINGS_CONFIG" |
        head -n1
    )"

    remote="$(trim "$remote")"

    if [[ -z "$remote" ]]; then

        fail "remote kosong."

    fi

    if [[ "$remote" != "$PANEL_URL" ]]; then

        fail \
            "remote pada config tidak sama dengan Panel URL."

    fi

    # --------------------------------------------------------
    # SSL files
    # --------------------------------------------------------

    if [[ ! -f "$SSL_CERT" ]]; then

        fail "SSL certificate tidak ditemukan."

    fi

    if [[ ! -f "$SSL_KEY" ]]; then

        fail "SSL private key tidak ditemukan."

    fi

    # --------------------------------------------------------
    # Wings itself validates YAML
    # --------------------------------------------------------

    info "Meminta Wings membaca konfigurasi..."

    if ! "$WINGS_BINARY" \
        --config "$WINGS_CONFIG" \
        --debug \
        >/tmp/putzofficial-wings-validation.log \
        2>&1; then

        echo
        error "Wings menolak konfigurasi."
        echo
        cat /tmp/putzofficial-wings-validation.log
        echo

        rm -f /tmp/putzofficial-wings-validation.log

        fail \
            "config.yml tidak valid atau token/configuration bermasalah."
    fi

    rm -f /tmp/putzofficial-wings-validation.log

    log "YAML/config Wings: VALID"
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
Wants=docker.service
After=docker.service
Requires=docker.service

[Service]
Type=simple

User=root
Group=root

WorkingDirectory=/etc/pterodactyl

ExecStart=/usr/local/bin/wings --config /etc/pterodactyl/config.yml

Restart=on-failure
RestartSec=5

TimeoutStartSec=60
TimeoutStopSec=30

LimitNOFILE=4096

KillMode=process

StandardOutput=journal
StandardError=journal

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
        warn "Installer tidak mengaktifkan UFW otomatis."

        return 0
    fi

    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
    ufw allow 8080/tcp >/dev/null 2>&1 || true
    ufw allow 2022/tcp >/dev/null 2>&1 || true

    log "Firewall: 80, 443, 8080 dan 2022 diperbolehkan."
}

# ============================================================
# STOP OLD WINGS
# ============================================================

stop_old_wings() {

    if systemctl list-unit-files 2>/dev/null |
        grep -q '^wings.service'; then

        info "Menghentikan Wings lama sementara..."

        systemctl stop wings 2>/dev/null || true

        sleep 2
    fi
}

# ============================================================
# START WINGS
# ============================================================

start_wings() {

    info "Menjalankan Wings..."

    systemctl daemon-reload

    systemctl reset-failed wings 2>/dev/null || true

    systemctl start wings

    local attempts=30

    local i

    for ((i=1; i<=attempts; i++)); do

        if systemctl is-active --quiet wings; then

            log "Wings Service: ACTIVE"

            return 0
        fi

        # If it exited, don't wait unnecessarily.
        if systemctl is-failed --quiet wings; then

            warn "Wings masuk status FAILED."

            break
        fi

        sleep 2

    done

    echo
    error "Wings benar-benar gagal aktif."

    echo
    echo "================================================"
    echo "                 WINGS LOG"
    echo "================================================"

    journalctl \
        -u wings \
        -n 100 \
        --no-pager \
        -l ||
        true

    echo

    fail "Wings gagal dijalankan."
}

# ============================================================
# WAIT PORT
# ============================================================

wait_for_port() {

    local port="$1"

    local attempts=30

    local i

    info "Menunggu port ${port}..."

    for ((i=1; i<=attempts; i++)); do

        if port_is_listening "$port"; then

            log "Port ${port}: LISTENING"

            return 0
        fi

        sleep 1

    done

    warn "Port ${port} belum listening."

    return 1
}

# ============================================================
# VERIFY WINGS PORTS
# ============================================================

verify_wings_ports() {

    info "Memeriksa port Wings..."

    if ! wait_for_port 8080; then

        echo
        error "Port 8080 tidak listening."

        journalctl \
            -u wings \
            -n 80 \
            --no-pager \
            -l ||
            true

        fail "Wings API tidak listening pada port 8080."
    fi

    if ! wait_for_port 2022; then

        echo
        error "Port 2022 tidak listening."

        journalctl \
            -u wings \
            -n 80 \
            --no-pager \
            -l ||
            true

        fail "SFTP Wings tidak listening pada port 2022."
    fi

    log "Port Wings: OK"
}

# ============================================================
# LOCAL HTTPS TEST
# ============================================================

test_local_wings() {

    info "Menguji HTTPS Wings secara lokal..."

    local result=""

    result="$(
        curl \
            -4 \
            -k \
            -sS \
            --connect-timeout 5 \
            --max-time 10 \
            -o /tmp/putzofficial-wings-response \
            -w '%{http_code}' \
            "https://127.0.0.1:8080/" \
            2>/dev/null ||
            true
    )"

    rm -f /tmp/putzofficial-wings-response

    case "$result" in

        200|401|403|404)

            log "Wings HTTPS local: HTTP ${result}"

            ;;

        "")

            fail "Tidak mendapatkan response HTTPS dari Wings."

            ;;

        *)

            warn "Wings memberikan HTTP ${result}."

            ;;
    esac
}

# ============================================================
# PUBLIC NODE TEST
# ============================================================

test_public_node() {

    info "Menguji domain Node..."

    local result=""

    result="$(
        curl \
            -4 \
            -k \
            -sS \
            --connect-timeout 10 \
            --max-time 15 \
            -o /tmp/putzofficial-public-response \
            -w '%{http_code}' \
            "https://${NODE_DOMAIN}:8080/" \
            2>/dev/null ||
            true
    )"

    rm -f /tmp/putzofficial-public-response

    case "$result" in

        200|401|403|404)

            log "Node HTTPS public: HTTP ${result}"

            ;;

        "")

            warn "Tidak mendapatkan response public Node."

            warn "Ini bisa disebabkan firewall/provider atau DNS/proxy."

            ;;

        *)

            warn "Node public memberikan HTTP ${result}."

            ;;
    esac
}

# ============================================================
# VERIFY PANEL COMMUNICATION
# ============================================================

verify_panel_communication() {

    info "Memeriksa komunikasi Wings dengan Panel..."

    sleep 3

    local logs

    logs="$(
        journalctl \
            -u wings \
            -n 120 \
            --no-pager \
            2>/dev/null ||
            true
    )"

    if echo "$logs" |
        grep -qi \
        "fetching list of servers from API"; then

        log "Wings berhasil menghubungi Panel."

        return 0
    fi

    if echo "$logs" |
        grep -qi \
        "processing servers returned by the API"; then

        log "Wings menerima response dari Panel."

        return 0
    fi

    warn "Belum menemukan log komunikasi Panel."

    warn "Periksa:"
    warn "journalctl -u wings -n 100 --no-pager"

    return 0
}

# ============================================================
# FINAL STATUS
# ============================================================

final_status() {

    echo
    echo "================================================"
    echo "          PUTZOFFICIAL WINGS STATUS"
    echo "================================================"
    echo

    if systemctl is-active --quiet wings; then

        log "Wings Service : ACTIVE"

    else

        error "Wings Service : NOT ACTIVE"

        return 1
    fi

    if port_is_listening 8080; then

        log "Wings Port    : 8080 LISTENING"

    else

        error "Wings Port    : 8080 NOT LISTENING"

        return 1
    fi

    if port_is_listening 2022; then

        log "SFTP Port     : 2022 LISTENING"

    else

        error "SFTP Port     : 2022 NOT LISTENING"

        return 1
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
    echo "SSL Private Key:"
    echo "  $SSL_KEY"

    echo
    echo "Wings Config:"
    echo "  $WINGS_CONFIG"

    echo
    echo "Wings Binary:"
    echo "  $WINGS_BINARY"

    echo
    echo "================================================"
    echo

    log "Wings installation selesai."

    echo
    echo "Perintah status:"
    echo
    echo "systemctl status wings --no-pager -l"
    echo
    echo "Perintah log:"
    echo
    echo "journalctl -u wings -n 100 --no-pager"
    echo
}

# ============================================================
# MAIN
# ============================================================

install_wings() {

    require_root

    check_architecture

    echo
    echo "================================================"
    echo "       PUTZOFFICIAL WINGS INSTALLER"
    echo "================================================"
    echo
    echo "Version:"
    echo "  Wings ${WINGS_VERSION}"
    echo
    echo "Installer akan:"
    echo
    echo "  1. Check architecture"
    echo "  2. Install dependency"
    echo "  3. Check/install Docker"
    echo "  4. Install Wings"
    echo "  5. Input Panel URL"
    echo "  6. Input Node ID"
    echo "  7. Input Node Domain"
    echo "  8. Verify DNS"
    echo "  9. Generate SSL otomatis"
    echo " 10. Backup config lama"
    echo " 11. Input config Wings"
    echo " 12. Validate token"
    echo " 13. Validate YAML"
    echo " 14. Configure SSL"
    echo " 15. Configure systemd"
    echo " 16. Configure firewall"
    echo " 17. Start Wings"
    echo " 18. Verify service"
    echo " 19. Verify port 8080"
    echo " 20. Verify port 2022"
    echo " 21. Test HTTPS"
    echo " 22. Verify Panel communication"
    echo
    echo "================================================"
    echo

    # --------------------------------------------------------
    # Dependency
    # --------------------------------------------------------

    install_dependencies

    # --------------------------------------------------------
    # Docker
    # --------------------------------------------------------

    ensure_docker

    # --------------------------------------------------------
    # Wings
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
    # Public IP
    # --------------------------------------------------------

    PUBLIC_IPV4="$(get_public_ipv4 || true)"

    if [[ -z "$PUBLIC_IPV4" ]]; then

        fail "Public IPv4 VPS tidak dapat diketahui."

    fi

    info "Public IPv4 VPS: $PUBLIC_IPV4"

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    if ! wait_for_dns; then

        echo
        echo "================================================"
        echo "                    DNS ERROR"
        echo "================================================"
        echo
        echo "Buat DNS berikut:"
        echo
        echo "Type : A"
        echo "Name : node"
        echo "Value: $PUBLIC_IPV4"
        echo
        echo "Untuk domain:"
        echo "$NODE_DOMAIN"
        echo
        echo "Pastikan hasil:"
        echo
        echo "dig +short A $NODE_DOMAIN"
        echo
        echo "menghasilkan:"
        echo "$PUBLIC_IPV4"
        echo
        echo "================================================"
        echo

        fail "DNS Node belum valid."
    fi

    # --------------------------------------------------------
    # SSL
    # --------------------------------------------------------

    setup_node_ssl

    # --------------------------------------------------------
    # Config
    # --------------------------------------------------------

    read_wings_configuration

    # --------------------------------------------------------
    # Validate
    # --------------------------------------------------------

    validate_wings_config

    # --------------------------------------------------------
    # Firewall
    # --------------------------------------------------------

    configure_firewall

    # --------------------------------------------------------
    # Existing Wings
    # --------------------------------------------------------

    stop_old_wings

    # --------------------------------------------------------
    # systemd
    # --------------------------------------------------------

    create_wings_service

    # --------------------------------------------------------
    # Start
    # --------------------------------------------------------

    start_wings

    # --------------------------------------------------------
    # Ports
    # --------------------------------------------------------

    verify_wings_ports

    # --------------------------------------------------------
    # Local test
    # --------------------------------------------------------

    test_local_wings

    # --------------------------------------------------------
    # Public test
    # --------------------------------------------------------

    test_public_node

    # --------------------------------------------------------
    # Panel communication
    # --------------------------------------------------------

    verify_panel_communication

    # --------------------------------------------------------
    # Final
    # --------------------------------------------------------

    final_status
}

# ============================================================
# START
# ============================================================

install_wings
