# EFC Comprehensive Status Mode 解析设计

## 背景

EFC 设备页进入后会通过 vendor model GET `0x4D 0x04` 获取设备当前状态。当前 SDK 将响应中的 `enable_mode` 解析成布尔 `enabled`，App 设备页再直接按 `fire_active` 优先、`em_active` 次之来显示状态。

这个逻辑没有保留 `enable_mode` 的位图语义。当设备返回“只启用应急”时，如果 `fire_active = 1`，页面仍可能误显示 Fire Alarm。正确行为应该先看设备真实返回的 `enable_mode`，再决定哪些 active 字段有效。

## 协议字段

响应格式：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| ret | u8 | `0` 表示成功 |
| enable_mode | u8 | 位图，同 `0x4D/0x05`：`0` 都关，`1` 只应急，`2` 只火警，`3` 都开 |
| fire_active | u8 | 当前是否火警报警，`0/1` |
| em_active | u8 | 当前是否应急触发，合并应急 ADC 与掉电，`0/1` |
| ever_em | u8 | 调试字段，App UI 忽略 |
| ever_fire | u8 | 调试字段，App UI 忽略 |

示例 `0x4D04000101010100`：

- `ret = 0x00`：成功
- `enable_mode = 0x01`：只启用应急
- `fire_active = 0x01`：火警触发，但火警未启用，UI 忽略
- `em_active = 0x01`：应急触发，UI 显示 Power Loss
- `ever_em / ever_fire`：调试字段，UI 忽略

## 目标

- SDK 保留设备真实返回的 `enable_mode`，不再只暴露布尔 `enabled`。
- App 设备页根据 `enable_mode` 选择有效 active 字段。
- 无效 `enable_mode` 静默显示 Normal State，不作为解析失败处理。
- `ever_em` 与 `ever_fire` 只作为协议字段保留，不参与当前 UI 状态判断。

## 状态判定规则

| enable_mode | 有效字段 | UI 状态 |
| --- | --- | --- |
| `0` | 不解析后续 active 字段 | Normal State |
| `1` | 只看 `em_active` | `1` 显示 Power Loss，`0` 显示 Normal State |
| `2` | 只看 `fire_active` | `1` 显示 Fire Alarm，`0` 显示 Normal State |
| `3` | 同时看 `fire_active` 与 `em_active` | Fire Alarm 优先；无火警且应急触发时显示 Power Loss；都未触发时显示 Normal State |
| 其他 | 不解析后续 active 字段 | Normal State |

## 推荐方案

采用 SDK 协议模型修正 + App 显示映射收口。

1. SDK `EmergencyFireComprehensiveStatus` 保留真实 `enable_mode`，优先表达为 `EmergencyFireWorkingMode?` 或等价字段。
2. SDK 继续解析 `fire_active`、`em_active`、`ever_em`、`ever_fire`，但 App UI 只使用 `enable_mode`、`fire_active`、`em_active`。
3. App 的 `EmerFireAlarmMonitorStateMapper.displayState(status:)` 只在一个集中入口执行状态映射：
   - `disabled` 或无效模式返回 Normal State。
   - `powerLossOnly` 只看 `emergencyActive`。
   - `fireAlarmOnly` 只看 `fireActive`。
   - `powerLossAndFireAlarm` 下 Fire Alarm 优先于 Power Loss。
4. 不在页面层使用本地配置 `workingMode` 替代设备返回值。本地配置可能与设备实际状态不同，实时展示应以设备返回为准。

## 影响范围

包含：

- 本地 `NordicSigMeshSDK` 的 `0x4D/0x04` 状态模型与解析。
- SDK 的 `EmergencyFireVendorMessageTests`。
- App EFC 设备页状态映射入口。

不包含：

- EFC 编辑页 working mode 保存逻辑。
- EFC 关联组、同步、默认配置、删除、恢复、Mock 操作。
- UI 文案和资源变更。
- `ever_em` / `ever_fire` 的用户可见展示。

## 测试计划

1. SDK 单元测试覆盖 `enable_mode = 0/1/2/3`，确认解析结果保留真实模式和 active 字段。
2. SDK 单元测试覆盖无效 `enable_mode`，确认响应仍解析成功，并把模式表达为无效/未知。
3. App 映射测试覆盖状态判定表：
   - `0` 即使 active 字段为 `1` 也应显示 Normal。
   - `1` 只响应 `em_active`。
   - `2` 只响应 `fire_active`。
   - `3` 同时响应两路，并保持 Fire Alarm 优先。
   - 无效模式静默显示 Normal。
4. App 映射测试覆盖 `0x4D04000101010100` 对应 Power Loss。
5. 静态检查运行 `git diff --check`。
6. SDK 验证优先运行本地 SDK iPhoneOS build。
7. App 验证运行 SunSmart iPhoneOS build。

## 风险与约束

- 如果直接删除 `enabled` 或 `everTriggered`，可能影响现有 App 编译。实现时应先搜索调用点，必要时保留兼容计算属性。
- 本地 SDK 当前已有其他未提交改动，实施时需要避免混入这些改动。
- 无效 `enable_mode` 按产品要求静默 Normal，测试应明确锁定这个行为，避免后续被误改成解析失败或 Offline。
