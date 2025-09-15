#!/usr/bin/env bash
set -euo pipefail

# Fetch prebuilt Node runtimes and place them inside the repo under
# Vendor/node/darwin-<arch>/ so they can be bundled without network access
# during builds/archives.
#
# Usage:
#   bash Scripts/fetch_node_binaries.sh [version] [--current-only]
#
# Examples:
#   bash Scripts/fetch_node_binaries.sh            # default 20.17.0, both archs
#   bash Scripts/fetch_node_binaries.sh 20.17.0    # specific version, both archs
#   bash Scripts/fetch_node_binaries.sh 20.17.0 --current-only

VER="${1:-20.17.0}"
CURRENT_ONLY="${2:-}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/node"
mkdir -p "$VENDOR_DIR"

case "${CURRENT_ONLY}" in
  --current-only)
    case "$(uname -m)" in
      arm64) ARCHS=(arm64) ;;
      x86_64) ARCHS=(x64) ;;
      *) echo "Unsupported arch $(uname -m)"; exit 1 ;;
    esac
    ;;
  "") ARCHS=(arm64 x64) ;;
  *) echo "Unknown flag: ${CURRENT_ONLY}"; exit 1 ;;
esac

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

for A in "${ARCHS[@]}"; do
  echo "Downloading Node v${VER} for darwin-${A}"
  URL="https://nodejs.org/dist/v${VER}/node-v${VER}-darwin-${A}.tar.xz"
  TAR="$TMP/node-${A}.tar.xz"
  curl -sSL "$URL" -o "$TAR"

  echo "Extracting $TAR"
  mkdir -p "$TMP/extract-${A}"
  tar -xJf "$TAR" -C "$TMP/extract-${A}"
  INNER="$TMP/extract-${A}/node-v${VER}-darwin-${A}"

  DEST="$VENDOR_DIR/darwin-${A}"
  echo "Staging to $DEST"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  rsync -a "$INNER"/ "$DEST"/

  # Ensure executables are marked
  chmod +x "$DEST/bin/node" || true
  chmod +x "$DEST/bin/npm" || true
  chmod +x "$DEST/bin/npx" || true
done

echo "Vendored Node layouts:"
ls -la "$VENDOR_DIR" || true
echo "Done. Commit the Vendor/node directory." 

