# 兴东 Space 云端与 App 导出数据分析

> 本文保留原始数据与初次分析结论。后续按用户要求，数量兼容规则已扩展为所有整数 `>20 → 255`，见 [规则更新](260915_1614_proximity_relay_all_normalization_update.md)。

## 结论

本次 `Proximity lighting data is invalid and was not imported.` 提示由 `Test1` 组（地址 `C00D`）的云端 Profile `proximityLightingNumber = 21` 触发。修复前只接受 `0...20` 或 `255`，因此导入首先被 Profile 完整性检查拒绝；拓扑检查也会拒绝同一个值。App 本地该字段为 `255`，15 台相关设备的缓存值也全部为 `255`。

路径、组触发区域、Space 触发区域与设备成员关系均未发现相关异常。`21` 可根据现有 UI 对 `ALL` 的转换约定兼容为 `255`，以消除此类误报；不能通过直接隐藏提示解决导入被阻断的问题。

## 数据来源与检查范围

- 云端响应：`/Users/maginawin/Downloads/tmp/xingdong_cloud.json`，实际 Space 位于 `data`。
- App 导出：`/Users/maginawin/Downloads/tmp/Space_兴东_20260915_155329_575+0800.json`，实际 Space 位于 `spaces[0]`。
- 检查两份 JSON 的非敏感配置、当前 Profile 校验、导入预检、拓扑归一化与数量滑条实现。
- 未修改原始 JSON；未在本分析中记录密钥、认证数据或用户信息。
- 本文属于静态数据分析。App 导出中的状态是导出时的持久化快照，不代表后续重新进入 Space 的运行结果；尚未进行真机验证。

## 量化对比

| 项目 | 云端 | App | 判断 |
| --- | --- | --- | --- |
| 设备数 | 500 | 500 | 地址集合相同 |
| 全部分组数 | 21 | 21 | 17 个实际组、4 个虚拟组 |
| 邻近照明分组 | `Test1 / C00D` | `Test1 / C00D` | 均为 Profile 类型 8 |
| 邻近照明数量 | **21** | **255** | 本次失败的直接触发值 |
| `proximityLightingSchemaVersion` | 1 | 1 | 相同 |
| Space `triggerZones` | 空数组 | 空数组 | 相同，属于明确合法空值 |
| Group `paths` | 1 条，15 个地址 | 1 条，15 个地址 | 内容完全相同 |
| Group `zones` | 1 个，2 个地址 | 1 个，2 个地址 | 内容完全相同 |
| 开启邻近照明的设备数 | 15 | 15 | 恰好为路径中的 15 个设备 |
| 开启设备的 relay 缓存 | 15 台均为 255 | 15 台均为 255 | 全部一致 |
| 节点分组状态/声明组/邻居缓存 | 500 条 | 500 条 | 对应字段全部一致 |
| 声明组与实际组订阅不符 | 0 | 0 | 无成员不一致 |

`C00D` 共声明 16 台设备，其中 15 台为正常成员；地址 `2E7F` 的设备处于 `exitFailure`（值 2），当前预检按既有语义排除此设备。它不出现在路径或区域中，不会造成路径成员清理。

路径首尾通过组内区域相连，形成 15 个设备的闭环。按路径相邻关系加区域关系重新计算，每个设备均有 2 个邻居，**15/15 与两份 JSON 中的邻居缓存相符**。把 Profile 数量统一为 `255` 后，提供的缓存没有显示需要执行邻近照明同步的差异。

其余 16 个实际组均为非邻近照明 Profile，不携带 `proximityLightingPath`，数量字段缺省并使用默认值 2，没有导致本次校验失败。除 `C00D.profile` 外，其余 20 个 Group 对象均完全相同。

## 修复前的首个失败点及提示来源

