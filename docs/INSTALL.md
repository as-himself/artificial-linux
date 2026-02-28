# Artificial Linux - Installation Guide

![Logo](../branding/logo.png)

## Prerequisites

- A Linux build environment (native or VM via QEMU/WSL)
- 8GB+ RAM, 4+ CPU cores recommended (TinyLlama runs well on 8GB)
- ~80GB disk for LFS build
- Quantized GGUF model: e.g. `tinyllama-1.1b-chat-v1.0-Q5_K_M.gguf` (place in `/tmp` or set `ALFS_GGUF`)

## Supported models

- **TinyLlama-1.1B-Chat-v1.0** (default): 1.1B parameters, small footprint, good for low-memory systems. Place HuggingFace model files in `model/` and run `./convert/convert-model.sh`.
- **Granite-4.0-Micro**: 3B parameters; use if conversion is supported and you have more RAM.
- You can also download a pre-quantized GGUF (e.g. from Hugging Face) and copy it to `/usr/share/models/artificial-linux-slm.gguf` on the target system.

## Conversion (host)

1. Ensure `model/` contains a HuggingFace model (e.g. TinyLlama: `config.json`, tokenizer files, and weight files).
2. Run: `./convert/convert-model.sh`
3. If you see **NumPy 2.x** or **torch.uint64** errors, the script pins `numpy<2`. Remove the venv and re-run so dependencies are reinstalled:
   ```bash
   rm -rf build/venv-convert
   ./convert/convert-model.sh
   ```
4. Output is in `build/gguf/` (e.g. `tinyllama-1.1b-chat-v1.0-Q5_K_M.gguf`).

## Quick start (from built system)

1. Copy the GGUF to the target: `/usr/share/models/artificial-linux-slm.gguf` (or set the service to use your filename).
2. Enable and start the AI fabric:
   ```bash
   sudo systemctl enable --now slm-server.service
   sudo systemctl enable --now ai-fabric.target
   ```
3. Use the `ask` command:
   ```bash
   ask "How do I check disk usage?"
   ```

## Full build (LFS + BLFS + AI fabric)

1. **Set up the build VM** (macOS + QEMU):
   ```bash
   BOOT_FROM_ISO=1 ./scripts/00-setup-vm.sh
   ```
   A QEMU GUI window will open with the Debian installer.  
   *(For headless mode: `QEMU_NOGRAPHIC=1 BOOT_FROM_ISO=1 ./scripts/00-setup-vm.sh`)*
   
   During installation:
   - Create a user (e.g., `lfsuser`)
   - Enable SSH server (required for file transfer)
   - After install, power off the VM

2. **Convert the model** on the host: `./convert/convert-model.sh` (output in `build/gguf/`).

3. **Boot the VM** and transfer the GGUF:
   ```bash
   # Boot normally (no ISO)
   ./scripts/00-setup-vm.sh
   
   # From another terminal, copy GGUF to VM
   scp -P 2222 build/gguf/tinyllama-1.1b-chat-v1.0-Q5_K_M.gguf lfsuser@localhost:/tmp/
   ```
   Or set `ALFS_GGUF` to the path of your GGUF when running the inference script.

4. **Run the build** inside the VM (as root):
   ```bash
   # SSH into VM
   ssh -p 2222 lfsuser@localhost
   
   # Switch to root (set root password during Debian install if needed)
   su -
   cd /home/lfsuser/artificial-linux
   ALFS_PROJECT_ROOT=$(pwd) ./scripts/build-all.sh
   ```
   **Important:** Set a root password during Debian installation (or run `passwd root` as root later). The build needs root for phases 02 and 04.

## Recovery: broken sudo or no root access

If you see *"sudo must be owned by uid 0"* or *"su: Authentication failure"*:

1. **Power off the VM** (close QEMU or `poweroff` from the VM).
2. **Boot from the Debian ISO again** (same as initial install):  
   `BOOT_FROM_ISO=1 ./scripts/00-setup-vm.sh`
3. In the Debian installer, choose **"Advanced options"** → **"Rescue mode"** (or "Recovery").
4. Select your installed system (e.g. `/dev/vda1`), then **"Execute a shell in /dev/vda1"** (or similar).
5. In the rescue shell, fix permissions and set root password:
   ```bash
   chown root:root /usr/bin/sudo
   chmod 4755 /usr/bin/sudo
   passwd root   # set a password you will remember
   exit
   ```
6. Reboot (remove ISO boot and start VM normally). Then `ssh` in and use `su -` with the new root password.

If rescue mode is too involved, **reinstall the VM**: new Debian install, create user, **set root password** when prompted, enable SSH, then run the build as root.
5. After the build, boot the new system and enable the AI fabric as in Quick start.

## Bootable live ISO

Phase 10 creates a **full bootable live ISO** (`artificial-linux-1.0-live.iso`) that includes:

- Root filesystem (squashfs) with the built system
- Kernel and initramfs (live boot from CD/ISO)
- TinyLlama GGUF model (if present at `/usr/share/models/artificial-linux-slm.gguf` or copied to `/tmp/*.gguf` before running phase 10)

Copy the GGUF to the VM before running the full build (or before re-running phase 10) so it is included:

```bash
scp -P 2222 build/gguf/tinyllama-1.1b-chat-v1.0-Q5_K_M.gguf lfsuser@localhost:/tmp/
```

Then run the build (or `ALFS_FROM=10 ./scripts/build-all.sh`). Output: `build/iso/artificial-linux-1.0-live.iso`. Boot from this ISO to run Artificial Linux live (no install required).

**Re-run phase 10** (e.g. after updating the ISO script or adding the GGUF): use `ALFS_FORCE=10` with the same command, or clear the state and run:
```bash
sed -i '/^phase10=/d' build/.alfs-state
ALFS_PROJECT_ROOT=$(pwd) ALFS_FROM=10 ./scripts/build-all.sh
```

## Troubleshooting

- **Conversion: NumPy / torch errors**: Use `numpy<2` (script does this). Delete `build/venv-convert` and run the convert script again.
- **SLM not responding**: Check `systemctl status slm-server.service`. Ensure `/usr/share/models/artificial-linux-slm.gguf` exists.
- **ask timeout**: Set `ASK_TIMEOUT=120` in `/etc/ai-fabric/ask.conf` or in the environment.
- **eBPF/BPF LSM**: Requires kernel with `CONFIG_BPF_LSM=y` and `CONFIG_DEBUG_INFO_BTF=y`.
