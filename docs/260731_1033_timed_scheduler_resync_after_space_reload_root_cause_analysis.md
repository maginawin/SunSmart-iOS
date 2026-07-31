# Timed Scheduler 退出 Space 后重复提示同步：根因分析

## 1. 结论

本问题已经能够从日志、App 源码和本地 `NordicSigMeshSDK` 源码形成完整闭环。

核心结论如下：

1. Scheduler 第一次同步在 Mesh 层实际成功，不是设备没有保存，也不是 `TimeSet`、时区或网络失败。
2. 当前 App 在同步完成后，内存中的 per-Model Scheduler 缓存正确，所以同步标记会立即消失。
3. 退出 Space 再进入时，SDK 无法反序列化数据库中的 per-Model Scheduler 缓存，`allSchedulerModelEntrys` 重新变成空或未知。
4. 新的严格同步判定把“Owner Model 缓存不存在”或“非 Owner Model 状态未知”视为需要同步，所以标记重新出现。
5. 直接根因是 `ScheduleModelDataContainer.elementAddress` 的编码、解码格式不一致：
   - `Address` 实际是 `UInt16`；
   - 保存时编码为 JSON 数字，例如 `2479`；
   - 读取时强制按十六进制字符串，例如 `"09AF"` 解码；
   - 解码使用 `try?`，错误被静默吞掉。
6. 该编解码缺陷从 2025 年 4 月已经存在；2026 年 7 月 27 日的 Timed 多 Scheduler 修复将同步真值从扁平 `schedulerActions` 切换为 `allSchedulerModelEntrys`，因此把旧缺陷变成了当前可见的回归。
7. 这与 7 月 27 日的 Timed 修复直接相关，但不是 7 月 21 日/29 日的 `TimeSet`、时间或时区发送逻辑引起的。

## 2. 复现日志时间线

### 2.1 第一次进入 Space

`enter the space.txt` 显示：

- Space 云端数据请求成功；
- `serverUpdateTimestamp` 与 `localLastUpdate` 相同；
- App 明确记录 `note=serverUpdateTimestampNotNewer`，没有用更新的云端数据替换本地数据；
- Space 内有 13 个节点、16 个 Scene、16 个 Schedule。

因此后续退出再进入时，Scheduler 缓存恢复主要依赖本地 Mesh 数据库，不是服务器下发了不同的 Schedule 定义。

### 2.2 第一次进入 Timed

`enter the timed page.txt` 显示：

- App 本地共有 16 个 Schedule，id 为 0...15；
- 扁平兼容缓存 `schedulerActions` 严重不完整：
  - L2 只有 id 0...4；
  - 其余多数节点只有 id 15；
  - 很多 Schedule 在多数节点上显示 `missing`。

这些调试行只能说明扁平兼容缓存的内容，不能说明每个 Scheduler Model 的真实缓存状态。当前调试函数只打印 `node.schedulerActions`，没有打印实际用于 `needsSync` 的 `node.allSchedulerModelEntrys`。

### 2.3 第一次 SAVE Scheduler 0

`save sync the first scheduler.txt` 的统计结果：

| 项目 | 数量 |
| --- | ---: |
| 目标节点 | 13 |
| `TimeSet` 发送/`TimeStatus` 返回 | 13 / 13 |
| 非 Owner `SchedulerActionSet(noAction)` 发送/Status 返回 | 13 / 13 |
| Owner `SchedulerActionSet(sceneRecall)` 发送/Status 返回 | 13 / 13 |
| Scheduler 失败日志 | 0 |

Scheduler 0 的目标值始终一致：

- enabled：true；
- hour/minute：17:59；
- dayOfWeek：127；
- action：sceneRecall；
- sceneNumber：1。

每个节点都先成功清理非 Owner Model 的 id 0，再成功向 Owner Model 写入目标 entry。同步结束后 UI 标记消失，与 App 内存缓存更新成功一致。

日志末尾的 Space 上传也返回 HTTP 200 和业务 `success`。这只能证明云端上传接口成功，不能代替 per-Model 本地缓存持久化验证。

### 2.4 退出并再次进入 Space

`enter the space again.txt` 再次显示：

- Space 数据请求成功；
- 本地与服务端更新时间相同，仍然走本地数据；
- 没有 Scheduler Register/Action 的全量重新读取；
- 进入 Devices 后会向节点发送 `TimeSet`，`TimeStatus` 成功。

