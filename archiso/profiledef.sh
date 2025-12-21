#!/usr/bin/env bash
# ShedOS archiso profile definition
# shellcheck disable=SC2034

iso_name="shedos"
iso_label="SHEDOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="ShedOS <https://github.com/theshedman/shedos>"
iso_application="ShedOS Live/Install ISO"
iso_version="0.1.0"
install_dir="shedos"
buildmodes=('iso')
# Using syslinux for BIOS and GRUB for UEFI
bootmodes=('bios.syslinux' 'uefi.grub')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d/wheel"]="0:0:440"
  ["/opt/shedos-installer/"]="0:0:755"
  ["/usr/local/bin/shedos-installer"]="0:0:755"
  ["/usr/local/bin/shedos-install-limine"]="0:0:755"
  ["/usr/local/bin/shedos-welcome"]="0:0:755"
  ["/home/shedos/"]="1000:1000:755"
)
