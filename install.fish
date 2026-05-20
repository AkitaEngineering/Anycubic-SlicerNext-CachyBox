#!/usr/bin/fish

set blue (set_color blue); set green (set_color green); set red (set_color red); set yellow (set_color yellow); set normal (set_color normal)

set APP_NAME "Elegoo Slicer"
set APP_ID "ElegooSlicer"
set APP_SLUG "elegoo-slicer"
set APP_RUNTIME_DIR "/opt/$APP_ID"
set APP_LAUNCHER "/usr/local/bin/$APP_ID"
set APP_DESKTOP "$APP_ID.desktop"

echo -e "$blue--------------------------------------------------------"
echo -e "$APP_NAME Installer for CachyOS"
echo -e "--------------------------------------------------------$normal"

# --- CLI options & logging ---
set LOG_DIR "$HOME/.cache/elegoo-installer"
mkdir -p $LOG_DIR
set LOG_FILE "$LOG_DIR/install.log"
set NON_INTERACTIVE false
set DRY_RUN false

# Prevent running as root: distrobox commands do not behave correctly under sudo
if test (id -u) -eq 0
    echo "ERROR: Do not run this installer with sudo or as root."
    echo "Please run as your regular user (no sudo): ./install.fish"
    echo "If you intentionally need root distrobox operations, re-run without this script or use distrobox --root commands as documented."
    exit 1
end

set PRECHECK false
set UNINSTALL false
set DEFAULT_ELEGOO_URL "https://github.com/ELEGOO-3D/ElegooSlicer/releases/download/v1.5.0.7/ElegooSlicer_Linux_V1.5.0.7.AppImage"
set ELEGOO_LATEST_API "https://api.github.com/repos/ELEGOO-3D/ElegooSlicer/releases/latest"
if set -q ELEGOO_URL
    set elegoo_url_source environment
else
    set ELEGOO_URL ""
    set elegoo_url_source ""
end
set CONTAINER_NAME "$APP_SLUG"
set gpu_choice ""
set img_choice ""
set i 1
while test $i -le (count $argv)
    switch $argv[$i]
        case --non-interactive --yes -y
            set NON_INTERACTIVE true
        case --dry-run
            set DRY_RUN true
        case --check
            set PRECHECK true
        case --uninstall
            set UNINSTALL true
        case --url
            set i (math $i + 1)
            set ELEGOO_URL $argv[$i]
            set elegoo_url_source cli
        case --container-name
            set i (math $i + 1)
            set CONTAINER_NAME $argv[$i]
        case --log-file
            set i (math $i + 1)
            set LOG_FILE $argv[$i]
        case --gpu
            set i (math $i + 1)
            set gpu_choice $argv[$i]
        case --image-source
            set i (math $i + 1)
            set img_choice $argv[$i]
        case --help -h
            echo "Usage: $_ [--non-interactive] [--dry-run] [--check] [--uninstall] [--url URL] [--container-name NAME] [--gpu 1-4] [--image-source 1-2]"
            exit 0
    end
    set i (math $i + 1)
end

function log
    set level $argv[1]; set -e argv[1]
    set ts (date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$ts] [$level] $argv" | tee -a $LOG_FILE
end

function resolve_latest_elegoo_url
    if test -n "$ELEGOO_URL"
        switch $elegoo_url_source
            case cli
                log INFO "Using $APP_NAME AppImage URL from CLI: $ELEGOO_URL"
            case environment
                log INFO "Using $APP_NAME AppImage URL from environment: $ELEGOO_URL"
        end
        return 0
    end

    set latest_response (curl --fail -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 60 -H "Accept: application/vnd.github+json" $ELEGOO_LATEST_API 2>>$LOG_FILE)
    set latest_url (printf "%s" "$latest_response" | grep -oE '"browser_download_url":[[:space:]]*"[^"]*ElegooSlicer[^"]*\.AppImage"' | head -n 1 | sed -E 's/.*"([^"]+)"/\1/')
    if test -z "$latest_url"
        set latest_url (printf "%s" "$latest_response" | grep -oE '"browser_download_url":[[:space:]]*"[^"]+AppImage"' | head -n 1 | sed -E 's/.*"([^"]+)"/\1/')
    end

    if test -n "$latest_url"
        set -g ELEGOO_URL "$latest_url"
        log INFO "Resolved latest $APP_NAME AppImage: $ELEGOO_URL"
    else
        set -g ELEGOO_URL "$DEFAULT_ELEGOO_URL"
        log WARN "Unable to resolve the latest $APP_NAME release; falling back to $ELEGOO_URL"
    end
