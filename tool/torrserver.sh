#!/usr/bin/env bash
# Downloads the TorrServer program that plays torrents (github.com/YouROK/TorrServer, GPL-3.0)
# and puts it where the build ships it. Pinned to a release, checked by SHA-256.
# Usage: tool/torrserver.sh android            (into android/app/src/main/jniLibs)
#        tool/torrserver.sh linux <bundle dir> (as <dir>/lib/torrserver)
#        tool/torrserver.sh windows <app dir>  (as <dir>/torrserver.exe)
set -euo pipefail
version=MatriX.146.2
base="https://github.com/YouROK/TorrServer/releases/download/$version"
root="$(cd "$(dirname "$0")/.." && pwd)"

fetch() { # fetch <asset> <sha256> <destination>
  mkdir -p "$(dirname "$3")"
  curl -fsSL -o "$3.part" "$base/$1"
  echo "$2  $3.part" | sha256sum -c --quiet -
  mv "$3.part" "$3"
  chmod +x "$3"
}

case "${1:-}" in
android)
  libs="$root/android/app/src/main/jniLibs"
  fetch TorrServer-android-arm64 48b36ca0bfaf975b831025c44df67e8e05d2b824ff294637804021c89b43e2ed \
    "$libs/arm64-v8a/libtorrserver.so"
  fetch TorrServer-android-arm7 a5870db3e12a7eb69c46ece419f433516cc39676cce9c8cc18d84784ed111075 \
    "$libs/armeabi-v7a/libtorrserver.so"
  ;;
linux)
  fetch TorrServer-linux-amd64 61cdeb275685e4938389e1e9addd5974df4928d4e7e529e3209388c0b02abcca \
    "${2:?bundle dir}/lib/torrserver"
  ;;
windows)
  fetch TorrServer-windows-amd64.exe 1459f369f66dafed172204f6410ddef5e43e7942e9b5c325b6745939b197edf9 \
    "${2:?app dir}/torrserver.exe"
  ;;
*)
  echo "usage: $0 android | linux <bundle dir> | windows <app dir>" >&2
  exit 2
  ;;
esac
