#!/usr/bin/env bash
# Publisher harness. Real gpg, real repo-add, real rclone — the bucket is a
# directory and the signing key is thrown away with the temp dir. No root, no
# network, no R2.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
PUBLISH=$ROOT/publisher/publish.sh

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

# --- fixtures ---------------------------------------------------------------

export GNUPGHOME=$WORK/gnupg
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-gen-key 'ShedOS publisher harness <harness@shedos.invalid>' \
    default default never >"$WORK/gpg.log" 2>&1
GPG_FP=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')
export GPG_FP
if [[ -z $GPG_FP ]]; then
    echo "could not generate a harness signing key:" >&2
    cat "$WORK/gpg.log" >&2
    exit 1
fi
printf '%s\n' "$GPG_FP" > "$WORK/trusted-keys.txt"

# rclone that fails only the listing, the way a bad credential or a 403 would.
RCLONE_BIN=$(command -v rclone)
mkdir -p "$WORK/shim"
cat > "$WORK/shim/rclone" <<EOF
#!/usr/bin/env bash
if [[ \${1:-} == lsf ]]; then
    echo 'simulated listing failure' >&2
    exit 7
fi
exec $RCLONE_BIN "\$@"
EOF
chmod +x "$WORK/shim/rclone"

cat > "$WORK/makepkg.conf" <<EOF
source /etc/makepkg.conf
PKGDEST='$WORK/pkgs'
SRCDEST='$WORK/src'
SRCPKGDEST='$WORK/srcpkg'
BUILDDIR='$WORK/build'
PKGEXT='.pkg.tar.zst'
BUILDENV=(!distcc color !check !sign)
OPTIONS=(!debug)
EOF
mkdir -p "$WORK/pkgs" "$WORK/src" "$WORK/srcpkg" "$WORK/build"

build_fixture() {
    local name=$1
    local dir=$WORK/fixture/$name
    mkdir -p "$dir"
    cp "$HERE/fixtures/$name/PKGBUILD" "$dir/PKGBUILD"
    if ! (cd "$dir" && makepkg --config "$WORK/makepkg.conf" --nodeps --force) \
            >>"$WORK/makepkg.log" 2>&1; then
        echo "could not build the $name fixture:" >&2
        tail -20 "$WORK/makepkg.log" >&2
        exit 1
    fi
}

build_fixture alpha
build_fixture beta
ALPHA=$(echo "$WORK/pkgs"/alpha-*.pkg.tar.zst)
BETA=$(echo "$WORK/pkgs"/beta-*.pkg.tar.zst)
ALPHA_BASE=$(basename "$ALPHA")
BETA_BASE=$(basename "$BETA")

stage_artifact() {
    local name=$1
    shift
    local dir=$WORK/artifact/$name
    rm -rf "$dir"
    mkdir -p "$dir"
    cp "$@" "$dir/"
    (cd "$dir" && sha256sum -- *.pkg.tar.zst > SHA256SUMS)
    printf '%s' "$dir"
}

# The shape shedos-ci's request-publish.sh dispatches.
make_payload() {
    local out=$1 repo=$2 dir=$3
    local packages
    packages=$(cd "$dir" && awk 'NF {print $1 "\t" $NF}' SHA256SUMS \
        | jq -Rn '[inputs | split("\t") | {file: .[1], sha256: .[0]}]')
    jq -n --arg repo "$repo" --argjson packages "$packages" \
        '{repo: $repo, run_id: 0, sha: "deadbeef", artifact: "pkg-deadbeef",
          packages: $packages}' > "$out"
}

# --- bucket helpers ---------------------------------------------------------

BUCKET=$WORK/bucket
CHANNEL=$BUCKET/staging/test/x86_64
TRANSFER_LOG=$WORK/transfers.log
mkdir -p "$BUCKET"
export SHEDOS_BUCKET=$BUCKET
export SHEDOS_TRANSFER_LOG=$TRANSFER_LOG
export SHEDOS_TRUSTED_KEYS_FILE=$WORK/trusted-keys.txt
# Keep rclone off the developer's own remotes.
export RCLONE_CONFIG=$WORK/rclone.conf
: > "$RCLONE_CONFIG"

run_publish() {
    local payload=$1 artifact=$2
    shift 2
    : > "$TRANSFER_LOG"
    env "$@" "$PUBLISH" "$payload" "$artifact" >"$WORK/last.out" 2>&1
}

bucket_digest() {
    (cd "$1" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum)
}

db_entries() {
    bsdtar -tf "$1" 2>/dev/null | awk -F/ '$2 == "desc" {print $1}' | sort -u
}

# Last line matching $1 must come before the first line matching $2.
ordered_before() {
    local first last
    last=$(grep -n "$1" "$TRANSFER_LOG" | tail -1 | cut -d: -f1)
    first=$(grep -n "$2" "$TRANSFER_LOG" | head -1 | cut -d: -f1)
    [[ -n $last && -n $first && $last -lt $first ]]
}

# --- case 1: first publish --------------------------------------------------

section 'case 1 — first publish lands alpha and a signed db'
alpha_dir=$(stage_artifact alpha "$ALPHA")
make_payload "$WORK/alpha.json" shed-os/shedman "$alpha_dir"
run_publish "$WORK/alpha.json" "$alpha_dir"
rc=$?
check 'publish succeeds' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'says the channel had no db yet' grep -q 'no db in the channel' "$WORK/last.out"
check 'alpha package is in the channel' test -f "$CHANNEL/$ALPHA_BASE"
check 'alpha signature is in the channel' test -f "$CHANNEL/$ALPHA_BASE.sig"
for name in shedos.db shedos.db.sig shedos.files shedos.files.sig; do
    check "$name is in the channel" test -f "$CHANNEL/$name"
