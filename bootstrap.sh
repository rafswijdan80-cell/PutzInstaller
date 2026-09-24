#!/bin/bash

set -e

REPO="https://github.com/rafswijdan80-cell/PutzInstaller.git"
DIR="/tmp/putzofficial-installer"

echo "=========================================="
echo "       PUTZOFFICIAL INSTALLER"
echo "=========================================="

rm -rf "$DIR"

echo "[INFO] Downloading installer..."

git clone --depth 1 "$REPO" "$DIR"

cd "$DIR"

chmod +x install.sh
chmod +x lib/*.sh 2>/dev/null || true

echo "[OK] Installer downloaded."
echo

exec bash "$DIR/install.sh"
