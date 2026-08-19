# shellcheck shell=bash
# What the two metapackage generators agree about: where their inputs are, how
# a package list is read, and what the resolved closure says. Sourced, never
# run.
#
# The closure resolver and the renderer used to learn about each other by
# reading each other's source — the resolver ran awk over the renderer to find
# the conflicts array it would emit. Everything they share is a file now, and
# this is how both read it.

# SHEDOS_META_ROOT puts the inputs and the output somewhere else, which is how
# the suite hands the generators a world of their own instead of editing the
# lists this repository ships.
META_ROOT=${SHEDOS_META_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
META_PACKAGES=$META_ROOT/packages
META_CLOSURE=$META_PACKAGES/.meta-closure.txt
META_CONFLICTS=$META_PACKAGES/meta-conflicts.txt
META_MANIFEST=$META_ROOT/release-manifest.toml
META_PKGBUILD=$META_ROOT/packaging/shedos-meta/PKGBUILD
# The package being generated. Written once because two places need it and
# they must not drift: the PKGBUILD's own pkgname, and the name the generator
# has to keep out of the depends it builds from the manifest.
META_PKGNAME=shedos-meta

# shellcheck source=tools/lib-manifest.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib-manifest.sh"

# The names a package list holds, one per line, comments and blanks gone. A
# list that is not there is a refusal rather than an empty answer: every one of
# these decides what does not go into the metapackage, and a missing
# aur-norepublish.txt read as "nothing" would make ten packages we may not
# redistribute into hard dependencies of it.
# A list holding no names is a fine answer and grep says 1 to it, so the two
# are told apart here rather than at every call site.
list_names() {
    [[ -f $1 ]] || { echo "ERROR: $1 is missing." >&2; return 1; }
    grep -Ev '^\s*(#|$)' "$1"
    (( $? <= 1 ))
}

# The closure is one package per line, and a line may carry a second
# tab-separated field saying the channel serves that name rather than Arch.
# cage is the whole reason: it is declared as an Arch root in
# packages/official/desktop.txt and the package a ShedOS box actually installs
# is our own repackage of it. Nothing but repository order used to decide
# which one arrived, and repository order is not a decision.
closure_names()    { list_names "$1" | cut -f1; }
closure_replaced() { list_names "$1" | awk -F'\t' '$2 == "replaced" { print $1 }'; }

# "<name>\t<pkgver>\t<pkgrel>" for every package the manifest names, in the
# order the manifest writes them. The schema check is manifest_read's and a
# manifest it refuses stops the caller here.
manifest_entries() {
    manifest_read "$1" | awk -F'\t' '$1 == "package" { print $2 "\t" $5 "\t" $6 }'
}

# The release the manifest defines, which is the metapackage's pkgver.
manifest_version() {
    manifest_read "$1" | awk -F'\t' '$1 == "release" { print $2 }'
}
