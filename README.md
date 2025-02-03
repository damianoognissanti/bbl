# Busybox Linux - bbl
### Because sometimes everything you need is a statically built busybox.

TL;DR. Just for fun I tried to see how little was needed to boot into Linux. I compiled a kernel and a statically linked busybox and that was enough! 

Remember, everything below is just a suggestion on how things can be done, adjust to your needs.

I have added a script called `bbl_script.sh` that will perform all steps below.

*And be careful before you type any command into the terminal. Try to learn what each command does before running it.*

![Screenshot of bbl](https://github.com/damianoognissanti/bbl/blob/main/bbl.png?raw=true)

## Chapter 1 Create partition and set some variables
In this example I use btrfs since it's easy to create and delete subvolumes with it, but you can certainly use ext4 or whatever file system you want.

Create a unique name for the installation. I usually pick some prefix + date, like so:
```
DATE=$(date +"%Y%m%d_%H%M")
BUILDNAME="bbl_$DATE"
```

Set the bbl root directory. Remember, if you take a break and close the terminal, or if you switch user (e.g. to root) the variables are gone, which means that if you, for example run `rm -rf $BBLROOT/usr` because you want to delete the `usr` folder in the bbl folder this will just read `rm -rf /usr` since `$BBLROOT` is empty, which means it will remove your `usr` folder. 

Please note that I never tell you to `rm -rf $SOME_VARIABLE` in this document since it's bad practice!

```
BBLROOT="/mnt"
```

Store the drive name and UUID in variables. You get these values by typing `blkid` in a terminal and copying the values from the correct line. 
```
DRIVE="/dev/nvme0n1p2"
UUID="abc1234d-a123-1234-abc1-12ab34c56789"
```

Select a user name
```
USERNAME="bbl"
```

Mount your drive in a folder called Mount and create btrfs subvolumes. Unmount the drive and mount the subvolume in the `$BBLROOT`-folder.
```
mkdir -p Mount
mount $DRIVE Mount
btrfs subvolume create Mount/$BUILDNAME
umount Mount
mount $DRIVE -osubvol=$BUILDNAME $BBLROOT 
```

## Chapter 2 Create the base system
Populate subvolume with the folders needed for the install
```
mkdir $BBLROOT/{bin,etc,dev,lib,root,home,sys,run,proc,tmp,mnt,var}
mkdir $BBLROOT/lib/modules
mkdir $BBLROOT/home/$USERNAME
mkdir $BBLROOT/var/log
```

Now you need to build a statically linked busybox binary. If you don't want to build it yourself, you can download a precompiled static busybox build.
```
BUSYBOXURL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
BUSYBOXSHASUM="6e123e7f3202a8c1e9b1f94d8941580a25135382b99e8d3e34fb858bba311348  busybox"
pushd $BBLROOT/bin/
wget $BUSYBOXURL 
echo "$BUSYBOXSHASUM" | sha256sum -c
```
If the checksum is OK proceed to make it executable.
```
chmod +x busybox
```
Create a symbolic link for each busybox program.
```
for prog in $(./busybox --list); do ln -s busybox $prog; done
```
Make su available for user account.
```
chmod +s su
```

Now we need something that runs after the kernel, so let's create the file `/etc/inittab` and:
1) populate it with tty (to get some terminals with a login)
2) create some folders in `/dev` that will be populated
3) mount everything in `fstab` (we will create it shortly)
4) set hostname (we will create the hostname file shortly)
5) load neccessary kernel modules with `modprobe` (we will install these shortly). `mwifiex_pcie` is the kernel module used for my wifi card.
6) change permissions on certain folders and files to make input, video, etc. work (some of these are only neccessary if you wish to use Xorg).
7) set commands for ctrl-alt-del and for shutdown.
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
UUID="$UUID" /              btrfs      rw,relatime,subvol=/$BUILDNAME 0     1
proc                                        /proc          proc       nosuid,noexec,nodev            0     0
sysfs                                       /sys           sysfs      nosuid,noexec,nodev            0     0
devpts                                      /dev/pts       devpts     gid=5,mode=620                 0     0
tmpfs                                       /run           tmpfs      defaults                       0     0
devtmpfs                                    /dev           devtmpfs   mode=0755,nosuid               0     0
tmpfs                                       /dev/shm       tmpfs      nosuid,nodev                   0     0
cgroup2                                     /sys/fs/cgroup cgroup2    nosuid,noexec,nodev            0     0
efivarfs                                    /sys/firmware/efi/efivars efivarfs defaults              0     0
EOF
```

Run `cat $BBLROOT/etc/fstab` to see that the `UUID` variable has been inserted correctly on line 1. When the UUID is in place the first line should be aligned with the others. If not you can just add spaces to make them aligned (not neccesary, just to make it more readable).

If you noticed that `/boot` isn't present in `/etc/fstab`, please note that you don't actually need to mount `/boot` to your bbl installation. You only need to have it mounted if you ever want to change kernel. You can add `/boot` yourself if it's important to you.

Create the hostname file. This file just contains the hostname
```
cat <<EOF > $BBLROOT/etc/hostname
busyboxlinux
EOF

