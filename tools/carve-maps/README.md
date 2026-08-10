# Maps files

A maps file tells `carve.sh` which part of the monolith belongs to a package
repo. One directive per line, `#` starts a comment, and blank lines are
ignored. Every directive needs a value.

```
path <dir>              keep <dir> where it sits
rename <old>:<new>      keep <old> too and move it to <new>
flatten <dir>           keep <dir> and lift its contents to the repo root
```

They compose. A package repo usually takes its packaging directory and its
out-of-tree test suite, which is two directives:

```
flatten packaging/shedos-ui
path test/shedos-ui/
```

That carves `packaging/shedos-ui/*` to the repo root, where the pipeline's
`packages: ["."]` expects the PKGBUILD, and leaves `test/shedos-ui/` where it
is, where the pipeline's `test/*/run.sh` expects it.

## Renames

`rename old:new` is for a directory that moved inside the monolith. It keeps
both the source and the destination and replays the move, so the commits from
before it are still in the file's history and `git blame` reaches them.

Two forms look right and are not:

- `rename old:new` on its own **used to** keep the whole monolith.
  `--path-rename` is not a filter — it renames what matches and keeps
  everything else. `carve.sh` now passes `--path old` alongside it, so the
  directive filters as well as moves.
- Naming only the destination (`path new` plus a rename) silently starts the
  history at the move and drops every commit from before it, which is the exact
  blame the directive exists to preserve.

Writing `path new` next to `rename old:new` is fine and is the clearer form —
it says what the repo ends up holding. It changes nothing, because the rename
already declares both ends.

## Matching

`path` and `rename` match whole path components, the way filter-repo does:
`path old` takes `old/` and a file named exactly `old`, and leaves `oldies/`
alone. Trailing slashes are optional and are the clearer way to write a
directory.

## What happens before the push

`carve.sh` rebuilds the history, then — before it pushes anything — checks the
result against the maps file: the carve has to keep at least one commit, and
every path it touches has to be one the maps file asked for. A carve that
overreaches dies locally, where the fix is to edit the maps file and run again.
Getting that wrong on the remote instead would leave a force-push as the only
way out.

`test/carve/run.sh` covers this, including a broken copy of `carve.sh`, so the
check is proven to fire.

## Running one

```
tools/carve.sh /path/to/shedos <target-repo> tools/carve-maps/<target>.paths
```

Needs `git-filter-repo` installed. `SHEDOS_CARVE_REMOTE` overrides the push
target, which defaults to `git@github.com:shed-os/<target-repo>.git`.

## .gitignore rules a carve has to carry over

The monolith's `.gitignore` covers every package at once. A carved repo needs
its own, and two of the monolith's rules do real work that a generic
`.gitignore` would undo.

**The Rust package repos.** The monolith ignores `packaging/*/src/` because
that is where makepkg extracts sources, and then exempts five packages whose
`src/` holds the actual Rust code (`.gitignore:29-33`):

```
!packaging/shedos-greeter/src/
!packaging/shedos-prompt-ui/src/
!packaging/shedos-power/src/
!packaging/shedos-tour/src/
!packaging/shedos-switcher/src/
```

Those five carve to repos where the PKGBUILD sits at the root, so a plain
`src/` line — which is right for every other package — would untrack the crate.
Their repos must not ignore `src/` at all. Nothing warns you: the files just
stop being tracked on the next commit.

**The keyring repo.** The monolith guards against committing private key
material (`.gitignore:125`):

```
packaging/shedos-keyring/shedos-private.asc
*-private.asc
```

The keyring carve has to keep the `*-private.asc` guard, rewritten for the
flattened layout. The key ceremony writes the private key next to the PKGBUILD,
so without it one `git add -A` publishes the repo signing key.

cage's `.gitignore` is the ordinary case and is correct as it shipped: makepkg
byproducts, the downloaded source tarball, and the pipeline's `dist/`.
