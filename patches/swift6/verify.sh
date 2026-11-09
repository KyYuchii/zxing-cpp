#!/usr/bin/env bash
set -euo pipefail
source_root="${1:?Usage: verify.sh /path/to/source /path/to/scratch}"
scratch="${2:?Scratch directory is required}"
mkdir -p "$scratch"
source_root="$(cd -- "$source_root" && pwd)"
scratch="$(cd -- "$scratch" && pwd)"
wrapper="$source_root/wrappers/ios/Sources/Wrapper"
modulemap="$wrapper/module.modulemap"

for header in "Reader/ZXIPosition+Helper.h" "ZXIFormatHelper.h" "Version.h"; do
    if ! grep -F -q "exclude header \"$header\"" "$modulemap"; then
        echo "Missing umbrella exclusion for $header in $modulemap" >&2
        exit 1
    fi
done

printf 'import ZXingCpp\nlet reader = ZXIBarcodeReader()\n' > "$scratch/import-smoke.swift"
{
    xcodebuild -version
    swift --version
} | tee "$scratch/toolchain.txt"

# A fresh module cache prevents a previously compiled PCM from hiding header warnings.
xcrun swiftc -typecheck -module-cache-path "$scratch/fresh-module-cache" \
    -I "$wrapper" -Xcc -Werror=incomplete-umbrella "$scratch/import-smoke.swift"
swift build --package-path "$source_root" --scratch-path "$scratch/macos"
swift build --package-path "$source_root" \
    --triple arm64-apple-ios16.0-simulator \
    --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    --scratch-path "$scratch/ios-simulator"
swift build --package-path "$source_root" \
    --triple arm64-apple-ios16.0 \
    --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
    --scratch-path "$scratch/ios-device"
