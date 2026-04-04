#!/usr/bin/env bash
set -euo pipefail

#--- Constants ---#
readonly CORE_URL="https://raw.githubusercontent.com/zenkiet/public-bash-script/main/bash/core.sh?v=$(date +%s)"
readonly REPO="Infisical/cli"
readonly INSTALL_DIR="/usr/bin"
readonly BINARY_NAME="infisical"
readonly GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"
readonly DEFAULT_INFISICAL_URL="https://app.infisical.com"
readonly DEFAULT_AGENT_DIR="/etc/infisical-agent"

#--- State ---#
OS_NAME=""
ARCH_NAME=""
CLI_ARCH_SUFFIX=""
LATEST_VERSION=""
TMP_DIR=""

#--- Bootstrap ---#
source <(curl -fsSL --connect-timeout 10 --max-time 30 "$CORE_URL" || {
    echo -e "\033[0;31m[ERROR]\033[0m Failed to fetch core.sh from GitHub. Check your network." >&2
    exit 1
})

#--- Cleanup ---#
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

#--- Functions ---#
map_cli_arch_suffix() {
    case "$ARCH_NAME" in
        x86_64) echo "amd64" ;;
        x86)    echo "386" ;;
        arm64)  echo "arm64" ;;
        armv7)  echo "armv7" ;;
        armv6)  echo "armv6" ;;
        *)      log_error "Unsupported architecture for Infisical CLI: $ARCH_NAME"; exit 1 ;;
    esac
}

fetch_latest_version() {
    log_info "Fetching latest Infisical CLI version from GitHub API..."

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
        "$BINARY_NAME" --version 2>/dev/null | head -n1 | sed -E 's/^[^0-9]*//; s/[[:space:]].*//' || echo "unknown"
    else
        echo "none"
    fi
}

