#!/bin/bash
#
# Build a Droidspaces-capable GKI kernel for the REDMAGIC 8S Pro+ (NX729J).
#
# Strategy: use the *same* upstream GKI tree and the *same* config the phone's
# stock kernel was built from, add only the options Droidspaces needs, and keep
# the ABI intact with the official Droidspaces kABI patch. Nothing is ported and
# nothing is patched device-specifically, which is why every vendor module keeps
# loading with identical CRCs.
#
# Requirements: Linux x86_64 or aarch64, ~30 GB free, clang/LLD (14 works),
# bc bison flex libssl-dev libelf-dev cpio lz4 zstd dwarves python3 kmod.
#
set -e

# ---------------------------------------------------------------- parameters
WORK=${WORK:-$HOME/nx729j-kernel}
ACK_COMMIT=b1f32b310a30e5a1d9a433eb8386497beaae1c72     # same commit the stock kernel runs
REPO_DIR=$(cd "$(dirname "$0")" && pwd)
STOCK_CONFIG="$REPO_DIR/nx729j-RedMagicOS10.0.12.config"
PATCH="$REPO_DIR/patches/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch"
JOBS=${JOBS:-$(nproc)}

mkdir -p "$WORK"
cd "$WORK"

# ------------------------------------------------------------------- source
if [ ! -d "$WORK/ack" ]; then
  echo "=== fetching ACK $ACK_COMMIT ==="
  mkdir -p "$WORK/ack"
  curl -L -o ack.tar.gz \
    "https://android.googlesource.com/kernel/common/+archive/$ACK_COMMIT.tar.gz"
  tar xzf ack.tar.gz -C "$WORK/ack"
fi
cd "$WORK/ack"

# ------------------------------------------------- stock config as the base
echo "=== base config = the phone's stock config ==="
cp "$STOCK_CONFIG" .config

# ------------------------------------------------------ ABI padding patches
echo "=== applying the Droidspaces kABI patch ==="
patch -p1 < "$PATCH"

# --------------------------------------------------------- enable the options
echo "=== enabling Droidspaces options ==="
scripts/config --file .config \
  --enable SYSVIPC --enable POSIX_MQUEUE --enable IPC_NS --enable PID_NS \
  --enable DEVTMPFS --enable USER_NS --enable MACVLAN \
  --enable IP6_NF_NAT --enable IP6_NF_TARGET_MASQUERADE \
  --enable NETFILTER_XT_MATCH_ADDRTYPE \
  --enable TMPFS_POSIX_ACL --enable TMPFS_XATTR \
  --disable TRIM_UNUSED_KSYMS \
  --disable LOCALVERSION_AUTO \
  --set-str LOCALVERSION "-android13-8-00017-gb1f32b310a30-ab12826353"

export ARCH=arm64
export LLVM=1
make olddefconfig

# -------------------------------------------------------------------- build
# NOTE: LTO_CLANG_FULL needs ~15 GB of RAM at link time. On a small machine
# switch to ThinLTO (what Google uses for GKI) instead -- it does not change
# the ABI or any symbol CRC:
#   scripts/config --disable LTO_CLANG_FULL --enable LTO_CLANG_THIN
echo "=== building Image ==="
make -j"$JOBS" Image

echo "=== Module.symvers (for the CRC check) ==="
make -j"$JOBS" modules

echo "=== kernel release ==="
make kernelrelease

echo
echo "Image: $WORK/ack/arch/arm64/boot/Image"
echo
echo "Next steps:"
echo "  1) verify module compatibility:  MODS_DIR=<vendor .ko dir> python3 check_crc.py"
echo "  2) repack the boot image with magiskboot:"
echo "       magiskboot unpack boot_b.img && cp <Image> kernel && magiskboot repack boot_b.img boot_b-new.img"
echo "  3) flash boot_b only (never init_boot, its ramdisk holds KernelSU)"
