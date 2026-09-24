#!/bin/bash

set -e

PANEL_DIR="/var/www/pterodactyl"
NGINX_CONFIG="/etc/nginx/sites-enabled/pterodactyl.conf"
NGINX_AVAILABLE="/etc/nginx/sites-available/pterodactyl.conf"
BACKUP_DIR="/root/putzofficial-backups"

echo
echo "=========================================="
echo "        UNINSTALL PTERODACTYL PANEL"
echo "=========================================="
echo
echo "[WARNING] Tindakan ini akan menghapus source"
echo "          Pterodactyl Panel dari VPS."
echo
echo "[INFO] Docker dan Wings TIDAK akan dihapus."
echo "[INFO] Server/container Docker TIDAK akan dihapus."
echo

if [ ! -d "$PANEL_DIR" ]; then
    echo "[ERROR] Pterodactyl Panel tidak ditemukan."
    exit 1
fi

read -rp 'Ketik "UNINSTALL" untuk melanjutkan: ' CONFIRM

if [ "$CONFIRM" != "UNINSTALL" ]; then
    echo "[INFO] Uninstall dibatalkan."
    exit 0
fi

echo
echo "[INFO] Membuat backup..."

mkdir -p "$BACKUP_DIR"

if [ -f "$PANEL_DIR/.env" ]; then
    cp "$PANEL_DIR/.env" \
       "$BACKUP_DIR/pterodactyl.env.$(date +%Y%m%d-%H%M%S)"
    echo "[OK] Backup .env dibuat."
fi

echo "[INFO] Menghentikan queue worker..."

if command -v systemctl >/dev/null 2>&1; then
    systemctl stop pteroq.service 2>/dev/null || true
    systemctl disable pteroq.service 2>/dev/null || true
fi

echo "[INFO] Menghapus konfigurasi Nginx Panel..."

rm -f "$NGINX_CONFIG"
rm -f "$NGINX_AVAILABLE"

if command -v nginx >/dev/null 2>&1; then
    nginx -t
    systemctl reload nginx
fi

echo "[INFO] Menghapus source Pterodactyl..."

rm -rf "$PANEL_DIR"

echo
echo "=========================================="
echo "          UNINSTALL SELESAI"
echo "=========================================="
echo "[OK] Source Panel: dihapus"
echo "[OK] Nginx config Panel: dihapus"
echo "[OK] Docker: dipertahankan"
echo "[OK] Wings: dipertahankan"
echo "[OK] Container/server Docker: dipertahankan"
echo
echo "[INFO] Backup berada di:"
echo "$BACKUP_DIR"
echo
