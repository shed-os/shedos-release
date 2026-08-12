# Maps files

A maps file tells `carve.sh` which part of the monolith belongs to a package
repo. One directive per line, `#` starts a comment, and blank lines are
ignored. Every directive needs a value.

```
path <dir>              keep <dir> where it sits
rename <old>:<new>      keep <old> too and move it to <new>
flatten <dir>           keep <dir> and lift its contents to the repo root
new-package <name>      <name> is a package the monolith does not build
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

The suite then has to be re-rooted in the carved repo: every carve so far
reached its package through the `packaging/<name>/` prefix that `flatten` has
just removed, and a suite still spelling it out dies before its first fixture.

## A package the monolith does not build

A split that takes part of one package and gives it a new name has nothing on
the monolith side to compare against: there is no `packaging/shedman/PKGBUILD`
and there never was. `new-package shedman` says so, and the version check reads
it as a package it names and does not pair rather than one that quietly fell
out of the comparison. It selects nothing, so a maps file holding only that
directive still carves nothing and says so.

Such a map takes its files with `rename` a file at a time — `path` and
`flatten` take whole directories, and the point of the split is that the
directory belongs to two repos now. Note that a `rename` whose source still
exists in the monolith brings that file's later commits along to the
destination, so a path the monolith still uses for something else cannot be
chased back through.

## A map with no carve behind it

`shedos-branding` was imported rather than carved: the package is mostly
wallpapers that have been redrawn many times, and nobody needed that history in
every clone, so no rewrite ever ran against the monolith for it. Its maps file
is here anyway, because the version check derives its pairs from this
directory — a package with no maps file is a package nothing compares against
the monolith. Such a file says at the top that there was no carve, and is
otherwise an ordinary maps file that `carve.sh` has never been pointed at.

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

A rename also carves a package into a subdirectory, which is what a repo that
already has a history of its own needs:

```
path packaging/shedos-hyprland-plugin-hyprspace/
rename packaging/shedos-hyprland-plugin-hyprspace:packaging
```

The fork's own source keeps the root and the package build lands under
`packaging/`, where the pipeline's `packages: ["packaging"]` looks for it. The
`path` line is not redundant here: the version check pairs a repo with the
monolith directory a directive names, and after the rename the only monolith
path left in the file would be the destination. Named this way, the check also
reads the destination as where the carved PKGBUILD ended up, so it compares
`packaging/PKGBUILD` rather than the root.

## Several packages in one repo

Packages that share a dependency graph carve together rather than one repo
each. Every package keeps its own directory, so the crate paths between them
still resolve and each PKGBUILD stays beside the crate it builds:

```
path packaging/shedos-greeter/
rename packaging/shedos-greeter:shedos-greeter
```

one pair per package, six of them for `shedos-ui`. The version check reads the
PKGBUILD each rename destination holds, so every packaging directory in such a
map has to name a destination of its own: two of them carved to the same place
is the same ambiguity as a map naming two packaging directories and no
destination at all.

A directory the monolith builds no package from is skipped by name rather than
counted. `shedos-prompt-ui` is the library the other five link against and it
carves along with them because the dependency graph needs it. The monolith is
what decides that — the check reads its PKGBUILD first — and a directory the
monolith does build a package from is still an error when the carved repo has
no PKGBUILD for it.

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

## Before a carve or a compare

Both read the monolith, so the clone has to be level with `origin/main` before
either runs — fetch, check, and write the commit down beside whatever the run
produces. A clone one commit behind carves the version from before the last
release, and the channel then serves what reads as a downgrade. The compare
carries that requirement plus one of its own: the reference's `pkgver` and
`pkgrel` come from the monolith's PKGBUILD, never from the version the
candidate's channel happens to hold. Taking them from the channel compares the
carved repo against itself, and passes whatever the carve got wrong.

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

Those five carve together into `shedos-ui`, one directory each, so a plain
`src/` line — which is right for every other package — would untrack the crate.
That repo must not ignore `src/` at all. Nothing warns you: the files just
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
