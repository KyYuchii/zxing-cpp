# ZXingCpp RoleP Fork：交给 Grok 的 CI/CD 搭建任务

## 任务与授权边界

请在 `KyYuchii/zxing-cpp` 中搭建可维护的 SwiftPM 补丁验证、上游兼容检查和版本发布流程。先检查仓库实际状态，再增量实施。本文是执行规格，不代表远端工作流已经部署。

本次文档编写阶段没有提交、推送或改变远端配置。Grok 应依据用户交付时的授权执行远端提交、PR、合并和发布；没有发布授权时，完成可审查的 PR，停在发布前。

不要修改 RoleP App、自动编辑 `project.pbxproj`、移动已有标签，或将派生缓存当作补丁来源。不要改动二维码算法，不引入 WebView、兼容层或新的条码识别器。

## 已确认的事实

| 项目 | 值 |
| --- | --- |
| Fork | `https://github.com/KyYuchii/zxing-cpp` |
| upstream | `https://github.com/zxing-cpp/zxing-cpp` |
| 原始基线 | `v3.1.1` |
| 基线 commit | `287c85df6f961c8efbfb5ffd736cd9457b8b890e` |
| 本地维护分支 | `rolep/ios-modulemap-3.1.1` |
| SwiftPM 产品/模块 | `ZXingCpp` |
| 本地仓库 | `/Users/kyyuchiii./Developer/RoleP-iOS/Require/ZXingFork` |

本地已有以下文件，但编写本文时仍是未提交改动，不能假定远端已经拥有它们：

- `wrappers/ios/Sources/Wrapper/module.modulemap` 的四行补丁。
- `patches/rolep/0001-exclude-private-ios-headers.patch`。
- `patches/rolep/apply.sh`：补丁重放、幂等性和冲突失败处理。
- `patches/rolep/verify.sh`：全新模块缓存的 Swift 导入检查及 native package build。
- `.github/workflows/rolep-ios-patch.yml`：初始 CI，不含发布步骤。
- `patches/rolep/README.md`：早期说明，其中“尚未创建 origin/Fork”的描述已经过时，实施时更新。

本地实际验证过：补丁重放、重复应用、以 `-Werror=incomplete-umbrella` 导入 Swift 模块、macOS SwiftPM 构建、arm64 iOS Simulator SwiftPM 构建。上游仍有其他 C++ 编译警告；不得把这次补丁描述为整个上游仓库零警告。GitHub 托管 runner 尚未验证。

## 1. 建立远端事实与维护分支

1. 核对登录账号、Fork 所属者、默认分支、分支保护、Actions 开关，以及用户已推送的文件。
2. 检查默认分支是否已经偏离上游；保留已有提交，不强推、不 reset 用户分支。
3. 从上面的固定 commit 建立或核对维护分支，不直接基于 upstream 最新 HEAD 开发。
4. 推送本地维护分支前，核对差异仅包含补丁、脚本、文档和本任务工作流。精确暂存，不使用宽泛的 `git add .`。
5. 工作流最终必须进入 Fork 的默认分支，才能通过 `workflow_dispatch` 手动运行。若默认分支需通过 PR 集成，先提交 PR；不要为显示 Run workflow 按钮擅自更改默认分支。

## 2. 实施最小补丁

目标文件：`wrappers/ios/Sources/Wrapper/module.modulemap`。

```diff
 module ZXingCpp {
     umbrella header "UmbrellaHeader.h"
+    // Internal C++ conversion helpers and build configuration are not Swift API.
+    exclude header "Reader/ZXIPosition+Helper.h"
+    exclude header "ZXIFormatHelper.h"
+    exclude header "Version.h"
     export *
     module * { export * }
 }
```

两个 Helper 含有 C++ 类型，Version.h 是内部构建配置；显式排除它们，避免 umbrella 未覆盖头文件的三条诊断。不得直接把这些 C++ Helper import 到公开 umbrella 中。源文件仍可包含这些内部头文件。

补丁文件必须通过 `git diff` 从固定基线生成，不能混入算法或版本号变化。`apply.sh` 的约定：

1. `git apply --check` 成功时应用。
2. 若正向检查失败，但 `git apply --reverse --check` 成功，报告已应用并成功退出。
3. 其他情况失败退出，显示冲突，不能忽略补丁或盲目恢复文件。

所有脚本使用 `set -euo pipefail`，路径变量双引号保护。不要依赖执行者当前工作目录。

## 3. CI：验证当前 Fork，也验证补丁可重放

