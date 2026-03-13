#!/usr/bin/env bash
set -euo pipefail

DATE="$(date +"%Y%m%d_%H%M")"
BUILDNAME="${BUILDNAME:-bbl_$DATE}"
BBLROOT="${BBLROOT:-/mnt}"
MOUNT_TMP="${MOUNT_TMP:-/tmp/bbl-mount}"
DRIVE="${DRIVE:-/dev/nvme0n1p2}"
USERNAME="${USERNAME:-bbl}"
HOSTNAME="${HOSTNAME:-busyboxlinux}"
BOOT_DIR="${BOOT_DIR:-/boot}"
WORKDIR="${WORKDIR:-/usr/local/src/bbl-build}"

BUSYBOX_URL="${BUSYBOX_URL:-https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox}"
BUSYBOX_SHA256="${BUSYBOX_SHA256:-6e123e7f3202a8c1e9b1f94d8941580a25135382b99e8d3e34fb858bba311348}"

KERNEL_VERSION="${KERNEL_VERSION:-6.19.6}"
KERNEL_URL="${KERNEL_URL:-https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz}"

NIX_VERSION="${NIX_VERSION:-2.34.0}"
NIX_URL="${NIX_URL:-https://releases.nixos.org/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-x86_64-linux.tar.xz}"
NIX_SHA256="${NIX_SHA256:-5676b0887f1274e62edd175b6611af49aa8170c69c16877aa9bc6cebceb19855}"

ETH_IFACE="${ETH_IFACE:-eth0}"
WIFI_IFACE="${WIFI_IFACE:-wlan0}"
WIFI_MODULE="${WIFI_MODULE:-}"
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PASSWORD="${WIFI_PASSWORD:-}"
EXTRA_KERNEL_OPTS="${EXTRA_KERNEL_OPTS:-}"

KERNEL_BASENAME="vmlinuz-${BUILDNAME}"
SYSTEMMAP_BASENAME="System.map-${BUILDNAME}"
BOOT_ENTRY_NAME="${BUILDNAME}.conf"

HOST_HOME="${HOST_HOME:-${SUDO_HOME:-${HOME:-/root}}}"
HOST_VARS_FILE="${HOST_VARS_FILE:-$HOST_HOME/bbl-vars}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

cleanup() {
  set +e
  if mountpoint -q "$BBLROOT/run"; then umount "$BBLROOT/run"; fi
  if mountpoint -q "$BBLROOT/proc"; then umount "$BBLROOT/proc"; fi
  if mountpoint -q "$BBLROOT/sys"; then umount -R "$BBLROOT/sys"; fi
  if mountpoint -q "$BBLROOT/dev"; then umount -R "$BBLROOT/dev"; fi
  if mountpoint -q "$BBLROOT"; then umount "$BBLROOT"; fi
  if mountpoint -q "$MOUNT_TMP"; then umount "$MOUNT_TMP"; fi
}
trap cleanup EXIT

