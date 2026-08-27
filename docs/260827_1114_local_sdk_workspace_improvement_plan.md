# 本地 SDK Workspace 改进方案

## 状态

方案已确认并完成概念验证。个人 workspace 成功解析本地 SDK，标准 workspace 仍解析远程 `release`；共享工程文件与个人依赖状态已完成 Git 隔离。

## 结论

当前通过修改共享 `project.pbxproj` 切换本地 SDK 的方案可以构建，但不适合作为长期日常流程。它会让 App worktree 固定存在以下两项差异：

- `SunSmart.xcodeproj/project.pbxproj` 被替换为个人绝对路径。
- Xcode 解析纯本地 Package 后删除 shared `Package.resolved`。

这会增加误提交风险，也会让开发者在提交 App 代码时持续处理依赖配置差异。

建议改为：**共享工程永远保持远程 `release` 基线；每个 App worktree 使用一个自动生成、被 Git 忽略的个人 workspace 来覆盖本地 SDK。**

## 目标结构

### Git 共享内容

- `SunSmart.xcodeproj` 始终引用远程 Gitee `release` 分支。
- `SunSmart.xcworkspace` 始终使用并提交 shared `Package.resolved`。
- 团队成员和 CI 只打开 `SunSmart.xcworkspace`。
- 增加一个可提交的本地 workspace 初始化脚本和协作文档。

### 每个 App worktree 的个人内容

