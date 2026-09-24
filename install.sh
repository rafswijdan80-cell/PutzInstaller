#!/usr/bin/env bash

set -Eeuo pipefail

VERSION="1.1.0"
NAME="PutzOfficial Pterodactyl Installer"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common functions / UI
source "$BASE_DIR/lib/common.sh"

# Error handler
trap 'error "Installer berhenti pada baris $LINENO. Lihat log: $LOG_FILE"' ERR


# ============================================================
# MENU
# ============================================================

show_menu() {
    clear 2>/dev/null || true

    banner

    echo
    echo "  SYSTEM"
    echo "  ──────────────────────────────────────────────────"

    system_info

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                  MAIN MENU                         │"
    echo "├────────────────────────────────────────────────────┤"
    echo "│                                                    │"
    echo "│   01   Install Panel                               │"
    echo "│   02   Install Docker                              │"
    echo "│   03   Install Wings                               │"
    echo "│   04   Full Installation                           │"
    echo "│   05   Health Check                                │"
    echo "│   06   Uninstall Panel                             │"
    echo "│   07   Exit                                        │"
    echo "│                                                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo
}


# ============================================================
# INSTALL PANEL
# ============================================================

install_panel() {
    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│              PTERODACTYL PANEL                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    bash "$BASE_DIR/lib/panel.sh"

    echo
    info "Panel installation process selesai."
    pause
}


# ============================================================
# INSTALL DOCKER
# ============================================================

install_docker() {
    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                 DOCKER ENGINE                     │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    bash "$BASE_DIR/lib/docker.sh"

    echo
    info "Docker installation process selesai."
    pause
}


# ============================================================
# INSTALL WINGS
# ============================================================

install_wings() {
    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                    WINGS                           │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    bash "$BASE_DIR/lib/wings.sh"

    echo
    info "Wings installation process selesai."
    pause
}


# ============================================================
# FULL INSTALLATION
# ============================================================

full_install() {
    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│              FULL INSTALLATION                    │"
    echo "├────────────────────────────────────────────────────┤"
    echo "│                                                    │"
    echo "│  Panel → Docker → Wings                            │"
    echo "│                                                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    bash "$BASE_DIR/lib/panel.sh"

    echo
    bash "$BASE_DIR/lib/docker.sh"

    echo
    bash "$BASE_DIR/lib/wings.sh"

    echo
    info "Full installation selesai."
    pause
}


# ============================================================
# HEALTH CHECK
# ============================================================

run_health_check() {
    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                 HEALTH CHECK                      │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    health_check

    echo
    pause
}


# ============================================================
# UNINSTALL PANEL
# ============================================================

uninstall_panel() {
    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│              UNINSTALL PANEL                      │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    bash "$BASE_DIR/lib/uninstall.sh"

    echo
    pause
}


# ============================================================
# MAIN
# ============================================================

main() {
    require_root
    init_log

    check_os
    check_arch

    while true; do

        show_menu

        read -r -p "  Select option [1-7] ❯ " choice

        case "$choice" in

            1)
                install_panel
                ;;

            2)
                install_docker
                ;;

            3)
                install_wings
                ;;

            4)
                full_install
                ;;

            5)
                run_health_check
                ;;

            6)
                uninstall_panel
                ;;

            7)
                echo
                echo "  ──────────────────────────────────────────────────"
                echo "  PutzOfficial Installer"
                echo "  Thank you for using PutzOfficial."
                echo "  ──────────────────────────────────────────────────"
                echo
                exit 0
                ;;

            *)
                warn "Pilihan tidak valid. Gunakan angka 1-7."
                sleep 1
                ;;

        esac

    done
}


# ============================================================
# START
# ============================================================

main "$@"
