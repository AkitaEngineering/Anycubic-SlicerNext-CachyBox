#!/bin/bash

set -euo pipefail

APP_NAME="Anycubic Slicer Next"
APP_ID="AnycubicSlicerNext"
DEFAULT_ANYCUBIC_APT_REPO_URL="https://cdn-universe-slicer.anycubic.com/prod"

ANYCUBIC_APT_REPO_URL="${ANYCUBIC_APT_REPO_URL:-$DEFAULT_ANYCUBIC_APT_REPO_URL}"
LEGACY_ANYCUBIC_GIT_URL="${ANYCUBIC_GIT_URL:-}"
LEGACY_ANYCUBIC_REF="${ANYCUBIC_REF:-}"

if [ -n "$LEGACY_ANYCUBIC_REF" ]; then
    echo "WARNING: ANYCUBIC_REF is ignored; Compose now uses the official Ubuntu package." >&2
fi

if [ -n "$LEGACY_ANYCUBIC_GIT_URL" ]; then
    echo "WARNING: ANYCUBIC_GIT_URL is ignored; Compose now uses the official Anycubic package repository." >&2
fi

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

echo "Bootstrapping packages for $APP_NAME"
sudo apt update
sudo apt install -y ca-certificates curl locales lsb-release sudo xz-utils
sudo locale-gen en_US.UTF-8

release_codename=$(lsb_release -sc)
if [ "$release_codename" != 'noble' ]; then
    echo "The official $APP_NAME package is only published for Ubuntu 24.04 (noble)."
    exit 1
fi

repo_file='/etc/apt/sources.list.d/acnext.list'
repo_entry="deb [trusted=yes] $ANYCUBIC_APT_REPO_URL $release_codename main"
current_repo_entry=''
if [ -f "$repo_file" ]; then
    current_repo_entry=$(cat "$repo_file")
fi

if [ "$current_repo_entry" != "$repo_entry" ]; then
    printf '%s\n' "$repo_entry" | sudo tee "$repo_file" >/dev/null
fi

echo 'Running: apt update (official Anycubic repo)'
sudo apt update

if dpkg -s anycubicslicernext >/dev/null 2>&1; then
    echo "Refreshing official $APP_NAME package"
else
    echo "Installing official $APP_NAME package"
fi
sudo apt install -y anycubicslicernext

binary_path="/usr/bin/$APP_ID"
[ -x "$binary_path" ] || {
    echo "Installed binary not found at $binary_path"
    exit 1
}

exec "$binary_path"