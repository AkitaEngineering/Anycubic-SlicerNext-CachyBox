#!/bin/bash

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

APP_NAME="Anycubic Slicer Next"
APP_ID="AnycubicSlicerNext"
APP_SLUG="anycubic-slicer-next"
APP_RUNTIME_DIR="/opt/$APP_ID"
APP_LAUNCHER="/usr/local/bin/$APP_ID"
APP_DESKTOP="$APP_ID.desktop"

DEFAULT_ANYCUBIC_GIT_URL="https://github.com/ANYCUBIC-3D/AnycubicSlicerNext.git"
DEFAULT_ANYCUBIC_REF="main"
ANYCUBIC_TAGS_API="https://api.github.com/repos/ANYCUBIC-3D/AnycubicSlicerNext/tags?per_page=100"

if [ -n "${ANYCUBIC_GIT_URL:-}" ]; then
    ANYCUBIC_GIT_URL_SOURCE="environment"
else
    ANYCUBIC_GIT_URL_SOURCE=""
fi
ANYCUBIC_GIT_URL="${ANYCUBIC_GIT_URL:-$DEFAULT_ANYCUBIC_GIT_URL}"

if [ -n "${ANYCUBIC_REF:-}" ]; then
    ANYCUBIC_REF_SOURCE="environment"
else
    ANYCUBIC_REF_SOURCE=""
fi
ANYCUBIC_REF="${ANYCUBIC_REF:-}"

NON_INTERACTIVE=false
DRY_RUN=false
PRECHECK=false
UNINSTALL=false
AUTO_CONFIGURE_NVIDIA=false
CONTAINER_NAME="$APP_SLUG"
LOG_DIR="$HOME/.cache/anycubic-slicer-next-installer"
LOG_FILE="$LOG_DIR/install.log"
LAST_STEP_FILE="$LOG_DIR/last_failed_step"

NVIDIA_CONTAINER_SUPPORT_OVERRIDE=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --non-interactive|--yes|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --check)
            PRECHECK=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --ref)
            ANYCUBIC_REF="$2"
            ANYCUBIC_REF_SOURCE="cli"
            shift 2
            ;;
        --git-url|--repo-url)
            ANYCUBIC_GIT_URL="$2"
            ANYCUBIC_GIT_URL_SOURCE="cli"
            shift 2
            ;;
        --container-name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --gpu)
            gpu_choice="$2"
            shift 2
            ;;
        --configure-nvidia-host)
            AUTO_CONFIGURE_NVIDIA=true
            shift
            ;;
        --image-source)
            img_choice="$2"
            shift 2
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [options]

Options:
  --non-interactive, --yes, -y   Run without prompts.
  --dry-run                      Print planned actions without executing them.
  --check                        Run preflight checks and exit.
  --uninstall                    Run uninstall.sh with the current options.
  --ref REF                      Build a specific upstream tag or branch.
  --git-url URL                  Override the upstream Anycubic Git repository.
  --container-name NAME          Override the Distrobox container name.
  --gpu 1-4                      Preselect Nvidia, AMD, Intel, or Generic.
  --configure-nvidia-host        Install Nvidia Podman support on Arch/CachyOS hosts.
  --image-source 1-2             Use Ubuntu 24.04 directly or build a local image.
  --log-file PATH                Write logs to a custom path.
EOF
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Do not run this installer with sudo or as root."
    echo "Please run as your regular user (no sudo): ./install.sh"
    exit 1
fi

mkdir -p "$LOG_DIR"

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo -e "$APP_NAME Installer (Universal Bash)"
echo -e "${BLUE}--------------------------------------------------------${NC}"

log(){
    local level="$1"
    shift
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo -e "[$ts] [$level] $*" | tee -a "$LOG_FILE"
}

fail(){
    local msg="$1"
    echo
    log "ERROR" "$msg"
    echo "$LAST_STEP" > "$LAST_STEP_FILE" || true
    exit 1
}

