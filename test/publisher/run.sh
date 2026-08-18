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
gpg --export "$GPG_FP" > "$WORK/keyring.gpg"

# A keyring built from some other key, for the gate that has to notice.
gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-gen-key 'ShedOS harness decoy <decoy@shedos.invalid>' \
    default default never >>"$WORK/gpg.log" 2>&1
decoy_fp=$(gpg --list-keys --with-colons decoy@shedos.invalid \
    | awk -F: '/^fpr:/ {print $10; exit}')
gpg --export "$decoy_fp" > "$WORK/decoy-keyring.gpg"

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
    local name=$1 pkgver=${2:-}
    local dir=$WORK/fixture/$name${pkgver:+-$pkgver}
    mkdir -p "$dir"
    cp "$HERE/fixtures/$name/PKGBUILD" "$dir/PKGBUILD"
    [[ -z $pkgver ]] || sed -i "s/^pkgver=.*/pkgver=$pkgver/" "$dir/PKGBUILD"
    if ! (cd "$dir" && makepkg --config "$WORK/makepkg.conf" --nodeps --force) \
            >>"$WORK/makepkg.log" 2>&1; then
        echo "could not build the $name fixture:" >&2
        tail -20 "$WORK/makepkg.log" >&2
        exit 1
    fi
}

# A keyring package the way the channel serves one, holding whichever key it
# is handed.
build_keyring_fixture() {
    local pkgver=$1 key=$2
    local dir=$WORK/fixture/keyring-$pkgver
    mkdir -p "$dir/tree"
    cp "$HERE/fixtures/keyring/PKGBUILD" "$dir/PKGBUILD"
    sed -i "s/^pkgver=.*/pkgver=$pkgver/" "$dir/PKGBUILD"
    printf '%s\n' "$key" > "$dir/tree/shedos-trusted"
    # Both keys, so the packaged shedos.gpg cannot be confused with the one
    # the override points at.
    gpg --export "$GPG_FP" "$decoy_fp" > "$dir/tree/shedos.gpg"
    if ! (cd "$dir" && makepkg --config "$WORK/makepkg.conf" --nodeps --force) \
            >>"$WORK/makepkg.log" 2>&1; then
        echo "could not build the keyring fixture:" >&2
        tail -20 "$WORK/makepkg.log" >&2
        exit 1
    fi
}

build_fixture alpha
build_fixture beta
build_fixture delta 1
build_fixture delta 2
build_fixture delta 3
build_keyring_fixture 1 "$GPG_FP"
build_keyring_fixture 2 "$decoy_fp"
build_keyring_fixture 3 "$GPG_FP"
KEYRING=$WORK/pkgs/shedos-keyring-1-1-any.pkg.tar.zst
DECOY_KEYRING=$WORK/pkgs/shedos-keyring-2-1-any.pkg.tar.zst
# A keyring that passes every other gate, for the one that has to notice the
# channel is serving a package its database never recorded.
SWAPPED_KEYRING=$WORK/pkgs/shedos-keyring-3-1-any.pkg.tar.zst
KEYRING_BASE=$(basename "$KEYRING")
ALPHA=$(echo "$WORK/pkgs"/alpha-*.pkg.tar.zst)
BETA=$(echo "$WORK/pkgs"/beta-*.pkg.tar.zst)
ALPHA_BASE=$(basename "$ALPHA")
BETA_BASE=$(basename "$BETA")
DELTA1=$WORK/pkgs/delta-1-1-any.pkg.tar.zst
DELTA2=$WORK/pkgs/delta-2-1-any.pkg.tar.zst
DELTA3=$WORK/pkgs/delta-3-1-any.pkg.tar.zst
DELTA2_BASE=$(basename "$DELTA2")

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

# The shape shedos-ci's request-publish.sh dispatches. The commit is a real
# forty-character one, because that is what $GITHUB_SHA is and the publisher
# writes it into the channel — a fixture shorter than the real thing would let
# a check on its shape pass here and fail in production.
PAYLOAD_COMMIT=1111111111111111111111111111111111111111
PAYLOAD_RUN=4242

