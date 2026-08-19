#!/usr/bin/env bash
# extract-package.sh <release-manifest.toml> <package> <into>
#
# One published package, unpacked. Everything that needs to read what a release
# ships reads it here: the boot harnesses that used to source shipped code out
# of a working tree, and the release checks that hold several packages'
# shipped copies against each other.
#
# A working tree and a published package are different things, and the second
# is the one a release is made of. A harness that proves the working tree works
# proves nothing about the ISO built beside it.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/lib-fetch.sh
source "$HERE/lib-fetch.sh"

(( $# == 3 )) || { echo 'usage: extract-package.sh <release-manifest.toml> <package> <into>' >&2; exit 2; }
manifest=$1
name=$2
into=$3
[[ -f $manifest ]] || { echo "extract: $manifest does not exist" >&2; exit 2; }

extract_manifest_package "$manifest" "$name" "$into" || exit 1
printf 'extracted %s into %s\n' "$name" "$into"