```

Create the groups. The first column is group and the last users taking part of that group.
```
cat <<EOF > $BBLROOT/etc/group
root:x:0:
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

Create the file containing the users.
```
cat <<EOF > $BBLROOT/etc/passwd
root:x:0:0:root:/root:/bin/sh
$USERNAME:x:1030:1030:Linux User,,,:/home/$USERNAME:/bin/sh
EOF
```
Create a password for your user. The password to both `$USERNAME` and `root` is set to `bbl`. If you wish to change it you will either have to read about the shadow file or you run `passwd` after you login later.
```
cat <<EOF > $BBLROOT/etc/shadow
root:$y$j9T$82GPlTw.R0C2fLI4xWvZn.$u2mW6Ln/Qy8kxjMaNrpLvFTwQj54tlVd/u20UjYmzG/:20005::::::
$USERNAME:$y$j9T$82GPlTw.R0C2fLI4xWvZn.$u2mW6Ln/Qy8kxjMaNrpLvFTwQj54tlVd/u20UjYmzG/:20005::::::
EOF

```

Add an environment file stating where to look for binaries
```
cat <<EOF > $BBLROOT/etc/environment
PATH="/bin"
EOF
```
If you wish to add more paths later you can just add new paths to the variable separating the values by colon, e.g. `PATH="/bin:/sbin:/usr/local/bin"`.

If you wish to test your system now, before adding a kernel, you can use a `chroot` command (for example `arch-chroot` if you run an arch based distribution, or `xchroot` if you use void).

If you don't have `arch-chroot` or `xchroot` present on your machine you can also manually mount everything and then use `chroot`:

```
mount --rbind /dev $BBLROOT/dev
mount --make-rslave $BBLROOT/dev
mount -t proc /proc $BBLROOT/proc
mount --rbind /sys $BBLROOT/sys
mount --make-rslave $BBLROOT/sys
mount --rbind /tmp $BBLROOT/tmp
mount --bind /run $BBLROOT/run
chroot $BUILDROOT /bin/sh
```
You need to source your environment, otherwise running commands will just yield: `/bin/sh: ls: not found`.
```
source /etc/environment
```

This command:
```
export PS1="(chroot) $PS1" 
```
will add "(chroot)" to the beginning of each line in your terminal, so that you remember that you are in the chrooted environment. It's not mandatory, but good practice.

If you want to exit your chrooted environment, just type `exit`. The `(chroot)` text should now be gone.

Since you mounted directories to `$BBLROOT/dev`, etc. you can't just type `umount $BBLROOT` when you wish to unmount the partition from the folder, you must use `unmount -R $BBLROOT` (where -R if for recursive).

## Chapter 3 Kernel
Now you must compile and install your own kernel. This is the hardest step in the entire installation! This is also something you should do on the host and not in the chrooted environment since you need to install a bunch of dependencies to be able to compile the kernel.

Go to https://www.linuxfromscratch.org/lfs/view/development/chapter10/kernel.html and follow the steps there. 
Before you do this though you must make sure you have all dependencies needed to compile your kernel installed: 
https://www.kernel.org/doc/html/v4.13/process/changes.html

What you need to do is basically:
1) Download the source code from https://www.kernel.org, extract it and move into the folder.
2) Go to the part of the LFS-page stating "Be sure to enable/disable/set the following features or the system might not work correctly or boot at all" and do what it says.
3) If you have an NVME SSD you have to enable it here (how this is done is mentioned on the LFS-page).
4) If you use btrfs, like me, you have to enable it by going to `File systems  --->` in the `menuconfig` and setting it, i.e., making sure it says `<*> Btrfs filesystem`.
5) You will have to enable other stuff such as sound, graphics, networking, etc. But you can recompile the kernel later and skip this step the first time you do this (if you keep your kernel folder you will only compile the parts you add and not the whole thing, so it won't take long).
6) Run `make ARCH=x86_64 -jN` where N is the number of cores you wish to use for compilation.
7) Run `make modules_install` and then move the folder `/lib/modules/KERNEL_VERSION` to `$BBLROOT/lib/modules`.
8) Copy the compiled kernel `cp -iv arch/x86_64/boot/bzImage /boot/vmlinuz`
9) Copy the System map `cp -iv System.map /boot/System.map`

Create an entry in your bootloader. Here's an example if you use systemd-boot (since that is what I have installed on my machine):
```
cat <<EOF > /boot/loader/entries/bbl.conf
title   BBL
linux   /vmlinuz
options root=$DRIVE rootflags=subvol=$BUILDNAME rw rootfstype=btrfs
EOF
```
With this you should be able to reboot into your system!

