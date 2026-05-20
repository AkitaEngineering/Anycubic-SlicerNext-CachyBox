#!/bin/bash

# --- Configuration & Colors ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

APP_NAME="Elegoo Slicer"
APP_ID="ElegooSlicer"
APP_SLUG="elegoo-slicer"
APP_RUNTIME_DIR="/opt/$APP_ID"
APP_LAUNCHER="/usr/local/bin/$APP_ID"
APP_DESKTOP="$APP_ID.desktop"

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo -e "$APP_NAME Installer (Universal Bash)"
echo -e "${BLUE}--------------------------------------------------------${NC}"

# --- CLI options & Logging ---
LOG_DIR="$HOME/.cache/elegoo-installer"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install.log"
LAST_STEP_FILE="$LOG_DIR/last_failed_step"

log(){
    local level="$1"; shift
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo -e "[$ts] [$level] $*" | tee -a "$LOG_FILE"
}

NVIDIA_CONTAINER_SUPPORT_OVERRIDE=false

has_nvidia_cdi_spec(){
    find /etc/cdi /var/run/cdi -maxdepth 1 -type f \( -iname '*nvidia*.yaml' -o -iname '*nvidia*.json' \) -print -quit 2>/dev/null | grep -q .
}

has_nvidia_container_support(){
    [ "$NVIDIA_CONTAINER_SUPPORT_OVERRIDE" = true ] && return 0
    command -v podman &>/dev/null || return 1
    command -v nvidia-smi &>/dev/null || return 1
    has_nvidia_cdi_spec && return 0
    return 1
}

can_auto_configure_nvidia_host(){
    command -v pacman &>/dev/null
}

configure_nvidia_container_support(){
    if has_nvidia_container_support; then
        log "INFO" "Nvidia container support is already configured."
        return 0
    fi

    if ! can_auto_configure_nvidia_host; then
        log "WARN" "Automatic Nvidia host setup is only supported on Arch/CachyOS hosts with pacman."
        return 1
    fi

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would install nvidia-container-toolkit and generate /etc/cdi/nvidia.yaml"
        NVIDIA_CONTAINER_SUPPORT_OVERRIDE=true
        return 0
    fi

    log "INFO" "Installing nvidia-container-toolkit on the host"
    run_logged sudo pacman -S --needed --noconfirm nvidia-container-toolkit || return 1
    command -v nvidia-ctk &>/dev/null || {
        log "ERROR" "nvidia-ctk was not found after installing nvidia-container-toolkit."
        return 1
    }

    log "INFO" "Generating Nvidia CDI spec at /etc/cdi/nvidia.yaml"
    run_logged sudo install -d -m 0755 /etc/cdi || return 1
    run_logged sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml || return 1

    has_nvidia_container_support || {
        log "ERROR" "Nvidia CDI support is still unavailable after automatic setup."
        return 1
    }

    NVIDIA_CONTAINER_SUPPORT_OVERRIDE=true
    return 0
}

run_logged(){
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run: $*"
        return 0
    fi

    "$@" 2>&1 | tee -a "$LOG_FILE"
    return ${PIPESTATUS[0]:-0}
}

resolve_latest_elegoo_url(){
    local latest_response latest_url

    if [ -n "$ELEGOO_URL" ]; then
        case "$ELEGOO_URL_SOURCE" in
            cli)
                log "INFO" "Using $APP_NAME AppImage URL from CLI: $ELEGOO_URL"
                ;;
            environment)
                log "INFO" "Using $APP_NAME AppImage URL from environment: $ELEGOO_URL"
                ;;
        esac
        return 0
    fi

    latest_response=$(curl --fail -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 60 \
        -H 'Accept: application/vnd.github+json' "$ELEGOO_LATEST_API" 2>>"$LOG_FILE" || true)

    latest_url=$(printf '%s' "$latest_response" | grep -oE '"browser_download_url":[[:space:]]*"[^"]*ElegooSlicer[^"]*\.AppImage"' | head -n 1 | sed -E 's/.*"([^"]+)"/\1/')
    if [ -z "$latest_url" ]; then
        latest_url=$(printf '%s' "$latest_response" | grep -oE '"browser_download_url":[[:space:]]*"[^"]+AppImage"' | head -n 1 | sed -E 's/.*"([^"]+)"/\1/')
    fi

    if [ -n "$latest_url" ]; then
        ELEGOO_URL="$latest_url"
        log "INFO" "Resolved latest $APP_NAME AppImage: $ELEGOO_URL"
    else
        ELEGOO_URL="$DEFAULT_ELEGOO_URL"
        log "WARN" "Unable to resolve the latest $APP_NAME release; falling back to $ELEGOO_URL"
    fi
}

