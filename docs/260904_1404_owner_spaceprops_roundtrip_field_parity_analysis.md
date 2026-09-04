# Owner SpaceProps 往返字段一致性与同步状态分析

## 1. 结论

本次 `/sitespace/get/spaceprops` 原始响应把问题进一步收敛为两个已经有直接证据的缺陷，以及两个需要在服务端和设备数据库继续取证的风险点。

1. **服务端返回的是一份内部不一致的 Proximity Lighting 快照。**
   - Group 1 的 Profile、32 个 Path、32 个 Group Trigger Zone 都正确存在。
   - 7 个 Node 的 `proximityLightingEnabled`、Relay 和 Neighbor Addresses 也存在，而且每个节点的邻居正好是 Space Zone 1 中除自身之外的另外 6 个节点。
   - 但同一份响应完全没有 `proximityLightingSchemaVersion` 和 `triggerZones`。
   - 因此服务器保留了由 Space Trigger Zone 计算出的设备结果，却没有返回生成该结果的 Space 拓扑定义。

2. **Owner 本次进入 Space 时没有把服务器响应导入本地。**
   - 服务器和本地的 `updateTimestamp` 都是 `1788501097`。
   - App 只比较 Node、普通 Group、Scene、Schedule、Switch、EFC 的数量；这些数量相同，因此执行 `serverUpdateTimestampNotNewer` 并跳过整份服务器数据。
   - 所以当前服务器里的正确 Group 1 Path 或 Node Proximity 状态，都不会修复 Owner 本机上可能存在的旧缓存。

3. **Group 2、Group 3 仍显示需要同步，最确定的公共来源仍是 Scheduler 的 per-Model 状态缺失。**
   - 服务器有 Schedule 0、1，但它们都不以 Group 2、Group 3 的设备为目标。
   - 每个 Node 的 `schedules` 都是空数组，但 Cloud 数据没有表达每个 Scheduler Setup Model 的“已确认空”状态。
   - App 的 `needsDelete` 把 `allSchedulerModelEntrys[model] == nil` 当成需要删除，于是未同步过的 Group 2、Group 3 会继续显示红色，并生成 Schedule 0、1 的删除任务。

4. **如果同一份服务器响应被首次安装的 Editor 导入，还会再次制造 Proximity 差异。**
   - 缺少 schema 和 `triggerZones` 时，首次导入会把 Space Trigger Zone 初始化为空。
   - Group 2、Group 3 没有 Group Path，它们当前的 6 个邻居完全来自 Space Zone 1；Editor 丢失 Space Zone 后，目标邻居会变为空，而服务器 Node 缓存仍是 6 个邻居。
   - Editor 因此会把正确的设备状态判断成需要同步，并可能下发空邻居表。

这说明 Group 红色状态并不等同于 Mesh 设备配置错误；当前至少包含 Cloud 逻辑拓扑不完整、Owner 本地跳过导入和 Scheduler 未知状态误判三种来源。

## 2. 本次证据范围

输入文件：

- `/Users/maginawin/Downloads/temp/enter space log.txt`
- `/Users/maginawin/Downloads/temp/get spaceprops.txt`
- 前一轮 Owner / Editor 七份进入与同步日志
- 当前分支的 Space 导出、导入、Group `needSync`、Scheduler 和 Proximity 差量源码

限制：

- `enter space log.txt` 只有进入 Space 的网络和生命周期日志，没有打开 Group 2、Group 3 同步页面后的任务明细。
- 因此可以确定同步判断的代码入口和已知公共缺陷，但当前这一刻 Group 2、Group 3 的每一条具体任务，仍需增加同步差量诊断或再次进入同步页确认。
- 当前资料只能证明字段在完整 HTTP 往返后缺失，无法单独区分它是在 `/sync/siteprops`、`/sync/spaceprops` 的写入阶段丢失，还是在 `/get/spaceprops` 的返回 DTO 中被裁剪。

## 3. 实际配置与服务器响应逐项对账

### 3.1 Group 1 Profile

服务器返回：

- address：`C000`
- profile type：`7`
- profile id：`7095B005-7BFA-4E03-9A96-FD93944D5442`
- Proximity Relay：`2`

这次响应中的 Group 1 已经是正确的 Proximity Lighting Profile，不再是前一轮出现过的 `type = 1` 默认 Profile。

### 3.2 Group 1 Path

服务器返回 `proximityLightingPath.paths` 共 32 条：

- Path 1：`[140, 143, 153]`，对应 `008C、008F、0099`。
- Path 2：`[156, 0, 0]`，对应 `009C` 加两个空 Point。
- Path 3 至 Path 32：均为 `[0, 0, 0]`。

