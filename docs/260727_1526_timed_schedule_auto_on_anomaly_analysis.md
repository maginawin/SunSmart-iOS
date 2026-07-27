# Timed Schedule「Auto/On」未进入 AUTO 模式问题分析

## 1. 结论

本问题目前**不应判定为测试误报**。

更准确的缺陷状态应为：

> 用户可见预期成立、异常现象可信，但现有测试步骤和日志不足以确认唯一触发条件；应按“间歇性日程路由/存量数据一致性问题”继续调查。

主要依据：

1. Timed 页面明确向用户展示 `Auto/On`（中文为“自动/开”），当前代码也明确尝试让组内设备的 `turnOn` 日程走 Light LC 所在 Element 的 Scheduler Setup Model。因此，组日程到点进入 AUTO 是当前 App 的产品意图，不只是测试人员自行推断。
2. 标准 Bluetooth Mesh Scheduler 没有独立的 `AUTO` Action。App 中 `Auto/On` 最终编码仍是标准 `turnOn = 0x01`。
3. App 对 AUTO 与普通 ON 的区分，不在 Scheduler Action 字段或 payload 内，而在于同一条 `Scheduler Action Set` 被发送到设备的哪一个 Scheduler Setup Model / Element：
   - 普通 Scheduler Setup Model：通常表现为普通开灯；
   - Light LC 所在 Element 的 Scheduler Setup Model：利用该 Element 上 Generic OnOff 与 Light LC 状态绑定，进入 Light LC 自动控制流程。
4. 因此，固件只看到 `action = 0x01` 并判断“这是手动 ON”，不能单独证明 App 没有配置 AUTO。还必须核对消息目标 Element、对应 Scheduler Setup Server 实例以及该 Element 的模型组成。
5. “编辑并更新一次后恢复”与当前 App 的同步判定缺陷高度吻合：App 的常用缓存 `schedulerActions[id]` 只保存日程参数，没有保存这条参数来自哪个 Scheduler Model / Element；同步判断也只比较参数。于是“参数相同但写在普通 Scheduler 上”的异常数据，可能被误判为已同步。编辑时间、周期、Action 或渐变时间后，参数发生变化，App 才会重新下发，并可能在此时正确写到 Light LC Scheduler。

## 2. 当前 App 中 `Auto/On` 的真实含义

### 2.1 UI 只有一个复合选项

`ScheduleAddView` 对设备或组只提供：

- `Auto/On`
- `Off`

`Auto/On` 被选中后，`actionType` 返回：

`SchedulerAction.turnOn`

不存在 App 级别的独立 `auto` Scheduler Action 属性，也没有随 Schedule 持久化的 `isAuto`、`controlMode` 或类似字段。

相关位置：

- `SunSmart/Main/Timed/View/ScheduleAddView.swift:123-138`
- `SunSmart/Main/Timed/View/ScheduleAddView.swift:370-384`
- `SunSmart/zh-Hans.lproj/Localizable.strings:497-498`
- `SunSmart/en.lproj/Localizable.strings:489-490`

### 2.2 Schedule 持久化的 Action 只有标准 SIG 值

本地 SDK 定义：

| Action | 原始值 |
|---|---:|
| Turn Off | `0x00` |
| Turn On | `0x01` |
| Scene Recall | `0x02` |
| No Action / Inactive | `0x0F` |

