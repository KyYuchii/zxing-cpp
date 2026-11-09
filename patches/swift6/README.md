# Swift 6 iOS header patch

Base: `v3.1.1`, commit `287c85df6f961c8efbfb5ffd736cd9457b8b890e`.

Maintenance branch: `fix/swift6-strict-concurrency`.

The Swift module umbrella exposes the Objective-C API. These three headers are
not part of that API and are excluded from the module:

- `Reader/ZXIPosition+Helper.h`
- `ZXIFormatHelper.h`
- `Version.h`

The exclusion removes their `-Wincomplete-umbrella` diagnostics. Other upstream
C++ warnings are outside this check. The headers remain available to the
package's Objective-C++ implementation, and the QR decoder is unchanged.

## Scripts

```sh
bash patches/swift6/apply.sh /path/to/clean/upstream-checkout
bash patches/swift6/verify.sh /path/to/patched/source /tmp/zxing-swift6-check
```

`apply.sh` is idempotent. A conflict exits with an error and does not drop the
patch. `verify.sh` uses a fresh Clang module cache, turns incomplete-umbrella
diagnostics into errors, then builds the native package, the arm64 iOS
Simulator library, and the arm64 iOS device SDK library.

## Workflow

`.github/workflows/swift6-maintain.yml` has three layers:

1. Every day, read the latest stable upstream tag. If `vX.Y.Z-Fixed` already
   exists, stop. Otherwise sync that tag onto `fix/swift6-strict-concurrency`
   when the patch still applies. A conflict stops the job and does not push.
2. Check the three headers on the maintenance commit and on a clean upstream
   checkout with the patch applied twice. Remaining umbrella diagnostics fail
   the job. Other compiler warnings do not.
3. After both checks pass, create the immutable tag `vX.Y.Z-Fixed` on the
   verified commit. An existing tag is left untouched. This does not create a
   GitHub Release.

The scheduled workflow runs only after this file is on the default branch,
`master`. That daily run publishes the tag. Push and pull request runs verify
the branch and do not publish. A manual run publishes only when its publish
input is enabled. Passing another upstream tag or commit checks compatibility
and does not move the branch or publish a tag.
