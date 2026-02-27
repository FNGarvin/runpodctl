#!/usr/bin/env bash

# Unified Installer for RunPod CLI Tool (CI-Only Resilient Base)
#
# This script is a "resilient" version of the original installer,
# tuned to handle current download naming conventions while remaining ROOT-ONLY
# on Linux to demonstrate feature isolation on the CI branch.

set -e

# -------------------------------- Check Root -------------------------------- #
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root with sudo."
        exit 1
    fi
}

# ------------------------- Install Required Packages ------------------------ #
check_system_requirements() {
    for cmd in wget tar grep sed; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: Missing required command: $cmd"
            exit 1
        fi
    done
}

# ----------------------------- runpodctl Version ---------------------------- #
fetch_latest_version() {
    local version_url="https://api.github.com/repos/runpod/runpodctl/releases/latest"
    VERSION=$(wget -q -O- "$version_url" | grep '"tag_name":' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    if [ -z "$VERSION" ]; then
        echo "Failed to fetch version."
        exit 1
    fi
    echo "Latest version of runpodctl: $VERSION"
}

# ------------------------------- Download URL ------------------------------- #
download_url_constructor() {
    local os_type=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch_type=$(uname -m)

    case "$os_type" in
        darwin) os_type="darwin"; arch_type="all" ;;
        linux)
            os_type="linux"
            case "$arch_type" in
                x86_64) arch_type="amd64" ;;
                aarch64|arm64) arch_type="arm64" ;;
                *)
                    echo "Unsupported Linux architecture: $arch_type"
                    exit 1
                    ;;
            esac
            ;;
    esac

    # Dual-URL Resilience
    URL1="https://github.com/runpod/runpodctl/releases/download/${VERSION}/runpodctl-${os_type}-${arch_type}.tar.gz"
    VER_STR=$(echo "$VERSION" | sed 's/^v//')
    URL2="https://github.com/runpod/runpodctl/releases/download/${VERSION}/runpodctl-${VER_STR}-${os_type}-${arch_type}.tar.gz"
    DOWNLOAD_URLS=("$URL1" "$URL2")
}

# ----------------------------- Homebrew Support ----------------------------- #
try_brew_install() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        return 1
    fi

    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew not detected. Falling back to binary installation..."
        return 1
    fi

    echo "macOS detected. Attempting to install runpodctl via Homebrew..."
    
    # Homebrew prefers not to run as root.
    if [ "$EUID" -eq 0 ]; then
        local original_user
        original_user=$(logname 2>/dev/null || echo "$SUDO_USER")
        if [[ -n "$original_user" && "$original_user" != "root" ]]; then
            if su - "$original_user" -c "brew install runpodctl"; then
                echo "runpodctl installed successfully via Homebrew."
                exit 0
            fi
        fi
    else
        if brew install runpodctl; then
            echo "runpodctl installed successfully via Homebrew."
            exit 0
        fi
    fi

    echo "Homebrew installation failed or was skipped. Falling back to binary..."
    return 1
}

# ---------------------------- Download & Install ---------------------------- #
download_and_install_cli() {
    local success=false
    for url in "${DOWNLOAD_URLS[@]}"; do
        if wget --progress=bar "$url" -O runpodctl.tar.gz; then
            success=true; break
        fi
    done

    if [ "$success" = false ]; then echo "Download failed."; exit 1; fi

    tar -xzf runpodctl.tar.gz runpodctl || { echo "Failed to extract runpodctl."; exit 1; }
    chmod +x runpodctl
    mv runpodctl /usr/local/bin/ || { echo "Failed to move runpodctl to /usr/local/bin/. (Permissions?)"; exit 1; }
    echo "runpodctl installed successfully to /usr/local/bin."
}

# ----------------------------------- Main ----------------------------------- #
echo "Installing runpodctl (CI Resilient Base)..."

# 1. Prioritize Homebrew on macOS
if try_brew_install; then
    exit 0
fi

# 2. Resilient Binary Installation (Strict Root-Only for Linux)
check_root
check_system_requirements
fetch_latest_version
download_url_constructor
download_and_install_cli