build_distrobox_create_cmd(){
    local image_name="$1"
    local gpu_flag="$2"
    local additional_flags="$3"

    DBX_CREATE_CMD=(distrobox create --name "$CONTAINER_NAME" --image "$image_name")
    if [ -n "$gpu_flag" ]; then
        DBX_CREATE_CMD+=("$gpu_flag")
    fi
    if [ -n "$additional_flags" ]; then
        DBX_CREATE_CMD+=(--additional-flags "$additional_flags")
    fi
    DBX_CREATE_CMD+=(--yes)
}

# latest-release resolution (can be overridden with ELEGOO_URL or --url)
DEFAULT_ELEGOO_URL="https://github.com/ELEGOO-3D/ElegooSlicer/releases/download/v1.5.0.7/ElegooSlicer_Linux_V1.5.0.7.AppImage"
ELEGOO_LATEST_API="https://api.github.com/repos/ELEGOO-3D/ElegooSlicer/releases/latest"
ELEGOO_URL="${ELEGOO_URL:-}"
ELEGOO_URL_SOURCE=""
if [ -n "$ELEGOO_URL" ]; then
    ELEGOO_URL_SOURCE="environment"
fi

# Prevent running as root: distrobox commands do not behave correctly under sudo
if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Do not run this installer with sudo or as root."
    echo "Please run as your regular user (no sudo): ./install.sh"
    echo "If you intentionally need root distrobox operations, re-run without this script or use distrobox --root commands as documented."
    exit 1
fi

NON_INTERACTIVE=false
DRY_RUN=false
PRECHECK=false
UNINSTALL=false
CONTAINER_NAME="$APP_SLUG"
AUTO_CONFIGURE_NVIDIA=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --non-interactive|--yes|-y)
            NON_INTERACTIVE=true; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --check)
            PRECHECK=true; shift ;;
        --uninstall)
            UNINSTALL=true; shift ;;
        --url)
            ELEGOO_URL="$2"; ELEGOO_URL_SOURCE="cli"; shift 2 ;;
        --container-name)
            CONTAINER_NAME="$2"; shift 2 ;;
        --gpu)
            gpu_choice="$2"; shift 2 ;;
        --configure-nvidia-host)
            AUTO_CONFIGURE_NVIDIA=true; shift ;;
        --image-source)
            img_choice="$2"; shift 2 ;;
        --log-file)
            LOG_FILE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--non-interactive] [--dry-run] [--check] [--uninstall] [--url URL] [--container-name NAME] [--gpu 1-4] [--configure-nvidia-host] [--image-source 1-2]";
            exit 0 ;;
        *) shift ;;
    esac
done

# if uninstall flag passed, delegate to uninstaller script in same directory
if [ "$UNINSTALL" = true ]; then
    log "INFO" "Switching to uninstaller mode"
    exec bash "$(dirname "$0")/uninstall.sh" --container-name "$CONTAINER_NAME" $( [ "$NON_INTERACTIVE" = true ] && echo --yes ) $( [ "$DRY_RUN" = true ] && echo --dry-run )
fi

LAST_STEP="init"

fail(){
    local msg="$1"; shift
    echo
    log "ERROR" "$msg"
    echo "$LAST_STEP" > "$LAST_STEP_FILE" || true
    exit 1
}

trap 'rc=$?; if [ $rc -ne 0 ]; then log "ERROR" "Installer exited with code $rc (last step: $LAST_STEP)"; fi' EXIT

# Helpers: download with retries and run commands (logs + dry-run)
download_with_retries(){
    local url="$1" dest="$2"
    local tries=0 max=5
    while [ $tries -lt $max ]; do
        tries=$((tries+1))
        if [ "$DRY_RUN" = true ]; then
            log "INFO" "DRY RUN: would download $url to $dest (attempt $tries)"
            return 0
        fi
        log "INFO" "Downloading $url (attempt $tries/$max)"
        curl --fail -L --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 300 --progress-bar "$url" -o "$dest" 2>&1 | tee -a "$LOG_FILE"
        if [ ${PIPESTATUS[0]:-0} -eq 0 ]; then
            return 0
        fi
        sleep $((tries * 2))
    done
    return 1
}