相关位置：

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/SchedulerMessage.swift:250-256`
- `SunSmart/Main/Timed/Model/Scheduler.swift:190-202`

所以 App 本地 JSON、服务器数据和 SIG Scheduler payload 里都没有一个独立的 AUTO Action 值。

## 3. 标准 SIG Mesh 是否支持 Scheduler AUTO

答案是：

> 标准 Scheduler 不提供名为 AUTO 的 Action；它只定义 Turn Off、Turn On、Scene Recall 和 Inactive。

Bluetooth Mesh Model 1.1 规定，Action `0x01` 的行为等价于向 Scheduler Server 所覆盖的一段 Element 依次执行 `Generic OnOff Set Unacknowledged(OnOff = 1)`。

规范同时规定：

- Scheduler Server 是独立的 root/main model；
- Scheduler Setup Server 与对应 Scheduler Server 位于同一个 Element；
- 一个节点可以通过不同 Element 上的 Scheduler Server 实例控制不同的 Element 范围；
- Light LC Light OnOff 与同 Element 的 Generic OnOff 存在标准状态绑定。

因此，本项目通过“选择哪个 Scheduler Server 实例”实现 AUTO 语义，使用的仍是标准模型与标准 Action，但 AUTO 并不是 Schedule Register 中的独立字段。

官方规范：

- Bluetooth Mesh Model 1.1，Schedule Register Action：
  https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html
- Bluetooth Mesh Model 1.1，Scheduler Server：
  https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html
- Bluetooth Mesh Model 1.1，Light LC Light OnOff 与 Generic OnOff 绑定：
  https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html

## 4. App 如何区分 AUTO 与普通 ON

### 4.1 两个 Scheduler Model 查找入口

SDK 中：

- `node.schedulerSetupModel`：查找节点的普通 Scheduler Setup Server；
- `node.lightLCSchedulerSetupModel`：先定位 Light LC Server 所在 Element，再在这个 Element 中查找 Scheduler Setup Server。

相关位置：

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift:143-153`
- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift:493-510`

### 4.2 Timed 主同步路径的路由条件

`Schedule.getMessageHandles(node:delete:)` 的当前逻辑是：

1. 日程 Action 是 `.turnOn`；
2. `node.group != nil`；
3. 设备存在 `lightLCSchedulerSetupModel`；
4. 三个条件同时成立时，把 `SchedulerActionSet` 发给 Light LC Scheduler Setup Model；
5. 否则发给普通 `schedulerSetupModel`。

相关位置：

- `SunSmart/Common/Data/Node+MessageHandles.swift:421-462`

所以 `Auto/On` 实际是一个条件式语义：

| 运行时条件 | 实际路由 | 预期行为 |
|---|---|---|
| Turn On + 已识别为组成员 + 有 Light LC Scheduler | Light LC Element 的 Scheduler Setup | AUTO |
| 其他情况 | 普通 Scheduler Setup | 普通 ON |

Action、index、时间、周期等 payload 字段可以完全相同；关键差别是目标 Element / Model。

## 5. 为什么固件会看到“手动控制”

存在两种解释，必须通过目标地址和 Composition Data 区分。

### 解释 A：固件只按 Action 字段判断

如果固件工程师看到 `action = 0x01` 就称为“手动 ON”，这个结论不完整。

因为无论 App 想实现 AUTO 还是普通 ON，Schedule Register 的 Action 都是 `0x01`。还要确认：

- `Scheduler Action Set` 的 DST / Element Address；
- 该 Element 上是否同时存在 Scheduler Server、Scheduler Setup Server、Generic OnOff Server、Light LC Server；
- 到点时触发的是哪个 Scheduler Server 实例。

### 解释 B：消息确实发到了普通 Scheduler Element

如果串口日志已确认该条 Schedule 被写入普通 Scheduler Server，而不是 Light LC 所在 Element 的 Scheduler Server，那么固件表现为普通 ON 与当前标准行为一致，问题位于 App 路由、设备 Composition 兼容性或存量数据。

现有测试反馈没有提供这个关键证据，因此还不能在 App 与固件之间归责。

## 6. “编辑后恢复”的高概率原因

### 6.1 最高概率：同步状态丢失了 Scheduler Model / Element 维度

SDK 收到 `SchedulerActionStatus` 时，会把符合灯模型条件的结果写入：

`node.schedulerActions[index]`

这个字典的 Key 只有 schedule index，Value 只有 `SchedulerRegistryEntry`，不包含来源 Element 或 Model。

虽然 SDK 另有 `allSchedulerModelEntrys` 可以按 Model 保存日程，但 Timed 常用同步判断没有使用这个维度。

相关位置：

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift:114-131`
- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift:423-430`
- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift:867-881`

App 判断是否需要同步时只比较：

`node.schedulerActions[id] == schedule.schedulerEntry`

比较内容只有年、月、日、时、分、秒、星期、Action、Transition Time、Scene Number，同样不包含 Model / Element。

相关位置：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1564-1572`
- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshScheduleServer.swift:164-166`

由此可能出现：

