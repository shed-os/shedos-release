#!/bin/bash
# Build AUR packages for shedOS.
#
# Populates archiso/shedos-repo/ with .pkg.tar.zst files for every
# package listed in packages/aur.txt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
AUR_BUILD_DIR="/tmp/shedos-aur-build"
REPO_DIR="$PROJECT_ROOT/archiso/shedos-repo"

echo "=========================================="
echo "Building AUR packages for shedOS"
echo "=========================================="

# Create directories
mkdir -p "$REPO_DIR"
mkdir -p "$AUR_BUILD_DIR"
chmod 777 "$AUR_BUILD_DIR"

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Running as root, creating build user..."

    # Cleanup runs on ANY exit path (success, error, signal) so we never
    # leave a stale builduser + sudoers file behind between runs.
    _cleanup_builduser() {
        echo "Cleaning up build user..."
        userdel -r builduser 2>/dev/null || true
        rm -f /etc/sudoers.d/builduser-aur
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

# Read AUR packages from packages/aur.txt (single source of truth)
AUR_FILE="$PROJECT_ROOT/packages/aur.txt"
if [ ! -f "$AUR_FILE" ]; then
    echo "ERROR: AUR package list not found: $AUR_FILE"
    exit 1
fi

# Read packages, filtering out comments and empty lines
mapfile -t AUR_PACKAGES < <(grep -v '^#' "$AUR_FILE" | grep -v '^$' | tr -d ' ')
echo "Found ${#AUR_PACKAGES[@]} AUR packages to build"

# Function to get version from package file
get_package_version() {
    local pkgname=$1
    local pkgfile=$(ls "$REPO_DIR"/${pkgname}-*.pkg.tar.zst 2>/dev/null | head -n1)
    if [ -n "$pkgfile" ]; then
        # Extract version from filename: pkgname-version-release-arch.pkg.tar.zst
        basename "$pkgfile" | sed -E "s/^${pkgname}-(.+)-(x86_64|any)\.pkg\.tar\.zst$/\1/"
    fi
}

# Function to get version from PKGBUILD
get_pkgbuild_version() {
    local pkgbuild_dir=$1
    cd "$pkgbuild_dir"

    # PKGBUILDs reference makepkg-injected vars ($CARCH, $srcdir, etc.) that
    # aren't set when we source directly — relax nounset for this one call.
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
    # stock — wipe it so the pre-flight skip below doesn't keep us on
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

    # ────────────────────────────────────────────────────────────
    # Pre-flight: trust the GHA cache.
    #
    # When CI's actions/cache restored archiso/shedos-repo/ before
    # this script ran, a cached .pkg.tar.zst for $PACKAGE means it
    # was built for the current packages/aur.txt (cache key gates
    # this). Skip the clone AND the build — net effect on
    # cache-hit runs is zero AUR network calls.
    #
    # SHEDOS_AUR_FORCE_REBUILD=1 (set by release-weekly.yml) bypasses
    # this skip so the weekly job can pull fresh upstream PKGBUILDs.
    # ────────────────────────────────────────────────────────────
    if [ -z "${SHEDOS_AUR_FORCE_REBUILD:-}" ] && [ -n "$CURRENT_VERSION" ]; then
        echo "✓ $PACKAGE $CURRENT_VERSION cached (aur.txt unchanged); skipping clone + build"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # ────────────────────────────────────────────────────────────
    # Clone or update AUR repo. aur.archlinux.org has chronic TLS
    # flakiness (`SSL routines::unexpected eof while reading`) and
    # occasional HTTP 500s. Hardenings:
    #   • -c http.version=HTTP/1.1 — avoid the HTTP/2-vs-middlebox
    #     scenario that produces 0A000126.
    #   • --depth 1 — smallest possible transfer; less surface area
    #     for mid-stream connection death.
    #   • timeout 60 — fail fast on a hung TLS handshake.
    #   • Jittered backoff 30s/60s/120s — push retries far enough
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

    # ShedOS-specific PKGBUILD overrides — applied after clone, before
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
        rm -f "$REPO_DIR"/${PACKAGE}-*.pkg.tar.zst*
    elif [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" = "$AUR_VERSION" ]; then
        # Only reached under FORCE — the upstream pkgver matches
        # what we already have, so no rebuild is needed.
        echo "✓ $PACKAGE $CURRENT_VERSION pkgver unchanged upstream; keeping cached build"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    elif [ -n "$CURRENT_VERSION" ]; then
        echo "⚠ $PACKAGE version changed: $CURRENT_VERSION → $AUR_VERSION (rebuilding)"
        rm -f "$REPO_DIR"/${PACKAGE}-*.pkg.tar.zst*
    else
        echo "⚠ $PACKAGE not found in repo (building $AUR_VERSION)"
    fi

    # Build the package
    echo "Building $PACKAGE $AUR_VERSION from AUR..."

    if [ "$EUID" -eq 0 ]; then
        # Run as builduser
        sudo -u builduser bash <<EOF
set -e
cd "$AUR_BUILD_DIR/$PACKAGE"
makepkg -sf --noconfirm --skippgpcheck
EOF
    else
        # Run as current user
        cd "$AUR_BUILD_DIR/$PACKAGE"
        makepkg -sf --noconfirm --skippgpcheck
    fi

    # Copy built package to repo
    find "$AUR_BUILD_DIR/$PACKAGE" -name "*.pkg.tar.zst" -exec cp -v {} "$REPO_DIR/" \;

    echo "✓ $PACKAGE built successfully!"
    BUILT_COUNT=$((BUILT_COUNT + 1))
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
