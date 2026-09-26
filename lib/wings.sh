#!/usr/bin/env bash

# ============================================================
# PUTZOFFICIAL WINGS INSTALLER
# SIMPLE / FULL REPLACEMENT
# ============================================================

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ============================================================
# COMMON LIBRARY
# ============================================================

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
        if [[ "$EUID" -ne 0 ]]; then
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
# CONFIG
# ============================================================

WINGS_VERSION="${WINGS_VERSION:-1.13.3}"

WINGS_BINARY="/usr/local/bin/wings"
WINGS_DIR="/etc/pterodactyl"
WINGS_CONFIG="${WINGS_DIR}/config.yml"
WINGS_SERVICE="/etc/systemd/system/wings.service"

BACKUP_DIR="/var/backups/putzofficial-wings"
LOG_DIR="/var/log/putzofficial-installer"
LOG_FILE="${LOG_DIR}/wings-install.log"

WINGS_URL="https://github.com/pterodactyl/wings/releases/download/v${WINGS_VERSION}/wings_linux_amd64"

PANEL_URL=""
NODE_ID=""
NODE_DOMAIN=""

# ============================================================
# LOG
# ============================================================

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# ERROR HANDLER
# ============================================================

on_error() {
    local code="$?"

    echo
    echo "================================================"
    echo "          PUTZOFFICIAL WINGS ERROR"
    echo "================================================"
    echo
    error "Installer gagal."
    error "Exit code : $code"
    error "Command   : ${BASH_COMMAND}"
    error "Log       : $LOG_FILE"
    echo

    if systemctl list-unit-files 2>/dev/null | grep -q '^wings.service'; then
        echo "================ WINGS STATUS ================"
        systemctl status wings --no-pager -l 2>&1 || true

        echo
        echo "================ WINGS LOG ==================="
        journalctl -u wings -n 80 --no-pager -l 2>&1 || true
    fi

    exit "$code"
}

trap on_error ERR

# ============================================================
# ROOT
# ============================================================

check_root() {
    require_root
}

# ============================================================
# ARCHITECTURE
# ============================================================

check_architecture() {
    local arch

    arch="$(uname -m)"

    case "$arch" in
        x86_64|amd64)
            log "Architecture: $arch"
            ;;
        *)
            error "Architecture $arch tidak didukung."
            error "Installer ini membutuhkan x86_64/amd64."
            exit 1
            ;;
    esac
}

# ============================================================
# DEPENDENCIES
# ============================================================

install_dependencies() {
    info "Menginstall dependency..."

    apt_install \
        ca-certificates \
        curl \
        curl \
        tar \
        unzip \
        iproute2 \
        openssl

    log "Dependency berhasil disiapkan."
}

# ============================================================
# DOCKER
# ============================================================

install_docker() {
    info "Memeriksa Docker..."

    if command_exists docker; then
        log "Docker sudah terinstall."
    else
        info "Docker belum ada. Menginstall Docker..."

        if [[ -f "$BASE_DIR/lib/docker.sh" ]]; then
            bash "$BASE_DIR/lib/docker.sh"
        else
            curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
            bash /tmp/get-docker.sh
            rm -f /tmp/get-docker.sh
        fi
    fi

    if ! command_exists docker; then
        error "Docker gagal diinstall."
        exit 1
    fi

    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker

    if ! systemctl is-active --quiet docker; then
        error "Docker tidak aktif."
        systemctl status docker --no-pager -l || true
        exit 1
    fi

    log "Docker: ACTIVE"
}

# ============================================================
# WINGS
# ============================================================

install_wings() {
    info "Memeriksa Wings..."

    mkdir -p "$WINGS_DIR"

    if [[ -x "$WINGS_BINARY" ]]; then
        if "$WINGS_BINARY" version >/dev/null 2>&1; then
            log "Wings sudah tersedia."
            "$WINGS_BINARY" version || true
            return 0
        fi

        warn "Binary Wings lama tidak valid. Menginstall ulang."
    fi

    info "Mengunduh Wings v${WINGS_VERSION}..."

    local tmp="/tmp/wings-${WINGS_VERSION}-$$"

    curl \
        -fL \
        --retry 5 \
        --retry-delay 2 \
        --connect-timeout 15 \
        --max-time 300 \
        "$WINGS_URL" \
        -o "$tmp"

    chmod 0755 "$tmp"

    if ! "$tmp" version >/dev/null 2>&1; then
        rm -f "$tmp"
        error "Binary Wings yang didownload tidak valid."
        exit 1
    fi

    install -m 0755 "$tmp" "$WINGS_BINARY"
    rm -f "$tmp"

    log "Wings berhasil diinstall."
    "$WINGS_BINARY" version || true
}

# ============================================================
# INPUT PANEL
# ============================================================

