#!/usr/bin/env bash
# Installs Godot (headless-capable) and imports the project so tests can run.
# Usage: tools/ci/install-godot.sh [version]   (default 4.5.1, matches deploy.yml)
set -euo pipefail

VERSION="${1:-4.5.1}"
NAME="Godot_v${VERSION}-stable_linux.x86_64"
URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable/${NAME}.zip"
TMP="$(mktemp -d)"

wget -q -O "$TMP/godot.zip" "$URL"
unzip -q "$TMP/godot.zip" -d "$TMP/out"
sudo mv "$TMP/out/$NAME" /usr/local/bin/godot
sudo chmod +x /usr/local/bin/godot
rm -rf "$TMP"

godot --version
# Generate the .godot/ import cache so scripts and resources resolve.
godot --headless --path . --import || true
