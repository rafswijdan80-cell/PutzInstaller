#!/usr/bin/env bash

set -Eeuo pipefail

LOG_DIR="/var/log/putzofficial-installer"
LOG_FILE="$LOG_DIR/install.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

init_log() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"

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
    exit 1
}

banner() {
    clear || true

    echo "================================================"
    echo "       PUTZOFFICIAL PTERODACTYL INSTALLER"
    echo "       Version: $VERSION"
    echo "================================================"
}

require_root() {
    if [[ "${EUID:-999}" -ne 0 ]]; then
        error "Installer harus dijalankan sebagai root."
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        error "Tidak dapat mendeteksi operating system."
    fi

    source /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        error "Installer ini hanya mendukung Ubuntu."
    fi

    case "$VERSION_ID" in
        24.04|24.10|25.04|25.10)
            ;;
        *)
            warn "Ubuntu $VERSION_ID belum diuji oleh installer ini."
            ;;
    esac

    log "OS: Ubuntu $VERSION_ID"
}

check_arch() {
    local arch

    arch="$(dpkg --print-architecture)"

    case "$arch" in
        amd64)
            log "Architecture: amd64"
            ;;
        *)
            error "Architecture tidak didukung: $arch"
            ;;
    esac
}

system_info() {
    info "Hostname : $(hostname)"
    info "Kernel   : $(uname -r)"
    info "RAM      : $(free -h | awk '/^Mem:/ {print $2}')"
    info "Disk     : $(df -h / | awk 'NR==2 {print $4 " free"}')"
}

apt_install() {
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y
    apt-get install -y "$@"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

ask_required() {
    local prompt="$1"
    local value=""

    while [[ -z "$value" ]]; do
        read -r -p "$prompt: " value
    done

    printf '%s' "$value"
}

health_check() {
    echo
    info "=========================================="
    info "             HEALTH CHECK"
    info "=========================================="

    if command_exists nginx; then
        if nginx -t >/dev/null 2>&1; then
            log "Nginx: OK"
        else
            warn "Nginx: konfigurasi bermasalah"
        fi
    else
        warn "Nginx: belum terinstall"
    fi

    if command_exists php; then
        log "PHP: $(php -r 'echo PHP_VERSION;')"
    else
        warn "PHP: belum terinstall"
    fi

    if systemctl is-active --quiet mariadb 2>/dev/null; then
        log "MariaDB: active"
    else
        warn "MariaDB: tidak active"
    fi

    if systemctl is-active --quiet redis-server 2>/dev/null ||
       systemctl is-active --quiet redis 2>/dev/null; then
        log "Redis: active"
    else
        warn "Redis: tidak active"
    fi

    if systemctl is-active --quiet docker 2>/dev/null; then
        log "Docker: active"
    else
        warn "Docker: tidak active"
    fi

    if systemctl is-active --quiet wings 2>/dev/null; then
        log "Wings: active"
    else
        warn "Wings: tidak active"
    fi

    if [[ -f /var/www/pterodactyl/artisan ]]; then
        log "Pterodactyl Panel: source ditemukan"
    else
        warn "Pterodactyl Panel: belum ditemukan"
    fi

    echo
}
