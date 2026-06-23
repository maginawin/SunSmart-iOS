# AC Power Switch Refresh 菜单分析与开发方案

## 背景

需求是在 AC power switch 的设备详情页右上角菜单中增加与 light 设备页一致的 `Refresh` 菜单项，复用 `menu_refresh` 图标，并复用 `refresh` 本地化文案。

目标菜单：

- 有 edit 权限：`Edit`、`Delete`、`Information`、`Identify`、`Refresh`
- 无 edit 权限：`Information`、`Identify`、`Refresh`

这里按实际代码能力判断描述为“有 edit 权限 / 无 edit 权限”。`SpaceData.deviceOperates` 会受 `permission == .visitor`、`disableEditorPermission`、`meshOTADistribution` 等条件影响，因此比字面 Owner / Editor / Visitor 更接近真实菜单权限。

## 现状分析

### Light 设备页 Refresh 的真实功能

Light 设备详情页入口是 `DeviceLightViewController.moreClick()`：

- 菜单项使用 `UIImage(named: "menu_refresh")`
- 文案使用 `"refresh".localizedString`
- 点击后调用 `refresh()`

`DeviceLightViewController.refresh()` 的行为：

1. 显示一个短暂 HUD。
2. 调用 `getNodeState()`。
3. `getNodeState()` 内部会执行 `MeshAPI.getNodeState(address:)`，向当前 light 设备查询状态。
4. 如果设备有 ambient light sensor，会额外读取 lux。
5. 同时通过 `MeshLibManager.manager.refreshNodesRSSI(...)` 扫描 RSSI：
   - 扫到当前节点时更新 `node.rssi` 并停止 RSSI 刷新。
   - `refresh()` 末尾的 5 秒扫描若结果不包含当前节点，会把 `node.rssi` 置空。

结论：light 页的 `Refresh` 不是重新同步配置，也不是云端刷新；它是本地 mesh 状态刷新，核心是查询当前节点状态并刷新 RSSI。

### AC Power Switch 当前菜单

AC power switch 设备详情页入口是 `PJEightKeySwitchMonitorVC.moreAction()`。

当前菜单逻辑：

- 无 edit 权限分支：
  - 仅在存在真实绑定设备时显示 `Information`
  - 不显示 `Identify`
  - 不显示 `Refresh`
- 有 edit 权限分支：
  - 显示 `Edit`、`Delete`
  - 已绑定真实设备时显示 `Information`、`Identify`
  - 不显示 `Refresh`

当前 `identifyAction()` 还有一层 `viewModel.canEditPowerSwitch` guard，因此即使在无 edit 权限分支里加入 `Identify` 菜单，也会被 “No permission!” 拦截。需求要求无 edit 权限也显示 `Identify`，所以需要同步调整 action guard。

### AC Power Switch 状态刷新缺口

AC 页头部状态由 `PJEightKeySwitchMonitorViewModel.acHeaderState()` 计算：

- `informationNode?.state == true` 表示设备在线
- `MeshLibManager.manager.isMeshNetworkConnected` 表示 mesh 连接状态
- 两者共同决定 `online`、`device_offline`、`space_offline`

但 `PJEightKeySwitchMonitorVC` 当前没有与 light 页同等的右上角 Refresh，也没有主动在菜单动作中执行：

- `MeshAPI.getNodeState(address:)`
- `MeshLibManager.manager.refreshNodesRSSI(...)`
- `updateUI()`

因此需求真实存在。

## 开发方案

### 1. 调整 AC 菜单构建

修改 `PJEightKeySwitchMonitorVC.moreAction()`：

- 对已绑定真实 AC power switch 的页面，始终追加：
  - `Information`
  - `Identify`
  - `Refresh`
- 只有 `viewModel.space.deviceOperates.contains(.edit)` 时追加：
  - `Edit`
- 只有 `viewModel.space.deviceOperates.contains(.delete)` 时追加：
  - `Delete`
- 对未绑定真实设备的 virtual power switch，继续保持不显示 `Information` / `Identify` / `Refresh`，避免没有目标 node 时操作失败。

建议将 `Information`、`Identify`、`Refresh` 的 MenuItem 构造拆成小的 private helper，减少权限分支重复，但不做更大范围重构。

### 2. 新增 AC Refresh action

在 `PJEightKeySwitchMonitorVC` 新增 `refreshCurrentPowerSwitch()`：

- guard `viewModel.switchData.powerSwitchKind == .ac`
- guard `let node = viewModel.informationNode`
- 显示与 light 页一致的 HUD：`XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 2)`
- 调用 `MeshAPI.getNodeState(address: node.primaryUnicastAddress)`
- 调用 `MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 5)`：
  - 若结果不包含当前 node，将 `node.rssi = nil`
  - 完成后主线程调用 `updateUI()`

这与 light 页 Refresh 保持同一类行为：查询当前设备状态 + 刷新 RSSI。

### 3. 调整 Identify 权限

根据目标菜单，无 edit 权限也需要 `Identify`。建议把 `identifyAction()` 中的 `viewModel.canEditPowerSwitch` guard 移除或只限制编辑类 flow。

对 AC power switch：

- `identifyAction()` 已经在 `switchData.powerSwitchKind == .ac` 时直接使用 `identifySender.sendIdentify(to:)`
- 这类操作更接近设备识别/定位，不是配置写入
- 因此可以允许无 edit 权限用户触发

对 battery power switch：

- 当前 identify 可能进入激活弹窗 flow
- 本需求只要求 AC power switch，因此实现时可优先保证 AC 分支无 edit 权限可用
- 如要避免扩大 battery 行为，可将 guard 移到 battery 分支，AC 分支不受 edit 权限限制

### 4. 国际化与资源

无需新增资源或本地化：

- 图标复用已有 `menu_refresh`
- 文案复用已有 `"refresh"`，当前 English / 简体中文均已存在

### 5. 验证计划

代码修改后建议验证：

1. 静态检查：
   - 确认 `PJEightKeySwitchMonitorVC.moreAction()` 在有 edit 权限时菜单顺序为 `Edit`、`Delete`、`Information`、`Identify`、`Refresh`
   - 确认无 edit 权限时菜单顺序为 `Information`、`Identify`、`Refresh`
   - 确认 unlinked virtual AC power switch 不显示无目标 node 的操作
2. 构建验证：
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 影响范围

预计只修改：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

不需要修改：

- 本地化文件
- asset catalog
- target 配置
- SDK
- power switch 数据模型

## 待确认点

1. `Identify` 是否确认对无 edit 权限的 AC power switch 用户开放实际发送能力，而不只是显示菜单。已确认：可以实际发送。
2. 未绑定真实设备的 virtual AC power switch 是否继续隐藏 `Information`、`Identify`、`Refresh`。已确认：继续隐藏。