`TimeStatus` 本身不参与 Schedule 差异比较，但其回调会调用通用的 `savePropertys()`。如果 per-Model Scheduler 数据读取失败、内存字典为空，这次无关的时间属性保存还可能把数据库中的 `allSchedulerModelActions` 重写成空数组，进一步破坏可恢复性。

### 2.5 第二次进入 Timed

`enter the timed page again.txt` 显示：

- 仍有 16 个本地 Schedule；
- 每个节点的扁平 `schedulerActions` 现在只剩 id 0；
- id 1...15 在所有节点上基本都变为 `missing`。

这正是同步 Scheduler 0 后的 per-Model 内存数据被投影到扁平缓存、再保存到旧 `schedulesData` 的结果。因为重新加载时 per-Model 缓存解码失败，真正用于同步判定的数据仍然未知，所以 Scheduler 0 虽然出现在扁平缓存中，标记仍会再次出现。

### 2.6 第二次 SAVE 同一个 Scheduler

`sync the first scheduler again.txt` 与第一次 SAVE 的行为相同：

- 同样选择 13 个节点；
- 同样发送并收到 13 个 `TimeSet/TimeStatus`；
- 同样成功清理 13 个非 Owner entry；
- 同样成功写入 13 个 Owner sceneRecall entry；
- 没有 Scheduler 失败日志。

这证明问题不是偶发的 Mesh 超时，而是每次 Space 重载都会重新丢失 App 的 per-Model 持久化真值，导致完全相同的同步被重复执行。

## 3. 源码根因

### 3.1 UI 标记直接来自严格同步判定

`SchedulesViewCell` 通过 `schedule.getNeedSyncDatas().isEmpty()` 决定是否显示同步图标。

`Schedule.needsSync` 当前要求：

1. Owner Scheduler Model 中必须存在当前 id；
2. Owner entry 必须与 App 的 `schedulerEntry` 相等；
3. 每一个非 Owner Scheduler Model 的缓存必须存在；
4. 非 Owner 的同 id 不能是有效 entry。

只要 `allSchedulerModelEntrys` 没有恢复，Owner 或 cleanup Model 就会被判定为未知，直接返回需要同步。

相关位置：

- `SunSmart/Main/Timed/View/SchedulesViewCell.swift:74`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1564`

### 3.2 同步完成时内存缓存确实会更新

Schedule 写入固定执行：

1. 可用时发送 `TimeSet`；
2. 清理全部非 Owner Scheduler Models 的同 index；
3. 向 Owner Scheduler Model 写入目标 entry。

成功回调会把 `messageHandle.model` 一起传给 `node.updateData`。`updateData` 按具体 Model 更新 `allSchedulerModelEntrys`，重建扁平 `schedulerActions`，并调用 `savePropertys()`。

这解释了为什么当前页面内图标可以消失。

相关位置：

- `SunSmart/Common/Data/Node+MessageHandles.swift:448`
- `SunSmart/Main/Timed/Model/ScheduleServer.swift:184`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:3139`

### 3.3 数据库确实尝试保存和恢复 per-Model 数据

SDK 将每个 Scheduler Setup Model 保存为一个 `ScheduleModelDataContainer`：

- Element Address；
- 该 Model 下按 10 字节编码的 Scheduler entries。

保存字段为 `allSchedulerModelActions`，加载时会按 Element Address 找回对应的 Scheduler Setup Model，再恢复 `allSchedulerModelEntrys`。

相关位置：

- `NordicSigMeshSDK/MeshDatabase.swift:949`
- `NordicSigMeshSDK/MeshDatabase.swift:1208`
- `NordicSigMeshSDK/MeshDatabase.swift:1295`

### 3.4 `elementAddress` 编解码格式不对称

SDK 定义：

- `Address` 是 `UInt16`；
- `ScheduleModelDataContainer.encode` 直接编码 `elementAddress`，所以 JSON 是数字；
- `ScheduleModelDataContainer.init(from:)` 却调用 `decode(String.self)`，只接受字符串；
- 外层加载调用 `try? jsonDecoder.decode(...)`，解码错误不会输出。

使用与当前实现相同的最小验证得到：

