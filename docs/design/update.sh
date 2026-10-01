#!/bin/sh
# Replace the design package with a new Claude Design export and re-render the screen PNGs.
# Export: Claude Design → Share → Project HTML → Project archive. Then:
#   docs/design/update.sh ~/Downloads/"Ataste iOS app design.zip"
# Needs: unzip, uv (https://docs.astral.sh/uv/) and Google Chrome.
set -eu
zip="${1:?usage: update.sh <Claude Design export .zip>}"
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
unzip -q "$zip" -d "$tmp"
rm -rf "$here/boards" "$here/frames"
mkdir -p "$here/boards"
# Boards, their scripts and the art they show; not Claude Design's own working screenshots or third-party logos.
cp "$tmp"/*.dc.html "$tmp"/*.js "$here/boards/"
mkdir -p "$here/boards/uploads"
cp -R "$tmp/uploads/art" "$here/boards/uploads/art"
cp "$tmp"/uploads/Roundo-Variable.* "$here/boards/uploads/" 2>/dev/null || true
rm -rf "$tmp"
uv run "$here/frames.py"