append_once() {
  local file="$1"
  local line="$2"
  grep -Fqx "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root." >&2
  exit 1
fi

for cmd in \
  wget sha256sum mount umount btrfs blkid mkdir chmod chown ln cp cat sed grep awk \
  tar make gcc xz nproc install passwd chroot su ip git mountpoint find lsblk; do
  require_cmd "$cmd"
done

if [ ! -d "$BOOT_DIR" ]; then
  echo "Boot directory not found: $BOOT_DIR" >&2
  exit 1
fi

if ! mountpoint -q "$BOOT_DIR"; then
  echo "$BOOT_DIR is not mounted. Mount your EFI/boot partition first." >&2
  exit 1
fi

mkdir -p "$WORKDIR" "$BBLROOT" "$MOUNT_TMP"

echo "[1/11] Creating host variable file..."
UUID="$(blkid -s UUID -o value "$DRIVE")"
cat > "$HOST_VARS_FILE" <<EOF
export BUILDNAME="$BUILDNAME"
export BBLROOT="$BBLROOT"
export DRIVE="$DRIVE"
export UUID="$UUID"
export USERNAME="$USERNAME"
EOF

echo "[2/11] Creating btrfs subvolume..."
mount "$DRIVE" "$MOUNT_TMP"
if btrfs subvolume list "$MOUNT_TMP" | awk '{print $9}' | grep -qx "$BUILDNAME"; then
  echo "Subvolume already exists: $BUILDNAME"
else
  btrfs subvolume create "$MOUNT_TMP/$BUILDNAME"
fi
umount "$MOUNT_TMP"

echo "[3/11] Mounting target subvolume..."
mount -o "subvol=$BUILDNAME" "$DRIVE" "$BBLROOT"

echo "[4/11] Creating base system..."
mkdir -p "$BBLROOT"/{bin,etc,dev,lib,root,home,sys,run,proc,tmp,mnt,var,usr}
mkdir -p "$BBLROOT"/usr/{bin,sbin}
mkdir -p "$BBLROOT"/home/"$USERNAME"
mkdir -p "$BBLROOT"/var/{log,empty}
mkdir -p "$BBLROOT"/lib/modules
chmod 1777 "$BBLROOT/tmp"
chmod 0555 "$BBLROOT/var/empty"

cd "$WORKDIR"
wget -O busybox "$BUSYBOX_URL"
echo "${BUSYBOX_SHA256}  busybox" | sha256sum -c
cp busybox "$BBLROOT/bin/busybox"
chmod +x "$BBLROOT/bin/busybox"

cd "$BBLROOT/bin"
for prog in $(./busybox --list); do
  ln -sf busybox "$prog"
done
cd "$BBLROOT"

chmod u+s "$BBLROOT/bin/busybox"

cat > "$BBLROOT/etc/inittab" <<'EOF'
::sysinit:/bin/mount -a
::sysinit:/bin/hostname -F /etc/hostname
::sysinit:/bin/mkdir -p /dev/pts
::sysinit:/bin/ln -sf pts/ptmx /dev/ptmx
::sysinit:/bin/mount -t devpts -o gid=5,mode=620,ptmxmode=666 devpts /dev/pts
::sysinit:/bin/mkdir -p /dev/shm
::sysinit:/bin/mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs /dev/shm
::sysinit:/bin/ip link set lo up
::ctrlaltdel:/bin/reboot
::shutdown:/bin/echo SHUTTING DOWN
::shutdown:/bin/umount -a -r
tty1::respawn:/bin/getty 38400 tty1
tty2::askfirst:/bin/getty 38400 tty2
tty3::askfirst:/bin/getty 38400 tty3
tty4::askfirst:/bin/getty 38400 tty4
EOF

cat > "$BBLROOT/etc/fstab" <<EOF
UUID=$UUID /              btrfs      rw,relatime,subvol=/$BUILDNAME 0 1
proc      /proc           proc       nosuid,noexec,nodev            0 0
sysfs     /sys            sysfs      nosuid,noexec,nodev            0 0
devpts    /dev/pts        devpts     gid=5,mode=620                 0 0
tmpfs     /run            tmpfs      defaults                       0 0
devtmpfs  /dev            devtmpfs   mode=0755,nosuid               0 0
tmpfs     /dev/shm        tmpfs      nosuid,nodev                   0 0
efivarfs  /sys/firmware/efi/efivars  efivarfs  defaults             0 0
EOF

printf '%s\n' "$HOSTNAME" > "$BBLROOT/etc/hostname"

cat > "$BBLROOT/etc/group" <<EOF
root:x:0:
tty:x:5:$USERNAME
wheel:x:97:$USERNAME
$USERNAME:x:1000:
EOF

cat > "$BBLROOT/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/sh
$USERNAME:x:1000:1000:Linux User,,,:/home/$USERNAME:/bin/sh
EOF

cat > "$BBLROOT/etc/shadow" <<EOF
root:!:20000::::::
$USERNAME:!:20000::::::
EOF
chmod 600 "$BBLROOT/etc/shadow"

cat > "$BBLROOT/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME
EOF

cat > "$BBLROOT/etc/bbl-vars" <<EOF
export BUILDNAME="$BUILDNAME"
export DRIVE="$DRIVE"
export UUID="$UUID"
export USERNAME="$USERNAME"
EOF

cat > "$BBLROOT/etc/profile" <<'EOF'
export PATH="/bin:/usr/bin:/usr/sbin:$PATH"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
[ -f /etc/bbl-vars ] && . /etc/bbl-vars
EOF

cat > "$BBLROOT/home/$USERNAME/.profile" <<'EOF'
export PS1='\u@\h:\w\\$ '
export PATH="$HOME/bin:/bin:/usr/bin:/usr/sbin:$PATH"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
EOF

echo "[5/11] Preparing firmware and building kernel..."
mkdir -p "$BBLROOT/lib/firmware"
if [ ! -d "$BBLROOT/lib/linux-firmware" ]; then
  git clone --depth=1 \
    https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git \
    "$BBLROOT/lib/linux-firmware"
fi
(
  cd "$BBLROOT/lib/linux-firmware"
  ./copy-firmware.sh "$BBLROOT/lib/firmware"
)

cd "$WORKDIR"
wget -O "linux-${KERNEL_VERSION}.tar.xz" "$KERNEL_URL"
rm -rf "linux-${KERNEL_VERSION}"
tar -xf "linux-${KERNEL_VERSION}.tar.xz"
cd "linux-${KERNEL_VERSION}"

make defconfig

cat >> .config <<'EOF'
CONFIG_BLK_DEV=y
CONFIG_PCI=y
CONFIG_PARTITION_ADVANCED=y
CONFIG_MSDOS_PARTITION=y
CONFIG_EFI=y
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
CONFIG_FW_LOADER=y
EOF

cat >> .config <<'EOF'
CONFIG_BTRFS_FS=y
CONFIG_BLK_DEV_NVME=y
CONFIG_SYSFB=y
CONFIG_SYSFB_SIMPLEFB=y
CONFIG_FB=y
CONFIG_FB_EFI=y
CONFIG_DRM=y
CONFIG_DRM_SIMPLEDRM=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_PANIC=y
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_DRM_AMDGPU=y
CONFIG_SND_TIMER=y
CONFIG_SND_PCM=y
CONFIG_SND_SEQ_DEVICE=y
CONFIG_SND_JACK=y
CONFIG_SND_HRTIMER=y
CONFIG_SND_HDA=y
CONFIG_SND_HDA_INTEL=y
CONFIG_SND_HDA_CODEC_HDMI=y
CONFIG_SND_HDA_CODEC_REALTEK=y
CONFIG_SND_HDA_GENERIC=y
EOF

cat >> .config <<'EOF'
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y
EOF

cat >> .config <<EOF
CONFIG_EXTRA_FIRMWARE="amdgpu/psp_14_0_3_sos.bin amdgpu/psp_14_0_3_ta.bin amdgpu/smu_14_0_3.bin amdgpu/dcn_4_0_1_dmcub.bin amdgpu/gc_12_0_1_pfp.bin amdgpu/gc_12_0_1_me.bin amdgpu/gc_12_0_1_mec.bin amdgpu/gc_12_0_1_rlc.bin amdgpu/gc_12_0_1_toc.bin amdgpu/gc_12_0_1_imu.bin amdgpu/gc_12_0_1_imu_kicker.bin amdgpu/gc_12_0_1_rlc_kicker.bin amdgpu/gc_12_0_1_mes.bin amdgpu/gc_12_0_1_mes1.bin amdgpu/gc_12_0_1_uni_mes.bin amdgpu/sdma_7_0_1.bin amdgpu/vcn_5_0_0.bin i915/adls_dmc_ver2_01.bin i915/tgl_guc_70.bin"
CONFIG_EXTRA_FIRMWARE_DIR="$BBLROOT/lib/linux-firmware"
EOF

make olddefconfig
make -j"$(nproc)"
make INSTALL_MOD_PATH="$BBLROOT" modules_install

cp -iv arch/x86/boot/bzImage "$BOOT_DIR/$KERNEL_BASENAME"
cp -iv System.map "$BOOT_DIR/$SYSTEMMAP_BASENAME"

mkdir -p "$BOOT_DIR/loader/entries"
cat > "$BOOT_DIR/loader/entries/$BOOT_ENTRY_NAME" <<EOF
title   BBL $BUILDNAME
linux   /$KERNEL_BASENAME
options root=$DRIVE rootflags=subvol=$BUILDNAME rw rootfstype=btrfs rootwait net.ifnames=0 biosdevname=0 console=tty1 loglevel=7 $EXTRA_KERNEL_OPTS
EOF

echo "[6/11] Preparing chroot..."
mount --rbind /dev "$BBLROOT/dev"
mount --make-rslave "$BBLROOT/dev"
mount -t proc /proc "$BBLROOT/proc"
mount --rbind /sys "$BBLROOT/sys"
mount --make-rslave "$BBLROOT/sys"
mount --bind /run "$BBLROOT/run"
cp /etc/resolv.conf "$BBLROOT/etc/"

mkdir -p "$BBLROOT/etc/ssl"
cp -a /etc/ssl/certs "$BBLROOT/etc/ssl/"

echo "[7/11] Downloading and verifying Nix..."
cd "$WORKDIR"
wget -O "nix-${NIX_VERSION}-x86_64-linux.tar.xz" "$NIX_URL"
echo "${NIX_SHA256}  nix-${NIX_VERSION}-x86_64-linux.tar.xz" | sha256sum -c
cp "nix-${NIX_VERSION}-x86_64-linux.tar.xz" "$BBLROOT/home/$USERNAME/"
chown 1000:1000 "$BBLROOT/home/$USERNAME/nix-${NIX_VERSION}-x86_64-linux.tar.xz"

echo "[8/11] Creating inside-chroot installer..."
cat > "$BBLROOT/root/install-inside-chroot.sh" <<'EOF'
#!/bin/sh
set -eu

USERNAME="__USERNAME__"
ETH_IFACE="__ETH_IFACE__"
WIFI_IFACE="__WIFI_IFACE__"
WIFI_MODULE="__WIFI_MODULE__"
NIX_VERSION="__NIX_VERSION__"
WIFI_SSID="__WIFI_SSID__"
WIFI_PASSWORD="__WIFI_PASSWORD__"

. /etc/profile

echo "Set root password:"
passwd
echo "Set user password:"
passwd "$USERNAME"

chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"

mkdir -m 0755 /nix
chown "$USERNAME:$USERNAME" /nix

mkdir -p /usr/share/udhcpc
cat > /usr/share/udhcpc/default.script <<'EOS'
#!/bin/sh
[ -z "$1" ] && exit 1
case "$1" in
  deconfig)
    ip addr flush dev "$interface"
    ip link set "$interface" up
    ;;
  bound|renew)
    ip addr flush dev "$interface"
    ip addr add "$ip/${subnet:-24}" dev "$interface"
    ip link set "$interface" up
    ip route del default 2>/dev/null || true
    for r in $router; do
      ip route add default via "$r" dev "$interface"
      break
    done
    : > /etc/resolv.conf
    for d in $dns; do
      echo "nameserver $d" >> /etc/resolv.conf
    done
    ;;