这与用户描述的实际配置完全一致。当前服务器快照没有丢失 Group 1 Path。

### 3.3 Group 1 Trigger Zone

服务器返回 `proximityLightingPath.zones` 共 32 条：

- Zone 1：`[140, 143, 153, 156]`，对应 Group 1 的 4 个节点。
- Zone 2 至 Zone 32：均为空数组。

这与实际配置完全一致。当前服务器快照没有丢失 Group 1 Trigger Zone。

### 3.4 Space Trigger Zone

实际配置是 25 个 Space Trigger Zone：

- Zone 1 包含全部 7 个节点：`008C、008F、0099、009C、009F、00A2、00A5`。
- Zone 2 至 Zone 25 为空。

但服务器 `data` 对象中：

- 没有 `triggerZones` 键；
- 没有 `proximityLightingSchemaVersion` 键。

这不是 `triggerZones: []`，而是字段整体缺失。缺失与显式空数组的业务含义完全不同：前者表示快照不完整或旧协议，后者才表示用户明确删除了所有 Space Trigger Zone。

### 3.5 Node Proximity 已观测状态

服务器返回的 7 个 Node 均为：

- `proximityLightingEnabled = true`
- Group 1、Group 3 节点 Relay 为 2；Group 2 节点 Relay 为 3
- 每个节点的 Neighbor Addresses 都是另外 6 个节点

逐组结果：

| Group | Node | Relay | Neighbor 数量 | 与 Space Zone 1 目标一致 |
| --- | --- | ---: | ---: | --- |
| Group 1 | `008C、008F、0099、009C` | 2 | 每台 6 个 | 是 |
| Group 2 | `009F` | 3 | 6 个 | 是 |
| Group 3 | `00A2、00A5` | 2 | 每台 6 个 | 是 |

这组数据证明服务器曾收到并保留 Space Zone 1 计算出来的设备结果。它同时证明当前 GET 响应中的 `triggerZones` 缺失不是因为用户没有配置 Space Zone。

### 3.6 Scheduler 数据

Space 中存在两个全局 Schedule 对象：

- Schedule 0：disabled，只绑定地址 `000B`，不属于当前 7 个灯节点。
- Schedule 1：enabled，但没有 Device、Group 或 Scene 目标。

所有 7 个 Node 的扁平 `schedules` 都是空数组。从业务目标看，Group 1、2、3 的灯节点不应因为这两个 Schedule 产生写入或删除任务。

### 3.7 Group 2、Group 3 Profile 与 Node 常用缓存

服务器响应中的常用差量字段与 Profile 目标一致：

- 两组 Node 的亮度范围均为约 1% 至 100%，与 Profile 的 `lowEndTrim = 1`、`highEndTrim = 100` 一致。
- Power-up State 均为 Restore。
- Light LC Mode、Occupancy Mode、Manual Override、Manual Control、Auto Adjust、三个阶段亮度和 T1 至 T5 与各自 Profile 一致。
- Group 2 的 `relativeSensitivity = 1` 对应 Node `motionSensitivity = 655`；Group 3 的 `relativeSensitivity = 95` 对应 `62258`。

所以当前服务器 JSON 中没有发现足以解释 Group 2、3 红色状态的普通 Profile 参数差异。Model Publication 等依赖 Element/Model 的判断仍需任务级诊断确认，但结合前一轮实际同步任务，Scheduler unknown 比 Profile 更符合当前现象。

## 4. 服务端字段不统一的直接证据

App 的 `SpaceData.export()` 每次都输出：

- `proximityLightingSchemaVersion = 1`
- `triggerZones`，包括空数组
- eligible Group 的 `profile.proximityLightingNumber`
- Group 的 `proximityLightingPath`
- Node 的 `proximityLightingEnabled`
- Node 的 `proximityLightingRelayCount`
- Node 的 `proximityLightingNeighborAddresses`

当前 GET 响应的处理结果却是：

| 字段 | App 上传契约 | 当前 GET | 判断 |
| --- | --- | --- | --- |
| `proximityLightingSchemaVersion` | 固定为 1 | 缺失 | 服务端往返不完整 |
| `triggerZones` | 25 条 | 缺失 | 服务端往返不完整，直接造成 Space Zone 丢失 |
| Group 1 `profile.type` | 7 | 7 | 保留 |
| Group 1 `proximityLightingNumber` | 2 | 2 | 保留 |
| Group 1 `proximityLightingPath.paths` | 32 条 | 32 条且内容正确 | 保留 |
| Group 1 `proximityLightingPath.zones` | 32 条 | 32 条且内容正确 | 保留 |
| Node Proximity 状态 | 7 台完整状态 | 7 台完整状态 | 保留 |

