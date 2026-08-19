#!/usr/bin/env bash
# reconcile-publishes.sh [--dispatch]
#
# Every package repository funnels its publish request through one concurrency
# group, and GitHub keeps one pending run per group: a request that arrives
# while another is already waiting takes the waiting one's place and the
# waiting one is cancelled. Fourteen repositories rebuilding at once is exactly
# that shape. The build is green, the artifact is there, the request was sent,
# and the package never reaches the channel — with nothing anywhere saying so,
# because the publisher keeps no record of what it was asked.
#
# So this asks the question from the other end: for each repository, what did
# its last successful build on main produce, and is the channel serving it? A
# package that is missing gets its publish requested again through the ordinary
# path. Nothing here signs anything, writes to the bucket or talks to R2; the
# publisher stays the only writer, and this only makes it an offer it already
# knows how to refuse.
#
# Without --dispatch it says what it found and asks for nothing, which is what
# a hand run should do. The scheduled job passes it.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
# shellcheck source=tools/lib-manifest.sh
source "$HERE/lib-manifest.sh"

ALLOWLIST=${SHEDOS_RECONCILE_ALLOWLIST:-$ROOT/publisher/allowlist.txt}
NOREPUBLISH=${SHEDOS_NOREPUBLISH_FILE:-$ROOT/packages/aur-norepublish.txt}
INSTALLER_ONLY=${SHEDOS_INSTALLER_ONLY_FILE:-$ROOT/publisher/installer-only.txt}
RELEASE_REPO=${SHEDOS_RECONCILE_TARGET:-shed-os/shedos-release}
# How far back to look for a build that still has its artifact. A run whose
# artifact has expired cannot be republished from, and no number here changes
# that.
LOOKBACK=${SHEDOS_RECONCILE_LOOKBACK:-10}
# The workflow that builds. Asking for every successful run on main instead
# would let a repository's other workflows fill the window above, so the build
# this is looking for falls out of it and a complete channel reads as a
# repository with no usable build at all.
WORKFLOW=${SHEDOS_RECONCILE_WORKFLOW:-ci.yml}

dispatch=0
case ${1:-} in
    '') ;;
    --dispatch) dispatch=1 ;;
    *) echo 'usage: reconcile-publishes.sh [--dispatch]' >&2; exit 2 ;;
esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for file in "$ALLOWLIST" "$NOREPUBLISH" "$INSTALLER_ONLY"; do
    [[ -f $file ]] || { echo "reconcile: $file does not exist" >&2; exit 2; }
done

uncommented() { awk 'NF && $1 !~ /^#/' "$@"; }

served=$WORK/served.tsv
channel_database "$WORK" > "$served" || exit 2

mapfile -t excluded < <(uncommented "$NOREPUBLISH" "$INSTALLER_ONLY")

missing=0
requested=0
unreachable=0

# The publisher's own reading of a package file name, so the two agree about
# what a package is called before one asks the other for it.
package_name() { printf '%s\n' "${1%-*-*-*.pkg.tar.zst}"; }

package_version() {
    local file=$1 name=$2 rest=${1%-*.pkg.tar.zst}
    printf '%s\n' "${rest#"$name"-}"
}

excluded_package() {
    local name=$1 entry
    for entry in ${excluded[@]+"${excluded[@]}"}; do
        [[ $name != "$entry" ]] || return 0
    done
    return 1
}

# The newest successful build on main that still has the artifact its publish
# request would name. Prints "<run id>\t<sha>", empty when there is none.
#
# An artifact expires long before the channel forgets the package, and a build
# whose artifact is gone cannot be republished from by anyone — the publisher
# downloads it from the run. Every newer build this has to step over is said
# out loud, because stepping over one quietly is how a dropped publish becomes
# invisible: the older build it falls back to is in the channel, and the run
# that never landed is never mentioned again.
latest_build() {
    local repo=$1 id='' sha=''
    while read -r id sha; do
        [[ -n $id ]] || continue
        if ! gh api "repos/$repo/actions/runs/$id/artifacts" \
                --jq '.artifacts[] | select(.expired | not) | .name' 2> /dev/null \
                | grep -qxF "pkg-$sha"; then
            echo "$repo: run $id succeeded on main and its artifact is gone" >&2
            continue
        fi
        printf '%s\t%s\n' "$id" "$sha"
        return 0
    done < <(gh api \
        "repos/$repo/actions/workflows/$WORKFLOW/runs?branch=main&status=success&per_page=$LOOKBACK" \
        --jq '.workflow_runs[] | "\(.id)\t\(.head_sha)"' 2> /dev/null)
    return 1
}

