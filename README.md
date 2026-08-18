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

Beside every package it publishes, the publisher writes a `.origin` record
naming the repository, the run and the commit the request carried. The request
has always carried the commit and nothing read it, so a package in the channel
could not say which tree it came from. The record is what the release manifest
reads to pin a package whose PKGBUILD pins no tag.

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

## What a release is

`release-manifest.toml` is the release definition: the packages a release is
made of, where each one's source came from, and the exact published file the
name resolves to. It is authored state — a person writes it and a person reads
it — because everything downstream cuts from it, and a file a machine keeps
rewriting is one nobody checks.

```toml
[release]
version = "2026.08.09"

[[package]]
name = "shedos-theme-engine"
repo = "shedos-theme-engine"
ref = "2026.08.09"
pkgver = "2026.08.09"
pkgrel = "1"
sha256 = "7e8b46343285326315b04128294212c0f0171eeb6bf25c20b5cafd9db193918e"
```

`repo` is org-relative; the organisation is written once, in the resolver.

`tools/resolve-manifest.sh <manifest>` checks every pin against the world and
names the entry and the axis for anything that has moved:

- `ref` — the repository carries the tag, or the commit
- `pkgbuild` — the ref builds a package by that name
- `pkgver` — the PKGBUILD at the ref is at that pkgver
- `pkgrel` — for a tag, not *ahead* of the release the channel serves; behind is
  fine and normal, because the pipeline moves pkgrel past whatever the channel
  already carries every time it republishes and the tag does not follow. For a
  commit, exactly the released pkgrel: the commit names the tree the package was
  built from, and that tree carries the release or it is not the tree.
- `channel` — the signed database serves that name at that version and sha256
- `bytes` — the file the channel hands over hashes to that sha256

The last two are separate on purpose. Agreeing with the database only says the
manifest matches a record; what a later build fetches is the file, so the file
is fetched and hashed. Exit 1 is a pin that does not hold, exit 2 is a check
that could not be made — an unreadable channel must never read as a clean
release definition. A package the channel serves that the manifest does not
name is a note rather than a failure, because nothing is ever deleted from a
channel and a release may leave a retired package behind.

The manifest is refused rather than half-understood: a key nobody recognises,
an entry short of a field, a value shaped wrong or a name written twice stops
the run naming the entry.

`tools/draft-manifest.sh [<version>]` drafts one from what the channel serves,
so writing a manifest is reading eighteen entries rather than transcribing
eighteen checksums. It refuses to draft from a database whose signature does
not verify against the keyring the channel publishes, and a field it cannot
fill is left as a comment saying why — never guessed. It exits non-zero while
any field is still a hole, because a draft is not a manifest.

Where a PKGBUILD pins a tag, that tag is the ref and nothing is derived. Where
it pins none — seven of the eighteen packages on the channel — the ref is the
commit the release was built at, and the drafter finds it one of two ways. The
publisher records the commit of every request it serves beside the package it
published, so anything published since then is placed by what was recorded.
Anything published before is placed by reading the branch for the commit whose
PKGBUILD says that exact release, and the draft says so in a comment: a derived
answer and a recorded one are not the same quality of answer, and the reader
decides whether the difference matters. If the branch holds more than one such
commit the draft says that too, and leaves the entry as a hole, because
choosing quietly between two candidates is the one thing a drafting tool must
never do.

## When a publish goes missing

Every publish request in the org queues behind one concurrency group, and
GitHub keeps a single pending run per group: a request that arrives while
another is waiting takes the waiting one's place, and the waiting one is
cancelled. Fourteen repositories rebuilding at once is exactly that shape. The
build is green, the artifact is there, and the package never reaches the
channel — with nothing anywhere saying so, because the publisher keeps no
record of what it was asked.

`tools/reconcile-publishes.sh` asks from the other end. For every repository on
the publisher allowlist it reads the newest successful build on `main` that
still has its artifact, takes the packages out of that build's own `SHA256SUMS`
and asks whether the channel serves them. Anything missing has its publish
requested again on the ordinary `repository_dispatch` path — the publisher
stays the only writer, and every gate it has still runs. A channel already past
a build is not a dropped publish and is left alone.