因此服务端不是把所有新字段一起拒绝，而是选择性保留了 Group/Node 层字段，丢掉 Space 顶层的 schema 和 Zone 字段。高度怀疑服务端不同 DTO、数据库实体或字段白名单没有使用同一套 SpaceProps 定义。

## 5. 三个服务端端点可能使用了不一致的映射

当前 App 会通过三条路径处理同一个 Space 对象：

1. 普通 Space 修改：`/sitespace/sync/spaceprops`，Space 位于请求的 `spaces[]`。
2. 分享、Site/地址级修改或 Site 尚未上传：`/sitespace/sync/siteprops`，Space 嵌套在 `site.spaces[]`。
3. 进入 Space：`/sitespace/get/spaceprops`。

前一轮日志中三条路径都真实出现过。App 端两种上传最终调用的是同一个 `SpaceData.export()`，所以字段源一致；服务端如果分别使用旧版 Site DTO、新版 Space DTO和第三套 GET DTO，就可能出现以下过程：

- `/sync/spaceprops` 暂时保存新字段；
- 随后 `/sync/siteprops` 用旧 DTO 全量覆盖同一 Space，删除它不认识的字段；
- 或数据库已经保存，但 `/get/spaceprops` 的响应 DTO 没有输出顶层新字段；
- Owner/Editor 在两种写入口间交替时，现象表现为有时存在、有时消失。

这是当前最需要服务器团队确认的属性不统一点。现有客户端日志还不能判定三个阶段中的具体丢失位置，必须查看服务端接收 DTO、持久化记录和返回 DTO。

## 6. Owner 本次为什么没有被服务器数据修正

日志显示：

- `initialize = false`
- `serverUpdateTimestamp = 1788501097`
- `localLastUpdate = 1788501097`
- 随后是 `serverUpdateTimestampNotNewer`

App 当前相同时间戳的摘要只比较：

- Node 数量
- 非虚拟 Group 数量
- Scene 数量
- Schedule 数量
- Switch 数量
- EFC 数量

它不比较：

- Profile type/id/参数
- Group Path 和 Group Trigger Zone
- Space Trigger Zone
- Node Proximity 状态
- Node per-Model Scheduler 状态

日志中 `serverArrayCounts groups=12` 而 `localCounts groups=3` 不是本次跳过的异常：服务器数组里包含 3 个普通 Group 和 9 个虚拟 Group，真正的摘要会过滤虚拟 Group，所以普通 Group 数量仍是 3。

真正的问题是：服务端可在保留原客户端时间戳的同时裁剪或改写字段，App 又把“时间戳相等、数量相同”当成内容相同。因此：

- 服务器有正确 Path，本地缺失时不会补回来；
- 服务器 Node Proximity 状态正确，本地旧状态不会更新；
- 本地有 25 个 Space Zone，服务器缺失时 Owner 暂时仍保留，但 Editor 首次导入会丢失；
- 下一次任一手机上传都会把自己的局部状态重新变成服务器全量真值。

## 7. Group 2、Group 3 仍显示需要同步的原因分层

### 7.1 已有直接证据：Scheduler unknown 被当成 delete

Group 的 `needSync` 只要任一 Node 的 Group 差量不为空就为 true。Group 差量包括 Profile、Scene、Scheduler、Switch、Proximity 和 EFC。

Scheduler 判断会遍历 Space 中全部 Schedule。对于不以当前 Node 为目标的 Schedule，只要 Node 任一 Scheduler Setup Model 在 `allSchedulerModelEntrys` 中没有记录，`needsDelete` 就直接返回 true。

Cloud 当前只导出/导入扁平 `node.schedules`，没有表达：

- 普通 Scheduler Model 是否已经读过；
- Light LC Scheduler Model 是否已经读过；
- 每个 Model 是已知空，还是尚未读取；
- 某个 Schedule id 实际属于哪个 Model。

前一轮日志已经记录：

- Group 2 的 `009F` 删除 Schedule 0、1；
- Group 3 的 `00A2、00A5` 删除 Schedule 0、1；
- Group 1 同步完成后，其节点本机 per-Model 缓存被更新，因此 Group 1 可暂时不再显示红色；未同步的 Group 2、3 继续为红色。

这与当前现象完全一致，是 Group 2、3 仍需要同步的最确定解释。

### 7.2 当前服务器 Proximity 状态本身与实际目标一致