- 编码结果：`{"elementAddress":2479}`；
- 解码结果：期望 String、实际 Number，`typeMismatch`。

因此，只要 `allSchedulerModelActions` 中存在一个容器，整个容器数组都无法恢复，`allSchedulerModelEntrys` 保持为空。

相关位置：

- `NordicSigMeshSDK/Address.swift:41`
- `NordicSigMeshSDK/Node+Propertys.swift:1186`
- `NordicSigMeshSDK/Node+Propertys.swift:1204`
- `NordicSigMeshSDK/Node+Propertys.swift:1221`
- `NordicSigMeshSDK/MeshDatabase.swift:950`

### 3.5 为什么旧扁平缓存还在，但图标仍然出现

数据库还会单独保存 `schedulerActions` 到旧字段 `schedulesData`。这个字段不包含 Scheduler Model/Element 归属，但能够正常反序列化。

Timed 调试日志也只打印这个扁平缓存，所以日志会出现：

- Scheduler 0 看似已经存在；
- UI 却仍然提示同步。

这不是 UI 与日志互相矛盾，而是它们观察了两个不同层级：

| 数据 | 用途 | 重载结果 |
| --- | --- | --- |
| `schedulerActions` | 旧兼容投影、当前 Debug 输出 | 可以恢复 |
| `allSchedulerModelEntrys` | Owner/非 Owner 真值、`needsSync` | 因解码失败无法恢复 |

## 4. 与 7 月 27 日 Timed 修复的关系

### 4.1 直接相关的部分

App 提交 `2891ec03` 和本地 SDK 提交 `7fde212` 在 2026 年 7 月 27 日完成了以下调整：

- Auto/On、Off、Scene Recall 按业务规则选择唯一 Owner Scheduler；
- 写入前清理非 Owner 同 index；
- 删除时清理全部 Scheduler Models；
- 同步判断由扁平 `schedulerActions` 改为严格依赖 `allSchedulerModelEntrys`；
- 多 Scheduler 状态按来源 Model 保存。

这套方向用于防止普通 Scheduler 与 Light LC Scheduler 同 index 重复执行，本身有必要保留。

但是实施时没有覆盖 `allSchedulerModelActions` 的数据库编解码 round-trip，也没有覆盖“同步成功 → 退出 Space → 重新加载 → 仍为已同步”。因此，2025 年已经存在的序列化缺陷被新逻辑放大成了当前回归。

准确归因应是：

> 7 月 27 日修复改变了同步真值依赖，直接触发了回归；底层持久化编解码缺陷更早已经存在。

### 4.2 与 TimeSet 修复无关

本次日志中 26 次同步过程里的 `TimeSet/TimeStatus` 都成功。Schedule 的同步判断只比较 Scheduler Model entries，不比较 timezone 或 timestamp。

因此：

- TimeSet 不是标记出现的原因；
- 时区不是标记出现的原因；
- TimeStatus 的通用 `savePropertys()` 只可能在 per-Model 解码失败后扩大数据覆盖问题，不是最初根因。

### 4.3 日志中的 AppKey warning 不是本次根因

日志反复出现本地 0x002A Element 的 Scheduler Server/Setup Server 未绑定 AppKey 警告，但远端设备的 `SchedulerActionStatus` 均已成功返回，并被命令流程识别为成功。

这些 warning 属于本地接收侧 Model 分发噪声，不能解释“当前页面成功、重载后失败”的持久化边界现象。

## 5. 影响范围

### 5.1 Target

Devices、Groups、Scenes 最终都会分解为具体 Node，并调用同一个 `needsSync` 和 per-Model 缓存，因此三类 Target 都会受影响。

### 5.2 Action

- Auto/On 在自动 Profile Group 中通常使用 Light LC Scheduler；
- Off 使用普通 Scheduler；
- Scene Recall 使用普通 Scheduler。

三类 Action 最终都依赖 `allSchedulerModelEntrys`，所以都会受影响。当前 Scheduler 0 是 Scene Recall，已经证明问题并不限于 Auto/On 或 Light LC。

### 5.3 Profile

当前测试的：

- proximity/predictive lighting with photocell；
- daylight harvesting (closed loop)；

都属于非 Manual Control 的自动 Profile，Auto/On 会走 Light LC Owner，但持久化问题不属于 Profile 参数问题。

