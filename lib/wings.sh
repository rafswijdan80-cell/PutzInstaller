#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

install_wings() {

    info "Memulai instalasi Pterodactyl Wings..."

    # ============================================================
    # ROOT CHECK
    # ============================================================

    if [[ "${EUID}" -ne 0 ]]; then
        error "Wings harus diinstall sebagai root."
        return 1
    fi

    # ============================================================
    # DEPENDENCY CHECK
    # ============================================================

    info "Memeriksa Docker..."

    if ! command -v docker >/dev/null 2>&1; then
        info "Docker belum tersedia. Menjalankan installer Docker..."

        if [[ -x "$BASE_DIR/lib/docker.sh" ]]; then
            "$BASE_DIR/lib/docker.sh"
        elif [[ -f "$BASE_DIR/lib/docker.sh" ]]; then
            bash "$BASE_DIR/lib/docker.sh"
        else
            error "File lib/docker.sh tidak ditemukan."
            return 1
        fi
    fi

    if ! command -v docker >/dev/null 2>&1; then
        error "Docker tidak tersedia setelah instalasi."
        return 1
    fi

    if ! systemctl is-active --quiet docker; then
        info "Menjalankan Docker..."

        systemctl enable docker >/dev/null 2>&1 || true
        systemctl start docker
    fi

    if systemctl is-active --quiet docker; then
        log "Docker: OK"
    else
        error "Docker gagal aktif."
        return 1
    fi

    # ============================================================
    # DIRECTORY
    # ============================================================

    info "Mempersiapkan direktori Pterodactyl..."

    mkdir -p \
        /etc/pterodactyl \
        /var/log/pterodactyl

    chmod 0755 /etc/pterodactyl
    chmod 0755 /var/log/pterodactyl

    # ============================================================
    # INSTALL WINGS
    # ============================================================

    if [[ ! -x /usr/local/bin/wings ]]; then

        info "Mengunduh Pterodactyl Wings..."

        TMP_WINGS="/tmp/wings_linux_amd64"

        rm -f "$TMP_WINGS"

        if ! curl \
            --fail \
            --location \
            --retry 3 \
            --connect-timeout 15 \
            --max-time 300 \
            https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64 \
            -o "$TMP_WINGS"; then

            error "Gagal mengunduh Pterodactyl Wings."
            return 1
        fi

        if [[ ! -s "$TMP_WINGS" ]]; then
            error "File Wings hasil download kosong."
            rm -f "$TMP_WINGS"
            return 1
        fi

        install -m 0755 "$TMP_WINGS" /usr/local/bin/wings

        rm -f "$TMP_WINGS"

        log "Wings berhasil diinstall."

    else

        log "Wings sudah terinstall."

    fi

    # ============================================================
    # VERSION
    # ============================================================

    info "Versi Wings:"

    if ! /usr/local/bin/wings version; then
        error "Binary Wings tidak dapat dijalankan."
        return 1
    fi

    echo

    # ============================================================
    # NODE CONFIGURATION
    # ============================================================

    echo "================================================"
    echo "              KONFIGURASI NODE"
    echo "================================================"
    echo
    echo "Buat Node terlebih dahulu di Admin Pterodactyl:"
    echo
    echo "1. Login ke Admin Panel"
    echo "2. Buka Administration"
    echo "3. Pilih Nodes"
    echo "4. Klik Create New"
    echo "5. Isi nama Node"
    echo "6. Isi FQDN Node"
    echo "7. Scheme: HTTPS"
    echo "8. Daemon Port: 8080"
    echo "9. SFTP Port: 2022"
    echo
    echo "Setelah Node dibuat, buka:"
    echo
    echo "Nodes -> Node kamu -> Configuration"
    echo
    echo "Salin konfigurasi/token Wings dari halaman tersebut."
    echo
    echo "================================================"
    echo

    local panel_url
    local token
    local node_id

    # ============================================================
    # PANEL URL
    # ============================================================

    while true; do

        panel_url="$(
            ask_required \
                'Panel URL, contoh https://panel.example.com'
        )"

        panel_url="${panel_url%/}"

        if [[ "$panel_url" =~ ^https?:// ]]; then
            break
        fi

        warn "Panel URL harus diawali http:// atau https://."

    done

    # ============================================================
    # NODE ID
    # ============================================================

    while true; do

        node_id="$(
            ask_required \
                'Node ID'
        )"

        if [[ "$node_id" =~ ^[0-9]+$ ]] && [[ "$node_id" -gt 0 ]]; then
            break
        fi

        warn "Node ID harus berupa angka lebih besar dari 0."

    done

    # ============================================================
    # WINGS TOKEN
    # ============================================================

    while true; do

        token="$(
            ask_required \
                'Wings token/configuration token'
        )"

        if [[ -n "$token" ]]; then
            break
        fi

        warn "Token tidak boleh kosong."

    done

    echo

    info "Memeriksa koneksi ke Panel..."

    # Hanya cek konektivitas dasar.
    # TIDAK memanggil endpoint /api/application/nodes/.../configuration
    # karena endpoint tersebut membutuhkan autentikasi API dan dapat
    # mengembalikan redirect ke /auth/login.

    local panel_code

    panel_code="$(
        curl \
            -4 \
            -sS \
            -o /dev/null \
            -w '%{http_code}' \
            --connect-timeout 15 \
            --max-time 30 \
            "$panel_url" \
            2>/dev/null || echo "000"
    )"

    if [[ "$panel_code" == "000" ]]; then
        warn "Panel tidak dapat diakses melalui IPv4."
        warn "Lanjutkan hanya jika URL panel memang benar."
    else
        log "Panel dapat diakses. HTTP: $panel_code"
    fi

    # ============================================================
    # GENERATE CONFIG
    # ============================================================

    info "Membuat config.yml Wings..."

    cd /etc/pterodactyl

    rm -f /etc/pterodactyl/config.yml.tmp

    if ! /usr/local/bin/wings configure \
        --panel-url "$panel_url" \
        --token "$token" \
        --node "$node_id"; then

        error "Wings gagal membuat config.yml."
        return 1
    fi

    # ============================================================
    # CONFIG CHECK
    # ============================================================

    if [[ ! -s /etc/pterodactyl/config.yml ]]; then
        error "config.yml tidak ditemukan atau kosong."
        return 1
    fi

    chmod 0600 /etc/pterodactyl/config.yml

    log "config.yml berhasil dibuat."

    echo
    info "Lokasi konfigurasi:"
    echo "/etc/pterodactyl/config.yml"
    echo

    # ============================================================
    # SYSTEMD SERVICE
    # ============================================================

    info "Membuat service systemd Wings..."

    cat > /etc/systemd/system/wings.service <<'SERVICE'
