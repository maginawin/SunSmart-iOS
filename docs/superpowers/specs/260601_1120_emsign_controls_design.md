# EMSign 控件展示与点击拦截优化设计

## 背景

`SR-BL9036T-PCBA` EMSign 设备仍归类为 Lighting，需继续在 Site、Space、Group 等灯设备通路中展示和管理。但它是 Identify-only 设备，不支持单设备 On/Off、亮度、色温控制。此前已完成 EMSign 设备识别、默认命名、参数页过滤和单设备 Identify-only 页面，本次优化集中处理列表/组内控件展示与点击行为。

## 目标

- Site - Space - Main - Lights 分类下展示的 EMSign 设备控件：
  - 在线且 keybind 完成时默认显示为 ON 视觉状态。
  - 不展示亮度/色温进度条。
  - 点击设备控件不发送任何 Mesh 命令。
  - 点击设备控件不切换 `node.isOn`，不切换 OFF 状态。
- Group 相关页面展示 EMSign 设备控件时使用同一规则：
  - Group 详情页设备圆形控件。
  - Group Members/组成员管理里的设备圆形控件。
- 长按进入 EMSign 单设备页面后，Identify 按钮图标使用资源 `Identify`，图标显示尺寸为 40x40。

## 非目标

- 不改变 EMSign 的 `deviceCategory = Lighting` 归类。
- 不改变 EMSign 加入 Site、Space、Group 的能力。
- 不过滤组、场景、日程中基于灯 model 展示的组级控件。
- 不改变全组 On/Off、Auto、亮度、色温等组级命令逻辑。
- 不改变离线状态展示；离线 EMSign 仍按离线设备展示。

## 推荐方案

采用已确认的方案一：在通用设备 cell 层处理 EMSign 的展示规则，在各页面点击回调入口拦截 EMSign 的单设备控制。

这样展示规则集中在 `DevicesViewCell`，`GroupDeviceViewCell` 继承后自然生效；点击拦截保留在页面控制逻辑入口，避免影响普通灯、全组控制和其他业务路径。

## 组件设计

### `DevicesViewCell`

当 `device.isEmergencySignController` 且设备在线、keybind 完成时：

- 强制使用 ON 视觉：白色背景、正常标题色、正常设备 icon。
- 隐藏 `progressView`，不展示亮度/色温条。
- 不根据 `device.isOn` 或 `device.lightness` 推导 OFF 背景。

离线或未 keybind 完成时，沿用现有离线/repair 展示。

### `GroupDeviceViewCell`

继续继承 `DevicesViewCell` 的 EMSign 展示规则，仅保留现有 Group cell 的图标尺寸和位置差异。

### `DeviceLightsViewController`

在单设备点击流程中，若目标节点是 EMSign：

- 直接返回。
- 不触发 emergency block 提示。
- 不修复、不查询 On/Off、不切换 `node.isOn`、不发送 `MeshAPI.setNodeOnOffState`。

长按进入 `DeviceLightViewController` 保持可用。

### `GroupViewController`

在 Group 详情页设备圆形控件点击流程中，若目标节点是 EMSign：

- 直接返回。
- 不触发 emergency block 提示。
- 不查询 On/Off、不切换本地状态、不发送单设备 On/Off 命令。

Group 页面的全组控制仍保持原逻辑。

### `GroupMembersViewController`

在组成员管理页设备圆形控件点击流程中，若目标节点是 EMSign：

- 直接返回。
- 不触发 repair/offline 后续控制逻辑。
- 不切换本地状态、不发送单设备 On/Off 命令。

长按进入设备详情保持可用。

### `DeviceLightViewController`

EMSign Identify-only 页面中：

- Identify 按钮图标从 `device_identify` 改为 `Identify`。
- 按钮约束保持 40x40。
- Identify 下发仍沿用当前 vendor identify：`SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500)))`。

## 验证点

- Site - Space - Main - Lights 中，EMSign 在线时无进度条、显示 ON 视觉，点击不发 On/Off 命令且不变灰。
- Group 详情页中，EMSign 在线时无进度条、显示 ON 视觉，点击不发 On/Off 命令且不变灰。
- Group Members/组成员管理页中，EMSign 在线时无进度条、显示 ON 视觉，点击不发 On/Off 命令且不变灰。
- 长按 EMSign 进入单设备页，Identify 图标为 `Identify`，显示尺寸为 40x40。
- 普通灯的列表展示、点击开关、亮度/色温条不受影响。
- iOS Debug iphoneos 构建通过。
