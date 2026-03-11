#!/usr/bin/env bash
set -euo pipefail

KERNEL_VERSION="${KERNEL_VERSION:-6.19.6}"
KERNEL_URL="${KERNEL_URL:-https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz}"

DRIVE="${DRIVE:-/dev/nvme0n1p2}"
BBLROOT="${BBLROOT:-/mnt}"
BOOT_DIR="${BOOT_DIR:-/boot}"
WORKDIR="${WORKDIR:-/nix/usr/local/src/bbl-build}"
BUILDNAME="${BUILDNAME:-}"
COPY_FIRMWARE="${COPY_FIRMWARE:-1}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}

cleanup() {
  set +e
  if mountpoint -q "$BBLROOT"; then
    umount "$BBLROOT"
  fi
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root."
  exit 1
fi

for cmd in \
  wget tar make nproc cp mkdir mount umount mountpoint blkid lsblk grep sed awk git; do
  require_cmd "$cmd"
done

if [ ! -d "$BOOT_DIR" ]; then
  echo "Boot dir not found: $BOOT_DIR"
  exit 1
fi

if ! mountpoint -q "$BOOT_DIR"; then
  echo "$BOOT_DIR is not mounted."
  exit 1
fi

if [ -z "$BUILDNAME" ]; then
  echo "BUILDNAME is empty."
  echo "Example:"
  echo "  sudo BUILDNAME=bbl_20260310_2130 DRIVE=/dev/nvme0n1p2 ./rebuild_bbl_kernel.sh"
  exit 1
fi

KERNEL_NAME="${KERNEL_NAME:-vmlinuz-${BUILDNAME}}"
SYSTEMMAP_NAME="${SYSTEMMAP_NAME:-System.map-${BUILDNAME}}"
ENTRY_NAME="${ENTRY_NAME:-${BUILDNAME}.conf}"

UUID="$(blkid -s UUID -o value "$DRIVE")"

mkdir -p "$WORKDIR" "$BBLROOT"

echo "[1/8] Mounting bbl subvolume..."
mount -o "subvol=$BUILDNAME" "$DRIVE" "$BBLROOT"

echo "[2/8] Copying AMD firmware..."
if [ "$COPY_FIRMWARE" = "1" ]; then
  cd "$WORKDIR"
  if [ ! -d linux-firmware ]; then
    git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
  fi
  mkdir -p "$BBLROOT/lib/firmware"
  rm -rf "$BBLROOT/lib/firmware/amdgpu"
  cp -a linux-firmware/amdgpu "$BBLROOT/lib/firmware/"
fi

echo "[3/8] Downloading kernel source..."
cd "$WORKDIR"
if [ ! -f "linux-${KERNEL_VERSION}.tar.xz" ]; then
  wget -O "linux-${KERNEL_VERSION}.tar.xz" "$KERNEL_URL"
fi

rm -rf "linux-${KERNEL_VERSION}"
tar -xf "linux-${KERNEL_VERSION}.tar.xz"
cd "linux-${KERNEL_VERSION}"

echo "[4/8] Preparing kernel config..."
make defconfig

cat >> .config <<EOF
CONFIG_BLK_DEV=y
CONFIG_PCI=y
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_BLK=y
CONFIG_BTRFS_FS=y
CONFIG_PARTITION_ADVANCED=y
CONFIG_MSDOS_PARTITION=y
CONFIG_EFI_PARTITION=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_UNIX=y
CONFIG_INET=y
CONFIG_PACKET=y
CONFIG_UNIX98_PTYS=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y

CONFIG_EFI=y
CONFIG_SYSFB_SIMPLEFB=y
CONFIG_DRM=y
CONFIG_DRM_SIMPLEDRM=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_PANIC=y

CONFIG_PCI_MSI=y
CONFIG_IOMMU_SUPPORT=y
CONFIG_IRQ_REMAP=y
CONFIG_X86_X2APIC=y

CONFIG_FB=y
CONFIG_FB_EFI=y
CONFIG_SYSFB=y
CONFIG_DRM_AMDGPU=y
CONFIG_FW_LOADER=y

CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_EXTRA_FIRMWARE="amdgpu/psp_14_0_3_sos.bin amdgpu/psp_14_0_3_ta.bin amdgpu/smu_14_0_3.bin amdgpu/dcn_4_0_1_dmcub.bin amdgpu/gc_12_0_1_pfp.bin amdgpu/gc_12_0_1_me.bin amdgpu/gc_12_0_1_mec.bin amdgpu/gc_12_0_1_rlc.bin amdgpu/gc_12_0_1_toc.bin amdgpu/gc_12_0_1_imu.bin amdgpu/gc_12_0_1_imu_kicker.bin amdgpu/gc_12_0_1_rlc_kicker.bin amdgpu/gc_12_0_1_mes.bin amdgpu/gc_12_0_1_mes1.bin amdgpu/gc_12_0_1_uni_mes.bin amdgpu/sdma_7_0_1.bin amdgpu/vcn_5_0_0.bin i915/adls_dmc_ver2_01.bin i915/tgl_guc_70.bin"
CONFIG_EXTRA_FIRMWARE_DIR="$WORKDIR/linux-firmware"
EOF

if echo "$DRIVE" | grep -q nvme; then
  cat >> .config <<'EOF'
CONFIG_BLK_DEV_NVME=y
EOF
fi

make olddefconfig

echo "[5/8] Building kernel..."
make -j"$(nproc)"

echo "[6/8] Installing kernel modules into bbl..."
make INSTALL_MOD_PATH="$BBLROOT" modules_install

echo "[7/8] Copying kernel to boot..."
cp -iv arch/x86/boot/bzImage "$BOOT_DIR/$KERNEL_NAME"
cp -iv System.map "$BOOT_DIR/$SYSTEMMAP_NAME"

echo "[8/8] Updating boot entry..."
mkdir -p "$BOOT_DIR/loader/entries"
cat > "$BOOT_DIR/loader/entries/$ENTRY_NAME" <<EOF
title   BBL $BUILDNAME
linux   /$KERNEL_NAME
options root=UUID=$UUID rootflags=subvol=$BUILDNAME rw rootfstype=btrfs rootwait net.ifnames=0 biosdevname=0 init=/init console=tty1 loglevel=7 amdgpu.dc=1
EOF

sync

echo
echo "Done."
echo
echo "Installed kernel: $BOOT_DIR/$KERNEL_NAME"
echo "Installed System.map: $BOOT_DIR/$SYSTEMMAP_NAME"
echo "Boot entry: $BOOT_DIR/loader/entries/$ENTRY_NAME"
echo "Root device: $DRIVE"
echo "Root UUID: $UUID"
echo "Subvolume: $BUILDNAME"
echo
echo "Reboot and choose BBL."
