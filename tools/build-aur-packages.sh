#!/bin/bash
# Build AUR packages for ShedOS.
#
# Populates archiso/shedos-repo/ with .pkg.tar.zst files for every
# package listed in packages/aur.txt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
AUR_BUILD_DIR="/tmp/shedos-aur-build"
REPO_DIR="$PROJECT_ROOT/archiso/shedos-repo"

# Register $REPO_DIR as a build-local pacman repo for the duration of
# this script so makepkg --syncdeps resolves AUR-internal deps (e.g.
# libfprint-2-tod1-broadcom -> libfprint-tod, walker -> elephant)
# regardless of whether the prereq was just built or restored from the
# GHA cache. Mirrors build-shedos-packages.sh's [shedos-repo]
# registration; uses a distinct section name + mount path so the two
# scripts never collide if their setup blocks ever overlap in time.
PUBLIC_REPO_DIR="/srv/shedos-aur-build-repo"
PACMAN_CONF_BACKUP="/tmp/shedos-aur-pacman.conf.bak"
PACMAN_CONF_MARKER="# >>> shedos-aur-build-local-repo (temporary) >>>"

echo "=========================================="
echo "Building AUR packages for ShedOS"
echo "=========================================="

# Create directories
mkdir -p "$REPO_DIR"
mkdir -p "$AUR_BUILD_DIR"
chmod 777 "$AUR_BUILD_DIR"

# Truncate the rebuild manifest at the start of every run.
# build-shedos-packages.sh appends to this file too; the gate in
# build-packages.yml's "Build repo DB" step checks it for non-empty
# to decide whether to actually repo-add fresh entries.
: > /tmp/built-pkgs.txt

