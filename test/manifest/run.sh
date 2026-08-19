#!/usr/bin/env bash
# The release manifest and the two tools that touch it. The channel here is a
# directory of real files with a real signed database over them, and the
# package repositories are real git repositories with real tags, so the tools
# run against fixtures without a line of their own being swapped out: the same
# gpg, the same git, the same reads.
#
# What the packages hold does not matter to either tool — neither ever unpacks
# one — so the fixture packages are a few bytes each and the suite stays fast.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
RESOLVER=$ROOT/tools/resolve-manifest.sh
DRAFTER=$ROOT/tools/draft-manifest.sh
MANIFEST=$ROOT/release-manifest.toml

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
not() { ! "$@"; }

check() {
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

section() { printf '\n── %s\n' "$1"; }

# The line that follows another, for the drafted blocks where which value goes
# with which package is the whole point.
line_after() {
    awk -v want="$1" -v then="$2" '
        $0 == want { getline; if ($0 == then) found = 1 }
        END { exit !found }' "$3"
}

# --- the fixture channel ----------------------------------------------------

export GNUPGHOME=$WORK/gnupg
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-gen-key 'ShedOS manifest harness <harness@shedos.invalid>' \
    default default never > "$WORK/gpg.log" 2>&1
FP=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ { print $10; exit }')
if [[ -z $FP ]]; then
    echo 'could not generate a harness signing key:' >&2
    cat "$WORK/gpg.log" >&2
    exit 1
fi

# A second key the channel does not publish, for the database signed by
# something nobody asked to trust.
gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-gen-key 'ShedOS manifest decoy <decoy@shedos.invalid>' \
    default default never >> "$WORK/gpg.log" 2>&1
DECOY=$(gpg --list-keys --with-colons decoy@shedos.invalid \
    | awk -F: '/^fpr:/ { print $10; exit }')

CHANNEL=$WORK/channel
PKGS=$CHANNEL/test/x86_64
REPOS=$WORK/repos

# name, version, file, sha256 — one line per package the fixture channel serves.
ENTRIES=$WORK/entries.tsv

reset_channel() {
    rm -rf "$CHANNEL"
    mkdir -p "$PKGS"
    : > "$ENTRIES"
}

# $4 is the tree the publisher recorded the package as built from, $5 the
# commit it recorded the run at — the second is the parent of the first
# whenever the pipeline bumped pkgrel, and they are written independently so a
# case can put them at odds the way the pipeline really does.
serve() {
    local name=$1 version=$2 body=$3 build=${4:-} run=${5:-}
    local file=$name-$version-any.pkg.tar.zst
    printf '%s' "$body" > "$PKGS/$file"
    if [[ -n $build || -n $run ]]; then
        {
            printf 'repo shed-os/x\nrun 1\n'
            [[ -z $run ]] || printf 'commit %s\n' "$run"
            [[ -z $build ]] || printf 'build %s\n' "$build"
        } > "$PKGS/$file.origin"
    fi
    printf '%s\t%s\t%s\t%s\n' "$name" "$version" "$file" \
        "$(sha256sum "$PKGS/$file" | cut -d' ' -f1)" >> "$ENTRIES"
}

# The sha the fixture channel recorded for a package, which is what a manifest
# written against it has to carry.
served_sum() { awk -F'\t' -v n="$1" '$1 == n { print $4; exit }' "$ENTRIES"; }

# Build the database out of the entries and sign it. $1 overrides the signing
# key, which is how the untrusted-signature case is made.
seal_channel() {
    local key=${1:-$FP} name='' version='' file='' sum=''
    rm -rf "$WORK/dbroot"
    mkdir -p "$WORK/dbroot"
    while IFS=$'\t' read -r name version file sum; do
        mkdir -p "$WORK/dbroot/$name-$version"
        {
            printf '%%FILENAME%%\n%s\n\n' "$file"
            printf '%%NAME%%\n%s\n\n' "$name"
            printf '%%VERSION%%\n%s\n\n' "$version"
            printf '%%SHA256SUM%%\n%s\n' "$sum"
        } > "$WORK/dbroot/$name-$version/desc"
    done < "$ENTRIES"
    tar czf "$PKGS/shedos.db.tar.gz" -C "$WORK/dbroot" .
    rm -f "$PKGS/shedos.db.tar.gz.sig"
    gpg --batch --yes --detach-sign --no-armor -u "$key" \
        -o "$PKGS/shedos.db.tar.gz.sig" "$PKGS/shedos.db.tar.gz" 2>> "$WORK/gpg.log"
    gpg --export "$FP" > "$CHANNEL/shedos.gpg"
}

# --- the fixture repositories -----------------------------------------------

# The harness signs the database with a key of its own, so the fixture
# repositories must not reach for the one a workstation signs commits with.
git_in() {
    git -C "$1" -c user.email=harness@shedos.invalid -c user.name=harness \
        -c commit.gpgsign=false -c tag.gpgSign=false \
        -c tag.forceSignAnnotated=false "${@:2}"
}

# repo, path within it, pkgname, pkgver, pkgrel, and the source ref the
# PKGBUILD pins — 'tag' writes the #tag=$pkgver every ShedOS package writes,
# 'commit' and 'none' write the two shapes that carry no tag.
write_pkgbuild() {
    local repo=$1 path=$2 name=$3 pkgver=$4 pkgrel=$5 kind=${6:-tag}
    local dir=$REPOS/$repo
    if [[ ! -d $dir ]]; then
        mkdir -p "$dir"
        git_in "$dir" init -q .
    fi
    mkdir -p "$dir/$(dirname "$path")"
    {
        printf 'pkgname=%s\n' "$name"
        printf 'pkgver=%s\n' "$pkgver"
        printf 'pkgrel=%s\n' "$pkgrel"
        # The $pkgver and $_commit here belong in the file being written, not
        # in this shell: the tools have to expand them the way makepkg would.
        # shellcheck disable=SC2016
        case $kind in
            tag) printf 'source=("git+https://example.invalid/%s.git#tag=$pkgver")\n' "$repo" ;;
            commit) printf "_commit='%s'\n" "$(printf '0%.0s' {1..40})"
                    printf 'source=("git+https://example.invalid/%s.git#commit=$_commit")\n' "$repo" ;;
            none) printf 'source=("%s-$pkgver.tar.gz::https://example.invalid/x.tar.gz")\n' "$name" ;;
            *) ;;
        esac
    } > "$dir/$path"
    git_in "$dir" add -A
    git_in "$dir" commit -q -m "$name $pkgver-$pkgrel"
}

