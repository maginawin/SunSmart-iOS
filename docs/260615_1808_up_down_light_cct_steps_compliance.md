# Up/Down Light CCT Default Steps 添加链路符合性分析

## 需求摘要

目标设备为 `CID 0x0A78 / PID 0x2491` 的 Up/Down Light。

添加成功后需要读取一次 `get cct default steps`，并把结果保存到节点属性中，供 `Site - Space - More - Device Parameter Settings` 里的 `Absolute CCT Range` 默认值和 `Reset` 使用。

映射关系：

| CCT default steps | Absolute CCT Range 默认值 |
|---|---|
| `5` | `2700K...5000K` |
| `6` | `2700K...6500K` |
| 未返回或失败 | `2700K...5000K` |

## 当前实现核查

### 协议层

当前 SDK 已支持协议编码和解析：

- `SunricherVendorGet(function: .upDownLightDefaultCctSteps)` 映射到 `upDownLightDefaultCctSteps` 命令。
- `SunricherVendorStatus` 只接受返回 steps 为 `5` 或 `6`；非法值会标记失败并清空参数。

结论：符合。

### 添加成功后读取

当前 App 在 Classic 和 Professional 添加完成路径中，都会先调用 `UpDownLightDefaultCctStepsReader.readAfterProvisioning(devices:)`，完成后才继续 `deviceAddCallback`、空间统计保存和刷新通知。

`UpDownLightDefaultCctStepsReader` 的行为：

- 从成功添加的 provisioning device 找到对应 `Node`。
- 只筛选 `supportsUpDownRatioControl`，该能力对应 `CID 0x0A78 / PID 0x2491`。
- 对每个目标节点发送 `SunricherVendorGet(function: .upDownLightDefaultCctSteps)`。
- 返回成功且 steps 为 `6` 时保存 `6`。
- 其他情况，包括失败、超时、无 vendor model、非法返回，保存默认 `5`。
- 保存通过 `node.savePropertys()` 落库。

结论：添加主链路符合。

### 本地保存

SDK 已在 node properties 表中增加 `upDownLightDefaultCctSteps` 字段，并在 `loadPropertys()` / `savePropertys()` 中读写：

- 读取时恢复 `node.upDownLightDefaultCctSteps`。
- 保存时仅对 Up/Down Light default CCT steps 产品写入该字段。
- `Node.upDownLightDefaultCctSteps` 自身默认语义为 `5`，且 setter 会把非 `6` 值归一化为 `5`。

结论：符合“失败或未返回默认为 5，并保存根值”的要求。

### 默认范围和单设备 Reset

`Node.defaultAbsoluteCctRange` 已按保存的 `upDownLightDefaultCctSteps` 计算：

- steps `6`：`2700...6500`
- steps `5` 或缺失：`2700...5000`

`DeviceParameterSettingsController.defaultCctRangeDataForSelection` 使用首个设备的 `defaultAbsoluteCctRange`；单设备进入时，首个设备就是目标设备，所以 `Reset` 会回到保存 steps 对应的默认范围。

结论：单设备符合。

## 发现的缺口

当前批量 Device Parameter Settings 仍有边界问题：

- `defaultCctRangeDataForSelection` 只取 `devices.first?.defaultAbsoluteCctRange`。
- `absoluteCctRangeViewCellResetAction` 也只用这个单一默认值。
- 如果同一次批量设置里同时选中了 steps `5` 和 steps `6` 的 Up/Down Light，点击 `Reset` 会把所有设备统一重置到第一个设备的默认范围。

这不符合“此类型设备根据设备返回结果决定 Absolute CCT Range 默认值”的逐设备语义。

影响范围：

- 单个 Up/Down Light：不受影响。
- 多个 Up/Down Light 且 steps 相同：不受影响。
- 多个 Up/Down Light steps 混合：Reset 可能错误。
- 用户手动设置显式 Absolute CCT Range：仍按现有批量设置语义执行，不属于本缺口。

