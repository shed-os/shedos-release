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

## Staging and production

`publisher/lib-channel.sh` is the only place the channel path is spelled out.
`CHANNEL_ROOT` defaults to `staging/`, so everything published today lands
under `staging/test/x86_64/` and the live repo is untouched. The cutover sets
`CHANNEL_ROOT` to the empty string and the same publisher writes
`test/x86_64/` for real. That one variable is the whole switch, and the test
suite covers both settings.

## Running the tests

```
bash test/publisher/run.sh
```

No root, no network, no R2. The bucket is a temporary directory that rclone
reads with its local backend, the signing key is generated and thrown away
with it, and the two packages it publishes are built with makepkg from
`test/publisher/fixtures/`.
