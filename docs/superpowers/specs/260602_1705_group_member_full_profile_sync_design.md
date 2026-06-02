# Group Member Full Profile Sync Design

## 背景

当前 group profile 同步逻辑以差量为主：`Node.getNodeSyncProfiles(...)` 会根据节点当前缓存状态与 group profile 目标值比较，只生成需要变化的 profile 配置命令。

近期已为“group profile type 切换”新增 `GroupProfileSyncContext` 与 `forceFullProfileSync` 链路，使 type 从 A 切换到 B 时可以对既有 group members 下发 Profile B 的全量核心配置。

本次新增预期：在 group 的 members 中添加新 light 成员时，也必须对新成员下发全量 profile 属性。否则新增设备可能因为缓存状态不完整、设备回包状态不可信或旧配置残留，导致进入 group 后实际行为不正常。

## 目标

- 只覆盖 `GroupMembersViewController` 中手动把 light 添加到已有 group 的 `inNodes` 流程。
- 对新增成员生成全量 profile 核心配置命令。
- 复用现有 `GroupProfileSyncContext` / `forceFullProfileSync` 机制，避免复制 profile 命令生成逻辑。
- 保持删除成员、普通 group sync/resync、scene、schedule、switch、proximity path 等同步域现有行为不变。

## 非目标

- 不改变 `outNodes` 退组逻辑。
- 不把普通 group `Sync` / `Re-Sync` 改成全量 profile 下发。
- 不新增 profile 外的全量同步，例如 scene、schedule、switch、proximity path。
- 不调整同步 UI、失败展示、重试流程或成功回调。
- 不新增 Auth 信息。

## 当前代码路径

成员保存入口：

- `GroupMembersViewController.saveAction()`
- 计算 `addNodes = selectNodes.filter { !group.nodes.contains($0) }`
- 创建 `SyncDevicesViewController(type: .group(group, inNodes: addNodes, outNodes: exitNodes))`

同步数据源入口：

- `SyncDevicesViewController.setupDataSource()`
- `.group(let group, let inNodes, let outNodes)` 分支计算 `remainingNodes`、`addedNodes`、`effectiveMemberCount`
- 当前 `inNodes` 调用 `getSyncDeviceModel(...)` 时没有传 `profileSyncContext`
- 只有 `inNodes == nil && outNodes == nil` 的普通 profile 保存路径会传入 `groupProfileSyncContext`

profile 命令生成入口：

- `Node.getSyncData(type:profileSyncContext:)`
- `Node.getNodeSyncProfiles(group:effectiveMemberCount:profileSyncContext:)`
- `forceFullProfileSync = profileSyncContext?.shouldForceFullProfileSync == true`
- `getNodeLightDataSyncProfiles(... forceFullProfileSync:)` 中已把核心 profile 属性判断改为 `forceFullProfileSync || diff`

## 设计方案

采用方案 A：复用并扩展 `GroupProfileSyncContext`。

`GroupProfileSyncContext` 从“仅表示 profile type 切换”扩展为“group profile 同步上下文”。它应能表达强制全量同步原因，例如：

- profile type changed
- member added

现有 profile type 切换路径继续创建该 context。新增成员路径为每个 `inNodes` 设备传入“member added”上下文，使 `shouldForceFullProfileSync` 为 `true`。

### 数据流

1. `GroupMembersViewController` 保持现有保存流程，继续把新增成员作为 `inNodes` 传入 `SyncDevicesViewController`。
2. `SyncDevicesViewController.setupDataSource()` 在 `.group` 分支内保留现有 `effectiveMemberCount` 计算。
3. 遍历 `inNodes` 时，调用 `getSyncDeviceModel(group:node:effectiveMemberCount:profileSyncContext:)` 并传入 member-added 强制全量 context。
4. `outNodes` 遍历不传该 context。
5. 既有 group nodes 遍历继续只在 `inNodes == nil && outNodes == nil` 时使用 `groupProfileSyncContext`，保持 profile 保存路径语义。
6. `Node.getNodeSyncProfiles(...)` 读取 context 后让 `forceFullProfileSync == true`。
7. 现有 profile 命令生成逻辑负责输出全量核心 profile 配置。

## 全量 Profile 范围

新增成员全量 profile 范围复用现有 `forceFullProfileSync` 已覆盖的核心配置：

- Light LC mode
- occupancy mode
- high / low end trim
- occupancy / vacant / standby level
- occupancy / vacant / standby lux
- T1-T5 时间参数
- manual override timeout
- manual control
- light auto adjust
- adjust speed
- day / night lux trigger condition
- power up state / power up CCT
- motion sensitivity
- light LC scene switch / store / delete 相关现有逻辑

不纳入本次 profile 全量范围：

- group subscription 以外的 group membership 行为调整
- scene 全量同步
- schedule 全量同步
- switch 全量同步
- proximity path 全量同步
- emergency fire controller group mutation items

这些仍由现有独立同步逻辑判断是否需要生成任务。

## 错误处理

不新增特殊错误处理。新增成员的全量 profile 配置仍通过现有 `SyncDevicesViewController` 展示同步步骤、记录失败状态、支持用户在同步页面重试。

如果新增成员同时需要订阅 group、profile、scene、schedule 或其他配置，仍按现有同步数据排序和分组规则执行。全量 profile 只增加 profile 配置步骤数量，不改变 UI 流程。

## 测试与验证

静态核查：

- `inNodes` 调用会传入强制全量 profile context。
- `outNodes` 调用不传强制全量 profile context。
- 普通 group sync/resync 不因本改动变成全量 profile。
- profile type 切换保存路径仍能触发全量 profile。

代码路径核查：

- 新增成员路径中 `forceFullProfileSync` 能进入 `getNodeSyncProfiles(...)`。
- `getNodeLightDataSyncProfiles(...)` 的既有 `forceFullProfileSync || diff` 条件继续覆盖核心 profile 属性。

构建验证：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

验证时不使用 Simulator，不使用 shell 包装或日志重定向。

## 风险与约束

- 新增成员同步命令数量会增加，配置耗时可能变长，但这是满足设备可靠性的预期代价。
- 全量范围依赖现有 `forceFullProfileSync` 覆盖面；若未来新增 profile 属性，应同步纳入该机制。
- 如果某些设备缺少对应 model 或 capability，现有命令生成逻辑仍会跳过相关命令。本设计不改变设备能力判断。
- 本改动不修复 profile 外同步域可能存在的差量判断问题。

## 验收标准

- 从 group members 添加新 light 时，新成员会走强制全量 profile 配置。
- 删除成员不触发全量 profile 配置。
- 普通 group sync/resync 不触发新增成员专用全量 profile 配置。
- profile type 切换全量同步行为保持可用。
- `SunSmart` iPhoneOS Debug 构建通过。
