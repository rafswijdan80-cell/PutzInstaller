#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

install_docker() {

    if command_exists docker &&
       systemctl is-active --quiet docker; then

        log "Docker sudah terinstall dan aktif."
        return
    fi

    info "Menginstall dependency Docker..."

    apt_install \
        ca-certificates \
        curl \
        gnupg

    info "Mempersiapkan Docker repository..."

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL \
        https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    source /etc/os-release

    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list

    info "Menginstall Docker..."

    apt-get update -y

    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    if ! systemctl is-active --quiet docker; then
        journalctl -u docker -n 40 --no-pager
        error "Docker gagal dijalankan."
    fi

    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon tidak dapat diakses."
    fi

    log "Docker berhasil aktif."
    docker --version
}

install_docker
