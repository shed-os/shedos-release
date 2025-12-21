#!/bin/bash
# Build AUR packages for shedOS
# Creates a local repository with pre-built packages
# Only rebuilds packages if version changed or doesn't exist

set -e

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

    # Create temporary build user
    useradd -m -G wheel builduser 2>/dev/null || true
    echo "builduser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builduser-aur
    chmod 440 /etc/sudoers.d/builduser-aur
fi

# List of AUR packages to build
declare -a AUR_PACKAGES=("elephant" "elephant-bluetooth" "elephant-calc" "elephant-clipboard" "elephant-desktopapplications" "elephant-files" "elephant-menus" "elephant-providerlist" "elephant-runner" "elephant-symbols" "elephant-todo" "elephant-unicode" "elephant-websearch" "walker" "calamares" "yay" "visual-studio-code-bin" "google-chrome" "slack-desktop" "obsidian-bin" "hadolint-bin")

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

    # Source PKGBUILD to get pkgver and pkgrel
    source PKGBUILD

    # Handle epoch if present
    if [ -n "$epoch" ]; then
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

    # Get currently installed version in repo
    CURRENT_VERSION=$(get_package_version "$PACKAGE")

    # Clone or update AUR repo
    if [ "$EUID" -eq 0 ]; then
        sudo -u builduser bash <<EOF
set -e
cd "$AUR_BUILD_DIR"
if [ -d "$PACKAGE" ]; then
    cd "$PACKAGE"
    git pull
else
    git clone https://aur.archlinux.org/$PACKAGE.git
fi
EOF
    else
        cd "$AUR_BUILD_DIR"
        if [ -d "$PACKAGE" ]; then
            cd "$PACKAGE"
            git pull
        else
            git clone https://aur.archlinux.org/$PACKAGE.git
        fi
    fi

    # Get version from PKGBUILD
    AUR_VERSION=$(get_pkgbuild_version "$AUR_BUILD_DIR/$PACKAGE")

    # Compare versions
    if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" = "$AUR_VERSION" ]; then
        echo "✓ $PACKAGE $CURRENT_VERSION is up to date (skipping)"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    if [ -n "$CURRENT_VERSION" ]; then
        echo "⚠ $PACKAGE version changed: $CURRENT_VERSION → $AUR_VERSION (rebuilding)"
        # Remove old version
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
makepkg -sf --noconfirm
EOF
    else
        # Run as current user
        cd "$AUR_BUILD_DIR/$PACKAGE"
        makepkg -sf --noconfirm
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

    # Cleanup on error
    if [ "$EUID" -eq 0 ]; then
        userdel -r builduser 2>/dev/null || true
        rm -f /etc/sudoers.d/builduser-aur
    fi

    exit 1
fi

echo ""
echo "Total packages in repository: $PACKAGE_COUNT"

# Cleanup build user if created
if [ "$EUID" -eq 0 ]; then
    echo "Cleaning up build user..."
    userdel -r builduser 2>/dev/null || true
    rm -f /etc/sudoers.d/builduser-aur
fi

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