如果以 Owner 的 25 个 Space Zone 为目标，服务器返回的 Group 2、3 Proximity Enabled、Relay 和 6 个邻居全部正确。因此不能仅根据当前 GET 文件认定 Group 2、3 的物理邻近照明配置错误。

### 7.3 服务器快照一旦被新 Editor 导入，会主动制造 Proximity 差异

首次导入缺少 schema 和 `triggerZones` 时，App 将 Space Zone 设为空。此时：

- Group 2、3 没有 Group Path 或 Group Zone；
- App 计算出的目标邻居为空；
- Cloud Node 已观测邻居仍是 6 个；
- 差量算法将生成空 Neighbor Set，或在某些状态下生成 Disable。

所以同一份服务器快照对 Owner 本机可能暂时看起来正常，对新 Editor 却必然不完整。

### 7.4 当前 Owner 的精确任务仍需补充诊断

本次进入日志没有打印 Group 2、3 当前的 `NodeSyncData` 分类，且服务器响应被时间戳规则跳过。若需要精确区分当前 Owner 红色状态中 Scheduler、Profile 和 Proximity 各占多少，应在只读诊断中打印：

- Node 地址和 Group；
- Profile 差量类型；
- Scheduler sync/delete id 与对应 Model；
- Proximity current/target/mutation；
- Scene、Switch、EFC 差量。

在没有这份分类前，不应把红色状态全部归因于 Proximity。

## 8. Path 和 Trigger Zone 消失的完整路径

### 8.1 Space Trigger Zone：当前已由服务器响应直接证实

当前 GET 不返回 `triggerZones`：

- 现有 Owner 更新导入时会保留本地旧值；
- 首次 Editor 导入时会得到空数组；
- Editor 上传全量 Space 后可能把空值扩散回服务器；
- Owner 再进入或上传时形成来回覆盖。

### 8.2 Group Path / Group Trigger Zone：当前服务器快照是正确的

当前 GET 中 Group 1 的 32 个 Path 和 32 个 Zone 均完整，因此它们本次不是在 GET 响应中丢失的。

它们仍可能在 App 中消失的原因有三类：

1. 相同时间戳直接跳过，使本地旧的空 Path 不会被服务器正确数据修复。
2. Profile SQLite 保存失败后，Group 重载为默认非 Proximity Profile；导出逻辑只为 eligible Profile 输出 `proximityLightingPath`，下一次上传会省略 Path。
3. 另一台手机曾在 Profile 或 Path 不完整时上传整份 Space，服务端采用最后写入覆盖，而没有字段级 merge/revision 冲突。

本次证据排除了“当前 GET 正在丢 Group 1 Path”，但没有排除上述客户端持久化和历史覆盖路径。

## 9. 其他已发现的协议问题

### 9.1 写成功不等于往返成功

Cloud 收到 HTTP 200 后立即把 `lastUploadCloudTimestamp` 更新为本地 `lastUpdate`，没有读取服务器规范化后的 Space，也没有比较内容摘要。服务器即使删除字段，App 仍会标记上传成功。

### 9.2 逻辑目标和设备已观测状态混在同一个全量快照

`triggerZones`、Group Path 是配置目标；Node Neighbor、Relay、Scheduler Entry 是设备已观测状态。两者生命周期不同：

- 配置目标应由用户编辑和 revision 冲突控制；
- 已观测状态应带来源设备、读取时间和可信度，不能由任意手机的旧缓存覆盖。

当前整份 Space 最后写入获胜，会让 Editor 的旧设备缓存覆盖 Owner 的新缓存，也会让缺失目标定义与仍存在的设备结果同时出现。

### 9.3 `versionSEQ` 不能承担 Space 冲突控制

服务器 Space 顶层返回 `versionSEQ = -1`，但 App 的 Space 导入决策只使用 `updateTimestamp`。Node 的 `versionSEQ` 也没有参与服务器与本地择新，因此当前没有可用的服务端权威 revision/CAS。

### 9.4 Group 2、3 缺少 `proximityLightingPath` 本身不是当前错误

用户尚未为 Group 2、3 配置 Group Path/Group Zone，字段缺失可以表示它们没有 Group 级拓扑。真正的问题是服务器同时丢失 Space 级拓扑，使它们失去了唯一的邻居来源。

## 10. 修复建议

### 10.1 服务端 P0：统一 SpaceProps 契约

1. `/sync/siteprops`、`/sync/spaceprops`、`/get/spaceprops` 必须共用同一个版本化 SpaceProps mapper。
2. schema 1 必须原样持久化并返回：
   - `proximityLightingSchemaVersion`
   - `triggerZones`
   - Group `profile.proximityLightingNumber`
   - Group `proximityLightingPath`
   - Node Proximity 已观测字段
