#!/bin/bash
# Regenerates GuitarTransposer.xcodeproj from project.yml, then patches the
# pbxproj objectVersion down to 60 (Xcode 15.x format) since this machine's
# XcodeGen defaults to objectVersion 77 (Xcode 16.3+), which Xcode 15.4 can't open.
# Safe to re-run any time project.yml changes.
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
sed -i '' 's/objectVersion = [0-9]*;/objectVersion = 60;/' GuitarTransposer.xcodeproj/project.pbxproj
sed -i '' '/preferredProjectObjectVersion = [0-9]*;/d' GuitarTransposer.xcodeproj/project.pbxproj
echo "Regenerated and patched objectVersion to 60."
