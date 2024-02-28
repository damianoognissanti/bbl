# Busybox Linux - bbl
### Because sometimes everything you need is a statically built busybox.

TL;DR. Just for fun I tried to see how little was needed to boot into Linux. I compiled a kernel and a statically linked busybox and that was enough! 
 
Remember, everything below is just a suggestion on how things can be done, adjust to your needs.
And be careful before you type any command into the terminal. Try to learn what each command does before running it.

## Chapter 1 Create partition and set some variables
For this installation I use btrfs, since it's easy to create and delete subvolumes with it.

Create a unique name for the installation. I usually pick some prefix + date, like so:
```
DATE=$(date +"%Y%m%d_%H%M")
BUILDNAME="bbl_$DATE"
```

Set the bbl root directory. Remember, if you take a break and close the terminal the variables are gone, which means that if you, for example run `rm -rf $BBLROOT/usr` because you want to delete the `usr` folder in the bbl folder this will just read `rm -rf /usr` since `$BBLROOT` is empty, which means it will remove your `usr` folder. 
Please note that I never tell you to `rm -rf $SOME_VARIABLE` in this document since it's bad practice!

```
BBLROOT="/mnt"
```

Store the drive name and UUIDs. You get these values by typing `blkid` in a terminal and copying from the correct line. 
```
DRIVE="/dev/nvme0n1p2"
UUID="abc1234d-a123-1234-abc1-12ab34c56789"
PARTUUID="1abc23d4-1abc-1abc-12ab-a12345b123cd"
```

Select a user name
```
USERNAME="bbl"
```

Create btrfs subvolumes
```
mkdir -p Mount
mount $DRIVE Mount
btrfs subvolume create Mount/$BUILDNAME
umount Mount
mount $DRIVE -osubvol=$BUILDNAME $BBLROOT 
```

## Chapter 2 Create the base system
Populate drive with folders needed for the install
```
mkdir $BBLROOT/{bin,etc,dev,lib,root,home,sys,run,proc,tmp,mnt,var}
mkdir $BBLROOT/lib/{modules,firmware,xorg}
mkdir $BBLROOT/home/$USERNAME
mkdir $BBLROOT/var/log
```

If you don't want to build it yourself you can download a static busybox build, and put it in /bin and test checksum
```
BUSYBOXURL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
BUSYBOXSHASUM="6e123e7f3202a8c1e9b1f94d8941580a25135382b99e8d3e34fb858bba311348  busybox"
pushd $BBLROOT/bin/
wget $BUSYBOXURL 
echo "$BUSYBOXSHASUM" | sha256sum -c
```
If the checksum is OK proceed to make it executable
```
chmod +x busybox
```
Create a symbolic link for each busybox program
```
for prog in $(./busybox --list); do ln -s busybox $prog; done
```
Make su available for user account
```
chmod +s su
```

Download static bash, put it in /bin and test checksum
```
mkdir staticbash
pushd staticbash
BASHURL="http://ftp.us.debian.org/debian/pool/main/b/bash/bash-static_5.2.15-2+b2_amd64.deb"
BASHSHASUM="ee9b003975406c46669cbdf1d75c237a2ebf5a5ec241c4c6fd7bda8c88d7e05c  bash-static.deb"
wget $BASHURL -O bash-static.deb 
echo "$BASHSHASUM" | sha256sum -c
ar -x bash-static.deb
tar xvf data.tar.xz
chmod +x bin/bash-static
mv bin/bash-static $BBLROOT/bin/bash
rm -rf staticbash
popd
```

Create /etc/inittab
Please note this command:
`::sysinit:/bin/modprobe mwifiex_pcie`
This runs modprobe, which can be used to load kernel modules 
Here it loads the kernel module mwifiex_pcie needed for my wifi card
The lines with chmod and chown set the ownership of various important folders and files.
```
cat <<EOF > $BBLROOT/etc/inittab
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
::ctrlaltdel:/bin/reboot
::shutdown:/bin/echo SHUTTING DOWN
::shutdown:/bin/swapoff -a
::shutdown:/bin/umount -a -r
EOF
```

Create an fstab file. The first line is used to mount the bbl partition. 
The others are for various important mount points.
```
cat <<EOF > $BBLROOT/etc/fstab
UUID="$UUID" / btrfs rw,relatime,subvol=/$BUILDNAME 0 1
proc           /proc          proc       nosuid,noexec,nodev 0     0
sysfs          /sys           sysfs      nosuid,noexec,nodev 0     0
devpts         /dev/pts       devpts     gid=5,mode=620      0     0
tmpfs          /run           tmpfs      defaults            0     0
devtmpfs       /dev           devtmpfs   mode=0755,nosuid    0     0
tmpfs          /dev/shm       tmpfs      nosuid,nodev        0     0
cgroup2        /sys/fs/cgroup cgroup2    nosuid,noexec,nodev 0     0
efivarfs       /sys/firmware/efi/efivars efivarfs defaults   0     0
EOF
```