end

function has_nvidia_cdi_spec
    for cdi_dir in /etc/cdi /var/run/cdi
        if test -d $cdi_dir
            set spec (find $cdi_dir -maxdepth 1 -type f \( -iname '*nvidia*.yaml' -o -iname '*nvidia*.json' \) 2>/dev/null | head -n 1)
            if test -n "$spec"
                return 0
            end
        end
    end
    return 1
end

function has_nvidia_container_support
    if not type -q podman
        return 1
    end
    if not type -q nvidia-smi
        return 1
    end
    has_nvidia_cdi_spec
end

function build_distrobox_create_cmd
    set image_name $argv[1]
    set gpu_flag $argv[2]
    set additional_flags $argv[3]

    set -g dbx_create_cmd distrobox create --name "$CONTAINER_NAME" --image "$image_name"
    if test -n "$gpu_flag"
        set -a dbx_create_cmd "$gpu_flag"
    end
    if test -n "$additional_flags"
        set -a dbx_create_cmd --additional-flags "$additional_flags"
    end
    set -a dbx_create_cmd --yes
end

if test "$UNINSTALL" = "true"
    log INFO "Switching to uninstaller mode"
    set extra_args
    if test "$NON_INTERACTIVE" = "true"
        set extra_args $extra_args --yes
    end
    if test "$DRY_RUN" = "true"
        set extra_args $extra_args --dry-run
    end
    set script_dir (dirname (status filename))
    exec fish "$script_dir/uninstall.fish" --container-name $CONTAINER_NAME $extra_args
end

function spinner
    # simple spinner for a pid (compatible with older fish)
    set pid $argv[1]
    set chars "|/-\\"
    set len (echo $chars | wc -c)
    set i 1
    while ps -p $pid > /dev/null
        # extract the i-th character
        set char (echo $chars | cut -c$i)
        printf " [%s]  " $char
        set i (math "($i % $len) + 1")
        sleep 0.1
        printf "\b\b\b\b\b\b"
    end
end

function preflight
    log INFO "Running preflight checks"
    for cmd in distrobox podman curl lspci
        if not type -q $cmd
            log WARN "Command $cmd not found"
        end
    end
    if not ping -c1 github.com >/dev/null 2>&1
        log WARN "Network appears unreachable"
        echo "WARNING: network check failed"
    end
    if type -q nvidia-smi
        if nvidia-smi >/dev/null 2>&1
            if not has_nvidia_container_support
                log WARN "Nvidia GPU detected but Podman CDI support is not configured. Install nvidia-container-toolkit and generate a CDI spec before using the Nvidia path."
                echo "WARNING: Nvidia container support is not configured for Podman."
                echo "Install nvidia-container-toolkit and generate /etc/cdi/nvidia.yaml, or use Generic rendering."
            end
        end
    end
    set avail (df --output=avail -k . | tail -n1)
    if test $avail -lt 1048576
        log WARN "Less than 1GB free disk space"
    end
    echo "preflight complete"
end



# --- Download URL for the latest AppImage release ---
# (already in ELEGOO_URL, copied earlier)

# if preflight requested, run and exit
if test "$PRECHECK" = "true"
    preflight
    exit 0
end

resolve_latest_elegoo_url

# --- GPU Selection ---

echo -e "\n$yellow--- GPU Selection ---$normal"

if test -n "$gpu_choice"
    log INFO "Using GPU selection from CLI: $gpu_choice"
else
    set gpu_choice ""
end
set detected_gpu "none"
if type -q nvidia-smi; if nvidia-smi > /dev/null 2>&1; set detected_gpu "nvidia"; end; end
if test "$detected_gpu" = "none"
    if lspci | grep -Ei "VGA|3D" | grep -iq "AMD"; set detected_gpu "amd"
    else if lspci | grep -Ei "VGA|3D" | grep -iq "Intel"; set detected_gpu "intel"; end
end

