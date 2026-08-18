# shellcheck shell=bash
# What the release manifest is, and how the two tools that touch it read the
# channel and the package repositories. Sourced, never run.
#
# The manifest is authored state: a person writes it and a person reviews it.
# draft-manifest.sh helps write one and resolve-manifest.sh checks one, and
# neither may quietly repair what it is handed.
#
# SHEDOS_MANIFEST_CHANNEL and SHEDOS_MANIFEST_CHANNEL_ROOT take a directory in
# place of the two channel URLs, and SHEDOS_MANIFEST_REPO_BASE takes one in
# place of GitHub, which is how the suite runs offline. The channel paths carry
# the same staging prefix publisher/lib-channel.sh writes to and have to move
# when CHANNEL_ROOT does.

CHANNEL_URL=${SHEDOS_MANIFEST_CHANNEL:-https://repo.shedos.org/staging/test/x86_64}
CHANNEL_ROOT_URL=${SHEDOS_MANIFEST_CHANNEL_ROOT:-https://repo.shedos.org/staging}
REPO_BASE=${SHEDOS_MANIFEST_REPO_BASE:-https://github.com/shed-os}

# shellcheck source=tools/lib-carve-maps.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-carve-maps.sh"

# --- the channel ------------------------------------------------------------

# A CDN node holds a database object for the best part of a day, and this repo
# has already been bitten by one: a copy one publish behind names a release the
# channel no longer serves. Every read here says no-cache and carries a query
# nothing has answered before.
channel_fetch() {
    local base=$1 name=$2 out=$3
    if [[ $base == http://* || $base == https://* ]]; then
        curl -fsSL --max-time 300 -A "$USER_AGENT" -H 'Cache-Control: no-cache' \
            -o "$out" "$base/$name?cb=$(date +%s)-$RANDOM"
    else
        cp -- "$base/$name" "$out"
    fi
}

# The database, its signature and the keyring the channel publishes, read into
# $1 and reduced to one "<name>\t<version>\t<file>\t<sha256>" line per package
# on stdout. Anything that cannot be verified is a refusal with a reason on
# stderr, never an empty answer: an empty answer here reads as "the channel
# serves nothing", which is what a manifest is checked against.
#
# What this proves is that the database was signed by a key the channel also
# publishes as shedos.gpg. Whether that key is one the fleet trusts is the
# trust-anchor suite's question, asked of the keyring package rather than here.
channel_database() {
    local work=$1 db=$1/shedos.db.tar.gz sig=$1/shedos.db.tar.gz.sig
    local keyring=$1/shedos.gpg

    channel_fetch "$CHANNEL_URL" shedos.db.tar.gz "$db" \
        || { echo 'could not read the channel database' >&2; return 1; }
    channel_fetch "$CHANNEL_URL" shedos.db.tar.gz.sig "$sig" \
        || { echo 'the channel database carries no signature' >&2; return 1; }
    channel_fetch "$CHANNEL_ROOT_URL" shedos.gpg "$keyring" \
        || { echo 'could not read the channel keyring' >&2; return 1; }

    local home=$work/gnupg
    mkdir -p "$home"
    chmod 700 "$home"
    if ! GNUPGHOME=$home gpg --batch --quiet --import "$keyring" 2> "$work/gpg.err"; then
        cat "$work/gpg.err" >&2
        echo 'the channel keyring could not be imported' >&2
        return 1
    fi
    if ! GNUPGHOME=$home gpg --batch --verify "$sig" "$db" 2> "$work/gpg.err"; then
        cat "$work/gpg.err" >&2
        echo 'the channel database is not signed by the key the channel publishes' >&2
        return 1
    fi

    mkdir -p "$work/db"
    bsdtar -xf "$db" -C "$work/db" \
        || { echo 'the channel database is not readable as a database' >&2; return 1; }

    shopt -s nullglob
    local descs=("$work"/db/*/desc)
    shopt -u nullglob
    (( ${#descs[@]} )) || { echo 'the channel database holds no packages' >&2; return 1; }

    awk '
        FNR == 1 && NR > 1 { print n "\t" v "\t" f "\t" s; n=""; v=""; f=""; s="" }
        /^%NAME%$/      { getline n }
        /^%VERSION%$/   { getline v }
        /^%FILENAME%$/  { getline f }
        /^%SHA256SUM%$/ { getline s }
        END { if (NR) print n "\t" v "\t" f "\t" s }
    ' "${descs[@]}" | LC_ALL=C sort
}

# The commit the publisher recorded for a published package, empty when it
# recorded none. Every publish since the publisher learned to write these has
# one; the packages that were on the channel before it did have nothing to
# read, and that silence is the caller's to describe rather than to paper over.
channel_origin_commit() {
    local file=$1 out='' commit=''
    out=$(mktemp)
    if channel_fetch "$CHANNEL_URL" "$file.origin" "$out" 2> /dev/null; then
        commit=$(awk '$1 == "commit" { print $2; exit }' "$out")
    fi
    rm -f "$out"
    printf '%s\n' "$commit"
}

# --- the package repositories -----------------------------------------------

# The commit a repository's tag names, on stdout. 0 it is there, 2 the
# repository carries no such tag, 1 the repository could not be read at all.
# The three have to stay apart: a repository nobody can reach and a tag nobody
# cut are different findings and only one of them is the manifest's fault.
#
# An annotated tag answers twice, and the peeled line is the commit rather than
# the tag object. Both patterns are spelled out because a glob would answer for
# 2026.08.09.1 when it was asked about 2026.08.09.
repo_tag_commit() {
    local repo=$1 tag=$2 out='' peeled=''
    out=$(git ls-remote --tags "$REPO_BASE/$repo" \
        "refs/tags/$tag" "refs/tags/$tag^{}" 2> /dev/null) || return 1
    [[ -n $out ]] || return 2
    peeled=$(awk '$2 ~ /\^\{\}$/ { print $1; exit }' <<<"$out")
    [[ -n $peeled ]] || peeled=$(awk 'NR == 1 { print $1 }' <<<"$out")
    printf '%s\n' "$peeled"
}

# A repository in $2, at the tag $3 names or at its default branch when $3 is
# empty. One clone per repository and tag however many packages ask for it.
#
# No history, no working tree and no file contents until something asks for
# one: these tools want a handful of PKGBUILDs and the repositories carrying
# wallpapers and shipped plugins are hundreds of megabytes of things they will
# never read. shedos-branding alone is the difference between two seconds and
# two minutes.
repo_clone() {
    local repo=$1 dir=$2 tag=${3:-} branch=()
    [[ ! -d $dir ]] || return 0
    [[ -z $tag ]] || branch=(--branch "$tag")
    git clone --quiet --depth 1 --filter=blob:none --no-checkout \
        "${branch[@]}" "$REPO_BASE/$repo" "$dir" 2> /dev/null
}

# The same, keeping the history, for the one question that needs it: which
# commit a published release was built at.
repo_clone_history() {
    local repo=$1 dir=$2
    [[ ! -d $dir ]] || return 0
    git clone --quiet --filter=blob:none --no-checkout "$REPO_BASE/$repo" "$dir" 2> /dev/null
}

# The commit a published release was built at, as "<matches>\t<newest>".
#
# The pipeline moves pkgrel past whatever the channel already carries, commits
# that move to the branch, and only then builds — so the tree a package was
# built from is a commit on the branch whose PKGBUILD says exactly the release
# that got published. The count comes back with it because one match is a
# derivation and several are a choice, and a caller must not present the second
# as the first.
repo_build_commit() {
    local dir=$1 path=$2 pkgver=$3 pkgrel=$4
    local commit='' newest='' matches=0 work=''
    work=$(mktemp)
    while read -r commit; do
        repo_file "$dir" "$commit" "$path" "$work" || continue
        [[ $(pkgbuild_field "$work" pkgver) == "$pkgver" ]] || continue
        [[ $(pkgbuild_field "$work" pkgrel) == "$pkgrel" ]] || continue
        matches=$((matches + 1))
        [[ -n $newest ]] || newest=$commit
    done < <(git -C "$dir" log --format=%H HEAD -- "$path" 2> /dev/null)
    rm -f "$work"
    printf '%s\t%s\n' "$matches" "$newest"
}

# The same clone, held to the commit the tag names: --branch takes a branch of
# that name in preference to the tag, and would then read a tree the manifest
# never pinned.
repo_clone_tag() {
    local repo=$1 dir=$2 tag=$3 commit=$4
    repo_clone "$repo" "$dir" "$tag" || return 1
    [[ $(git -C "$dir" rev-parse HEAD 2> /dev/null) == "$commit" ]]
}

# A clone holding one named commit. --branch cannot ask for a bare sha, so the
# clone comes down at whatever the default branch is and the commit is fetched
# by name afterwards; a commit that is not in the repository fails there rather
# than resolving to something else.
repo_clone_commit() {
    local repo=$1 dir=$2 commit=$3
    repo_clone "$repo" "$dir" || return 1
    git -C "$dir" fetch --quiet --depth 1 origin "$commit" 2> /dev/null || return 1
    git -C "$dir" cat-file -e "$commit^{commit}" 2> /dev/null
}

# What a manifest ref is: a commit when it is written as one, a tag otherwise.
# Read off the shape rather than by asking the repository, so that the answer
# does not change under the tools when somebody cuts a tag; forty lowercase hex
# digits is not a name anybody gives a release.
ref_kind() {
    [[ $1 =~ ^[0-9a-f]{40}$ ]] && { printf 'commit\n'; return; }
    printf 'tag\n'
}

# Every PKGBUILD the clone holds at a revision, one path per line.
repo_pkgbuilds() {
    git -C "$1" ls-tree -r --name-only "$2" | grep -E '(^|/)PKGBUILD$'
}

# One file out of the clone, which is where the blob it skipped gets fetched.
repo_file() {
    git -C "$1" show "$2:$3" > "$4" 2> /dev/null
}

# The names a PKGBUILD builds, one per line. pkgname is an array as often as it
# is a scalar and both forms have to answer, but neither is worth sourcing a
# file that came off the network to read.
pkgbuild_names() {
    local raw
    raw=$(pkgbuild_field "$1" pkgname) || return 1
    tr -d '()' <<<"$raw" | tr ' ' '\n' | sed '/^$/d'
}

# Which PKGBUILD in a clone builds a package, at a revision. The file lands in
# $4 and its path within the repository goes to stdout; nothing is printed when
# no PKGBUILD there builds it.
repo_pkgbuild_for() {
    local dir=$1 rev=$2 name=$3 out=$4 path=''
    while read -r path; do
        repo_file "$dir" "$rev" "$path" "$out" || continue
        pkgbuild_names "$out" 2> /dev/null | grep -qxF "$name" || continue
        printf '%s\n' "$path"
        return 0
    done < <(repo_pkgbuilds "$dir" "$rev")
    return 1
}

# What a PKGBUILD's source pins, as "<kind>\t<value>": a tag, a commit, a
# source array carrying neither, or no source array at all. The four are kept
# apart because they are four different answers to "what tree was this built
# from", and only the first is a tag.
#
# $pkgver and $_commit are expanded because that is what ours write; a fragment
# naming anything else comes back with the $ still in it and the caller refuses
# it rather than guessing.
pkgbuild_source_ref() {
    local file=$1 pkgver=$2 ref='' commit=''
    ref=$(sed -n 's/.*#tag=\([^"'"'"' )]*\).*/\1/p' "$file" | head -1)
    if [[ -n $ref ]]; then
        ref=${ref//\$\{pkgver\}/$pkgver}
        ref=${ref//\$pkgver/$pkgver}
        printf 'tag\t%s\n' "$ref"
        return
    fi
    ref=$(sed -n 's/.*#commit=\([^"'"'"' )]*\).*/\1/p' "$file" | head -1)
    if [[ -n $ref ]]; then
        commit=$(pkgbuild_field "$file" _commit) || commit=''
        ref=${ref//\$\{_commit\}/$commit}
        ref=${ref//\$_commit/$commit}
        printf 'commit\t%s\n' "$ref"
        return
    fi
    if grep -q '^source=' "$file"; then
        printf 'none\t\n'
    else
        printf 'nosource\t\n'
    fi
}

# --- the manifest file ------------------------------------------------------

# Parsed by a TOML parser rather than by a pattern, and then held to a schema
# that admits nothing else: a key nobody recognises, a package short of a
# field, a value shaped wrong or a name written twice is a refusal naming the
# entry. A manifest a tool half-understands is worse than one it will not read,
# because the half it understood still verifies green.
manifest_read() {
    python3 - "$1" <<'PY'
import re, sys, tomllib

PACKAGE_KEYS = ("name", "repo", "ref", "pkgver", "pkgrel", "sha256")
PATTERNS = {
    "name": r"[a-z0-9][a-z0-9._+-]*",
    # Org-relative: the organisation is the resolver's, written once there
    # rather than eighteen times here.
    "repo": r"[A-Za-z0-9][A-Za-z0-9._-]*",
    # A tag name where a tag governs the build, and the commit the build used
    # where none does. One pattern holds both; which one an entry is comes off
    # its shape, in ref_kind above.
    "ref": r"[A-Za-z0-9][A-Za-z0-9._+/-]*",
    "pkgver": r"[A-Za-z0-9][A-Za-z0-9._+]*",
    "pkgrel": r"[0-9]+(\.[0-9]+)?",
    "sha256": r"[0-9a-f]{64}",
}
VERSION = r"[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?(-rc[0-9]+)?"

path = sys.argv[1]
errors = []

try:
    with open(path, "rb") as fh:
        doc = tomllib.load(fh)
except OSError as exc:
    sys.exit(f"manifest: {exc}")
except tomllib.TOMLDecodeError as exc:
    sys.exit(f"manifest: {path} is not readable as TOML: {exc}")

for key in doc:
    if key not in ("release", "package"):
        errors.append(f"the manifest holds an unknown table '{key}'")

release = doc.get("release")
if not isinstance(release, dict):
    errors.append("the manifest has no [release] table")
    release = {}
for key in release:
    if key != "version":
        errors.append(f"[release] holds an unknown key '{key}'")
version = release.get("version")
if not isinstance(version, str):
    errors.append("[release] names no version")
elif not re.fullmatch(VERSION, version):
    errors.append(f"[release] version '{version}' is not a release version")

packages = doc.get("package", [])
if not isinstance(packages, list) or not packages:
    errors.append("the manifest names no packages")
    packages = []

seen = set()
rows = []
for index, entry in enumerate(packages, 1):
    where = entry.get("name") if isinstance(entry, dict) else None
    where = f"package '{where}'" if isinstance(where, str) else f"package {index}"
    if not isinstance(entry, dict):
        errors.append(f"{where} is not a table")
        continue
    for key in entry:
        if key not in PACKAGE_KEYS:
            errors.append(f"{where} holds an unknown key '{key}'")
    for key in PACKAGE_KEYS:
        value = entry.get(key)
        if value is None:
            errors.append(f"{where} names no {key}")
        elif not isinstance(value, str):
            errors.append(f"{where} writes {key} as {type(value).__name__} rather than a string")
        elif not re.fullmatch(PATTERNS[key], value):
            errors.append(f"{where} {key} '{value}' is not shaped like a {key}")
    name = entry.get("name")
    if isinstance(name, str):
        if name in seen:
            errors.append(f"the manifest names {name} twice")
        seen.add(name)
    rows.append("\t".join(str(entry.get(k, "")) for k in PACKAGE_KEYS))

if errors:
    for line in errors:
        print(line, file=sys.stderr)
    sys.exit(1)

print(f"release\t{version}")
for row in rows:
    print(f"package\t{row}")
PY
}