Run `cat $BBLROOT/etc/fstab` to see that the `UUID` variable has been inserted correctly on line 1.
If you noticed that `/boot` isn't present in `/etc/fstab`, please note that you don't actually need to mount `/boot` to your bbl installation. You only need to have it mounted if you ever want to change kernel.

Create the groups (the nixbld group is for the nix package manager). The first column is group and the last users taking part of that group.
```
cat <<EOF > $BBLROOT/etc/group
root:x:0:
nixbld:x:1000:nixbld1,nixbld2,nixbld3,nixbld4,nixbld5,nixbld6,nixbld7,nixbld8,nixbld9,nixbld10,nixbld11,nixbld12,nixbld13,nixbld14,nixbld15,nixbld16,nixbld17,nixbld18,nixbld19,nixbld20,nixbld21,nixbld22,nixbld23,nixbld24,nixbld25,nixbld26,nixbld27,nixbld28,nixbld29,nixbld30
tty:x:5:$USERNAME
audio:x:11:$USERNAME
video:x:12:$USERNAME
input:x:24:$USERNAME
wheel:x:97:$USERNAME
lpadmin:x:19:$USERNAME
$USERNAME:x:1030:
EOF
```

Run `cat $BBLROOT/etc/group` to see that the `USERNAME` variable has been inserted correctly in the file.

Create the file containing the users. No passwords are set yet.
```
cat <<EOF > $BBLROOT/etc/passwd
root:x:0:0:root:/root:/bin/bash
nixbld1:x:1000:1000:Linux User,,,:/home/nixbld1:/bin/bash
nixbld2:x:1001:1000:Linux User,,,:/home/nixbld2:/bin/bash
nixbld3:x:1002:1000:Linux User,,,:/home/nixbld3:/bin/bash
nixbld4:x:1003:1000:Linux User,,,:/home/nixbld4:/bin/bash
nixbld5:x:1004:1000:Linux User,,,:/home/nixbld5:/bin/bash
nixbld6:x:1005:1000:Linux User,,,:/home/nixbld6:/bin/bash
nixbld7:x:1006:1000:Linux User,,,:/home/nixbld7:/bin/bash
nixbld8:x:1007:1000:Linux User,,,:/home/nixbld8:/bin/bash
nixbld9:x:1008:1000:Linux User,,,:/home/nixbld9:/bin/bash
nixbld10:x:1009:1000:Linux User,,,:/home/nixbld10:/bin/bash
nixbld11:x:1010:1000:Linux User,,,:/home/nixbld11:/bin/bash
nixbld12:x:1011:1000:Linux User,,,:/home/nixbld12:/bin/bash
nixbld13:x:1012:1000:Linux User,,,:/home/nixbld13:/bin/bash
nixbld14:x:1013:1000:Linux User,,,:/home/nixbld14:/bin/bash
nixbld15:x:1014:1000:Linux User,,,:/home/nixbld15:/bin/bash
nixbld16:x:1015:1000:Linux User,,,:/home/nixbld16:/bin/bash
nixbld17:x:1016:1000:Linux User,,,:/home/nixbld17:/bin/bash
nixbld18:x:1017:1000:Linux User,,,:/home/nixbld18:/bin/bash
nixbld19:x:1018:1000:Linux User,,,:/home/nixbld19:/bin/bash
nixbld20:x:1019:1000:Linux User,,,:/home/nixbld20:/bin/bash
nixbld21:x:1020:1000:Linux User,,,:/home/nixbld21:/bin/bash
nixbld22:x:1021:1000:Linux User,,,:/home/nixbld22:/bin/bash
nixbld23:x:1022:1000:Linux User,,,:/home/nixbld23:/bin/bash
nixbld24:x:1023:1000:Linux User,,,:/home/nixbld24:/bin/bash
nixbld25:x:1024:1000:Linux User,,,:/home/nixbld25:/bin/bash
nixbld26:x:1025:1000:Linux User,,,:/home/nixbld26:/bin/bash
nixbld27:x:1026:1000:Linux User,,,:/home/nixbld27:/bin/bash
nixbld28:x:1027:1000:Linux User,,,:/home/nixbld28:/bin/bash
nixbld29:x:1028:1000:Linux User,,,:/home/nixbld29:/bin/bash
nixbld30:x:1029:1000:Linux User,,,:/home/nixbld30:/bin/bash
$USERNAME:x:1030:1030:Linux User,,,:/home/$USERNAME:/bin/bash
EOF
```