trap 'rc=$?; if [ $rc -ne 0 ]; then log "ERROR" "Installer exited with code $rc (last step: $LAST_STEP)"; fi' EXIT

LAST_STEP="init"

run_logged(){
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run: $*"
        return 0
    fi

    "$@" 2>&1 | tee -a "$LOG_FILE"
    return ${PIPESTATUS[0]:-0}
}

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

resolve_anycubic_ref(){
    local tags_response latest_ref

    if [ -n "$ANYCUBIC_REF" ]; then
        case "$ANYCUBIC_REF_SOURCE" in
            cli)
                log "INFO" "Using $APP_NAME ref from CLI: $ANYCUBIC_REF"
                ;;
            environment)
                log "INFO" "Using $APP_NAME ref from environment: $ANYCUBIC_REF"
                ;;
        esac
        return 0
    fi

    tags_response=$(curl --fail -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 60 \
        -H 'Accept: application/vnd.github+json' "$ANYCUBIC_TAGS_API" 2>>"$LOG_FILE" || true)

    latest_ref=$(printf '%s' "$tags_response" | grep -oE '"name":[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"/\1/' | grep -E '^[A-Za-z0-9._-]+$' | sort -V | tail -n 1)

    if [ -n "$latest_ref" ]; then
        ANYCUBIC_REF="$latest_ref"
        log "INFO" "Resolved latest upstream $APP_NAME tag: $ANYCUBIC_REF"
    else
        ANYCUBIC_REF="$DEFAULT_ANYCUBIC_REF"
        log "WARN" "Unable to resolve the latest upstream tag; defaulting to $ANYCUBIC_REF"
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

preflight(){
    local avail_kb free_mem_gb

    log "INFO" "Running preflight checks"
    for cmd in distrobox podman curl git lspci; do
        if ! command -v "$cmd" &>/dev/null; then
            log "WARN" "Command $cmd not found. Installer may attempt to install it or fail."
        fi
    done

    if ! ping -c1 github.com &>/dev/null; then
        log "WARN" "Network appears unreachable; upstream clone/build steps will fail."
        echo "WARNING: network check failed"
    fi

    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null && ! has_nvidia_container_support; then
        log "WARN" "Nvidia GPU detected but Podman CDI support is not configured."
        echo "WARNING: Nvidia container support is not configured for Podman."
        echo "Install nvidia-container-toolkit and generate /etc/cdi/nvidia.yaml, or use Generic rendering."
    fi

    avail_kb=$(df --output=avail -k . | tail -n 1)
    if [ "$avail_kb" -lt $((12 * 1024 * 1024)) ]; then
        log "WARN" "Less than 12GB free disk space detected; upstream source builds may fail."
    fi

    free_mem_gb=$(free --gibi | awk '/^Mem:/ {print $7}')
    if [ -n "$free_mem_gb" ] && [ "$free_mem_gb" -lt 10 ]; then
        log "WARN" "Less than 10GiB available memory detected; upstream source builds may fail unless swap is configured."
    fi

    echo "preflight complete"
}

if [ "$UNINSTALL" = true ]; then
    log "INFO" "Switching to uninstaller mode"
    exec bash "$(dirname "$0")/uninstall.sh" --container-name "$CONTAINER_NAME" $( [ "$NON_INTERACTIVE" = true ] && echo --yes ) $( [ "$DRY_RUN" = true ] && echo --dry-run )
fi

if [ "$PRECHECK" = true ]; then
    preflight
    exit 0
fi

resolve_anycubic_ref

echo -e "\n${YELLOW}--- GPU Selection ---${NC}"

if [ -n "${gpu_choice:-}" ]; then
    log "INFO" "Using GPU selection from CLI: $gpu_choice"
fi

detected_gpu="none"
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    detected_gpu="nvidia"
elif lspci | grep -Ei 'VGA|3D' | grep -iq 'AMD'; then
    detected_gpu="amd"