esac
exit 0
EOS
chmod +x /usr/share/udhcpc/default.script

append_once() {
  file="$1"
  line="$2"
  grep -Fqx "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

append_once /etc/inittab "::sysinit:/bin/ip link set $ETH_IFACE up"
append_once /etc/inittab "::sysinit:/bin/udhcpc -i $ETH_IFACE"

su "$USERNAME" -c "
set -eu
unset TMPDIR
export TMPDIR=/tmp
cd ~
tar -xf nix-${NIX_VERSION}-x86_64-linux.tar.xz
cd nix-${NIX_VERSION}-x86_64-linux
sed -i 's/cp -RP --preserve=ownership,timestamps /cp -RPp /' install
./install --no-daemon
. \$HOME/.nix-profile/etc/profile.d/nix.sh
cat <<'EOP' >> \$HOME/.profile
export PATH=\"\$HOME/.nix-profile/bin:/bin:/usr/bin:/usr/sbin:\$PATH\"
[ -f \"\$HOME/.nix-profile/etc/profile.d/nix.sh\" ] && . \"\$HOME/.nix-profile/etc/profile.d/nix.sh\"
EOP
nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
nix-channel --update
nix-env -iA \
  nixpkgs.eudev \
  nixpkgs.dbus \
  nixpkgs.seatd \
  nixpkgs.sway \
  nixpkgs.swaybg \
  nixpkgs.swayidle \
  nixpkgs.swaylock \
  nixpkgs.foot \
  nixpkgs.wmenu \
  nixpkgs.grim \
  nixpkgs.mesa \
  nixpkgs.fontconfig \
  nixpkgs.dejavu_fonts \
  nixpkgs.terminus_font \
  nixpkgs.libinput \
  nixpkgs.libwacom \
  nixpkgs.xkeyboard_config \
  nixpkgs.shared-mime-info \
  nixpkgs.wpa_supplicant \
  nixpkgs.iw
"

cat > /usr/sbin/start-udev.sh <<EOS
#!/bin/sh
set -eu

USER_HOME="/home/$USERNAME"
export PATH="\$USER_HOME/.nix-profile/bin:/bin:/usr/bin:/usr/sbin:\$PATH"
UDEVADM="\$USER_HOME/.nix-profile/bin/udevadm"
UDEVD="\$USER_HOME/.nix-profile/bin/udevd"

if [ ! -x "\$UDEVADM" ] || [ ! -x "\$UDEVD" ]; then
    exit 0
fi

EUDEV_PREFIX="\$(cd "\$(dirname "\$(readlink -f "\$UDEVADM")")/.." && pwd)"

mkdir -p /run/udev
mkdir -p /etc/udev/rules.d
mkdir -p /etc/udev/hwdb.d
mkdir -p /dev/input/by-path

cp "\$EUDEV_PREFIX/var/lib/udev/rules.d/50-udev-default.rules" /etc/udev/rules.d/ || true
cp "\$EUDEV_PREFIX/var/lib/udev/rules.d/60-input-id.rules" /etc/udev/rules.d/ || true
cp "\$EUDEV_PREFIX/var/lib/udev/rules.d/60-persistent-input.rules" /etc/udev/rules.d/ || true
cp "\$EUDEV_PREFIX/var/lib/udev/rules.d/70-mouse.rules" /etc/udev/rules.d/ || true
cp "\$EUDEV_PREFIX/var/lib/udev/hwdb.d/60-input-id.hwdb" /etc/udev/hwdb.d/ || true
cp "\$EUDEV_PREFIX/var/lib/udev/hwdb.d/70-mouse.hwdb" /etc/udev/hwdb.d/ || true

"\$UDEVADM" hwdb --update || true
"\$UDEVD" --daemon || true
sleep 1
"\$UDEVADM" control --reload || true
"\$UDEVADM" trigger --action=add || true
"\$UDEVADM" settle || true
EOS
chmod +x /usr/sbin/start-udev.sh
append_once /etc/inittab "::sysinit:/bin/sh /usr/sbin/start-udev.sh"

mkdir -p /etc/dbus-1
cat > /etc/dbus-1/session.conf <<'EOS'
<!DOCTYPE busconfig PUBLIC
 "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <standard_session_servicedirs />
  <policy context="default">
    <allow send_destination="*"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOS

cat > /etc/group <<EOS
root:x:0:
tty:x:5:$USERNAME
audio:x:11:$USERNAME
video:x:12:$USERNAME
input:x:24:$USERNAME
render:x:107:$USERNAME
wheel:x:97:$USERNAME
network:x:101:$USERNAME
$USERNAME:x:1000:
EOS

cat > /usr/sbin/seatd-daemon.sh <<EOS
#!/bin/sh
set -eu

SEATD_BIN="/home/$USERNAME/.nix-profile/bin/seatd"
SOCK="/run/seatd.sock"

if [ ! -x "\$SEATD_BIN" ]; then
    exit 0
fi

rm -f "\$SOCK"
exec "\$SEATD_BIN" -g video
EOS
chmod +x /usr/sbin/seatd-daemon.sh
append_once /etc/inittab "::once:/bin/sh /usr/sbin/seatd-daemon.sh"

su "$USERNAME" -c "
set -eu
mkdir -p \$HOME/.config/sway
SWAY_DEFAULT_CONF=\$(find /nix/store -path '*/etc/sway/config' | head -n 1)
if [ -n \"\$SWAY_DEFAULT_CONF\" ] && [ -f \"\$SWAY_DEFAULT_CONF\" ]; then
  cp \"\$SWAY_DEFAULT_CONF\" \$HOME/.config/sway/config
  chmod 644 \$HOME/.config/sway/config
fi
cat > \$HOME/start-sway.sh <<'EOP'
#!/bin/sh
set -eu

export PATH=\"\$HOME/.nix-profile/bin:/bin:/usr/bin:/usr/sbin:\$PATH\"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export XDG_RUNTIME_DIR=\"/tmp/xdg-runtime-\$USER\"
mkdir -p \"\$XDG_RUNTIME_DIR\"
chmod 700 \"\$XDG_RUNTIME_DIR\"
export SEATD_SOCK=/run/seatd.sock
export LIBSEAT_BACKEND=seatd
exec sway
EOP
chmod +x \$HOME/start-sway.sh
"

if [ -n "$WIFI_MODULE" ]; then
  append_once /etc/inittab "::sysinit:/bin/modprobe $WIFI_MODULE"
fi

su "$USERNAME" -c "
set -eu
cat > \$HOME/wifi-up.sh <<'EOP'
#!/bin/sh
set -eu

IFACE=\"$WIFI_IFACE\"
CONF=\"\$HOME/wpa.conf\"

if [ ! -f \"\$CONF\" ]; then
  echo \"Missing \$CONF\"
  exit 1
fi

ip link set dev \"\$IFACE\" up
rfkill unblock all || true
wpa_supplicant -B -i \"\$IFACE\" -c \"\$CONF\"
udhcpc -i \"\$IFACE\"
EOP
chmod +x \$HOME/wifi-up.sh
"

if [ -n "$WIFI_SSID" ] && [ -n "$WIFI_PASSWORD" ]; then
  su "$USERNAME" -c "wpa_passphrase \"$WIFI_SSID\" \"$WIFI_PASSWORD\" > \$HOME/wpa.conf && chmod 600 \$HOME/wpa.conf"
fi

chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
EOF

sed -i "s|__USERNAME__|$USERNAME|g" "$BBLROOT/root/install-inside-chroot.sh"
sed -i "s|__ETH_IFACE__|$ETH_IFACE|g" "$BBLROOT/root/install-inside-chroot.sh"
sed -i "s|__WIFI_IFACE__|$WIFI_IFACE|g" "$BBLROOT/root/install-inside-chroot.sh"
sed -i "s|__WIFI_MODULE__|$WIFI_MODULE|g" "$BBLROOT/root/install-inside-chroot.sh"
sed -i "s|__NIX_VERSION__|$NIX_VERSION|g" "$BBLROOT/root/install-inside-chroot.sh"
sed -i "s|__WIFI_SSID__|$WIFI_SSID|g" "$BBLROOT/root/install-inside-chroot.sh"
sed -i "s|__WIFI_PASSWORD__|$WIFI_PASSWORD|g" "$BBLROOT/root/install-inside-chroot.sh"
chmod +x "$BBLROOT/root/install-inside-chroot.sh"

echo "[9/11] Running inside-chroot installer..."
chown -R 1000:1000 "$BBLROOT/home/$USERNAME"
chroot "$BBLROOT" /bin/sh -c "/root/install-inside-chroot.sh"

echo "[10/11] Final ownership fix..."
chown -R 1000:1000 "$BBLROOT/home/$USERNAME"

echo "[11/11] Done."
echo
echo "Installed to: $DRIVE"
echo "Subvolume: $BUILDNAME"
echo "Kernel: $BOOT_DIR/$KERNEL_BASENAME"
echo "System.map: $BOOT_DIR/$SYSTEMMAP_BASENAME"
echo "Boot entry: $BOOT_DIR/loader/entries/$BOOT_ENTRY_NAME"
echo "Host vars file: $HOST_VARS_FILE"
echo
echo "After reboot:"
echo "  - log in as $USERNAME"
echo "  - ethernet should try via $ETH_IFACE + udhcpc at boot"
echo "  - for WiFi, create ~/wpa.conf if missing and run: sh ~/wifi-up.sh"
echo "  - for Wayland, run on tty1: sh ~/start-sway.sh"
