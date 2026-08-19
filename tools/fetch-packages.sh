#!/usr/bin/env bash
# fetch-packages.sh <release-manifest.toml> <into>
#
# Every ShedOS package the release names, fetched from the channel into a
# directory the ISO build then makes a repository out of. This is what replaced
# building them: the ISO bakes the same signed bytes the fleet upgrades to,
# rather than a rebuild of the same source that happens to carry the same
# version.
#
# It fetches all or none. A package the channel serves at another version, or
# whose bytes do not hash to what the manifest wrote down, fails the run rather
# than leaving a directory that is nearly the release.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/lib-fetch.sh
source "$HERE/lib-fetch.sh"

(( $# == 2 )) || { echo 'usage: fetch-packages.sh <release-manifest.toml> <into>' >&2; exit 2; }
manifest=$1
into=$2
[[ -f $manifest ]] || { echo "fetch: $manifest does not exist" >&2; exit 2; }

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

# Into a staging directory first, so a run that refuses halfway leaves the
# destination as it found it rather than half a release.
fetch_manifest_packages "$manifest" "$staging"
rc=$?
if (( rc != 0 )); then
    echo 'fetch: no packages were written' >&2
    exit $rc
fi

mkdir -p "$into"
count=0
for file in "$staging"/*.pkg.tar.zst; do
    mv -- "$file" "$into/"
    count=$((count + 1))
done
printf '\n%d package(s) into %s\n' "$count" "$into"