Please note that you can now, if you wish, use a `chroot` command (for example `arch-chroot` if you run an arch based distribution), or xchroot if you use void.
If you don't have any of those commands you can also manually mount everything and then use `chroot`:
```
mount --rbind /dev $BBLROOT/dev
mount --make-rslave $BBLROOT/dev
mount -t proc /proc $BBLROOT/proc
mount --rbind /sys $BBLROOT/sys
mount --make-rslave $BBLROOT/sys
mount --rbind /tmp $BBLROOT/tmp
mount --bind /run $BBLROOT/run
chroot $BUILDROOT /bin/bash
```

This command:
```
export PS1="(chroot) $PS1" 
```
will add "(chroot)" to the beginning of each line in your terminal, so that you remember that you are in the chrooted environment. It's not mandatory, but good practice.

If you want to exit your chrooted environment, just type `exit`. The `(chroot)` text should now be gone.

Since you mounted directories to `$BBLROOT/dev`, etc. you can't just type `umount $BBLROOT` when you wish to unmount the partition from the folder, you must use `unmount -R $BBLROOT` (where -R if for recursive).

## Chapter 3 Kernel (optional)

If you just wish to play around in the terminal via `chroot`, install a package manager, install some packages and call it a day, you can skip this step (but then you could have skipped a lot of steps above too...), but if you want to run this on bare metal you must now compile and Install your own kernel. You do this on your host machine, not inside your `chroot`.
This is the hardest step in the entire installation. Go to https://www.linuxfromscratch.org/lfs/view/development/chapter10/kernel.html and follow the steps.

Create an entry in your bootloader. Here's an example if you use systemd-boot
```
cat <<EOF > /boot/loader/entries/bbl.conf
title   BBL
linux   /vmlinuz-
options root=PARTUUID=$PARTUUID rootflags=subvol=bbl_20240227_1207 rw rootfstype=btrfs i915.enable_psr=0
EOF
```

You will probably need firmware for your wifi card, sound, etc. the easiest way to solve this is to grab every firmware you need from kernel.org using git
```
git clone depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
cp -a linux-firmware/* $BBLROOT/lib/firmware
```

## Chapter 4 Package manager

This configuration is needed for nix work!
```
mkdir $BBLROOT/etc/nix
cat <<EOF > $BBLROOT/etc/nix/nix.conf
sandbox = false
EOF
```

Download nix install script
```
wget https://nixos.org/nix/install -O $BBLROOT/home/$USERNAME/install
```

Chroot into the installation
`arch-chroot /mnt` (or use the steps above for a manual chroot).

Set the USERNAME variable again, since it doesn't exist in the chroot

```
USERNAME=bbl
```