1. 相同 index 和参数已存在于普通 Scheduler；
2. App 认为设备日程与本地定义一致；
3. 不再向 Light LC Scheduler 补发；
4. 到点只执行普通 ON；
5. 用户编辑了时间、周期、Action 或渐变时间；
6. 参数比较变为不一致；
7. App 重新生成消息；
8. 此时 `node.group` 和 `lightLCSchedulerSetupModel` 条件成立，消息改写到 Light LC Scheduler；
9. 新时间到达后表现为 AUTO。

该链路可以同时解释：

- 为什么不是每次都出现；
- 为什么表面 payload 的 Action 一直是 `0x01`；
- 为什么编辑一次会恢复；
- 为什么测试没有找到稳定业务逻辑。

### 6.2 次高概率：首次下发时 AUTO 路由条件暂时不成立

AUTO 路由依赖 `node.group != nil`。

`node.group` 不是 Schedule 自身记录的目标组，而是运行时扫描节点各 Model 的 subscription，返回找到的第一个普通组。若组订阅尚未完成、刚完成但本地状态尚未稳定、恢复/导入数据不完整，或者设备 Composition 缺少 Light LC Element 上的 Scheduler Setup Server，就会回退到普通 Scheduler。

相关位置：

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift:400-412`

测试步骤“设备加入组”没有说明：

- 是否等待整个组同步页成功结束；
- 是否存在失败后退出；
- 新建日程前是否重连或重启 App；
- 设备是否属于多个组；
- Composition 中是否确实有两个 Scheduler Server 实例。

因此，这些条件仍可能造成首次路由差异。

### 6.3 中等概率：旧版本、恢复或旁路同步曾写入普通 Scheduler

项目历史和当前代码中存在不止一个 Scheduler Action Set 生成入口，并非所有入口都显式执行 Light LC Scheduler 路由。

例如 `Group.getNodeSyncDataMessageHandles(node:)` 中存在直接使用普通 `node.schedulerSetupModel` 写入组绑定日程的逻辑：

- `SunSmart/Main/Group/Model/GroupServer.swift:399-415`

设备恢复路径中也存在直接写普通 Scheduler 的逻辑，但当前过滤的是直接设备目标：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2715-2725`

不能仅凭这些代码断定本次测试一定走过这些入口，但它们说明：

- 存量日程可能由旧版本或不同同步入口写在普通 Scheduler；
- 同一条业务 Schedule 的模型路由没有被集中成唯一规则；
- 编辑页当前路径可能把存量错误数据重新写到 Light LC Scheduler，从而表现为“编辑后修复”。

### 6.4 需要额外警惕：可能残留两个 Scheduler Server 上的重复 slot

如果异常数据原先在普通 Scheduler 的 index N，编辑后只在 Light LC Scheduler 写入 index N，并没有先清理普通 Scheduler 的 index N，那么同一设备上可能同时存在两条日程。

潜在结果：

- 原时间仍可能执行普通 ON；
- 新时间执行 AUTO；
- 两个实例在相同时间执行时，最终状态可能依赖固件执行顺序；
- 删除日程时如果只按当前 AUTO 路由清理 Light LC Scheduler，普通 Scheduler 的旧 entry 可能残留。

这与已有组日程孤儿分析中的 Model 路由风险一致：

- `docs/260603_1108_group_schedule_orphan_analysis.md:214-215`

因此，“编辑后当前看起来正常”不等于设备内错误数据已经被彻底修复。

## 7. 为什么暂时不能认定唯一根因

测试反馈缺少以下关键数据：

- 异常日程的 schedule index；
- 设备 Composition Data；
- 普通 Scheduler Setup 与 Light LC Scheduler Setup 各自的 Element Address；
- 初次保存时 `Scheduler Action Set` 的 DST；
- 编辑后再次保存时 `Scheduler Action Set` 的 DST；
- 初次保存后两个 Scheduler Server 实例分别保存的 index/entry；
- 编辑后两个实例分别保存的 index/entry；
- 新建日程前组同步是否完整成功；
- 编辑时具体修改了哪个字段；
- 是否存在 App 升级、项目导入、设备恢复或网关恢复；
- 设备是否加入多个组。

仅有“14:00、14:02、14:04 都异常”不能区分：

- 三条日程是否都被写入了同一个错误 Scheduler；
- 日程是否被复制；
- 是否存在重复 index；
- 是否是同一组同步状态下连续创建；
- 是否存在前一条日程对后一条状态的干扰。