1. `SpaceConfigurationIntegrityPolicy.profileIssue` 对类型 7/8 的数量限定为 `0...20` 或 `255`，云端 `21` 返回 `invalidProfileRelay`。
2. `profilesIssue` 增加组地址，得到 `C00D:invalidProfileRelay`。
3. `ImportData.swift` 在处理拓扑导入策略前调用该检查，并将 Space 标记为 `invalidRemoteProfile:C00D:invalidProfileRelay`。存在可用本地快照时跳过导入并保留本地配置。
4. App 导出中的 `_debugInspection.spaces[0].status.blockedReason` **正好记录了 `invalidRemoteProfile:C00D:invalidProfileRelay`**；同时 `recoveryPhase = active`、`state = 1`、`pendingImport = false`，说明导出时并非单纯存在待下发的邻近照明参数差异。
5. 后续拓扑预检也会把 `21` 判为 `invalidRelayNumber`，因此修复不能只放宽第一个校验点。
6. 英文提示对应现有本地化 Key `proximity_lighting_import_invalid`。它描述的是配置未成功导入，不能据此推断设备当前邻近照明功能已经损坏。

关联实现：

- `SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift`
- `SunSmart/Common/Data/ImportData.swift`
- `SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift`
- `SunSmart/Main/Profile/View/ProfileProximityLightingNumberView.swift`
- `SunSmart/en.lproj/Localizable.strings`

## 为什么可以兼容 21

现有 `ProfileProximityLightingNumberView` 的正常范围是 `0...20`，滑条最大位置为 `21`。用户选择这个最大位置时，UI 显示 `ALL` 并向业务层回调 `UInt8.max`，即 `255`。

因此，`21` 与 `255` 存在明确的 UI 表示和业务存储对应关系。再结合 App 本地值和所有 15 台设备缓存均为 `255`，把云端 `21` 归一为 `255` 是有证据支持的兼容行为。**无法仅凭这两份 JSON 确定是哪一版本或哪一端把滑条值 21 写到了云端**，不应将来源推断写成事实。

建议在导入和参与配置比较的统一边界进行兼容，将合法语义值应用到后续 Profile、拓扑与持久化流程，保证再次校验和再次进入时不会回到相同阻断状态。对于没有明确对应关系的其他异常值，应独立判断，避免把任意错误数量都解释为 `ALL`。

## 仍然存在的实际配置差异

云端 `updateTimestamp = 1789443554`，App 为 `1789442241`，云端比本地新 1313 秒（21 分 53 秒）。云端 `C00D` 除数量外还包含以下有效业务差异：

| 字段 | 云端 | App |
| --- | --- | --- |
| Profile `timeT2` | 5 | 1200 |
| Profile `timeT4` | 0 | 600 |
| Profile `manualOverrideTimeout` | 5 | 600 |
| General Scene `timeT2` | 5 | 1200 |
| General Scene `timeT4` | 0 | 600 |

云端还附带部分 UI/冗余字段，如 Profile 的 `name`、`address` 以及昼夜条件中的展开场景内容。这些字段不应与邻近照明路径损坏混为一谈。

因此合理验收目标是：App 自动兼容已知可恢复值，不再因为 `21` 报邻近照明导入异常；正常导入后，如果上述实际 Profile 配置与设备不同，仍可按正常业务流程产生相应同步任务。不能承诺所有同步提示都消失。

## 建议验证

- 真实云端样本归一后通过 Profile 与拓扑校验，数量最终为 255。
- 归一化重复执行结果不变；`0...20` 和 `255` 保持原值。
- 云端与本地仅有 `21/255` 表示差异时，配置比较相等且不生成邻近照明任务。
- 完整样本保留合法的时间参数差异，不吞掉真实业务修改。
- 导出时已有的 `invalidRemoteProfile:C00D:invalidProfileRelay` 状态在成功恢复后清理，重复进入不会继续显示历史阻断提示。
- 真机重新进入兴东，检查提示、`Test1` 的 `ALL` 数量、15 节点路径及区域，并确认普通 Profile 同步提示是否符合实际差异。