echo -e "Detected Hardware: $green$detected_gpu$normal"
set g_def "4"; switch $detected_gpu; case "nvidia"; set g_def "1"; case "amd"; set g_def "2"; case "intel"; set g_def "3"; end

echo "1) Nvidia  2) AMD  3) Intel  4) Generic"
if test -n "$gpu_choice"
    set g_choice $gpu_choice
    log INFO "Using GPU from CLI: $g_choice"
else if test "$NON_INTERACTIVE" = "true"
    set g_choice $g_def
    log INFO "Non-interactive: selecting GPU stack $g_choice"
else
    read -P "Select Driver Stack [$g_def]: " g_choice; if test -z "$g_choice"; set g_choice "$g_def"; end
end

if test "$g_choice" = "1"
    if not has_nvidia_container_support
        echo -e "\n$yellow""Nvidia GPU detected, but Podman GPU support is not configured.""$normal"
        echo "Install nvidia-container-toolkit and generate /etc/cdi/nvidia.yaml to use the Nvidia path."
        if test "$NON_INTERACTIVE" = "true"
            log WARN "Nvidia container support is unavailable; falling back to Generic / software rendering."
            set g_choice 4
        else
            echo "1) Fall back to Generic / None / Software Rendering"
            echo "2) Abort and configure Nvidia container support first"
            read -P "Selection [1]: " nvidia_fallback_choice
            if test -z "$nvidia_fallback_choice"
                set nvidia_fallback_choice 1
            end
            if test "$nvidia_fallback_choice" = "2"
                log ERROR "Aborted so Nvidia container support can be configured first."
                exit 1
            end
            log WARN "Nvidia container support is unavailable; falling back to Generic / software rendering."
            set g_choice 4
        end
    end
end

set gpu_flags ""; set add_flags ""; set g_type "generic"; set c_file "containerfile.amd"
switch $g_choice
    case 1; set gpu_flags "--nvidia"; set g_type "nvidia"; set c_file "containerfile.nvidia"
    case 2; set add_flags "--device /dev/dri:/dev/dri"; set g_type "amd"; set c_file "containerfile.amd"
    case 3; set add_flags "--device /dev/dri:/dev/dri"; set g_type "intel"; set c_file "containerfile.intel"
end

# --- Step 2: Image Source ---
echo -e "\n$yellow--- Step 2: Image Source ---$normal"
echo "1) Standard Ubuntu 24.04 from DockerHub (Default)"
echo "2) Custom Local Containerfile (Build locally)"
if test -n "$img_choice"
    log INFO "Using image source from CLI: $img_choice"
else if test "$NON_INTERACTIVE" = "true"
    set img_choice 1
    log INFO "Non-interactive: selecting image source $img_choice"
else
    read -P "Selection [1]: " img_choice
    if test -z "$img_choice"; set img_choice "1"; end
end

# --- Image Preparation ---
set image_name "ubuntu:24.04"
if test "$img_choice" = "2"
    if test -f "$c_file"
        log INFO "Building local image from $c_file"
        if test "$DRY_RUN" = "true"
            log INFO "DRY RUN: would run podman build -t elegoo-custom-$g_type -f $c_file ."
        else
            podman build -t "elegoo-custom-$g_type" -f "$c_file" . 2>&1 | tee -a $LOG_FILE
            if test $pipestatus[1] -ne 0
                log ERROR "Image build failed. See $LOG_FILE for details"
                exit 1
            end
        end
        set image_name "elegoo-custom-$g_type"
    else
        echo -e "$red""Warning: $c_file not found, using standard image.""$normal"
    end
end

# Inform user what's next and where logs will go
log INFO "Starting installation loop. Output will stream to console and $LOG_FILE"
echo -e "\nStarting installation — streaming output to console and log: $LOG_FILE\n"