Make home available for user
```
chown $USERNAME -R /home/$USERNAME
```
Create the `/nix` folder manually (since you don't have sudo) and give it correct permissions.
```
mkdir -m 0755 /nix && chown $USERNAME /nix
```

Set user password
```
passwd $USERNAME
```
Set root password
```
passwd
```
Switch to user account
```
su $USERNAME
```
Go home
```
cd ~
```
Create your .bashrc file
```
cat <<EOF > .bashrc
export PS1="\[\e[38;5;30m\]\u\[\e[38;5;31m\]@\[\e[38;5;32m\]\h \[\e[38;5;33m\]\w \[\033[0m\]$ "
source /home/$USERNAME/.nix-profile/etc/profile.d/nix.sh
EOF
```

Add home manager
```
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update
```
There is a bug that makes some home manager paths conflict with nix' paths, so set nix priority here.
You need to change the command below so that it uses the version of nix that is installed on your system here.
To find which nix version you have installed just run `nix-env -q`
```
nix-env --set-flag priority 0 nix-2.20.3
```
Install home manager
```
nix-shell '<home-manager>' -A install
```
Initialize home-manager
```
home-manager
```

Now your config file is created in `.config/home-manager/home.nix`

You can edit it with vi inside the chroot (or your editor of choice outside the chroot).

Add the packages you need by entering their name under `home.packages = [`. 
Try to add some package that run in the terminal to see that it works.
You can search for packages here: https://search.nixos.org
(please note that you must write `pkgs.` before the package name, for example `pkgs.wpa_supplicant`)

Apply the config, this will install the packages
```
home-manager switch
```

## Chapter 5 Xorg

Here is a sample for a working Xorg
```
pkgs.wpa_supplicant
pkgs.xorg.setxkbmap
pkgs.xorg.xauth
pkgs.xorg.xinit
pkgs.xorg.xinput
pkgs.xorg.xorgserver
pkgs.xorg.xrdb
```

Don't forget to add a video driver, for example one of
```
pkgs.xorg.xf86videointel
pkgs.xorg.xf86videonouveau
pkgs.xorg.xf86videoati
```

Also don't forget tools such as btrfs-progs (if you use btrfs), an editor, a window manager or a desktop environment, etc.

Since this install doesn't use libinput or libeudev we need Xorg drivers for the keyboard and mouse. Unfortunately the nix package won't build since these driver have been phased out.
They still exist for Debian though, so let's grab them there.
Change user to root (you will copy the files to folders which the regular user can't write to).
```
su

mkdir ~/xorg-drivers
pushd ~/xorg-drivers
KBDURL="http://ftp.us.debian.org/debian/pool/main/x/xserver-xorg-input-keyboard/xserver-xorg-input-kbd_1.9.0-1+b3_amd64.deb"
KBDSHASUM="bfba5dc3fe75df8ae6f5f3065e4aeb03474de4a9f77d94fe32f8d36795c4313b  kbd.deb"
wget $KBDURL -O kbd.deb
echo "$KBDSHASUM" | sha256sum -c
ar -x kbd.deb
tar xvf data.tar.xz
cp -a usr/lib/xorg/* /lib/xorg/
rm -rf control.tar.xz data.tar.xz usr debian-binary kbd.deb

MOUSEURL="http://ftp.us.debian.org/debian/pool/main/x/xserver-xorg-input-mouse/xserver-xorg-input-mouse_1.9.3-1+b1_amd64.deb"
MOUSESHASUM="1933b81d9a4923e7c57473ece42e6124be850f3353954c558b1ad74aab25a20d  mouse.deb"
wget "$MOUSEURL" -O mouse.deb
echo "$MOUSESHASUM" | sha256sum -c
ar -x mouse.deb
tar xvf data.tar.xz
cp -a usr/lib/xorg/* /lib/xorg/
rm -rf control.tar.xz data.tar.xz usr debian-binary mouse.deb
popd
rm -rf ~/xorg-drivers
```

Add a config for mouse and keyboard. Unfortunately you must add the path to the nix-installed xorg's modules, which means this must be updates manually each time the path changes.
Type `ls /nix/store/*xorg-server*` to find the path to the folder that contains the `lib` folder. For me it was `/nix/store/hf4rbbcdzgl1nbz4nv8hgwjjl7q8flnn-xorg-server-21.1.11`. Change the `ModulePath` below to the folder you get by this command.

```
mkdir -p /etc/X11/xorg.conf.d/
cat <<EOF > /etc/X11/xorg.conf.d/00-mousekbd.conf
Section "ServerFlags"
	Option "AutoAddDevices" "False"
EndSection

Section "Files"
	ModulePath   "/nix/store/hf4rbbcdzgl1nbz4nv8hgwjjl7q8flnn-xorg-server-21.1.11/lib/xorg/modules"
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
```

The final step is to add the file `.xinitrc` to your user's home directory. The content of the file depends on which window manager or desktop environment you wish to start. An example for i3 is just the line `exec i3`.

This should be it. Reboot into your new machine, login, type `startx` and you should have everything set up. If you wish to log in to your window manager directly after login (without typing `startx`) you can add a file named `.bash_profile` to your home folder with the following lines:

```
# Run startx if on tty1
if [ -z "${DISPLAY}" ] && [ $(tty) == "/dev/tty1" ]; then
  exec startx
fi
```

## Chapter 6 WiFi
First install `wpa_supplicant` via home-manager when you are chrooted into your bbl-installation (so that you have an internet connection). 
Now run 
```
wpa_passphrase YOUR_SSID > wpa.conf
```
Where YOUR_SSID is the "name" of your connection. You will be prompted for the password, so have it nearby.

With the command `ip link` you can see the name of your wifi interface (it might be `wlan0`, `mlan0`, or something similar).

To connect you run
```
wpa_supplicant -imlan0 -cwpa.conf &
```
as the root user, where you substitute mlan0 for the name of your wifi interface.

Now you need an IP address. For this you can use the following script (remember to check that $BBLROOT is set before running this):
```
mkdir -p $BBLROOT/usr/share/udhcpc/
cat <<EOF > $BBLROOT/usr/share/udhcpc/default.script 
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


```
To receive an IP address you can now write
```
udhcpc -imlan0 /usr/share/udhcpc/default.script
```
Where again you have to change the interface name to match the one you got from `ip link`.
