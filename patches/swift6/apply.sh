#!/usr/bin/env bash
set -euo pipefail
patch_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_root="${1:?Usage: apply.sh /path/to/upstream-checkout}"
patch_file="$patch_dir/0001-exclude-private-ios-headers.patch"
if git -C "$source_root" apply --check "$patch_file" 2>/dev/null; then
    git -C "$source_root" apply "$patch_file"
    echo 'Applied RoleP iOS module-map patch.'
elif git -C "$source_root" apply --reverse --check "$patch_file" 2>/dev/null; then
    echo 'RoleP iOS module-map patch is already applied.'
else
    echo 'Patch conflicts with upstream. Review the module map; do not silently skip this failure.' >&2
    exit 1
fi