其他 Profile 即使 Owner 规则不同，只要节点拥有 Scheduler Setup Model 并经历 Space 重载，同样可能受影响。尚未测试的 Profile 需要纳入回归矩阵，但不影响当前根因结论。

### 5.4 16 个 Scene 和 16 个 Schedule

当前日志显示合法的 16 个逻辑 Schedule id 0...15，没有证据表明本问题由容量溢出、Scene/Schedule 同为 16 或第 17 个 index 引起。

7 月 27 日修复处理的是“双 Scheduler 上同 index 重复导致物理事件超过 16”的另一类问题。本次问题发生在 App 本地真值恢复阶段，不能通过减少 Scene 或 Schedule 数量解决。

## 6. 修复方案

### 方案 A：修复编解码并增加一次性权威读取迁移（推荐）

这是能同时解决重复提示和旧数据可信度的完整方案。

#### A1. 修复 SDK 编解码

1. `elementAddress` 读取同时兼容：
   - 既有 JSON 数字；
   - 十六进制字符串。
2. 后续保存统一使用一种规范格式，建议使用项目现有 Mesh JSON 常用的四位十六进制字符串。
3. 不再用无日志的 `try?` 吞掉整个容器数组错误。
4. 区分“字段不存在”“字段为空”“字段损坏”三种状态。
5. 解码失败时避免由无关的 `TimeStatus` 或其他属性保存立即把原始 Scheduler blob 覆盖为 `[]`。

#### A2. 补齐持久化验证

至少建立以下 RED → GREEN 用例：

1. 数字地址旧数据可以读取；
2. 字符串地址新数据可以读取；
3. 双 Scheduler：Owner 有目标 entry，非 Owner 是已知空字典；
4. 保存并重新加载 Node 后，两个 Model 的状态保持；
5. 保存后 `needsSync == false`；
6. 退出/重载等价的数据库 round-trip 后仍为 false；
7. 损坏数据有明确诊断，且不会被无关属性保存静默覆盖。

#### A3. 一次性迁移旧状态

仅修 codec 后，尚未被覆盖的数字格式数据可以直接恢复；已经被旧版本重写为 `[]` 的节点仍然缺少可信 per-Model 状态。

推荐对“per-Model 状态未知”的节点执行一次性权威读取：

1. 分别读取每个 Scheduler Model 的 Register；
2. 只读取 Register 中有效 id 的 Action；
3. 按来源 Model 保存；
4. 完成全部 Model 后再计算 `needsSync`；
5. 只对真实 Owner 错误、entry 不一致或非 Owner 残留显示同步。

该读取应是一次性迁移或明确的修复流程，不建议每次进入 Timed 都全量执行。

#### A4. 改进诊断

Timed Debug 应增加：

- Node；
- Scheduler Model Element Address；
- Model 是 Owner、cleanup 还是 unknown；
- 每个 Model 的 id 列表；
- `needsSync` 的具体 reason；
- 本地 Scheduler blob 解码状态。

不应继续只打印扁平 `schedulerActions` 并把它称为设备侧完整 Schedule 真值。

#### 优点

- 修复根因；
- 保留 7 月 27 日防重复事件的严格语义；
- 可恢复数字格式旧缓存；
- 对已丢失数据通过设备读取恢复真值；
- 不需要盲目重写全部 Schedule。

#### 代价

- 需要 App 与本地 SDK 联合修改；
- 一次性读取会产生额外 Mesh 请求，需要串行、超时和中断恢复设计；
- 必须进行真机多 Model 回归。

### 方案 B：只修 SDK 编解码，已有未知数据由用户逐条同步

做法：

1. 修复数字/字符串兼容解码；
2. 增加 round-trip 测试；
3. 不做设备真值迁移；
4. 对已经丢失的 per-Model 数据继续显示需要同步，用户逐条 SAVE 后建立新缓存。

优点：

- 改动最小；
- 可以立即终止“同步后重进又脏”的循环；
- 实施风险较低。

缺点：

- 当前 16 个 Schedule 仍可能需要逐条同步一次；
- 其他 Space/用户升级后也可能看到大面积一次性待同步；
- 无法区分设备实际不一致与单纯本地未知；
- 用户体验较差。

该方案可作为紧急止血版本，但不应作为完整最终方案。