# spinner for background operations
spinner(){
    local pid=$1
    local delay=0.1
    local spinstr='|/-\\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%$temp}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

# preflight checks
preflight(){
    log "INFO" "Running preflight checks"
    # check required commands
    for cmd in distrobox podman curl lspci; do
        if ! command -v $cmd &>/dev/null; then
            log "WARN" "Command $cmd not found. Installer may attempt to install it or fail."
            case $cmd in
                distrobox|podman)
                    echo "Install via your package manager (apt/pacman/dnf) or see https://github.com/89luca89/distrobox";
                    ;;
                curl)
                    echo "Install curl (apt install curl)";
                    ;;
                lspci)
                    echo "Install pciutils (apt install pciutils)";
                    ;;
            esac
        fi
    done
    # network check
    if ! ping -c1 github.com &>/dev/null; then
        log "WARN" "Network appears unreachable; downloads will fail."
        echo "WARNING: network check failed"
    fi
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null && ! has_nvidia_container_support; then
        log "WARN" "Nvidia GPU detected but Podman CDI support is not configured. Install nvidia-container-toolkit and generate a CDI spec before using the Nvidia path."
        echo "WARNING: Nvidia container support is not configured for Podman."
        echo "Install nvidia-container-toolkit and generate /etc/cdi/nvidia.yaml, or use Generic rendering."
    fi
    # disk space
    avail=$(df --output=avail -k . | tail -1)
    if [ "$avail" -lt 1048576 ]; then
        log "WARN" "Less than 1GB free; installation may fail."
    fi
    echo "preflight complete"
}


run_in_container(){
    # run command in distrobox container and stream output to log
    local cmd="$*"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run in container: $cmd"
        return 0
    fi
    distrobox enter "$CONTAINER_NAME" -- bash -lc "$cmd" 2>&1 | tee -a "$LOG_FILE"
    return ${PIPESTATUS[0]:-0}
}


# --- Download URL for the latest AppImage release ---
# (may be overridden with --url)

# if --check was given, run preflight and exit
if [ "$PRECHECK" = true ]; then
    preflight
    exit 0
fi

resolve_latest_elegoo_url


# --- GPU Selection ---
# detect hardware and ask the user to choose a driver stack

echo -e "\n${YELLOW}--- GPU Selection ---${NC}"

# allow overriding via CLI
if [ -n "$gpu_choice" ]; then
    log "INFO" "Using GPU selection from CLI: $gpu_choice"
fi
detected_gpu="none"
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    detected_gpu="nvidia"
elif lspci | grep -Ei "VGA|3D" | grep -iq "AMD"; then
    detected_gpu="amd"
elif lspci | grep -Ei "VGA|3D" | grep -iq "Intel"; then
    detected_gpu="intel"
fi

echo -e "Detected Hardware: ${GREEN}$detected_gpu${NC}"

gpu_default="4"
case $detected_gpu in
    "nvidia") gpu_default="1" ;;
    "amd")    gpu_default="2" ;;
    "intel")  gpu_default="3" ;;
esac

echo "1) Nvidia (uses --nvidia flag)"
echo "2) AMD (uses DRI pass-through)"
echo "3) Intel (uses DRI pass-through)"
echo "4) Generic / None / Software Rendering"
if [ -n "$gpu_choice" ]; then
    log "INFO" "Using GPU from CLI: $gpu_choice"
elif [ "$NON_INTERACTIVE" = true ]; then
    gpu_choice=$gpu_default
    log "INFO" "Non-interactive: selecting GPU stack $gpu_choice"
else
    read -p "Select Driver Stack [$gpu_default]: " gpu_choice
    gpu_choice=${gpu_choice:-$gpu_default}
fi