## Chapter 4 Firmware (quasi-optional)
You will probably need firmware for your wifi card, sound, etc. and the easiest way to solve this is to grab every firmware you need from kernel.org using git
```
git clone depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
mkdir $BBLROOT/lib/firmware
cp -a linux-firmware/* $BBLROOT/lib/firmware
```
But there is unfortunately more to this, so read this page: https://www.linuxfromscratch.org/blfs/view/svn/postlfs/firmware.html for more information.
This is a bit tricky and you might have to add `modprobe` lines to the `inittab` file mentioned above for it to work (after you have downloaded the firmware to the correct folder and recompiled the kernel with the features added).

## Chapter 5 Nix package manager (optional)
I had to manually create the group and users (since the nix install script creates these using `sudo`, which isn't installed on our machine).
```
cat <<EOF >> $BBLROOT/etc/group
nixbld:x:30000:nixbld1,nixbld2,nixbld3,nixbld4,nixbld5,nixbld6,nixbld7,nixbld8,nixbld9,nixbld10,nixbld11,nixbld12,nixbld13,nixbld14,nixbld15,nixbld16,nixbld17,nixbld18,nixbld19,nixbld20,nixbld21,nixbld22,nixbld23,nixbld24,nixbld25,nixbld26,nixbld27,nixbld28,nixbld29,nixbld30,nixbld31,nixbld32
EOF

cat <<EOF >> $BBLROOT/etc/passwd
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
Create your .profile file (I added some color to the PS1 variable here)
```
cat <<EOF > .profile
export PS1="\[\e[38;5;30m\]\u\[\e[38;5;31m\]@\[\e[38;5;32m\]\h \[\e[38;5;33m\]\w \[\033[0m\]$ "
source /home/$USERNAME/.nix-profile/etc/profile.d/nix.sh
EOF
```
Download nix install script
```
wget https://nixos.org/nix/install -O install
```
Run the nix install script you downloaded
```
chmod +x install
./install
```
You can now install programs with `nix-env -iA nixpkgs.PKGNAME`

### Home manager (optional)
Add the home manager channel:
```
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update
```
There is a bug that makes some home manager paths conflict with the nix paths, so set nix priority here.

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

You can search for packages here: https://search.nixos.org (please note that you must write `pkgs.` before the package name, for example `pkgs.wpa_supplicant`)

Apply the config, this will install the packages
```
home-manager switch
```

## Chapter 6 Xorg (optional)

Here is a sample for a working Xorg
```
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

They still exist for Debian though (do adjust the links and checksums if they are too old), so let's grab them there.

First though, make sure your kernel was compiled with `CONFIG_INPUT_MOUSEDEV=y`, otherwise the mouse won't work.

Change user to root (you will copy the files to folders which the regular user can't write to).
```
su

mkdir /lib/xorg
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

Now, find the modules used for xorg and copy them to `/lib/xorg/`

```
cp -arv /nix/store/hf4rbbcdzgl1nbz4nv8hgwjjl7q8flnn-xorg-server-21.1.11/lib/xorg/* /lib/xorg/
```
Type `ls /nix/store/*xorg-server*` to find the path to the folder that contains the `lib` folder.

Since your xorg config relies on not finding stuff automatically, you must point to the directory in which the modules exist. If you point to the folder in the nix store you might enounter problems later on when you update xorg since the path is broken. Copying everything to `/lib/xorg/` allows you to use the old modules when you have updated xorg and decide when you wish to update the xorg modules (manually).

```
mkdir -p /etc/X11/xorg.conf.d/
cat <<EOF > /etc/X11/xorg.conf.d/00-mousekbd.conf
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
```

The final step is to add the file `.xinitrc` to your user's home directory. The content of the file depends on which window manager or desktop environment you wish to start. An example for i3 is just the line `exec i3`.

If you have a high DPI monitor and wish to use i3 you have to create the file `.Xresources` with the line `Xft.dpi: 256` (change 256 to the appropriate value by testing a couple of times). You also need to add the line `xrdb -merge .Xresources` before `exec i3` in the `.xinitrc` file.

This should be it. Reboot into your new machine, login, type `startx` and you should have everything set up. If you wish to log in to your window manager directly after login (without typing `startx`) you can add this to your `.profile` file:

```
# Run startx if on tty1
if [ -z "${DISPLAY}" ] && [ $(tty) == "/dev/tty1" ]; then
  exec startx
fi
```

## Chapter 7 Ethernet or WiFi (optional)
### Ethernet
For ethernet you write `ip link` to find the name of your connection, for example `eth0`. 
Write `iconf eth0 up` to start it.

### IP-adress with udhcpc
Now you need an IP address. You can use the script below for that.

N.B.! The script below must be stored in `/usr/share/udhcpc/default.script` and make sure you make it executable with `chmod +x /usr/share/udhcpc/default.script`, otherwise it won't work!

```
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
```
When the script is stored in the correct place and is executable you receive an IP address by running:
```
udhcpc
```

### WiFi
For WiFi first install `wpa_supplicant` via the nix package manager when you are chrooted into your bbl-installation (so that you have an internet connection). 
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

Follow the steps above (section **IP-adress with udhcpc**) to receive an IP adress.