完善现有 `rolep-ios-patch.yml`，保留两条独立验证链：

### A. 当前 Fork 源码

checkout 本次 PR/分支的源码，直接验证它自身。不能只验证“上游 + patch”而遗漏实际发布的 Fork。

- `git diff --check`。
- 导入检查，使用新的、独立的 Clang module cache。
- native/macOS SwiftPM 构建。
- arm64 iOS Simulator 构建。
- arm64 iOS device SDK 库构建，无签名；这是库构建，不要求实体设备。

### B. 固定上游 + 补丁

将 upstream checkout 到另一个目录，默认固定为基线 commit；允许手动指定另一个上游 tag/commit 做兼容性试验。

- 对独立 upstream checkout 应用保存的 patch，连续执行两次以检查幂等性。
- 运行同样的 Swift 模块导入与平台构建。
- 默认基线下，比较补丁后的 module map 与当前 Fork 的 module map，应完全一致。
- 上传实际应用的 diff、上游 commit、构建日志和工具链版本。
- 测试新版 upstream 只表示兼容性检查，不能因此自动更新产品基线、合并或发布。

建议把以上复用步骤集中到脚本或 reusable workflow；不得复制多份补丁或用复杂配置框架包裹几个命令。

### 可直接使用的验证命令

以下在 macOS runner 上执行；`source_root` 指向待验证的源码，`scratch` 指向本次任务独立目录：

```bash
set -euo pipefail
source_root="$GITHUB_WORKSPACE/fork"
scratch="$RUNNER_TEMP/rolep-zxing-check"
mkdir -p "$scratch"
printf 'import ZXingCpp\nlet reader = ZXIBarcodeReader()\n' > "$scratch/import-smoke.swift"
xcodebuild -version
swift --version
xcrun swiftc -typecheck \
  -module-cache-path "$scratch/fresh-module-cache" \
  -I "$source_root/wrappers/ios/Sources/Wrapper" \
  -Xcc -Werror=incomplete-umbrella "$scratch/import-smoke.swift"
swift build --package-path "$source_root" --scratch-path "$scratch/macos"
swift build --package-path "$source_root" \
  --triple arm64-apple-ios16.0-simulator \
  --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  --scratch-path "$scratch/ios-simulator"
swift build --package-path "$source_root" \
  --triple arm64-apple-ios16.0 \
  --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  --scratch-path "$scratch/ios-device"
```

本地已验证前两种平台构建；device SDK 构建需在搭建过程中补验。iOS 16.0 是该 CI 的构建测试目标，不修改 Package.swift 声明的最低支持版本。不要从裸 Package.swift 目录假设 `xcodebuild -scheme ZXingCpp` 可工作；本地该方式未识别为工程，已改为 SwiftPM 的 SDK/triple 构建。

### 触发与 runner

- PR：验证即将合并的源码。
- Push：维护分支以及实际发布来源分支；不要只覆盖 `rolep/**` 而遗漏默认分支上的发布候选提交。
- `workflow_dispatch`：接收上游兼容性测试 ref。
- 可增加每周一次的上游兼容检查，失败仅报状态，不自动升级。
- 初始 runner 使用 `macos-15`；实施时确认可用 Xcode/Swift 版本，在日志中记录。若 pin Xcode，选定已验证且 runner 支持的版本，不使用未经核验的路径。
- 冷缓存模块导入检查始终执行，不通过复用 PCM 缓存掩盖 Warning。
- 加入合理 timeout、同分支并发取消、artifact 保留期限。

## 4. CD：验证后发布不可变 SwiftPM 源码版本

这是源码包，不需要部署服务器、Docker、App Store 或 Apple 签名证书。

新增独立发布 workflow，推荐手动 `workflow_dispatch`，输入明确的候选 commit SHA、发布 tag 和发布说明；默认不跟随浮动分支 HEAD。

1. 校验 SHA 为完整十六进制提交号，tag 为约定格式，例如 `v3.1.1-rolep.1`。
2. 确认候选 SHA 已进入批准的发布来源分支；先完整 fetch，按明确分支检查祖先关系。
3. checkout 这个精确 SHA，复用 CI，验证当前 Fork 源码及其补丁来源一致性。
4. 校验不存在同名 tag 或 release；存在时失败，不覆盖、不删除后重建。
5. 发布 job 使用 `needs` 等待 CI 全部成功；checkout 相同 SHA，不能重新解析浮动 HEAD。
6. 仅发布 job 获得 `contents: write`；其他 jobs 保持 `contents: read`。
7. 在用户已有发布授权下创建 tag 和 GitHub Release，记录候选 SHA、上游 SHA、补丁 SHA256、Xcode/Swift 版本及已知上游警告。
8. 若用户要求人工发布审核，可配置 `release` environment；先核对当前账号/仓库是否支持所需保护功能。没有该功能时采用经批准的手动发布流程，不假设保护已生效。
9. 发布失败不能留下指向错误提交的标签；报告已创建的外部对象和最后成功步骤，不能静默重写已发布 tag。

