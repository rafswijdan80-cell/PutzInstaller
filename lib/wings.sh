#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

WINGS_BINARY="/usr/local/bin/wings"
WINGS_CONFIG="/etc/pterodactyl/config.yml"
WINGS_SERVICE="/etc/systemd/system/wings.service"

WINGS_VERSION="${WINGS_VERSION:-1.13.3}"
WINGS_DOWNLOAD_URL="https://github.com/pterodactyl/wings/releases/download/v${WINGS_VERSION}/wings_linux_amd64"


# ============================================================
# DOCKER
# ============================================================

ensure_docker() {

    info "Memeriksa Docker..."

    if command_exists docker; then

        log "Docker sudah tersedia."

    else

        info "Docker belum tersedia."
        info "Menginstall Docker..."

        if [[ -f "$BASE_DIR/lib/docker.sh" ]]; then
            bash "$BASE_DIR/lib/docker.sh"
        else
            error "File lib/docker.sh tidak ditemukan."
        fi

    fi

    if ! command_exists docker; then
        error "Docker gagal tersedia."
    fi

    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true

    if systemctl is-active --quiet docker; then
        log "Docker: OK"
    else
        error "Docker tidak aktif."
    fi
}


# ============================================================
# INSTALL WINGS BINARY
# ============================================================

install_wings_binary() {

    if [[ -x "$WINGS_BINARY" ]]; then

        info "Wings sudah terinstall."

        "$WINGS_BINARY" version || true

        return 0
    fi

    info "Mengunduh Pterodactyl Wings v${WINGS_VERSION}..."

    mkdir -p /etc/pterodactyl
    mkdir -p /var/log/pterodactyl

    local tmp_file

    tmp_file="$(mktemp)"

    if ! curl \
        --fail \
        --show-error \
        --location \
        --connect-timeout 15 \
        --retry 3 \
        --retry-delay 2 \
        "$WINGS_DOWNLOAD_URL" \
        -o "$tmp_file"; then

        rm -f "$tmp_file"

        error "Gagal mengunduh Wings."
    fi

    if [[ ! -s "$tmp_file" ]]; then

        rm -f "$tmp_file"

        error "File Wings kosong."
    fi

    install \
        -m 0755 \
        "$tmp_file" \
        "$WINGS_BINARY"

    rm -f "$tmp_file"

    if [[ ! -x "$WINGS_BINARY" ]]; then
        error "Binary Wings gagal dipasang."
    fi

    log "Wings berhasil diinstall."

    info "Versi Wings:"

    "$WINGS_BINARY" version || true
}


# ============================================================
# INPUT PANEL
# ============================================================

ask_panel_url() {

    local value=""

    while true; do

        read -r -p \
            "Panel URL, contoh https://panel.example.com: " \
            value

        value="${value%/}"

        if [[ -z "$value" ]]; then
            warn "Panel URL wajib diisi."
            continue
        fi

        if [[ ! "$value" =~ ^https?:// ]]; then
            warn "Panel URL harus diawali http:// atau https://"
            continue
        fi

        printf '%s' "$value"

        return 0
    done
}


ask_token() {

    local value=""

    while true; do

        read -r -p "Application API Token: " value

        if [[ -z "$value" ]]; then
            warn "Token wajib diisi."
            continue
        fi

        # Mencegah kesalahan seperti memasukkan command shell
        if [[ "$value" == *"sudo "* ]] ||
           [[ "$value" == *"wings configure"* ]] ||
           [[ "$value" == *"cd /etc/pterodactyl"* ]]; then

            warn "Yang dimasukkan harus TOKEN saja, bukan command."
            warn "Contoh: ptla_xxxxxxxxxxxxxxxxxxxxxxxxx"
            continue
        fi

        printf '%s' "$value"

        return 0
    done
}


ask_node_id() {

    local value=""

    while true; do

        read -r -p "Node ID: " value

        if [[ ! "$value" =~ ^[0-9]+$ ]]; then
            warn "Node ID harus berupa angka."
            continue
        fi

        if [[ "$value" == "0" ]]; then
            warn "Node ID tidak boleh 0."
            continue
        fi

        printf '%s' "$value"

        return 0
    done
}


# ============================================================
# CHECK PANEL CONNECTION
# ============================================================

check_panel_connection() {

    local panel_url="$1"

    info "Memeriksa koneksi ke Panel..."

    local http_code

    http_code="$(
        curl \
            -4 \
            -sS \
            -o /dev/null \
            --connect-timeout 10 \
            --max-time 20 \
            -w '%{http_code}' \
            "$panel_url"
    )" || {

        error "Panel tidak dapat diakses dari VPS."
    }

    case "$http_code" in

        200|301|302|403|404|405|419|401)

            log "Panel dapat diakses. HTTP $http_code"

            ;;

        *)

            error "Panel memberikan HTTP $http_code."
            ;;

    esac
}


