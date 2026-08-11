# shedos-release

The release side of ShedOS. Package repositories build; this repo signs what
they built and writes it into the package channels on R2. Later it also grows
the release manifests, the ISO build and the release gates — for now it holds
the channel publisher.

## The security invariant

The signing key and the R2 credentials live here and nowhere else. A package
repo can build anything it likes and ask for it to be published; it cannot
sign it and it cannot touch the bucket. Every change to this repo has to keep
that true.

The publisher checks a request in this order, and stops at the first thing
that doesn't hold:

1. the requesting repo is on `publisher/allowlist.txt`
2. every package listed is present and hashes to what the payload claims
3. no package is on the no-republish lists, and none is a `-debug` build
4. the imported signing key's fingerprint is one the fleet trusts
5. the bootstrap keyring about to be published holds that same key
6. no package is older than the version the channel already serves

Both lists behind 4 and 5 are read out of the `shedos-keyring` package the
channel serves, checked against the sha256 its database records, so the
publisher and the fleet trust the same file. A first publish into an empty
channel has no such package to read and takes them from the keyring in the
request; a request that brings none is refused.

Only then does anything get signed. Nothing already in a channel is ever
deleted — retiring a package is a separate, deliberate act.

## How a publish happens

A package repo runs the shared pipeline in `shed-os/shedos-ci`. When a build
on `main` succeeds, it sends a `publish-request` repository dispatch here with
this payload:

```json
{"repo": "shed-os/<name>", "run_id": 0, "sha": "<commit>", "artifact": "pkg-<sha>",
 "packages": [{"file": "<name>-<ver>-<rel>-x86_64.pkg.tar.zst", "sha256": "<hex>"}]}
```

`.github/workflows/channel-publisher.yml` picks it up, downloads that run's
artifact from the sending repo, imports the signing key, and hands both to
`publisher/publish.sh`. Every publish in the org runs through one concurrency
group, because folding packages into the channel database is a
read-modify-write and two at once would lose one of them.

The database is updated in place: the publisher pulls the current
`shedos.db.tar.gz` and `shedos.files.tar.gz` down, adds the new packages, and
puts them back. Packages upload before the database, so a machine that pulls
mid-publish never sees an entry whose file isn't up yet. The database is then
mirrored as `shedostest.*` so a stable box can opt into the canary.

The public keyring goes up beside the packages as `shedos.gpg` at the channel
root, because a box migrating from Arch fetches it before it owns a single
ShedOS package and has nothing else to verify the repo with.

Until this repo owns the keyring, the trusted-keys list and that `shedos.gpg`
are fetched from the monolith on every publish, and both fetches send a
descriptive User-Agent. Any fetch this repo later makes from `repo.shedos.org`
has to send one too. Cloudflare's managed rules drop datacenter traffic that
does not name itself, and a GitHub runner is a datacenter address: a bare
`curl` gets 403 from CI while working perfectly from a desk, which is the
worst shape a failure can take.

If the publisher cannot read what the channel currently holds, it stops.
"I couldn't list it" and "there's nothing there" have to stay different
answers, or a failed listing would look like an empty channel and the run
would write a database holding only its own packages over a live one.

## Staging and production

`publisher/lib-channel.sh` is the only place the channel path is spelled out.
`CHANNEL_ROOT` defaults to `staging/`, so today the packages and database land
under `staging/test/x86_64/`, the keyring lands at `staging/shedos.gpg`, and
the live repo is untouched. Both paths are built from that one variable: the
cutover sets it to the empty string and the same publisher writes
`test/x86_64/` and `shedos.gpg` for real. The test suite covers both settings.

## Is it the same package?

`tools/compare-package.sh` answers the question the cutover turns on: did the
per-repo pipeline build the same package the monolith did?

```
tools/compare-package.sh <reference.pkg.tar.zst> <candidate.pkg.tar.zst> \
    tools/expected-diffs/<package>.txt
```

It compares the `.PKGINFO` fields, the file manifests, the bytes of every
shared path, and the mode, owner and type `.MTREE` recorded at build time. It
reports everything it found rather than stopping at the first thing. Exit 0
means nothing separates the two that wasn't expected and written down.

Only content differences can be expected, one per line in the package's
expected-diffs file, in either form:

```
content <path> — <reason>
content <path> <ref-sha256>..<cand-sha256> — <reason>
```

The second pins the entry to one exact difference: if either side's bytes
change again the entry stops matching and the new difference is unexplained.
The first still works and is still credited, but the tool notes it as unpinned,
because an unpinned entry keeps forgiving that path whatever later happens to
it. Prefer the pinned form.

A field that moved, a file that appeared or a mode that changed is never
allowlistable, because that is exactly the drift the check exists to catch.
Every expectation that matched is printed, and one that has stopped matching
anything fails the run, so an allowlist cannot outlive the difference it was
written for.

`builddate` and `packager` are ignored — they say when and where a build ran,
never what it built. `size` is reconciled rather than ignored: the tool adds up
the lengths the content findings account for and compares that against the
size the two packages claim. When the two agree it is only a note. When they
don't, it is a finding, because makepkg counts a hardlinked file once — two
packages can carry identical manifests and identical bytes and still install
different amounts.

Mode and ownership come from `.MTREE` rather than from the extracted files:
the tool unpacks unprivileged, so a setuid bit would not survive into the
extracted tree, and that is the difference most worth catching. Timestamps are
the one column left out — they are why `.MTREE` can't be compared whole.

### Building the reference

The reference is the monolith's build of the same source, and it has to sit
close enough to the pipeline's that whatever is left over belongs to the
package rather than to the builder. What that takes:

- the build job itself rather than something like it: an `archlinux` container
  with the ShedOS channels enabled, the build run as `builder` — a Rust binary
  records the registry paths under that account's home — and the drop-in
  `BUILDENV` and `OPTIONS` the pipeline writes beside its makepkg config
- `LC_ALL=C`, and `SOURCE_DATE_EPOCH` set to the candidate's `builddate`
- the packages the candidate's `.BUILDINFO` names, at the versions it names.
  The repos move within the day and `archive.archlinux.org` is where the ones
  that moved come back from. Building every package of a multi-package repo in
  one container in the pipeline's order reproduces the rest, since each build
  there sees whatever the builds before it installed
- every crate the package's `Cargo.toml` reaches by `path`, laid out around it
  the way the carved repo lays them out. The five UI crates each declare
  `shedos-prompt-ui = { path = "../shedos-prompt-ui" }`, so that directory has
  to sit beside the one being built or `build()` stops at a `Cargo.toml` it
  cannot read
- the tree where the pipeline's checkout puts it. Cargo builds a package id out
  of the absolute path, so the same crate built elsewhere differs in `.text`.
  The path is `.BUILDINFO`'s `builddir` plus wherever the carved PKGBUILD `cd`s
  to under `$srcdir` — for the shedos-ui packages, which clone themselves,
  that is `/__w/shedos-ui/shedos-ui/<pkg>/src/shedos-ui/<pkg>`, with
  `shedos-prompt-ui` beside it
- `git archive`, never the working tree: the monolith's packaging directories
  hold build output and old artifacts that the commit does not.

## Running the tests

```
bash test/publisher/run.sh
bash test/carve/run.sh
bash test/compare/run.sh
```

No root, no network, no R2. The bucket is a temporary directory that rclone
reads with its local backend, the signing key is generated and thrown away
with it, and every package involved is built with makepkg from the fixtures
beside each suite. `.github/workflows/ci.yml` runs all three on every push and
pull request, because this repo is the only thing in the org that can write to
a channel.
