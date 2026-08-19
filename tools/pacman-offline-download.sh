#!/bin/bash
# Fully offline XferCommand wrapper for deterministic ISO builds
# Uses only cached packages and frozen database files - NO network access

set -euo pipefail

OUTPUT_FILE="$1"
URL="$2"

# The build copies this into <build>/scripts/ and pacman runs it from there,
# so the frozen databases and the package caches are named relative to it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(dirname "$SCRIPT_DIR")"
DB_CACHE_DIR="$BUILD_DIR/db-cache"
# Substituted when the build copies this in, the same way pacman.conf.in's
# Server line is. pacman runs this as its XferCommand and an environment
# variable would have to survive mkarchiso, pacstrap and pacman to get here.
ISO_REPO="@SHEDOS_REPO@"

# If downloading a database file (.db, .db.sig, .files), use cached version
if [[ "$URL" == *.db ]] || [[ "$URL" == *.db.sig ]] || [[ "$URL" == *.files ]]; then
    # Check if it's a file:// URL (local repository like shedos-repo)
    if [[ "$URL" == file://* ]]; then
        FILE_PATH="${URL#file://}"
        if [ -f "$FILE_PATH" ]; then
            # File exists, copy it
            cp "$FILE_PATH" "$OUTPUT_FILE"
            exit 0
        elif [[ "$URL" == *.sig ]]; then
            # Signature file doesn't exist
            echo "INFO: Skipping optional local signature: $(basename "$URL")" >&2
            exit 1
        else
            # Required database file missing
            echo "ERROR: Local database file not found: $FILE_PATH" >&2
            exit 1
        fi
    fi

    # For remote database URLs, use CACHED databases (frozen at download-packages time)
    # Extract database name from URL (e.g., core.db, extra.db)
    DB_NAME=$(basename "$URL")
    CACHED_DB="$DB_CACHE_DIR/$DB_NAME"

    if [ -f "$CACHED_DB" ]; then
        # Use frozen database
        cp "$CACHED_DB" "$OUTPUT_FILE"
        exit 0
    elif [[ "$URL" == *.sig ]] || [[ "$URL" == *.files ]]; then
        # Signature and .files are optional. Return error (404) so pacman knows they don't exist
        # Do NOT create empty files, as that causes "GPGME error: No data"
        echo "INFO: Skipping optional file: $(basename "$URL")" >&2
        exit 1
    else
        echo "ERROR: Frozen database not found: $DB_NAME" >&2
        echo "Cached databases are in: $DB_CACHE_DIR" >&2
        echo "Available databases:" >&2
        ls -1 "$DB_CACHE_DIR/" 2>/dev/null || echo "  (none)" >&2
        echo "" >&2
        echo "The package state changed after the databases were frozen." >&2
        echo "Run tools/download-packages.sh again to re-freeze it." >&2
        exit 1
    fi
fi

# For package files, check cache only (no network downloads)
if [[ "$URL" == *.pkg.tar.zst ]] || [[ "$URL" == *.pkg.tar.zst.sig ]]; then
    PACKAGE_NAME=$(basename "$URL")

    # The ISO repository first: it holds the release's fetched packages and the
    # AUR builds, and a name it answers for must not be served by a stale copy
    # sitting in one of the caches behind it.
    CACHE_DIRS=(
        "$ISO_REPO"
        "$BUILD_DIR/pkg-cache"
        "/var/cache/pacman/pkg"
    )

    for CACHE_DIR in "${CACHE_DIRS[@]}"; do
        if [ -f "$CACHE_DIR/$PACKAGE_NAME" ]; then
            # Package found in cache, "download" successful
            cp "$CACHE_DIR/$PACKAGE_NAME" "$OUTPUT_FILE"
            exit 0
        fi
    done

    # If signature file (.sig) not found, that's okay
    if [[ "$PACKAGE_NAME" == *.sig ]]; then
        echo "INFO: Skipping optional package signature: $PACKAGE_NAME" >&2
        exit 1
    fi

    # Package not in cache
    echo "ERROR: Package not in cache: $PACKAGE_NAME" >&2
    echo "Searched in:" >&2
    for CACHE_DIR in "${CACHE_DIRS[@]}"; do
        echo "  - $CACHE_DIR" >&2
    done
    echo "Run tools/download-packages.sh to update the cached packages" >&2
    exit 1
fi

# Unknown file type, fail
echo "ERROR: Unknown download type: $URL" >&2
exit 1