elif lspci | grep -Ei 'VGA|3D' | grep -iq 'Intel'; then
    detected_gpu="intel"
fi

echo -e "Detected Hardware: ${GREEN}$detected_gpu${NC}"

gpu_default="4"
case "$detected_gpu" in
    nvidia) gpu_default="1" ;;
    amd) gpu_default="2" ;;
    intel) gpu_default="3" ;;
esac

echo "1) Nvidia (uses --nvidia flag)"
echo "2) AMD (uses DRI pass-through)"
echo "3) Intel (uses DRI pass-through)"
echo "4) Generic / None / Software Rendering"

if [ -n "${gpu_choice:-}" ]; then
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
            log "WARN" "Nvidia container support is unavailable; falling back to Generic rendering."
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
                        log "WARN" "Nvidia container support is unavailable; falling back to Generic rendering."
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
                log "WARN" "Nvidia container support is unavailable; falling back to Generic rendering."
                gpu_choice=4
            fi
        fi
    fi
fi

GPU_FLAG=""
ADD_FLAGS=""
GPU_TYPE="generic"
CONTAINERFILE="containerfile.amd"

case "$gpu_choice" in
    1)
        GPU_FLAG="--nvidia"
        GPU_TYPE="nvidia"
        CONTAINERFILE="containerfile.nvidia"
        ;;
    2)
        ADD_FLAGS="--device /dev/dri:/dev/dri"
        GPU_TYPE="amd"
        CONTAINERFILE="containerfile.amd"
        ;;
    3)
        ADD_FLAGS="--device /dev/dri:/dev/dri"
        GPU_TYPE="intel"
        CONTAINERFILE="containerfile.intel"
        ;;
esac

echo -e "\n${YELLOW}--- Step 2: Image Source ---${NC}"
echo "1) Standard Ubuntu 24.04 from DockerHub (Default)"
echo "2) Custom Local Containerfile (Build locally)"

if [ -n "${img_choice:-}" ]; then
    log "INFO" "Using image source from CLI: $img_choice"
elif [ "$NON_INTERACTIVE" = true ]; then
    img_choice=1
    log "INFO" "Non-interactive: selecting image source $img_choice"
else
    read -p "Selection [1]: " img_choice
    img_choice=${img_choice:-1}
fi

LAST_STEP="start"
log "INFO" "Starting installation loop. Output will stream to console and $LOG_FILE"
echo -e "\nStarting installation — streaming output to console and log: $LOG_FILE\n"

SUCCESS=false
USE_DNS=false