_strip_aur_pacman_block() {
    # Idempotent re-entry: drop any prior registration block before re-adding.
    if grep -qF "$PACMAN_CONF_MARKER" /etc/pacman.conf 2>/dev/null; then
        sed -i "/$(printf '%s' "$PACMAN_CONF_MARKER" | sed 's/[][\/.^$*]/\\&/g')/,/# <<< shedos-aur-build-local-repo (temporary) <<</d" /etc/pacman.conf
    fi
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Running as root, creating build user..."

    _strip_aur_pacman_block
    cp /etc/pacman.conf "$PACMAN_CONF_BACKUP"

    # Bind-mount the repo at a stable path so pacman's alpm sandbox can
    # reach it without traversing the runner's $HOME (which it can't).
    mkdir -p "$PUBLIC_REPO_DIR"
    mountpoint -q "$PUBLIC_REPO_DIR" && umount "$PUBLIC_REPO_DIR"
    mount --bind "$REPO_DIR" "$PUBLIC_REPO_DIR"

    cat >> /etc/pacman.conf <<EOF

$PACMAN_CONF_MARKER
[shedos-repo]
SigLevel = Never
Server = file://$PUBLIC_REPO_DIR
# <<< shedos-aur-build-local-repo (temporary) <<<
EOF

    # Cleanup runs on ANY exit path (success, error, signal) so we never
    # leave stale builduser, sudoers file, pacman.conf block, or bind
    # mount behind between runs.
    _cleanup_builduser() {
        echo "Cleaning up build user..."
        userdel -r builduser 2>/dev/null || true
        rm -f /etc/sudoers.d/builduser-aur
        if [[ -f "$PACMAN_CONF_BACKUP" ]]; then
            mv "$PACMAN_CONF_BACKUP" /etc/pacman.conf
        fi
        if mountpoint -q "$PUBLIC_REPO_DIR" 2>/dev/null; then
            umount "$PUBLIC_REPO_DIR" 2>/dev/null || true
        fi
        rmdir "$PUBLIC_REPO_DIR" 2>/dev/null || true
    }
    trap _cleanup_builduser EXIT

    # Create temporary build user
    useradd -m -G wheel builduser 2>/dev/null || true
    echo "builduser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builduser-aur
    chmod 440 /etc/sudoers.d/builduser-aur

    # Setup rustup for build user (needed for Rust AUR packages like impala)
    if command -v rustup &> /dev/null; then
        echo "Setting up Rust toolchain for build user..."
        sudo -u builduser rustup default stable 2>/dev/null || true
    fi
fi

# Full registration of every .pkg.tar.zst in $REPO_DIR with
# [shedos-repo]'s DB. Called once after the phantom sweep so cached
# AUR pkgs are visible to makepkg --syncdeps from the first build
# iteration onward.
_refresh_repo_db() {
    local pkg_count
    pkg_count=$(find "$REPO_DIR" -maxdepth 1 -name '*.pkg.tar.zst' 2>/dev/null | wc -l)
    if (( pkg_count == 0 )); then
        return 0
    fi
    (
        cd "$REPO_DIR"
        # -p: prevent-downgrade so the highest version always wins, even
        # when glob expansion lex-sorts pkgrel "10" before "7".
        repo-add -p shedos-repo.db.tar.gz ./*.pkg.tar.zst >/dev/null
    )
    # Guard against repo-add silently exiting 0 without producing a DB
    # (mirrors build-shedos-packages.sh's same guard).
    if [[ ! -e "$REPO_DIR/shedos-repo.db" ]]; then
        echo "ERROR: $REPO_DIR/shedos-repo.db missing after repo-add" >&2
        ls -la "$REPO_DIR" | head -20 >&2
        return 1
    fi
    if [[ $EUID -eq 0 ]]; then
        # -y without -u: refresh pacman's local DB cache from the
        # rebuilt [shedos-repo] DB without touching the host system's
        # installed packages.
        pacman -Sy --noconfirm >/dev/null
    fi
}

# Register only the .pkg.tar.zst files under $1 (the makepkg output
# directory for the package just built). Per-iteration variant of
# _refresh_repo_db that avoids the O(N²) "already existed" repo-add
# warnings a full glob would emit every loop pass.
_repo_add_built() {
    local src_dir=$1
    shopt -s nullglob
    local fresh_pkgs=("$src_dir"/*.pkg.tar.zst)
    shopt -u nullglob
    (( ${#fresh_pkgs[@]} > 0 )) || return 0
    local pkg_basenames=() f
    for f in "${fresh_pkgs[@]}"; do
        pkg_basenames+=("$(basename "$f")")
    done
    (
        cd "$REPO_DIR"
        repo-add -p shedos-repo.db.tar.gz "${pkg_basenames[@]}" >/dev/null
    )
    if [[ $EUID -eq 0 ]]; then
        pacman -Sy --noconfirm >/dev/null
    fi
}

# Read AUR packages from packages/aur.txt (single source of truth)
AUR_FILE="$PROJECT_ROOT/packages/aur.txt"
if [ ! -f "$AUR_FILE" ]; then
    echo "ERROR: AUR package list not found: $AUR_FILE"
    exit 1
fi

# Read packages, filtering out comments and empty lines
mapfile -t AUR_PACKAGES < <(grep -v '^#' "$AUR_FILE" | grep -v '^$' | tr -d ' ')
echo "Found ${#AUR_PACKAGES[@]} AUR packages to build"

# Drop cached packages whose source name was removed from aur.txt.
# Without this they'd be re-signed and republished into shedos.db,
# leaving 404-able entries once retention sweep deletes the file.
declare -A keep_aur=()
for p in "${AUR_PACKAGES[@]}"; do
    keep_aur[$p]=1
done
phantom_count=0
shopt -s nullglob
for f in "$REPO_DIR"/*.pkg.tar.zst; do
    base=$(basename "$f")
    pkgname=${base%-*-*-*.pkg.tar.zst}
    [[ "$pkgname" == shedos-* ]] && continue
    parent=${pkgname%-debug}
    if [[ -z ${keep_aur[$parent]:-} ]]; then
        echo "  prune phantom AUR: $base"
        rm -f "$f" "${f}.sig"
        phantom_count=$((phantom_count + 1))
    fi
done
shopt -u nullglob
if (( phantom_count > 0 )); then
    echo "Phantom sweep: removed $phantom_count stale AUR package file(s)"
    # Force the downstream cache-skip gate to rebuild the repo DB.
    echo "phantom-sweep" >> /tmp/built-pkgs.txt
fi

# Register the cached set with [shedos-aur-build] before the build loop
# runs makepkg --syncdeps. Without this, an AUR pkg that depends on a
# cached AUR pkg (e.g. libfprint-2-tod1-broadcom -> libfprint-tod when
# only libfprint-tod was carried over from a prior cache) would resolve
# the dep against pacman's repos, find nothing (it's AUR-only), and abort.
_refresh_repo_db

# Function to get version from package file. Exact-match on the parsed
# pkgname — a bare prefix glob made `elephant` claim any cached
# `elephant-<provider>-*` sibling, so a missing parent with a cached
# sibling skipped the build entirely.
get_package_version() {
    local pkgname=$1 f base
    for f in "$REPO_DIR/$pkgname"-*.pkg.tar.zst; do
        [[ -e $f ]] || continue
        base=$(basename "$f")
        [[ ${base%-*-*-*.pkg.tar.zst} == "$pkgname" ]] || continue
        # Extract version from filename: pkgname-version-release-arch.pkg.tar.zst
        sed -E "s/^${pkgname}-(.+)-(x86_64|any)\.pkg\.tar\.zst$/\1/" <<<"$base"
        return 0
    done
}

# Delete exactly one package's cached builds (and sigs), never a
# prefix-sharing sibling's.
remove_cached_package() {
    local pkgname=$1 f base
    for f in "$REPO_DIR/$pkgname"-*.pkg.tar.zst; do
        [[ -e $f ]] || continue
        base=$(basename "$f")
        [[ ${base%-*-*-*.pkg.tar.zst} == "$pkgname" ]] || continue
        rm -f "$f" "$f.sig"
    done
}

# Function to get version from PKGBUILD
get_pkgbuild_version() {
    local pkgbuild_dir=$1
    cd "$pkgbuild_dir"

    # PKGBUILDs reference makepkg-injected vars ($CARCH, $srcdir, etc.) that
    # aren't set when we source directly; relax nounset for this one call.
    set +u
    # shellcheck source=/dev/null
    source PKGBUILD
    set -u

    if [ -n "${epoch:-}" ]; then
        echo "${epoch}:${pkgver}-${pkgrel}"
    else
        echo "${pkgver}-${pkgrel}"
    fi
}

# Read validpgpkeys=() from a PKGBUILD. Emits one 40-hex-char fingerprint
# per line. Tolerates inline comments and either single- or multi-line
# array bodies.
_read_validpgpkeys() {
    local pkgbuild=$1
    awk '
        /^validpgpkeys=\(/ { seen=1; next }
        seen && /^\)/      { exit }
        seen {
            sub(/#.*/, "")
            for (i=1;i<=NF;i++) {
                gsub(/[()'"'"'"]/, "", $i)
                if ($i ~ /^[A-F0-9]{40}$/) print $i
            }
        }
    ' "$pkgbuild"
}

