#!/bin/bash
# Build, bundle, install to ~/Applications, and drop the Raycast script command.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh release

DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/AIShot.app"
cp -R build/AIShot.app "$DEST/AIShot.app"
echo "installed $DEST/AIShot.app"

RAYCAST_DIR="$HOME/.raycast-scripts"
mkdir -p "$RAYCAST_DIR"
cp raycast/annotate-clipboard.sh "$RAYCAST_DIR/"
chmod +x "$RAYCAST_DIR/annotate-clipboard.sh"
echo "installed $RAYCAST_DIR/annotate-clipboard.sh"
echo
echo "Next: Raycast → Extensions → + → Script Directory → add $RAYCAST_DIR"
echo "      then bind a hotkey to \"Annotate Clipboard Screenshot\"."
