#!/bin/sh
set -e  # Exit immediately if a command exits with a non-zero status

# SET VARIABLES
DATE=$(date +"%Y%m%d_%H%M")
BUILDNAME="bbl_$DATE"
BBLROOT="/mnt"
BDRIVE="/dev/nvme0n1p1"
RDRIVE="/dev/nvme0n1p2"
USERNAME="damiano"

BUSYBOXURL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
BUSYBOXSHASUM="6e123e7f3202a8c1e9b1f94d8941580a25135382b99e8d3e34fb858bba311348  busybox"

KBDURL="http://ftp.us.debian.org/debian/pool/main/x/xserver-xorg-input-keyboard/xserver-xorg-input-kbd_1.9.0-1+b3_amd64.deb"
KBDSHASUM="bfba5dc3fe75df8ae6f5f3065e4aeb03474de4a9f77d94fe32f8d36795c4313b  kbd.deb"
MOUSEURL="http://ftp.us.debian.org/debian/pool/main/x/xserver-xorg-input-mouse/xserver-xorg-input-mouse_1.9.3-1+b1_amd64.deb"
MOUSESHASUM="1933b81d9a4923e7c57473ece42e6124be850f3353954c558b1ad74aab25a20d  mouse.deb"

# CREATE SUBVOLUME
mkdir -p "Mount"
mount "$RDRIVE" "Mount"
btrfs subvolume create "Mount/$BUILDNAME"
umount "Mount"

# CREATE FOLDER HIERARCHY
mount "$RDRIVE" -osubvol="$BUILDNAME" "$BBLROOT"
mkdir -p "$BBLROOT/boot" "$BBLROOT/bin" "$BBLROOT/etc" "$BBLROOT/dev" "$BBLROOT/lib" \
         "$BBLROOT/root" "$BBLROOT/home" "$BBLROOT/sys" "$BBLROOT/run" "$BBLROOT/proc" \
         "$BBLROOT/tmp" "$BBLROOT/mnt" "$BBLROOT/var" "$BBLROOT/var/log"
mkdir -p "$BBLROOT/home/$USERNAME"

# INSTALL BUSYBOX
cd "$BBLROOT/bin/"
wget "$BUSYBOXURL"
echo "$BUSYBOXSHASUM" | sha256sum -c
chmod +x busybox
for prog in $(./busybox --list); do
    ln -s busybox "$prog"
done
chmod +s su

