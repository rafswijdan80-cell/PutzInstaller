#!/usr/bin/env bash

set -Eeuo pipefail

VERSION="1.1.0"
NAME="PutzOfficial Pterodactyl Installer"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# LOAD COMMON FUNCTIONS / UI
# ============================================================

source "$BASE_DIR/lib/common.sh"


# ============================================================
# PAUSE FUNCTION
# ============================================================

pause() {
    echo
    read -r -p "  Press Enter to return to menu ❯ " _
}


# ============================================================
# ERROR HANDLER
# ============================================================

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

    echo "[1/3] Installing Pterodactyl Panel..."
    echo

    bash "$BASE_DIR/lib/panel.sh"

    echo
    echo "────────────────────────────────────────────────────"
    echo

    echo "[2/3] Installing Docker..."
    echo

    bash "$BASE_DIR/lib/docker.sh"

    echo
    echo "────────────────────────────────────────────────────"
    echo

    echo "[3/3] Installing Wings..."
    echo

    bash "$BASE_DIR/lib/wings.sh"

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│              INSTALLATION COMPLETE                │"
    echo "├────────────────────────────────────────────────────┤"
    echo "│                                                    │"
    echo "│   ✓ Pterodactyl Panel                             │"
    echo "│   ✓ Docker                                        │"
    echo "│   ✓ Wings                                         │"
    echo "│                                                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    pause
}


# ============================================================
# HEALTH CHECK
# ============================================================

run_health_check() {
    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                 HEALTH CHECK                       │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    health_check

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│              HEALTH CHECK COMPLETE                 │"
    echo "╰────────────────────────────────────────────────────╯"

    pause
}


# ============================================================
# UNINSTALL PANEL
# ============================================================

uninstall_panel() {
    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│              UNINSTALL PANEL                       │"
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

    # Root check
    require_root

    # Initialize log
    init_log

    # System checks
    check_os
    check_arch

    while true; do

        show_menu

        read -r -p "  Select option [1-7] ❯ " choice

        case "$choice" in

            # ------------------------------------------------
            # 1. INSTALL PANEL
            # ------------------------------------------------
            1)
                install_panel
                ;;

            # ------------------------------------------------
            # 2. INSTALL DOCKER
            # ------------------------------------------------
            2)
                install_docker
                ;;

            # ------------------------------------------------
            # 3. INSTALL WINGS
            # ------------------------------------------------
            3)
                install_wings
                ;;

            # ------------------------------------------------
            # 4. FULL INSTALLATION
            # ------------------------------------------------
            4)
                full_install
                ;;

            # ------------------------------------------------
            # 5. HEALTH CHECK
            # ------------------------------------------------
            5)
                run_health_check
                ;;

            # ------------------------------------------------
            # 6. UNINSTALL PANEL
            # ------------------------------------------------
            6)
                uninstall_panel
                ;;

            # ------------------------------------------------
            # 7. EXIT
            # ------------------------------------------------
            7)
                clear 2>/dev/null || true

                echo
                echo "╭────────────────────────────────────────────────────╮"
                echo "│                                                    │"
                echo "│              PUTZOFFICIAL INSTALLER               │"
                echo "│                                                    │"
                echo "│              Thank you for using it.              │"
                echo "│                                                    │"
                echo "╰────────────────────────────────────────────────────╯"
                echo

                exit 0
                ;;

            # ------------------------------------------------
            # INVALID OPTION
            # ------------------------------------------------
            *)
                warn "Pilihan tidak valid. Gunakan angka 1-7."
                sleep 1
                ;;

        esac

    done
}


# ============================================================
# START INSTALLER
# ============================================================

main "$@"
