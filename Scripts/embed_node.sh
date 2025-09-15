#!/usr/bin/env bash
set -euo pipefail

# Copy a vendored Node from the repo into the built app's Resources,
# clear quarantine, and codesign the nested binaries.

case "${ARCHS:-$(uname -m)}" in
  *arm64*) NODE_ARCH="arm64" ;;
  *x86_64*|*x86*) NODE_ARCH="x64" ;;
  *) echo "Unsupported ARCHS=${ARCHS:-$(uname -m)}"; exit 1 ;;
esac

SRC="${SRCROOT}/Vendor/node/darwin-${NODE_ARCH}"
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/node"
BIN_DST="${DEST}/bin"

if [[ ! -x "${SRC}/bin/node" ]]; then
  echo "ERROR: Missing vendored Node at ${SRC}/bin/node"
  echo "Run: bash Scripts/fetch_node_binaries.sh [version] [--current-only]"
  exit 1
fi

echo "Embedding Node from ${SRC} -> ${DEST}"
rm -rf "${DEST}"
mkdir -p "${DEST}"
rsync -a "${SRC}/" "${DEST}/"

chmod +x "${BIN_DST}/node" || true
chmod +x "${BIN_DST}/npm" || true
chmod +x "${BIN_DST}/npx" || true

# Remove quarantine if present
xattr -dr com.apple.quarantine "${DEST}" || true

if [[ "${CODE_SIGNING_ALLOWED}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  echo "Codesigning bundled Node with ${EXPANDED_CODE_SIGN_IDENTITY}"
  codesign --force --options runtime --timestamp=none --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "${BIN_DST}/node" || true
  [[ -x "${BIN_DST}/npm" ]] && codesign --force --options runtime --timestamp=none --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "${BIN_DST}/npm" || true
  [[ -x "${BIN_DST}/npx" ]] && codesign --force --options runtime --timestamp=none --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "${BIN_DST}/npx" || true
fi

echo "Node embedded at ${BIN_DST}/node"
"${BIN_DST}/node" -v || true