## 修复方案

### 方案 A：窄修复，禁止混合默认值的批量 Reset

当选择设备的 `defaultAbsoluteCctRange` 不一致时：

- `Absolute CCT Range` 打开后仍允许用户手动选择一个统一范围。
- `Reset` 不再使用第一个设备的默认值误导性地覆盖全部设备。
- UI 可显示当前批量值或 fallback 值，但 Reset 按钮需要禁用或隐藏，并给出简短提示。

优点：

- 改动小，不改变 `SyncDevicesViewController` 的批量参数结构。
- 避免把一个设备的默认值错误应用到另一个设备。
- 保留当前“批量手动设置同一范围”的能力。

缺点：

- 混合默认值批量场景不能一键 Reset，需要用户分组操作。

### 方案 B：按默认值分组下发 Reset

当用户点击 Reset 时，按每个节点的 `defaultAbsoluteCctRange` 分组，生成多组 `.absoluteCctRange(range:)` 同步任务：

- steps `5` 组下发 `2700...5000`
- steps `6` 组下发 `2700...6500`

优点：

- 最贴近逐设备 Reset 语义。

缺点：

- 需要改 `DeviceParameterSettingsController` 到 `SyncDevicesViewController` 的数据结构，目前 `.devicesParameter(devices.map({ ($0, setParameters) }))` 是每个设备共享同一组参数。
- 涉及批量同步结果汇总和 UI 文案，风险高于当前需求。

## 推荐计划

采用方案 A，先消除错误批量 Reset。

### Task 1：补充默认值一致性判断

文件：

- `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`

步骤：

1. 新增一个只读判断，检查 `devices.map(\.defaultAbsoluteCctRange)` 是否全部一致。
2. 保持单设备和同默认值批量设备行为不变。
3. 当默认值不一致时，Reset 不再使用 `devices.first` 的默认值。

验收：

- 单设备 steps `5` Reset 为 `2700K...5000K`。
- 单设备 steps `6` Reset 为 `2700K...6500K`。
- 批量 steps 全为 `6` Reset 为 `2700K...6500K`。
- 批量 steps 混合时不发生“全部按第一个设备默认值重置”。

### Task 2：调整 Absolute CCT Range cell 的 Reset 状态

文件：

- `SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift`
- `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`

步骤：

1. 给 `DeviceParameterAbsoluteCctRangeViewCell` 增加 Reset 可用性配置。
2. 默认保持现有行为。
3. 当默认值不一致时禁用或隐藏 Reset。
4. 如需提示，复用现有 noteLabel，不新增复杂弹窗。

验收：

- 单设备 UI 不变。
- 同默认值批量 UI 不变。
- 混合默认值批量不会出现可点击但语义错误的 Reset。

### Task 3：验证

命令：

- `git diff --check`
- `git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如果 SDK SPM 测试仍因 `no such module 'UIKit'` 失败，记录为既有测试环境限制，不作为本 App 集成验证阻塞。

## 当前结论

当前添加 Up/Down Light 的主流程已经符合需求：添加成功后读取一次、失败 fallback 为 `5`、保存 steps、单设备 Absolute CCT Range 默认值和 Reset 能使用保存值。

仍需修复的是批量 Device Parameter Settings 的混合 steps Reset 边界：当前会用第一个设备的默认值代表整个选择集，存在误重置风险。

## 方案 A 实施记录

已按方案 A 做窄修复：

- `DeviceParameterSettingsController` 增加所选设备默认 `Absolute CCT Range` 一致性判断。
- 单设备、同默认值批量设备继续保留 Reset。
- 混合默认值批量设备隐藏 Reset，避免把第一个设备的默认值错误应用到所有设备。
- `DeviceParameterAbsoluteCctRangeViewCell` 增加 Reset 可用性配置，默认行为保持不变。

验证结果：

- `git diff --check`
  - 通过。
- `git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check`
  - 通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - 通过，输出 `** BUILD SUCCEEDED **`。
