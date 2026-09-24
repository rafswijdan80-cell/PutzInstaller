#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

install_wings() {

    info "Memastikan Docker tersedia..."

    "$BASE_DIR/lib/docker.sh"

    mkdir -p \
        /etc/pterodactyl \
        /var/log/pterodactyl

    if [[ ! -x /usr/local/bin/wings ]]; then

        info "Mengunduh Pterodactyl Wings..."

        curl -fL \
            https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64 \
            -o /usr/local/bin/wings

        chmod 0755 \
            /usr/local/bin/wings

    else

        log "Wings sudah terinstall."

    fi

    info "Versi Wings:"

    /usr/local/bin/wings version || true

    echo
    echo "================================================"
    echo "              KONFIGURASI NODE"
    echo "================================================"
    echo
    echo "Sebelum melanjutkan:"
    echo
    echo "1. Buka Admin Pterodactyl"
    echo "2. Nodes"
    echo "3. Create New"
    echo "4. Masukkan FQDN Node"
    echo "5. Scheme: HTTPS"
    echo "6. Daemon Port: 8080"
    echo "7. SFTP Port: 2022"
    echo
    echo "Setelah Node dibuat, ambil configuration/token."
    echo

    local panel_url
    local token
    local node_id

    panel_url="$(
        ask_required \
        'Panel URL, contoh https://panel.example.com'
    )"

    token="$(
        ask_required \
        'Wings token'
    )"

    node_id="$(
        ask_required \
        'Node ID'
    )"

    info "Membuat config.yml..."

    cd /etc/pterodactyl

    /usr/local/bin/wings configure \
        --panel-url "$panel_url" \
        --token "$token" \
        --node "$node_id"

    if [[ ! -s /etc/pterodactyl/config.yml ]]; then
        error "config.yml gagal dibuat."
    fi

    log "config.yml berhasil dibuat."

    echo
    info "Pastikan SSL Node sudah tersedia sebelum Wings dijalankan."
    echo
    read -r -p \
        "Lanjut membuat service Wings? [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        warn "Service Wings tidak dijalankan."
        return
    fi

    cat > /etc/systemd/system/wings.service <<'SERVICE'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096

ExecStart=/usr/local/bin/wings

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

    info "Membuka firewall Wings..."

    ufw allow 8080/tcp || true
    ufw allow 2022/tcp || true

    systemctl daemon-reload

    systemctl enable wings

    systemctl restart wings

    sleep 3

    if systemctl is-active --quiet wings; then

        log "Wings berhasil aktif."

        echo
        systemctl status wings \
            --no-pager \
            -l

    else

        error "Wings gagal aktif."

    fi

    echo
    info "Port Wings:"
    ss -lntp | grep -E ':8080|:2022' || true

    echo
    log "Wings installation selesai."
}

install_wings
