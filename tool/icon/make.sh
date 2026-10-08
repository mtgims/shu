#!/usr/bin/env bash
# Renders the app icons from icon.svg and icon-square.svg. Needs rsvg-convert (librsvg) and
# ImageMagick 7. The Android adaptive and notification icons are vector drawables in
# android/app/src/main/res/drawable and are edited by hand.
set -euo pipefail
cd "$(dirname "$0")"
app=../..
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

png() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

# Android, for launchers without adaptive icons
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  png icon.svg "${d#*:}" "$app/android/app/src/main/res/mipmap-${d%%:*}/ic_launcher.png"
done

# Windows
for s in 16 24 32 48 64 128 256; do png icon.svg $s "$tmp/$s.png"; done
magick "$tmp"/{16,24,32,48,64,128,256}.png "$app/windows/runner/resources/app_icon.ico"

# Linux window icon
png icon.svg 256 "$app/linux/runner/resources/shu.png"

# macOS: the rounded square with a margin, like other Mac icons
for s in 16 32 64 128 256 512 1024; do
  inner=$((s * 824 / 1024))
  png icon.svg $inner "$tmp/mac.png"
  magick "$tmp/mac.png" -background none -gravity center -extent "${s}x$s" \
    "$app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$s.png"
done

# iOS: square and opaque, the system rounds the corners
ios=$app/ios/Runner/Assets.xcassets/AppIcon.appiconset
for f in "$ios"/Icon-App-*.png; do
  name=${f##*Icon-App-}
  pt=${name%%x*}
  scale=${name##*@}
  scale=${scale%x.png}
  size=$(awk "BEGIN { print int($pt * $scale + 0.5) }")
  png icon-square.svg "$size" "$tmp/ios.png"
  magick "$tmp/ios.png" -background '#1E2233' -alpha remove -alpha off "$f"
done
