#!/usr/bin/fish

set blue (set_color blue)
set red (set_color red)
set yellow (set_color yellow)
set normal (set_color normal)

set APP_NAME "Elegoo Slicer"
set APP_ID "ElegooSlicer"
set APP_SLUG "elegoo-slicer"

set LOG_DIR "$HOME/.cache/elegoo-installer"
mkdir -p $LOG_DIR
set LOG_FILE "$LOG_DIR/uninstall.log"
set CONTAINER_NAME "$APP_SLUG"
set NON_INTERACTIVE false
set DRY_RUN false

# CLI parsing
set i 1
while test $i -le (count $argv)
    switch $argv[$i]
        case --container-name
            set i (math $i + 1)
            set CONTAINER_NAME $argv[$i]
        case --non-interactive --yes -y
            set NON_INTERACTIVE true
        case --dry-run
            set DRY_RUN true
        case --log-file
            set i (math $i + 1)
            set LOG_FILE $argv[$i]
        case --help -h
            echo "Usage: "(status filename)" [--container-name NAME] [--non-interactive] [--dry-run]"
            exit 0
    end
    set i (math $i + 1)
end

function log
    set level $argv[1]; set -e argv[1]
    set ts (date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$ts] [$level] $argv" | tee -a $LOG_FILE
end

function spinner
    set pid $argv[1]
    set chars "|/-\\"
    set len (string length $chars)
    set i 1
    while ps -p $pid > /dev/null 2>&1
        set char (string sub -s $i -l 1 -- $chars)
        printf " [%s]  " $char
        set i (math "($i % $len) + 1")
        sleep 0.1
        printf "\b\b\b\b\b\b"
    end
end

echo -e "$blue--------------------------------------------------------"
echo -e "$APP_NAME Uninstaller"
echo -e "--------------------------------------------------------$normal"

# 1. Remove the app export (menu entries and binaries)
if type -q distrobox; and distrobox list | grep -q "$CONTAINER_NAME"
    log INFO "--- Step 1: Unexporting Application ---"
    if test "$DRY_RUN" = "true"
        log INFO "DRY RUN: would unexport $APP_ID from $CONTAINER_NAME"
    else
        distrobox enter "$CONTAINER_NAME" -- distrobox-export --app $APP_ID --delete
    end
else if not type -q distrobox
    log WARN "distrobox is not installed; skipping app unexport."
end

# 2. Remove the Distrobox container
if type -q distrobox; and distrobox list | grep -q "$CONTAINER_NAME"
    log INFO "--- Step 2: Removing Distrobox Container ---"
    if test "$DRY_RUN" = "true"
        log INFO "DRY RUN: would rm -f $CONTAINER_NAME"
    else
        distrobox rm -f "$CONTAINER_NAME" &
        spinner $last_pid
    end
else
    if not type -q distrobox
        log WARN "distrobox is not installed; skipping container cleanup."
    else
        log INFO "No container '$CONTAINER_NAME' found."
    end
end

# 3. Remove Podman Images related to Elegoo Slicer
echo -e "$yellow--- Step 3: Removing Podman Images ---$normal"
if type -q podman
    set images (podman images | grep "elegoo-custom" | awk '{print $3}')
    if test -n "$images"
        if test "$DRY_RUN" = "true"
            log INFO "DRY RUN: would remove images: $images"
        else
            for img in $images
                podman rmi -f "$img"
            end
            log INFO "Images removed."
        end
    else
        log INFO "No $APP_NAME-related images found."
    end
else
    log WARN "podman is not installed; skipping image cleanup."
end

# 4. Manual cleanup of desktop files and icons (just in case)
echo -e "$yellow--- Step 4: Final Cleanup ---$normal"
if test "$DRY_RUN" = "true"
    log INFO "DRY RUN: would remove leftover desktop files and binaries"
    if type -q update-desktop-database
        log INFO "DRY RUN: would refresh desktop database"
    end
else
    rm -f ~/.local/share/applications/*elegoo*.desktop
    rm -f ~/.local/share/applications/*ElegooSlicer*.desktop
    rm -f ~/.local/bin/ElegooSlicer
    rm -rf ~/.local/share/elegoo-slicer
    if type -q update-desktop-database
        update-desktop-database ~/.local/share/applications
    end
end

# 5. Optional: Config files
if test "$NON_INTERACTIVE" = "true"
    set cleanup_config n
else
    echo -e "$red"
    read -P "Do you want to delete all configuration and slicer settings in ~/.config? (y/N): " cleanup_config
end
echo -e "$normal"

if test "$cleanup_config" = "y"
    if test "$DRY_RUN" = "true"
        log INFO "DRY RUN: would delete ~/.config/ElegooSlicer and ~/.config/elegoo-slicer"
    else
        rm -rf ~/.config/ElegooSlicer
        rm -rf ~/.config/elegoo-slicer
        echo "Configuration files deleted."
    end
end

echo -e "$blue--------------------------------------------------------"
echo -e "✅ Deinstallation complete!"
echo -e "--------------------------------------------------------$normal"
