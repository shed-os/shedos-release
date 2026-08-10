#!/usr/bin/env bash
# The ShedOS signing key is written down twice. shedman migrate carries the
# fingerprints it will accept for the key it fetches, which is what a box
# joining ShedOS trusts before it has a keyring; shedos-keyring carries the
# trusted-keys list every box already on ShedOS trusts. A key added to one and
# not the other either locks new installs out or leaves them accepting
# something the fleet does not, and the two now live in separate repositories
# where nothing else looks at both.
#
# SHEDOS_TRUST_MIGRATE_FILE and SHEDOS_TRUST_KEYRING_FILE read a local file in
# place of a fetch, which is how the cases below run without a network.
set -uo pipefail

MIGRATE_URL=https://raw.githubusercontent.com/shed-os/shedos-migrate/main/tree/usr/libexec/shedman/migrate
# The keyring side is read from the package the channel serves rather than
# from a source tree, because that package is what a box actually installs
# and what the publisher takes its own trust from. This path has to move when
# CHANNEL_ROOT does, or the check reads a channel nothing publishes to.
CHANNEL_URL=https://repo.shedos.org/staging/test/x86_64
TRUSTED_PATH=usr/share/pacman/keyrings/shedos-trusted
# Cloudflare's managed rules drop datacenter traffic that does not name itself,
# and a GitHub runner is a datacenter address.
USER_AGENT='shedos-release (+https://shedos.org)'

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

# --- the check --------------------------------------------------------------

# Whole lines that are nothing but a fingerprint, so a comment or a renamed
# array cannot contribute one. Trimmed per line: collapsing the whole stream
# would run two fingerprints together into one.
fingerprints() { sed -e 's/[[:space:]]//g' -e '/^[0-9A-F]\{40\}$/!d' | LC_ALL=C sort -u; }

migrate_fingerprints() {
    sed -n '/^SHEDOS_KEY_FPRS=(/,/^)/p' "$1" | fingerprints
}

keyring_fingerprints() { fingerprints < "$1"; }

fetch() { curl -sSfL --max-time 60 -A "$USER_AGENT" -o "$2" "$1"; }

read_migrate() {
    local out=$1
    if [[ -n ${SHEDOS_TRUST_MIGRATE_FILE:-} ]]; then
        cp -- "$SHEDOS_TRUST_MIGRATE_FILE" "$out"
    else
        fetch "$MIGRATE_URL" "$out"
    fi
}

