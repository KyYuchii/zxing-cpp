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

# This directory is never reused. A restored PCM must not hide the umbrella diagnostics.
module_cache="$(mktemp -d "${TMPDIR:-/tmp}/zxing-module-cache.XXXXXX")"
xcrun swiftc -typecheck -module-cache-path "$module_cache" \
    -I "$wrapper" -Xcc -Werror=incomplete-umbrella "$scratch/import-smoke.swift"

swiftpm_cache="${SWIFTPM_CACHE_PATH:-$scratch/swiftpm-cache}"
mkdir -p "$swiftpm_cache"
swift_build() {
    swift build \
        --package-path "$source_root" \
        --cache-path "$swiftpm_cache" \
        --enable-dependency-cache \
        --enable-build-manifest-caching \
        --manifest-cache shared \
        "$@"
}
swift_build --scratch-path "$scratch/macos"
swift_build \
    --triple arm64-apple-ios16.0-simulator \
    --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    --scratch-path "$scratch/ios-simulator"
swift_build \
    --triple arm64-apple-ios16.0 \
    --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
    --scratch-path "$scratch/ios-device"
