#!/usr/bin/env bash
set -euo pipefail
source_root="${1:?Usage: verify.sh /path/to/source /path/to/scratch}"
scratch="${2:?Scratch directory is required}"
mkdir -p "$scratch"
source_root="$(cd -- "$source_root" && pwd)"
scratch="$(cd -- "$scratch" && pwd)"
wrapper="$source_root/wrappers/ios/Sources/Wrapper"
printf 'import ZXingCpp\nlet reader = ZXIBarcodeReader()\n' > "$scratch/import-smoke.swift"
# A fresh module cache prevents a previously compiled PCM from hiding header warnings.
xcrun swiftc -typecheck -module-cache-path "$scratch/module-cache" \
    -I "$wrapper" -Xcc -Werror=incomplete-umbrella "$scratch/import-smoke.swift"
swift build --package-path "$source_root" --scratch-path "$scratch/build"
