# Busybox Linux - bbl

Because sometimes everything you need is a statically built busybox.

TL;DR. Just for fun I tried to see how little was needed to boot into Linux. A kernel and a statically linked busybox are enough to get a system running. This version keeps the same basic idea, but adds Nix, eudev, seatd and a Wayland setup on top.

Remember, everything below is just a suggestion on how things can be done, adjust it to your needs.

I have added a script called `bbl_script.sh` that performs the full install shown below.

*And be careful before you type any command into the terminal. Try to learn what each command does before running it.*

![Screenshot of bbl](https://github.com/damianoognissanti/bbl/blob/main/bbl.png?raw=true)

## Chapter 1 Create partition and set some variables

In this example I use btrfs since it is easy to create and delete subvolumes with it, but you can certainly use ext4 or whatever file system you want.

Create a unique name for the installation. I usually pick some prefix + date, like so:

```sh
DATE=$(date +"%Y%m%d_%H%M")
BUILDNAME="bbl_$DATE"
````

Set the bbl root directory. Remember, if you take a break and close the terminal, or if you switch user, the variables are gone. That means a command using an empty variable can suddenly point to the wrong place.

```sh
BBLROOT="/mnt"
```

Store the drive name and UUID in variables. You get these values by typing `blkid` in a terminal and copying the values from the correct line.

```sh
DRIVE="/dev/nvme0n1p2"
UUID="abc1234d-a123-1234-abc1-12ab34c56789"
```

Select a user name:

```sh
USERNAME="bbl"
```

Mount your drive in a folder called `Mount` and create a `btrfs` subvolume. Unmount the drive and mount the subvolume in the `$BBLROOT` folder.

```sh
mkdir -p Mount
mount "$DRIVE" Mount
btrfs subvolume create "Mount/$BUILDNAME"
umount Mount
mount -o "subvol=$BUILDNAME" "$DRIVE" "$BBLROOT"
```

## Chapter 2 Create the base system

Populate the subvolume with the folders needed for the install:

```sh
mkdir -p "$BBLROOT"/{bin,etc,dev,lib,root,home,sys,run,proc,tmp,mnt,var,usr}
mkdir -p "$BBLROOT"/usr/{bin,sbin,share/udhcpc}
mkdir -p "$BBLROOT"/home/"$USERNAME"
mkdir -p "$BBLROOT"/var/{log,empty}
mkdir -p "$BBLROOT"/lib/modules
mkdir -p "$BBLROOT"/etc/{dbus-1,udev/rules.d,udev/hwdb.d,nix}
chmod 1777 "$BBLROOT/tmp"
chmod 0555 "$BBLROOT/var/empty"
```

Now you need a statically linked busybox binary.

In this setup I download the prebuilt static binary and verify it before using it.

```sh
BUSYBOXURL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
BUSYBOXSHASUM="6e123e7f3202a8c1e9b1f94d8941580a25135382b99e8d3e34fb858bba311348"

pushd "$BBLROOT/bin"
wget "$BUSYBOXURL" -O busybox
echo "$BUSYBOXSHASUM  busybox" | sha256sum -c
chmod +x busybox
```

Create a symbolic link for each busybox program:

```sh
for prog in $(./busybox --list); do ln -s busybox "$prog"; done
```

Make `su` available for the user account:

```sh
chmod u+s "$BBLROOT/bin/busybox"
```

Now we need something that runs after the kernel, so let us create `/etc/inittab`.

This file will:

* give you terminals with login
* create and mount the basic runtime directories
* mount everything in `fstab`
* set the hostname
* bring up `lo`
* try to bring up `eth0` with `udhcpc`
* start eudev later on if it is installed
* start seatd later on if it is installed
* set commands for ctrl-alt-del and shutdown

```sh
cat <<'EOF' > "$BBLROOT/etc/inittab"
::sysinit:/bin/mount -a
::sysinit:/bin/hostname -F /etc/hostname
::sysinit:/bin/mkdir -p /dev/pts
::sysinit:/bin/ln -sf pts/ptmx /dev/ptmx
::sysinit:/bin/mount -t devpts -o gid=5,mode=620,ptmxmode=666 devpts /dev/pts
::sysinit:/bin/mkdir -p /dev/shm
::sysinit:/bin/mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs /dev/shm
::sysinit:/bin/ip link set lo up
::sysinit:/bin/ip link set eth0 up
::sysinit:/bin/udhcpc -i eth0
::sysinit:/bin/sh /usr/sbin/start-udev.sh
::once:/bin/sh /usr/sbin/seatd-daemon.sh
::ctrlaltdel:/bin/reboot
::shutdown:/bin/echo SHUTTING DOWN
::shutdown:/bin/umount -a -r
tty1::respawn:/bin/getty 38400 tty1
tty2::askfirst:/bin/getty 38400 tty2
tty3::askfirst:/bin/getty 38400 tty3
tty4::askfirst:/bin/getty 38400 tty4
EOF
```

Create an `fstab` file. The first line mounts the bbl partition. The others are for the important mount points.

```sh
cat <<EOF > "$BBLROOT/etc/fstab"
UUID=$UUID /              btrfs      rw,relatime,subvol=/$BUILDNAME 0 1
proc      /proc           proc       nosuid,noexec,nodev            0 0
sysfs     /sys            sysfs      nosuid,noexec,nodev            0 0
devpts    /dev/pts        devpts     gid=5,mode=620                 0 0
tmpfs     /run            tmpfs      defaults                       0 0
devtmpfs  /dev            devtmpfs   mode=0755,nosuid               0 0
tmpfs     /dev/shm        tmpfs      nosuid,nodev                   0 0
efivarfs  /sys/firmware/efi/efivars  efivarfs  defaults             0 0
EOF
```

Create the hostname file:

```sh
cat <<'EOF' > "$BBLROOT/etc/hostname"
busyboxlinux
EOF
```

Create the groups:

```sh
cat <<EOF > "$BBLROOT/etc/group"
root:x:0:
tty:x:5:$USERNAME
audio:x:11:$USERNAME
video:x:12:$USERNAME
input:x:24:$USERNAME
render:x:107:$USERNAME
wheel:x:97:$USERNAME
network:x:101:$USERNAME
$USERNAME:x:1000:
EOF
```

Create the passwd file:

```sh
cat <<EOF > "$BBLROOT/etc/passwd"
root:x:0:0:root:/root:/bin/sh
$USERNAME:x:1000:1000:Linux User,,,:/home/$USERNAME:/bin/sh
EOF
```

Create a locked shadow file for now. You will set real passwords in the chroot later.

```sh
cat <<EOF > "$BBLROOT/etc/shadow"
root:!:20000::::::
$USERNAME:!:20000::::::
EOF

chmod 600 "$BBLROOT/etc/shadow"
```

Create a hosts file:

```sh
cat <<'EOF' > "$BBLROOT/etc/hosts"
127.0.0.1 localhost
127.0.1.1 busyboxlinux
EOF
```

Create a small `nsswitch.conf`:

```sh
cat <<'EOF' > "$BBLROOT/etc/nsswitch.conf"
passwd: files
group: files
shadow: files
hosts: files dns
networks: files dns
services: files
protocols: files
ethers: files
rpc: files
EOF
```

Create a small D-Bus session config:

```sh
cat <<'EOF' > "$BBLROOT/etc/dbus-1/session.conf"
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
EOF
```

Create profile files:

```sh
cat <<'EOF' > "$BBLROOT/etc/profile"
export PATH="/bin:/usr/bin:/usr/sbin:$PATH"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
EOF

cat <<EOF > "$BBLROOT/home/$USERNAME/.profile"
export PS1='\u@\h:\w\\$ '
export PATH="\$HOME/.nix-profile/bin:/bin:/usr/bin:/usr/sbin:\$PATH"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
[ -f "\$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "\$HOME/.nix-profile/etc/profile.d/nix.sh"
EOF
```

Create the default `udhcpc` script so that DHCP works:

```sh
cat <<'EOF' > "$BBLROOT/usr/share/udhcpc/default.script"
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
EOF

chmod +x "$BBLROOT/usr/share/udhcpc/default.script"
```

Create a helper that starts eudev when it is installed later via Nix:

```sh
cat <<EOF > "$BBLROOT/usr/sbin/start-udev.sh"
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
EOF

chmod +x "$BBLROOT/usr/sbin/start-udev.sh"
```

Create a helper that starts `seatd` if it is installed later:

```sh
cat <<EOF > "$BBLROOT/usr/sbin/seatd-daemon.sh"
#!/bin/sh
set -eu

SEATD_BIN="/home/$USERNAME/.nix-profile/bin/seatd"
SOCK="/run/seatd.sock"

if [ ! -x "\$SEATD_BIN" ]; then
    exit 0
fi

rm -f "\$SOCK"
exec "\$SEATD_BIN" -g video
EOF

chmod +x "$BBLROOT/usr/sbin/seatd-daemon.sh"
```

## Chapter 3 Kernel

Now you must compile and install your own kernel.

Do this on the host, not inside the chroot.

Before you run the script, make sure your host has the tools needed to compile a kernel.

Download the source, extract it and move into the folder:

```sh
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.19.6.tar.xz
tar -xf linux-6.19.6.tar.xz
cd linux-6.19.6
```

Create a default config first:

```sh
make defconfig
```

Then append the things you know you need. This is the base used in the script:

```sh
cat >> .config <<'EOF'
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
EOF
```

If you have an NVMe SSD, also add:

```sh
cat >> .config <<'EOF'
CONFIG_BLK_DEV_NVME=y
EOF
```

### A note about AMD graphics

If you want AMD graphics to work on a very small setup like this, it may not be enough to just enable `CONFIG_DRM_AMDGPU=y`.

In my case I also had to make sure `linux-firmware` was present before compiling the kernel, and build the needed firmware into the kernel.

That means the order matters. First get `linux-firmware`, then point the kernel config at it.

For example:

```sh
git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
```

Then add something like this to `.config`:

```sh
cat >> .config <<EOF
CONFIG_EXTRA_FIRMWARE="amdgpu/psp_14_0_3_sos.bin amdgpu/psp_14_0_3_ta.bin amdgpu/smu_14_0_3.bin amdgpu/dcn_4_0_1_dmcub.bin amdgpu/gc_12_0_1_pfp.bin amdgpu/gc_12_0_1_me.bin amdgpu/gc_12_0_1_mec.bin amdgpu/gc_12_0_1_rlc.bin amdgpu/gc_12_0_1_toc.bin amdgpu/gc_12_0_1_imu.bin amdgpu/gc_12_0_1_imu_kicker.bin amdgpu/gc_12_0_1_rlc_kicker.bin amdgpu/gc_12_0_1_mes.bin amdgpu/gc_12_0_1_mes1.bin amdgpu/gc_12_0_1_uni_mes.bin amdgpu/sdma_7_0_1.bin amdgpu/vcn_5_0_0.bin i915/adls_dmc_ver2_01.bin i915/tgl_guc_70.bin"
CONFIG_EXTRA_FIRMWARE_DIR="/path/to/linux-firmware"
EOF
```

This firmware list is just an example from my own setup. You may need a different list depending on your hardware.

Now refresh the config:

```sh
make olddefconfig
```

Then compile:

```sh
make -j"$(nproc)"
```

Install modules into the new system:

```sh
make INSTALL_MOD_PATH="$BBLROOT" modules_install
```

Copy the compiled kernel:

```sh
cp -iv arch/x86/boot/bzImage /boot/vmlinuz-$BUILDNAME
cp -iv System.map /boot/System.map-$BUILDNAME
```

Each bbl install gets its own kernel and its own boot entry. That means multiple bbl installs can live side by side without sharing the same kernel.

Create an entry in your bootloader. Here is an example for `systemd-boot`:

```sh
cat <<EOF > /boot/loader/entries/$BUILDNAME.conf
title   BBL $BUILDNAME
linux   /vmlinuz-$BUILDNAME
options root=UUID=$UUID rootflags=subvol=$BUILDNAME rw rootfstype=btrfs rootwait net.ifnames=0 biosdevname=0 init=/init console=tty1 loglevel=7 amdgpu.dc=1
EOF
```

With this you should be able to reboot into your system.

## Chapter 4 Firmware

You will probably need firmware for wifi, sound and graphics. The easiest way to solve this is to clone `linux-firmware` and copy it into `/lib/firmware`.

```sh
git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
mkdir -p "$BBLROOT/lib/firmware"
cd linux-firmware
./copy-firmware.sh "$BBLROOT/lib/firmware"
```

This is important for wifi, and also important if you use AMD graphics.

If you build firmware into the kernel as shown above, `linux-firmware` must already exist before you compile the kernel.

## Chapter 5 Nix package manager

Now that the base system boots, you can install Nix on top.

Since this is a small busybox system without systemd, the easiest route is a single-user install.

Chroot into the installation:

```sh
mount -o "subvol=$BUILDNAME" "$DRIVE" "$BBLROOT"
mount --rbind /dev "$BBLROOT/dev"
mount --make-rslave "$BBLROOT/dev"
mount -t proc /proc "$BBLROOT/proc"
mount --rbind /sys "$BBLROOT/sys"
mount --make-rslave "$BBLROOT/sys"
mount --bind /run "$BBLROOT/run"
cp /etc/resolv.conf "$BBLROOT/etc/"
chroot "$BBLROOT" /bin/sh
. /etc/profile
```

Set the user variable again, since it does not exist in the chroot:

```sh
USERNAME="bbl"
```

Make sure the user owns the home folder:

```sh
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
```

Create `/nix` manually and give it to the user:

```sh
mkdir -m 0755 /nix
chown "$USERNAME:$USERNAME" /nix
```

Switch to the user account:

```sh
su "$USERNAME"
cd ~
```

Download Nix:

```sh
VERSION="2.34.0"
NIXURL="https://releases.nixos.org/nix/nix-$VERSION/nix-$VERSION-x86_64-linux.tar.xz"
NIXSHASUM="5676b0887f1274e62edd175b6611af49aa8170c69c16877aa9bc6cebceb19855"

wget "$NIXURL"
```

Verify the tarball:

```sh
echo "$NIXSHASUM  nix-$VERSION-x86_64-linux.tar.xz" | sha256sum -c
```

If the checksum is OK, extract and install it:

```sh
tar -xf "nix-$VERSION-x86_64-linux.tar.xz"
cd "nix-$VERSION-x86_64-linux"
sed -i 's/cp -RP --preserve=ownership,timestamps /cp -RPp /' install
./install --no-daemon
```

Load the Nix profile:

```sh
. "$HOME/.nix-profile/etc/profile.d/nix.sh"
```

Add the unstable channel and update:

```sh
nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
nix-channel --update
```

## Chapter 6 Wayland with eudev and seatd (optional)

Here is one simple Wayland setup using Sway.

Install the packages you need:

```sh
nix-env -iA \
  nixpkgs.seatd \
  nixpkgs.sway \
  nixpkgs.swaybg \
  nixpkgs.swayidle \
  nixpkgs.swaylock \
  nixpkgs.foot \
  nixpkgs.wmenu \
  nixpkgs.grim \
  nixpkgs.dbus \
  nixpkgs.mesa \
  nixpkgs.eudev \
  nixpkgs.fontconfig \
  nixpkgs.dejavu_fonts \
  nixpkgs.terminus_font \
  nixpkgs.libinput \
  nixpkgs.libwacom \
  nixpkgs.xkeyboard_config \
  nixpkgs.shared-mime-info \
  nixpkgs.wpa_supplicant \
  nixpkgs.iw \
  nixpkgs.rfkill
```

The startup scripts created earlier will now begin to do useful work at boot:

* `start-udev.sh` will start `udevd`, load the rules, load the hwdb and trigger devices
* `seatd-daemon.sh` will start `seatd`

This install copies Sway's original config from the Nix store into the user's home directory, so you start with a proper default config instead of a tiny hand-written one.

If you need to do it manually:

```sh
mkdir -p ~/.config/sway
cp "$(find /nix/store -path '*/etc/sway/config' | head -n 1)" ~/.config/sway/config
```

Create a helper to start Sway:

```sh
cat <<'EOF' > ~/start-sway.sh
#!/bin/sh
set -eu

export PATH="$HOME/.nix-profile/bin:/bin:/usr/bin:/usr/sbin:$PATH"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export XDG_RUNTIME_DIR="/tmp/xdg-runtime-$USER"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

export SEATD_SOCK=/run/seatd.sock
export LIBSEAT_BACKEND=seatd

exec sway
EOF

chmod +x ~/start-sway.sh
```

Reboot, log in on `tty1`, and run:

```sh
sh ~/start-sway.sh
```

## Chapter 7 Ethernet or WiFi

### Ethernet

For ethernet, write:

```sh
ip link
```

to find the name of your connection.

If you used `net.ifnames=0 biosdevname=0` in the bootloader, it will often be called `eth0`. Otherwise it may be something like `enp3s0`.

Bring the interface up:

```sh
ip link set dev eth0 up
```

Request an IP address:

```sh
udhcpc -i eth0
```

If your interface is not called `eth0`, replace it with the correct name.

### WiFi

For WiFi you usually need three things:

1. the correct kernel driver
2. the correct firmware in `/lib/firmware`
3. `wpa_supplicant`

First, check that the wifi interface exists:

```sh
ip link
```

If it does not, load the kernel module for your card. Example:

```sh
modprobe iwlwifi
```

or:

```sh
modprobe mwifiex_pcie
```

If the card is blocked, unblock it:

```sh
rfkill unblock all
```

Create a WiFi config:

```sh
wpa_passphrase YOUR_SSID YOUR_PASSWORD > wpa.conf
chmod 600 wpa.conf
```

Bring the interface up:

```sh
ip link set dev wlan0 up
```

Start `wpa_supplicant`:

```sh
wpa_supplicant -B -i wlan0 -c wpa.conf
```

Then request an IP address:

```sh
udhcpc -i wlan0
```

If your wifi interface is not called `wlan0`, substitute the correct name.

### If WiFi still does not work

The usual causes are:

* the kernel driver is missing
* the firmware is missing
* the radio is blocked
* you used the wrong interface name

These commands are often enough to figure out what is wrong:

```sh
dmesg | grep -i firmware
dmesg | grep -i wifi
dmesg | grep -i iwlwifi
dmesg | grep -i mwifiex
ip link
rfkill list
```

If you figure out that a certain module must always be loaded, you can add it to `/etc/inittab`. Example:

```sh
::sysinit:/bin/modprobe iwlwifi
```

or:

```sh
::sysinit:/bin/modprobe mwifiex_pcie
```

## About

A minimalistic busybox linux install, updated to work nicely with `btrfs`, Nix, eudev, seatd and a small Wayland setup.