done
check 'db lists alpha' test "$(db_entries "$CHANNEL/shedos.db")" = alpha-1-1
check 'files db lists alpha' test "$(db_entries "$CHANNEL/shedos.files")" = alpha-1-1
check 'the package signature verifies' gpg --batch --verify \
    "$CHANNEL/$ALPHA_BASE.sig" "$CHANNEL/$ALPHA_BASE"
check 'the db signature verifies' gpg --batch --verify \
    "$CHANNEL/shedos.db.sig" "$CHANNEL/shedos.db"
check 'every package uploads before the db' \
    ordered_before '^up .*\.pkg\.tar\.zst' '^up shedos\.db'

# --- case 2: incremental ----------------------------------------------------

section 'case 2 — publishing beta keeps alpha in the db'
alpha_sum=$(sha256sum < "$CHANNEL/$ALPHA_BASE")
beta_dir=$(stage_artifact beta "$BETA")
make_payload "$WORK/beta.json" shed-os/shedos-system "$beta_dir"
run_publish "$WORK/beta.json" "$beta_dir"
rc=$?
check 'publish succeeds' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'db lists alpha and beta' \
    test "$(db_entries "$CHANNEL/shedos.db")" = "$(printf 'alpha-1-1\nbeta-1-1')"
check 'files db lists alpha and beta' \
    test "$(db_entries "$CHANNEL/shedos.files")" = "$(printf 'alpha-1-1\nbeta-1-1')"
check 'alpha package is untouched' \
    test "$(sha256sum < "$CHANNEL/$ALPHA_BASE")" = "$alpha_sum"
check 'alpha was not re-uploaded' not grep -q "^up $ALPHA_BASE\$" "$TRANSFER_LOG"
check 'beta package is in the channel' test -f "$CHANNEL/$BETA_BASE"
check 'the db signature still verifies' gpg --batch --verify \
    "$CHANNEL/shedos.db.sig" "$CHANNEL/shedos.db"

# --- case 3: canary mirror --------------------------------------------------

section 'case 3 — the canary db mirrors the real one'
for ext in db db.sig files files.sig; do
    check "shedostest.$ext matches shedos.$ext" \
        cmp -s "$CHANNEL/shedos.$ext" "$CHANNEL/shedostest.$ext"
done

# --- refusals ---------------------------------------------------------------

before=$(bucket_digest "$BUCKET")

section 'case 4 — a repo off the allowlist is refused'
evil_dir=$(stage_artifact evil "$ALPHA")
make_payload "$WORK/evil.json" shed-os/evil "$evil_dir"
run_publish "$WORK/evil.json" "$evil_dir"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'allowlist' "$WORK/last.out"
check 'bucket is unchanged' test "$(bucket_digest "$BUCKET")" = "$before"

section 'case 5 — a package whose hash does not match is refused'
bad_dir=$(stage_artifact badhash "$ALPHA")
make_payload "$WORK/badhash.json" shed-os/shedman "$bad_dir"
jq '.packages[0].sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' \
    "$WORK/badhash.json" > "$WORK/badhash.tmp"
mv "$WORK/badhash.tmp" "$WORK/badhash.json"
run_publish "$WORK/badhash.json" "$bad_dir"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'sha256' "$WORK/last.out"
check 'bucket is unchanged' test "$(bucket_digest "$BUCKET")" = "$before"

section 'case 6 — a package on the no-republish list is refused'
run_publish "$WORK/alpha.json" "$alpha_dir" \
    "SHEDOS_NOREPUBLISH_FILE=$HERE/fixtures/norepublish.txt"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'republish' "$WORK/last.out"
check 'bucket is unchanged' test "$(bucket_digest "$BUCKET")" = "$before"

section 'case 7 — an untrusted signing key is refused before anything is signed'
run_publish "$WORK/alpha.json" "$alpha_dir" \
    "SHEDOS_TRUSTED_KEYS_FILE=$HERE/fixtures/untrusted-keys.txt"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'trusted' "$WORK/last.out"
check 'nothing was signed' not grep -q '^sign ' "$WORK/last.out"
check 'nothing was transferred' test ! -s "$TRANSFER_LOG"
check 'bucket is unchanged' test "$(bucket_digest "$BUCKET")" = "$before"

section 'case 8 — a channel listing that fails is not an empty channel'
run_publish "$WORK/beta.json" "$beta_dir" "PATH=$WORK/shim:$PATH"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'could not list the channel' "$WORK/last.out"
check 'nothing was transferred' test ! -s "$TRANSFER_LOG"
check 'bucket is unchanged' test "$(bucket_digest "$BUCKET")" = "$before"

# --- case 9: the cutover switch ---------------------------------------------

section 'case 9 — an empty CHANNEL_ROOT publishes to the production path'
PROD=$WORK/prod-bucket
mkdir -p "$PROD"
run_publish "$WORK/alpha.json" "$alpha_dir" "SHEDOS_BUCKET=$PROD" 'CHANNEL_ROOT='
rc=$?
check 'publish succeeds' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'alpha lands under test/x86_64' test -f "$PROD/test/x86_64/$ALPHA_BASE"
check 'nothing lands under staging' test ! -d "$PROD/staging"

# --- result -----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
