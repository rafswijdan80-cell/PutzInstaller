#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# PUTZOFFICIAL PTERODACTYL INSTALLER
# ============================================================

VERSION="1.1.1"
NAME="PutzOfficial Pterodactyl Installer"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# LOAD COMMON
# ============================================================

source "$BASE_DIR/lib/common.sh"

# ============================================================
# INITIAL LOG
# ============================================================

init_log

# ============================================================
# ERROR HANDLER
# ============================================================

handle_error() {

    local exit_code=$?
    local line_number="${1:-unknown}"

    echo
    echo "================================================"
    echo "              INSTALLER ERROR"
    echo "================================================"
    echo
    echo "[ERROR] Installer berhenti pada baris $line_number."
    echo "[ERROR] Exit code: $exit_code"
    echo "[ERROR] Log: $LOG_FILE"
    echo

    return "$exit_code"
}

trap 'handle_error "$LINENO"' ERR

# ============================================================
# PAUSE
# ============================================================

pause() {

    echo
    read -r -p "  Press Enter to return to menu ❯ " _
}

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

    if [[ ! -f "$BASE_DIR/lib/panel.sh" ]]; then
        warn "lib/panel.sh tidak ditemukan."
        pause
        return 1
    fi

    if bash "$BASE_DIR/lib/panel.sh"; then

        echo
        log "Panel installation process selesai."

    else

        echo
        error "Panel installation gagal."
        show_log_location

    fi

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

    if [[ ! -f "$BASE_DIR/lib/docker.sh" ]]; then
        warn "lib/docker.sh tidak ditemukan."
        pause
        return 1
    fi

    if bash "$BASE_DIR/lib/docker.sh"; then

        echo
        log "Docker installation process selesai."

    else

        echo
        error "Docker installation gagal."
        show_log_location

    fi

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

    if [[ ! -f "$BASE_DIR/lib/wings.sh" ]]; then
        warn "lib/wings.sh tidak ditemukan."
        pause
        return 1
    fi

    if bash "$BASE_DIR/lib/wings.sh"; then

        echo
        log "Wings installation process selesai."

    else

        echo
        error "Wings installation gagal."
        show_log_location

    fi

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

    # ========================================================
    # PANEL
    # ========================================================

    echo "[1/3] Installing Pterodactyl Panel..."
    echo

    if ! bash "$BASE_DIR/lib/panel.sh"; then

        echo
        error "Instalasi Panel gagal."
        show_log_location
        pause
        return 1

    fi

    echo
    echo "────────────────────────────────────────────────────"
    echo

    # ========================================================
    # DOCKER
    # ========================================================

    echo "[2/3] Installing Docker..."
    echo

    if ! bash "$BASE_DIR/lib/docker.sh"; then

        echo
        error "Instalasi Docker gagal."
        show_log_location
        pause
        return 1

    fi

    echo
    echo "────────────────────────────────────────────────────"
    echo

    # ========================================================
    # WINGS
    # ========================================================

    echo "[3/3] Installing Wings..."
    echo

    if ! bash "$BASE_DIR/lib/wings.sh"; then

        echo
        error "Instalasi Wings gagal."
        show_log_location
        pause
        return 1

    fi

    # ========================================================
    # COMPLETE
    # ========================================================

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

    log "Full installation selesai."

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

    if [[ ! -f "$BASE_DIR/lib/uninstall.sh" ]]; then
        warn "lib/uninstall.sh tidak ditemukan."
        pause
        return 1
    fi

    if bash "$BASE_DIR/lib/uninstall.sh"; then

        log "Proses uninstall selesai."

    else

        error "Uninstall Panel gagal."
        show_log_location

    fi

    echo
    pause
}

# ============================================================
# EXIT
# ============================================================

exit_installer() {

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
}

# ============================================================
# MAIN
# ============================================================

main() {

    # --------------------------------------------------------
    # ROOT
    # --------------------------------------------------------

    require_root

    # --------------------------------------------------------
    # SYSTEM CHECK
    # --------------------------------------------------------

    check_os
    check_arch

    # --------------------------------------------------------
    # MAIN LOOP
    # --------------------------------------------------------

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
                exit_installer
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