SwiftPM 直接消费 Git tag 和仓库内容。GitHub 自动生成的源码归档足够；只有未来确需二进制分发时才另行设计 XCFramework 与 checksum。

`v3.1.1-rolep.1` 是独立的 SemVer prerelease 版本，RoleP 应显式 exact pin；不要使用宽泛范围，也不要覆盖 upstream 的 `v3.1.1`。

## 5. Actions 权限和上游自带 workflows

- 核对 Fork 继承的 `.github/workflows`。其中含上游其他语言的发布流程，不应让这次维护任务意外触发 PyPI、NuGet、Android、站点等发布。
- 用户确认后，在 Fork 中禁用不需要的上游发布 workflows，或给它们加上明确的上游仓库条件。不要删除上游源代码模块。
- workflow 默认 `permissions: contents: read`，仅发布 job 提权。
- checkout 设置 `persist-credentials: false`；发布需要 Git 推送时明确安排最小权限认证，不能依赖 checkout 遗留凭据。
- 初始本地模板的 Actions 使用版本标签；正式搭建时核对官方仓库并锁定完整 commit SHA，同时保留版本注释。不要凭记忆填 SHA。
- 手动输入经 env 变量传给 shell 并校验，不将 `${{ inputs.* }}` 直接拼成脚本代码。
- 普通 PR 使用 `pull_request`；不通过带写权限的 `pull_request_target` 执行未信任 PR 的脚本。
- 不需要外部服务凭证；优先使用 job 自带 `GITHUB_TOKEN`，不要让用户把 PAT、证书或私钥写进文档、仓库或日志。

## 6. RoleP 接入与回滚交接

发布完成后，将以下信息交给 RoleP 开发者：

- Fork URL、精确发布 tag、发布 commit、upstream 基线 SHA。
- 成功 CI 和 Release 的链接。
- 三条 umbrella Warning 的验证日志及其余已知警告。

由开发者在 Xcode 手动替换包 URL 为 Fork，选择发布版本的 Exact Version，确认 RoleP Target 仍链接 `ZXingCpp` 产品。不要同时保留两个相同 identity 的 zxing-cpp 包。

随后检查 Package.resolved 的来源和 revision，执行冷缓存完整 App 构建，再做真机相机、图库、旋转图片、框外二维码和扫描性能验收。CI 的库构建不能代替 RoleP 的真机验收。

回滚通过将 App 的依赖精确 pin 回前一已验证发布，或原始 upstream v3.1.1；保留新旧发布标签与记录，不修改历史 tag。

## 7. Grok 交付验收清单

- [ ] 远端真实默认分支、维护分支和发布来源已记录。
- [ ] 最小 module map 补丁及 patch 文件一致，无算法变化。
- [ ] 重放、重复应用和冲突失败三种情况均已测试。
- [ ] 全新缓存下 `-Werror=incomplete-umbrella` 导入成功。
- [ ] Fork 自身与 upstream + patch 都完成 macOS / iOS Simulator / iOS device SDK 构建。
- [ ] 默认分支上的手动运行入口可见，至少一次 GitHub 托管 CI 实际成功。
- [ ] 发布流程只在验证成功后操作指定 SHA，重复 tag 发布测试会被拒绝。
- [ ] 没有打开不必要的上游发布通道，CI 无写权限或秘密泄漏。
- [ ] 发布授权、tag、release、CI 链接与未完成项全部如实交接。
- [ ] 未自动修改 RoleP 工程与应用依赖。

最终回复应区分“已编写 YAML”“已在 GitHub 跑通”“已发布版本”“RoleP 已接入”四个阶段，不能相互替代。

## 官方参考

- [手动运行工作流：workflow_dispatch 文件需位于默认分支](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- [Actions 安全使用：最小权限、完整 SHA 固定、输入与 PR 信任边界](https://docs.github.com/en/actions/reference/security/secure-use)
