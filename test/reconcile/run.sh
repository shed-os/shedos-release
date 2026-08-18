#!/usr/bin/env bash
# The publish reconcile. The channel is a directory with a real signed database
# over it, the same fixture shape the manifest suite uses, and GitHub is a stub
# `gh` on PATH that answers out of files the case writes and records what it was
# asked to send. Every line of the reconcile itself runs: which build to read,
# what the build produced, what the channel is missing, and the payload that
# goes back out.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
RECONCILE=$ROOT/tools/reconcile-publishes.sh

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

# --- the fixture channel ----------------------------------------------------

export GNUPGHOME=$WORK/gnupg
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-gen-key 'ShedOS reconcile harness <harness@shedos.invalid>' \
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
    --quick-gen-key 'ShedOS reconcile decoy <decoy@shedos.invalid>' \
    default default never >> "$WORK/gpg.log" 2>&1
DECOY=$(gpg --list-keys --with-colons decoy@shedos.invalid \
    | awk -F: '/^fpr:/ { print $10; exit }')

CHANNEL=$WORK/channel
PKGS=$CHANNEL/test/x86_64
ENTRIES=$WORK/entries.tsv

reset_channel() {
    rm -rf "$CHANNEL"
    mkdir -p "$PKGS"
    : > "$ENTRIES"
}

serve() {
    local name=$1 version=$2
    local file=$name-$version-any.pkg.tar.zst
    printf 'the %s package' "$name" > "$PKGS/$file"
    printf '%s\t%s\t%s\t%s\n' "$name" "$version" "$file" \
        "$(sha256sum "$PKGS/$file" | cut -d' ' -f1)" >> "$ENTRIES"
}

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
    gpg --batch --yes --detach-sign --no-armor -u "$key" \
        -o "$PKGS/shedos.db.tar.gz.sig" "$PKGS/shedos.db.tar.gz" 2>> "$WORK/gpg.log"
    gpg --export "$FP" > "$CHANNEL/shedos.gpg"
}

# --- the stub GitHub --------------------------------------------------------

