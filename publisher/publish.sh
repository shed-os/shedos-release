#!/usr/bin/env bash
# publish.sh <payload.json> <artifact-dir>
#
# The single writer of the ShedOS package channels. A package repo builds and
# asks; this is where the signing key and the bucket credentials live, so this
# is where the asking gets checked. Nothing is signed until the request has
# cleared the allowlist, the checksums and the trusted-key gate, and nothing
# already in the channel is ever deleted.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
# shellcheck source=publisher/lib-channel.sh
source "$HERE/lib-channel.sh"

MONOLITH_TRUSTED_KEYS=https://raw.githubusercontent.com/Theshedman/shedos/main/packaging/shedos-keyring/tree/shedos-trusted

(( $# == 2 )) || die 'usage: publish.sh <payload.json> <artifact-dir>'
payload=$1
artifact=$2
[[ -f $payload ]] || die "payload $payload does not exist"
[[ -d $artifact ]] || die "artifact directory $artifact does not exist"
: "${SHEDOS_BUCKET:?SHEDOS_BUCKET is not set}"
: "${GPG_FP:?GPG_FP is not set}"

# The exclusion lists are overridable so the harness can exercise a refusal
# without editing the shipped lists. The allowlist deliberately is not.
ALLOWLIST=$HERE/allowlist.txt
NOREPUBLISH=${SHEDOS_NOREPUBLISH_FILE:-$ROOT/packages/aur-norepublish.txt}
INSTALLER_ONLY=${SHEDOS_INSTALLER_ONLY_FILE:-$ROOT/packages/installer-only.txt}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

uncommented() { awk 'NF && $1 !~ /^#/' "$@"; }

# --- 1. the requesting repo must be one of ours -----------------------------

repo=$(jq -r '.repo // empty' "$payload") || die "$payload is not valid JSON"
[[ -n $repo ]] || die 'payload names no repo'
uncommented "$ALLOWLIST" | grep -qxF "$repo" \
    || die "$repo is not on the publisher allowlist"

# --- 2. every package must be the one the build hashed ----------------------

entries=$(jq -r '.packages[] | "\(.file) \(.sha256)"' "$payload") \
    || die 'payload has no usable package list'
[[ -n $entries ]] || die 'payload lists no packages'

files=()
while read -r file sum extra; do
    [[ -z $extra ]] || die "package entry '$file $sum $extra' has trailing junk"
    # A dispatch payload is only as trustworthy as the PAT that sent it, so
    # the file name has to be a plain package basename before it reaches gpg
    # or rclone.
    [[ $file =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*\.pkg\.tar\.zst$ ]] \
        || die "'$file' is not a package file name"
    [[ $sum =~ ^[0-9a-f]{64}$ ]] || die "'$file' has a malformed sha256"
    [[ -f $artifact/$file ]] || die "$file is not in the artifact"
    actual=$(sha256sum "$artifact/$file" | cut -d' ' -f1)
    [[ $actual == "$sum" ]] || die "$file does not match its payload sha256"
    files+=("$file")
done <<<"$entries"

# --- 3. some packages may never be republished under our signature ----------

mapfile -t excluded < <(uncommented "$NOREPUBLISH" "$INSTALLER_ONLY")
for file in "${files[@]}"; do
    pkgname=${file%-*-*-*.pkg.tar.zst}
    [[ $pkgname != *-debug ]] || die "$pkgname is a debug package"
    for name in "${excluded[@]}"; do
        [[ $pkgname != "$name" ]] || die "$pkgname is on the no-republish list"
    done
done

# --- 4. the key doing the signing must be one the fleet trusts --------------

if [[ -n ${SHEDOS_TRUSTED_KEYS_FILE:-} ]]; then
    trusted=$SHEDOS_TRUSTED_KEYS_FILE
    [[ -f $trusted ]] || die "trusted-keys file $trusted does not exist"
else
    echo "bootstrap: trusting the monolith's shedos-trusted"
    trusted=$work/shedos-trusted
    curl -fsSL "$MONOLITH_TRUSTED_KEYS" -o "$trusted" \
        || die 'could not fetch the trusted-keys list'
fi
uncommented "$trusted" | grep -qxF "$GPG_FP" \
    || die "signing key $GPG_FP is not on the trusted-keys list"

# --- 5. sign ----------------------------------------------------------------

for file in "${files[@]}"; do
    echo "sign $file"
    cp "$artifact/$file" "$work/$file"
    gpg --batch --yes --detach-sign --use-agent --no-armor \
        -u "$GPG_FP" --output "$work/$file.sig" "$work/$file"
done

# --- 6. fold the new packages into the channel db ---------------------------

present=$(channel_list)
in_channel() { grep -qxF "$1" <<<"$present"; }

# Only the archives: repo-add rewrites the materialized shedos.db /
# shedos.files as symlinks, and pulling those back down would just be a copy
# of the same bytes under another name.
if in_channel shedos.db.tar.gz; then
    channel_get shedos.db.tar.gz "$work/shedos.db.tar.gz"
    if in_channel shedos.db.tar.gz.sig; then
        channel_get shedos.db.tar.gz.sig "$work/shedos.db.tar.gz.sig"
    fi
    # The files db comes down too, or repo-add rebuilds one holding only what
    # this run brought and every earlier package drops out of pacman -F.
    if in_channel shedos.files.tar.gz; then
        channel_get shedos.files.tar.gz "$work/shedos.files.tar.gz"
    else
        echo 'the channel has a db but no files db; repo-add will make one'
    fi
    if in_channel shedos.files.tar.gz.sig; then
        channel_get shedos.files.tar.gz.sig "$work/shedos.files.tar.gz.sig"
    fi
else
    echo 'no db in the channel yet; starting a fresh one'
fi

(
    cd "$work"
    repo-add --sign --key "$GPG_FP" shedos.db.tar.gz "${files[@]}"
    # repo-add leaves these as symlinks and R2 has no symlinks, so give them
    # real bytes. rm first or cp sees src == dst.
    for name in shedos.db shedos.db.sig shedos.files shedos.files.sig; do
        if [[ -L $name ]]; then rm -f "$name"; fi
    done
    cp shedos.db.tar.gz shedos.db
    cp shedos.db.tar.gz.sig shedos.db.sig
    cp shedos.files.tar.gz shedos.files
    cp shedos.files.tar.gz.sig shedos.files.sig
)

# --- 7. upload, packages first ----------------------------------------------

# A box that pulls the db mid-publish must never see an entry whose file
# isn't up yet.
for file in "${files[@]}"; do
    channel_put "$work/$file" "$file"
    channel_put "$work/$file.sig" "$file.sig"
done
for name in shedos.db.tar.gz shedos.db.tar.gz.sig \
            shedos.files.tar.gz shedos.files.tar.gz.sig \
            shedos.db shedos.db.sig shedos.files shedos.files.sig; do
    channel_put "$work/$name" "$name"
done

# --- 8. mirror the db as [shedostest] so stable boxes can opt into the canary ---

for ext in db db.sig files files.sig; do
    channel_put "$work/shedos.$ext" "shedostest.$ext"
done

echo "published ${#files[@]} package(s) from $repo to $(channel_prefix)"