### 方案 C：未知 Model 缓存按“已同步”处理

做法：

- Owner 或非 Owner per-Model 缓存缺失时，回退使用扁平 `schedulerActions`；
- 如果扁平 entry 等于 App entry，就隐藏同步图标。

优点：

- UI 立即不再大面积显示同步；
- 网络开销最小。

缺点：

- 会重新隐藏普通 Scheduler 与 Light LC Scheduler 的重复 entry；
- 无法证明非 Owner 已清理；
- 破坏 7 月 27 日单 Owner 修复的核心安全条件；
- 可能恢复“16 个逻辑 Schedule、设备执行超过 16 个物理事件”的问题。

不推荐采用。

## 7. 推荐实施边界

推荐采用方案 A，并拆成两个可独立验收的阶段：

1. 第一阶段：修复 SDK codec、错误可见性、非破坏性保存和 round-trip 测试，先保证新同步状态能够跨 Space/进程重载稳定保存。
2. 第二阶段：为状态未知的节点增加一次性 Scheduler Model 权威读取，避免要求用户盲目重同步 16 条 Schedule。

不建议同时调整 Owner 路由规则、Profile 规则、TimeSet 或 UI 文案。这些都不是本次根因，混入会扩大验证范围。

## 8. 验收矩阵

### 8.1 必须通过的生命周期

每个用例都至少验证：

1. 进入 Timed；
2. 同步或读取完成；
3. 当前页面标记消失；
4. 退出 Timed 再进入；
5. 退出 Space 再进入；
6. App 杀进程后重启；
7. 标记仍不重新出现；
8. 再次 SAVE 不应产生 Scheduler Mesh 消息。

### 8.2 Target 与 Action

| Target | Auto/On | Off | Scene Recall |
| --- | --- | --- | --- |
| Device | 必测 | 必测 | 若 UI 允许则测 |
| Group | 必测 | 必测 | 按产品路径测 |
| Scene | 按产品路径测 | 按产品路径测 | 必测 |

### 8.3 Profile/Composition

至少覆盖：

1. proximity/predictive lighting with photocell；
2. daylight harvesting (closed loop)；
3. Manual control；
4. 未加入 Group 的设备；
5. 双 Scheduler 设备；
6. 只有一个 Scheduler 的旧设备；
7. Profile 从 Manual Control 切换到自动 Profile；
8. 自动 Profile 切换回 Manual Control。

### 8.4 容量与异常

1. 16 个 Schedule 全部读取和持久化；
2. 普通/Light LC 同 index 存在历史重复；
3. 非 Owner 清理失败；
4. 读取中断后重新进入；
5. 一台设备离线；
6. 数据库存在数字地址旧格式；
7. 数据库存在字符串地址新格式；
8. Scheduler blob 损坏；
9. 与 Scene 16 个的组合保持正常。

### 8.5 静态与构建验证

修改 SDK 后需要检查所有引用 `NordicSigMeshSDK` 的品牌 target：

- SunSmart；
- Archipelago；
- SLG Sync Plus；
- SylSmart。

按项目约束使用 generic iPhoneOS 构建，不使用 Simulator。静态测试和构建成功不能代替上述真机 Mesh 与重载验收。

## 9. 是否还需要更多信息

### 根因判断

不需要再提供信息。现有六份日志和源码已经足以确认根因、历史关联和影响链路。

### 实施前需要确认的产品选择

需要确认一个策略选择：

- 采用推荐方案 A，App 对未知旧缓存执行一次性设备权威读取；
- 或采用方案 B，只修持久化，允许已有 Schedule 由用户逐条同步一次。

### 修复后的真机验收信息

实现后仍需要新日志验证：

1. 同一 Scheduler 同步后退出 Space 再进入；
2. 杀进程重启；
3. 一个自动 Profile 的 Auto/On；
4. 一个 Off；
5. 一个 Scene Recall；
6. 至少一台单 Scheduler 设备。

这些是修复验收信息，不是继续判断当前根因所必需的信息。

## 10. 当前工作区说明

- 本轮只完成分析，没有修改 App 或 SDK 业务代码。
- 当前 App 分支为 `fix`，比 `origin/fix` ahead 1；工作区原本没有未提交差异。
- App 当前引用本地 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- 本地 SDK 分支为 `dev`，工作区无未提交差异。
