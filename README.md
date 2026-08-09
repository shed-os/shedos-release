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

It compares the `.PKGINFO` fields, the file manifests and then the bytes of
every shared path, and it reports everything it found rather than stopping at
the first thing. Exit 0 means nothing separates the two that wasn't expected
and written down.

Only content differences can be expected, one per line in the package's
expected-diffs file:

```
content <path> — <reason>
```

A field that moved or a file that appeared is never allowlistable, because
that is exactly the drift the check exists to catch. Every expectation that
matched is printed, and one that has stopped matching anything fails the run,
so an allowlist cannot outlive the difference it was written for.

Two `.PKGINFO` fields are ignored — `builddate` and `packager` say when and
where a build ran, never what it built. `size` is reported as a note rather
than a difference: it is the sum of the installed bytes, so it moves if and
only if some file's content moved, and the content tier already names the path
that did.

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
