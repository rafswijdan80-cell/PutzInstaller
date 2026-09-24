#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# PUTZOFFICIAL PTERODACTYL INSTALLER
# ============================================================

VERSION="1.1.2"
NAME="PutzOfficial Pterodactyl Installer"

DEVELOPER="PutzOfficial"
TELEGRAM_CHANNEL="https://t.me/PutzPayOfficial"
COPYRIGHT="© 2026 PutzOfficial. All Rights Reserved."

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# LOAD COMMON
# ============================================================

if [[ ! -f "$BASE_DIR/lib/common.sh" ]]; then
    echo "[ERROR] lib/common.sh tidak ditemukan."
    exit 1
fi

source "$BASE_DIR/lib/common.sh"

# ============================================================
# LOG
# ============================================================

init_log

# ============================================================
# ERROR HANDLER
# ============================================================

handle_error() {

    local exit_code=$?
    local line_number="${1:-unknown}"

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                 INSTALLER ERROR                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo
    echo "[ERROR] Installer berhenti pada baris: $line_number"
    echo "[ERROR] Exit code: $exit_code"

    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[ERROR] Log: $LOG_FILE"
    fi

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
# INSTALLER INFO
# ============================================================

show_about() {

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│              PUTZOFFICIAL INSTALLER               │"
    echo "├────────────────────────────────────────────────────┤"
    printf "│  %-16s : %-29s │\n" "Name" "$NAME"
    printf "│  %-16s : %-29s │\n" "Version" "$VERSION"
    printf "│  %-16s : %-29s │\n" "Developer" "$DEVELOPER"
    printf "│  %-16s : %-29s │\n" "Telegram" "$TELEGRAM_CHANNEL"
    printf "│  %-16s : %-29s │\n" "Copyright" "$COPYRIGHT"
    echo "╰────────────────────────────────────────────────────╯"
}

# ============================================================
# MENU
# ============================================================

show_menu() {

    clear 2>/dev/null || true

    banner

    show_about

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
    echo "│        Install Pterodactyl Panel.                  │"
    echo "│                                                    │"
    echo "│   02   Install Docker                              │"
    echo "│        Install Docker Engine.                      │"
    echo "│                                                    │"
    echo "│   03   Install Wings                               │"
    echo "│        Install Pterodactyl Wings Node.             │"
    echo "│                                                    │"
    echo "│   04   Full Installation                           │"
    echo "│        Panel + Docker + Wings.                     │"
    echo "│                                                    │"
    echo "│   05   Health Check                                │"
    echo "│        Check Panel, Wings & system.                │"
    echo "│                                                    │"
    echo "│   06   Uninstall Panel                             │"
    echo "│        Full cleanup Pterodactyl.                   │"
    echo "│                                                    │"
    echo "│   07   Uninstall Wings                             │"
    echo "│        Remove Wings only.                          │"
    echo "│                                                    │"
    echo "│   08   Exit                                        │"
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
    echo "├────────────────────────────────────────────────────┤"
    echo "│                                                    │"
    echo "│  Install Pterodactyl Panel untuk mengelola        │"
    echo "│  server melalui web interface.                    │"
    echo "│                                                    │"
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
    echo "├────────────────────────────────────────────────────┤"
    echo "│                                                    │"
    echo "│  Docker digunakan oleh Wings untuk menjalankan     │"
    echo "│  container/server Pterodactyl.                    │"
    echo "│                                                    │"
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
    echo "├────────────────────────────────────────────────────┤"
    echo "│                                                    │"
    echo "│  Wings adalah daemon Pterodactyl yang menjalankan  │"
    echo "│  server pada Node VPS.                             │"
    echo "│                                                    │"
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
    echo "│  1. Pterodactyl Panel                              │"
    echo "│  2. Docker                                         │"
    echo "│  3. Pterodactyl Wings                              │"
    echo "│                                                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    read -r -p "  Lanjutkan Full Installation? [y/N] ❯ " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Full installation dibatalkan."
        pause
        return 0
    fi

    # ========================================================
    # PANEL
    # ========================================================

    echo
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
    echo "  Developer : $DEVELOPER"
    echo "  Telegram  : $TELEGRAM_CHANNEL"
    echo "  Version   : $VERSION"
    echo "  $COPYRIGHT"
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
    echo "├────────────────────────────────────────────────────┤"
    echo "│                                                    │"
    echo "│  Memeriksa service dan komponen Pterodactyl.       │"
    echo "│                                                    │"
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
    echo "│              FULL UNINSTALL PANEL                  │"
    echo "├────────────────────────────────────────────────────┤"
    echo "│                                                    │"
    echo "│  Menghapus seluruh environment Pterodactyl.        │"
    echo "│                                                    │"
    echo "│  Gunakan hanya jika ingin melakukan reinstall.     │"
    echo "│                                                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    if [[ ! -f "$BASE_DIR/lib/uninstall.sh" ]]; then
        warn "lib/uninstall.sh tidak ditemukan."
        pause
        return 1
    fi

    if bash "$BASE_DIR/lib/uninstall.sh"; then

        log "Proses full uninstall selesai."

    else

        error "Uninstall Panel gagal."
        show_log_location

    fi

    echo
    pause
}

# ============================================================
# UNINSTALL WINGS
# ============================================================

uninstall_wings() {

    echo
    echo "╭────────────────────────────────────────────────────╮"
    echo "│                UNINSTALL WINGS                    │"
    echo "├────────────────────────────────────────────────────┤"
    echo "│                                                    │"
    echo "│  Menghapus Pterodactyl Wings dari Node VPS.        │"
    echo "│                                                    │"
    echo "│  Panel, PHP, Nginx, Docker dan database            │"
    echo "│  TIDAK akan disentuh.                              │"
    echo "│                                                    │"
    echo "╰────────────────────────────────────────────────────╯"
    echo

    if [[ ! -f "$BASE_DIR/lib/uninstall_wings.sh" ]]; then
        warn "lib/uninstall_wings.sh tidak ditemukan."
        pause
        return 1
    fi

    if bash "$BASE_DIR/lib/uninstall_wings.sh"; then

        log "Proses uninstall Wings selesai."

    else

        error "Uninstall Wings gagal."
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
    echo "  Developer : $DEVELOPER"
    echo "  Telegram  : $TELEGRAM_CHANNEL"
    echo "  Version   : $VERSION"
    echo "  $COPYRIGHT"
    echo

    exit 0
}

# ============================================================
# MAIN
# ============================================================

main() {

    require_root

    check_os
    check_arch

    while true; do

        show_menu

        read -r -p "  Select option [1-8] ❯ " choice

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
                uninstall_wings
                ;;

            8)
                exit_installer
                ;;

            *)
                warn "Pilihan tidak valid. Gunakan angka 1-8."
                sleep 1
                ;;

        esac

    done
}

# ============================================================
# START
# ============================================================

main "$@"
