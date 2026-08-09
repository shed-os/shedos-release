# shellcheck shell=bash
# Bucket I/O for the channel publisher, sourced by publish.sh.
#
# SHEDOS_BUCKET is either an rclone remote (r2:shedos-repo) or a plain
# directory — rclone reads bare paths with its local backend, so the same
# calls serve production and the harness.
#
# CHANNEL_ROOT is the ONLY place the channel path is spelled out. It defaults
# to staging/ so nothing here can touch the live repo by accident; the cutover
# sets it to the empty string and that is the whole change.

channel_prefix() {
    printf '%stest/x86_64/' "${CHANNEL_ROOT-staging/}"
}

channel_target() {
    printf '%s/%s%s' "${SHEDOS_BUCKET%/}" "$(channel_prefix)" "$1"
}

channel_log() {
    [[ -n ${SHEDOS_TRANSFER_LOG:-} ]] || return 0
    printf '%s %s\n' "$1" "$2" >> "$SHEDOS_TRANSFER_LOG"
}

# What the channel holds right now, one name per line. Object stores have no
# directories, so asking rclone about a single missing key answers "empty
# listing, no error" and looks exactly like a file that is there — asking for
# the whole channel and looking the name up is the only form that reads the
# same on R2 and on a local directory. An unpublished channel lists nothing.
channel_list() {
    rclone lsf "$(channel_target '')" 2>/dev/null || true
}

channel_get() {
    rclone copyto "$(channel_target "$1")" "$2"
    channel_log down "$1"
}

channel_put() {
    rclone copyto "$1" "$(channel_target "$2")"
    channel_log up "$2"
}