tag_repo() { git_in "$REPOS/$1" tag -a "$2" -m "$2"; }

reset_repos() {
    rm -rf "$REPOS"
    mkdir -p "$REPOS"
}

# --- the fixture manifest ---------------------------------------------------

# Written out longhand rather than through a builder, because a manifest a tool
# generated is exactly what the committed one must never be.
write_manifest() {
    local out=$1
    shift
    {
        printf '[release]\nversion = "%s"\n' "${MANIFEST_VERSION:-2026.08.09}"
        while (( $# )); do
            IFS=, read -r name repo ref pkgver pkgrel sum <<<"$1"
            printf '\n[[package]]\nname = "%s"\nrepo = "%s"\nref = "%s"\n' \
                "$name" "$repo" "$ref"
            printf 'pkgver = "%s"\npkgrel = "%s"\nsha256 = "%s"\n' \
                "$pkgver" "$pkgrel" "$sum"
            shift
        done
    } > "$out"
}

with_fixture() {
    SHEDOS_MANIFEST_CHANNEL=$PKGS \
    SHEDOS_MANIFEST_CHANNEL_ROOT=$CHANNEL \
    SHEDOS_MANIFEST_REPO_BASE=$REPOS \
    "$@" > "$WORK/last.out" 2>&1
}

resolve() { with_fixture bash "$RESOLVER" "$@"; }

# The whole fixture in its healthy state: one repository holding one package,
# one holding two, and a channel serving all three.
reset_fixture() {
    reset_channel
    reset_repos

    write_pkgbuild alpha PKGBUILD alpha 1.0 1
    tag_repo alpha 1.0

    write_pkgbuild multi one/PKGBUILD beta 2.0 1
    write_pkgbuild multi two/PKGBUILD gamma 2.0 1
    tag_repo multi 2.0

    serve alpha 1.0-1 'the alpha package'
    serve beta 2.0-2 'the beta package'
    serve gamma 2.0-1 'the gamma package'
    seal_channel

    write_manifest "$WORK/manifest.toml" \
        "alpha,alpha,1.0,1.0,1,$(served_sum alpha)" \
        "beta,multi,2.0,2.0,2,$(served_sum beta)" \
        "gamma,multi,2.0,2.0,1,$(served_sum gamma)"
}

# --- case 1: the pins hold --------------------------------------------------

section 'case 1 — a manifest whose pins all hold resolves'
reset_fixture
resolve "$WORK/manifest.toml"
rc=$?
check 'the resolver passes' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it says how many pins it checked' grep -qx 'all 3 pin(s) hold' "$WORK/last.out"
check 'it names the release' grep -qx 'release 2026.08.09' "$WORK/last.out"
check 'it names every package it cleared' \
    grep -qx 'ok beta 2.0-2 from multi 2.0' "$WORK/last.out"
# beta is published at pkgrel 2 while the tag still holds 1: the pipeline moves
# pkgrel past what the channel carries and the tag does not follow.
check 'a tag behind the published pkgrel is not a failure' \
    not grep -q 'pkgrel' "$WORK/last.out"

# --- case 2: the sha does not match -----------------------------------------

section 'case 2 — a manifest sha the channel does not record is refused'
reset_fixture
write_manifest "$WORK/manifest.toml" \
    "alpha,alpha,1.0,1.0,1,$(printf 'a%.0s' {1..64})" \
    "beta,multi,2.0,2.0,2,$(served_sum beta)" \
    "gamma,multi,2.0,2.0,1,$(served_sum gamma)"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it names the entry and the axis' \
    grep -q '^alpha: channel: the database records' "$WORK/last.out"
check 'it names the sha the channel has' \
    grep -q "$(served_sum alpha)" "$WORK/last.out"
check 'the entries beside it still pass' grep -q '^ok beta ' "$WORK/last.out"
check 'and the count is of the pins that failed' \
    grep -qx '1 of 3 pin(s) did not hold' "$WORK/last.out"

section 'case 2b — a package whose bytes moved under a database that still agrees'
reset_fixture
# The database keeps the sha the manifest carries; only the file changes. A
# check that read the database and stopped would call this green.
printf 'something else entirely' > "$PKGS/alpha-1.0-1-any.pkg.tar.zst"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it names the entry and the bytes axis' \
    grep -q '^alpha: bytes: alpha-1.0-1-any.pkg.tar.zst hashes to' "$WORK/last.out"
check 'the channel axis is silent, because the database still agrees' \
    not grep -q '^alpha: channel:' "$WORK/last.out"

# --- case 3: the tag is not there -------------------------------------------

section 'case 3 — a tag the repository does not carry is refused'
reset_fixture
write_manifest "$WORK/manifest.toml" \
    "alpha,alpha,1.1,1.0,1,$(served_sum alpha)" \
    "beta,multi,2.0,2.0,2,$(served_sum beta)" \
    "gamma,multi,2.0,2.0,1,$(served_sum gamma)"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it names the entry, the axis and the ref' \
    grep -qx 'alpha: ref: alpha carries no tag 1.1' "$WORK/last.out"

section 'case 3b — a repository that cannot be read is not a missing tag'
reset_fixture
write_manifest "$WORK/manifest.toml" \
    "alpha,nowhere,1.0,1.0,1,$(served_sum alpha)"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it says the repository could not be read' \
    grep -qx 'alpha: ref: nowhere could not be read' "$WORK/last.out"

section 'case 3c — a branch sharing the tag name does not stand in for the tag'
reset_fixture
# git clone --branch takes a branch of that name in preference to the tag, and
# a repository carrying both would otherwise be read at the wrong tree
# entirely. This one moves on past the tag and then names the new commit 1.0.
write_pkgbuild alpha PKGBUILD alpha 9.9 1
git_in "$REPOS/alpha" branch 1.0
resolve "$WORK/manifest.toml"
check 'the resolver fails rather than reading the branch' test "$?" -eq 1
check 'and it says it is the tag it could not get' \
    grep -qx 'alpha: ref: alpha at 1.0 could not be read as tag 1.0' "$WORK/last.out"
check 'nothing off the branch is reported as though it were the tag' \
    not grep -q '9\.9' "$WORK/last.out"

section 'case 3d — a commit ref resolves against the commit rather than a tag'
reset_channel
reset_repos
write_pkgbuild solo PKGBUILD solo 1.0 1 checkout
built_at=$(git_in "$REPOS/solo" rev-parse HEAD)
# The branch moves on afterwards, which is the whole point of pinning a commit:
# what the manifest names is the tree the package was built from, not whatever
# the repository holds now.
write_pkgbuild solo PKGBUILD solo 2.0 1 checkout
serve solo 1.0-1 'the solo package'
seal_channel
write_manifest "$WORK/manifest.toml" "solo,solo,$built_at,1.0,1,$(served_sum solo)"
resolve "$WORK/manifest.toml"
rc=$?
check 'the resolver passes' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it names the commit it resolved from' \
    grep -qx "ok solo 1.0-1 from solo $built_at" "$WORK/last.out"

section 'case 3e — a commit the repository does not carry is refused'
reset_fixture
missing_commit=$(printf 'b%.0s' {1..40})
write_manifest "$WORK/manifest.toml" \
    "alpha,alpha,$missing_commit,1.0,1,$(served_sum alpha)"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it names the entry, the axis and the commit' \
    grep -qx "alpha: ref: alpha carries no commit $missing_commit" "$WORK/last.out"

section 'case 3f — a commit that built another release is refused'
reset_channel
reset_repos
write_pkgbuild solo PKGBUILD solo 1.0 1 checkout
older=$(git_in "$REPOS/solo" rev-parse HEAD)
write_pkgbuild solo PKGBUILD solo 1.0 2 checkout
serve solo 1.0-2 'the solo package'
seal_channel
# A tag is allowed to sit behind the published release; a commit is not, because
# a commit names the tree the package came out of.
write_manifest "$WORK/manifest.toml" "solo,solo,$older,1.0,2,$(served_sum solo)"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it names the pkgrel axis and both releases' \
    grep -qx "solo: pkgrel: solo at $older is at pkgrel 1 rather than the published 2" \
    "$WORK/last.out"

# --- case 4: the channel does not serve it ----------------------------------

section 'case 4 — a package the channel does not serve is refused'
reset_fixture
write_manifest "$WORK/manifest.toml" \
    "alpha,alpha,1.0,1.0,1,$(served_sum alpha)" \
    "delta,alpha,1.0,1.0,1,$(served_sum alpha)"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it names the entry and the axis' \
    grep -qx 'delta: channel: the channel serves no delta' "$WORK/last.out"

# --- case 5: the version does not match -------------------------------------

section 'case 5 — a version the channel has moved past is refused'
reset_fixture
write_manifest "$WORK/manifest.toml" \
    "beta,multi,2.0,2.0,1,$(served_sum beta)"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it names both versions' \
    grep -qx 'beta: channel: the channel serves beta 2.0-2 rather than 2.0-1' "$WORK/last.out"

section 'case 5b — a pkgver the tag does not build is refused'
reset_fixture
write_manifest "$WORK/manifest.toml" \
    "alpha,alpha,1.0,9.9,1,$(served_sum alpha)"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it names the pkgver axis and what the tag builds' \
    grep -qx 'alpha: pkgver: alpha at 1.0 builds 1.0 rather than 9.9' "$WORK/last.out"

section 'case 5c — a tag ahead of the release the channel serves is refused'
reset_channel
reset_repos
write_pkgbuild alpha PKGBUILD alpha 1.0 5
tag_repo alpha 1.0
serve alpha 1.0-2 'the alpha package'
seal_channel
write_manifest "$WORK/manifest.toml" "alpha,alpha,1.0,1.0,2,$(served_sum alpha)"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it names the pkgrel axis and both releases' \
    grep -qx 'alpha: pkgrel: alpha at 1.0 is at pkgrel 5 ahead of the published 2' \
    "$WORK/last.out"

section 'case 5d — a tag that builds no package of that name is refused'
reset_fixture
write_manifest "$WORK/manifest.toml" \
    "alpha,multi,2.0,1.0,1,$(served_sum alpha)"
resolve "$WORK/manifest.toml"
check 'the resolver fails' test "$?" -eq 1
check 'it names the pkgbuild axis' \
    grep -qx 'alpha: pkgbuild: multi at 2.0 builds no package called alpha' "$WORK/last.out"

# --- case 6: the database has to be signed ----------------------------------

section 'case 6 — a database signed by a key the channel does not publish is not read'
reset_fixture
seal_channel "$DECOY"
resolve "$WORK/manifest.toml"
check 'the resolver stops rather than failing pins' test "$?" -eq 2
check 'it says why' \
    grep -qx 'the channel database is not signed by the key the channel publishes' \
    "$WORK/last.out"
check 'and no pin is reported either way' not grep -q '^ok \|did not hold' "$WORK/last.out"

section 'case 6b — a database with no signature at all is not read'
reset_fixture
rm -f "$PKGS/shedos.db.tar.gz.sig"
resolve "$WORK/manifest.toml"
check 'the resolver stops' test "$?" -eq 2
check 'it says the signature is missing' \
    grep -qx 'the channel database carries no signature' "$WORK/last.out"

section 'case 6c — a channel that cannot be read is not an empty channel'
reset_fixture
rm -f "$PKGS/shedos.db.tar.gz"
resolve "$WORK/manifest.toml"
check 'the resolver stops' test "$?" -eq 2
check 'it says the database could not be read' \
    grep -qx 'could not read the channel database' "$WORK/last.out"

# --- case 7: the manifest itself --------------------------------------------

section 'case 7 — a manifest the tool only half understands is refused'
reset_fixture

bad_manifest() { printf '%s\n' "$1" > "$WORK/bad.toml"; resolve "$WORK/bad.toml"; }

bad_manifest '[release]
version = "2026.08.09"

[[package]]
name = "alpha"
repo = "alpha"
ref = "1.0"
pkgver = "1.0"
pkgrel = "1"
sha256 = "'"$(served_sum alpha)"'"
branch = "main"'
check 'a key nobody recognises stops the run' test "$?" -eq 2
check 'and it names the key and the entry' \
    grep -qx "package 'alpha' holds an unknown key 'branch'" "$WORK/last.out"

bad_manifest '[release]
version = "2026.08.09"

[[package]]
name = "alpha"
repo = "alpha"
pkgver = "1.0"
pkgrel = "1"
sha256 = "'"$(served_sum alpha)"'"'
check 'an entry short of a field stops the run' test "$?" -eq 2
check 'and it names the field' grep -qx "package 'alpha' names no ref" "$WORK/last.out"

bad_manifest '[release]
version = "2026.08.09"

[[package]]
name = "alpha"
repo = "alpha"
ref = "1.0"
pkgver = "1.0"
pkgrel = "1"
sha256 = "deadbeef"'
check 'a sha256 that is not one stops the run' test "$?" -eq 2
check 'and it says which value' \
    grep -qx "package 'alpha' sha256 'deadbeef' is not shaped like a sha256" "$WORK/last.out"

bad_manifest '[release]
version = "2026.08.09"

[[package]]
name = "alpha"
repo = "shed-os/alpha"
ref = "1.0"
pkgver = "1.0"
pkgrel = "1"
sha256 = "'"$(served_sum alpha)"'"'
check 'a repo written with its organisation stops the run' test "$?" -eq 2
check 'and it says the value is not a repo' \
    grep -qx "package 'alpha' repo 'shed-os/alpha' is not shaped like a repo" "$WORK/last.out"

bad_manifest '[release]
version = "2026.08.09"

[[package]]
name = "alpha"
repo = "alpha"
ref = "1.0"
pkgver = "1.0"
pkgrel = "1"
sha256 = "'"$(served_sum alpha)"'"

[[package]]
name = "alpha"
repo = "alpha"
ref = "1.0"
pkgver = "1.0"
pkgrel = "1"
sha256 = "'"$(served_sum alpha)"'"'
check 'a package written twice stops the run' test "$?" -eq 2
check 'and it says which' grep -qx 'the manifest names alpha twice' "$WORK/last.out"

bad_manifest '[release]
version = "next"

[[package]]
name = "alpha"
repo = "alpha"
ref = "1.0"
pkgver = "1.0"
pkgrel = "1"
sha256 = "'"$(served_sum alpha)"'"'
check 'a release version that is not one stops the run' test "$?" -eq 2
check 'and it says so' \
    grep -qxF "[release] version 'next' is not a release version" "$WORK/last.out"

bad_manifest '[release]
version = "2026.08.09"'
check 'a manifest naming no packages stops the run' test "$?" -eq 2
check 'and it says so' grep -qx 'the manifest names no packages' "$WORK/last.out"

section 'case 7b — a release candidate is a release version'
reset_fixture
MANIFEST_VERSION=2026.08.09-rc1 write_manifest "$WORK/manifest.toml" \
    "alpha,alpha,1.0,1.0,1,$(served_sum alpha)"
resolve "$WORK/manifest.toml"
rc=$?
check 'the resolver passes' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'and names it' grep -qx 'release 2026.08.09-rc1' "$WORK/last.out"

# --- case 8: what the manifest leaves out -----------------------------------

section 'case 8 — a package the channel serves and the manifest does not name is a note'
reset_fixture
write_manifest "$WORK/manifest.toml" "alpha,alpha,1.0,1.0,1,$(served_sum alpha)"
resolve "$WORK/manifest.toml"
rc=$?
check 'it is not a failure, because a channel keeps what a release retired' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it is said out loud' \
    grep -qx 'note: the channel serves beta which the manifest does not name' "$WORK/last.out"
check 'and the package the manifest does name is not noted' \
    not grep -qx 'note: the channel serves alpha which the manifest does not name' \
    "$WORK/last.out"

# --- case 9: the drafter ----------------------------------------------------

section 'case 9 — the drafter will not draft from a database it cannot verify'
reset_fixture
printf 'shed-os/alpha\nshed-os/multi\n' > "$WORK/allowlist.txt"
seal_channel "$DECOY"
SHEDOS_MANIFEST_ALLOWLIST=$WORK/allowlist.txt with_fixture bash "$DRAFTER" 2026.08.09
check 'the drafter stops' test "$?" -eq 2
check 'it says why' \
    grep -qx 'the channel database is not signed by the key the channel publishes' \
    "$WORK/last.out"
check 'and it drafts nothing' not grep -q '\[\[package\]\]' "$WORK/last.out"

section 'case 10 — the drafter fills what the repositories can answer'
reset_fixture
SHEDOS_MANIFEST_ALLOWLIST=$WORK/allowlist.txt with_fixture bash "$DRAFTER" 2026.08.09
rc=$?
check 'a channel every package has a tag for drafts complete' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it takes the version and the release from the channel' \
    grep -qx 'pkgver = "2.0"' "$WORK/last.out"
check 'it takes the repository from whichever one builds the package' \
    line_after 'name = "gamma"' 'repo = "multi"' "$WORK/last.out"
check 'it takes the tag from the source the PKGBUILD pins' \
    grep -qx 'ref = "2.0"' "$WORK/last.out"
check 'it takes the sha from the database' \
    grep -qx "sha256 = \"$(served_sum alpha)\"" "$WORK/last.out"

# What it drafts has to be what the resolver reads, or the assistance is worth
# nothing: this is the same fixture round-tripped.
grep -v '^drafted ' "$WORK/last.out" > "$WORK/drafted.toml"
resolve "$WORK/drafted.toml"
rc=$?
check 'and what it drafted resolves' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"

section 'case 10b — a suite fixture is not a package the channel serves'
# A repository that publishes a package and also holds package fixtures under
# its suite. shedos-release is exactly that: it builds the metapackage, and its
# publisher harness builds a fixture called shedos-keyring because that is the
# name the keyring gate is about. Reading fixtures as packages makes two
# repositories claim one name, and the drafter then refuses to draft anything
# at all — the whole manifest, over a file nobody publishes.
reset_fixture
write_pkgbuild multi test/publisher/fixtures/alpha/PKGBUILD alpha 9.9 1
SHEDOS_MANIFEST_ALLOWLIST=$WORK/allowlist.txt with_fixture bash "$DRAFTER" 2026.08.09
rc=$?
check 'the draft still happens' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'nothing is reported as built twice' \
    not grep -q 'both build alpha' "$WORK/last.out"
check 'and the real repository still owns the name' \
    line_after 'name = "alpha"' 'repo = "alpha"' "$WORK/last.out"

section 'case 11 — a package pinning no tag is placed by the commit it was built at'
reset_channel
reset_repos
write_pkgbuild pinned PKGBUILD pinned 1.0 1 commit
write_pkgbuild loose PKGBUILD loose 1.0 1 none
write_pkgbuild bare PKGBUILD bare 1.0 1 checkout
pinned_commit=$(git_in "$REPOS/pinned" rev-parse HEAD)
serve pinned 1.0-1 'pinned'
serve loose 1.0-1 'loose'
serve bare 1.0-1 'bare'
serve orphan 1.0-1 'orphan'
seal_channel
printf 'shed-os/pinned\nshed-os/loose\nshed-os/bare\n' > "$WORK/allowlist.txt"
SHEDOS_MANIFEST_ALLOWLIST=$WORK/allowlist.txt with_fixture bash "$DRAFTER" 2026.08.09
check 'the drafter still fails, for the package no repository builds' test "$?" -eq 1
check 'it derives the ref from the commit the release was built at' \
    grep -qx "ref = \"$pinned_commit\"" "$WORK/last.out"
check 'and it says the derivation is a derivation' \
    grep -qx "# derived: the one commit on pinned whose PKGBUILD says 1.0-1" "$WORK/last.out"
check 'a source pinned to a commit says the pin is the fork, not the tree' \
    grep -qx '# its source pins 0000000000000000000000000000000000000000, which is the fork rather than this tree' \
    "$WORK/last.out"
check 'a source pinning no ref says that' \
    grep -qx '# it builds from a source that names no ref' "$WORK/last.out"
check 'a package with no source at all says that' \
    grep -qx '# it builds from the checkout and declares no source' "$WORK/last.out"
check 'and every derived entry says why it had to be derived' \
    test "$(grep -c '^# this release predates the publisher recording what it was asked' \
        "$WORK/last.out")" = 3
check 'a package no listed repository builds is still a hole' \
    grep -qx '# repo: no repository on the publisher allowlist builds this' "$WORK/last.out"
check 'and that is the only field it could not fill' \
    grep -qx 'drafted 4 package(s) with 2 field(s) this could not fill' "$WORK/last.out"

# What it derived has to resolve, or the derivation is decoration.
grep -v '^drafted ' "$WORK/last.out" | grep -v 'no repository on the publisher' > "$WORK/derived.toml"
python3 - "$WORK/derived.toml" <<'PYEOF'
import re, sys
path = sys.argv[1]
text = open(path).read()
blocks = text.split('[[package]]')
keep = [b for b in blocks[1:] if 'name = "orphan"' not in b]
open(path, 'w').write(blocks[0] + '[[package]]'.join([''] + keep))
PYEOF
resolve "$WORK/derived.toml"
rc=$?
check 'and the derived refs resolve' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"

section 'case 11b — a recorded build tree is used in preference to a derived one'
reset_channel
reset_repos
write_pkgbuild bare PKGBUILD bare 1.0 1 checkout
first=$(git_in "$REPOS/bare" rev-parse HEAD)
# A second commit touching the PKGBUILD at the same release, so the branch
# alone cannot say which of the two the package was built at. What the
# publisher recorded is the only thing that knows.
write_pkgbuild bare PKGBUILD bare 1.0 1 none
serve bare 1.0-1 'bare' "$first"
seal_channel
printf 'shed-os/bare\n' > "$WORK/allowlist.txt"
SHEDOS_MANIFEST_ALLOWLIST=$WORK/allowlist.txt with_fixture bash "$DRAFTER" 2026.08.09
rc=$?
check 'the draft is complete' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it takes the tree the publisher recorded' \
    grep -qx "ref = \"$first\"" "$WORK/last.out"
check 'and says so rather than calling it derived' \
    grep -qx '# the tree the publisher recorded this package as built from' "$WORK/last.out"
check 'it does not also claim to have derived it' \
    not grep -q '^# derived:' "$WORK/last.out"
check 'and it says the record was checked rather than trusted' \
    grep -qx '# checked against 1.0-1 rather than taken on trust' "$WORK/last.out"

# The drafting cases all round-trip, or the assistance is worth nothing — and
# this is the one that did not, which is how a recorded ref the resolver must
# refuse got shipped.
grep -v '^drafted ' "$WORK/last.out" | grep -v '^draft: ' > "$WORK/recorded.toml"
resolve "$WORK/recorded.toml"
rc=$?
check 'and what it drafted resolves' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"

# The same channel without the record, to show the ambiguity was real and that
# the drafter says so rather than picking quietly.
rm -f "$PKGS"/bare-1.0-1-any.pkg.tar.zst.origin
SHEDOS_MANIFEST_ALLOWLIST=$WORK/allowlist.txt with_fixture bash "$DRAFTER" 2026.08.09
check 'without the record the draft is not complete' test "$?" -eq 1
check 'and it says the branch cannot choose between them' \
    grep -qx '# ref: 2 commits on bare build bare at 1.0-1 and this took the newest' \
    "$WORK/last.out"

section 'case 11c — a recorded commit that built another release is discarded'
reset_channel
reset_repos
# Exactly the shape the pipeline makes: the run is triggered at one commit, the
# pkgrel guard bumps and commits, and the build happens on top of that. A
# release pinning the commit the run started at names a tree carrying the
# pkgrel before the bump.
write_pkgbuild bumped PKGBUILD bumped 1.0 1 checkout
triggered_at=$(git_in "$REPOS/bumped" rev-parse HEAD)
write_pkgbuild bumped PKGBUILD bumped 1.0 2 checkout
built_at=$(git_in "$REPOS/bumped" rev-parse HEAD)
serve bumped 1.0-2 'bumped' '' "$triggered_at"
seal_channel
printf 'shed-os/bumped\n' > "$WORK/allowlist.txt"
SHEDOS_MANIFEST_ALLOWLIST=$WORK/allowlist.txt with_fixture bash "$DRAFTER" 2026.08.09
rc=$?
check 'the draft is still complete' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'the recorded commit is not written down' \
    not grep -qx "ref = \"$triggered_at\"" "$WORK/last.out"
check 'the branch answers instead' grep -qx "ref = \"$built_at\"" "$WORK/last.out"
check 'and the discard is said out loud' \
    grep -q "the recorded commit $triggered_at does not build 1.0-2" "$WORK/last.out"

grep -v '^drafted ' "$WORK/last.out" | grep -v '^draft: ' > "$WORK/discarded.toml"
resolve "$WORK/discarded.toml"
rc=$?
check 'and what it drafted resolves' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"

section 'case 11d — the build tree wins over the run commit when both are there'
reset_channel
reset_repos
write_pkgbuild pair PKGBUILD pair 1.0 1 checkout
pair_triggered=$(git_in "$REPOS/pair" rev-parse HEAD)
write_pkgbuild pair PKGBUILD pair 1.0 2 checkout
pair_built=$(git_in "$REPOS/pair" rev-parse HEAD)
serve pair 1.0-2 'pair' "$pair_built" "$pair_triggered"
seal_channel
printf 'shed-os/pair\n' > "$WORK/allowlist.txt"
SHEDOS_MANIFEST_ALLOWLIST=$WORK/allowlist.txt with_fixture bash "$DRAFTER" 2026.08.09
rc=$?
check 'the draft is complete' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'the tree it was built from is the ref' \
    grep -qx "ref = \"$pair_built\"" "$WORK/last.out"
check 'and nothing is discarded, because the right field was read first' \
    not grep -q 'does not build' "$WORK/last.out"

section 'case 12 — the release version is the author'"'"'s and the drafter says so'
reset_fixture
printf 'shed-os/alpha\nshed-os/multi\n' > "$WORK/allowlist.txt"
SHEDOS_MANIFEST_ALLOWLIST=$WORK/allowlist.txt with_fixture bash "$DRAFTER"
check 'a draft with no version given is not finished' test "$?" -eq 1
check 'and it says which field it left' \
    grep -q '^# version: the release names itself' "$WORK/last.out"

section 'case 12b — a channel read that does not answer is tried again'
# Resolving the whole manifest is fifty-odd reads of one host and the committed
# manifest is checked on every push, so one 503 among them must not be a red
# release check. A stub curl is what makes that checkable on demand.
CURL_STUB=$WORK/bin
mkdir -p "$CURL_STUB"
cat > "$CURL_STUB/curl" <<'STUBEOF'
#!/usr/bin/env bash
n=$(cat "$CURL_STUB_COUNT" 2> /dev/null || echo 0)
n=$((n + 1))
printf '%s' "$n" > "$CURL_STUB_COUNT"
for ((i = 1; i <= $#; i++)); do
    [[ ${!i} == -o ]] || continue
    j=$((i + 1))
    printf 'the body
' > "${!j}"
done
read -r -a codes <<< "$CURL_STUB_CODES"
printf '%s' "${codes[$((n - 1))]:-${codes[-1]}}"
STUBEOF
chmod +x "$CURL_STUB/curl"

fetch_over_stub() {
    (
        export CURL_STUB_COUNT=$WORK/curl.count CURL_STUB_CODES=$1
        export SHEDOS_FETCH_PAUSE=0
        : > "$WORK/curl.count"
        PATH=$CURL_STUB:$PATH
        SHEDOS_MANIFEST_CHANNEL=https://example.invalid \
            bash -c 'source tools/lib-manifest.sh; channel_fetch "$CHANNEL_URL" thing "$1"' \
            _ "$WORK/fetched"
    )
}

fetch_over_stub '503 200'
check 'a read that answered 503 and then 200 succeeds' test "$?" -eq 0
fetch_over_stub '404'
check 'a 404 fails' test "$?" -ne 0
check 'and is not retried, because it is an answer' test "$(cat "$WORK/curl.count")" = 1
fetch_over_stub '503'
check 'a host that keeps failing still fails' test "$?" -ne 0
check 'after the attempts it is allowed' test "$(cat "$WORK/curl.count")" = 3

# --- case 13: the manifest as it stands -------------------------------------

section 'case 13 — the committed manifest resolves against the live channel'
if [[ ! -f $MANIFEST ]]; then
    printf '  SKIP no release-manifest.toml at the repository root\n'
else
    (
        unset SHEDOS_MANIFEST_CHANNEL SHEDOS_MANIFEST_CHANNEL_ROOT \
            SHEDOS_MANIFEST_REPO_BASE SHEDOS_MANIFEST_ALLOWLIST
        bash "$RESOLVER" "$MANIFEST"
    ) > "$WORK/last.out" 2>&1
    rc=$?
    check 'every pin in the committed manifest holds' test "$rc" -eq 0
    [[ $rc -eq 0 ]] || cat "$WORK/last.out"
fi

# --- result -----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