# What that build produced, as the publisher would read it: "<file>\t<sha256>"
# out of the artifact's own checksum manifest rather than out of a file name.
build_packages() {
    local repo=$1 id=$2 dir=$WORK/artifact
    rm -rf "$dir"
    gh run download "$id" --repo "$repo" --name "pkg-$3" --dir "$dir" > /dev/null 2>&1 \
        || return 1
    [[ -s $dir/SHA256SUMS ]] || return 1
    awk 'NF { print $NF "\t" $1 }' "$dir/SHA256SUMS"
}

# The request goes out in the shape the publisher documents and validates, on
# the ordinary repository_dispatch path. It carries the sha256s the build
# recorded, which the publisher rehashes against the artifact it downloads
# itself — this cannot make it trust anything it would not have trusted.
request_publish() {
    local repo=$1 id=$2 sha=$3 packages=$4 payload=$WORK/payload.json
    jq -n \
        --arg repo "$repo" \
        --argjson run_id "$id" \
        --arg sha "$sha" \
        --argjson packages "$packages" \
        '{event_type: "publish-request",
          client_payload: {
              repo: $repo,
              run_id: $run_id,
              sha: $sha,
              artifact: ("pkg-" + $sha),
              packages: $packages
          }}' > "$payload" || return 1
    gh api "repos/$RELEASE_REPO/dispatches" --method POST --input "$payload" > /dev/null
}

while read -r repo; do
    build=$(latest_build "$repo") || {
        echo "$repo: no successful build on main still holding its artifact"
        unreachable=$((unreachable + 1))
        continue
    }
    IFS=$'\t' read -r run_id sha <<<"$build"

    built=$(build_packages "$repo" "$run_id" "$sha") || {
        echo "$repo: the artifact of run $run_id could not be read"
        unreachable=$((unreachable + 1))
        continue
    }

    absent=()
    while IFS=$'\t' read -r file _; do
        [[ -n $file ]] || continue
        name=$(package_name "$file")
        if excluded_package "$name"; then
            echo "$repo: $name is on a no-republish list and is not asked for"
            continue
        fi
        version=$(package_version "$file" "$name")
        entry=$(awk -F'\t' -v n="$name" '$1 == n { print; exit }' "$served")
        if [[ -z $entry ]]; then
            absent+=("$name $version")
            continue
        fi
        IFS=$'\t' read -r _ have have_file _ <<<"$entry"
        [[ $have_file != "$file" ]] || continue
        # A channel ahead of the build is not a dropped publish, it is a build
        # the channel has already moved past, and asking for it again would be
        # asking the publisher to walk the channel backwards.
        if (( $(vercmp "$have" "$version") >= 0 )); then
            echo "$repo: the channel is at $name $have, past this build's $version"
            continue
        fi
        absent+=("$name $version")
    done <<<"$built"

    if (( ${#absent[@]} == 0 )); then
        echo "$repo: the channel has everything run $run_id built"
        continue
    fi

    missing=$((missing + ${#absent[@]}))
    for entry in "${absent[@]}"; do
        echo "$repo: the channel is missing $entry from run $run_id"
    done

    if (( dispatch == 0 )); then
        echo "$repo: not asking for it, because --dispatch was not given"
        continue
    fi

    packages=$(awk -F'\t' '{ print $1 "\t" $2 }' <<<"$built" \
        | jq -Rn '[inputs | split("\t") | {file: .[0], sha256: .[1]}]')
    if request_publish "$repo" "$run_id" "$sha" "$packages"; then
        echo "$repo: publish requested again for run $run_id"
        requested=$((requested + 1))
    else
        echo "$repo: the publish request could not be sent"
        unreachable=$((unreachable + 1))
    fi
done < <(uncommented "$ALLOWLIST")

printf '\n%d package(s) missing, %d request(s) sent, %d repository(s) could not be read\n' \
    "$missing" "$requested" "$unreachable"

(( unreachable == 0 )) || exit 2
(( missing == 0 )) || exit 1
