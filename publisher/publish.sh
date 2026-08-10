#!/usr/bin/env bash
# publish.sh <payload.json> <artifact-dir>
#
# The single writer of the ShedOS package channels. A package repo builds and
# asks; this is where the signing key and the bucket credentials live, so this
# is where the asking gets checked. Nothing is signed until the request has
# cleared the allowlist, the checksums, the trusted-key gate, the keyring gate
# and the version gate, and nothing already in the channel is ever deleted.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
# shellcheck source=publisher/lib-channel.sh
source "$HERE/lib-channel.sh"

KEYRING_PKG=shedos-keyring
KEYRING_DIR=usr/share/pacman/keyrings

(( $# == 2 )) || die 'usage: publish.sh <payload.json> <artifact-dir>'
payload=$1
artifact=$2
[[ -f $payload ]] || die "payload $payload does not exist"
[[ -d $artifact ]] || die "artifact directory $artifact does not exist"
: "${SHEDOS_BUCKET:?SHEDOS_BUCKET is not set}"
: "${GPG_FP:?GPG_FP is not set}"

# The exclusion lists are overridable so a suite can exercise a refusal without
# editing the shipped lists. The allowlist is not.
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

# --- 4. what the incoming packages call themselves --------------------------

# Read once, from the package rather than the file name: the keyring lookup
# and the version gate both need it, and this is what repo-add will record.
incoming=$(
    for file in "${files[@]}"; do
        info=$(bsdtar -xOqf "$artifact/$file" .PKGINFO) \
            || die "could not read the package metadata in $file"
        awk -F' = ' -v f="$file" \
            '$1 == "pkgname" { n = $2 } $1 == "pkgver" { v = $2 }
             END { if (n == "" || v == "") exit 1; print f "\t" n "\t" v }' \
            <<<"$info" || die "$file names no package or version"
    done
)

# --- 5. pull the channel db -------------------------------------------------

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

# One record per line: name, version, file, sha256. Unpacked to a directory
# rather than read as a stream so a record ends where its file does.
published=
if [[ -f $work/shedos.db.tar.gz ]]; then
    mkdir "$work/db"
    bsdtar -xf "$work/shedos.db.tar.gz" -C "$work/db" \
        || die 'could not read the channel database'
    shopt -s nullglob
    descs=("$work"/db/*/desc)
    shopt -u nullglob
    if (( ${#descs[@]} )); then
        published=$(awk '
            FNR == 1 && NR > 1 { print n "\t" v "\t" f "\t" s; n=""; v=""; f=""; s="" }
            /^%NAME%$/      { getline n }
            /^%VERSION%$/   { getline v }
            /^%FILENAME%$/  { getline f }
            /^%SHA256SUM%$/ { getline s }
            END { if (NR) print n "\t" v "\t" f "\t" s }
        ' "${descs[@]}")
    fi
fi

# --- 6. the trust files come out of the published keyring -------------------

# The fingerprint list this gate reads and the shedos.gpg republished at the
# channel root are the same two files the fleet installs from shedos-keyring,
# taken from the channel's own copy of that package. Trusting a key the fleet
# does not is then not a thing the publisher can do. The overrides stay for
# the harness and for a channel whose keyring has to be worked around.
if [[ -n ${SHEDOS_TRUSTED_KEYS_FILE:-} ]]; then
    trusted=$SHEDOS_TRUSTED_KEYS_FILE
    [[ -f $trusted ]] || die "trusted-keys file $trusted does not exist"
fi
if [[ -n ${SHEDOS_KEYRING_GPG_FILE:-} ]]; then
    keyring=$SHEDOS_KEYRING_GPG_FILE
    [[ -f $keyring ]] || die "keyring $keyring does not exist"
fi

if [[ -z ${trusted:-} || -z ${keyring:-} ]]; then
    entry=$(awk -F'\t' -v n="$KEYRING_PKG" '$1 == n { print; exit }' <<<"$published")
    if [[ -n $entry ]]; then
        IFS=$'\t' read -r _ version file sum <<<"$entry"
        mkdir "$work/channel"
        channel_get "$file" "$work/channel/$file"
        got=$(sha256sum "$work/channel/$file" | cut -d' ' -f1)
        [[ $got == "$sum" ]] \
            || die "the channel's $file does not match the sha256 its database records"
        pkg=$work/channel/$file
        origin='from the channel'
    else
        # The first publish into an empty channel has no keyring to read, so
        # it may only come from the request that is bringing one.
        entry=$(awk -F'\t' -v n="$KEYRING_PKG" '$2 == n { print; exit }' <<<"$incoming")
        [[ -n $entry ]] \
            || die "the channel holds no $KEYRING_PKG and this request brings none"
        IFS=$'\t' read -r file _ version <<<"$entry"
        pkg=$artifact/$file
        origin='from this request'
    fi
    echo "trust source: $KEYRING_PKG $version $origin"
    mkdir "$work/keys"
    for name in shedos-trusted shedos.gpg; do
        bsdtar -xOqf "$pkg" "$KEYRING_DIR/$name" > "$work/keys/$name" \
            || die "the $KEYRING_PKG package holds no $name"
    done
    trusted=${trusted:-$work/keys/shedos-trusted}
    keyring=${keyring:-$work/keys/shedos.gpg}
fi

# --- 7. the key doing the signing must be one the fleet trusts --------------

uncommented "$trusted" | grep -qxF "$GPG_FP" \
    || die "signing key $GPG_FP is not on the trusted-keys list"

# --- 8. the bootstrap keyring must hold that same key -----------------------

# A box migrating from Arch fetches this keyring before it has any ShedOS
# package, so it is the only thing standing between it and an unverifiable
# repo. Publishing one that doesn't hold the key we are about to sign with
# would strand exactly that box.
keyring_keys=$(gpg --show-keys --with-colons "$keyring" 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10 }') || die "could not read $keyring as a keyring"
grep -qxF "$GPG_FP" <<<"$keyring_keys" \
    || die "the keyring does not hold the signing key $GPG_FP"

# --- 9. a published package may not go backwards ----------------------------

# repo-add writes whatever it is handed, in either direction, so rerunning an
# old build would walk the channel back a version and every box that already
# took the newer one would be offered a downgrade. Republishing the same
# version is still fine; that is a rebuild of what is already there.
if [[ -n $published ]]; then
    while IFS=$'\t' read -r _ name version; do
        have=$(awk -F'\t' -v n="$name" '$1 == n { print $2; exit }' <<<"$published")
        [[ -n $have ]] || continue
        if [[ $(vercmp "$version" "$have") -lt 0 ]]; then
            die "$name $version is older than the published $have"
        fi
    done <<<"$incoming"
fi

# --- 10. sign ---------------------------------------------------------------

for file in "${files[@]}"; do
    echo "sign $file"
    cp "$artifact/$file" "$work/$file"
    gpg --batch --yes --detach-sign --use-agent --no-armor \
        -u "$GPG_FP" --output "$work/$file.sig" "$work/$file"
done

# --- 9. fold the new packages into the channel db ---------------------------

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

# --- 10. upload, packages first ----------------------------------------------

# A box that pulls the db mid-publish must never see an entry whose file
# isn't up yet.
for file in "${files[@]}"; do
    channel_put "$work/$file" "$file"
    channel_put "$work/$file.sig" "$file.sig"
done
channel_put_root "$keyring" shedos.gpg
for name in shedos.db.tar.gz shedos.db.tar.gz.sig \
            shedos.files.tar.gz shedos.files.tar.gz.sig \
            shedos.db shedos.db.sig shedos.files shedos.files.sig; do
    channel_put "$work/$name" "$name"
done

# --- 11. mirror the db as [shedostest] so stable boxes can opt into the canary ---

for ext in db db.sig files files.sig; do
    channel_put "$work/shedos.$ext" "shedostest.$ext"
done

echo "published ${#files[@]} package(s) from $repo to $(channel_path '')"