if [ "$gpu_choice" = "1" ] && ! has_nvidia_container_support; then
    echo -e "${YELLOW}Nvidia GPU detected, but Podman GPU support is not configured.${NC}"
    echo "Install nvidia-container-toolkit and generate /etc/cdi/nvidia.yaml to use the Nvidia path."
    if [ "$AUTO_CONFIGURE_NVIDIA" = true ]; then
        log "INFO" "Opt-in Nvidia host setup requested."
        configure_nvidia_container_support || fail "Automatic Nvidia host setup failed."
    fi

    if ! has_nvidia_container_support; then
        if [ "$NON_INTERACTIVE" = true ]; then
            log "WARN" "Nvidia container support is unavailable; falling back to Generic / software rendering."
            gpu_choice=4
        else
            echo "1) Fall back to Generic / None / Software Rendering"
            if can_auto_configure_nvidia_host; then
                echo "2) Install nvidia-container-toolkit and generate CDI spec automatically (Arch/CachyOS only)"
                echo "3) Abort and configure Nvidia container support first"
                read -p "Selection [1]: " nvidia_fallback_choice
                nvidia_fallback_choice=${nvidia_fallback_choice:-1}
                case "$nvidia_fallback_choice" in
                    2)
                        configure_nvidia_container_support || fail "Automatic Nvidia host setup failed."
                        ;;
                    3)
                        fail "Aborted so Nvidia container support can be configured first."
                        ;;
                    *)
                        log "WARN" "Nvidia container support is unavailable; falling back to Generic / software rendering."
                        gpu_choice=4
                        ;;
                esac
            else
                echo "2) Abort and configure Nvidia container support first"
                read -p "Selection [1]: " nvidia_fallback_choice
                nvidia_fallback_choice=${nvidia_fallback_choice:-1}
                if [ "$nvidia_fallback_choice" = "2" ]; then
                    fail "Aborted so Nvidia container support can be configured first."
                fi
                log "WARN" "Nvidia container support is unavailable; falling back to Generic / software rendering."
                gpu_choice=4
            fi
        fi
    fi
fi

GPU_FLAG=""
ADD_FLAGS=""
GPU_TYPE="generic"
CONTAINERFILE="containerfile.amd"

case $gpu_choice in
    1) GPU_FLAG="--nvidia"; GPU_TYPE="nvidia"; CONTAINERFILE="containerfile.nvidia" ;;
    2) ADD_FLAGS="--device /dev/dri:/dev/dri"; GPU_TYPE="amd"; CONTAINERFILE="containerfile.amd" ;;
    3) ADD_FLAGS="--device /dev/dri:/dev/dri"; GPU_TYPE="intel"; CONTAINERFILE="containerfile.intel" ;;
    *) GPU_TYPE="generic"; CONTAINERFILE="containerfile.amd" ;;
esac

# --- Step 2: Image Source ---
echo -e "\n${YELLOW}--- Step 2: Image Source ---${NC}"
echo "1) Standard Ubuntu 24.04 from DockerHub (Default)"
echo "2) Custom Local Containerfile (Build locally)"
if [ -n "$img_choice" ]; then
    log "INFO" "Using image source from CLI: $img_choice"
elif [ "$NON_INTERACTIVE" = true ]; then
    img_choice=1
    log "INFO" "Non-interactive: selecting image source $img_choice"
else
    read -p "Selection [1]: " img_choice
    img_choice=${img_choice:-1}
fi

# Inform user what's next and where logs will go
LAST_STEP="start"
log "INFO" "Starting installation loop. Output will stream to console and $LOG_FILE"
echo -e "\nStarting installation — streaming output to console and log: $LOG_FILE\n"

# --- Step 3: Installation Loop with DNS Retry ---
SUCCESS=false
USE_DNS=false