# --- Step 3: Installation Loop with DNS Retry ---
set use_custom_dns false; set install_success false
while test "$install_success" = false
    if distrobox list | grep -q "$CONTAINER_NAME"; distrobox rm -f "$CONTAINER_NAME"; end
    set current_add_flags "$add_flags"
    if test "$use_custom_dns" = true
        echo -e "$yellow""DNS issues detected. Retrying with explicit DNS...""$normal"
        set current_add_flags "$current_add_flags --dns 1.1.1.1 --dns 8.8.8.8"
    end

    set missing_host_deps
    for host_dep in distrobox podman
        if not type -q $host_dep
            set -a missing_host_deps $host_dep
        end
    end

    if test (count $missing_host_deps) -eq 0
        log INFO "Host dependencies already present: distrobox, podman"
    else if test "$DRY_RUN" = "true"
        log INFO "DRY RUN: would install missing host dependencies via system package manager: $missing_host_deps"
    else
        log INFO "Installing missing host dependencies: $missing_host_deps"
        if type -q pacman
            sudo pacman -S --needed --noconfirm $missing_host_deps 2>&1 | tee -a $LOG_FILE
            if test $pipestatus[1] -ne 0
                log ERROR "Failed to install host dependencies. See $LOG_FILE for details"
                exit 1
            end
        else if type -q apt
            sudo apt update 2>&1 | tee -a $LOG_FILE
            if test $pipestatus[1] -ne 0
                log ERROR "Failed to update apt metadata. See $LOG_FILE for details"
                exit 1
            end
            sudo apt install -y $missing_host_deps 2>&1 | tee -a $LOG_FILE
            if test $pipestatus[1] -ne 0
                log ERROR "Failed to install host dependencies. See $LOG_FILE for details"
                exit 1
            end
        else if type -q dnf
            sudo dnf install -y $missing_host_deps 2>&1 | tee -a $LOG_FILE
            if test $pipestatus[1] -ne 0
                log ERROR "Failed to install host dependencies. See $LOG_FILE for details"
                exit 1
            end
        else
            log ERROR "Unknown package manager. Please install these dependencies manually: $missing_host_deps"
            exit 1
        end
    end

    build_distrobox_create_cmd "$image_name" "$gpu_flags" "$current_add_flags"
    if test "$DRY_RUN" = "true"
        log INFO "DRY RUN: would create distrobox container: "(string join ' ' -- $dbx_create_cmd)
    else
        $dbx_create_cmd 2>&1 | tee -a $LOG_FILE
        if test $pipestatus[1] -ne 0
            log ERROR "Container creation failed. See $LOG_FILE for details"
            exit 1
        end
    end
    echo -e "\n$yellow""Installing basic packages. This might take a few minutes...""$normal"

    if test "$DRY_RUN" = "true"
        log INFO "DRY RUN: would enter container and run apt update/install and download $APP_NAME AppImage"
    else
        set install_cmd "set -euo pipefail; echo 'Running: apt update'; sudo apt update; echo 'Running: apt install'; sudo apt install -y curl ca-certificates lsb-release locales libfuse2* sudo libgl1 libglx-mesa0 libegl1 libgl1-mesa-dri libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 libwebkit2gtk-4.1-0 libjavascriptcoregtk-4.1-0 libwayland-server0; sudo locale-gen en_US.UTF-8; echo 'Downloading $APP_NAME AppImage'; tmp_app=\$(mktemp); curl --fail -L --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 300 --progress-bar $ELEGOO_URL -o \"\$tmp_app\"; chmod +x \"\$tmp_app\"; echo 'Installing desktop metadata from the AppImage'; extract_dir=\$(mktemp -d); cd \"\$extract_dir\"; \"\$tmp_app\" --appimage-extract >/dev/null; sudo rm -rf $APP_RUNTIME_DIR; sudo mkdir -p $APP_RUNTIME_DIR; sudo cp -a squashfs-root/. $APP_RUNTIME_DIR/; printf '#!/bin/sh\\nexec %s/AppRun \"\$@\"\\n' $APP_RUNTIME_DIR | sudo tee $APP_LAUNCHER >/dev/null; sudo chmod 0755 $APP_LAUNCHER; desktop_src=\$(find squashfs-root -name '*.desktop' | sort | head -n 1); [ -n \"\$desktop_src\" ] || { echo 'AppImage desktop file not found'; exit 1; }; icon_name=\$(awk -F= '/^Icon=/{print \$2; exit}' \"\$desktop_src\"); if [ -n \"\$icon_name\" ]; then icon_src=\$(find squashfs-root \( -path \"*/\$icon_name.png\" -o -path \"*/\$icon_name.svg\" -o -path \"*/\$icon_name.xpm\" -o -name \"\$icon_name.png\" -o -name \"\$icon_name.svg\" -o -name \"\$icon_name.xpm\" \) | sort | head -n 1); else icon_src=\$(find squashfs-root \( -iname '*ElegooSlicer*.png' -o -iname '*elegoo*.png' -o -iname '*ElegooSlicer*.svg' -o -iname '*elegoo*.svg' \) | sort | head -n 1); fi; sudo install -Dm 0644 \"\$desktop_src\" /usr/share/applications/$APP_DESKTOP; sudo sed -i 's|^Exec=.*|Exec=$APP_LAUNCHER %F|' /usr/share/applications/$APP_DESKTOP; if grep -q '^TryExec=' /usr/share/applications/$APP_DESKTOP; then sudo sed -i 's|^TryExec=.*|TryExec=$APP_LAUNCHER|' /usr/share/applications/$APP_DESKTOP; else echo 'TryExec=$APP_LAUNCHER' | sudo tee -a /usr/share/applications/$APP_DESKTOP >/dev/null; fi; if [ -n \"\$icon_src\" ]; then icon_ext=\${icon_src##*.}; sudo install -Dm 0644 \"\$icon_src\" /usr/share/icons/hicolor/192x192/apps/$APP_ID.\$icon_ext; sudo sed -i 's|^Icon=.*|Icon=$APP_ID|' /usr/share/applications/$APP_DESKTOP; fi; if [ -f /run/host/usr/share/cachyos-fish-config/cachyos-config.fish ]; then sudo mkdir -p /usr/share/cachyos-fish-config; sudo ln -sfn /run/host/usr/share/cachyos-fish-config/cachyos-config.fish /usr/share/cachyos-fish-config/cachyos-config.fish; if [ -d /run/host/usr/share/cachyos-fish-config/conf.d ]; then sudo ln -sfn /run/host/usr/share/cachyos-fish-config/conf.d /usr/share/cachyos-fish-config/conf.d; fi; fi; cd /; rm -rf \"\$extract_dir\"; rm -f \"\$tmp_app\""
        distrobox enter "$CONTAINER_NAME" -- bash -lc "$install_cmd" 2>&1 | tee -a $LOG_FILE
        set install_rc $pipestatus[1]
    end
    if test "$DRY_RUN" = "true"
        set install_success true
    else
        if test $install_rc -eq 0
            set install_success true
        else
            if test "$use_custom_dns" = false
                set use_custom_dns true
            else
                log ERROR "Installation failed. See $LOG_FILE for details"
                exit 1
            end
        end
    end
