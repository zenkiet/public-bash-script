#!/usr/bin/env bash
set -euo pipefail

#--- Constants ---#
readonly CORE_URL="https://raw.githubusercontent.com/zenkiet/public-bash-script/main/bash/core.sh?v=$(date +%s)"
readonly GET_DOCKER_URL="https://get.docker.com"

#--- Bootstrap ---#
source <(curl -fsSL --connect-timeout 10 --max-time 30 "$CORE_URL" || {
    echo -e "\033[0;31m[ERROR]\033[0m Failed to fetch core.sh from GitHub. Check your network." >&2
    exit 1
})

#--- Helpers ---#
get_docker_status() {
    if ! command -v docker &>/dev/null; then
        echo "none"
    elif ! docker info &>/dev/null; then
        echo "stopped"
    else
        echo "running"
    fi
}

get_os_id() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

#--- Actions ---#
action_install() {
    log_section "Install Docker"
    local status
    status=$(get_docker_status)
    local os_id
    os_id=$(get_os_id)

    if [ "$status" != "none" ]; then
        log_warn "Docker is already installed."
        prompt_confirm "Reinstall anyway?" "N" || return
    fi

    if [ "$(uname -s)" != "Linux" ]; then
        log_error "This script supports Linux only."
        return
    fi

    if [ "$os_id" == "alpine" ]; then
        log_info "Alpine Linux detected. Installing via apk..."
        apk update
        apk add docker docker-cli-compose

        log_info "Enabling and starting Docker service (OpenRC)..."
        rc-update add docker boot
        service docker start
    else
        log_info "Downloading and running get.docker.com script..."
        curl -fsSL "$GET_DOCKER_URL" | sh

        log_info "Enabling and starting Docker service (systemd)..."
        systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
    fi

    echo
    log_ok "Docker installed successfully."
    log_info "To manage Docker without sudo, run:"
    echo "  usermod -aG docker \$USER && newgrp docker"
}

action_prune() {
    log_section "System Prune"
    if [ "$(get_docker_status)" != "running" ]; then
        log_error "Docker daemon is not running."
        return
    fi

    log_warn "This will remove ALL unused containers, networks, images, and dangling volumes."
    prompt_confirm "Are you sure you want to proceed?" "N" || { log_info "Prune aborted."; return; }

    echo
    docker system prune -a --volumes -f
    echo
    log_ok "System pruned successfully."
}

action_uninstall() {
    log_section "Uninstall Docker"
    local os_id
    os_id=$(get_os_id)

    if [ "$(get_docker_status)" == "none" ]; then
        log_warn "Docker is not installed."
        return
    fi

    log_warn "This will COMPLETELY remove Docker Engine, CLI, Containerd, and Compose packages."
    prompt_confirm "Are you SURE you want to uninstall Docker?" "N" || { log_info "Uninstall aborted."; return; }

    log_info "Stopping Docker services..."
    if [ "$os_id" == "alpine" ]; then
        service docker stop || true
        log_info "Purging Docker packages..."
        apk del docker docker-cli-compose || true
    else
        systemctl stop docker docker.socket containerd || true
        log_info "Purging Docker packages..."
        apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras || true
        apt-get autoremove -y --purge || true
    fi

    echo
    if prompt_confirm "Remove ALL Docker data (images, containers, volumes) in /var/lib/docker? THIS CANNOT BE UNDONE." "N"; then
        rm -rf /var/lib/docker /var/lib/containerd
        log_ok "Docker data removed."
    else
        log_info "Docker data preserved."
    fi

    echo
    log_ok "Docker has been uninstalled successfully."
}

#--- Header ---#
print_header() {
    [ -t 1 ] && clear

    local status
    status=$(get_docker_status)
    local status_msg

    case "$status" in
        "none")    status_msg="${RED}Not Installed${NC}" ;;
        "stopped") status_msg="${YELLOW}Installed (Daemon Stopped)${NC}" ;;
        "running") status_msg="${GREEN}Running${NC}" ;;
    esac

    echo
    echo -e "  ${BOLD}============================================${NC}"
    echo -e "  ${BOLD}           Docker Engine Manager            ${NC}"
    echo -e "  ${DIM}  Manages Docker lifecycle & cleanup      ${NC}"
    echo -e "  ${BOLD}============================================${NC}"
    echo -e "  Status: ${status_msg} | OS: ${CYAN}$(get_os_id)${NC}"
    echo -e "  ${BOLD}============================================${NC}"
    echo
    echo -e "  ${BOLD}  1.${NC} Install Docker"
    echo -e "  ${BOLD}  2.${NC} System Prune (Deep Clean)"
    echo -e "  ${BOLD}  3.${NC} Uninstall Docker"
    echo -e "  ${BOLD}  4.${NC} Exit"
    echo
    echo -e "  ${BOLD}============================================${NC}"
}

#--- Main ---#
main() {
    check_commands "curl"

    while true; do
        print_header
        echo -n "  Select an option [1-4]: "
        read -r choice

        case "$choice" in
            1) action_install   ;;
            2) action_prune     ;;
            3) action_uninstall ;;
            4)
                echo
                log_info "Goodbye."
                echo
                exit 0
                ;;
            *)
                echo
                log_error "Invalid option '$choice'. Please enter a number from 1 to 4."
                ;;
        esac

        echo
        echo -n "  Press Enter to return to menu..."
        read -r
    done
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi