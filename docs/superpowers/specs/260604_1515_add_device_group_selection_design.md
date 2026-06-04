# Add Device Group Selection Restrictions Design

## 背景

Add Device 页面支持将新设备添加到 Space、Group 或 Dongle。当前 Classic 和 Professional 两种添加模式在扫描到支持设备时会默认设为选中状态，之后通过 `applySelectableState` 修正部分业务限制。

新需求是：当 `Add device(s) to` 选择 Group 时，Switches 列表和 Others 列表下的设备仍然展示，但不允许选中，也不允许添加入网。如果用户先在 Space 下选中了 switches 或 others 设备，再切换到 Group，需要取消这些设备的选中状态并显示为不可选状态。

## 当前实现分析

相关文件：

- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
- `SunSmart/Main/Device/View/DeviceAddViewCell.swift`

Classic 模式维护 `scanDevices` 和 `showDevices`，目标用 `addToGroup` / `bindToDongle` / `bindTarget` 表示。Professional 模式维护 `scanDevices`、`inRSSIDevices`、`remainingRSSIDevices` 和 `candidateDevices`，目标用 `addTarget` 表示。

两种模式都已有集中判断入口：`isAllowedDevice`、`isBlockedDevice`、`isSelectableDevice`、`applySelectableState`、`normalizeSelectionForCurrentTarget`。因此新增规则应接入这些入口，而不是只在某个按钮点击处拦截。

`DeviceAddViewCell` 已支持 `device_add_disable` 图片，但当前 `.disabled` 设备在 `.none` 状态下仍可能让 Add 按钮保持 enabled，需要补齐 UI 状态。

## 设计目标

1. Group 目标下，Switches 和 Others 分类设备继续展示。
2. Group 目标下，Switches 和 Others 分类设备显示为不可选。
3. Group 目标下，Switches 和 Others 分类设备的 Add 按钮显示 disabled 状态且不可点击。
4. 从 Space 切换到 Group 时，已选中的 switches/others 设备立刻取消选中并变为 disabled。
5. 从 Group 切回 Space 时，未处于添加流程的 switches/others 设备恢复为可选未选中状态。
6. 不改变 Lights 和 Sensors 在 Group 目标下的现有添加行为。
7. 不改变 Identify 行为；本需求只限制选中和添加入网。

## 规则定义

新增“当前目标是否为 Group”的局部判断：

- Classic：`addToGroup != nil`。
- Professional：`addTarget` 为 `.group`。

Group 目标下禁选以下设备类型：

- `.switches`
- `.dongle`
- `.gateway`
- `.emergencyController`
- `.unknown`

这些类型对应 Add Device 页面中的 Switches 和 Others 分类。`.light` 和 `.sensor` 不受影响。

## 方案

推荐采用控制器层统一规则加 UI 补齐。

### Classic 模式

在 `DeviceAddClassicModeController` 中增加 Group 目标禁选判断，并接入 `isBlockedDevice` 或相邻的可选性判断。这样扫描、RSSI 筛选、分类切换、目标切换都会复用同一套规则。

目标切换回调中继续调用现有 `normalizeSelectionForCurrentTarget()`，该方法会对 `scanDevices` 和 `showDevices` 调用 `applySelectableState`。Group 目标下已选中的 switches/others 将被设置为 `.disabled`，从而不再计入选中数量，也不会进入批量添加。

### Professional 模式

在 `DeviceAddProfessionalModeController` 中增加相同规则，并接入 `isBlockedDevice` 或相邻的可选性判断。

Professional 模式除表格外还有 `candidateDevices`。目标切换到 Group 后，`normalizeSelectionForCurrentTarget()` 需要继续清理 `candidateDevices` 中的 disabled 设备，避免已预选的 switches/others 留在候选列表并被添加。

扫描自动加入候选列表的逻辑已经检查 `selectedState != .disabled` 和 `isSelectableDevice`，接入统一规则后，Group 目标下的新扫描 switches/others 不会自动进入候选列表。

### Candidate 列表

`DeviceAddCandidateDeviceListView` 的批量选择和添加入口已经以 `selectedState != .disabled` 为主要过滤条件。由于 Professional 控制器会在传入 candidate 前清理 disabled 设备，弹层主要需要保持现有防线。

为了避免状态不同步，candidate 的 `startAdd` 回调进入 Professional 控制器后仍应只提交当前可选设备。

### Cell Add 按钮

在 `DeviceAddViewCell` 的 `.none` / `.scaning` 状态展示逻辑中，Add 按钮需要同时检查：

- 设备类型不是 `.unknown`。
- `device.selectedState != .disabled`。
- 当前 add state 没有处于扫描禁用状态。

当 `selectedState == .disabled` 时，Add 按钮应使用已有 disabled 图片并禁用点击。这样 Group 目标下 switches/others 的视觉状态与业务状态一致。

## 防线

实现时需要保留多层防线：

- `applySelectableState` 负责把非法设备转成 `.disabled`。
- row selection 遇到 `.disabled` 时直接返回并显示现有禁用提示。
- 单个 Add 入口遇到 `.disabled` 时直接返回。
- 全选只处理非 disabled 设备。
- 批量添加只提交 selected 且非 disabled 的设备。
- Professional candidate 添加前再次过滤不可选设备。

## 不在本次范围

- 不隐藏 switches/others 设备。
- 不新增本地化文案。
- 不改变 Group/Dongle/Space 目标选择 UI。
- 不修改设备发现、入网、key bind、group deferred sync 的底层流程。
- 不改变 Site add、Restore add、Reset 等非 Add Device 页面。

## 验证计划

1. Classic 模式：
   - Space 目标下进入 Switches 列表，设备可选，Add 可用。
   - 选中 switches 后切换 `Add device(s) to` 为 Group，设备变为 disabled，Add 不可用。
   - Group 目标下进入 Others 列表，设备展示但 disabled，Add 不可用。
   - 切回 Space 后，未添加中的 switches/others 恢复为未选中可选状态。

2. Professional 模式：
   - Space 目标下 switches/others 可进入 candidate。
   - 切换到 Group 后，candidate 中 switches/others 被移除。
   - Group 目标下扫描到 switches/others 时不会自动进入 candidate。
   - Group 目标下 switches/others 的单行 Add 不可用。

3. 构建验证：
   - 运行 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。
   - 不使用 Simulator 作为本次校验依据。

## 风险与注意事项

- Classic 和 Professional 有重复逻辑，实施时要保持规则一致。
- Professional 的 `candidateDevices` 是额外状态源，必须在目标切换和添加入口都清理或过滤。
- 从 Group 切回 Space 时，只恢复未处于添加中、等待添加、连接中或成功状态的设备，避免破坏正在添加流程。
- 当前工作区已有无关 Swift 文件和 docs 文件改动，实施和提交时需要避免误包含。