# ============================================================
# CONFIGURE WINGS
# ============================================================

configure_wings() {

    local panel_url="$1"
    local token="$2"
    local node_id="$3"

    info "Membuat config.yml Wings..."

    mkdir -p /etc/pterodactyl

    # Backup konfigurasi lama jika ada
    if [[ -s "$WINGS_CONFIG" ]]; then

        local backup

        backup="${WINGS_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"

        cp "$WINGS_CONFIG" "$backup"

        log "Backup config lama: $backup"
    fi

    # Hapus config sementara jika ada
    rm -f "${WINGS_CONFIG}.tmp"

    info "Menghubungkan Wings ke Panel..."
    info "Node ID: $node_id"
    info "Panel: $panel_url"

    local output
    local status=0

    set +e

    output="$(
        "$WINGS_BINARY" configure \
            --panel-url "$panel_url" \
            --token "$token" \
            --node "$node_id" \
            --config-path "$WINGS_CONFIG" \
            --override \
            2>&1
    )"

    status=$?

    set -e

    echo "$output"

    if [[ "$status" -ne 0 ]]; then

        if echo "$output" | grep -qi \
            "authentication credentials provided were not valid"; then

            error "Token Wings tidak valid. Buat Application API Token baru dari Admin Pterodactyl."
        fi

        if echo "$output" | grep -qi \
            "failed to fetch configuration"; then

            error "Wings tidak dapat mengambil konfigurasi Node dari Panel."
        fi

        error "Wings gagal membuat config.yml."
    fi

    if [[ ! -s "$WINGS_CONFIG" ]]; then

        error "config.yml tidak berhasil dibuat."
    fi

    chmod 600 "$WINGS_CONFIG"

    log "config.yml berhasil dibuat."
}


# ============================================================
# VALIDATE CONFIG
# ============================================================

validate_config() {

    info "Memeriksa config.yml..."

    if [[ ! -f "$WINGS_CONFIG" ]]; then
        error "config.yml tidak ditemukan."
    fi

    if [[ ! -s "$WINGS_CONFIG" ]]; then
        error "config.yml kosong."
    fi

    # Pastikan beberapa bagian penting tersedia.
    if ! grep -qE '^uuid:' "$WINGS_CONFIG"; then
        warn "UUID Node tidak ditemukan di config.yml."
    fi

    if ! grep -qE '^token_id:' "$WINGS_CONFIG"; then
        warn "token_id tidak ditemukan di config.yml."
    fi

    if ! grep -qE '^token:' "$WINGS_CONFIG"; then
        warn "token tidak ditemukan di config.yml."
    fi

    if ! grep -qE '^remote:' "$WINGS_CONFIG"; then
        warn "remote Panel tidak ditemukan di config.yml."
    fi

    log "config.yml berhasil divalidasi."
}


# ============================================================
# SYSTEMD SERVICE
# ============================================================

create_systemd_service() {

    info "Membuat systemd service Wings..."

    cat > "$WINGS_SERVICE" <<'SERVICE'
[Unit]
Description=Pterodactyl Wings Daemon
Documentation=https://pterodactyl.io/
Wants=docker.service
After=docker.service
Requires=docker.service

[Service]
Type=simple

User=root
Group=root

WorkingDirectory=/etc/pterodactyl

ExecStart=/usr/local/bin/wings

Restart=on-failure
RestartSec=5s

LimitNOFILE=4096

PrivateTmp=false
ProtectSystem=full
ProtectHome=false

[Install]
WantedBy=multi-user.target
SERVICE

    chmod 644 "$WINGS_SERVICE"

    systemctl daemon-reload

    systemctl enable wings

    log "systemd Wings berhasil dibuat."
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

    # Jangan mengubah policy firewall.
    # Hanya membuka port yang diperlukan Wings.

    ufw allow 8080/tcp >/dev/null 2>&1 || true
    ufw allow 2022/tcp >/dev/null 2>&1 || true

    log "Port Wings: 8080/tcp"
    log "Port SFTP Wings: 2022/tcp"
}


