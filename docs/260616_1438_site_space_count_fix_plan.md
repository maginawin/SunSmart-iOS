# Site Space Count Fix Plan

## 背景

`siteInfo` 新日志显示，Site 页面刷新时两个 Space 都进入了 `phase=skipped`：

- `serverUpdateTimestamp=1781589312`
- `localLastUpdate=1781589312`
- `note=serverUpdateTimestampNotNewer`

因此 `SpaceData.update(spaceJsonData:)` 没有执行 full import，Site 卡片继续显示本地 SQLite 的旧 count。`Space 1` 服务端顶层摘要为 `nodes=0, switches=0, scenes=0, groups=1, schedules=0`，本地旧摘要为 `device=0, switches=4, scenes=0, groups=1, schedules=0`，所以 `switches=4` 是本地 stale count。

## 修复目标

当服务端 `updateTimestamp` 未递增但顶层摘要已经和本地不一致时，客户端应能刷新 Site 页面简介，且不能覆盖本地未上传改动。

## 方案比较

### 方案 A：服务端递增 `updateTimestamp`

服务端在 Space 顶层 `nodes/groups/switches/scenes/schedules` 任一内容变化时递增 `spaces[*].updateTimestamp`。

优点：

- 符合当前客户端数据合同。
- App 不需要绕过现有 full import gate。
- 所有客户端一致受益。

缺点：

- 需要服务端配合，App 侧不能单独落地。
- 已经存在的脏数据仍需要重新触发服务端更新时间或重新同步。

### 方案 B：客户端只覆盖 count 摘要

当 `updateTimestamp` 相等但服务端数组 count 和本地 count 不一致时，只更新 `SpaceData.deviceCount/switchesCount/groupCount/sceneCount/scheheduleCount` 并保存。

优点：

- 改动最小，能快速修正 Site 卡片。
- 不重建 MeshNetwork，风险低。

缺点：

- 只修 Site 简介，不修 Space 内部实际数据。
- 可能出现卡片 count 与进入 Space 后内容不一致。
- 对 `mmmm` 这种服务端 `groups=16`、本地 `groups=9` 的情况，只更新摘要会掩盖更深的数据 stale。

### 方案 C：客户端受保护地绕过 timestamp gate 执行 full import

当 `updateTimestamp` 相等时，先判断服务端顶层摘要是否和本地摘要不一致；如果不一致且本地没有未上传改动，则继续执行现有 full import；如果本地有未上传改动，则保持 skip，避免覆盖本地修改。

优点：

- 修 Site 卡片，也同步修 Space 内部数据。
- 复用现有 `SpaceData.update` 导入链路，不新增第二套 count 合同。
- 通过 `needUploadCloud` 保护本地未上传改动。

缺点：

- 比只更新摘要重，可能触发 MeshNetwork 重建。
- 依赖服务端数组作为可信来源；如果服务端本身返回旧数据，会按旧数据覆盖本地。

推荐采用方案 C，同时保留方案 A 作为服务端长期修复建议。方案 B 不推荐作为主修复，因为它只修 UI 摘要，容易留下 Space 内部 stale 数据。

## 设计

### 数据判断

在 `SpaceData.update(spaceJsonData:initialize:)` 中，把现有 gate：

- `lastUpdate > self.lastUpdate || initialize`

扩展为：

- `lastUpdate > self.lastUpdate`
- 或 `initialize == true`
- 或 `lastUpdate == self.lastUpdate && remoteSummary != localSummary && !self.needUploadCloud`

`remoteSummary` 使用服务端顶层数组计算：

- `deviceCount`：优先使用顶层 `nodes.count`，同时保留日志中的 `deviceCount` 用于诊断。
- `groupCount`：`groups` 里 `isVirtual != true` 的数量。
- `sceneCount`：顶层 `scenes.count`。
- `scheduleCount`：顶层 `schedules.count`。
- `switchesCount`：顶层 `switches.count`。

`localSummary` 使用当前 `SpaceData` 已保存的：

- `deviceCount`
- `groupCount`
- `sceneCount`
- `scheheduleCount`
- `switchesCount`

不把 `luminairesCount` 纳入 gate，因为服务端摘要没有直接给 light count，且 App 当前是 full import 后基于 decoded nodes 计算。

### 本地改动保护

如果 `self.needUploadCloud == true`，说明本地有新改动未上传。此时即使服务端摘要不同，也不能绕过 gate 覆盖本地。

需要在 DEBUG 日志中新增 note：

- `serverSummaryDiffers`
- `serverSummaryDiffersButLocalNeedsUpload`

这样复现时可以区分“已受保护导入”和“因本地未上传而跳过”。

