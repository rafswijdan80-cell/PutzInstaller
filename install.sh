#!/usr/bin/env bash

set -Eeuo pipefail

VERSION="1.0.0"
NAME="PutzOfficial Pterodactyl Installer"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$BASE_DIR/lib/common.sh"

trap 'error "Installer berhenti pada baris $LINENO. Lihat log: $LOG_FILE"' ERR

main() {
    require_root
    init_log
    banner

    check_os
    check_arch
    system_info

    while true; do
        echo
        echo "=========================================="
        echo "          PUTZOFFICIAL INSTALLER"
        echo "=========================================="
        echo
        echo "1. Install Panel"
        echo "2. Install Docker"
        echo "3. Install Wings"
        echo "4. Install Panel + Docker + Wings"
        echo "5. Health Check"
        echo "6. Exit"
        echo

        read -r -p "Pilih [1-6]: " choice

        case "$choice" in
            1)
                "$BASE_DIR/lib/panel.sh"
                ;;
            2)
                "$BASE_DIR/lib/docker.sh"
                ;;
            3)
                "$BASE_DIR/lib/wings.sh"
                ;;
            4)
                "$BASE_DIR/lib/panel.sh"
                "$BASE_DIR/lib/docker.sh"
                "$BASE_DIR/lib/wings.sh"
                ;;
            5)
                health_check
                ;;
            6)
                echo "Keluar."
                exit 0
                ;;
            *)
                warn "Pilihan tidak valid."
                ;;
        esac
    done
}

main "$@"
