# SpaceProps `spaceData` 与 Scheduler unknown 删除保护修复

## 结论

本次按确认后的顺序完成两部分修改：

1. App 已适配服务端新的 SpaceProps 扩展属性容器。新上传数据把 `proximityLightingSchemaVersion` 与 Space 级 `triggerZones` 放入每个 Space 的 `spaceData`；站点全量同步与单 Space 同步共用同一份 Space 导出结果。
2. Scheduler 的 per-Model 状态缺失现在表示 unknown，不再直接生成删除任务。用户主动删除定时或编辑并移除旧目标时，如果相关设备状态仍为 unknown，App 会先完整读取 Scheduler Register/Action；读取失败则保留本地数据并停止删除。

## SpaceProps 契约调整

### 新格式

- `spaces[].spaceData.proximityLightingSchemaVersion = 1`
- `spaces[].spaceData.triggerZones = [...]`
- 新导出不再把这两个扩展属性重复写到 Space 根节点。
- `/sitespace/sync/spaceprops` 请求体补充根级 `spaceId`，同时保留 `siteId`、`userId` 与单元素 `spaces` 数组。

### 三个接口的统一行为

- `/sitespace/sync/siteprops`：`SiteData.export` 内部调用同一个 `SpaceData.export`，因此每个 `spaces[]` 都使用新 `spaceData` 容器。
- `/sitespace/sync/spaceprops`：使用相同的 Space 导出结构，并显式传递根级 `spaceId`。
- `/sitespace/get/spaceprops`：统一由 Space 导入预检读取 `spaceData`。

### 旧项目兼容

- 存在 `spaceData` 时，以该对象作为扩展属性的权威来源。
- 不存在 `spaceData` 时，回退读取旧格式 Space 根节点中的 `proximityLightingSchemaVersion` 与 `triggerZones`。
- 旧格式连这两个字段也不存在时，保持原兼容语义：首次导入初始化为空 Space Trigger Zones；覆盖已有 Space 时不凭空清空本地 Zones。
- 如果服务端声明了 `spaceData`，但其类型错误，或 schema v1 缺少/损坏 `triggerZones`，导入预检失败，不执行破坏性覆盖，避免把不完整快照再次上传为服务器事实。

Group Path 与 Group Trigger Zone 仍由 Group 数据承载；本次没有改变它们的层级。`spaceData` 当前只承载 Space 级可扩展属性。

## Scheduler P0 修复

### 状态语义

- `allSchedulerModelEntrys[model] == nil`：unknown，不能证明设备上存在该槽位。
- Model 字典已存在且槽位为空：known empty，不删除。
- Model 字典已存在且槽位有有效 Entry：known residual，且当前 Schedule 不再以该 Node 为目标时才允许生成删除任务。
- 当前 Schedule 仍以该 Node 为目标时不生成删除任务。

### 主动操作保护

- 主动删除定时前，先检查所有旧目标设备的每个 Scheduler Setup Model。
- 编辑定时并移除旧目标前，同样先完成 unknown 状态读取，再计算同步/删除差量。
- 权威读取使用完整 Scheduler Register/Action 读取，而不是在未知状态下直接发送 `noAction`。
- 读取失败或 Mesh 命令正忙时，不修改定时目标、不删除本地 Schedule，也不进入一个空的“删除同步”流程；用户可在设备在线且 Mesh 空闲时重试。

## 验证结果

### 聚焦测试

- Path topology persistence contracts：通过。
- Proximity Lighting topology/lifecycle/follow-up/integration/review regression：全部通过。
- Timed Scheduler owner/delete/read-before-delete contracts：通过。
- Scheduler Model cache persistence/read completion：通过。
- `git diff --check`：通过。

### iPhoneOS 构建

使用 Debug、generic iOS device、关闭签名直接构建：

- SunSmart：通过。
- Archipelago：通过。
- SLG Sync Plus：通过。
- SylSmart：通过。
- Lumineux：未进入本次 Swift 源码编译；其 CocoaPods target support 文件缺失，包括 `Pods-Common-Lumineux.debug.xcconfig` 和对应 xcfilelist。需要先恢复该 target 的 Pods 产物后复验。

## 修复后重新评估

本次已经封住两条已确认的公共根因：Space 级 Trigger Zone 未进入服务端新容器，以及 Scheduler unknown 被误判为删除。但以下结论仍需真实服务器与两台手机复验，不能由本地测试或构建代替：

1. Owner 上传后，服务端 `/get/spaceprops` 是否原样返回 `spaces[].spaceData`，包括空数组和全部非空 Space Trigger Zone 节点。
2. Editor 首次导入后，32 个 Group Path、32 个 Group Trigger Zone、25 个 Space Trigger Zone 的数量和已配置节点是否全部保持。
3. Editor 上传、Owner 再进入后，服务端是否仍保持相同结构，且不再发生 Owner/Editor 往返覆盖。
4. Group 2、3 是否不再因 Scheduler unknown 显示需要同步；若仍显示，需要重新采集具体 `NodeSyncData` 分类，再判断 Profile、Publication、Proximity 或其他设备状态是否还有独立差量。
5. 真实设备上普通 Scheduler 与 Light LC Scheduler 的完整读取、known residual 清理及失败重试是否符合预期。

本轮没有处理 Profile/GroupInfo 原子持久化、服务端 revision/并发覆盖、Scheduler per-Model Cloud 持久化等后续项；应先用新服务端契约完成上述 Owner/Editor 回归，再以新证据决定是否继续。
