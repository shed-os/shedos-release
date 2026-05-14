#!/usr/bin/env bash
# ShedOS archiso profile definition
# shellcheck disable=SC2034

iso_name="shedos"
iso_label="SHEDOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="ShedOS <https://github.com/Theshedman/shedos>"
iso_application="ShedOS Live/Install ISO"
# Substituted at build time by the Makefile from the repo-root VERSION file
# (the same CalVer scripts/bump-version.sh writes, so the ISO label and the
# packages on it agree). Edits made here by hand are clobbered on next build —
# bump VERSION, not this literal.
iso_version="@SHEDOS_VERSION@"
install_dir="shedos"
buildmodes=('iso')
# Using syslinux for BIOS and GRUB for UEFI
bootmodes=('bios.syslinux' 'uefi.grub')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d/calamares-live"]="0:0:440"
  ["/home/shedos/"]="1000:1000:755"
)
