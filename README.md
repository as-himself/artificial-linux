# Artificial Linux

![Artificial Linux logo](branding/logo.png)

**Artificial Linux** is a Linux From Scratch (LFS) distribution with a Small Language Model (SLM) integrated into the OS: shell assistance, build-log analysis, eBPF kernel monitoring, and optional BPF LSM security coordination.

## Features

- **LFS + BLFS base**: Custom Linux system built from source (LFS 12.x systemd).
- **SLM inference**: **TinyLlama 1.1B Chat** (or Granite-4.0-Micro) via llama.cpp, quantized to Q5_K_M. Lightweight and runs well on 8–16 GB RAM.
- **AI fabric**: systemd service for the inference server, C++ `ask` gateway, shell integration (error analysis, MOTD), `ai-make` build wrapper.
- **eBPF**: Kernel event monitor (execve) and BPF LSM gatekeeper coordinated by an SLM guard script.
- **Live ISO**: Phase 10 produces a full bootable live image (`artificial-linux-1.0-live.iso`) with root filesystem (squashfs), kernel, initramfs, and the TinyLlama GGUF model so users can boot and run Artificial Linux without installing.

## Project layout

- `config/` – QEMU, LFS, and kernel config.
- `scripts/` – Build and setup scripts (00–10, build-all.sh).
- `convert/` – Model conversion (HuggingFace → GGUF Q5_K_M); supports TinyLlama and Granite.
- `src/` – ask binary, eBPF programs, shell profile, slm-guard.
- `systemd/` – Unit files for SLM server, guard, eBPF monitor.
- `branding/` – Logo, os-release, issue, lsb-release.
- `model/` – TinyLlama-1.1B-Chat-v1.0 (or other HF model; convert before use).
- `docs/` – [INSTALL.md](docs/INSTALL.md), [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Quick start

1. **Convert model** (on macOS/Linux host):  
   `./convert/convert-model.sh`  
   Uses `model/` (e.g. TinyLlama). Output: `build/gguf/<model>-Q5_K_M.gguf`.  
   If conversion fails (numpy/torch), remove the venv and retry:  
   `rm -rf build/venv-convert && ./convert/convert-model.sh`(It might install an already quantized gguf from huggingface if you don't have a model to convert)
2. **Set up VM** (macOS/QEMU):  
   `BOOT_FROM_ISO=1 ./scripts/00-setup-vm.sh`  
   A QEMU window will open showing the Debian installer.  
   *(For headless mode: `QEMU_NOGRAPHIC=1 BOOT_FROM_ISO=1 ./scripts/00-setup-vm.sh`)*

   # Running the live ISO (-m 4G recommended for a smoother experience)
   qemu-system-x86_64 -serial stdio -cdrom build/iso/artificial-linux-1.0-live.iso -boot d -m 4G

   **During Debian Installation:**
   - Select "Install" (text mode recommended)
   - Create a user (e.g., `lfsuser`)
   - **Enable SSH server** (required for file transfer)
   - After install completes, **power off the VM** (don't reboot yet)

   **Continue the build:**

   ```bash
   # Boot normally (no ISO) - QEMU window will open again
   ./scripts/00-setup-vm.sh

   # In another terminal, SSH into VM
   ssh -p 2222 lfsuser@localhost

   # Copy GGUF to VM (from your terminal)
   scp -P 2222 build/gguf/tinyllama-1.1b-chat-v1.0-Q5_K_M.gguf lfsuser@localhost:/tmp/

   # STEP 1: From your Host terminal copy the project to the VM
   # Make sure VM is running first
   ./scripts/00-setup-vm.sh

   # In another terminal, tar up the project (excluding build artifacts)
   cd "/path/to/Documents/Artificial Linux"
   tar czf artificial-linux.tar.gz \
   --exclude='build/' \
   --exclude='model/' \
   --exclude='.git/' \
   config/ scripts/ src/ systemd/ branding/ convert/ docs/ README.md BUILD_GUIDE.md

   # Copy to VM
   scp -P 2222 artificial-linux.tar.gz lfsuser@localhost:/home/lfsuser/

   # Also copy the GGUF model
   scp -P 2222 build/gguf/tinyllama-1.1b-chat-v1.0-Q5_K_M.gguf lfsuser@localhost:/tmp/

   # STEP 2: SSH into the VM and extract
   ssh -p 2222 lfsuser@localhost

   # Inside the VM:
   cd ~
   tar xzf artificial-linux.tar.gz
   cd Artificial\ Linux  # or wherever it extracted to

   # Copy script from mac to VM
   scp -P 2222 scripts/10-create-iso.sh lfsuser@localhost:~/artificial-linux/scripts/

   # Now run the build(MUST BE ROOT - su)
   ALFS_PROJECT_ROOT=$(pwd) ./scripts/build-all.sh

   # From root
   LFS=/ ALFS_FORCE=10 ALFS_PROJECT_ROOT=$(pwd) ALFS_FROM=10 ./scripts/build-all.sh

   or 

   env -u LFS ALFS_FORCE=10 ALFS_PROJECT_ROOT=$(pwd) ALFS_FROM=10 ./scripts/build-all.sh

   # Incase you need to start the iso build again
   sed -i '/^phase10=/d' build/.alfs-state
   sed -i '/^phase0[89]=/d; /^phase10=/d' build/.alfs-state


   # Copy ISO to HOST system
   scp -P 2222 lfsuser@localhost:/home/lfsuser/artificial-linux/build/iso/artificial-linux-1.0-live.iso "/path/to/Documents/Artificial Linux/build/iso/"

   # Check the ISO
   xorriso -indev "build/iso/artificial-linux-1.0-live.iso" -find / -type f

   # Boot the Live ISO (from host; QEMU uses same window as Debian install)
   BOOT_LIVE_ISO=1 ./scripts/00-setup-vm.sh

   # To see boot logs in terminal (serial console), use QEMU directly:
   qemu-system-x86_64 -serial stdio -cdrom build/iso/artificial-linux-1.0-live.iso -boot d -m 4G
   # (Use -cdrom so the ISO is the CD; without it the ISO is attached as a disk and the live root won't mount.)
   # BOOT_LIVE_ISO=1 ./scripts/00-setup-vm.sh is equivalent (uses same -cdrom and -boot d); use whichever you prefer.

   # Removing old key
   ssh-keygen -R "[localhost]:2222"

   # Enable slm-server
   systemctl enable --now slm-server.service; systemctl enable --now ai-fabric.target

   # status
   sudo systemctl status slm-server.service --no-pager


**Architecture:** The kernel is built for **x86_64**. The ISO is built with both `grub-pc-bin` (BIOS) and `grub-efi-amd64-bin` (UEFI) so `grub-mkrescue` produces a hybrid ISO that boots on BIOS and UEFI. Install on the build VM: `apt install grub-efi-amd64-bin` if the ISO only had i386-pc before.

**Note:** `build/venv-convert/` and PyTorch there are only for **model conversion** on the host (e.g. HuggingFace → GGUF). They are not used by the live ISO or the VM; if conversion fails, remove the venv and re-run `./convert/convert-model.sh`. The blank-screen boot issue is separate (initramfs/kernel console); no need to start from scratch for that.

See [docs/INSTALL.md](docs/INSTALL.md) for installation and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for architecture details.

## Troubleshooting

**`ask` says "Could not connect to server" / slm-server fails with signal ILL (SIGILL)**  
The live ISO was built with a llama-server binary that uses CPU instructions (e.g. AVX2) not available on the machine you’re running (e.g. QEMU). Rebuild inference and repack the ISO on the **build VM** (Debian, not the live ISO):

1. Boot the build VM (no live ISO): `./scripts/00-setup-vm.sh`
2. Sync the project into the VM (e.g. `rsync` or tar+scp as in Quick start), then SSH in.
3. As root: `cd ~/artificial-linux` (or your project path), then:
   ```bash
   sed -i '/^phase08=/d; /^phase09=/d; /^phase10=/d' build/.alfs-state
   ALFS_PROJECT_ROOT=$(pwd) ALFS_FROM=08 ./scripts/build-all.sh
   ```
4. Copy the new ISO back to the host and boot that image. The new squashfs will contain a portable llama-server and `ask` should work.

**Live ISO feels slow**  
Use more RAM for QEMU (e.g. `-m 4G` instead of `-m 2G`). The default target is graphical; with 2G the system is tight and many services may fail or retry.

**`ask` times out (Timeout was reached)**  
On CPU-only or low-memory systems the SLM can take 1–2+ minutes to answer. The client default is 120s; config is in `/etc/ai-fabric/ask.conf` (`ASK_TIMEOUT=180`). For the current session: `export ASK_TIMEOUT=180` then run `ask "your question"` again.

## References

- [Linux From Scratch (LFS)](https://www.linuxfromscratch.org/lfs/)
- [Beyond LFS (BLFS)](https://www.linuxfromscratch.org/blfs/)
- [llama.cpp](https://github.com/ggerganov/llama.cpp)
- [TinyLlama](https://github.com/jzhang38/TinyLlama)
- [IBM Granite](https://github.com/ibm-granite/granite-models)