[Unit]
Description=Pterodactyl Wings Daemon
Documentation=https://pterodactyl.io/
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

NoNewPrivileges=false
PrivateTmp=false

[Install]
WantedBy=multi-user.target
SERVICE

    chmod 0644 /etc/systemd/system/wings.service

    # ============================================================
    # FIREWALL
    # ============================================================

    info "Memeriksa firewall..."

    if command -v ufw >/dev/null 2>&1; then

        if ufw status 2>/dev/null | grep -q "Status: active"; then

            info "Membuka port Wings..."

            ufw allow 8080/tcp >/dev/null 2>&1 || true
            ufw allow 2022/tcp >/dev/null 2>&1 || true

            log "Port 8080/tcp dan 2022/tcp diizinkan."

        else

            log "UFW tidak aktif. Tidak ada perubahan firewall."

        fi

    else

        log "UFW tidak terinstall. Melewati konfigurasi firewall."

    fi

    # ============================================================
    # SYSTEMD RELOAD
    # ============================================================

    info "Memuat ulang systemd..."

    systemctl daemon-reload

    systemctl enable wings >/dev/null 2>&1

    # ============================================================
    # START WINGS
    # ============================================================

    echo
    info "Menjalankan Wings..."

    systemctl restart wings

    sleep 5

    # ============================================================
    # SERVICE CHECK
    # ============================================================

    if systemctl is-active --quiet wings; then

        log "Wings berhasil aktif."

    else

        error "Wings gagal aktif."

        echo
        echo "================ WINGS LOG ================"
        journalctl \
            -u wings \
            -n 50 \
            --no-pager \
            -l || true
        echo "============================================"

        return 1

    fi

    # ============================================================
    # PORT CHECK
    # ============================================================

    echo
    info "Memeriksa port Wings..."

    if ss -lntp 2>/dev/null | grep -q ':8080'; then
        log "Port 8080: LISTEN"
    else
        warn "Port 8080 belum terlihat LISTEN."
    fi

    if ss -lntp 2>/dev/null | grep -q ':2022'; then
        log "Port 2022: LISTEN"
    else
        warn "Port 2022 belum terlihat LISTEN."
    fi

    # ============================================================
    # STATUS
    # ============================================================

    echo
    echo "================================================"
    echo "              STATUS WINGS"
    echo "================================================"
    echo

    systemctl status wings \
        --no-pager \
        -l || true

    echo
    echo "================================================"
    echo "          INSTALASI WINGS SELESAI"
    echo "================================================"
    echo
    echo "Binary    : /usr/local/bin/wings"
    echo "Config    : /etc/pterodactyl/config.yml"
    echo "Service   : wings.service"
    echo "Daemon    : 8080"
    echo "SFTP      : 2022"
    echo
    echo "Cek status:"
    echo "  systemctl status wings"
    echo
    echo "Lihat log:"
    echo "  journalctl -u wings -f"
    echo

    log "Instalasi Wings selesai."

}

install_wings
