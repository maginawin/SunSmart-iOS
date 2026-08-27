# NordicSigMeshSDK 团队协作基础框架修改计划

## 状态

用户已确认方案 A。远程共享基线已实施、验证并形成 Git 提交；原先修改共享 `project.pbxproj` 的个人替换方式已被双 workspace 方案取代。本计划暂不包含 OEM Target。

## 实施进度

- 已确认 `origin/release` 存在并指向 `9504e5ba7286205f8d4749d8127bf2178b19d9a2`。
- 已将 App 的唯一 Package Reference 切换为 Gitee SSH URL 的 `release` 分支。
- 已生成 shared `Package.resolved`，锁定上述已验证 revision。
- 已新增共享依赖检查和协作文档。
- 已统一 13 个 SDK 源码检查脚本的路径解析。
- 已通过四个品牌的 generic iPhoneOS Debug 无签名构建。
- 远程共享基线已提交。
- 直接 Add Local 因本地目录 identity 为 `one-dev` 而失败，已使用末级目录名为 `nordic-sig-mesh-sdk` 的本地 symlink 保持 Package identity 一致。
- 已新增并忽略 `SunSmartLocal.xcworkspace` 与 `.local-sdk`，个人联调不再修改共享 `project.pbxproj` 或删除 shared `Package.resolved`。
- Xcode 已确认个人 workspace 从本地别名解析和编译 SDK，SunSmart generic iPhoneOS Debug 无签名构建通过。
- 标准 workspace 仍解析 Gitee `release @ 9504e5b`，四品牌 generic iPhoneOS Debug 无签名构建通过。

## 目标

建立两种明确且不会混淆的 SDK 使用模式：

- 个人联调模式：App 使用绝对路径 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，允许同时修改 App 与 SDK。
- 团队共享模式：App 使用 `git@gitee.com:sunricher-i-os/nordic-sig-mesh-sdk.git` 的 `release` 分支，团队成员仅有读取权限。

## 对现有计划的评价

总体方向合理，但当前还不完整，暂时不能直接实施，缺少以下边界：

1. Gitee `origin` 当前不存在远程 `release` 分支；只有本地 `release` worktree。
2. 本地 `one-dev` 与 `release` 当前都没有设置 upstream。
3. “使用 release 最新提交”的刷新时机没有定义。普通 Xcode Build 不保证每次都主动更新远端分支。
4. 没有定义如何避免个人绝对路径被提交到 App 共享分支。
5. 没有定义 SDK 从 `one-dev` 晋升到 `release` 的条件、分叉处理和回滚方式。
6. 当前有 13 个检查脚本仍引用旧 SDK 路径或旧相对目录，切换到 `one-dev` 后部分检查会读取错误 SDK。
7. 没有定义远程模式与本地模式分别需要通过哪些 Target 构建验证。

## 已核对的当前状态

### App 仓库

- 当前分支：`fix`
- 当前 HEAD：`72b5293c`
- `SunSmart.xcodeproj` 仍通过一个项目级 `XCLocalSwiftPackageReference` 指向旧路径 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 Target 都链接该 Package 的 `NordicSigMeshSDK` Product。
- 当前没有纳入 Git 的 `Package.resolved`。
- 当前已有一份未跟踪的前序分析文档，本计划不会覆盖或删除它。

### SDK 仓库

- `one-dev` worktree 存在，工作区干净，分支为 `one-dev`。
- `release` worktree 存在，工作区干净，分支为 `release`。
- 两者当前都指向 `9504e5ba7286205f8d4749d8127bf2178b19d9a2`。
- `origin` URL 为 `git@gitee.com:sunricher-i-os/nordic-sig-mesh-sdk.git`。
- 远程现有分支只有 `dev`、`master`、`timezone`；远程 `release` 尚未创建。
- 当前 commit 已存在于远程 `timezone`，因此创建首个远程 `release` 时不需要重新产生 SDK 源码提交。

## 关于 release 最新提交与 Package.resolved

### 推荐方案 A：release 分支约束 + 提交 Package.resolved

这是推荐方案。

- Xcode 工程中的 Package requirement 设置为 `release` 分支，不在 `project.pbxproj` 中写死 exact commit。
- 每次正式发布 SDK 后，在 App 共享分支执行一次 Package 更新，让 `Package.resolved` 记录当时 `release` 的最新 commit。
- 将 `Package.resolved` 与 App 改动一起提交。
- 团队成员、CI 和历史 App commit 都使用相同 SDK revision。

此方案仍然是“工程跟随 release 分支”，但把“什么时候采用 release 的新 HEAD”变成一次明确的 App 依赖升级，而不是让不同开发者在不同时间自动拿到不同 SDK。

### 备选方案 B：完全浮动到 release 最新 HEAD

如果坚持不提交 `Package.resolved`：

- 新 clone 或清理后的首次解析通常取得当时的 `release` HEAD。
- 已解析过的 Xcode workspace 可能继续使用旧 revision，必须由团队成员主动执行 Package 更新。
- 同一个 App commit 在不同日期可能构建出不同结果。
- SDK `release` 必须长期保持向后兼容，否则旧 App 可能在未来重新构建时失败。
- CI 必须明确执行依赖更新，否则也未必使用最新 HEAD。

只读权限能防止团队成员推送 SDK，但不能解决构建不可复现问题。因此不推荐方案 B，也不建议在每次普通 Build 前自动联网更新 Package。

## 拟实施方案

以下默认采用推荐方案 A；如果用户明确选择方案 B，再调整 `Package.resolved` 和校验规则。

