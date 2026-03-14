#!/usr/bin/env bash

#--- Colors ---#
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    GREEN='' BLUE='' YELLOW='' RED='' CYAN='' BOLD='' DIM='' NC=''
fi

#--- Logging ---#
log_info()    { echo -e "  ${BLUE}[INFO]${NC}    $*"; }
log_ok()      { echo -e "  ${GREEN}[OK]${NC}      $*"; }
log_warn()    { echo -e "  ${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "  ${RED}[ERROR]${NC}   $*" >&2; }
log_section() { echo -e "\n  ${BOLD}${CYAN}>> $*${NC}"; echo -e "  ${DIM}$(printf '%0.s-' {1..44})${NC}"; }

#--- Dependency ---#
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo
        log_error "This script must be run as root or with sudo."
        echo
        exit 1
    fi
}

check_commands() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
}

#--- Functions ---#
prompt_confirm() {
    local message="$1"
    local default="${2:-N}"
    local prompt

    if [[ "$default" =~ ^[Yy]$ ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    echo -n "  $message $prompt: "
    read -r reply

    reply="${reply:-$default}"

    [[ "$reply" =~ ^[Yy]$ ]]
}

detect_os() {
    local os
    os=$(uname -s)
    if [ "$os" != "Linux" ]; then
        log_error "Unsupported OS: $os. This script targets Linux only."
        exit 1
    fi
    echo "Linux"
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)          echo "x86_64" ;;
        i386|i686)       echo "x86" ;;
        aarch64|arm64)   echo "arm64" ;;
        armv7l)          echo "armv7" ;;
        armv6l)          echo "armv6" ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}