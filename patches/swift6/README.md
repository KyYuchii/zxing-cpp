# RoleP maintained iOS module patch

Base: `v3.1.1`, commit `287c85df6f961c8efbfb5ffd736cd9457b8b890e`.

The Swift module's umbrella header intentionally exposes the Objective-C API.
Two C++ conversion helpers (`ZXIPosition+Helper.h`, `ZXIFormatHelper.h`) and the
internal build configuration (`Version.h`) are explicitly excluded from that
module. This resolves three `-Wincomplete-umbrella` diagnostics without exposing
C++ declarations to Swift, disabling compiler warnings, or changing QR decoding.
The headers remain available to the package's Objective-C++ implementation.

## Patch maintenance

```sh
bash patches/rolep/apply.sh /path/to/clean/upstream-checkout
bash patches/rolep/verify.sh /path/to/patched/upstream-checkout /tmp/zxing-rolep-check
```

The apply script is idempotent; conflicts fail rather than dropping the patch.
The verification script uses a fresh Clang module cache and promotes incomplete
umbrella warnings to errors, then builds the native package.

`RoleP iOS patch verification` runs on relevant branch pushes and pull requests.
Manual dispatch accepts an upstream tag/commit to test forward compatibility.
It reapplies the stored patch to a separate upstream checkout, tests idempotency,
builds the Swift package and iOS Simulator library, and uploads the patch plus the
exact upstream commit as artifacts. It has read-only repository permissions and
never commits, creates a PR, publishes a release, or pushes automatically.

For a new baseline: inspect the upstream changes, test via manual dispatch,
regenerate the patch if needed, and update this baseline record and the workflow's
pinned default/comparison ref together. Do not silently refresh to a newer tag.

## GitHub handoff

This local checkout has branch `rolep/ios-modulemap-3.1.1` and an `upstream` remote.
No GitHub fork, `origin`, commit, push, or release has been created by this task.
When ready, create a GitHub fork, add its URL as `origin`, review and commit this
patch and workflow, then push this branch. Keep the original `v3.1.1` tag unchanged;
use a distinct fork release tag after CI passes. Update RoleP's Swift package URL
and pin in Xcode manually only after that release exists.