ask_panel_url() {
    local value

    while true; do
        echo
        read -r -p "Panel URL, contoh https://panel.example.com: " value

        value="${value%/}"

        if [[ "$value" == http://* || "$value" == https://* ]]; then
            printf '%s' "$value"
            return 0
        fi

        warn "Panel URL harus diawali http:// atau https://."
    done
}

# ============================================================
# INPUT NODE ID
# ============================================================

ask_node_id() {
    local value

    while true; do
        echo
        read -r -p "Node ID: " value

        if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
            printf '%s' "$value"
            return 0
        fi

        warn "Node ID harus berupa angka."
    done
}

# ============================================================
# INPUT NODE DOMAIN
# ============================================================

ask_node_domain() {
    local value

    while true; do
        echo
        read -r -p "Domain Node/FQDN: " value

        value="${value#http://}"
        value="${value#https://}"
        value="${value%%/*}"
        value="${value%%:*}"

        if [[ -n "$value" && "$value" == *.* ]]; then
            printf '%s' "$value"
            return 0
        fi

        warn "Domain Node tidak valid."
    done
}

# ============================================================
# CONFIG BACKUP
# ============================================================

backup_config() {
    if [[ ! -f "$WINGS_CONFIG" ]]; then
        return 0
    fi

    mkdir -p "$BACKUP_DIR"

    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"

    cp -a \
        "$WINGS_CONFIG" \
        "${BACKUP_DIR}/config-${timestamp}.yml"

    chmod 0600 \
        "${BACKUP_DIR}/config-${timestamp}.yml"

    log "Backup config lama dibuat."
}

# ============================================================
# CONFIG INPUT
# ============================================================

create_config() {
    local tmp

    tmp="$(mktemp)"

    chmod 0600 "$tmp"

    echo
    echo "================================================"
    echo "             WINGS CONFIGURATION"
    echo "================================================"
    echo
    echo "Buka:"
    echo
    echo "Admin Panel"
    echo "  -> Nodes"
    echo "  -> Node #${NODE_ID}"
    echo "  -> Configuration"
    echo
    echo "Copy SELURUH konfigurasi Wings."
    echo
    echo "Paste config di bawah."
    echo
    echo "Jika selesai, ketik:"
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

        printf '%s\n' "$line" >> "$tmp"
    done

    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        error "Config kosong."
        exit 1
    fi

    # Pastikan config mempunyai field dasar.
    if ! grep -q '^uuid:' "$tmp"; then
        rm -f "$tmp"
        error "Config tidak mempunyai uuid."
        exit 1
    fi

    if ! grep -q '^token_id:' "$tmp"; then
        rm -f "$tmp"
        error "Config tidak mempunyai token_id."
        exit 1
    fi

    if ! grep -q '^token:' "$tmp"; then
        rm -f "$tmp"
        error "Config tidak mempunyai token."
        exit 1
    fi

    if ! grep -q '^remote:' "$tmp"; then
        rm -f "$tmp"
        error "Config tidak mempunyai remote."
        exit 1
    fi

    backup_config

    install \
        -m 0600 \
        "$tmp" \
        "$WINGS_CONFIG"

    rm -f "$tmp"

    log "config.yml berhasil dibuat."
}

# ============================================================
# CONFIG CHECK
# ============================================================

check_config() {
    info "Memeriksa config.yml..."

    if [[ ! -s "$WINGS_CONFIG" ]]; then
        error "config.yml tidak ditemukan."
        exit 1
    fi

    local remote

    remote="$(
        sed -n \
            -E \
            's/^remote:[[:space:]]*["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\1/p' \
            "$WINGS_CONFIG" |
        head -n1
    )"

    remote="${remote%/}"

    if [[ -z "$remote" ]]; then
        error "Remote Panel tidak ditemukan di config."
        exit 1
    fi

    echo
    info "Panel dari config: $remote"
    info "Panel input       : ${PANEL_URL%/}"
    info "Node domain       : $NODE_DOMAIN"

    echo

    if [[ "$remote" != "${PANEL_URL%/}" ]]; then
        warn "Remote di config berbeda dengan Panel URL yang dimasukkan."
        warn "Pastikan kamu mengambil Configuration dari Node/Panel yang benar."
        echo
        read -r -p "Tetap lanjutkan? [y/N]: " answer

        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            error "Instalasi dibatalkan."
            exit 1
        fi
    fi

    log "Config dasar: OK"
}

# ============================================================
# SYSTEMD
# ============================================================

create_service() {
    info "Membuat systemd service..."

    cat > "$WINGS_SERVICE" <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
Documentation=https://pterodactyl.io/wings
After=docker.service
Requires=docker.service

[Service]
User=root
Group=root
WorkingDirectory=/etc/pterodactyl

ExecStart=/usr/local/bin/wings --config /etc/pterodactyl/config.yml

Restart=on-failure
RestartSec=5

LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

    chmod 0644 "$WINGS_SERVICE"

    systemctl daemon-reload
    systemctl enable wings >/dev/null

    log "systemd Wings berhasil dibuat."
}

# ============================================================
# FIREWALL
# ============================================================

configure_firewall() {
    if ! command_exists ufw; then
        return 0
    fi

    if ! ufw status 2>/dev/null | grep -q "Status: active"; then
        return 0
    fi

    info "Membuka port Wings..."

    ufw allow 8080/tcp >/dev/null 2>&1 || true
    ufw allow 2022/tcp >/dev/null 2>&1 || true

    log "Port 8080 dan 2022 diizinkan."
}

# ============================================================
# START WINGS
# ============================================================

start_wings() {
    info "Menjalankan Wings..."

    systemctl stop wings >/dev/null 2>&1 || true
    systemctl reset-failed wings >/dev/null 2>&1 || true

    systemctl start wings

    sleep 3

    if systemctl is-active --quiet wings; then
        log "Wings: ACTIVE"
        return 0
    fi

    error "Wings gagal aktif."

    echo
    echo "================ WINGS STATUS ================"
    systemctl status wings --no-pager -l || true

    echo
    echo "================ WINGS LOG ==================="
    journalctl -u wings -n 100 --no-pager -l || true

    exit 1
}

# ============================================================
# PORT CHECK
# ============================================================

check_ports() {
    info "Memeriksa port Wings..."

    if ss -lnt | grep -q ':8080 '; then
        log "Port 8080: LISTENING"
    else
        warn "Port 8080 belum listening."
    fi

    if ss -lnt | grep -q ':2022 '; then
        log "Port 2022: LISTENING"
    else
        warn "Port 2022 belum listening."
    fi
}

# ============================================================
# PANEL CONNECTION
# ============================================================

check_panel_connection() {
    info "Menunggu koneksi Wings ke Panel..."

    sleep 5

    local logs

    logs="$(
        journalctl \
            -u wings \
            -n 100 \
            --no-pager \
            2>/dev/null || true
    )"

    if echo "$logs" | grep -qi \
        "fetching list of servers from API"; then

        log "Wings berhasil menghubungi Panel."
        return 0
    fi

    if echo "$logs" | grep -qi \
        "processing servers returned by the API"; then

        log "Wings menerima response dari Panel."
        return 0
    fi

    warn "Belum menemukan log komunikasi Panel."
    warn "Cek: journalctl -u wings -n 100 --no-pager"
}