## 8. 建议的证据采集

下一轮复测不要只观察灯是否亮，建议同时采集以下信息。

### 8.1 App 下发证据

每条 `Scheduler Action Set` 至少记录：

- node primary address；
- schedule index；
- Action；
- 完整 10-byte Schedule Register；
- 目标 Model ID；
- 目标 Element Address / 实际 DST；
- 路由判断时的 `node.group`；
- `lightLCSchedulerSetupModel` 是否存在；
- 当前操作来源：新建、编辑、组成员同步、恢复、Retry。

当前 DEBUG 日志已经打印 payload 和 Action，但没有打印目标 Model / Element，因此不足以区分 AUTO 与 ON：

- `SunSmart/Common/Data/Node+MessageHandles.swift:447-456`

### 8.2 设备读取证据

对同一个 index，分别向以下两个实例执行 Scheduler Action Get：

1. 普通 Scheduler Server；
2. Light LC 所在 Element 的 Scheduler Server。

在以下三个时点读取：

1. 首次保存完成后；
2. 异常执行后；
3. 编辑保存完成后。

如果首次保存后普通 Scheduler 有 entry、Light LC Scheduler 没有，而编辑后 Light LC Scheduler 出现 entry，即可直接证明模型路由/存量数据问题。

### 8.3 状态证据

到点后同时读取：

- Light LC Mode；
- Light LC Light OnOff / 可用的 LC 状态；
- Generic OnOff；
- Light Lightness；
- 固件内部触发该动作的 Scheduler Element。

仅观察“灯亮”无法证明 AUTO 状态。

## 9. 建议的最小复现矩阵

每个用例开始前，应分别清空普通 Scheduler 与 Light LC Scheduler 的相关 index，避免前一用例污染。

| 用例 | 前置条件 | 操作 |
|---|---|---|
| A | 新设备，完整加入邻近照明组并等待同步成功 | 新建 Group + Auto/On 日程 |
| B | 刚加入组，不重连、不退出同步页 | 立即新建日程 |
| C | 组已存在 Auto/On 日程 | 再向组加入新设备 |
| D | 异常日程已存在 | 不改任何 Schedule Register 字段，仅改名称并保存 |
| E | 异常日程已存在 | 修改分钟并保存 |
| F | 设备不在组 | Device + Auto/On |
| G | 设备在一个组 | Group + Auto/On |
| H | 设备存在多个组订阅 | 分别对不同组设置 Auto/On |
| I | 项目导入/设备恢复后 | 执行已有 Auto/On 日程 |

重点对比 D 与 E：

- 只改名称不会改变 Scheduler Register，理论上可能不会触发设备重写；
- 修改分钟会改变 Scheduler Register，更可能触发重新路由；
- 如果只有 E 能修复，将进一步支持“同步只比较 entry、未比较 model”的判断。

## 10. 后续修复方向

在取得双 Scheduler 实例读回证据前，不建议直接修改代码。

若证据确认上述高概率原因，建议后续方案包含：

1. 明确定义业务语义：`Auto` 与 `On` 不能只依赖一个模糊的 `Auto/On` UI 和运行时推断。
2. 集中所有 Schedule Model 路由，禁止新建、编辑、组成员同步、恢复、导入后的补同步各自选择 Model。
3. 同步判断使用 `allSchedulerModelEntrys` 或等价的 per-Model 状态，不再只使用扁平 `schedulerActions[id]`。
4. AUTO 日程迁移时先确认并清理普通 Scheduler 的同 index entry，再写入 Light LC Scheduler，避免双实例残留。
5. 对没有 Light LC Scheduler 的组设备给出明确兼容策略，不应静默降级后仍在 UI 显示 AUTO 语义。
6. 为路由选择、写入结果和双实例读回增加可复测日志或自动化契约。

## 11. 最终判定建议

建议测试系统中暂时标记为：

> **Valid / Need more diagnostic evidence**

不建议标记：

> **False positive**

原因是当前代码与 UI 都承诺组场景下的 AUTO 语义，而现有实现确实存在“相同 Action、不同 Scheduler Element”以及“同步状态未携带 Model 维度”的风险；“编辑后恢复”又与该风险具有明确因果一致性。