end

# --- Step 4: Export & Auto-Stop ---
if test "$DRY_RUN" = "true"
    log INFO "DRY RUN: would run distrobox-export --app $APP_ID"
else
    distrobox enter "$CONTAINER_NAME" -- distrobox-export --app $APP_ID 2>&1 | tee -a $LOG_FILE
    if test $pipestatus[1] -ne 0
        log ERROR "Application export failed. See $LOG_FILE for details"
        exit 1
    end
end
set d_files
if test -d ~/.local/share/applications
    set d_files (find ~/.local/share/applications -maxdepth 1 -iname "*$APP_ID*.desktop" | sort)
    if test (count $d_files) -eq 0
        set d_files (find ~/.local/share/applications -maxdepth 1 -iname "*elegoo*.desktop" | sort)
    end
end
if test (count $d_files) -gt 0
    for d_file in $d_files
        sed -i 's|/run/host||' $d_file
        set exec_cmd (grep '^Exec=' $d_file | head -n 1 | cut -d'=' -f2-)
        if test -n "$exec_cmd"
            if not grep -q "distrobox stop" $d_file
                sed -i "s|Exec=.*|Exec=sh -c \"$exec_cmd; distrobox stop $CONTAINER_NAME --yes\"|" $d_file
            end
        end
    end
    if type -q update-desktop-database
        update-desktop-database ~/.local/share/applications
    end
    echo -e "$green""Done! Container stops automatically on exit.""$normal"
else
    if test "$DRY_RUN" = "true"
        log INFO "DRY RUN: desktop file would be created at ~/.local/share/applications/*elegoo*.desktop"
        exit 0
    end
    echo -e "$red""Export failed. Desktop file not found.""$normal"
    echo "See $LOG_FILE for details"
    exit 1
end