while [ "$SUCCESS" = false ]; do
    # Cleanup old container if exists
    if distrobox list | grep -q "$CONTAINER_NAME"; then
        distrobox rm -f "$CONTAINER_NAME"
    fi

    CURRENT_ADD_FLAGS="$ADD_FLAGS"
    if [ "$USE_DNS" = true ]; then
        echo -e "${YELLOW}DNS/Network issues detected. Re-creating container with explicit DNS (1.1.1.1)...${NC}"
        CURRENT_ADD_FLAGS="$CURRENT_ADD_FLAGS --dns 1.1.1.1 --dns 8.8.8.8"
    fi

    # Host Dependencies
    LAST_STEP="host:deps"
    missing_host_deps=()
    for host_dep in distrobox podman; do
        if ! command -v "$host_dep" &>/dev/null; then
            missing_host_deps+=("$host_dep")
        fi
    done

    if [ ${#missing_host_deps[@]} -eq 0 ]; then
        log "INFO" "Host dependencies already present: distrobox, podman"
    elif [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would install missing host dependencies via system package manager: ${missing_host_deps[*]}"
    else
        log "INFO" "Installing missing host dependencies: ${missing_host_deps[*]}"
        if command -v pacman &> /dev/null; then
            run_logged sudo pacman -S --needed --noconfirm "${missing_host_deps[@]}" || fail "Failed to install host dependencies. See $LOG_FILE for details."
        elif command -v apt &> /dev/null; then
            run_logged sudo apt update || fail "Failed to update apt metadata. See $LOG_FILE for details."
            run_logged sudo apt install -y "${missing_host_deps[@]}" || fail "Failed to install host dependencies. See $LOG_FILE for details."
        elif command -v dnf &> /dev/null; then
            run_logged sudo dnf install -y "${missing_host_deps[@]}" || fail "Failed to install host dependencies. See $LOG_FILE for details."
        else
            fail "Unknown package manager. Please install these dependencies manually: ${missing_host_deps[*]}"
        fi
    fi

    # Image Preparation
    IMAGE_NAME="ubuntu:24.04"
    if [ "$img_choice" == "2" ]; then
        if [ -f "$CONTAINERFILE" ]; then
            log "INFO" "Building local image from $CONTAINERFILE"
            if [ "$DRY_RUN" = true ]; then
                log "INFO" "DRY RUN: would run podman build -t elegoo-custom-$GPU_TYPE -f $CONTAINERFILE ."
            else
                run_logged podman build -t "elegoo-custom-$GPU_TYPE" -f "$CONTAINERFILE" . || fail "Image build failed. See $LOG_FILE for details."
            fi
            IMAGE_NAME="elegoo-custom-$GPU_TYPE"
        else
            echo -e "${RED}Warning: $CONTAINERFILE not found, using standard image.${NC}"
        fi
    fi

    echo -e "${BLUE}Creating Distrobox container...${NC}"
    LAST_STEP="container:create"
    build_distrobox_create_cmd "$IMAGE_NAME" "$GPU_FLAG" "$CURRENT_ADD_FLAGS"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run: ${DBX_CREATE_CMD[*]}"
    else
        run_logged "${DBX_CREATE_CMD[@]}" || fail "Container creation failed. See $LOG_FILE for details."
    fi

    echo -e "\n${YELLOW}Installing basic packages. This might take a few minutes...${NC}"

    # Package list fixed for Ubuntu 24.04 (Noble)
    LAST_STEP="install:packages"
    log "INFO" "Installing packages and downloading application inside container"
    install_cmds=$(cat <<EOC
    set -euo pipefail
    echo 'Running: apt update'
    sudo apt update
    echo 'Running: apt install (this will stream progress)'
    sudo apt install -y curl ca-certificates lsb-release locales libfuse2* sudo libgl1 libglx-mesa0 libegl1 libgl1-mesa-dri libopengl0 libsm6 libice6 libmspack0t64 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 libwebkit2gtk-4.1-0 libjavascriptcoregtk-4.1-0 libwayland-server0
    echo 'Generating locales'
    sudo locale-gen en_US.UTF-8
    echo 'Downloading $APP_NAME AppImage (with retries)'
    echo 'Downloading with curl (retries)'
    tmp_app=\$(mktemp)
    curl --fail -L --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 300 --progress-bar "$ELEGOO_URL" -o "\$tmp_app"
    chmod +x "\$tmp_app"
    echo 'Installing desktop metadata from the AppImage'
    extract_dir=\$(mktemp -d)
    cd "\$extract_dir"
    "\$tmp_app" --appimage-extract >/dev/null
    sudo rm -rf "$APP_RUNTIME_DIR"
    sudo mkdir -p "$APP_RUNTIME_DIR"
    sudo cp -a squashfs-root/. "$APP_RUNTIME_DIR/"
    printf '#!/bin/sh\nexec %s/AppRun "\$@"\n' "$APP_RUNTIME_DIR" | sudo tee "$APP_LAUNCHER" >/dev/null
    sudo chmod 0755 "$APP_LAUNCHER"
    desktop_src=\$(find squashfs-root -name '*.desktop' | sort | head -n 1)
    [ -n "\$desktop_src" ] || { echo 'AppImage desktop file not found'; exit 1; }
    icon_name=\$(awk -F= '/^Icon=/{print \$2; exit}' "\$desktop_src")
    if [ -n "\$icon_name" ]; then
        icon_src=\$(find squashfs-root \( -path "*/\$icon_name.png" -o -path "*/\$icon_name.svg" -o -path "*/\$icon_name.xpm" -o -name "\$icon_name.png" -o -name "\$icon_name.svg" -o -name "\$icon_name.xpm" \) | sort | head -n 1)
    else
        icon_src=\$(find squashfs-root \( -iname '*ElegooSlicer*.png' -o -iname '*elegoo*.png' -o -iname '*ElegooSlicer*.svg' -o -iname '*elegoo*.svg' \) | sort | head -n 1)
    fi
    sudo install -Dm 0644 "\$desktop_src" "/usr/share/applications/$APP_DESKTOP"
    sudo sed -i 's|^Exec=.*|Exec=$APP_LAUNCHER %F|' "/usr/share/applications/$APP_DESKTOP"
    if grep -q '^TryExec=' "/usr/share/applications/$APP_DESKTOP"; then
        sudo sed -i 's|^TryExec=.*|TryExec=$APP_LAUNCHER|' "/usr/share/applications/$APP_DESKTOP"
    else
        echo 'TryExec=$APP_LAUNCHER' | sudo tee -a "/usr/share/applications/$APP_DESKTOP" >/dev/null
    fi
    if [ -n "\$icon_src" ]; then
        icon_ext=\${icon_src##*.}
        sudo install -Dm 0644 "\$icon_src" "/usr/share/icons/hicolor/192x192/apps/$APP_ID.\$icon_ext"
        sudo sed -i 's|^Icon=.*|Icon=$APP_ID|' "/usr/share/applications/$APP_DESKTOP"
    fi
    if [ -f /run/host/usr/share/cachyos-fish-config/cachyos-config.fish ]; then
        sudo mkdir -p /usr/share/cachyos-fish-config
        sudo ln -sfn /run/host/usr/share/cachyos-fish-config/cachyos-config.fish /usr/share/cachyos-fish-config/cachyos-config.fish
        if [ -d /run/host/usr/share/cachyos-fish-config/conf.d ]; then
            sudo ln -sfn /run/host/usr/share/cachyos-fish-config/conf.d /usr/share/cachyos-fish-config/conf.d
        fi
    fi
    cd /
    rm -rf "\$extract_dir"
    rm -f "\$tmp_app"
EOC
)

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run install commands inside container"
        SUCCESS=true
    else
        distrobox enter "$CONTAINER_NAME" -- bash -lc "$install_cmds" 2>&1 | tee -a "$LOG_FILE"
        install_rc=${PIPESTATUS[0]:-0}
        if [ $install_rc -eq 0 ]; then
            SUCCESS=true
        else
            if [ "$USE_DNS" = false ]; then
                log "WARN" "Installation inside container failed (rc=$install_rc). Retrying with DNS fix..."
                USE_DNS=true
            else
                fail "Installation failed twice. See $LOG_FILE for details."
            fi
        fi
    fi
done

# --- Step 4: Export & Final Fixes ---
echo -e "\n${BLUE}🔗 Exporting application and applying fixes...${NC}"
LAST_STEP="export:app"
log "INFO" "Exporting application"
if [ "$DRY_RUN" = true ]; then
    log "INFO" "DRY RUN: would run distrobox-export for $APP_ID"
else
    run_logged distrobox enter "$CONTAINER_NAME" -- distrobox-export --app "$APP_ID" || fail "Application export failed. See $LOG_FILE for details."
fi

D_FILES=()
if [ -d "$HOME/.local/share/applications" ]; then
    while IFS= read -r desktop_file; do
        D_FILES+=("$desktop_file")
    done < <(find "$HOME/.local/share/applications" -maxdepth 1 -iname "*$APP_ID*.desktop" | sort)

    if [ ${#D_FILES[@]} -eq 0 ]; then
        while IFS= read -r desktop_file; do
            D_FILES+=("$desktop_file")
        done < <(find "$HOME/.local/share/applications" -maxdepth 1 -iname "*elegoo*.desktop" | sort)
    fi
fi

if [ ${#D_FILES[@]} -gt 0 ]; then
    for D_FILE in "${D_FILES[@]}"; do
        sed -i 's|/run/host||' "$D_FILE"

        OLD_EXEC=$(grep '^Exec=' "$D_FILE" | head -n 1 | cut -d'=' -f2-)
        if [ -n "$OLD_EXEC" ] && ! grep -q "distrobox stop" "$D_FILE"; then
            sed -i "s|Exec=.*|Exec=sh -c \"$OLD_EXEC; distrobox stop $CONTAINER_NAME --yes\"|" "$D_FILE"
        fi
    done

    [ -x "$(command -v update-desktop-database)" ] && update-desktop-database ~/.local/share/applications
    echo -e "${GREEN}Installation successful!${NC}"
    echo -e "You can now find '$APP_NAME' in your app menu."
else
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: desktop file would be created at ~/.local/share/applications/*elegoo*.desktop"
        exit 0
    fi
    echo -e "${RED}Export failed. Desktop file not found.${NC}"
    echo "See $LOG_FILE for details"
    exit 1
fi