# ============================================================
# FINAL
# ============================================================

final_status() {
    echo
    echo "================================================"
    echo "       PUTZOFFICIAL WINGS INSTALLATION"
    echo "================================================"
    echo

    if systemctl is-active --quiet wings; then
        log "Wings Service : ACTIVE"
    else
        error "Wings Service : NOT ACTIVE"
        return 1
    fi

    echo
    echo "Panel:"
    echo "  $PANEL_URL"

    echo
    echo "Node:"
    echo "  $NODE_DOMAIN"

    echo
    echo "Wings:"
    echo "  v${WINGS_VERSION}"

    echo
    echo "Config:"
    echo "  $WINGS_CONFIG"

    echo
    echo "Service:"
    echo "  $WINGS_SERVICE"

    echo
    echo "Log:"
    echo "  $LOG_FILE"

    echo
    echo "================================================"
    echo
    log "Wings berhasil dijalankan."
    echo
    echo "Cek status:"
    echo "  systemctl status wings --no-pager -l"
    echo
    echo "Cek log:"
    echo "  journalctl -u wings -n 100 --no-pager"
    echo
    echo "Sekarang cek Node di Panel."
    echo "Status yang diharapkan: ONLINE 🟢"
    echo
}

# ============================================================
# MAIN
# ============================================================

install_wings() {

    check_root

    check_architecture

    echo
    echo "================================================"
    echo "       PUTZOFFICIAL WINGS INSTALLER"
    echo "================================================"
    echo
    echo "Wings Version : v${WINGS_VERSION}"
    echo
    echo "Installer:"
    echo "  - Install dependency"
    echo "  - Install/check Docker"
    echo "  - Install Wings"
    echo "  - Input Panel URL"
    echo "  - Input Node ID"
    echo "  - Input Node domain"
    echo "  - Input config dari Panel"
    echo "  - Backup config lama"
    echo "  - Create systemd"
    echo "  - Start Wings"
    echo "  - Check ports"
    echo "  - Check Panel connection"
    echo
    echo "================================================"
    echo

    install_dependencies

    install_docker

    install_wings

    PANEL_URL="$(ask_panel_url)"
    NODE_ID="$(ask_node_id)"
    NODE_DOMAIN="$(ask_node_domain)"

    echo
    echo "================================================"
    echo "             NODE INFORMATION"
    echo "================================================"
    echo
    echo "Panel URL : $PANEL_URL"
    echo "Node ID   : $NODE_ID"
    echo "Node FQDN : $NODE_DOMAIN"
    echo
    echo "================================================"
    echo

    create_config

    check_config

    configure_firewall

    create_service

    start_wings

    check_ports

    check_panel_connection

    final_status
}

# ============================================================
# RUN
# ============================================================

install_wings