while [ "$SUCCESS" = false ]; do
    if distrobox list | grep -q "$CONTAINER_NAME"; then
        distrobox rm -f "$CONTAINER_NAME"
    fi

    CURRENT_ADD_FLAGS="$ADD_FLAGS"
    if [ "$USE_DNS" = true ]; then
        echo -e "${YELLOW}Network issues detected. Re-creating container with explicit DNS...${NC}"
        CURRENT_ADD_FLAGS="$CURRENT_ADD_FLAGS --dns 1.1.1.1 --dns 8.8.8.8"
    fi

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
        log "INFO" "DRY RUN: would install missing host dependencies: ${missing_host_deps[*]}"
    else
        log "INFO" "Installing missing host dependencies: ${missing_host_deps[*]}"
        if command -v pacman &>/dev/null; then
            run_logged sudo pacman -S --needed --noconfirm "${missing_host_deps[@]}" || fail "Failed to install host dependencies. See $LOG_FILE for details."
        elif command -v apt &>/dev/null; then
            run_logged sudo apt update || fail "Failed to update apt metadata. See $LOG_FILE for details."
            run_logged sudo apt install -y "${missing_host_deps[@]}" || fail "Failed to install host dependencies. See $LOG_FILE for details."
        elif command -v dnf &>/dev/null; then
            run_logged sudo dnf install -y "${missing_host_deps[@]}" || fail "Failed to install host dependencies. See $LOG_FILE for details."
        else
            fail "Unknown package manager. Please install these dependencies manually: ${missing_host_deps[*]}"
        fi
    fi

    IMAGE_NAME="ubuntu:24.04"
    if [ "$img_choice" = "2" ]; then
        if [ -f "$CONTAINERFILE" ]; then
            log "INFO" "Building local image from $CONTAINERFILE"
            if [ "$DRY_RUN" = true ]; then
                log "INFO" "DRY RUN: would run podman build -t anycubic-custom-$GPU_TYPE -f $CONTAINERFILE ."
            else
                run_logged podman build -t "anycubic-custom-$GPU_TYPE" -f "$CONTAINERFILE" . || fail "Image build failed. See $LOG_FILE for details."
            fi
            IMAGE_NAME="anycubic-custom-$GPU_TYPE"
        else
            echo -e "${RED}Warning: $CONTAINERFILE not found, using standard image.${NC}"
        fi
    fi

    LAST_STEP="container:create"
    build_distrobox_create_cmd "$IMAGE_NAME" "$GPU_FLAG" "$CURRENT_ADD_FLAGS"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run: ${DBX_CREATE_CMD[*]}"
    else
        run_logged "${DBX_CREATE_CMD[@]}" || fail "Container creation failed. See $LOG_FILE for details."
    fi

    echo -e "\n${YELLOW}Bootstrapping build dependencies and compiling upstream sources. This can take a while...${NC}"
    LAST_STEP="install:build"
    log "INFO" "Installing bootstrap packages and building $APP_NAME inside container"

    read -r -d '' install_cmds <<'EOC' || true
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

echo 'Running: apt update'
sudo apt update

echo 'Running: apt install (bootstrap packages)'
sudo apt install -y ca-certificates curl file fuse git locales lsb-release nasm python3-dev python3-numpy rsync sed sudo xz-utils

echo 'Generating locales'
sudo locale-gen en_US.UTF-8

BUILD_ROOT="$HOME/.local/share/$APP_SLUG"
REPO_DIR="$BUILD_ROOT/source"
APPIMAGE_CACHE_DIR="$BUILD_ROOT/appimage"
APPIMAGE_CACHE_FILE="$APPIMAGE_CACHE_DIR/$APP_ID.AppImage"
REF_FILE="$BUILD_ROOT/last-build-ref"
REPO_URL_FILE="$BUILD_ROOT/last-build-repo-url"

mkdir -p "$BUILD_ROOT" "$APPIMAGE_CACHE_DIR"

cached_ref=""
cached_repo_url=""

if [ -f "$REF_FILE" ]; then
    cached_ref=$(cat "$REF_FILE")
fi

if [ -f "$REPO_URL_FILE" ]; then
    cached_repo_url=$(cat "$REPO_URL_FILE")
fi

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "Cloning upstream repository from $ANYCUBIC_GIT_URL"
    git clone "$ANYCUBIC_GIT_URL" "$REPO_DIR"
else
    echo "Refreshing upstream repository"
    git -C "$REPO_DIR" remote set-url origin "$ANYCUBIC_GIT_URL"
    git -C "$REPO_DIR" reset --hard
    git -C "$REPO_DIR" fetch --tags --force origin
fi

if git -C "$REPO_DIR" ls-remote --exit-code --heads origin "$ANYCUBIC_REF" >/dev/null 2>&1; then
    git -C "$REPO_DIR" fetch --depth 1 origin "$ANYCUBIC_REF"
    git -C "$REPO_DIR" checkout --force -B "$ANYCUBIC_REF" FETCH_HEAD
else
    git -C "$REPO_DIR" fetch --tags --force origin
    git -C "$REPO_DIR" checkout --force "$ANYCUBIC_REF"
fi

BUILD_SCRIPT=""
if [ -x "$REPO_DIR/build_linux.sh" ]; then
    BUILD_SCRIPT="$REPO_DIR/build_linux.sh"
