#!/bin/bash

set -euo pipefail

APP_NAME="Anycubic Slicer Next"
APP_ID="AnycubicSlicerNext"
APP_SLUG="anycubic-slicer-next"
DEFAULT_ANYCUBIC_GIT_URL="https://github.com/ANYCUBIC-3D/AnycubicSlicerNext.git"
DEFAULT_ANYCUBIC_REF="main"
ANYCUBIC_TAGS_API="https://api.github.com/repos/ANYCUBIC-3D/AnycubicSlicerNext/tags?per_page=100"

ANYCUBIC_GIT_URL="${ANYCUBIC_GIT_URL:-$DEFAULT_ANYCUBIC_GIT_URL}"
ANYCUBIC_REF="${ANYCUBIC_REF:-}"

BUILD_ROOT="$HOME/.local/share/$APP_SLUG"
REPO_DIR="$BUILD_ROOT/source"
APPIMAGE_CACHE_DIR="$BUILD_ROOT/appimage"
APPIMAGE_CACHE_FILE="$APPIMAGE_CACHE_DIR/$APP_ID.AppImage"
RUNTIME_DIR="$BUILD_ROOT/runtime"
LAUNCHER_PATH="$HOME/.local/bin/$APP_ID"
REF_FILE="$BUILD_ROOT/last-build-ref"
REPO_URL_FILE="$BUILD_ROOT/last-build-repo-url"

resolve_anycubic_ref(){
    local tags_response latest_ref

    if [ -n "$ANYCUBIC_REF" ]; then
        printf '%s\n' "$ANYCUBIC_REF"
        return 0
    fi

    tags_response=$(curl --fail -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 60 \
        -H 'Accept: application/vnd.github+json' "$ANYCUBIC_TAGS_API" || true)
    latest_ref=$(printf '%s' "$tags_response" | grep -oE '"name":[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"/\1/' | grep -E '^[A-Za-z0-9._-]+$' | sort -V | tail -n 1)

    if [ -n "$latest_ref" ]; then
        printf '%s\n' "$latest_ref"
    else
        printf '%s\n' "$DEFAULT_ANYCUBIC_REF"
    fi
}

ANYCUBIC_REF=$(resolve_anycubic_ref)

mkdir -p "$HOME/.local/bin" "$BUILD_ROOT" "$APPIMAGE_CACHE_DIR"

cached_ref=""
cached_repo_url=""

if [ -f "$REF_FILE" ]; then
    cached_ref=$(cat "$REF_FILE")
fi

if [ -f "$REPO_URL_FILE" ]; then
    cached_repo_url=$(cat "$REPO_URL_FILE")
fi

build_needed=false
extract_needed=false

if [ ! -f "$APPIMAGE_CACHE_FILE" ] || [ "$cached_ref" != "$ANYCUBIC_REF" ] || [ "$cached_repo_url" != "$ANYCUBIC_GIT_URL" ]; then
    build_needed=true
    extract_needed=true
fi

if [ ! -x "$RUNTIME_DIR/AppRun" ] || [ ! -x "$LAUNCHER_PATH" ]; then
    extract_needed=true
fi

if [ "$build_needed" = true ]; then
    echo "Bootstrapping packages for $APP_NAME"
    sudo apt update
    sudo apt install -y ca-certificates curl file fuse git locales lsb-release rsync sed sudo xz-utils
    sudo locale-gen en_US.UTF-8
    export DEBIAN_FRONTEND=noninteractive
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

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

    echo "Installing upstream system build dependencies"
    (
        cd "$REPO_DIR"
        ./build_linux.sh -u
    )

    find "$REPO_DIR/build" -maxdepth 4 -type f -name '*.AppImage' -delete 2>/dev/null || true

    build_args=(-d -s -i -r)
    if [ "$cached_ref" != "$ANYCUBIC_REF" ] || [ "$cached_repo_url" != "$ANYCUBIC_GIT_URL" ]; then
        build_args=(-c "${build_args[@]}")
    fi

    echo "Building $APP_NAME from source at ref $ANYCUBIC_REF"
    (
        cd "$REPO_DIR"
        ./build_linux.sh "${build_args[@]}"
    )

    appimage_path=$(find "$REPO_DIR/build" -maxdepth 4 -type f -name '*.AppImage' | sort | tail -n 1)
    [ -n "$appimage_path" ] || {
        echo 'Built AppImage not found under build/'
        exit 1
    }

    install -Dm 0755 "$appimage_path" "$APPIMAGE_CACHE_FILE"
    printf '%s\n' "$ANYCUBIC_REF" > "$REF_FILE"
    printf '%s\n' "$ANYCUBIC_GIT_URL" > "$REPO_URL_FILE"
fi

if [ "$extract_needed" = true ]; then
    TMP_DIR=$(mktemp -d)
    APPIMAGE_PATH="$TMP_DIR/$APP_ID.AppImage"
    cp "$APPIMAGE_CACHE_FILE" "$APPIMAGE_PATH"
    chmod +x "$APPIMAGE_PATH"

    cd "$TMP_DIR"
    "$APPIMAGE_PATH" --appimage-extract >/dev/null

    rm -rf "$RUNTIME_DIR"
    mkdir -p "$RUNTIME_DIR"
    cp -a squashfs-root/. "$RUNTIME_DIR/"
    printf '#!/bin/sh\nexec %s/AppRun "$@"\n' "$RUNTIME_DIR" > "$LAUNCHER_PATH"
    chmod +x "$LAUNCHER_PATH"

    cd /
    rm -rf "$TMP_DIR"
fi

exec "$LAUNCHER_PATH"