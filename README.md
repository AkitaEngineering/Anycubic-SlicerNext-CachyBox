# ElegooSlicer-CachyBox
### Elegoo Slicer: CachyOS Container Edition

This repository contains installer scripts and container configuration that make it simple to run **Elegoo Slicer** inside a lightweight Ubuntu 24.04 LTS container using **Distrobox** and **Podman**. The container approach isolates upstream Linux AppImage dependencies from your host while still preserving native desktop integration and GPU acceleration.

---

## Features

* **Latest release resolution:** Resolves the latest Linux AppImage from the official Elegoo GitHub releases by default, with overrides available via `--url` or `ELEGOO_URL`.
* **Hardware-aware detection:** Automatically identifies Nvidia, AMD, or Intel GPUs and sets up the correct driver stack.
* **Manual hardware override:** Lets you force Nvidia, AMD, Intel, or Generic rendering during setup.
* **Opt-in Nvidia host setup:** On Arch/CachyOS, the installers can optionally install `nvidia-container-toolkit` and generate `/etc/cdi/nvidia.yaml` for you.
* **Image source selection:** Choose between a stock Ubuntu 24.04 image or a locally built image from the included GPU-specific `containerfile.*` definitions.
* **Automatic resource management:** The exported launcher stops the Distrobox container when the Elegoo Slicer window closes.
* **Desktop integration:** Installs a cleaned-up launcher with corrected icon paths and exported menu entries.
* **Network retry handling:** Retries the install with explicit DNS settings if release downloads fail due to resolver issues.

---

## Prerequisites

Ensure your host system has the following installed:

* **Podman**
* **Distrobox**
* **curl**
* **nvidia-container-toolkit** and a generated CDI spec such as `/etc/cdi/nvidia.yaml` if you plan to use the Nvidia path on non-Arch hosts

On Arch/CachyOS, you can let either installer do that host setup for you by passing `--configure-nvidia-host`.

---

## Installation

1. **Clone your copy of the repository and enter the directory:**

   ```bash
   git clone https://github.com/AkitaEngineering/ElegooSlicer-CachyBox.git
   cd ElegooSlicer-CachyBox
   ```

2. **Run the default Bash installer:**

   ```bash
   chmod +x install.sh
   ./install.sh
   ```

   On Arch/CachyOS, add `--configure-nvidia-host` if you want the installer to install `nvidia-container-toolkit` and generate `/etc/cdi/nvidia.yaml` before taking the Nvidia path:

   ```bash
   ./install.sh --configure-nvidia-host
   ```

   If you want the Fish variant instead:

   ```bash
   chmod +x install.fish
   ./install.fish
   ```

   Fish supports the same opt-in host setup flag:

   ```bash
   ./install.fish --configure-nvidia-host
   ```

3. **Answer the prompts.**

   The installer will:
   * detect your GPU and let you override the driver stack,
   * optionally build a custom container image,
   * resolve the latest Elegoo Slicer Linux AppImage unless you override it,
   * extract the AppImage inside the container, and
   * export the application into your desktop menu.

Once complete, Elegoo Slicer will appear in your application launcher. Closing the window automatically stops the container.

---

## File Structure

| File | Purpose |
| :--- | :--- |
| `install.sh` | Default Bash installer for Linux hosts. |
| `install.fish` | Optional Fish-shell installer variant. |
| `uninstall.sh` / `uninstall.fish` | Remove containers, images, launchers, and optional config. |
| `containerfile.[gpu]` | Local image build recipes for AMD, Nvidia, and Intel paths. |
| `docker-compose.yml` | Compose-based launch path for Elegoo Slicer. |

---

## Functionality Summary

1. **GPU override:** Detects your hardware but still lets you choose the final driver stack.
2. **Image source options:** Use Ubuntu 24.04 directly or build a tuned local image.
3. **Auto-stop launcher:** Exported desktop entries shut down the container when the app exits.
4. **Desktop cleanup:** Exported launchers are rewritten to avoid `/run/host` icon path issues.

---

## Advanced Usage: Podman Compose

You can bypass the interactive installers and run the container manually.

1. Export the desired image and Containerfile variables:
   * Fish: `set -x ELEGOO_IMAGE elegoo-custom-amd; set -x ELEGOO_CONTAINERFILE containerfile.amd`
   * Bash: `export ELEGOO_IMAGE=elegoo-custom-amd; export ELEGOO_CONTAINERFILE=containerfile.amd`

2. Optional: override the release URL if you want a specific AppImage:
   * Fish: `set -x ELEGOO_URL https://github.com/ELEGOO-3D/ElegooSlicer/releases/download/.../ElegooSlicer_Linux_....AppImage`
   * Bash: `export ELEGOO_URL=https://github.com/ELEGOO-3D/ElegooSlicer/releases/download/.../ElegooSlicer_Linux_....AppImage`

3. Launch:

   ```bash
   podman compose up
   ```

On first launch, the compose setup builds the selected image if needed, resolves the latest Linux AppImage, and caches the extracted runtime under `~/.local/share/elegoo-slicer/`. Later runs only refresh that cache when the resolved release URL changes.

---

## Troubleshooting

* **DNS errors:** The installer retries with `--dns 1.1.1.1` and `--dns 8.8.8.8` if container-side downloads fail.
* **Nvidia install hangs at container creation:** Install `nvidia-container-toolkit`, generate a CDI spec such as `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`, then rerun the installer. On Arch/CachyOS you can also rerun with `--configure-nvidia-host` or choose the automatic setup prompt. If CDI support is unavailable, the scripts fall back to Generic rendering.
* **FUSE errors:** The container installs `libfuse2*`, but your host still needs working FUSE support.
* **Broken icons:** Run `update-desktop-database ~/.local/share/applications` after install.

---

## FAQ

### Why use Distrobox?

Elegoo Slicer ships as a Linux AppImage, but containerizing it avoids host-library mismatches that are common on rolling-release distros while keeping the application integrated into the desktop.

### Is there a performance penalty?

No meaningful one. GPU devices are passed through directly via `/dev/dri` or the Nvidia stack, so the 3D preview runs with native acceleration.

### Where are my settings stored?

Configurations typically persist in `~/.config/ElegooSlicer/` on the host. They remain intact if you recreate the container unless you explicitly remove them during uninstall.

---

## Uninstallation

Run `./uninstall.sh` to remove the container, custom images, desktop entries, local runtime cache, and optionally your Elegoo Slicer configuration.

If you want the Fish variant, run `./uninstall.fish`.

---

## Credits

Originally created by Sascha Schüller.

Forked, adapted for Elegoo Slicer, validated, and released by Akita Engineering.