### 作用范围

只改 `SpaceData.update(spaceJsonData:initialize:)` 附近逻辑和 DEBUG helper，不改：

- `SpacesViewCell` 展示逻辑。
- `SpaceData.export()` payload 字段。
- `CloudSynchronizationManager` 队列。
- `SiteViewController` / `SitesViewController` 页面刷新逻辑。

## 实施任务

### Task 1：提取 Space 摘要比较 helper

文件：

- 修改：`SunSmart/Common/Data/ImportData.swift`

步骤：

- 在 `#if DEBUG` 之外增加一个私有轻量结构或私有函数，用于从 `JSON` 和 `SpaceData` 提取摘要。
- 摘要只包含 `deviceCount/groupCount/sceneCount/scheduleCount/switchesCount`。
- remote `groupCount` 按 `groups` 数组中过滤 `isVirtual == true` 后计算，和现有 full import 最终 `groupCount = groups.filter({ !$0.isVirtual }).count` 保持一致。
- helper 不保存数据，只返回用于比较的值。

验收：

- helper 不依赖 UI。
- helper 不读取数据库。
- helper 与 `SpaceData.update` 当前 count 计算口径一致。

### Task 2：扩展 timestamp gate

文件：

- 修改：`SunSmart/Common/Data/ImportData.swift`

步骤：

- 在现有 `let lastUpdate = json["updateTimestamp"].int64Value` 后，计算 `remoteSummary`、`localSummary`、`summaryDiffers`。
- 将 `guard lastUpdate > self.lastUpdate || initialize else` 改为允许 `summaryDiffers && !self.needUploadCloud` 继续导入。
- 如果 `summaryDiffers && self.needUploadCloud`，保持 skip，并在 DEBUG 日志 note 中输出 `serverSummaryDiffersButLocalNeedsUpload`。
- 如果 `summaryDiffers && !self.needUploadCloud`，继续走原有 full import，并在 DEBUG 日志 note 中输出 `serverSummaryDiffers`。

验收：

- `Space 1` 这类 `server switches=0`、`local switches=4`、timestamp 相等、无本地未上传改动的情况，会进入 `applied`。
- 本地 `needUploadCloud == true` 时仍然 skip，不覆盖本地未上传改动。

### Task 3：清理或保留诊断日志

文件：

- 修改：`SunSmart/Common/Data/ImportData.swift`
- 修改：`docs/260616_1426_site_space_count_log_analysis.md`

步骤：

- 如果修复期间仍需现场验证，保留 `[PJSpaceCountProbe]`，但把 note 扩展为能体现 gate 决策。
- 如果准备合并正式版本，移除临时日志或确认它只在 `#if DEBUG` 下编译。
- 在分析文档中追加最终选择的 gate 规则和验证结果。

验收：

- Release 不输出临时诊断日志。
- Debug 日志能解释每个 Space 是 `skipped` 还是 `applied`。

### Task 4：验证

命令：

- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

手动复现：

- 打开 Sites，点击目标 Site 进入 Site 页面。
- 查看 `[PJSpaceCountProbe]`：
  - `Space 1` 预期从 `received` 进入 `applied`，note 包含 `serverSummaryDiffers`。
  - `Space 1` 导入后 `localCounts switches=0, scenes=0`。
  - `mmmm` 如果 `groups=16` 和本地 `groups=9` 仍不一致，也应进入 `applied`，除非本地有未上传改动。
- 返回 ALL Spaces，确认 Space 简介使用刷新后的 count。

注意：

- 当前 iPhoneOS build 已被既有 SDK/FireAlarm 编译错误挡住：缺 `EmergencyControllerMode`、`VendorFunctionSet.emergencyMode`、`EmergencyControllerResendParameters`。修复实现后仍需记录该阻塞，或先修 SDK 依赖后再完成 build 验证。

## 风险与回滚

风险：

- 如果服务端返回的数组本身是旧数据，客户端会在无本地未上传改动时信任服务端并覆盖本地。
- 如果某些合法场景只更新内容但 count 不变，本方案不会绕过 timestamp gate；这是为了避免用过宽规则覆盖本地数据。

回滚：

- 恢复 `SpaceData.update` 原来的 `lastUpdate > self.lastUpdate || initialize` gate。
- 删除新增 summary helper 和 DEBUG note。

## 最终建议

短期 App 侧采用方案 C，解决现有用户看到的 stale Site 简介和 Space 内部 stale 数据风险。

长期仍建议服务端修正 `updateTimestamp` 合同：只要 Space 内容数组发生变化，就必须递增对应 Space 的 `updateTimestamp`。