3. schema 1 中缺少 `triggerZones` 必须拒绝写入，不能解释成空数组。
4. 旧客户端没有 schema 时，不得清除服务器已经存在的新字段；使用字段 merge 或显式 legacy mapper。
5. Owner 和 Editor 的配置数据必须一致；权限元数据可以不同，但不能按角色裁剪拓扑。
6. 增加服务端生成的 `revision`/ETag，并要求写入携带 `baseRevision`；冲突返回 409，而不是最后写入静默覆盖。
7. 写入成功响应返回 canonical revision 和内容 digest，或要求客户端立即 GET 校验。

### 10.2 App P0：不完整快照禁止写回

1. 首次或更新导入只要 Proximity Group 存在，但缺少 schema 1 必需字段，就标记 `incompleteCloudSnapshot`。
2. 不完整快照不得把字段解释为空，不得启动全量 Cloud 上传；界面只读并提示重新获取。
3. 相同时间戳不再只比较数量；至少比较版本化 canonical digest，最终改用服务端 revision。
4. Cloud 上传 HTTP 200 后做 read-after-write；字段、revision 或 digest 不一致时不清除 dirty。

### 10.3 Scheduler P0：unknown 不得直接 delete

1. `allSchedulerModelEntrys[model] == nil` 表示未知，不表示存在残留。
2. 未知状态先读取 Scheduler Register/Action；只有明确读到有效残留或服务器 tombstone 才允许删除。
3. Cloud 如需共享设备已观测状态，应保存逐 Element、逐 Model、逐 Slot 的状态、读取时间和来源；否则进入 Space 后必须重新读取，不能依赖扁平 `schedules` 推断。

### 10.4 App P1：本地持久化与导出失败关闭

继续执行前一轮计划：

- Profile 与 GroupInfo 原子保存；
- 兼容历史 `regulatorAccuracy` 非空列；
- 保存失败阻断 Mesh、Cloud 和页面成功状态；
- 导出发现 Profile 缺失或默认回退时拒绝上传，而不是生成新 UUID/默认 type；
- Server Import 先在 staging 中验证和落库成功，再替换现有 Network。

### 10.5 数据恢复顺序

1. 暂停 Editor 对当前 Space 的上传。
2. 备份 Owner 当前本地 Space、GroupInfo、Profile、Node 属性和原始导出 JSON。
3. 服务端修复三端点契约后，先用隔离测试 Space 验证往返。
4. 用 Owner 本地的 25 个 Space Trigger Zone 作为逻辑真值重新上传。
5. GET 校验 32 Path、32 Group Zone、25 Space Zone、schema 1 和 7 个 Node 状态均完整。
6. Editor 清理旧快照后首次导入，确认逻辑配置一致且不会自动上传。
7. 对 Scheduler 先读取再处理；不要继续直接删除未知槽位。

## 11. 服务端定向验收矩阵

在隔离 Space 上分别执行：

1. 通过 `/sync/spaceprops` 上传 schema 1 与非空 `triggerZones`，立即 GET，逐字段和数组顺序比对。
2. 通过 `/sync/siteprops` 的嵌套 Space 上传相同数据，立即 GET，逐字段比对。
3. 新客户端上传后再由旧客户端上传不含新字段的快照，确认新字段仍保留。
4. 分别以 Owner、Editor GET，同一 revision 下配置内容 digest 必须一致。
5. `triggerZones` 缺失、空数组、非空数组分别验证“保留、明确清空、替换”的契约。
6. 两台客户端基于同一 revision 并发写入，第二个写入必须冲突，不能静默覆盖。
7. 服务器写入前 DTO、数据库记录、GET DTO 三处都记录 schema、Zone 数量和 digest，以定位字段究竟在哪一层丢失。

## 12. 本轮状态

- 已完成 Owner 进入日志和完整 `/get/spaceprops` JSON 的结构化对账。
- 已确认当前服务器保留 Group 1 Path/Group Zone，却丢失 Space schema/Space Zone。
- 已确认 Node Proximity 结果与 7 节点 Space Zone 一致，服务器快照内部自相矛盾。
- 已确认 Owner 本次因相同时间戳跳过服务器导入。
- 已把 Group 2、3 红色状态收敛到 Scheduler unknown、Owner 本地旧缓存，以及新 Editor 丢失 Space Zone 后产生的 Proximity 差量。
- 未修改业务代码、SDK、资源、本地化、target 或依赖。
- 未执行构建或真机 Mesh 操作；本轮为日志、服务器 JSON 和源码分析。
