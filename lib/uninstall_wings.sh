#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# PUTZOFFICIAL WINGS UNINSTALLER
# ============================================================

VERSION="1.0.0"
NAME="PutzOfficial Wings Uninstaller"

DEVELOPER="PutzOfficial"
TELEGRAM_CHANNEL="https://t.me/PutzPayOfficial"
COPYRIGHT="© 2026 PutzOfficial. All Rights Reserved."

# ============================================================
# ROOT CHECK
# ============================================================

if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Script harus dijalankan sebagai root."
    exit 1
fi

# ============================================================
# FUNCTIONS
# ============================================================

info() {
    echo "[INFO] $*"
}

success() {
    echo "[OK] $*"
}

warn() {
    echo "[WARN] $*"
}

error() {
    echo "[ERROR] $*"
}

# ============================================================
# BANNER
# ============================================================

clear 2>/dev/null || true

echo
echo "╭────────────────────────────────────────────────────╮"
echo "│                                                    │"
echo "│           PUTZOFFICIAL WINGS UNINSTALLER           │"
echo "│                                                    │"
echo "╰────────────────────────────────────────────────────╯"
echo

echo "  Name      : $NAME"
echo "  Version   : $VERSION"
echo "  Developer : $DEVELOPER"
echo "  Telegram  : $TELEGRAM_CHANNEL"
echo "  $COPYRIGHT"

echo
echo "  DESKRIPSI"
echo "  ──────────────────────────────────────────────────"
echo
echo "  Script ini hanya menghapus Pterodactyl Wings."
echo
echo "  Yang akan dihapus:"
echo "    • Wings service"
echo "    • Wings binary"
echo "    • Wings configuration"
echo "    • Wings log"
echo "    • Wings systemd service"
echo
echo "  Yang TIDAK akan dihapus:"
echo "    • Pterodactyl Panel"
echo "    • PHP / PHP-FPM"
echo "    • Nginx"
echo "    • Docker"
echo "    • MariaDB / MySQL"
echo "    • Redis"
echo "    • Server data"
echo

# ============================================================
# CONFIRMATION
# ============================================================

echo "╭────────────────────────────────────────────────────╮"
echo "│  Ketik REMOVE WINGS untuk melanjutkan              │"
echo "╰────────────────────────────────────────────────────╯"
echo

read -r -p "  Confirmation ❯ " confirmation

if [[ "$confirmation" != "REMOVE WINGS" ]]; then

    echo
    warn "Konfirmasi salah."
    info "Uninstall Wings dibatalkan."
    echo

    exit 0

fi

# ============================================================
# SECOND CONFIRMATION
# ============================================================

echo
echo "╭────────────────────────────────────────────────────╮"
echo "│                 FINAL WARNING                      │"
echo "╰────────────────────────────────────────────────────╯"
echo
warn "Wings akan dihapus dari VPS."
warn "Docker dan data server TIDAK akan dihapus."
echo

read -r -p "  Ketik YES untuk melanjutkan ❯ " final_confirmation

if [[ "$final_confirmation" != "YES" ]]; then

    echo
    warn "Uninstall Wings dibatalkan."
    echo

    exit 0

fi

# ============================================================
# STOP WINGS
# ============================================================

echo
info "Menghentikan Wings..."

systemctl stop wings 2>/dev/null || true

systemctl disable wings 2>/dev/null || true

success "Wings service dihentikan."

# ============================================================
# REMOVE SYSTEMD SERVICE
# ============================================================

info "Menghapus systemd service Wings..."

rm -f /etc/systemd/system/wings.service
rm -f /usr/lib/systemd/system/wings.service

systemctl daemon-reload
systemctl reset-failed wings 2>/dev/null || true

success "Systemd service Wings dihapus."

# ============================================================
# REMOVE BINARY
# ============================================================

info "Menghapus Wings binary..."

rm -f /usr/local/bin/wings
rm -f /usr/bin/wings
rm -f /usr/local/sbin/wings

success "Wings binary dihapus."

# ============================================================
# REMOVE WINGS CONFIG
# ============================================================

info "Menghapus konfigurasi Wings..."

if [[ -d /etc/pterodactyl ]]; then

    rm -f /etc/pterodactyl/config.yml

fi

success "Konfigurasi Wings dihapus."

# ============================================================
# REMOVE WINGS LOG
# ============================================================

info "Menghapus log Wings..."

rm -f /var/log/pterodactyl/wings.log

rm -rf /var/log/pterodactyl/wings

success "Log Wings dibersihkan."

# ============================================================
# REMOVE EMPTY DIRECTORY ONLY
# ============================================================

if [[ -d /etc/pterodactyl ]]; then

    if [[ -z "$(ls -A /etc/pterodactyl 2>/dev/null)" ]]; then
        rmdir /etc/pterodactyl 2>/dev/null || true
    fi

fi

# ============================================================
# VERIFY
# ============================================================

echo
info "Memeriksa hasil uninstall..."

FAILED=0

if systemctl list-unit-files 2>/dev/null |
    grep -q '^wings.service'; then

    warn "wings.service masih terdaftar."
    FAILED=1

else

    success "Wings service: removed"

fi

if [[ -f /usr/local/bin/wings ]] ||
   [[ -f /usr/bin/wings ]] ||
   [[ -f /usr/local/sbin/wings ]]; then

    warn "Wings binary masih ditemukan."
    FAILED=1

else

    success "Wings binary: removed"

fi

if [[ -f /etc/pterodactyl/config.yml ]]; then

    warn "Wings config masih ditemukan."
    FAILED=1

else

    success "Wings config: removed"

fi

# ============================================================
# FINAL
# ============================================================

echo

if [[ "$FAILED" -eq 0 ]]; then

    echo "╭────────────────────────────────────────────────────╮"
    echo "│                                                    │"
    echo "│            WINGS UNINSTALL COMPLETE               │"
    echo "│                                                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    echo "  ✓ Wings service"
    echo "  ✓ Wings binary"
    echo "  ✓ Wings configuration"
    echo "  ✓ Wings logs"

    echo
    echo "  Panel     : NOT TOUCHED"
    echo "  Docker    : NOT TOUCHED"
    echo "  Nginx     : NOT TOUCHED"
    echo "  PHP       : NOT TOUCHED"
    echo "  Database  : NOT TOUCHED"
    echo "  Server data: NOT TOUCHED"

    echo
    echo "  Wings sekarang siap untuk di-install ulang."
    echo
    echo "  Developer : $DEVELOPER"
    echo "  Telegram  : $TELEGRAM_CHANNEL"
    echo "  $COPYRIGHT"
    echo

else

    echo "╭────────────────────────────────────────────────────╮"
    echo "│          WINGS UNINSTALL FINISHED                 │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    warn "Beberapa komponen Wings masih terdeteksi."
    warn "Periksa output di atas."

    exit 1

fi

exit 0