# CREATE INITTAB
cat <<EOF > "$BBLROOT/etc/inittab"
tty1::respawn:/bin/getty 38400 tty1
tty2::askfirst:/bin/getty 38400 tty2
tty3::askfirst:/bin/getty 38400 tty3
tty4::askfirst:/bin/getty 38400 tty4
::sysinit:/bin/mkdir /dev/pts
::sysinit:/bin/mkdir /dev/shm
::sysinit:/bin/mount -a
::sysinit:/bin/hostname -F /etc/hostname
::sysinit:/bin/modprobe mwifiex_pcie
::sysinit:/bin/chown root:video /dev/dri/*
::sysinit:/bin/chmod 660 /dev/dri/*
::sysinit:/bin/chown root:tty /dev/tty*
::sysinit:/bin/chmod 660 /dev/tty*
::sysinit:/bin/chown root:input /dev/input/*
::sysinit:/bin/chmod 660 /dev/input/*
::sysinit:/bin/ln -s /proc/self/fd /dev/fd
::ctrlaltdel:/bin/reboot
::shutdown:/bin/echo SHUTTING DOWN
::shutdown:/bin/swapoff -a
::shutdown:/bin/umount -a -r
EOF

# CREATE FSTAB
cat <<EOF > "$BBLROOT/etc/fstab"
$BDRIVE /boot              vfat       defaults            0     2
$RDRIVE /              btrfs      rw,relatime,subvol=/$BUILDNAME 0     1
proc                                        /proc          proc       nosuid,noexec,nodev            0     0
sysfs                                       /sys           sysfs      nosuid,noexec,nodev            0     0
devpts                                      /dev/pts       devpts     gid=5,mode=620                 0     0
tmpfs                                       /run           tmpfs      defaults                       0     0
devtmpfs                                    /dev           devtmpfs   mode=0755,nosuid               0     0
tmpfs                                       /dev/shm       tmpfs      nosuid,nodev                   0     0
cgroup2                                     /sys/fs/cgroup cgroup2    nosuid,noexec,nodev            0     0
efivarfs                                    /sys/firmware/efi/efivars efivarfs defaults              0     0
EOF

# SET HOSTNAME
cat <<EOF > "$BBLROOT/etc/hostname"
busyboxlinux
EOF

# CREATE GROUPS
cat <<EOF > "$BBLROOT/etc/group"
root:x:0:
tty:x:5:$USERNAME
audio:x:11:$USERNAME
video:x:12:$USERNAME
input:x:24:$USERNAME
wheel:x:97:$USERNAME
lpadmin:x:19:$USERNAME
$USERNAME:x:1030:
EOF

# CREATE USERS
cat <<EOF > "$BBLROOT/etc/passwd"
root:x:0:0:root:/root:/bin/sh
$USERNAME:x:1030:1030:Linux User,,,:/home/$USERNAME:/bin/sh
EOF

# SET PASSWORDS (BOTH ARE SET TO bbl)
cat <<EOF > "$BBLROOT/etc/shadow"
root:$y$j9T$82GPlTw.R0C2fLI4xWvZn.$u2mW6Ln/Qy8kxjMaNrpLvFTwQj54tlVd/u20UjYmzG/:20005::::::
$USERNAME:$y$j9T$82GPlTw.R0C2fLI4xWvZn.$u2mW6Ln/Qy8kxjMaNrpLvFTwQj54tlVd/u20UjYmzG/:20005::::::
EOF

# CREATE ENVIRONMENT
cat <<EOF > "$BBLROOT/etc/environment"
PATH="/bin"
EOF

# INSTALL KERNEL
cp -ar /lib/modules/ "$BBLROOT/lib/"
# INSTALL FIRMWARE
cp -ar /lib/firmware/ "$BBLROOT/lib/"

# CREATE BOOTLOADER ENTRY
cat <<EOF > /boot/loader/entries/"$BUILDNAME".conf
title   BBL
linux   /vmlinuz
options root=$RDRIVE rootflags=subvol=$BUILDNAME rw rootfstype=btrfs
EOF

# NIX
# Add group
cat <<EOF >> "$BBLROOT/etc/group"
nixbld:x:30000:nixbld1,nixbld2,nixbld3,nixbld4,nixbld5,nixbld6,nixbld7,nixbld8,nixbld9,nixbld10,nixbld11,nixbld12,nixbld13,nixbld14,nixbld15,nixbld16,nixbld17,nixbld18,nixbld19,nixbld20,nixbld21,nixbld22,nixbld23,nixbld24,nixbld25,nixbld26,nixbld27,nixbld28,nixbld29,nixbld30,nixbld31,nixbld32
EOF

# Add users
cat <<EOF >> "$BBLROOT/etc/passwd"
nixbld1:x:30001:30000:Nix build user 1 nixbld1:/var/empty:/sbin/nologin
nixbld2:x:30002:30000:Nix build user 2 nixbld2:/var/empty:/sbin/nologin
nixbld3:x:30003:30000:Nix build user 3 nixbld3:/var/empty:/sbin/nologin
nixbld4:x:30004:30000:Nix build user 4 nixbld4:/var/empty:/sbin/nologin
nixbld5:x:30005:30000:Nix build user 5 nixbld5:/var/empty:/sbin/nologin
nixbld6:x:30006:30000:Nix build user 6 nixbld6:/var/empty:/sbin/nologin
nixbld7:x:30007:30000:Nix build user 7 nixbld7:/var/empty:/sbin/nologin
nixbld8:x:30008:30000:Nix build user 8 nixbld8:/var/empty:/sbin/nologin
nixbld9:x:30009:30000:Nix build user 9 nixbld9:/var/empty:/sbin/nologin
nixbld10:x:30010:30000:Nix build user 10 nixbld10:/var/empty:/sbin/nologin
nixbld11:x:30011:30000:Nix build user 11 nixbld11:/var/empty:/sbin/nologin
nixbld12:x:30012:30000:Nix build user 12 nixbld12:/var/empty:/sbin/nologin
nixbld13:x:30013:30000:Nix build user 13 nixbld13:/var/empty:/sbin/nologin
nixbld14:x:30014:30000:Nix build user 14 nixbld14:/var/empty:/sbin/nologin
nixbld15:x:30015:30000:Nix build user 15 nixbld15:/var/empty:/sbin/nologin
nixbld16:x:30016:30000:Nix build user 16 nixbld16:/var/empty:/sbin/nologin
nixbld17:x:30017:30000:Nix build user 17 nixbld17:/var/empty:/sbin/nologin
nixbld18:x:30018:30000:Nix build user 18 nixbld18:/var/empty:/sbin/nologin
nixbld19:x:30019:30000:Nix build user 19 nixbld19:/var/empty:/sbin/nologin
nixbld20:x:30020:30000:Nix build user 20 nixbld20:/var/empty:/sbin/nologin
nixbld21:x:30021:30000:Nix build user 21 nixbld21:/var/empty:/sbin/nologin
nixbld22:x:30022:30000:Nix build user 22 nixbld22:/var/empty:/sbin/nologin
nixbld23:x:30023:30000:Nix build user 23 nixbld23:/var/empty:/sbin/nologin
nixbld24:x:30024:30000:Nix build user 24 nixbld24:/var/empty:/sbin/nologin
nixbld25:x:30025:30000:Nix build user 25 nixbld25:/var/empty:/sbin/nologin
nixbld26:x:30026:30000:Nix build user 26 nixbld26:/var/empty:/sbin/nologin
nixbld27:x:30027:30000:Nix build user 27 nixbld27:/var/empty:/sbin/nologin
nixbld28:x:30028:30000:Nix build user 28 nixbld28:/var/empty:/sbin/nologin
nixbld29:x:30029:30000:Nix build user 29 nixbld29:/var/empty:/sbin/nologin
nixbld30:x:30030:30000:Nix build user 30 nixbld30:/var/empty:/sbin/nologin
nixbld31:x:30031:30000:Nix build user 31 nixbld31:/var/empty:/sbin/nologin
nixbld32:x:30032:30000:Nix build user 32 nixbld32:/var/empty:/sbin/nologin
EOF

# SETUP DPI CONFIG AND XINITRC TO START I3
cat <<EOF > "$BBLROOT/home/$USERNAME/.Xresources"
Xft.dpi: 256
EOF

cat <<EOF > "$BBLROOT/home/$USERNAME/.xinitrc"
xrdb -merge .Xresources
exec i3
EOF

# COPY I3 CONFIG
mkdir -p "$BBLROOT/home/$USERNAME/.config"
cp -ar "/home/$USERNAME/.config/i3" "$BBLROOT/home/$USERNAME/.config/i3"

### IP-adress with udhcpc
mkdir -p "$BBLROOT/usr/share/udhcpc/"

cat <<'EOF' > "$BBLROOT/usr/share/udhcpc/default.script"
#!/bin/sh
# udhcpc script edited by Tim Riker <Tim at Rikers.org>
[ -z "$1" ] && echo "Error: should be called from udhcpc" && exit 1
RESOLV_CONF="/etc/resolv.conf"
[ -n "$broadcast" ] && BROADCAST="broadcast $broadcast"
[ -n "$subnet" ] && NETMASK="netmask $subnet"
# return 0 if root is mounted on a network filesystem
root_is_nfs() {
	grep -qe '^/dev/root.*\(nfs\|smbfs\|ncp\|coda\) .*' /proc/mounts
}
have_bin_ip=0
if [ -x /bin/ip ]; then
  have_bin_ip=1
fi
case "$1" in
	deconfig)
		if ! root_is_nfs ; then
                        if [ $have_bin_ip -eq 1 ]; then
                                ip addr flush dev $interface
                                ip link set dev $interface up
                        else
                                /bin/ifconfig $interface 0.0.0.0
                        fi
		fi
		;;

	renew|bound)
                if [ $have_bin_ip -eq 1 ]; then
                        ip addr add dev $interface local $ip/$mask $BROADCAST
                else
                        /bin/ifconfig $interface $ip $BROADCAST $NETMASK
                fi

		if [ -n "$router" ] ; then
			if ! root_is_nfs ; then
                                if [ $have_bin_ip -eq 1 ]; then
                                        while ip route del default 2>/dev/null ; do
                                                :
                                        done
                                else
                                        while route del default gw 0.0.0.0 dev $interface 2>/dev/null ; do
                                                :
                                        done
                                fi
			fi
			metric=0
			for i in $router ; do
                                if [ $have_bin_ip -eq 1 ]; then
                                        ip route add default via $i metric $((metric++))
                                else
                                        route add default gw $i dev $interface metric $((metric++)) 2>/dev/null
                                fi
			done
		fi
		echo -n > $RESOLV_CONF
		[ -n "$domain" ] && echo search $domain >> $RESOLV_CONF
		for i in $dns ; do
			echo adding dns $i
			echo nameserver $i >> $RESOLV_CONF
		done
		;;
esac
exit 0
EOF

chmod +x "$BBLROOT/usr/share/udhcpc/default.script"

# SETUP XORG
mkdir -p "$BBLROOT/etc/X11/xorg.conf.d/"
cat <<EOF > "$BBLROOT/etc/X11/xorg.conf.d/00-mousekbd.conf"
Section "ServerFlags"
        Option "AutoAddDevices" "False"
EndSection

Section "Files"
        ModulePath   "/lib/xorg/modules/"
EndSection

Section "InputDevice"
        Identifier  "Keyboard0"
        Driver      "kbd"
EndSection

Section "InputDevice"
        Identifier  "Mouse0"
        Driver      "mouse"
EndSection
EOF

# INSTALL MOUSE AND KEYBOARD
mkdir -p "$BBLROOT/lib/xorg"
mkdir -p "$BBLROOT/xorg-drivers/kb"
mkdir -p "$BBLROOT/xorg-drivers/mouse"

cd "$BBLROOT/xorg-drivers/kb"
wget "$KBDURL" -O kbd.deb
echo "$KBDSHASUM" | sha256sum -c
ar -x kbd.deb
tar xvf data.tar.xz
cp -a usr/lib/xorg/* "$BBLROOT/lib/xorg/"

cd "$BBLROOT/xorg-drivers/mouse"
wget "$MOUSEURL" -O mouse.deb
echo "$MOUSESHASUM" | sha256sum -c
ar -x mouse.deb
tar xvf data.tar.xz
cp -a usr/lib/xorg/* "$BBLROOT/lib/xorg/"

# SETUP CHROOT
mount --rbind /dev "$BBLROOT/dev"
mount --make-rslave "$BBLROOT/dev"
mount -t proc /proc "$BBLROOT/proc"
mount --rbind /sys "$BBLROOT/sys"
mount --make-rslave "$BBLROOT/sys"
mount --rbind /tmp "$BBLROOT/tmp"
mount --bind /run "$BBLROOT/run"
cp /etc/resolv.conf "$BBLROOT/etc/"

# INSTALL NIX PACKAGE MANAGER
chroot "$BBLROOT" /bin/sh <<EOF
. /etc/environment
chown "$USERNAME" -R /home/"$USERNAME"
mkdir -m 0755 /nix
chown "$USERNAME" /nix
chown "$USERNAME" -R /tmp

su - "$USERNAME" -c "wget https://nixos.org/nix/install"
su - "$USERNAME" -c "chmod +x install"
su - "$USERNAME" -c "./install"
EOF

# CREATE USER PROFILE
cat <<EOF > "$BBLROOT/home/$USERNAME/.profile"
. /home/$USERNAME/.nix-profile/etc/profile.d/nix.sh
EOF

# INSTALL PACKAGES USING NIX
chroot "$BBLROOT" /bin/sh <<EOF
. /etc/environment
# INSTALL XORG PACKAGES
su - "$USERNAME" -c "nix-env -iA nixpkgs.xorg.setxkbmap"
su - "$USERNAME" -c "nix-env -iA nixpkgs.xorg.xauth"
su - "$USERNAME" -c "nix-env -iA nixpkgs.xorg.xinit"
su - "$USERNAME" -c "nix-env -iA nixpkgs.xorg.xinput"
su - "$USERNAME" -c "nix-env -iA nixpkgs.xorg.xorgserver"
su - "$USERNAME" -c "nix-env -iA nixpkgs.xorg.xrdb"
su - "$USERNAME" -c "nix-env -iA nixpkgs.xorg.xf86videonouveau"

# INSTALL FONTS
su - "$USERNAME" -c "nix-env -iA nixpkgs.ubuntu-sans"
su - "$USERNAME" -c "nix-env -iA nixpkgs.ubuntu-sans-mono"
su - "$USERNAME" -c "nix-env -iA nixpkgs.fontconfig"
su - "$USERNAME" -c "fc-cache -fv"

# INSTALL I3
su - "$USERNAME" -c "nix-env -iA nixpkgs.i3"
su - "$USERNAME" -c "nix-env -iA nixpkgs.i3status"

# INSTALL OTHER APPLICATIONS
su - "$USERNAME" -c "nix-env -iA nixpkgs.konsole"
su - "$USERNAME" -c "nix-env -iA nixpkgs.brave"
su - "$USERNAME" -c "nix-env -iA nixpkgs.keepassxc"
su - "$USERNAME" -c "nix-env -iA nixpkgs.btrfs-progs"
su - "$USERNAME" -c "nix-env -iA nixpkgs.fzf"
su - "$USERNAME" -c "nix-env -iA nixpkgs.neovim"

# COPY XORG FILES
cp -arv /nix/store/*xorg-server*/lib/xorg/* /lib/xorg
EOF

# SOME PERSONAL CONFIGURATIONS
cat <<'EOF' >> "$BBLROOT/home/$USERNAME/.profile"
export PS1="\[\e[38;5;30m\]\u\[\e[38;5;31m\]@\[\e[38;5;32m\]\h \[\e[38;5;33m\]\w \[\033[0m\]$ "
. "$(fzf-share)/key-bindings.bash"
. "$(fzf-share)/completion.bash"
alias vim="nvim"
alias vi="nvim"
EOF

# JUST IN CASE 
chroot "$BBLROOT" /bin/sh <<EOF
. /etc/environment
chown "$USERNAME" -R /home/"$USERNAME"
chown "$USERNAME" /nix
chown "$USERNAME" -R /tmp
EOF
