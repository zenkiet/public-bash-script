#!/usr/bin/env bash
set -euo pipefail

#--- Constants ---#
readonly CORE_URL="https://raw.githubusercontent.com/zenkiet/public-bash-script/main/bash/core.sh?v=$(date +%s)"
readonly REPO="jesseduffield/lazydocker"
readonly INSTALL_DIR="/usr/local/bin"
readonly BINARY_NAME="lazydocker"
readonly GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"

#--- State ---#
OS_NAME=""
ARCH_NAME=""
LATEST_VERSION=""
TMP_DIR=""

#--- Bootstrap ---#
source <(curl -fsSL --connect-timeout 10 --max-time 30 "$CORE_URL" || {
    echo -e "\033[0;31m[ERROR]\033[0m Failed to fetch core.sh from GitHub. Check your network." >&2
    exit 1
})

# --- Cleanup ---#
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

#--- Functions ---#
fetch_latest_version() {
    log_info "Fetching latest version from GitHub API..."

    local auth_header=""
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
    fi

    LATEST_VERSION=$(curl -fsSL ${auth_header:+-H "$auth_header"} --connect-timeout 10 "$GITHUB_API" </dev/null \
        | grep '"tag_name":' \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        || true)

    if [ -z "$LATEST_VERSION" ]; then
        log_error "Failed to fetch latest version from GitHub API. (Maybe rate-limited? Export GITHUB_TOKEN)"
        exit 1
    fi
}

get_installed_version() {
    if command -v "$BINARY_NAME" &>/dev/null; then
        "$BINARY_NAME" --version 2>/dev/null | grep -i '^Version:' | awk '{print $2}' || echo "unknown"
    else
        echo "none"
    fi
}

install_binary() {
    local version="${LATEST_VERSION#v}"
    local filename="${BINARY_NAME}_${version}_${OS_NAME}_${ARCH_NAME}.tar.gz"
    local download_url="https://github.com/${REPO}/releases/download/${LATEST_VERSION}/${filename}"

    TMP_DIR=$(mktemp -d)
    local tar_file="${TMP_DIR}/${filename}"

    log_info "Platform  : ${OS_NAME} / ${ARCH_NAME}"
    log_info "Version   : ${LATEST_VERSION}"
    log_info "URL       : ${download_url}"
    echo

    if ! curl -fsSL --progress-bar --connect-timeout 15 "$download_url" -o "$tar_file" </dev/null; then
        echo
        log_error "Download failed. Please check your internet connection."
        exit 1
    fi

    echo
    log_info "Extracting archive ($(du -h "$tar_file" | cut -f1))..."
    tar -xzf "$tar_file" -C "$TMP_DIR"

    if [ ! -f "${TMP_DIR}/${BINARY_NAME}" ]; then
        log_error "Binary not found in archive. Unexpected archive structure."
        exit 1
    fi

    log_info "Installing to ${INSTALL_DIR}/${BINARY_NAME}..."
    mv "${TMP_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
}

#--- Actions ---#
action_install() {
    log_section "Install"
    local installed
    installed=$(get_installed_version)

    if [ "$installed" != "none" ]; then
        log_warn "lazydocker is already installed (version: $installed)."
        prompt_confirm "Reinstall anyway?" || { log_info "Installation aborted."; return; }
    fi

    fetch_latest_version
    install_binary

    echo
    log_ok "lazydocker ${LATEST_VERSION} installed successfully."
    log_ok "Run it with: lazydocker"
}

action_upgrade() {
    log_section "Upgrade"
    local installed
    installed=$(get_installed_version)

    if [ "$installed" == "none" ]; then
        log_warn "lazydocker is not installed. Use option 1 to install it first."
        return
    fi

    log_info "Installed version : v${installed}"
    fetch_latest_version
    log_info "Latest version    : ${LATEST_VERSION}"

    if [ "v${installed}" == "${LATEST_VERSION}" ]; then
        echo
        log_ok "You already have the latest version. No upgrade needed."
        return
    fi

    echo
    prompt_confirm "Upgrade from v${installed} to ${LATEST_VERSION}?" "Y" || { log_info "Upgrade aborted."; return; }

    echo
    install_binary

    echo
    log_ok "Successfully upgraded to ${LATEST_VERSION}."
}

action_uninstall() {
    log_section "Uninstall"
    local bin_path
    bin_path=$(command -v "$BINARY_NAME" 2>/dev/null || true)

    if [ -z "$bin_path" ]; then
        log_warn "lazydocker is not installed."
        return
    fi

    log_info "Found binary at: $bin_path"
    echo
    prompt_confirm "Remove $bin_path permanently?" || { log_info "Uninstallation aborted."; return; }

    rm -f "$bin_path"
    echo
    log_ok "lazydocker has been uninstalled successfully."
}

#--- Header ---#
print_header() {
    [ -t 1 ] && clear

    local installed
    installed=$(get_installed_version)
    local status_msg

    if [ "$installed" == "none" ]; then
        status_msg="${RED}Not Installed${NC}"
    else
        status_msg="${GREEN}v${installed}${NC}"
    fi

    echo
    echo -e "  ${BOLD}============================================${NC}"
    echo -e "  ${BOLD}              lazydocker                    ${NC}"
    echo -e "  ${DIM}  https://github.com/${REPO}  ${NC}"
    echo -e "  ${BOLD}============================================${NC}"
    echo -e "  Status: ${status_msg}  |  Platform: ${CYAN}${OS_NAME}/${ARCH_NAME}${NC}"
    echo -e "  ${BOLD}============================================${NC}"
    echo
    echo -e "  ${BOLD}  1.${NC} Install"
    echo -e "  ${BOLD}  2.${NC} Upgrade"
    echo -e "  ${BOLD}  3.${NC} Uninstall"
    echo -e "  ${BOLD}  4.${NC} Exit"
    echo
    echo -e "  ${BOLD}============================================${NC}"
}

#--- Main ---#
main() {
    check_root
    check_commands "curl" "tar"

    OS_NAME=$(detect_os)
    ARCH_NAME=$(detect_arch)

    while true; do
        print_header
        echo -n "  Select an option [1-4]: "
        read -r choice

        case "$choice" in
            1) action_install   ;;
            2) action_upgrade   ;;
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

#--- Main ---#
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi