#!/bin/bash

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

APP_NAME="Anycubic Slicer Next"
APP_ID="AnycubicSlicerNext"
APP_SLUG="anycubic-slicer-next"

CONTAINER_NAME="$APP_SLUG"
NON_INTERACTIVE=false
DRY_RUN=false
LOG_DIR="$HOME/.cache/anycubic-slicer-next-installer"
LOG_FILE="$LOG_DIR/uninstall.log"
LAST_STEP_FILE="$LOG_DIR/last_failed_step"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --container-name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --non-interactive|--yes|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--container-name NAME] [--non-interactive] [--dry-run] [--log-file PATH]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Do not run this uninstaller with sudo or as root."
    echo "Please run as your regular user (no sudo): ./uninstall.sh"
    exit 1
fi

mkdir -p "$LOG_DIR"

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo -e "$APP_NAME Uninstaller (Universal Bash)"
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

trap 'rc=$?; if [ $rc -ne 0 ]; then log "ERROR" "Uninstaller exited with code $rc (last step: $LAST_STEP)"; fi' EXIT

LAST_STEP="init"

run_logged(){
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run: $*"
        return 0
    fi

    "$@" 2>&1 | tee -a "$LOG_FILE"
    return ${PIPESTATUS[0]:-0}
}

LAST_STEP="unexport"
if command -v distrobox &>/dev/null && distrobox list | grep -q "$CONTAINER_NAME"; then
    log "INFO" "Removing exported launcher and menu entries"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would unexport $APP_ID from $CONTAINER_NAME"
    else
        distrobox enter "$CONTAINER_NAME" -- distrobox-export --app "$APP_ID" --delete || log "WARN" "Failed to remove exported app entry; continuing with cleanup."
    fi
else
    if ! command -v distrobox &>/dev/null; then
        log "WARN" "distrobox is not installed; skipping app unexport."
    else
        log "INFO" "No active container '$CONTAINER_NAME' found for unexporting."
    fi
fi

LAST_STEP="container:remove"
if command -v distrobox &>/dev/null && distrobox list | grep -q "$CONTAINER_NAME"; then
    log "INFO" "Removing Distrobox container $CONTAINER_NAME"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would remove container $CONTAINER_NAME"
    else
        run_logged distrobox rm -f "$CONTAINER_NAME" || fail "Failed to remove container $CONTAINER_NAME"
    fi
else
    if ! command -v distrobox &>/dev/null; then
        log "WARN" "distrobox is not installed; skipping container cleanup."
    else
        log "INFO" "Container '$CONTAINER_NAME' does not exist."
    fi
fi

LAST_STEP="images:remove"
echo -e "${YELLOW}--- Step 3: Removing Podman Images ---${NC}"
if command -v podman &>/dev/null; then
    mapfile -t images < <(podman images --format '{{.Repository}} {{.ID}}' | awk '$1 ~ /^anycubic-custom-/ {print $2}')
    if [ ${#images[@]} -gt 0 ]; then
        if [ "$DRY_RUN" = true ]; then
            log "INFO" "DRY RUN: would remove images: ${images[*]}"
        else
            run_logged podman rmi -f "${images[@]}" || fail "Failed to remove one or more custom images."
        fi
        log "INFO" "Custom $APP_NAME images removed."
    else
        log "INFO" "No custom $APP_NAME images found."
    fi
else
    log "WARN" "podman is not installed; skipping image cleanup."
fi

LAST_STEP="files:cleanup"
echo -e "${YELLOW}--- Step 4: Final Cleanup of Local Files ---${NC}"
if [ "$DRY_RUN" = true ]; then
    log "INFO" "DRY RUN: would remove leftover desktop files, binaries, runtime cache, and installer logs"
    if command -v update-desktop-database &>/dev/null; then
        log "INFO" "DRY RUN: would refresh desktop database"
    fi
else
    rm -f ~/.local/share/applications/*anycubic*.desktop
    rm -f ~/.local/share/applications/*AnycubicSlicer*.desktop
    rm -f ~/.local/share/applications/*AnycubicSlicerNext*.desktop
    rm -f ~/.local/bin/AnycubicSlicerNext
    rm -rf ~/.local/share/anycubic-slicer-next
    rm -rf "$LOG_DIR"

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database ~/.local/share/applications
        echo -e "${GREEN}Desktop database updated.${NC}"
    fi
fi

echo -e "\n${RED}CAUTION: Configuration Cleanup${NC}"
echo -e "Your slicer profiles and settings are typically stored in ${BLUE}~/.config/AnycubicSlicerNext${NC}"
if [ "$NON_INTERACTIVE" = true ]; then
    cleanup_config=n
else
    read -p "Do you want to delete all your profiles and settings? (y/N): " cleanup_config
fi

if [[ "$cleanup_config" == "y" || "$cleanup_config" == "Y" ]]; then
    LAST_STEP="config:cleanup"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would delete ~/.config/AnycubicSlicerNext, ~/.config/AnycubicSlicer, and ~/.config/anycubic-slicer-next"
    else
        rm -rf ~/.config/AnycubicSlicerNext
        rm -rf ~/.config/AnycubicSlicer
        rm -rf ~/.config/anycubic-slicer-next
        echo -e "${GREEN}Configuration directories deleted.${NC}"
    fi
else
    echo -e "${BLUE}Configuration directories kept.${NC}"
fi

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo -e "Uninstallation complete!"
echo -e "${BLUE}--------------------------------------------------------${NC}"