#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# PUTZOFFICIAL INSTALLER - COMMON FUNCTIONS
# ============================================================

LOG_DIR="/var/log/putzofficial-installer"
LOG_FILE="$LOG_DIR/install.log"

# Warna terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
RESET='\033[0m'

# ============================================================
# LOGGING
# ============================================================

init_log() {

    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"

    # Hindari init_log dipanggil berkali-kali
    if [[ "${PUTZ_LOG_INITIALIZED:-0}" == "1" ]]; then
        return 0
    fi

    export PUTZ_LOG_INITIALIZED=1

    exec > >(tee -a "$LOG_FILE") 2>&1
}

log() {
    echo -e "${GREEN}[OK]${RESET} $*"
}

info() {
    echo -e "${CYAN}[INFO]${RESET} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${RESET} $*"
}

error() {
    echo -e "${RED}[ERROR]${RESET} $*" >&2
    return 1
}

die() {
    error "$*"
    exit 1
}

# ============================================================
# BANNER
# ============================================================

banner() {

    clear 2>/dev/null || true

    echo "================================================"
    echo "       PUTZOFFICIAL PTERODACTYL INSTALLER"
    echo "       Version: ${VERSION:-unknown}"
    echo "================================================"
}

# ============================================================
# ROOT CHECK
# ============================================================

require_root() {

    if [[ "${EUID:-999}" -ne 0 ]]; then
        die "Installer harus dijalankan sebagai root."
    fi
}

# ============================================================
# OS CHECK
# ============================================================

check_os() {

    if [[ ! -f /etc/os-release ]]; then
        die "Tidak dapat mendeteksi operating system."
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        die "Installer ini hanya mendukung Ubuntu."
    fi

    case "${VERSION_ID:-}" in

        22.04|24.04|24.10|25.04|25.10)
            log "OS: Ubuntu $VERSION_ID"
            ;;

        *)
            warn "Ubuntu ${VERSION_ID:-unknown} belum diuji secara resmi oleh installer ini."
            ;;

    esac
}

# ============================================================
# ARCHITECTURE CHECK
# ============================================================

check_arch() {

    local arch

    arch="$(dpkg --print-architecture 2>/dev/null || true)"

    case "$arch" in

        amd64)
            log "Architecture: amd64"
            ;;

        *)
            die "Architecture tidak didukung: ${arch:-unknown}"
            ;;

    esac
}

# ============================================================
# SYSTEM INFORMATION
# ============================================================

system_info() {

    local hostname_value
    local kernel_value
    local ram_value
    local disk_value

    hostname_value="$(hostname 2>/dev/null || echo unknown)"
    kernel_value="$(uname -r 2>/dev/null || echo unknown)"
    ram_value="$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo unknown)"
    disk_value="$(df -h / 2>/dev/null | awk 'NR==2 {print $4 " free"}' || echo unknown)"

    info "Hostname : $hostname_value"
    info "Kernel   : $kernel_value"
    info "RAM      : $ram_value"
    info "Disk     : $disk_value"
}

# ============================================================
# APT INSTALL
# ============================================================

apt_install() {

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y
    apt-get install -y "$@"
}

# ============================================================
# COMMAND CHECK
# ============================================================

command_exists() {

    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# REQUIRED INPUT
# ============================================================

ask_required() {

    local prompt="$1"
    local value=""

    while [[ -z "$value" ]]; do

        read -r -p "$prompt: " value

        if [[ -z "$value" ]]; then
            warn "Input tidak boleh kosong."
        fi

    done

    printf '%s' "$value"
}

# ============================================================
# YES / NO CONFIRMATION
# ============================================================

ask_confirm() {

    local prompt="$1"
    local default="${2:-N}"
    local answer=""

    read -r -p "$prompt [y/N]: " answer

    if [[ -z "$answer" ]]; then
        answer="$default"
    fi

    [[ "$answer" =~ ^[Yy]$ ]]
}

# ============================================================
# SERVICE CHECK
# ============================================================

service_active() {

    systemctl is-active --quiet "$1" 2>/dev/null
}

# ============================================================
# HEALTH CHECK
# ============================================================

health_check() {

    echo
    info "=========================================="
    info "             HEALTH CHECK"
    info "=========================================="

    # Nginx
    if command_exists nginx; then

        if nginx -t >/dev/null 2>&1; then
            log "Nginx: OK"
        else
            warn "Nginx: konfigurasi bermasalah"
        fi

    else
        warn "Nginx: belum terinstall"
    fi

    # PHP
    if command_exists php; then

        local php_version

        php_version="$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo unknown)"

        log "PHP: $php_version"

    else
        warn "PHP: belum terinstall"
    fi

    # MariaDB
    if service_active mariadb; then
        log "MariaDB: active"
    else
        warn "MariaDB: tidak active"
    fi

    # Redis
    if service_active redis-server || service_active redis; then
        log "Redis: active"
    else
        warn "Redis: tidak active"
    fi

    # Docker
    if service_active docker; then
        log "Docker: active"
    else
        warn "Docker: tidak active"
    fi

    # Wings
    if service_active wings; then
        log "Wings: active"
    else
        warn "Wings: tidak active"
    fi

    # Panel
    if [[ -f /var/www/pterodactyl/artisan ]]; then
        log "Pterodactyl Panel: source ditemukan"
    else
        warn "Pterodactyl Panel: belum ditemukan"
    fi

    # Composer
    if command_exists composer; then

        local composer_version

        composer_version="$(
            composer --version 2>/dev/null |
            head -n 1 ||
            true
        )"

        if [[ -n "$composer_version" ]]; then
            log "Composer: $composer_version"
        else
            warn "Composer: tidak dapat membaca versi"
        fi

    else
        warn "Composer: belum terinstall"
    fi

    echo
}

# ============================================================
# PHP EXTENSION CHECK
# ============================================================

check_php_extension() {

    local extension="$1"

    if ! command_exists php; then
        return 1
    fi

    php -r "
        exit(extension_loaded('$extension') ? 0 : 1);
    " >/dev/null 2>&1
}

# ============================================================
# PHP EXTENSION REPORT
# ============================================================

php_extension_report() {

    local extensions=(
        PDO
        pdo_mysql
        Phar
        posix
        tokenizer
        fileinfo
    )

    local ext

    echo
    echo "===== PHP EXTENSION CHECK ====="

    for ext in "${extensions[@]}"; do

        if check_php_extension "$ext"; then
            printf "%-12s: OK\n" "$ext"
        else
            printf "%-12s: MISSING\n" "$ext"
        fi

    done

    echo
}

# ============================================================
# SAFE DIRECTORY
# ============================================================

ensure_directory() {

    local directory="$1"

    if [[ ! -d "$directory" ]]; then
        mkdir -p "$directory"
    fi
}

# ============================================================
# LOG LOCATION
# ============================================================

show_log_location() {

    echo
    info "Log installer:"
    echo "$LOG_FILE"
    echo
}

# ============================================================
# COMMAND FAILURE HANDLER
# ============================================================

run_or_die() {

    local description="$1"
    shift

    info "$description"

    if ! "$@"; then
        die "$description gagal."
    fi
}
