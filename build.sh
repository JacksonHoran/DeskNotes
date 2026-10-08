#!/bin/bash
# Builds DeskNotes.app (universal: Apple Silicon + Intel) into ./build.
#   ./build.sh            build only
#   ./build.sh install    build and copy to ~/Applications, then launch
#   ./build.sh release    build and zip to ./build/DeskNotes.zip (for GitHub Releases)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/DeskNotes.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" Sources/main.swift -o "build/DeskNotes-$arch"
done
lipo -create build/DeskNotes-arm64 build/DeskNotes-x86_64 -output "$APP/Contents/MacOS/DeskNotes"
rm build/DeskNotes-arm64 build/DeskNotes-x86_64
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"

case "${1:-}" in
  install)
    pkill -x DeskNotes 2>/dev/null || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/DeskNotes.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/DeskNotes.app
    echo "Installed to ~/Applications/DeskNotes.app and launched"
    ;;
  release)
    (cd build && rm -f DeskNotes.zip && ditto -c -k --keepParent DeskNotes.app DeskNotes.zip)
    echo "Release archive: build/DeskNotes.zip"
    ;;
esac
