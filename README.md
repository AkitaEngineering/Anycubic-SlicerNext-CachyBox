# Anycubic-SlicerNext-CachyBox
### Anycubic Slicer Next: CachyOS Container Edition

This repository packages Anycubic Slicer Next for CachyOS and other Linux hosts by running it inside an Ubuntu 24.04 Distrobox container backed by Podman.

The installers in this repository use Anycubic's official Ubuntu 24.04 package repository inside the container, then export a desktop launcher back onto the host.

---

## Features

* Installs the published `anycubicslicernext` package from Anycubic's official Ubuntu repository.
* Supports overriding the package repository with `--apt-repo-url` or `ANYCUBIC_APT_REPO_URL`.
* Detects Nvidia, AMD, and Intel GPUs and applies the matching Distrobox/Podman setup.
* Can optionally install `nvidia-container-toolkit` and generate `/etc/cdi/nvidia.yaml` on Arch/CachyOS hosts.
* Exports a launcher that automatically stops the container after the slicer window closes.
* Includes a Compose path that installs the same official package inside the Compose container.

---

## Requirements

Make sure the host has the following available:

* Podman
* Distrobox
* curl
* enough free space for the Ubuntu container image and package downloads; a few GB is usually sufficient
* an `amd64` or `x86_64` host, because the upstream package is published for `amd64`

For Nvidia on non-Arch hosts, configure Podman CDI support ahead of time with `nvidia-container-toolkit` and a generated spec such as `/etc/cdi/nvidia.yaml`.

On Arch/CachyOS, the Bash installer can do that host-side setup for you when you pass `--configure-nvidia-host`.

---

## Installation

1. Clone the repository and enter it.

   ```bash
   git clone https://github.com/AkitaEngineering/Anycubic-SlicerNext-CachyBox.git
   cd Anycubic-SlicerNext-CachyBox
   ```

2. Run the Bash installer.

   ```bash
   chmod +x install.sh
   ./install.sh
   ```

3. Optional overrides:

   Override the official Anycubic package repository or mirror:

   ```bash
   ./install.sh --apt-repo-url https://cdn-universe-slicer.anycubic.com/prod
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

The first full install can take a while because it creates the container, adds Anycubic's Ubuntu repository inside it, installs the published package, and then exports the launcher.

The old source-build overrides `--ref`, `ANYCUBIC_REF`, `--git-url`, and `ANYCUBIC_GIT_URL` are now ignored for backward compatibility.

---

## Runtime Layout

The repository now uses these main paths:

* `~/.cache/anycubic-slicer-next-installer/` for installer and uninstaller logs
* `~/.local/share/applications/` for the exported host desktop entries

Inside the Distrobox container, the official package installs under `/usr/share/AnycubicSlicerNext` with the binary at `/usr/bin/AnycubicSlicerNext`. The installer also creates `/usr/local/bin/AnycubicSlicerNext` and a branded desktop file for Distrobox export.

---

## Compose Usage

The Compose path installs the same official Anycubic package inside the Compose container and launches it directly.

1. Set any overrides you want.

   Fish:

   ```fish
   set -x ANYCUBIC_IMAGE anycubic-custom-amd
   set -x ANYCUBIC_CONTAINERFILE containerfile.amd
   set -x ANYCUBIC_APT_REPO_URL https://cdn-universe-slicer.anycubic.com/prod
   ```

   Bash:

   ```bash
   export ANYCUBIC_IMAGE=anycubic-custom-amd
   export ANYCUBIC_CONTAINERFILE=containerfile.amd
   export ANYCUBIC_APT_REPO_URL=https://cdn-universe-slicer.anycubic.com/prod
   ```

2. Launch Compose.

   ```bash
   podman compose up
   ```

Supported Compose environment variables:

* `ANYCUBIC_IMAGE`
* `ANYCUBIC_CONTAINERFILE`
* `ANYCUBIC_APT_REPO_URL`

On the first run, Compose installs the bootstrap packages in the container, adds Anycubic's Ubuntu repository, installs `anycubicslicernext`, and launches it. Later runs reuse that installed package until you recreate the Compose container.

---

## Troubleshooting

* If the first install fails on downloads or repository access, the Bash installer retries once with explicit DNS servers.
* If Nvidia setup falls back to Generic rendering, verify `nvidia-container-toolkit` is installed and `/etc/cdi/nvidia.yaml` exists.
* If the package install fails, inspect the log under `~/.cache/anycubic-slicer-next-installer/` first and confirm the container is Ubuntu 24.04 (`noble`) on `amd64`.
* If the official repository cannot be reached, verify access to `https://cdn-universe-slicer.anycubic.com/prod` or override it with `ANYCUBIC_APT_REPO_URL`.
* If the desktop icon does not refresh, run `update-desktop-database ~/.local/share/applications` on the host.

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

The uninstaller removes the exported launcher, Distrobox container, custom Podman images, local helper files, and installer logs. It also offers to delete Anycubic Slicer Next configuration directories under `~/.config/`.

---

## Credits

Originally created by Sascha Schüller.

Later adapted and repackaged by Akita Engineering.

This fork retargets the workflow for Anycubic Slicer Next and replaces the old release-download and source-build flow with the official Anycubic Ubuntu package workflow.