### 阶段 1：建立 SDK release 发布线

范围：SDK 仓库分支与远程，不修改 SDK 源码。

1. 再次确认 `one-dev`、`release` 两个 worktree 均干净。
2. 确认本地 `release` 指向准备发布的已测试 commit。
3. 首次把本地 `release` 明确推送为 `origin/release`，并建立 upstream。
4. 不推送个人 `one-dev` 分支，除非后续另有备份或协作需求。
5. 禁止 force push 和删除远程 `release`。

首次创建远程分支属于外部状态变更，实施时需要用户再次明确授权执行 push。

### 阶段 2：把 App 的共享依赖切换为远程 release

修改范围：

- `SunSmart.xcodeproj/project.pbxproj`
- Xcode 生成的 shared `Package.resolved`
- 新增依赖配置检查脚本
- 新增团队协作文档

具体修改：

1. 将唯一项目级 `XCLocalSwiftPackageReference` 改为 `XCRemoteSwiftPackageReference`。
2. Repository URL 使用用户指定的 SSH URL。
3. Package requirement 使用 `release` branch。
4. 保持四个现有 App Target 都依赖同一个 Package Reference 和 `NordicSigMeshSDK` Product，不创建重复 Package。
5. 通过 `SunSmart.xcworkspace` 解析依赖。
6. 按最终确认的 Package.resolved 策略处理锁文件；默认采用方案 A 并提交 shared 文件。
7. 增加共享配置检查：拒绝 App 工程出现 `XCLocalSwiftPackageReference`、`/Users/...` SDK 路径、错误 URL、错误分支或遗漏 Target Product dependency。
8. 增加简体中文协作文档，写清团队首次拉取、SDK 更新通知、Package 更新和故障恢复步骤。

### 阶段 3：建立你的个人 one-dev override（已由双 workspace 方案取代）

前提：阶段 2 的远程基线已经完成审核并形成可恢复的 Git 提交。

1. Git HEAD 中始终保留远程 `release` dependency 和 shared `Package.resolved`。
2. 初始化脚本生成被忽略的个人 workspace，并通过末级目录名为 `nordic-sig-mesh-sdk` 的 symlink 指向 `one-dev`。
3. 个人开发打开 `SunSmartLocal.xcworkspace`，团队和 CI 打开 `SunSmart.xcworkspace`。
4. App 源码在同一 worktree 正常修改和提交；个人依赖配置不进入 `git status`。
5. 每个 App worktree 只需单独初始化一次，不再进行工程引用来回切换。

### 阶段 4：统一依赖 SDK 源码的检查脚本

当前有 13 个 Shell 检查脚本仍引用旧路径或旧相对位置。

计划统一为以下解析顺序：

1. 脚本显式参数。
2. `NORDIC_SIG_MESH_SDK_ROOT` 环境变量。
3. 仅在你的机器存在时使用 `one-dev` 作为便捷 fallback。
4. 都不可用时给出清晰错误，不静默读取其他 SDK worktree。

不把认证信息写入脚本，不让团队脚本自动修改或更新 SDK 仓库。历史 `docs/` 中记录旧路径的事实性材料不做批量替换。

### 阶段 5：定义 SDK 发布流程

每次 SDK 从 `one-dev` 发布到 `release` 时：

1. 确认 SDK worktree 干净、测试通过、App 本地联调通过。
2. 让 `release` 只前进到已经验证的 `one-dev` commit。
3. 优先使用 fast-forward；如果两个分支已分叉则停止，不自动 rebase、merge 或 force push。
4. 在处理分叉并重新完成 SDK/App 验证后，显式推送 `origin release`。
5. 方案 A 下，在 App 共享分支更新 `Package.resolved` 并执行远程模式构建验证。
6. 发布失败时不强制回退远程分支；使用 revert commit 或向前修复，再重新验证和发布。

## 验证计划

### 远程共享模式

1. 静态检查确认项目中没有本机 SDK 绝对路径。
2. 确认只存在一个远程 Package Reference，URL 与 `release` requirement 正确。
3. 确认四个 App Targets 都链接 `NordicSigMeshSDK`。
4. 从 `SunSmart.xcworkspace` 完成 Package 解析。
5. 依次执行 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 generic iPhoneOS Debug 无签名构建。
6. 执行依赖检查脚本和 `git diff --check`。

### 本地 one-dev 模式

1. 确认实际解析路径为 `one-dev`，而不是旧 SDK 根目录或 Xcode 远程缓存。
2. 执行 SDK 相关测试和至少一次 App 集成构建。
3. SDK 公共 API 或共享行为变化时，依次构建四个现有 App Targets。
4. 构建成功只证明源码和依赖契约通过；BLE、Mesh、固件、服务器和真实设备行为仍需分别验收。

## 不在本次范围

- 不新增 OEM Target。
- 不修改 SDK 业务源码或协议行为。
- 不修改 App 业务功能、UI、本地化或品牌资源。
- 不自动 commit、merge、push 或 force push。
- 不配置或写入新的认证信息。
- 不批量重写历史文档中的旧 SDK 路径。

## 待用户确认

1. 是否接受推荐方案 A：项目跟随 `release` 分支，同时提交 `Package.resolved`，在每次 SDK 发布后显式更新一次 App 锁定 revision。
2. 是否确认首次实施时允许创建并推送远程 `origin/release`；该 push 会在实际执行前再次提示。
3. 是否同意远程基线先形成可审核/可提交状态，再添加你的个人 `one-dev` override，避免共享配置与个人配置混在同一个未提交状态中。
