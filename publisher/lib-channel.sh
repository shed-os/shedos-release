# shellcheck shell=bash
# Bucket I/O for the channel publisher, sourced by publish.sh.
#
# SHEDOS_BUCKET is either an rclone remote (r2:shedos-repo) or a plain
# directory — rclone reads bare paths with its local backend, so the same
# calls serve production and the harness.
#
# CHANNEL_ROOT is the ONLY place the channel path is spelled out. It defaults
# to staging/ so nothing here can touch the live repo by accident; the cutover
# sets it to the empty string and that is the whole change. Two things hang
# off it: the packages and database under test/x86_64/, and the bootstrap
# keyring that sits at the root beside them.

die() { printf 'publish: %s\n' "$*" >&2; exit 1; }

channel_root_path() {
    printf '%s%s' "${CHANNEL_ROOT-staging/}" "$1"
}

channel_path() {
    channel_root_path "test/x86_64/$1"
}

channel_root_target() {
    printf '%s/%s' "${SHEDOS_BUCKET%/}" "$(channel_root_path "$1")"
}

channel_target() {
    printf '%s/%s' "${SHEDOS_BUCKET%/}" "$(channel_path "$1")"
}

# Names go into the log as the publisher addressed them: bare for the files
# under test/x86_64/, and likewise bare for the bootstrap keyring at the root.
channel_log() {
    [[ -n ${SHEDOS_TRANSFER_LOG:-} ]] || return 0
    printf '%s %s\n' "$1" "$2" >> "$SHEDOS_TRANSFER_LOG"
}

# What the channel holds right now, one name per line. Object stores have no
# directories, so asking rclone about a single missing key answers "empty
# listing, no error" and looks exactly like a file that is there — asking for
# the whole channel and looking the name up is the only form that reads the
# same on R2 and on a local directory.
#
# An unpublished channel lists nothing: empty and successful on an object
# store, exit 3 (directory not found) on a local directory. Every other exit
# status is a real failure — bad credentials, no network, a 403 — and saying
# "empty" to any of those would let the caller build a database holding only
# this run's packages and write it over a live one.
channel_list() {
    local listing status=0 err
    err=$(mktemp)
    listing=$(rclone lsf "$(channel_target '')" 2>"$err") || status=$?
    if (( status != 0 && status != 3 )); then
        cat "$err" >&2
        rm -f "$err"
        die "could not list the channel (rclone exit $status)"
    fi
    rm -f "$err"
    printf '%s' "$listing"
}

channel_get() {
    rclone copyto "$(channel_target "$1")" "$2"
    channel_log down "$1"
}

channel_put() {
    rclone copyto "$1" "$(channel_target "$2")"
    channel_log up "$2"
}

channel_put_root() {
    rclone copyto "$1" "$(channel_root_target "$2")"
    channel_log up "$2"
}