elif [ -x "$REPO_DIR/BuildLinux.sh" ]; then
    BUILD_SCRIPT="$REPO_DIR/BuildLinux.sh"
else
    echo 'No supported Linux build script was found in the upstream checkout.'
    exit 1
fi

if [ ! -x "$APP_RUNTIME_DIR/AppRun" ] || [ ! -f "$APPIMAGE_CACHE_FILE" ] || [ "$cached_ref" != "$ANYCUBIC_REF" ] || [ "$cached_repo_url" != "$ANYCUBIC_GIT_URL" ]; then
    echo 'Installing upstream system build dependencies'
    (
        cd "$REPO_DIR"
        "$BUILD_SCRIPT" -u
    )

    find "$REPO_DIR/build" -maxdepth 4 -type f -name '*.AppImage' -delete 2>/dev/null || true

    build_args=(-d -s -i -r)
    if [ "$cached_ref" != "$ANYCUBIC_REF" ] || [ "$cached_repo_url" != "$ANYCUBIC_GIT_URL" ]; then
        build_args=(-c "${build_args[@]}")
    fi

    echo "Building $APP_NAME from source at ref $ANYCUBIC_REF"
    (
        cd "$REPO_DIR"
        "$BUILD_SCRIPT" "${build_args[@]}"
    )

    appimage_path=$(find "$REPO_DIR/build" -maxdepth 4 -type f -name '*.AppImage' | sort | tail -n 1)
    [ -n "$appimage_path" ] || {
        echo 'Built AppImage not found under build/'
        exit 1
    }

    install -Dm 0755 "$appimage_path" "$APPIMAGE_CACHE_FILE"
    printf '%s\n' "$ANYCUBIC_REF" > "$REF_FILE"
    printf '%s\n' "$ANYCUBIC_GIT_URL" > "$REPO_URL_FILE"
else
    echo "Reusing cached AppImage for ref $ANYCUBIC_REF"
fi

TMP_DIR=$(mktemp -d)
APPIMAGE_PATH="$TMP_DIR/$APP_ID.AppImage"
cp "$APPIMAGE_CACHE_FILE" "$APPIMAGE_PATH"
chmod +x "$APPIMAGE_PATH"

cd "$TMP_DIR"
"$APPIMAGE_PATH" --appimage-extract >/dev/null

sudo rm -rf "$APP_RUNTIME_DIR"
sudo mkdir -p "$APP_RUNTIME_DIR"
sudo cp -a squashfs-root/. "$APP_RUNTIME_DIR/"
printf '#!/bin/sh\nexec %s/AppRun "$@"\n' "$APP_RUNTIME_DIR" | sudo tee "$APP_LAUNCHER" >/dev/null
sudo chmod 0755 "$APP_LAUNCHER"

desktop_src=$(find squashfs-root -name '*.desktop' | sort | head -n 1)
[ -n "$desktop_src" ] || {
    echo 'AppImage desktop file not found'
    exit 1
}

icon_name=$(awk -F= '/^Icon=/{print $2; exit}' "$desktop_src")
if [ -n "$icon_name" ]; then
    icon_src=$(find squashfs-root \( -path "*/$icon_name.png" -o -path "*/$icon_name.svg" -o -path "*/$icon_name.xpm" -o -name "$icon_name.png" -o -name "$icon_name.svg" -o -name "$icon_name.xpm" \) | sort | head -n 1)
else
    icon_src=$(find squashfs-root \( -iname '*AnycubicSlicer*.png' -o -iname '*anycubic*.png' -o -iname '*AnycubicSlicer*.svg' -o -iname '*anycubic*.svg' \) | sort | head -n 1)
fi

sudo install -Dm 0644 "$desktop_src" "/usr/share/applications/$APP_DESKTOP"
sudo sed -i "s|^Exec=.*|Exec=$APP_LAUNCHER %F|" "/usr/share/applications/$APP_DESKTOP"
if grep -q '^TryExec=' "/usr/share/applications/$APP_DESKTOP"; then
    sudo sed -i "s|^TryExec=.*|TryExec=$APP_LAUNCHER|" "/usr/share/applications/$APP_DESKTOP"
