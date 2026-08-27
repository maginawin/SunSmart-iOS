# NordicSigMeshSDK 团队协作流程

## 适用范围

本文只说明 SunSmart App 与 NordicSigMeshSDK 的协作、发布和依赖更新流程，不包含 OEM Target。

## 两种开发模式

### 团队共享模式

- App 工程使用 `git@gitee.com:sunricher-i-os/nordic-sig-mesh-sdk.git`。
- Package requirement 跟随 `release` 分支。
- `Package.resolved` 记录当前 App 已验证的 SDK revision，并随 App 仓库提交。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 共用同一个远程 Package Product。
- 普通 App 开发者只需要 SDK 仓库读取权限，不修改和推送 SDK。

团队成员应打开 `SunSmart.xcworkspace`，而不是只打开 `.xcodeproj`。正常拉取 App 更新后，优先使用仓库中的 `Package.resolved`，不要自行更新到未经过 App 验证的 SDK HEAD。

### 个人 App + SDK 联调模式

- 本地 SDK 使用 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- Git 中的共享基线始终保留远程 `release` dependency。
- 运行 `scripts/setup_local_nordic_sdk_workspace.sh`，生成被 Git 忽略的 `SunSmartLocal.xcworkspace` 和 `.local-sdk/nordic-sig-mesh-sdk`。
- `.local-sdk/nordic-sig-mesh-sdk` 是 identity 别名，实际指向 `one-dev`，不会复制 SDK 源码。
- 个人开发时打开 `SunSmartLocal.xcworkspace`；App 代码仍在当前 App worktree 内正常修改和提交，SDK 代码仍直接在 `one-dev` 修改和提交。
- 标准 `SunSmart.xcworkspace`、共享 `project.pbxproj` 与 shared `Package.resolved` 不会因个人联调发生变化。
- 换到另一个 App worktree 时，在新 worktree 再运行一次初始化脚本；不需要切换分支，也不需要长期保留工程文件差异。

SDK 路径可通过脚本第一个参数或 `NORDIC_SIG_MESH_SDK_ROOT` 指定；未指定时使用当前约定的 `one-dev` 默认位置。如果已有别名指向其他目录，脚本会停止并要求显式处理，不会静默改写。

此方案的底层能力来自 Xcode 的同名本地 Package override。Apple 官方说明：保留已发布的远程 Package dependency，再把同名本地 Package 加入 App，即可在联调期间覆盖远程依赖；移除本地 Package 后恢复远程依赖。双 workspace 是本项目为了隔离共享 Git 配置而增加的工程化封装，并不是 Apple 单独命名的一种 workspace 类型。

## SDK 发布到 release

只有拥有 SDK push 权限的维护者执行以下流程：

1. 在 `one-dev` 完成 SDK 修改与提交。
2. 确认 `one-dev` 工作区干净。
3. 完成 SDK 自动测试、App 本地集成构建以及需要的真实设备验证。
4. 确认本地 `release` 与 `origin/release` 没有意外分叉。
5. 让 `release` fast-forward 到已经验证的 `one-dev` commit。
6. 如果不能 fast-forward，停止发布；处理分叉后必须重新验证。
7. 显式推送 `origin/release`，禁止 force push。
8. 在 App 的远程共享模式下更新 Package，让 `Package.resolved` 记录新的 `release` revision。
9. 运行依赖检查并构建四个品牌 Target。
10. 将 `Package.resolved` 更新随 App PR 或共享提交交付给团队。

如果 SDK 发布后发现问题，不强制移动远程分支到旧 commit。应使用 revert commit 或向前修复，重新完成验证后发布。

## App 采用新 SDK release

SDK `release` 更新不会自动代表所有开发者下一次普通 Build 都采用最新 HEAD。App 采用新 SDK 的完成条件是：

- Xcode 已将远程 Package 更新到目标 `release` HEAD。
- shared `Package.resolved` 已记录该 revision。
- `scripts/check_nordic_sdk_dependency.sh` 通过。
- 四个品牌的 generic iPhoneOS Debug 无签名构建通过。
- `Package.resolved` 与需要的 App 兼容改动一起进入共享提交。

因此，“最新 SDK”指当前 App 提交明确更新并验证过的 `release` HEAD，而不是构建时无条件联网追踪远端。

## SDK 源码检查脚本

需要直接读取 SDK 源码的 App 检查脚本按以下顺序解析 SDK 根目录：

1. 脚本第一个显式路径参数。
2. `NORDIC_SIG_MESH_SDK_ROOT` 环境变量。
3. 当前机器存在的 `nordic-sig-mesh-sdk-worktrees/one-dev`。
4. 都不存在时明确失败。

脚本不会自动 clone、fetch、checkout、修改或更新 SDK，也不会写入认证信息。需要针对远程锁定 revision 检查时，应显式传入一个 HEAD 与 `Package.resolved` 一致的干净 SDK checkout。

## 分享前检查

分享 App 改动前至少确认：

- `project.pbxproj` 不包含 `XCLocalSwiftPackageReference` 的 NordicSigMeshSDK 引用。
- `project.pbxproj` 不包含个人 `/Users/...` SDK 路径。
- Repository URL 是约定的 Gitee SSH 地址。
- Package requirement 是 `release`。
- `Package.resolved` 存在且 identity、URL、branch 和 revision 正确。
- 标准 workspace、`project.pbxproj` 与 `Package.resolved` 始终保持共享基线。
- `SunSmartLocal.xcworkspace` 和 `.local-sdk` 未被 Git 跟踪。
- 四个 App Targets 仍链接 `NordicSigMeshSDK`。
- `scripts/check_nordic_sdk_dependency.sh` 和 `git diff --check` 通过。

## 验收边界

- Package 解析成功只证明远程访问和依赖描述有效。
- 四品牌编译成功只证明 App/SDK 源码与构建契约兼容。
- SDK 单元测试和 App 自动检查不证明真实 BLE、Mesh、固件持久化、服务器或 UI 行为。
- 涉及协议和设备行为的 SDK 发布仍需对应的真实设备验证。

## 参考

- Apple Developer Documentation: [Developing a Swift package in tandem with an app](https://developer.apple.com/documentation/xcode/developing-a-swift-package-in-tandem-with-an-app)
- Apple Developer Documentation: [Editing a package dependency as a local package](https://developer.apple.com/documentation/xcode/editing-a-package-dependency-as-a-local-package)
