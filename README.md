# Busybox Linux - bbl

Because sometimes everything you need is a statically built busybox.

TL;DR. Just for fun I tried to see how little was needed to boot into Linux. It turns out that a kernel and a statically linked busybox are enough to get a system running.

This guide begins with that very small base system: a kernel, a statically linked busybox, a few config files, and just enough structure to boot and log in (Chapters 1-3). After that, the system is expanded in layers: firmware, networking, Nix, eudev, seatd, Wayland, WiFi (Chapters 4-9).

So the point is not that you need everything below. The point is that once you have seen how little is actually needed to boot Linux, it becomes much easier to understand the larger pieces you add on top.

Remember, everything below is just a suggestion on how things can be done. Adjust it to your needs.

I have added a script called `bbl_script.sh` that performs the full install shown below.

*And be careful before you type any command into the terminal. Try to learn what each command does before running it.*

![Screenshot of bbl](https://github.com/damianoognissanti/bbl/blob/main/bbl.png?raw=true)

## Chapter 1 Create partition and set some variables

In this example I use btrfs since it is easy to create and delete subvolumes with it, but you can certainly use ext4 or whatever file system you want.

Create a unique name for the installation. I usually pick some prefix + date, like so:

```sh
DATE=$(date +"%Y%m%d_%H%M")
BUILDNAME="bbl_$DATE"
```

Set the bbl root directory. Remember, if you take a break and close the terminal, or if you switch user (e.g. to root) the variables are gone, which means that if you, for example, run `rm -rf $BBLROOT/usr` because you want to delete the `usr` folder in the bbl folder this will just read `rm -rf /usr` since `$BBLROOT` is empty, which means it will remove your `usr` folder.

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

Using a separate subvolume per install makes it easy to keep multiple bbl systems side by side and remove or rebuild them without touching the rest.

## Chapter 2 Create the base system

In this chapter we are just creating the minimum structure needed for a Linux userspace.

Later chapters make it more comfortable and more practical, but the important thing is that the base system stays understandable.

Populate the subvolume with the folders needed for the install:

```sh
mkdir -p "$BBLROOT"/{bin,etc,dev,lib,root,home,sys,run,proc,tmp,mnt,var,usr}
mkdir -p "$BBLROOT"/usr/{bin,sbin}
mkdir -p "$BBLROOT"/home/"$USERNAME"
mkdir -p "$BBLROOT"/var/{log,empty}
mkdir -p "$BBLROOT"/lib/modules
chmod 1777 "$BBLROOT/tmp"
chmod 0555 "$BBLROOT/var/empty"
```

Now you need a statically linked busybox binary. In this setup I download the prebuilt static binary and verify it before using it.

```sh
BUSYBOXURL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
BUSYBOXSHASUM="6e123e7f3202a8c1e9b1f94d8941580a25135382b99e8d3e34fb858bba311348"

cd "$BBLROOT/bin"
wget "$BUSYBOXURL" -O busybox
echo "$BUSYBOXSHASUM  busybox" | sha256sum -c
chmod +x busybox
```

Busybox is where a lot of the fun is in a setup like this. One binary provides a large chunk of the basic userland. With a static build, you do not even need shared libraries to begin using it.

Create a symbolic link for each busybox program:

```sh
for prog in $(./busybox --list); do ln -sf busybox "$prog"; done
cd "$BBLROOT"
```

Make `su` available for the user account:

```sh
chmod u+s "$BBLROOT/bin/busybox"
```

Now we need something that runs after the kernel, so let us create `/etc/inittab` (the file that tells BusyBox init what to do at boot).

This file will:

* give you terminals with login
* create and mount the basic runtime directories
* mount everything in `fstab`
* set the hostname
* bring up `lo`
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
::ctrlaltdel:/bin/reboot
::shutdown:/bin/echo SHUTTING DOWN
::shutdown:/bin/umount -a -r
tty1::respawn:/bin/getty 38400 tty1
tty2::askfirst:/bin/getty 38400 tty2
tty3::askfirst:/bin/getty 38400 tty3
tty4::askfirst:/bin/getty 38400 tty4
EOF
```

Create an `fstab` file (the file that tells the system what to mount).

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

Notice that `/boot` is not listed here. That is intentional. You do not need `/boot` mounted inside the bbl system just to run it. You only need it mounted when you want to install or replace the kernel.

Create the hostname file (the file that stores the system host name):

```sh
cat <<'EOF' > "$BBLROOT/etc/hostname"
busyboxlinux
EOF
```

Create the groups file (the file that defines system groups):

```sh
cat <<EOF > "$BBLROOT/etc/group"
root:x:0:
tty:x:5:$USERNAME
wheel:x:97:$USERNAME
$USERNAME:x:1000:
EOF
```

Create the passwd file (the file that defines user accounts):

```sh
cat <<EOF > "$BBLROOT/etc/passwd"
root:x:0:0:root:/root:/bin/sh
$USERNAME:x:1000:1000:Linux User,,,:/home/$USERNAME:/bin/sh
EOF
```

Create a locked shadow file for now (the file that stores password hashes). You will set real passwords in the chroot later.

```sh
cat <<EOF > "$BBLROOT/etc/shadow"
root:!:20000::::::
$USERNAME:!:20000::::::
EOF

chmod 600 "$BBLROOT/etc/shadow"
```

Create a hosts file (the file that maps host names to addresses locally):

```sh
cat <<'EOF' > "$BBLROOT/etc/hosts"
127.0.0.1 localhost
127.0.1.1 busyboxlinux
EOF
```

Create profile files (shell startup files that set environment variables):

```sh
cat <<'EOF' > "$BBLROOT/etc/profile"
export PATH="/bin:/usr/bin:/usr/sbin:$PATH"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
EOF

cat <<'EOF' > "$BBLROOT/home/$USERNAME/.profile"
export PS1='\u@\h:\w\\$ '
export PATH="$HOME/bin:/bin:/usr/bin:/usr/sbin:$PATH"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
EOF
```

At this point the userspace is still tiny, which is exactly the point. This install is right now missing most things people think of as "the system", but we are almost done for the bare minimum.

## Chapter 3 Kernel

Now you must compile and install your own kernel. This is the hardest step in the whole process.

In this chapter, kernel compilation happens on the host system. The commands at the end of the chapter `make INSTALL_MOD_PATH="$BBLROOT" modules_install` and `cp ... /boot/...` install artifacts into the target system and host boot partition, but the build itself is still done on the host.

Download the source, extract it and move into the folder:

```sh
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.19.6.tar.xz
tar -xf linux-6.19.6.tar.xz
cd linux-6.19.6
```

First create a default config (where variables are set to their default values):

```sh
make defconfig
```

Then append a small base. These options are not especially tied to my exact machine, they give a bootable modern x86 Linux system with EFI boot, a text console, pseudo-terminals, `/dev` populated by the kernel, basic networking and firmware loading.

```sh
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
```

What these do:

* `CONFIG_BLK_DEV=y` enables block devices in general.
* `CONFIG_PCI=y` enables PCI and PCIe devices, which covers a lot of hardware on a modern PC.
* `CONFIG_PARTITION_ADVANCED=y` and `CONFIG_MSDOS_PARTITION=y` enable partition table support.
* `CONFIG_EFI=y` and `CONFIG_EFI_PARTITION=y` are needed for UEFI systems.
* `CONFIG_DEVTMPFS=y` and `CONFIG_DEVTMPFS_MOUNT=y` let the kernel populate `/dev` automatically, which is very useful on a tiny system like this.
* `CONFIG_SERIAL_8250=y` and `CONFIG_SERIAL_8250_CONSOLE=y` enable classic serial console support.
* `CONFIG_UNIX=y`, `CONFIG_INET=y` and `CONFIG_PACKET=y` provide the basic networking stack.
* `CONFIG_UNIX98_PTYS=y` enables pseudo-terminals, which are needed for shells, logins and terminal programs.
* `CONFIG_VT=y` and `CONFIG_VT_CONSOLE=y` enable virtual terminals, so you can use normal TTYs.
* `CONFIG_TMPFS=y` and `CONFIG_TMPFS_POSIX_ACL=y` are needed for things like `/run` and `/dev/shm`.
* `CONFIG_FW_LOADER=y` lets the kernel load firmware files, which becomes important once you start using real hardware.

Then append the parts that are specific to your system and your choices. In my case that means btrfs, NVMe, AMD graphics, a framebuffer-backed console and sound.

```sh
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
```

What these do:

* `CONFIG_BTRFS_FS=y` is specific because I use `btrfs`.
* `CONFIG_BLK_DEV_NVME=y` is specific because my system uses an NVMe SSD.
* `CONFIG_SYSFB=y` and `CONFIG_SYSFB_SIMPLEFB=y` expose the firmware framebuffer early in boot.
* `CONFIG_FB=y` and `CONFIG_FB_EFI=y` enable framebuffer support, including EFI framebuffer support.
* `CONFIG_DRM=y` enables the modern graphics subsystem.
* `CONFIG_DRM_SIMPLEDRM=y` provides a simple early display driver before the full GPU driver takes over.
* `CONFIG_FRAMEBUFFER_CONSOLE=y` lets the kernel console display text through the framebuffer.
* `CONFIG_DRM_FBDEV_EMULATION=y` keeps console behavior sane on modern DRM systems.
* `CONFIG_DRM_PANIC=y` helps show kernel panic output through DRM.
* `CONFIG_DRM_AMDGPU=y` is the actual AMD GPU driver, so this one is very specific to my hardware.
* `CONFIG_SOUND=y` and `CONFIG_SND=y` enable the sound subsystem and ALSA.
* `CONFIG_SND_TIMER=y`, `CONFIG_SND_PCM=y`, `CONFIG_SND_SEQ_DEVICE=y`, `CONFIG_SND_JACK=y` and `CONFIG_SND_HRTIMER=y` provide the core ALSA sound pieces.
* `CONFIG_SND_HDA=y` and `CONFIG_SND_HDA_INTEL=y` enable the HD Audio stack used by many modern systems.
* `CONFIG_SND_HDA_CODEC_HDMI=y` enables audio over HDMI or DisplayPort.
* `CONFIG_SND_HDA_CODEC_REALTEK=y` enables support for a very common class of onboard audio codecs.
* `CONFIG_SND_HDA_GENERIC=y` enables generic HDA fallback support.

If you plan to use sandboxed desktop software later, such as Chromium-based browsers, Steam or anything that depends on bwrap, it is a good idea to enable namespace support already now.

For example:

```sh
cat >> .config <<'EOF'
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y
EOF
```

This is not required for the minimal system to boot. But if you already know you want modern desktop applications later, it is easier to enable it now.

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
options root=$DRIVE rootflags=subvol=$BUILDNAME rw rootfstype=btrfs rootwait net.ifnames=0 biosdevname=0 console=tty1 loglevel=7
EOF
```

With this you should be able to reboot into your system.

At this point you already have a working Linux system. A kernel and a statically linked busybox are enough to boot and give you a shell. You do not even need firmware if all you care about is reaching userspace. Firmware becomes important when you want hardware like graphics, wifi and sound to work properly.

### How to chroot back into the system later

Later chapters build on top of the base system. A simple way to return to the install from the host is to mount it and chroot into it.

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
```

When inside the chroot run
```sh
. /etc/profile
```
To make commands such as `ls`, `cd`, etc. available.

A chroot is a nice way to continue building from inside the new system without rebooting every time. But remember that before `chroot` works well, you need to bind in things like `/dev`, `/sys`, `/proc` and `/run`, because the small system still depends on the running host kernel and its mounted interfaces.

## Chapter 4 Firmware

You will probably need firmware for wifi, sound and graphics. Firmware is one of the first places to look when your hardware doesn't work. On a tiny system like this, the failures are often quite concrete: missing kernel option, missing module, missing firmware.

In my case I also had to make sure `linux-firmware` was present before compiling the kernel, and build the needed firmware into the kernel.

That means the order matters. First get `linux-firmware`, then point the kernel config at it.

For example:
```sh
git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git "$BBLROOT/lib/linux-firmware"
mkdir -p "$BBLROOT/lib/firmware"
cd "$BBLROOT/lib/linux-firmware"
./copy-firmware.sh "$BBLROOT/lib/firmware"
```

Now cd back to the kernel source folder.

```sh
cd /path/to/linux-6.19.6
```

If you want AMD graphics to work on a very small setup like this, it may not be enough to just enable `CONFIG_DRM_AMDGPU=y` like we did earlier. You instead need something like this to `.config` (This uses `$BBLROOT` so the path written into .config matches where linux-firmware was cloned):

```sh
cat >> .config <<EOF
CONFIG_DRM_AMDGPU=y
CONFIG_EXTRA_FIRMWARE="amdgpu/psp_14_0_3_sos.bin amdgpu/psp_14_0_3_ta.bin amdgpu/smu_14_0_3.bin amdgpu/dcn_4_0_1_dmcub.bin amdgpu/gc_12_0_1_pfp.bin amdgpu/gc_12_0_1_me.bin amdgpu/gc_12_0_1_mec.bin amdgpu/gc_12_0_1_rlc.bin amdgpu/gc_12_0_1_toc.bin amdgpu/gc_12_0_1_imu.bin amdgpu/gc_12_0_1_imu_kicker.bin amdgpu/gc_12_0_1_rlc_kicker.bin amdgpu/gc_12_0_1_mes.bin amdgpu/gc_12_0_1_mes1.bin amdgpu/gc_12_0_1_uni_mes.bin amdgpu/sdma_7_0_1.bin amdgpu/vcn_5_0_0.bin i915/adls_dmc_ver2_01.bin i915/tgl_guc_70.bin"
CONFIG_EXTRA_FIRMWARE_DIR="$BBLROOT/lib/linux-firmware"
EOF
```

Then you need to recompile the kernel:
```sh
make olddefconfig
make -j"$(nproc)"
make INSTALL_MOD_PATH="$BBLROOT" modules_install
cp -iv arch/x86/boot/bzImage /boot/vmlinuz-$BUILDNAME
cp -iv System.map /boot/System.map-$BUILDNAME
```

If your graphics hardware needs extra kernel parameters, add them to the bootloader entry. For example, on some AMD systems you may want to try `amdgpu.dc=1`.

This firmware list is just an example from my own setup. You may need a different list depending on your hardware.

## Chapter 5 First boot and ethernet

This chapter assumes the kernel already includes the needed network support, and that (if you built it yourself instead of using the binary) BusyBox was built with the tools used here such as ip and udhcpc.

Now that the base system boots, you can reboot into it.

At this point you only have the minimal system. That is the whole idea. You can stop here if what you wanted was just a tiny Linux system with a kernel and busybox.

Before using `udhcpc`, create its default helper script (the script `udhcpc` calls when it receives network settings from DHCP):

```sh
mkdir -p /usr/share/udhcpc

cat <<'EOF' > /usr/share/udhcpc/default.script
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

chmod +x /usr/share/udhcpc/default.script
```

Now write:

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

If you want the system to do that automatically at boot, edit `/etc/inittab` and add these lines:

```sh
::sysinit:/bin/ip link set eth0 up
::sysinit:/bin/udhcpc -i eth0
```

A simple way is to open the file in an editor and place them after the line that brings up `lo`.

If your interface is not called `eth0`, replace it with the correct name there too.

## Chapter 6 Nix package manager

Now that the base system boots, you can install Nix on top.

This is the point where the machine stops being only a boot experiment and starts becoming a place you can actually live in.

Since this is a small busybox system without systemd, the easiest route is a single-user install.

There is one important thing to know here: the tiny base system may not yet have the CA certificates needed for HTTPS downloads. Because of that, the simplest and safest way to install Nix the first time is to download and verify the tarball on the host first, then copy it into the bbl system and install it from there.

If you have rebooted the computer or closed the terminal, set `BUILDNAME`, `DRIVE`, `BBLROOT` and `USERNAME` again. Don't use the command to create a buildname with the date command though, otherwise it's not the same as the one you created earlier, manually set it to what it's supposed to be, something like this:

```sh
BUILDNAME="bbl_20260313_1200"
DRIVE="/dev/nvme0n1p2"
BBLROOT="/mnt"
USERNAME="bbl"
```

Then mount your build again (if you have unmounted it previously):

```sh
mount -o "subvol=$BUILDNAME" "$DRIVE" "$BBLROOT"
```

### On the host: copy the CA certificates
Copy the CA certificates into the places most programs expect. In this setup I put them in `/etc/ssl`, which is enough to get HTTPS working for the Nix install (and later downloads on the system).
```sh
mkdir -p "$BBLROOT/etc/ssl"
cp -a /etc/ssl/certs "$BBLROOT/etc/ssl/"
```

### On the host: download and verify Nix

```sh
VERSION="2.34.0"
NIXURL="https://releases.nixos.org/nix/nix-$VERSION/nix-$VERSION-x86_64-linux.tar.xz"
NIXSHASUM="5676b0887f1274e62edd175b6611af49aa8170c69c16877aa9bc6cebceb19855"

cd /tmp
wget "$NIXURL"
echo "$NIXSHASUM  nix-$VERSION-x86_64-linux.tar.xz" | sha256sum -c
```

### On the host: prepare the chroot and copy in what is needed

Mount the install and bind the usual things from the host:

```sh
mount --rbind /dev "$BBLROOT/dev"
mount --make-rslave "$BBLROOT/dev"
mount -t proc /proc "$BBLROOT/proc"
mount --rbind /sys "$BBLROOT/sys"
mount --make-rslave "$BBLROOT/sys"
mount --bind /run "$BBLROOT/run"
cp /etc/resolv.conf "$BBLROOT/etc/"
```

Copy the verified Nix tarball into the new system:

```sh
cp "/tmp/nix-$VERSION-x86_64-linux.tar.xz" "$BBLROOT/home/$USERNAME/"
```

Now chroot into the system:

```sh
chroot "$BBLROOT" /bin/sh
```

When inside the chroot run
```sh
. /etc/profile
```
To make commands such as `ls`, `cd`, etc. available.


Set the USERNAME and VERSION variables since they don't exist inide the chroot:
```sh
USERNAME="bbl"
VERSION="2.34.0"
```

### Inside the bbl system: prepare the user and install Nix

Make sure the user owns the home folder (and the nix tarball):

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

Now unpack and install the already verified tarball:

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

Add this to your profile to make it automatic during login:

```sh
cat <<'EOF' >> "$HOME/.profile"
export PATH="$HOME/.nix-profile/bin:/bin:/usr/bin:/usr/sbin:$PATH"
[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"
EOF
```

Now Nix should work.

Add the unstable channel and update:

```sh
nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
nix-channel --update
```

If HTTPS still does not work, the first things to check are usually DNS and where the CA certificates ended up.

## Chapter 7 eudev

If you want automatic device handling, install `eudev` through Nix.

```sh
nix-env -iA \
  nixpkgs.eudev
```

Create a helper that starts `eudev`:

```sh
cat <<EOF > /usr/sbin/start-udev.sh
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

chmod +x /usr/sbin/start-udev.sh
```

Now edit `/etc/inittab` and add this line:

```sh
::sysinit:/bin/sh /usr/sbin/start-udev.sh
```

A simple way is to open the file in an editor and add it after the line that brings up `lo` or after the networking lines if you prefer.

If later user-space programs need a session bus, which is used for desktop applications to communicate with each other (needed for example if you wish to install a window manager later on), you need to install D-Bus and add a small session config (a file that defines the per-user D-Bus session bus):

```sh
nix-env -iA \
  nixpkgs.dbus
```

```sh
mkdir -p /etc/dbus-1

cat <<'EOF' > /etc/dbus-1/session.conf
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

## Chapter 8 Wayland with seatd

This chapter assumes the graphics driver is enabled in the kernel, needed firmware is available, and device handling is working well enough for input devices and DRM devices to appear.

Everything up to here is enough for a working text-based system. This chapter is where things become more pleasant to use interactively.

Here is one simple Wayland setup using Sway.

Before installing it, extend `/etc/group` so the user is in the groups that are usually useful for graphics and input.

```sh
cat <<EOF > /etc/group
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
  nixpkgs.mesa \
  nixpkgs.fontconfig \
  nixpkgs.dejavu_fonts \
  nixpkgs.terminus_font \
  nixpkgs.libinput \
  nixpkgs.libwacom \
  nixpkgs.xkeyboard_config \
  nixpkgs.shared-mime-info
```

Create a helper that starts `seatd`:

```sh
cat <<EOF > /usr/sbin/seatd-daemon.sh
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

chmod +x /usr/sbin/seatd-daemon.sh
```

Now edit `/etc/inittab` and add this line:

```sh
::once:/bin/sh /usr/sbin/seatd-daemon.sh
```

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

## Chapter 9 WiFi

If your WiFi driver was not built into the kernel or installed as a module in earlier chapters, you may need to go back to the kernel chapter and add the right driver first.

For WiFi you usually need three things:

1. the correct kernel driver
2. the correct firmware in `/lib/firmware`
3. `wpa_supplicant`

If you do not already have the WiFi tools, install them through Nix:

```sh
nix-env -iA \
  nixpkgs.wpa_supplicant \
  nixpkgs.iw
```

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

On a system this small, there aren't many things to check. These commands are often enough to figure out what is wrong:

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
