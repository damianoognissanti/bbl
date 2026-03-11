{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = with pkgs; [
    gcc
    gnumake
    bc
    bison
    flex
    ncurses
    openssl
    elfutils
    pahole
    perl
    pkg-config
    cpio
    rsync
    git
    wget
    xz
    zstd
    qemu
    gptfdisk
    parted
    python3
    e2fsprogs
    btrfs-progs
  ];

  shellHook = ''
    echo "Kernel build shell ready."
    echo "Common commands:"
    echo "  make olddefconfig"
    echo "  make menuconfig"
    echo "  make -j\$(nproc)"
  '';
}
