# Battery Power Switch BLE OTA Hint Design

## 背景

`Site - Space - More` 中的 `Firmware Update via BLE` 页面需要针对 Battery Power Switch 类型设备优化展开后的提示 UI。该优化只作用于 Battery Power Switch，不改变其他设备类型的展示、选择、刷新、升级流程。

Figma 参考节点：

- Fold details: `72:5887`
- Unfold details widget: `72:6005`

仅参考提示内容的位置、样式与展开/折叠行为，其余页面元素保持当前项目实现。

## 当前实现

BLE OTA 页面由 `BleFirmwareUpdateViewController` 管理，设备类型卡片由 `BleFirmwareTypeUpdateViewCell` 渲染。

设备类型卡片现有结构：

- 设备类型与产品 ID
- Current target version
- Total / Upgraded
- 展开后的设备列表，含 `Select all` header
- 底部展开/收起箭头

卡片高度依赖 Auto Layout 与 collection view 的 estimated item size。Battery Power Switch 类型可通过现有 `Node.isBatteryPowerSwitch` 判断；当前 Battery Power Switch 产品 ID 包含 `0x2A01`、`0x2A02`。

## 目标

1. 只优化 Battery Power Switch 类型设备卡片展开后的 UI。
2. 在 Battery Power Switch 展开后，增加 OTA 激活提示。
3. 提示位于设备列表 `Select all` header 上方，也就是 Figma 中 `REFRESH` 按钮上方对应的提示位置。
4. 默认折叠，折叠态展示单行省略文本。
5. 展开后展示完整提示内容，自动换行。
6. iPhone 与 iPad 均使用约束自适应宽度，不依赖固定屏幕宽度。
7. 不改变其他设备类型的 UI 与业务行为。

## 提示文案

完整内容：

```text
Battery-powered devices need to be activated before the upgrade can be performed.Press 'Button 2'and 'Button ON' on the device to wake it up for the update. Then click refresh.The device has a 60s activation time.Activation and upgrade must be completed within this timeframe.
```

实现时优先新增本地化 key，默认英文值使用上述原文。若项目本地化资源按多个 target 复用，需要同步检查 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的资源引用不受影响。

## 推荐方案

在 `BleFirmwareTypeUpdateViewCell` 内新增一个 Battery Power Switch 专用提示视图，放在 `deviceNumberView` 与 `deviceTableView` 之间。

推荐理由：

- 卡片内容与展开状态都由该 cell 管理，位置最准确。
- 只需要根据当前 `FirmwareUpdateTypeData` 的设备列表判断是否为 Battery Power Switch。
- Auto Layout 可以自然参与 collection view estimated item size 计算。
- 非 Battery Power Switch 类型隐藏该视图并将高度置零，避免影响其他设备类型。

## UI 设计

提示卡样式参考 Figma：

- 背景色：`#FFF3E3`
- 圆角：约 15pt
- 文本色：`#64748B`
- 字号：13pt，light 或项目中接近的轻字重
- 行高：约 20pt
- 左右内边距：文本左侧约 18-20pt，右侧为箭头预留空间
- 右侧按钮大小固定为 30x30pt，按钮图片与按钮同尺寸
- 默认折叠时右侧按钮图片使用 `arrow_fold_down`
- 展开后右侧按钮图片使用 `arrow_fold_up`

折叠态：

- 高度约 50pt。
- `numberOfLines = 1`。
- `lineBreakMode = .byTruncatingTail`。
- 文本可自然以 `...` 结尾。
- 右侧按钮显示 `arrow_fold_down`。

展开态：

- 文本 `numberOfLines = 0`。
- 高度根据文案和可用宽度自适应。
- iPad 宽屏下文本仍按卡片宽度换行，不写死行数。
- 右侧按钮显示 `arrow_fold_up`。

## 状态设计

新增一个仅 UI 使用的展开状态：

- 默认折叠。
- 点击提示卡或箭头切换展开/折叠。
- 刷新 RSSI、cell reload、collection layout invalidate 后保留状态。

状态可放在 `FirmwareUpdateTypeData`，例如 `isBatteryPowerSwitchHintExpanded`，因为该状态属于设备类型卡片并需要跨 cell reuse 保留。

## 数据判断

在 `FirmwareUpdateTypeData` 增加只读判断：

- `isBatteryPowerSwitchType`：当 `nodes` 中存在 `node.isBatteryPowerSwitch == true` 时为 true。

该判断比单纯用 product ID 更贴近现有项目模型，也复用已维护的 company/product 判断逻辑。

## 交互与业务边界

本次不改变：

- 扫描/刷新 RSSI 逻辑。
- 单设备升级入口。
- 多设备选择与 `Upgrade Selected` 逻辑。
- `Select all` header 行为。
- 升级结果栏与 restore 提示。
- 非 Battery Power Switch 设备类型 UI。

当 Battery Power Switch 类型未展开时，不显示提示。只有展开设备类型卡片后才展示提示，符合“设备展开后的 UI”范围。

## 验证

实现后需要验证：

1. Battery Power Switch 类型展开后显示提示，位置在设备列表 header 上方。
2. 默认折叠，折叠态单行省略。
3. 点击提示卡后展开完整内容，文本自动换行。
4. 再次点击后恢复折叠。
5. iPhone 宽度下不遮挡、不溢出、不影响底部升级栏。
6. iPad 宽度下卡片和文本按当前布局自适应。
7. 非 Battery Power Switch 类型卡片高度与 UI 无变化。
8. `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 通过。

## 风险与约束

- collection view 使用 estimated item size，新增可变高度视图后需要在切换提示展开状态时 invalidate layout。
- cell reuse 需要确保非 Battery Power Switch 类型隐藏提示并重置约束高度。
- 如果新增本地化 key，需要避免遗漏任一 target 的资源配置。