# Import each fingerprint into the build user's gpg keyring, trying
# the standard public keyservers in order. Mirrors the kernel-key
# import in build-shedos-packages.sh. Returns 0 on success (every key
# imported), 1 on any failure.
_import_pgp_keys() {
    local fps=("$@")
    (( ${#fps[@]} == 0 )) && return 0

    local user_prefix=()
    [[ $EUID -eq 0 ]] && user_prefix=(sudo -u builduser)

    local server
    for server in hkps://keyserver.ubuntu.com hkps://keys.openpgp.org hkps://pgp.mit.edu; do
        if "${user_prefix[@]}" gpg --batch --keyserver "$server" \
                --recv-keys "${fps[@]}" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

BUILT_COUNT=0
SKIPPED_COUNT=0

# Build each package
for PACKAGE in "${AUR_PACKAGES[@]}"; do
    echo ""
    echo "----------------------------------------"
    echo "Checking $PACKAGE..."

    # Cache-bust stock calamares before the version check so the
    # post-clone PKGBUILD patch (further down) actually gets a chance
    # to run. The patch enables packagechooser (which upstream's AUR
    # PKGBUILD skips) and bumps epoch=1; the patched build's filename
    # has a `1:` in it. If the cached pkg lacks the epoch prefix it's
    # stock; wipe it so the pre-flight skip below doesn't keep us on
    # the broken build forever.
    if [ "$PACKAGE" = "calamares" ]; then
        cached_pkg=$(find "$REPO_DIR" -maxdepth 1 \
            -name 'calamares-[0-9]*.pkg.tar.zst' 2>/dev/null | head -1)
        if [ -n "$cached_pkg" ]; then
            cached_ver=$(pacman -Qpi "$cached_pkg" 2>/dev/null \
                | awk '/^Version/ {print $3; exit}')
            case "$cached_ver" in
                1:*) ;;
                *)
                    echo "  cache-bust: stock calamares ($cached_ver) lacks packagechooser; forcing rebuild"
                    rm -f "$REPO_DIR"/calamares*.pkg.tar.zst*
                    ;;
            esac
        fi
    fi

    # Get currently installed version in repo
    CURRENT_VERSION=$(get_package_version "$PACKAGE")

    # Trust the GHA cache (cache key already hashes aur.txt). The
    # weekly aur-cache-refresh.yml job exhaustively rebuilds with
    # SHEDOS_AUR_FORCE_REBUILD=1 so -git packages still get refreshed.
    # Every push trusts the cached build to insulate us from upstream
    # regressions landing mid-week.
    if [ -z "${SHEDOS_AUR_FORCE_REBUILD:-}" ] && [ -n "$CURRENT_VERSION" ]; then
        echo "✓ $PACKAGE $CURRENT_VERSION cached (aur.txt unchanged); skipping clone + build"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # ────────────────────────────────────────────────────────────
    # Clone or update AUR repo. aur.archlinux.org has chronic TLS
    # flakiness (`SSL routines::unexpected eof while reading`) and
    # occasional HTTP 500s. Hardenings:
    #   • -c http.version=HTTP/1.1; avoid the HTTP/2-vs-middlebox
    #     scenario that produces 0A000126.
    #   • --depth 1; smallest possible transfer; less surface area
    #     for mid-stream connection death.
    #   • timeout 60; fail fast on a hung TLS handshake.
    #   • Jittered backoff 30s/60s/120s; push retries far enough
    #     apart that they don't all land in the same flaky minute.
    # 3 attempts; if all fail the script exits 1 and the run aborts.
    # The weekly refresh's success keeps the cache fresh enough that
    # this only matters for genuinely new aur.txt entries.
    # ────────────────────────────────────────────────────────────
    if [ "$EUID" -eq 0 ]; then
        sudo -u builduser bash <<EOF
set -e
cd "$AUR_BUILD_DIR"
for attempt in 1 2 3; do
    if [ -d "$PACKAGE" ]; then
        if timeout 60 git -c http.version=HTTP/1.1 -C "$PACKAGE" pull --depth 1 --no-tags; then
            break
        fi
    else
        if timeout 60 git -c http.version=HTTP/1.1 clone --depth 1 --no-tags https://aur.archlinux.org/$PACKAGE.git; then
            break
        fi
        # Half-cloned dir may linger; clean before next try.
        rm -rf "$PACKAGE"
    fi
    if [ "\$attempt" = "3" ]; then
        echo "FATAL: failed to fetch $PACKAGE from AUR after 3 attempts" >&2
        exit 1
    fi
    # Jitter [0,15)s on top of the base sleep so 3 parallel attempts
    # don't synchronize onto the same flaky window.
    base=\$(( attempt * 30 ))
    jitter=\$(( RANDOM % 15 ))
    delay=\$(( base + jitter ))
    echo "WARN: AUR fetch for $PACKAGE failed (attempt \$attempt); retrying in \${delay}s…" >&2
    sleep \$delay
done
EOF
    else
        cd "$AUR_BUILD_DIR"
        for attempt in 1 2 3; do
            if [ -d "$PACKAGE" ]; then
                if timeout 60 git -c http.version=HTTP/1.1 -C "$PACKAGE" pull --depth 1 --no-tags; then
                    break
                fi
            else
                if timeout 60 git -c http.version=HTTP/1.1 clone --depth 1 --no-tags https://aur.archlinux.org/$PACKAGE.git; then
                    break
                fi
                rm -rf "$PACKAGE"
            fi
            if [ "$attempt" = "3" ]; then
                echo "FATAL: failed to fetch $PACKAGE from AUR after 3 attempts" >&2
                exit 1
            fi
            base=$(( attempt * 30 ))
            jitter=$(( RANDOM % 15 ))
            delay=$(( base + jitter ))
            echo "WARN: AUR fetch for $PACKAGE failed (attempt $attempt); retrying in ${delay}s…" >&2
            sleep "$delay"
        done
    fi

    # ShedOS-specific PKGBUILD overrides; applied after clone, before
    # version read, so AUR_VERSION reflects the patched package and the
    # cached stock build is correctly seen as out-of-date.
    case "$PACKAGE" in
        calamares)
            # The upstream AUR PKGBUILD has _skip_modules=( ... packagechooser
            # packagechooserq ... ), passed to CMake as -DSKIP_MODULES.
            # ShedOS' settings.conf uses packagechooser for the optional-apps
            # picker, so we need it built. Drop those two lines from the skip
            # list and bump epoch=1 so this build supersedes any cached stock
            # calamares-3.4.2-2 in archiso/shedos-repo.
            sed -i '/^    packagechooser$/d; /^    packagechooserq$/d' \
                "$AUR_BUILD_DIR/$PACKAGE/PKGBUILD"
            grep -q '^epoch=' "$AUR_BUILD_DIR/$PACKAGE/PKGBUILD" || \
                sed -i '/^pkgver=/i epoch=1' "$AUR_BUILD_DIR/$PACKAGE/PKGBUILD"
            echo "  patched calamares PKGBUILD: enable packagechooser, epoch=1"
            ;;
        ananicy-cpp-git)
            # gcc 15 no longer pulls <unistd.h> transitively, and upstream's
            # src/platform/linux/{process,debug}.cpp call getpid() without
            # an explicit include. Inject the include via prepare(); the
            # upstream PKGBUILD has no prepare() of its own, so appending
            # one doesn't override anything.
            cat >> "$AUR_BUILD_DIR/$PACKAGE/PKGBUILD" <<'EOF'