# The database names the keyring package, the package holds the list. The
# override returns before either fetch, which is what keeps the cases below
# off the network.
read_keyring() {
    local out=$1 db=$WORK/channel.db.tar.gz pkg=$WORK/keyring.pkg.tar.zst file
    if [[ -n ${SHEDOS_TRUST_KEYRING_FILE:-} ]]; then
        cp -- "$SHEDOS_TRUST_KEYRING_FILE" "$out"
        return
    fi
    fetch "$CHANNEL_URL/shedos.db.tar.gz" "$db" || return 1
    rm -rf "$WORK/db" && mkdir "$WORK/db"
    bsdtar -xf "$db" -C "$WORK/db" || return 1
    # By %NAME%, the way the publisher resolves it: a package sharing the
    # keyring's prefix would otherwise answer for it.
    local desc
    for desc in "$WORK"/db/*/desc; do
        [[ -f $desc ]] || continue
        [[ $(awk '/^%NAME%$/ { getline; print; exit }' "$desc") == shedos-keyring ]] \
            || continue
        file=$(awk '/^%FILENAME%$/ { getline; print; exit }' "$desc")
        break
    done
    [[ -n ${file:-} ]] || return 1
    fetch "$CHANNEL_URL/$file" "$pkg" || return 1
    bsdtar -xOqf "$pkg" "$TRUSTED_PATH" > "$out"
}

# 0 the two agree, 1 they have drifted, 2 one of them could not be read.
drift_check() {
    local migrate=$WORK/migrate keyring=$WORK/trusted
    local mine theirs fpr drifted=0

    read_migrate "$migrate" \
        || { echo 'could not read the migrate verb'; return 2; }
    read_keyring "$keyring" \
        || { echo 'could not read the trusted-keys list'; return 2; }

    mine=$(migrate_fingerprints "$migrate")
    theirs=$(keyring_fingerprints "$keyring")
    [[ -n $mine ]] || { echo 'the migrate verb names no fingerprints'; return 2; }
    [[ -n $theirs ]] || { echo 'the trusted-keys list names no fingerprints'; return 2; }

    while IFS= read -r fpr; do
        [[ -n $fpr ]] || continue
        echo "the migrate verb trusts $fpr and the trusted-keys list does not"
        drifted=1
    done < <(LC_ALL=C comm -23 <(printf '%s\n' "$mine") <(printf '%s\n' "$theirs"))

    while IFS= read -r fpr; do
        [[ -n $fpr ]] || continue
        echo "the trusted-keys list trusts $fpr and the migrate verb does not"
        drifted=1
    done < <(LC_ALL=C comm -13 <(printf '%s\n' "$mine") <(printf '%s\n' "$theirs"))

    (( drifted == 0 )) || return 1
    printf 'both name the same %d key(s)\n' "$(printf '%s\n' "$mine" | wc -l)"
}

run_check() {
    (
        unset SHEDOS_TRUST_MIGRATE_FILE SHEDOS_TRUST_KEYRING_FILE
        while (( $# )); do export "${1?}"; shift; done
        drift_check
    ) >"$WORK/last.out" 2>&1
}

# --- fixtures ---------------------------------------------------------------

ONE=1111111111111111111111111111111111111111
TWO=2222222222222222222222222222222222222222
THREE=3333333333333333333333333333333333333333

write_migrate() {
    local out=$1
    shift
    {
        echo '#!/usr/bin/env bash'
        echo 'SHEDOS_KEY_FPRS=('
        echo '    # the key the repo is signed with'
        printf '    %s\n' "$@"
        echo ')'
        echo "SHEDOS_KEY_URL=https://repo.shedos.org/shedos.gpg"
        echo "# 0000000000000000000000000000000000000000 retired, kept for the record"
    } > "$out"
}

write_keyring() {
    local out=$1
    shift
    printf '%s\n' "$@" > "$out"
}

# --- case 1: the lists agree ------------------------------------------------

section 'case 1 — the same keys on both sides pass whatever the order'
write_migrate "$WORK/agree.migrate" "$ONE" "$TWO"
write_keyring "$WORK/agree.trusted" "$TWO" "$ONE"
run_check "SHEDOS_TRUST_MIGRATE_FILE=$WORK/agree.migrate" \
    "SHEDOS_TRUST_KEYRING_FILE=$WORK/agree.trusted"
rc=$?
check 'the check passes' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it says how many keys it compared' grep -qx 'both name the same 2 key(s)' "$WORK/last.out"
check 'the commented-out fingerprint is not counted' \
    not grep -q '0000000000000000000000000000000000000000' "$WORK/last.out"

# --- case 2: drift on the migrate side --------------------------------------

section 'case 2 — a key only the migrate verb trusts is drift'
write_migrate "$WORK/extra.migrate" "$ONE" "$TWO" "$THREE"
run_check "SHEDOS_TRUST_MIGRATE_FILE=$WORK/extra.migrate" \
    "SHEDOS_TRUST_KEYRING_FILE=$WORK/agree.trusted"
check 'the check fails' test "$?" -eq 1
check 'it names the fingerprint and the side that has it' \
    grep -qx "the migrate verb trusts $THREE and the trusted-keys list does not" \
    "$WORK/last.out"
check 'the keys they agree on are not reported' not grep -q "$ONE" "$WORK/last.out"

# --- case 3: drift on the keyring side --------------------------------------

section 'case 3 — a key only the trusted-keys list carries is drift'
write_keyring "$WORK/extra.trusted" "$ONE" "$TWO" "$THREE"
run_check "SHEDOS_TRUST_MIGRATE_FILE=$WORK/agree.migrate" \
    "SHEDOS_TRUST_KEYRING_FILE=$WORK/extra.trusted"
check 'the check fails' test "$?" -eq 1
check 'it names the fingerprint and the side that has it' \
    grep -qx "the trusted-keys list trusts $THREE and the migrate verb does not" \
    "$WORK/last.out"

# --- case 4: a source that cannot be read is not agreement ------------------

section 'case 4 — a fingerprint list that is not there stops the check'
printf '#!/usr/bin/env bash\necho hello\n' > "$WORK/renamed.migrate"
run_check "SHEDOS_TRUST_MIGRATE_FILE=$WORK/renamed.migrate" \
    "SHEDOS_TRUST_KEYRING_FILE=$WORK/agree.trusted"
check 'the check fails' test "$?" -eq 2
check 'it says the verb named none' grep -q 'names no fingerprints' "$WORK/last.out"

section 'case 5 — a file that is not there stops the check'
run_check "SHEDOS_TRUST_MIGRATE_FILE=$WORK/nowhere" \
    "SHEDOS_TRUST_KEYRING_FILE=$WORK/agree.trusted"
check 'the check fails' test "$?" -eq 2
check 'it says which side' grep -q 'could not read the migrate verb' "$WORK/last.out"

# --- case 6: the anchors as they are shipped --------------------------------

section 'case 6 — the shipped migrate verb and the published keyring agree'
run_check
rc=$?
check 'the check passes' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"

# --- result -----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