`--dispatch` is what makes it ask; without it, it reports and requests nothing.
`.github/workflows/publish-reconcile.yml` runs it four times a day with
`--dispatch`, in its own concurrency group, because a reconcile queued behind a
publish would be cancelled by the next publish. Not hourly: reading a build
means downloading its artifact, and two of the fourteen repositories ship
packages north of fifty megabytes.

Its one blind spot is stated rather than solved: the publisher downloads the
packages from the run, so a build whose artifact has aged out cannot be
republished from by anything. The reconcile names every such run it steps over,
because falling back quietly to an older build that *is* in the channel is how
a dropped publish would disappear for good.

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

Almost every file under `tools/expected-diffs/` is now the other kind — a
tree-form enumeration, described below, which governs the source and carries
no allowlist of installed bytes. Those files keep what their artifact
comparison found as history instead, and `build-reference.sh --compare`
refuses them by name rather than handing `compare-package.sh` a file it would
die reading. Comparing those two packages again means building the reference,
reading the result against that history, and — if a whole-package check is
wanted — writing the one-line allowlist it needs out of the pins the file
keeps.

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

The reference is the monolith's build of the same source, and
`tools/build-reference.sh` is what builds it:

```
tools/build-reference.sh --compare /path/to/shedos \
    <candidate.pkg.tar.zst> [<commit>]
```

It reads the candidate's `.PKGINFO` and `.BUILDINFO`, takes the monolith
directory the carve maps say the package comes from, lays that source out in an
`archlinux` container the way the pipeline's checkout does, builds it there and
prints where it landed; `--compare` hands both packages to the tool above and
exits with what that says. Docker is all it needs on the machine running it.
The commit defaults to the clone's HEAD, and an expectation written against an
older one names the commit to pass here.

The expectation file it looks for is the package's own where there is one and
otherwise the carved repository's, because a repository carving several
packages enumerates its tree once for all of them.

The reference has to sit close enough to the pipeline's build that whatever is
left over belongs to the package rather than to the builder, which is why the
script insists on every one of these:

- the environment the candidate recorded rather than today's. The repositories
  move within the day, so every package its `.BUILDINFO` names at a version
  this build would otherwise get wrong comes back from
  `archive.archlinux.org`, and one that is on neither is a hard error naming
  the package — a reference built on a different compiler answers a question
  nobody asked
- the tree where the pipeline's checkout puts it. Cargo builds a package id out
  of the absolute path, so the same crate built elsewhere differs in `.text`.
  The path is `.BUILDINFO`'s `builddir` plus wherever the carved PKGBUILD's
  `build()` `cd`s to under `$srcdir` — for the shedos-ui packages, which clone
  themselves, `/__w/shedos-ui/shedos-ui/<pkg>/src/shedos-ui/<pkg>`. A `build()`
  that steps nowhere, like cage handing its source to meson, builds at the
  checkout itself, and one that `cd`s somewhere a variable names is refused
  rather than guessed at
- every crate the package's `Cargo.toml` reaches by `path`, laid out around it
  the way the carved repo lays them out. The five UI crates each declare
  `shedos-prompt-ui = { path = "../shedos-prompt-ui" }`, so that directory has
  to sit beside the one being built or `build()` stops at a `Cargo.toml` it
  cannot read
- `git archive`, never the working tree: the monolith's packaging directories
  hold build output and old artifacts that the commit does not
- the build job itself rather than something like it: the ShedOS channels
  enabled with the pipeline's own script, the build run as `builder` — a Rust
  binary records the registry paths under that account's home — `LC_ALL=C`,
  `SOURCE_DATE_EPOCH` from the candidate's `builddate`, and the `BUILDENV` and
  `OPTIONS` read back out of the candidate rather than copied from the pipeline
  and left to drift apart from it.

The run ends by naming the packages the two `.BUILDINFO`s do not share, and
there is one rule for reading that. Packages the candidate has and the
reference does not are the pipeline's own: it builds every package of a
multi-package repo in one container in its order, so each build sees whatever
the ones before it installed, and that residue changes nothing about what
compiled this one. A package either side holds at a *different version* is the
opposite — it says a pin did not take, and the reference is not one.

