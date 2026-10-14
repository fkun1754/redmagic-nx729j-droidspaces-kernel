# REDMAGIC 8S Pro+ (NX729J) Droidspaces kernel build recipe

English | [简体中文](README.md)

Build a GKI kernel with [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS)
container support for the REDMAGIC 8S Pro+ (NX729J, Snapdragon 8 Gen 2 / SM8550).

> Pure-AI-built project (DeepSeek V4 Flash + Codex)

## The problem this solves

Droidspaces needs PID and IPC namespaces, SYSVIPC and a few more options, and most
stock GKI kernels do not have them (the NX729J does not). Enabling them the naive
way changes the size of `task_struct`, which invalidates the symbol CRCs of all
374 prebuilt vendor modules -- the phone then boots to a black screen.

The recipe here:

1. uses the **same upstream tree and commit the stock kernel was built from**
   (Google ACK `android13-5.15`, commit `b1f32b310a30`);
2. uses the **phone's own `/proc/config.gz` as the base config**;
3. adds only the options Droidspaces needs;
4. applies the official Droidspaces **kABI padding patch**, which moves
   `sysv_sem`/`sysv_shm` into the ABI slots Android already reserves, so the
   layout of `task_struct` -- and therefore every exported symbol CRC -- stays
   byte-identical to stock;
5. disables `TRIM_UNUSED_KSYMS`, so the kernel exports every symbol instead of a
   trimmed whitelist (a superset of stock, never a subset).

## Verification on this device

All **374 vendor kernel modules** (270 in `vendor_dlkm` plus the rest inside the
`vendor_boot` ramdisk) were checked symbol by symbol against the new kernel:

```
modules with real problems : 0
truly missing symbols      : 0
crc mismatches             : 0
```

> Checking `/vendor/lib/modules` alone is not enough: many symbols
> (`qcom_scm_*`, `gh_rm_*`, `llcc_slice_*`, `ipc_log_*`) are exported by modules
> that live in the **`vendor_boot` ramdisk**. `check_crc.py` covers both.

## Files

| File | Purpose |
|---|---|
| `nx729j-RedMagicOS10.0.12.config` | The phone's stock kernel config (`/proc/config.gz`) |
| `config.fragment` | Options this recipe adds or turns off |
| `patches/001.GKI...patch` | Droidspaces' kABI patch (GPL-3.0, origin in `patches/README.md`) |
| `build.sh` | One-shot build script |
| `check_crc.py` | Pre-flash vendor-module CRC verification (**run it before flashing**) |

## Build

```bash
sudo apt install build-essential bc bison flex libssl-dev libelf-dev \
                 cpio lz4 zstd dwarves python3 kmod clang-14 lld-14 llvm-14
./build.sh
```

Output: `$WORK/ack/arch/arm64/boot/Image`

> `LTO_CLANG_FULL` needs about 15 GB of RAM at link time. On a small machine
> switch to ThinLTO (what Google uses for GKI; it changes neither the ABI nor any
> CRC): `scripts/config --disable LTO_CLANG_FULL --enable LTO_CLANG_THIN`

## Flashing (touches `boot_b` only)

```bash
su -c "dd if=/dev/block/by-name/boot_b of=/sdcard/boot_b-stock.img bs=1M"   # backup
magiskboot unpack boot_b-stock.img && cp Image kernel && magiskboot repack boot_b-stock.img boot_b-new.img
fastboot flash boot_b boot_b-new.img
```

Never touch `init_boot`: KernelSU's `kernelsu.ko` lives in that ramdisk.

## Tested on

| Item | Result |
|---|---|
| Kernel boot | OK |
| Wi-Fi / display / Bluetooth / audio / camera | OK (all vendor modules load) |
| KernelSU root | Preserved (LKM in `init_boot`) |
| Droidspaces requirement check | All required features pass |
| Debian 13 container | systemd as PID 1, `is-system-running = running` |
| Container networking | NAT + DNS working, apt works through a local mirror |
| GPU nodes | `/dev/kgsl-3d0` and `/dev/dri/renderD128` mirrored into the container |
| Turnip hardware Vulkan | Not working yet: distro Mesa lacks the Android kgsl backend; the documented Mesa-for-Android-Container build is required |

## License

Build scripts and docs: GPL-2.0, same as the kernel. Patches in `patches/` come
from the Droidspaces project under GPL-3.0.