find_extracted_binary() {
    local found
    found=$(find "$TMP_DIR" -maxdepth 3 -type f -name "$BINARY_NAME" 2>/dev/null | head -n1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi
    return 1
}

install_cli_binary() {
    local version="${LATEST_VERSION#v}"
    local filename="cli_${version}_linux_${CLI_ARCH_SUFFIX}.tar.gz"
    local download_url="https://github.com/${REPO}/releases/download/${LATEST_VERSION}/${filename}"

    TMP_DIR=$(mktemp -d)
    local tar_file="${TMP_DIR}/${filename}"

    log_info "Platform  : Linux / ${CLI_ARCH_SUFFIX}"
    log_info "Version   : ${LATEST_VERSION}"
    log_info "URL       : ${download_url}"
    echo

    if ! curl -fsSL --progress-bar --connect-timeout 15 "$download_url" -o "$tar_file" </dev/null; then
        echo
        log_error "Download failed. Please check your internet connection and architecture support."
        exit 1
    fi

    echo
    log_info "Extracting archive ($(du -h "$tar_file" | cut -f1))..."
    tar -xzf "$tar_file" -C "$TMP_DIR"

    local bin_path
    if ! bin_path=$(find_extracted_binary); then
        log_error "Binary '$BINARY_NAME' not found in archive. Unexpected archive structure."
        exit 1
    fi

    log_info "Installing to ${INSTALL_DIR}/${BINARY_NAME}..."
    mv "$bin_path" "${INSTALL_DIR}/${BINARY_NAME}"
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
}

prompt_nonempty() {
    local label="$1"
    local default="${2:-}"
    local value=""
    while [ -z "$value" ]; do
        if [ -n "$default" ]; then
            echo -n "  ${label} [${default}]: "
        else
            echo -n "  ${label}: "
        fi
        read -r value
        if [ -z "$value" ] && [ -n "$default" ]; then
            value="$default"
        fi
        if [ -z "$value" ]; then
            log_warn "This value cannot be empty."
        fi
    done
    echo "$value"
}

prompt_secret() {
    local label="$1"
    local value=""
    while [ -z "$value" ]; do
        echo -n "  ${label} (hidden): "
        read -rs value
        echo
        if [ -z "$value" ]; then
            log_warn "This value cannot be empty."
        fi
    done
    echo "$value"
}

write_secret_template() {
    local out="$1"
    local slug="$2"
    local env_slug="$3"
    local secret_path="$4"
    local recursive="$5"

    local rec_json="false"
    [[ "$recursive" =~ ^[Yy] ]] && rec_json="true"

    # listSecretsByProjectSlug "<slug>" "<env>" "<path>" `{"recursive": ..., "expandSecretReferences": true}`
    {
        printf '%s\n' "{{- with listSecretsByProjectSlug \"${slug}\" \"${env_slug}\" \"${secret_path}\" \`{\"recursive\": ${rec_json}, \"expandSecretReferences\": true}\` }}"
        printf '%s\n' "{{- range . }}"
        printf '%s\n' "{{ .Key }}={{ .Value }}"
        printf '%s\n' "{{- end }}"
        printf '%s\n' "{{- end }}"
    } >"$out"
}

#--- Actions ---#
action_install_cli() {
    log_section "Install Infisical CLI"
    local installed
    installed=$(get_installed_version)

    if [ "$installed" != "none" ]; then
        log_warn "Infisical CLI is already installed (version: $installed)."
        prompt_confirm "Reinstall anyway?" || { log_info "Installation aborted."; return; }
    fi

    fetch_latest_version
    install_cli_binary

    echo
    log_ok "Infisical CLI ${LATEST_VERSION} installed successfully."
    log_ok "The agent runs as: ${BINARY_NAME} agent --config <file.yaml>"
}

action_upgrade_cli() {
    log_section "Upgrade Infisical CLI"
    local installed
    installed=$(get_installed_version)

    if [ "$installed" == "none" ]; then
        log_warn "Infisical CLI is not installed. Use option 1 first."
        return
    fi

    log_info "Installed version : v${installed}"
    fetch_latest_version
    log_info "Latest version    : ${LATEST_VERSION}"

    if [ "v${installed}" == "${LATEST_VERSION}" ]; then
        echo
        log_ok "You already have the latest version."
        return
    fi

    echo
    prompt_confirm "Upgrade from v${installed} to ${LATEST_VERSION}?" "Y" || { log_info "Upgrade aborted."; return; }

    echo
    install_cli_binary

    echo
    log_ok "Successfully upgraded to ${LATEST_VERSION}."
}

action_uninstall_cli() {
    log_section "Uninstall Infisical CLI"
    local bin_path
    bin_path=$(command -v "$BINARY_NAME" 2>/dev/null || true)

    if [ -z "$bin_path" ]; then
        log_warn "Infisical CLI is not installed."
        return
    fi

    log_info "Found binary at: $bin_path"
    echo
    prompt_confirm "Remove $bin_path permanently?" || { log_info "Uninstallation aborted."; return; }

    rm -f "$bin_path"
    echo
    log_ok "Infisical CLI has been uninstalled."
}

action_configure_agent() {
    log_section "Configure Infisical Agent (wizard)"

    if [ "$(get_installed_version)" == "none" ]; then
        log_error "Install Infisical CLI first (option 1)."
        return
    fi

    echo
    log_info "This wizard builds a minimal agent.yaml + credential files + Go templates."
    log_info "Docs: https://infisical.com/docs/integrations/platforms/infisical-agent"
    echo

    log_section "Step 1 — Infisical server URL"
    local infisical_url
    infisical_url=$(prompt_nonempty "Infisical API base URL" "$DEFAULT_INFISICAL_URL")

    log_section "Step 2 — Agent config directory"
    local agent_dir
    agent_dir=$(prompt_nonempty "Directory for agent.yaml, credentials, and templates" "$DEFAULT_AGENT_DIR")
    mkdir -p "${agent_dir}/templates"

    log_section "Step 3 — Universal Auth (client id / secret)"
    log_info "Create a Machine Identity with Universal Auth in Infisical, then paste values below."
    log_info "Agent reads credentials from files (not inline in YAML)."
    echo
    local client_id client_secret remove_secret
    client_id=$(prompt_nonempty "Client ID")
    client_secret=$(prompt_secret "Client Secret")
    echo -n "  Remove client secret file after first read? [y/N]: "
    read -r remove_secret

    local client_id_file="${agent_dir}/client-id"
    local client_secret_file="${agent_dir}/client-secret"
    umask 077
    printf '%s' "$client_id" >"$client_id_file"
    printf '%s' "$client_secret" >"$client_secret_file"
    chmod 600 "$client_id_file" "$client_secret_file"
    umask 022
    log_ok "Wrote ${client_id_file} and ${client_secret_file} (mode 600)."

    local remove_yaml="false"
    [[ "$remove_secret" =~ ^[Yy]$ ]] && remove_yaml="true"

    log_section "Step 4 — Access token sink (optional)"
    log_info "Optional: path where the agent writes a renewed Infisical access token (for SDKs/API)."
    echo -n "  Token file path (leave empty to skip sinks): "
    read -r sink_path

    log_section "Step 5 — Secret templates → .env (repeat)"
    local templates_yaml=""
    local idx=0
    while true; do
        idx=$((idx + 1))
        echo
        log_info "--- Template #${idx} ---"
        local slug env_slug secret_path recursive dest poll
        slug=$(prompt_nonempty "Project slug (e.g. my-backend)")
        env_slug=$(prompt_nonempty "Environment slug (e.g. dev, staging, prod)" "dev")
        secret_path=$(prompt_nonempty "Secret path in Infisical" "/")
        echo -n "  List secrets recursively under that path? [y/N]: "
        read -r recursive

        local tmpl_name="secrets-${idx}.tmpl"
        local tmpl_path="${agent_dir}/templates/${tmpl_name}"
        write_secret_template "$tmpl_path" "$slug" "$env_slug" "$secret_path" "$recursive"
        log_ok "Wrote template: ${tmpl_path}"

        dest=$(prompt_nonempty "Destination file for rendered secrets (e.g. /opt/myapp/.env)")
        poll=$(prompt_nonempty "Polling interval when checking for secret changes" "5m")

        templates_yaml+=$(printf '%s\n' "  - source-path: \"${tmpl_path}\"")
        templates_yaml+=$(printf '\n    destination-path: \"%s\"' "$dest")
        templates_yaml+=$(printf '\n    config:')
        templates_yaml+=$(printf '\n      polling-interval: \"%s\"' "$poll")
        templates_yaml+=$(printf '\n')

        echo
        prompt_confirm "Add another template?" "N" || break
    done

    local config_path="${agent_dir}/agent.yaml"
    {
        printf '%s\n' "infisical:"
        printf '%s\n' "  address: \"${infisical_url}\""
        printf '%s\n' "auth:"
        printf '%s\n' "  type: \"universal-auth\""
        printf '%s\n' "  config:"
        printf '%s\n' "    client-id: \"${client_id_file}\""
        printf '%s\n' "    client-secret: \"${client_secret_file}\""
        printf '%s\n' "    remove_client_secret_on_read: ${remove_yaml}"
        if [ -n "$sink_path" ]; then
            printf '%s\n' "sinks:"
            printf '%s\n' "  - type: \"file\""
            printf '%s\n' "    config:"
            printf '%s\n' "      path: \"${sink_path}\""
        fi
        printf '%s\n' "templates:"
        printf '%s\n' "$templates_yaml"
    } >"$config_path"

    chmod 644 "$config_path" 2>/dev/null || true

    echo
    log_ok "Wrote agent config: ${config_path}"
    log_info "Run the agent (foreground test):"
    echo "  ${BINARY_NAME} agent --config ${config_path}"
    log_info "Ensure the destination paths are writable by the user that runs the agent."
}

#--- Header ---#
print_header() {
    [ -t 1 ] && clear

    local installed
    installed=$(get_installed_version)
    local status_msg

    if [ "$installed" == "none" ]; then
        status_msg="${RED}CLI not installed${NC}"
    else
        status_msg="${GREEN}CLI v${installed}${NC}"
    fi

    echo
    echo -e "  ${BOLD}============================================${NC}"
    echo -e "  ${BOLD}           Infisical Agent Setup            ${NC}"
    echo -e "  ${BOLD}============================================${NC}"
    echo -e "  Status: ${status_msg}  |  Arch: ${CYAN}linux/${CLI_ARCH_SUFFIX}${NC}"
    echo -e "  ${BOLD}============================================${NC}"
    echo
    echo -e "  ${BOLD}  1.${NC} Install Infisical CLI"
    echo -e "  ${BOLD}  2.${NC} Upgrade Infisical CLI"
    echo -e "  ${BOLD}  3.${NC} Uninstall Infisical CLI"
    echo -e "  ${BOLD}  4.${NC} Configure agent (wizard: auth + templates + .env path)"
    echo -e "  ${BOLD}  5.${NC} Exit"
    echo
    echo -e "  ${BOLD}============================================${NC}"
}

#--- Main ---#
main() {
    check_root
    check_commands "curl" "tar"

    OS_NAME=$(detect_os)
    ARCH_NAME=$(detect_arch)
    CLI_ARCH_SUFFIX=$(map_cli_arch_suffix)

    while true; do
        print_header
        echo -n "  Select an option [1-5]: "
        read -r choice

        case "$choice" in
            1) action_install_cli    ;;
            2) action_upgrade_cli    ;;
            3) action_uninstall_cli  ;;
            4) action_configure_agent ;;
            5)
                echo
                log_info "Goodbye."
                echo
                exit 0
                ;;
            *)
                echo
                log_error "Invalid option '$choice'. Please enter a number from 1 to 5."
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