# ============================================================
# START WINGS
# ============================================================

start_wings() {

    info "Menjalankan Wings..."

    systemctl daemon-reload

    systemctl enable wings >/dev/null 2>&1

    systemctl restart wings

    sleep 3

    if systemctl is-active --quiet wings; then

        log "Wings berhasil aktif."

    else

        warn "Wings gagal aktif."

        echo
        echo "================================================"
        echo "              WINGS ERROR LOG"
        echo "================================================"
        echo

        journalctl \
            -u wings \
            -n 80 \
            --no-pager \
            -l || true

        echo

        error "Wings gagal dijalankan."
    fi
}


# ============================================================
# PORT CHECK
# ============================================================

port_check() {

    echo
    info "Memeriksa port Wings..."

    if ss -lntp 2>/dev/null | grep -qE ':8080[[:space:]]'; then
        log "Port 8080: LISTEN"
    else
        warn "Port 8080 belum LISTEN."
    fi

    if ss -lntp 2>/dev/null | grep -qE ':2022[[:space:]]'; then
        log "Port 2022: LISTEN"
    else
        warn "Port 2022 belum LISTEN."
    fi
}


# ============================================================
# WINGS STATUS
# ============================================================

show_wings_status() {

    echo
    echo "================================================"
    echo "              WINGS STATUS"
    echo "================================================"
    echo

    systemctl status wings \
        --no-pager \
        -l || true

    echo

    echo "Config:"
    echo "  $WINGS_CONFIG"

    echo

    echo "Service:"
    echo "  $WINGS_SERVICE"

    echo
}


# ============================================================
# MAIN INSTALL
# ============================================================

install_wings() {

    info "Memulai instalasi Pterodactyl Wings..."

    # --------------------------------------------------------
    # ROOT
    # --------------------------------------------------------

    require_root

    # --------------------------------------------------------
    # DEPENDENCIES
    # --------------------------------------------------------

    ensure_docker

    # --------------------------------------------------------
    # WINGS BINARY
    # --------------------------------------------------------

    install_wings_binary

    # --------------------------------------------------------
    # INPUT NODE
    # --------------------------------------------------------

    echo
    echo "================================================"
    echo "              KONFIGURASI NODE"
    echo "================================================"
    echo
    echo "Buat Node terlebih dahulu di:"
    echo
    echo "Admin Panel → Nodes → Create New"
    echo
    echo "Konfigurasi umum:"
    echo "  FQDN        : domain Node kamu"
    echo "  SSL         : sesuai konfigurasi Node"
    echo "  Daemon Port : 8080"
    echo "  SFTP Port   : 2022"
    echo
    echo "Setelah Node dibuat:"
    echo "  1. Buka Node tersebut"
    echo "  2. Buka Configuration"
    echo "  3. Siapkan Application API Token"
    echo "  4. Masukkan Node ID di bawah"
    echo

    local panel_url
    local token
    local node_id

    panel_url="$(ask_panel_url)"

    echo

    check_panel_connection "$panel_url"

    echo

    token="$(ask_token)"

    echo

    node_id="$(ask_node_id)"

    echo

    # --------------------------------------------------------
    # CONFIG
    # --------------------------------------------------------

    configure_wings \
        "$panel_url" \
        "$token" \
        "$node_id"

    validate_config

    # --------------------------------------------------------
    # SYSTEMD
    # --------------------------------------------------------

    create_systemd_service

    # --------------------------------------------------------
    # FIREWALL
    # --------------------------------------------------------

    configure_firewall

    # --------------------------------------------------------
    # START
    # --------------------------------------------------------

    start_wings

    # --------------------------------------------------------
    # PORT
    # --------------------------------------------------------

    port_check

    # --------------------------------------------------------
    # STATUS
    # --------------------------------------------------------

    show_wings_status

    echo
    echo "================================================"
    echo "        WINGS INSTALLATION COMPLETE"
    echo "================================================"
    echo
    log "Wings berhasil diinstall."
    log "Config: $WINGS_CONFIG"
    log "Service: wings"
    echo
}


# ============================================================
# RUN
# ============================================================

install_wings
