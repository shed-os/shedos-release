#!/usr/bin/env bash
# build-iso.sh [<release-manifest.toml>]
#
# prepare-iso.sh, then mkarchiso over what it laid out, then the checksum the
# ISO is published beside.
#
# Same environment as prepare-iso.sh, plus:
#   SHEDOS_OUT_DIR    where the ISO lands (default out)
#   SHEDOS_WORK_DIR   mkarchiso's scratch tree (default <build>/work) — a
#                     runner whose workspace disk is smaller than the squashfs
#                     points this at the big volume
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")

MANIFEST=${1:-$ROOT/release-manifest.toml}
BUILD_DIR=${SHEDOS_BUILD_DIR:-$ROOT/build}
OUT_DIR=${SHEDOS_OUT_DIR:-$ROOT/out}
WORK_DIR=${SHEDOS_WORK_DIR:-$BUILD_DIR/work}

[[ $EUID -eq 0 ]] || { echo 'build-iso: must be run as root' >&2; exit 1; }
command -v mkarchiso > /dev/null || { echo 'build-iso: mkarchiso is not installed' >&2; exit 1; }

bash "$HERE/prepare-iso.sh" "$MANIFEST"

mkdir -p "$OUT_DIR" "$WORK_DIR"
printf '\n== mkarchiso\n'
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$BUILD_DIR"

shopt -s nullglob
isos=("$OUT_DIR"/shedos-*.iso)
shopt -u nullglob
(( ${#isos[@]} == 1 )) \
    || { echo "build-iso: expected one ISO in $OUT_DIR, found ${#isos[@]}" >&2; exit 1; }
iso=${isos[0]}

# Per-file .sha256 rather than one SHA256SUMS: the published layout is flat and
# a shared file would be overwritten by whichever ISO was uploaded last.
( cd "$OUT_DIR" && sha256sum "$(basename "$iso")" > "$(basename "$iso").sha256" )

printf '\nbuild-iso: %s (%s)\n' "$iso" "$(numfmt --to=iec --suffix=B "$(stat -c %s "$iso")")"
cat "$iso.sha256"