# The stub answers three questions and records the fourth. Runs live in
# $WORK/gh/runs/<repo>, artifacts in $WORK/gh/artifacts/<repo>/<id>, and every
# dispatch it is handed lands in $WORK/gh/dispatches so a case can read what
# the reconcile actually asked for.
STUB=$WORK/bin
mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
set -uo pipefail
root=$GH_STUB_ROOT
case "$1 ${2:-}" in
    'api repos/'*)
        target=$2
        if [[ $target == *'/dispatches' ]]; then
            # gh api ... --method POST --input <file>
            for ((i = 1; i <= $#; i++)); do
                [[ ${!i} == --input ]] || continue
                j=$((i + 1))
                mkdir -p "$root/dispatches"
                cat "${!j}" >> "$root/dispatches/sent.json"
            done
            [[ -f $root/dispatch-fails ]] && exit 1
            exit 0
        fi
        repo=${target#repos/}
        if [[ $repo == *'/actions/runs?'* ]]; then
            repo=${repo%%/actions/runs?*}
            file=$root/runs/${repo//\//_}
            [[ -f $file ]] || exit 0
            awk -F'\t' '{ print $1 "\t" $2 }' "$file"
            exit 0
        fi
        if [[ $repo == *'/artifacts' ]]; then
            id=${repo%/artifacts}
            id=${id##*/runs/}
            repo=${repo%%/actions/runs/*}
            file=$root/artifacts/${repo//\//_}.$id
            [[ -f $file ]] || exit 0
            cat "$file"
            exit 0
        fi
        exit 1
        ;;
    'run download'*)
        id=$3
        repo=''
        name=''
        dir=''
        for ((i = 1; i <= $#; i++)); do
            case ${!i} in
                --repo) j=$((i + 1)); repo=${!j} ;;
                --name) j=$((i + 1)); name=${!j} ;;
                --dir)  j=$((i + 1)); dir=${!j} ;;
            esac
        done
        src=$root/sums/${repo//\//_}.$id
        [[ -f $src ]] || exit 1
        printf '%s\n' "$name" > /dev/null
        mkdir -p "$dir"
        cp "$src" "$dir/SHA256SUMS"
        exit 0
        ;;
esac
exit 1
STUBEOF
chmod +x "$STUB/gh"

GH=$WORK/gh
reset_github() { rm -rf "$GH"; mkdir -p "$GH/runs" "$GH/artifacts" "$GH/sums"; }

# Real forty-character commits. The publisher refuses a request whose sha is
# not one, so a fixture with a short stand-in would let this suite pass while
# every request it built was refused on arrival.
SHA_A=$(printf 'a%.0s' {1..40})
SHA_B=$(printf 'b%.0s' {1..40})
SHA_C=$(printf 'c%.0s' {1..40})

# repo, run id, head sha. Added newest first, because that is the order the
# runs API answers in and the reconcile takes the first one it can use.
add_run() {
    local file=$GH/runs/${1//\//_}
    printf '%s\t%s\n' "$2" "$3" > "$file.new"
    [[ ! -f $file ]] || cat "$file" >> "$file.new"
    mv "$file.new" "$file"
    printf 'pkg-%s\n' "$3" > "$GH/artifacts/${1//\//_}.$2"
}

# The same run without its artifact, which is what expiry looks like.
expire_artifact() { : > "$GH/artifacts/${1//\//_}.$2"; }

# The packages a run built, as its SHA256SUMS records them.
built() {
    local repo=$1 id=$2 file=''
    shift 2
    : > "$GH/sums/${repo//\//_}.$id"
    for file in "$@"; do
        printf '%s  %s\n' "$(printf '%s' "$file" | sha256sum | cut -d' ' -f1)" "$file" \
            >> "$GH/sums/${repo//\//_}.$id"
    done
}

dispatches() { cat "$GH/dispatches/sent.json" 2> /dev/null; }

# --- running it -------------------------------------------------------------

printf 'shed-os/alpha\n' > "$WORK/allowlist.txt"
printf '# nothing\n' > "$WORK/norepublish.txt"
printf '# nothing\n' > "$WORK/installer-only.txt"

reconcile() {
    PATH=$STUB:$PATH \
    GH_STUB_ROOT=$GH \
    SHEDOS_MANIFEST_CHANNEL=$PKGS \
    SHEDOS_MANIFEST_CHANNEL_ROOT=$CHANNEL \
    SHEDOS_RECONCILE_ALLOWLIST=$WORK/allowlist.txt \
    SHEDOS_NOREPUBLISH_FILE=$WORK/norepublish.txt \
    SHEDOS_INSTALLER_ONLY_FILE=$WORK/installer-only.txt \
    bash "$RECONCILE" "$@" > "$WORK/last.out" 2>&1
}

# The healthy world: one repository, one build, and a channel holding it.
reset_fixture() {
    reset_channel
    reset_github
    add_run shed-os/alpha 100 "$SHA_A"
    built shed-os/alpha 100 alpha-1.0-1-any.pkg.tar.zst
    serve alpha 1.0-1
    seal_channel
    printf 'shed-os/alpha\n' > "$WORK/allowlist.txt"
}

# --- case 1: nothing to do --------------------------------------------------

section 'case 1 — a channel holding everything the last build produced asks for nothing'
reset_fixture
reconcile --dispatch
rc=$?
check 'the reconcile passes' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it says the channel is complete' \
    grep -qx 'shed-os/alpha: the channel has everything run 100 built' "$WORK/last.out"
check 'and nothing was asked for' test -z "$(dispatches)"
check 'the tally says so' \
    grep -qx '0 package(s) missing, 0 request(s) sent, 0 repository(s) could not be read' \
    "$WORK/last.out"

# --- case 2: the dropped publish --------------------------------------------

section 'case 2 — a build the channel never received is found and asked for again'
reset_fixture
# The build moved to 1.0-2 and the channel still serves 1.0-1: the request went
# out, took the pending slot from nobody, and was taken from by the next one.
add_run shed-os/alpha 101 "$SHA_B"
built shed-os/alpha 101 alpha-1.0-2-any.pkg.tar.zst
reconcile --dispatch
check 'the reconcile reports the drop' test "$?" -eq 1
check 'it names the package, the release and the run' \
    grep -qx 'shed-os/alpha: the channel is missing alpha 1.0-2 from run 101' "$WORK/last.out"
check 'it says it asked again' \
    grep -qx 'shed-os/alpha: publish requested again for run 101' "$WORK/last.out"
check 'the tally counts both' \
    grep -qx '1 package(s) missing, 1 request(s) sent, 0 repository(s) could not be read' \
    "$WORK/last.out"

section 'case 2b — the request is the one the publisher already knows how to check'
check 'it is a publish-request' \
    test "$(dispatches | jq -r '.event_type')" = publish-request
check 'it names the repository that built it' \
    test "$(dispatches | jq -r '.client_payload.repo')" = shed-os/alpha
check 'it names the run whose artifact holds the packages' \
    test "$(dispatches | jq -r '.client_payload.run_id')" = 101
check 'the run id is a number rather than a string' \
    test "$(dispatches | jq -r '.client_payload.run_id | type')" = number
check 'it names the artifact by the commit' \
    test "$(dispatches | jq -r '.client_payload.artifact')" = "pkg-$SHA_B"
check 'it carries the file the build produced' \
    test "$(dispatches | jq -r '.client_payload.packages[0].file')" \
        = alpha-1.0-2-any.pkg.tar.zst
check 'and the checksum the build recorded for it' \
    test "$(dispatches | jq -r '.client_payload.packages[0].sha256')" \
        = "$(printf 'alpha-1.0-2-any.pkg.tar.zst' | sha256sum | cut -d' ' -f1)"
# publish.sh writes this commit into the channel and refuses anything that is
# not one, so the request has to carry the real shape or it dies on arrival.
check 'the commit it sends is a commit the publisher will take' \
    grep -qE '^[0-9a-f]{40}$' <<< "$(dispatches | jq -r '.client_payload.sha')"

section 'case 2c — a package the channel has never carried at all is a drop'
reset_fixture
built shed-os/alpha 100 alpha-1.0-1-any.pkg.tar.zst beta-1.0-1-any.pkg.tar.zst
reconcile --dispatch
check 'the reconcile reports it' test "$?" -eq 1
check 'it names the package the channel has never seen' \
    grep -qx 'shed-os/alpha: the channel is missing beta 1.0-1 from run 100' "$WORK/last.out"
check 'and the request carries both packages the build produced' \
    test "$(dispatches | jq -r '.client_payload.packages | length')" = 2

# --- case 3: it never publishes, and it can be asked not to request ---------

section 'case 3 — without --dispatch it finds the drop and asks for nothing'
reset_fixture
add_run shed-os/alpha 101 "$SHA_B"
built shed-os/alpha 101 alpha-1.0-2-any.pkg.tar.zst
reconcile
check 'it still reports the drop' test "$?" -eq 1
check 'it says why it asked for nothing' \
    grep -qx 'shed-os/alpha: not asking for it, because --dispatch was not given' \
    "$WORK/last.out"
check 'and nothing went out' test -z "$(dispatches)"

# --- case 4: a channel ahead of the build -----------------------------------

section 'case 4 — a channel past the last build is not a dropped publish'
reset_fixture
reset_channel
serve alpha 1.0-3
seal_channel
reconcile --dispatch
rc=$?
check 'the reconcile passes' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it says which way round it is' \
    grep -qx "shed-os/alpha: the channel is at alpha 1.0-3, past this build's 1.0-1" \
    "$WORK/last.out"
check 'and it does not ask the publisher to go backwards' test -z "$(dispatches)"

# --- case 5: what it cannot answer ------------------------------------------

section 'case 5 — a build whose artifact is gone cannot be republished from'
reset_fixture
add_run shed-os/alpha 101 "$SHA_B"
built shed-os/alpha 101 alpha-1.0-2-any.pkg.tar.zst
expire_artifact shed-os/alpha 101
reconcile --dispatch
rc=$?
# The publisher downloads the packages from the run, so a run whose artifact
# has aged out is beyond reach however the request is made. The reconcile falls
# back to run 100, which the channel does hold — and the whole danger is that
# it would then look complete. It has to name the run it stepped over.
check 'it names the build it could not use' \
    grep -qx 'shed-os/alpha: run 101 succeeded on main and its artifact is gone' \
    "$WORK/last.out"
check 'it falls back to the newest build that still has one' \
    grep -qx 'shed-os/alpha: the channel has everything run 100 built' "$WORK/last.out"
check 'and it does not claim to have checked what run 101 built' \
    not grep -q '1\.0-2' "$WORK/last.out"
check 'nothing is asked for, because nothing could be' test -z "$(dispatches)"
[[ $rc -eq 0 ]] || cat "$WORK/last.out"

section 'case 5b — a repository with no usable build at all is not silence'
reset_fixture
reset_github
reconcile --dispatch
check 'the reconcile stops' test "$?" -eq 2
check 'it names the repository' \
    grep -qx 'shed-os/alpha: no successful build on main still holding its artifact' \
    "$WORK/last.out"
check 'and it is counted as unread rather than as complete' \
    grep -qx '0 package(s) missing, 0 request(s) sent, 1 repository(s) could not be read' \
    "$WORK/last.out"

section 'case 5c — a request that will not send is not a request that was sent'
reset_fixture
add_run shed-os/alpha 101 "$SHA_B"
built shed-os/alpha 101 alpha-1.0-2-any.pkg.tar.zst
: > "$GH/dispatch-fails"
reconcile --dispatch
check 'the reconcile stops' test "$?" -eq 2
check 'it says the request did not go' \
    grep -qx 'shed-os/alpha: the publish request could not be sent' "$WORK/last.out"

section 'case 5d — a channel it cannot verify stops it before it asks anything'
reset_fixture
add_run shed-os/alpha 101 "$SHA_B"
built shed-os/alpha 101 alpha-1.0-2-any.pkg.tar.zst
rm -f "$PKGS/shedos.db.tar.gz.sig"
reconcile --dispatch
check 'the reconcile stops' test "$?" -eq 2
check 'it says why' grep -qx 'the channel database carries no signature' "$WORK/last.out"
check 'and nothing went out' test -z "$(dispatches)"

section 'case 5e — a database signed by a key the channel does not publish stops it'
reset_fixture
add_run shed-os/alpha 101 "$SHA_B"
built shed-os/alpha 101 alpha-1.0-2-any.pkg.tar.zst
seal_channel "$DECOY"
reconcile --dispatch
check 'the reconcile stops' test "$?" -eq 2
check 'it says why' \
    grep -qx 'the channel database is not signed by the key the channel publishes' \
    "$WORK/last.out"
check 'and it asks for nothing off a channel it could not verify' test -z "$(dispatches)"

# --- case 6: the lists the publisher would refuse on -------------------------

section 'case 6 — a package the publisher may not republish is not asked for'
reset_fixture
built shed-os/alpha 100 alpha-1.0-1-any.pkg.tar.zst google-chrome-1.0-1-x86_64.pkg.tar.zst
printf 'google-chrome\n' > "$WORK/norepublish.txt"
reconcile --dispatch
rc=$?
check 'the reconcile passes rather than asking forever' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it says which package and why' \
    grep -qx 'shed-os/alpha: google-chrome is on a no-republish list and is not asked for' \
    "$WORK/last.out"
check 'and nothing went out' test -z "$(dispatches)"

# --- case 7: more than one repository ---------------------------------------

section 'case 7 — every repository on the allowlist is asked about'
reset_fixture
printf 'shed-os/alpha\nshed-os/beta\n' > "$WORK/allowlist.txt"
add_run shed-os/beta 200 "$SHA_C"
built shed-os/beta 200 beta-2.0-1-any.pkg.tar.zst
reconcile --dispatch
check 'the reconcile reports the one that is behind' test "$?" -eq 1
check 'the complete repository is reported complete' \
    grep -qx 'shed-os/alpha: the channel has everything run 100 built' "$WORK/last.out"
check 'and the one that is missing is asked for' \
    grep -qx 'shed-os/beta: publish requested again for run 200' "$WORK/last.out"
check 'one request, for the repository that needed it' \
    test "$(dispatches | jq -s 'length')" = 1
check 'and it is that repository' \
    test "$(dispatches | jq -r '.client_payload.repo')" = shed-os/beta

# --- result -----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