- 生成 `SunSmartLocal.xcworkspace`，加入 `.gitignore`。
- 生成 `.local-sdk/nordic-sig-mesh-sdk` 本地别名，加入 `.gitignore`。
- 该别名指向实际 SDK worktree `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- 个人开发者打开 `SunSmartLocal.xcworkspace`。
- 本地 workspace 拥有自己的 SwiftPM 解析状态，不修改标准 workspace 的 `Package.resolved`。

## 为什么需要本地别名

已经通过 Xcode 实际验证：直接把目录 `one-dev` 加入与远程 Package 相同的 workspace 会失败，因为 Swift Package identity 使用本地目录名：

- 远程 identity：`nordic-sig-mesh-sdk`
- 本地 identity：`one-dev`

Xcode 会报告 identity 不匹配和 `NordicSigMeshSDK` Product 重名。

因此个人 workspace 中应使用末级目录名为 `nordic-sig-mesh-sdk` 的本地别名，别名实际指向 `one-dev`。如果 SwiftPM 解析后仍把 identity 识别成 symlink 真实目录名，则停止实施，不继续修改共享工程；备选方案是经用户确认后把 SDK worktree 移到末级目录名正确的位置。

## 拟修改范围

### 共享 App 仓库

- 修改 `.gitignore`：忽略 `SunSmartLocal.xcworkspace/` 和 `.local-sdk/`。
- 新增 `scripts/setup_local_nordic_sdk_workspace.sh`：为当前 App worktree 生成个人 workspace 和本地 Package 别名。
- 修改 `scripts/check_nordic_sdk_dependency.sh`：继续只验证共享 project 和标准 workspace，确保远程基线没有被个人配置污染。
- 更新 `docs/260827_1054_nordic_sdk_collaboration_workflow.md`：用个人 workspace 流程替代本地修改 `project.pbxproj` 的流程。
- 更新原实施计划，标记旧方案被本方案取代。

### 当前个人工作区

- 将 `project.pbxproj` 恢复为 Git HEAD 的远程依赖状态。
- 将 `Package.resolved` 恢复为 Git HEAD 中锁定 `release @ 9504e5b` 的状态。
- 运行初始化脚本，生成被忽略的 `SunSmartLocal.xcworkspace` 和 `.local-sdk`。
- 保留未跟踪的 OEM 分析文档，不纳入本次改进提交。

## 初始化脚本行为

脚本只处理当前 App worktree 内两个明确的生成目标，不修改共享 `project.pbxproj`、标准 workspace、Package.resolved、Git 分支或 SDK 仓库。

SDK 路径解析顺序：

1. 脚本显式路径参数。
2. `NORDIC_SIG_MESH_SDK_ROOT` 环境变量。
3. 默认个人路径 `../../nordic-sig-mesh-sdk-worktrees/one-dev`。

执行前检查：

- SDK 目录存在且包含 `Package.swift`。
- SDK 是 Git worktree，并记录当前分支与 HEAD 供用户查看。
- App 的共享 project 当前为远程 `release` 配置。
- 标准 `Package.resolved` 存在。

生成内容：

- identity 正确的本地 SDK 别名。
- 同时包含 `SunSmart.xcodeproj`、`Pods/Pods.xcodeproj` 和本地 SDK 的个人 workspace。
- 不复制 SDK 源码，不创建认证信息，不修改 SDK Git 状态。

## 日常使用方式

### 你开发 App + SDK

1. 在当前 App worktree 运行一次初始化脚本。
2. 打开 `SunSmartLocal.xcworkspace`。
3. App 代码仍在当前 App worktree 正常修改、暂存和提交。
4. SDK 代码直接在 `one-dev` 修改和提交。
5. `git status` 不应出现个人 Package 配置差异。

换到另一个 App worktree 时，只需要在新 worktree 再运行一次初始化脚本；不需要修改或提交该 worktree 的 project 文件。

### 其他团队成员

1. 正常拉取 App 仓库。
2. 打开标准 `SunSmart.xcworkspace`。
3. 使用 shared `Package.resolved` 对应的远程 `release` revision。
4. 不运行个人 workspace 初始化脚本，也不需要本地 SDK checkout。

## 验证计划

### 概念验证

1. 恢复当前共享 project 和 `Package.resolved`。
2. 生成个人 workspace 与 identity 别名。
3. 运行 Package 解析，必须显示 SDK 来源为 `one-dev` 对应的本地路径，而不是 DerivedData 远程 checkout。
4. 如果 identity 仍不匹配，停止并向用户报告，不采用 symlink 方案。

### 共享模式

1. `scripts/check_nordic_sdk_dependency.sh` 通过。
2. 标准 workspace 解析 `release @ 9504e5b`。
3. 四个现有品牌 generic iPhoneOS Debug 无签名构建保持通过。

### 个人模式

1. 个人 workspace 解析本地 SDK。
2. SunSmart generic iPhoneOS Debug 无签名构建通过。
3. 构建日志的 SDK 工作目录指向本地别名或其实际 `one-dev` 目录。
4. 标准 `project.pbxproj` 和 `Package.resolved` 保持与 Git HEAD 一致。
5. `git status` 只显示真实 App 代码变化和现有未跟踪文档，不显示本地 SDK 配置。

## 验证结果

- 初始化脚本成功生成个人 workspace 与 identity 别名。
- 个人 workspace 解析来源为 `.local-sdk/nordic-sig-mesh-sdk`，其实际目标为 `one-dev`。
- 个人 workspace 的 SunSmart generic iPhoneOS Debug 无签名构建通过。
- 标准 workspace 解析 Gitee `release @ 9504e5b`。
- 标准 workspace 的 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四品牌 generic iPhoneOS Debug 无签名构建通过。
- `project.pbxproj` 与 shared `Package.resolved` 均保持 Git HEAD 状态。
- 个人 workspace 与 SDK 别名均被 Git 忽略。

## 提交策略

如果概念验证通过，提交以下共享内容：

- `.gitignore`
- 初始化脚本
- 依赖检查调整
- 更新后的计划和协作文档

生成的个人 workspace、本地别名和个人 SwiftPM 状态不提交。

## 不在本次范围

- 不修改 SDK 业务源码。
- 不移动或重命名 SDK worktree，除非 symlink identity 验证失败且用户另行确认。
- 不修改 OEM Target。
- 不 push App 或 SDK。
- 不使用 `skip-worktree` 隐藏共享文件差异。