prepare() {
    local f
    for f in "${srcdir}/${_pkgname}/src/platform/linux/process.cpp" \
             "${srcdir}/${_pkgname}/src/platform/linux/debug.cpp"; do
        if [[ -f $f ]] && ! grep -q '^#include <unistd.h>' "$f"; then
            sed -i '1i #include <unistd.h>' "$f"
        fi
    done
}
EOF
            echo "  patched ananicy-cpp-git PKGBUILD: inject <unistd.h> for getpid() under gcc 15+"
            ;;
    esac

    # Get version from PKGBUILD
    AUR_VERSION=$(get_pkgbuild_version "$AUR_BUILD_DIR/$PACKAGE")

    # Post-clone routing.
    #
    # -git packages have unstable PKGBUILD pkgvers (the real version
    # is computed by pkgver() at build time), so version comparison
    # is meaningless. Under FORCE we always rebuild them; without
    # FORCE the pre-flight already short-circuited via the cached
    # binary, so reaching this branch means we have no cache and
    # must build.
    if [[ "$PACKAGE" == *-git ]]; then
        echo "⚠ $PACKAGE is a -git package; rebuilding from fresh checkout"
        remove_cached_package "$PACKAGE"
    elif [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" = "$AUR_VERSION" ]; then
        # Only reached under FORCE; the upstream pkgver matches
        # what we already have, so no rebuild is needed.
        echo "✓ $PACKAGE $CURRENT_VERSION pkgver unchanged upstream; keeping cached build"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    elif [ -n "$CURRENT_VERSION" ]; then
        echo "⚠ $PACKAGE version changed: $CURRENT_VERSION → $AUR_VERSION (rebuilding)"
        remove_cached_package "$PACKAGE"
    else
        echo "⚠ $PACKAGE not found in repo (building $AUR_VERSION)"
    fi

    # Per-package PGP gating. The PKGBUILD's validpgpkeys=() (if any)
    # is the upstream maintainer's signing-key declaration. Try to import
    # those keys with multi-keyserver fallback so makepkg's source
    # signature check actually runs. Only fall back to --skippgpcheck
    # for a specific package when key retrieval fails; and warn loudly.
    #
    # SHEDOS_AUR_STRICT_PGP=1 turns the warn-and-skip into a build-fail
    # for that package. Useful for hardening runs and one-off audits.
    SKIP_PGP=()
    mapfile -t pgp_fps < <(_read_validpgpkeys "$AUR_BUILD_DIR/$PACKAGE/PKGBUILD")
    if (( ${#pgp_fps[@]} == 0 )); then
        # No validpgpkeys → no source signatures to check. --skippgpcheck
        # would be a no-op; omit it.
        :
    elif _import_pgp_keys "${pgp_fps[@]}"; then
        echo "  pgp: imported ${#pgp_fps[@]} key(s) for $PACKAGE; signature verification ENFORCED"
    else
        if [[ -n "${SHEDOS_AUR_STRICT_PGP:-}" ]]; then
            echo "FATAL: pgp: could not retrieve all signing keys for $PACKAGE (strict mode)" >&2
            echo "       fingerprints: ${pgp_fps[*]}" >&2
            exit 1
        fi
        echo "  WARN: pgp: could not retrieve all signing keys for $PACKAGE — falling back to --skippgpcheck" >&2
        echo "        fingerprints: ${pgp_fps[*]}" >&2
        SKIP_PGP=(--skippgpcheck)
    fi

    # Build the package
    echo "Building $PACKAGE $AUR_VERSION from AUR..."

    if [ "$EUID" -eq 0 ]; then
        # Run as builduser
        SKIP_PGP_STR="${SKIP_PGP[*]:-}"
        sudo -u builduser bash <<EOF
set -e
cd "$AUR_BUILD_DIR/$PACKAGE"
makepkg -sf --noconfirm $SKIP_PGP_STR
EOF
    else
        # Run as current user
        cd "$AUR_BUILD_DIR/$PACKAGE"
        makepkg -sf --noconfirm "${SKIP_PGP[@]}"
    fi

    # Copy built package to repo
    find "$AUR_BUILD_DIR/$PACKAGE" -name "*.pkg.tar.zst" -exec cp -v {} "$REPO_DIR/" \;

    # Re-add to [shedos-repo] + pacman -Sy so the next iteration's
    # makepkg --syncdeps sees this freshly-built pkg as a resolvable dep.
    # Targeted incremental: only the just-built pkg(s) get re-added,
    # not the entire repo glob.
    _repo_add_built "$AUR_BUILD_DIR/$PACKAGE"

    echo "✓ $PACKAGE built successfully!"
    BUILT_COUNT=$((BUILT_COUNT + 1))
    # Tell build-packages.yml's "Build repo DB" step to actually
    # repo-add and re-sign; without this it early-exits on the
    # no-op gate and shedos.db keeps the stale (pre-rebuild) entry.
    echo "$PACKAGE" >> /tmp/built-pkgs.txt
done

echo ""
echo "=========================================="
echo "Build Summary:"
echo "  Built: $BUILT_COUNT packages"
echo "  Skipped (up to date): $SKIPPED_COUNT packages"
echo "=========================================="

# Check if we have packages in repo
PACKAGE_COUNT=$(find "$REPO_DIR" -name "*.pkg.tar.zst" | wc -l)
if [ "$PACKAGE_COUNT" -eq 0 ]; then
    echo "ERROR: No package files found in repository"
    exit 1
fi

echo ""
echo "Total packages in repository: $PACKAGE_COUNT"

# builduser cleanup is handled by EXIT trap installed at script start.

# Recreate repository database
echo "Updating local repository database..."
cd "$REPO_DIR"
rm -f shedos-repo.db* shedos-repo.files*
repo-add shedos-repo.db.tar.gz *.pkg.tar.zst

# Cleanup temporary build directory
echo "Cleaning up temporary build directory..."
rm -rf "$AUR_BUILD_DIR"

echo ""
echo "=========================================="
echo "AUR packages ready!"
echo "Repository: $REPO_DIR"
ls -lh "$REPO_DIR"/*.pkg.tar.zst 2>/dev/null || echo "No packages found"
echo "=========================================="