`pkgver` comes from the monolith and a candidate that disagrees is refused,
because taking it from the channel compares the carved repo against itself.
`pkgrel` is patched to the candidate's, because the carve republishes past the
monolith without a release behind it and `pkgrel` is a `.PKGINFO` field.

## Is the enumeration still true?

`tools/compare-package.sh` answers for a built package. For a package that was
split rather than moved there is no monolith package to build, and the question
becomes one about trees: does the carved repository still hold what the monolith
holds, and is everything that differs written down?
`tools/verify-enumeration.sh` answers that, and every enumeration acceptance
from here on cites it.

```
tools/verify-enumeration.sh repo tools/carve-maps/<name>.paths \
    /path/to/shedos <commit> /path/to/<carved-repo> <ref> \
    tools/expected-diffs/<name>.txt
```

It reads the maps file, maps every carved path back to the monolith path it was
taken from, and sorts the tree three ways: identical, transformed, and holding
no monolith counterpart. The expected-diffs file is optional — without one it
classifies and stops, which is the only thing to do for a repository whose
enumeration describes a built package. With one it reconciles the transformed
set in both directions and re-derives every pin, on the same terms the package
comparison uses: an entry that has stopped matching fails the run.

The pins here are git blobs rather than installed bytes, so a file's entry
survives a rebuild and stops matching only when the file itself moves. An
expectation file pinning sha256s is refused rather than reconciled — the two
questions cannot be answered out of one file.

The monolith is read with `git ls-tree` and never checked out, against the tree
at the named commit rather than the history. That is one place this differs
from `carve.sh` on purpose: an `except` naming a path only the history carries
is noted here and refused there, because the carve is what reads the history.

### The split, held together

A walk of one repository cannot answer the question a split raises. When files
leave a package for a sibling, each side ends up holding exactly what its own
map asked for — and a file that left and arrived nowhere looks the same from
either side as a file that arrived safely.

```
tools/verify-enumeration.sh set tools/carve-maps \
    /path/to/shedos <commit> packaging/<the directory that split> \
    <name>=/path/to/<repo> ...
```

Every file under that directory has to be claimed by exactly one map and held
by the repository that map belongs to. A file no map claims is a file the split
deleted in silence. The members are derived from the maps rather than from the
command line, so leaving one repository out is refused by name instead of
turning its share of the split into a pile of unclaimed files.

## Running the tests

```
bash test/publisher/run.sh
bash test/carve/run.sh
bash test/compare/run.sh
bash test/enumeration/run.sh
bash test/trust-anchor/run.sh
bash test/version-parity/run.sh
bash test/build-reference/run.sh
bash test/manifest/run.sh
bash test/reconcile/run.sh
```

The first four take no root, no network and no R2. The bucket is a temporary
directory that rclone reads with its local backend, the signing key is
generated and thrown away with it, and every package involved is built with
makepkg from the fixtures beside each suite. The enumeration suite builds its
monolith and the repositories a carve of it would produce with git in the same
temporary directory; the three cases at its end re-derive the figures the
carves were accepted on, which needs clones of the monolith and two carved
repositories, and it names whichever is missing when it skips. The trust anchor
and version checks read what they compare over HTTP. The reference suite plans real builds
against fixtures of its own and stops short of the container; its end-to-end
case rebuilds a published package and checks it against the sha its expectation
pins, which needs docker and a monolith clone, and it names whichever is
missing when it skips.

The manifest and reconcile suites build a channel of their own — a directory of
real files under a real signed database — and real git repositories with real
tags, so the tools run against fixtures without a line of their own swapped
out. The reconcile suite puts a stub `gh` on `PATH` that answers out of files
each case writes and keeps every dispatch it is handed, so a case can read what
was actually asked for. The manifest suite's last case resolves the committed
manifest against the live channel and says so when there is none to resolve.

`.github/workflows/ci.yml` runs every suite on every push and pull request,
because this repo is the only thing in the org that can write to a channel.