make_payload() {
    local out=$1 repo=$2 dir=$3
    local packages
    packages=$(cd "$dir" && awk 'NF {print $1 "\t" $NF}' SHA256SUMS \
        | jq -Rn '[inputs | split("\t") | {file: .[1], sha256: .[0]}]')
    jq -n --arg repo "$repo" --arg sha "$PAYLOAD_COMMIT" \
        --argjson run "$PAYLOAD_RUN" --argjson packages "$packages" \
        '{repo: $repo, run_id: $run, sha: $sha, artifact: ("pkg-" + $sha),
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
export SHEDOS_KEYRING_GPG_FILE=$WORK/keyring.gpg
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
check 'the bootstrap keyring is at the channel root' test -f "$BUCKET/staging/shedos.gpg"
check 'the keyring is the one we were given' \
    cmp -s "$WORK/keyring.gpg" "$BUCKET/staging/shedos.gpg"
check 'the keyring uploads before the db' \
    ordered_before '^up shedos\.gpg' '^up shedos\.db'

# The request carries the commit it was built at, and until now the publisher
# read it and threw it away — so a package in the channel could not say which
# tree it came from. It is written beside the package, and it has to come back
# out saying what went in.
check 'the request is recorded beside the package' test -f "$CHANNEL/$ALPHA_BASE.origin"
check 'and it records the commit that was sent' \
    grep -qx "commit $PAYLOAD_COMMIT" "$CHANNEL/$ALPHA_BASE.origin"
check 'and the run that sent it' grep -qx "run $PAYLOAD_RUN" "$CHANNEL/$ALPHA_BASE.origin"
check 'and the repository it came from' \
    grep -qx 'repo shed-os/shedman' "$CHANNEL/$ALPHA_BASE.origin"
check 'the record uploads before the db, like the package it describes' \
    ordered_before '^up .*\.origin' '^up shedos\.db'
# The run's commit is the parent of the build whenever the pipeline bumped
# pkgrel, so a release pinning it would name a tree carrying the pkgrel before
# the bump. The request carries both and so does the record.
check 'a request that names no build tree still publishes' \
    not grep -q '^build ' "$CHANNEL/$ALPHA_BASE.origin"

section 'case 1c — the tree a package was built from is recorded beside it'
tree_dir=$(stage_artifact tree "$ALPHA")
PAYLOAD_BUILD=2222222222222222222222222222222222222222
jq --arg t "$PAYLOAD_BUILD" '.packages |= map(. + {build_sha: $t})' \
    "$WORK/alpha.json" > "$WORK/withtree.json"
run_publish "$WORK/withtree.json" "$tree_dir"
rc=$?
check 'publish succeeds' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'the build tree is recorded' \
    grep -qx "build $PAYLOAD_BUILD" "$CHANNEL/$ALPHA_BASE.origin"
check 'and the run commit is kept beside it rather than replaced' \
    grep -qx "commit $PAYLOAD_COMMIT" "$CHANNEL/$ALPHA_BASE.origin"

jq '.packages |= map(. + {build_sha: "deadbeef"})' "$WORK/alpha.json" \
    > "$WORK/badtree.json"
run_publish "$WORK/badtree.json" "$tree_dir"
check 'a build tree that is not a commit is refused' test "$?" -ne 0
check 'and it says which package it was for' \
    grep -q "'deadbeef' is not a commit for $ALPHA_BASE" "$WORK/last.out"

section 'case 1b — a request that names no commit is not published'
nocommit_dir=$(stage_artifact nocommit "$ALPHA")
jq 'del(.sha)' "$WORK/alpha.json" > "$WORK/nocommit.json"
run_publish "$WORK/nocommit.json" "$nocommit_dir"
check 'publish fails' test "$?" -ne 0
check 'it says what is missing' grep -q 'payload names no commit' "$WORK/last.out"

jq '.sha = "deadbeef"' "$WORK/alpha.json" > "$WORK/shortcommit.json"
run_publish "$WORK/shortcommit.json" "$nocommit_dir"
check 'a commit that is not one is refused' test "$?" -ne 0
check 'and it says which value' \
    grep -q "'deadbeef' is not a commit" "$WORK/last.out"

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
check 'nothing was uploaded' not grep -q '^up ' "$TRANSFER_LOG"
check 'bucket is unchanged' test "$(bucket_digest "$BUCKET")" = "$before"

section 'case 8 — a keyring without the signing key is refused'
run_publish "$WORK/alpha.json" "$alpha_dir" \
    "SHEDOS_KEYRING_GPG_FILE=$WORK/decoy-keyring.gpg"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'does not hold the signing key' "$WORK/last.out"
check 'nothing was signed' not grep -q '^sign ' "$WORK/last.out"
check 'nothing was uploaded' not grep -q '^up ' "$TRANSFER_LOG"
check 'bucket is unchanged' test "$(bucket_digest "$BUCKET")" = "$before"

section 'case 9 — a channel listing that fails is not an empty channel'
run_publish "$WORK/beta.json" "$beta_dir" "PATH=$WORK/shim:$PATH"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'could not list the channel' "$WORK/last.out"
check 'nothing was transferred' test ! -s "$TRANSFER_LOG"
check 'bucket is unchanged' test "$(bucket_digest "$BUCKET")" = "$before"

# --- version monotonicity ---------------------------------------------------

section 'case 10 — a version older than the channel holds is refused'
delta2_dir=$(stage_artifact delta2 "$DELTA2")
make_payload "$WORK/delta2.json" shed-os/shedman "$delta2_dir"
run_publish "$WORK/delta2.json" "$delta2_dir"
rc=$?
check 'the publish that sets the baseline succeeds' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'db holds delta 2-1' grep -qxF delta-2-1 <<<"$(db_entries "$CHANNEL/shedos.db")"

baseline=$(bucket_digest "$BUCKET")
delta1_dir=$(stage_artifact delta1 "$DELTA1")
make_payload "$WORK/delta1.json" shed-os/shedman "$delta1_dir"
run_publish "$WORK/delta1.json" "$delta1_dir"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'older than the published' "$WORK/last.out"
check 'nothing was signed' not grep -q '^sign ' "$WORK/last.out"
check 'nothing was uploaded' not grep -q '^up ' "$TRANSFER_LOG"
check 'bucket is unchanged' test "$(bucket_digest "$BUCKET")" = "$baseline"

section 'case 11 — a newer version is accepted'
delta3_dir=$(stage_artifact delta3 "$DELTA3")
make_payload "$WORK/delta3.json" shed-os/shedman "$delta3_dir"
run_publish "$WORK/delta3.json" "$delta3_dir"
rc=$?
check 'publish succeeds' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'db holds delta 3-1' grep -qxF delta-3-1 <<<"$(db_entries "$CHANNEL/shedos.db")"
check 'the superseded entry is gone from the db' \
    not grep -qxF delta-2-1 <<<"$(db_entries "$CHANNEL/shedos.db")"
check 'the superseded package is still in the channel' test -f "$CHANNEL/$DELTA2_BASE"
run_publish "$WORK/delta3.json" "$delta3_dir"
check 'the same version again is still allowed' test "$?" -eq 0

# --- case 12: the cutover switch --------------------------------------------

section 'case 12 — an empty CHANNEL_ROOT publishes to the production path'
PROD=$WORK/prod-bucket
mkdir -p "$PROD"
run_publish "$WORK/alpha.json" "$alpha_dir" "SHEDOS_BUCKET=$PROD" 'CHANNEL_ROOT='
rc=$?
check 'publish succeeds' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'alpha lands under test/x86_64' test -f "$PROD/test/x86_64/$ALPHA_BASE"
check 'the keyring lands at the bucket root' test -f "$PROD/shedos.gpg"
check 'nothing lands under staging' test ! -d "$PROD/staging"

# --- case 13: a database that cannot be read --------------------------------

section 'case 13 — a channel database that will not open is refused'
cp "$CHANNEL/shedos.db.tar.gz" "$WORK/good.db.tar.gz"
head -c 512 /dev/urandom > "$CHANNEL/shedos.db.tar.gz"
corrupt=$(bucket_digest "$BUCKET")
run_publish "$WORK/alpha.json" "$alpha_dir"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'could not read the channel database' "$WORK/last.out"
check 'nothing was signed' not grep -q '^sign ' "$WORK/last.out"
check 'nothing was uploaded' not grep -q '^up ' "$TRANSFER_LOG"
check 'bucket is unchanged' test "$(bucket_digest "$BUCKET")" = "$corrupt"
# Hand the channel back intact, so whatever gets appended below starts where
# case 12 left off rather than on a database this case broke.
cp "$WORK/good.db.tar.gz" "$CHANNEL/shedos.db.tar.gz"

# --- where the trust comes from ---------------------------------------------

# Both overrides empty, so the publisher has to find the keyring itself —
# the production path.
NO_SEAMS=(SHEDOS_TRUSTED_KEYS_FILE= SHEDOS_KEYRING_GPG_FILE=)
bsdtar -xOqf "$KEYRING" usr/share/pacman/keyrings/shedos.gpg > "$WORK/packaged.gpg"

section 'case 14 — the first publish trusts the keyring it is carrying'
FRESH=$WORK/fresh-bucket
mkdir -p "$FRESH"
keyring_dir=$(stage_artifact keyring "$KEYRING")
make_payload "$WORK/keyring.json" shed-os/shedos-keyring "$keyring_dir"
run_publish "$WORK/keyring.json" "$keyring_dir" "${NO_SEAMS[@]}" "SHEDOS_BUCKET=$FRESH"
rc=$?
check 'publish succeeds' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it names the trust source' \
    grep -qx 'trust source: shedos-keyring 1-1 from this request' "$WORK/last.out"
check 'the channel root keyring is the packaged one' \
    cmp -s "$WORK/packaged.gpg" "$FRESH/staging/shedos.gpg"
check 'it is not the file the override names' \
    not cmp -s "$WORK/keyring.gpg" "$FRESH/staging/shedos.gpg"

section 'case 15 — the next publish trusts the keyring the channel holds'
run_publish "$WORK/alpha.json" "$alpha_dir" "${NO_SEAMS[@]}" "SHEDOS_BUCKET=$FRESH"
rc=$?
check 'publish succeeds' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it names the trust source' \
    grep -qx 'trust source: shedos-keyring 1-1 from the channel' "$WORK/last.out"
check 'it announces no other source' not grep -qi 'bootstrap' "$WORK/last.out"
check 'the channel root keyring is still the packaged one' \
    cmp -s "$WORK/packaged.gpg" "$FRESH/staging/shedos.gpg"

section 'case 16 — the fingerprint gate reads the channel keyring, not a local file'
DECOYED=$WORK/decoy-bucket
mkdir -p "$DECOYED"
decoy_dir=$(stage_artifact decoy-keyring "$DECOY_KEYRING")
make_payload "$WORK/decoy.json" shed-os/shedos-keyring "$decoy_dir"
run_publish "$WORK/decoy.json" "$decoy_dir" "SHEDOS_BUCKET=$DECOYED"
rc=$?
check 'the publish that seeds the channel succeeds' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"

seeded=$(bucket_digest "$DECOYED")
run_publish "$WORK/alpha.json" "$alpha_dir" "${NO_SEAMS[@]}" "SHEDOS_BUCKET=$DECOYED"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'is not on the trusted-keys list' "$WORK/last.out"
check 'the local trusted-keys file would have passed' \
    grep -qxF "$GPG_FP" "$WORK/trusted-keys.txt"
check 'nothing was signed' not grep -q '^sign ' "$WORK/last.out"
check 'nothing was uploaded' not grep -q '^up ' "$TRANSFER_LOG"
check 'bucket is unchanged' test "$(bucket_digest "$DECOYED")" = "$seeded"

section 'case 17 — a channel keyring the database does not vouch for is refused'
fresh_channel=$FRESH/staging/test/x86_64
cp "$fresh_channel/$KEYRING_BASE" "$WORK/good-keyring.pkg"
cp "$SWAPPED_KEYRING" "$fresh_channel/$KEYRING_BASE"
tampered=$(bucket_digest "$FRESH")
run_publish "$WORK/alpha.json" "$alpha_dir" "${NO_SEAMS[@]}" "SHEDOS_BUCKET=$FRESH"
check 'publish fails' test "$?" -ne 0
check 'says why' grep -q 'does not match the sha256' "$WORK/last.out"
check 'nothing was signed' not grep -q '^sign ' "$WORK/last.out"
check 'nothing was uploaded' not grep -q '^up ' "$TRANSFER_LOG"
check 'bucket is unchanged' test "$(bucket_digest "$FRESH")" = "$tampered"
cp "$WORK/good-keyring.pkg" "$fresh_channel/$KEYRING_BASE"

section 'case 18 — an empty channel with no keyring in the request is refused'
EMPTY=$WORK/empty-bucket
mkdir -p "$EMPTY"
run_publish "$WORK/alpha.json" "$alpha_dir" "${NO_SEAMS[@]}" "SHEDOS_BUCKET=$EMPTY"
check 'publish fails' test "$?" -ne 0
check 'says why' \
    grep -q 'holds no shedos-keyring and this request brings none' "$WORK/last.out"
check 'nothing was signed' not grep -q '^sign ' "$WORK/last.out"
check 'nothing was uploaded' not grep -q '^up ' "$TRANSFER_LOG"

# --- result -----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