else
    printf 'TryExec=%s\n' "$APP_LAUNCHER" | sudo tee -a "/usr/share/applications/$APP_DESKTOP" >/dev/null
fi
if grep -q '^Name=' "/usr/share/applications/$APP_DESKTOP"; then
    sudo sed -i "s|^Name=.*|Name=$APP_NAME|" "/usr/share/applications/$APP_DESKTOP"
else
    printf 'Name=%s\n' "$APP_NAME" | sudo tee -a "/usr/share/applications/$APP_DESKTOP" >/dev/null
fi
if [ -n "$icon_src" ]; then
    icon_ext=${icon_src##*.}
    sudo install -Dm 0644 "$icon_src" "/usr/share/icons/hicolor/192x192/apps/$APP_ID.$icon_ext"
    sudo sed -i "s|^Icon=.*|Icon=$APP_ID|" "/usr/share/applications/$APP_DESKTOP"
fi

if [ -f /run/host/usr/share/cachyos-fish-config/cachyos-config.fish ]; then
    sudo mkdir -p /usr/share/cachyos-fish-config
    sudo ln -sfn /run/host/usr/share/cachyos-fish-config/cachyos-config.fish /usr/share/cachyos-fish-config/cachyos-config.fish
    if [ -d /run/host/usr/share/cachyos-fish-config/conf.d ]; then
        sudo ln -sfn /run/host/usr/share/cachyos-fish-config/conf.d /usr/share/cachyos-fish-config/conf.d
    fi
fi

cd /
rm -rf "$TMP_DIR"
EOC

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run bootstrap, clone, build, and install commands inside container"
        SUCCESS=true
    else
        distrobox enter "$CONTAINER_NAME" -- env \
            APP_NAME="$APP_NAME" \
            APP_ID="$APP_ID" \
            APP_SLUG="$APP_SLUG" \
            APP_RUNTIME_DIR="$APP_RUNTIME_DIR" \
            APP_LAUNCHER="$APP_LAUNCHER" \
            APP_DESKTOP="$APP_DESKTOP" \
            ANYCUBIC_GIT_URL="$ANYCUBIC_GIT_URL" \
            ANYCUBIC_REF="$ANYCUBIC_REF" \
            bash -lc "$install_cmds" 2>&1 | tee -a "$LOG_FILE"
        install_rc=${PIPESTATUS[0]:-0}

        if [ "$install_rc" -eq 0 ]; then
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

echo -e "\n${BLUE}Exporting application and applying launcher fixes...${NC}"
LAST_STEP="export:app"
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
        done < <(find "$HOME/.local/share/applications" -maxdepth 1 -iname '*anycubic*.desktop' | sort)
    fi
fi

if [ ${#D_FILES[@]} -gt 0 ]; then
    for D_FILE in "${D_FILES[@]}"; do
        sed -i 's|/run/host||' "$D_FILE"

        OLD_EXEC=$(grep '^Exec=' "$D_FILE" | head -n 1 | cut -d'=' -f2-)
        if [ -n "$OLD_EXEC" ] && ! grep -q 'distrobox stop' "$D_FILE"; then
            sed -i "s|Exec=.*|Exec=sh -c \"$OLD_EXEC; distrobox stop $CONTAINER_NAME --yes\"|" "$D_FILE"
        fi
    done

    if [ -x "$(command -v update-desktop-database)" ]; then
        update-desktop-database ~/.local/share/applications
    fi

    echo -e "${GREEN}Installation successful!${NC}"
    echo -e "You can now find '$APP_NAME' in your app menu."
else
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: desktop file would be created at ~/.local/share/applications/*anycubic*.desktop"
        exit 0
    fi

    echo -e "${RED}Export failed. Desktop file not found.${NC}"
    echo "See $LOG_FILE for details"
    exit 1
fi