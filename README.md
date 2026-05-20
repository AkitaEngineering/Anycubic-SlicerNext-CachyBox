# Anycubic-SlicerNext-CachyBox
### Anycubic Slicer Next: CachyOS Container Edition

This repository packages Anycubic Slicer Next for CachyOS and other Linux hosts by running it inside an Ubuntu 24.04 Distrobox container backed by Podman.

This upstream does not publish GitHub release binaries. The installers in this repository clone the official Anycubic source tree, resolve the newest upstream tag by default, build the Linux AppImage in-container, cache it locally, and export a desktop launcher back onto the host.

---

## Features

* Builds from the official upstream source repository at `ANYCUBIC-3D/AnycubicSlicerNext`.
* Resolves the latest upstream tag automatically, with `--ref` and `ANYCUBIC_REF` overrides.
* Supports an alternate upstream remote via `--git-url` or `ANYCUBIC_GIT_URL`.
* Detects Nvidia, AMD, and Intel GPUs and applies the matching Distrobox/Podman setup.
* Can optionally install `nvidia-container-toolkit` and generate `/etc/cdi/nvidia.yaml` on Arch/CachyOS hosts.
* Caches the upstream checkout, built AppImage, and extracted runtime under `~/.local/share/anycubic-slicer-next/`.
* Exports a launcher that automatically stops the container after the slicer window closes.
* Includes a Compose path that uses the same build-and-cache strategy.

---

## Requirements

Make sure the host has the following available:

* Podman
* Distrobox
* curl
* enough free space and memory for a source build; roughly 12 GB of disk and 10 GiB of available RAM is a practical baseline

For Nvidia on non-Arch hosts, configure Podman CDI support ahead of time with `nvidia-container-toolkit` and a generated spec such as `/etc/cdi/nvidia.yaml`.

On Arch/CachyOS, the Bash installer can do that host-side setup for you when you pass `--configure-nvidia-host`.

---

## Installation

1. Clone the repository and enter it.

   ```bash
   git clone https://github.com/Slashdacoda/AnySlicer-Next-CachyBox.git
   cd AnySlicer-Next-CachyBox
   ```

2. Run the Bash installer.

   ```bash
   chmod +x install.sh
   ./install.sh
   ```

3. Optional overrides:

   Build a specific upstream tag or branch:

   ```bash
   ./install.sh --ref v2.3.1
   ```

   Point at a different Git remote:

   ```bash
   ./install.sh --git-url https://github.com/ANYCUBIC-3D/AnycubicSlicerNext.git
   ```

   Opt into automatic Nvidia host configuration on Arch/CachyOS:

   ```bash
   ./install.sh --configure-nvidia-host
   ```

   Run the preflight checks only:

   ```bash
   ./install.sh --check
   ```

4. If you prefer Fish as the entrypoint, use:

   ```fish
   chmod +x install.fish
   ./install.fish
   ```

The first full install can take a while because it clones the upstream repo, installs build dependencies inside the container, compiles the application, generates an AppImage, and then exports it.

After the first build, reruns reuse the cached source tree and AppImage unless the selected ref or Git URL changes.

---

## Runtime Layout

The repository now uses these main paths:

* `~/.local/share/anycubic-slicer-next/source/` for the upstream checkout
* `~/.local/share/anycubic-slicer-next/appimage/` for the built AppImage cache
* `~/.local/share/anycubic-slicer-next/runtime/` for the extracted runtime used by Compose
* `~/.cache/anycubic-slicer-next-installer/` for installer and uninstaller logs

Inside the Distrobox container, the exported runtime is installed under `/opt/AnycubicSlicerNext` and exposed through `/usr/local/bin/AnycubicSlicerNext`.

---

## Compose Usage

The Compose path builds and caches the upstream AppImage using the same approach as the interactive installer.

1. Set any overrides you want.

   Fish:

   ```fish
   set -x ANYCUBIC_IMAGE anycubic-custom-amd
   set -x ANYCUBIC_CONTAINERFILE containerfile.amd
   set -x ANYCUBIC_REF v2.3.1
   ```

   Bash:

   ```bash
   export ANYCUBIC_IMAGE=anycubic-custom-amd
   export ANYCUBIC_CONTAINERFILE=containerfile.amd
   export ANYCUBIC_REF=v2.3.1
   ```

2. Launch Compose.

   ```bash
   podman compose up
   ```

Supported Compose environment variables:

* `ANYCUBIC_IMAGE`
* `ANYCUBIC_CONTAINERFILE`
* `ANYCUBIC_GIT_URL`
* `ANYCUBIC_REF`

On the first run, Compose will install the bootstrap packages in the container, clone the upstream repo, build the AppImage, extract it into `~/.local/share/anycubic-slicer-next/runtime/`, and launch it. Later runs only rebuild when the selected ref or upstream URL changes.

---

## Troubleshooting

* If the first install fails on downloads or Git fetches, the Bash installer retries once with explicit DNS servers.
* If Nvidia setup falls back to Generic rendering, verify `nvidia-container-toolkit` is installed and `/etc/cdi/nvidia.yaml` exists.
* If the source build fails, inspect the log under `~/.cache/anycubic-slicer-next-installer/` first. Upstream build failures usually come from missing host resources rather than launcher integration.
* If the desktop icon does not refresh, run `update-desktop-database ~/.local/share/applications` on the host.
* If the compile fails due to low memory, add swap or try again when more RAM is available; the upstream build script is resource-heavy.

---

## Uninstallation

Run:

```bash
./uninstall.sh
```

Or, if you prefer Fish:

```fish
./uninstall.fish
```

The uninstaller removes the exported launcher, Distrobox container, custom Podman images, cached runtime tree, build cache, and installer logs. It also offers to delete Anycubic Slicer Next configuration directories under `~/.config/`.

---

## Credits

Originally created by Sascha Schüller.

Later adapted and repackaged by Akita Engineering.

This fork retargets the workflow for Anycubic Slicer Next and replaces the old release-download path with an upstream source build flow that matches the current Anycubic repository layout.