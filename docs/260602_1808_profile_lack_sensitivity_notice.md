# Profile lack sensitivity notice 设计

## 背景

Group Profile 编辑页中，现有 `Relative sensitivity` 只在部分 profile 中显示。根据当前代码逻辑，`daylight harvesting (Closed loop)` 和 `Manual control` 不显示 `Relative sensitivity`，其它默认 group profile 会显示该属性。

新需求要求：当 group 中存在任一 `isExternalLightSensorCapableLuminaire == true` 的 node 时，该 node 视为 lack sensitivity 设备。此时需要在 Profile 编辑页的 `Relative sensitivity` 标题同一行右侧显示提示：

`Some devices lack sensitivity`

## Figma 参考

Figma 节点：

https://www.figma.com/design/6oNpzrtKUau4OLQnpXallR/SunSmart_v1.3.0-v1.5.0?node-id=19706-44759&m=dev

读取结果显示该节点是完整的 Relative sensitivity 卡片：

- 白色背景，圆角 10。
- 左侧为 `Relative sensitivity` 标题和 help 按钮。
- 右侧为 `Some devices lack sensitivity`，颜色 `#FFA72C`，字号 12，右对齐。
- 节点中还包含一行 `10 min`，但它与当前 Relative sensitivity 百分比 slider 语义不一致，本需求不采用该内容。

## 目标行为

- `daylight harvesting (Closed loop)` 和 `Manual control` 继续不显示 `Relative sensitivity`，也不显示该提示。
- 其它会显示 `Relative sensitivity` 的 group profile 中：
  - 如果当前 group 中任一 node 的 `isExternalLightSensorCapableLuminaire == true`，显示 `Some devices lack sensitivity`。
  - 如果 group 为空、没有 group、或没有 lack sensitivity 设备，隐藏该提示。
- 提示只读，不影响保存、同步、profile 数据、设备参数或 SDK 行为。

## 推荐方案

采用 controller 计算、view 展示的方案：

- `ProfileSettingsViewController` 负责根据 `group?.nodes` 计算是否存在 lack sensitivity 设备。
- `ProfileSensitivityView` 增加一个可配置的提示状态，由它负责 label 的显示、隐藏和标题行布局。

这样可以保持职责边界清晰：

- 设备业务判断留在 controller。
- 标题行 UI 细节留在 view。
- 不向 view 引入 `Group` 或 `Node` 依赖。
- 不新增 `Group` 扩展属性，避免为了单一页面过早扩大模型层 API。

## UI 设计

`ProfileSensitivityView` 标题行调整为：

`Relative sensitivity` + help 按钮在左侧，`Some devices lack sensitivity` 在同一行右侧。

具体要求：

- 提示 label 文案使用本地化 key，例如 `profile_some_devices_lack_sensitivity`。
- 英文值：`Some devices lack sensitivity`。
- 中文建议值：`部分设备缺少灵敏度`。
- 提示颜色：`#FFA72C`。
- 提示字号：12。
- 提示右对齐，靠容器右边距 16。
- 提示与左侧 `Relative sensitivity` 标题垂直居中对齐；提示换行时仍围绕标题中线居中。
- 左侧标题和 help 按钮保持自然宽度，不被右侧提示压缩。
- 当宽度不足时，提示 label 允许换行；换行发生在右侧提示内部，不压缩左侧标题和 help 按钮。

现有卡片高度为 130，Figma 节点高度为 140。实现时优先保留现有高度；如果提示换行后与 slider 间距不足，再将 `sensitivityView` 高度调整到 140，以贴近 Figma 并避免内容重叠。

## 数据流

1. `ProfileSettingsViewController.updateUI()` 继续计算 `showSensitivity`。
2. 当 `showSensitivity == true` 时，计算：
   - `hasLackSensitivityDevices = group?.nodes.contains { $0.isExternalLightSensorCapableLuminaire } == true`
3. 将该值传给 `ProfileSensitivityView`。
4. `ProfileSensitivityView` 根据该值显示或隐藏提示 label。

## 影响范围

预计涉及文件：

- `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
- `SunSmart/Main/Profile/View/ProfileSensitivityView.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

修改本地化资源后，需要同步检查相关 target。该项目多个品牌 target 共享 `SunSmart` 下的本地化资源，本需求不新增品牌专属资源。

## 验证建议

- 检查 `.daylight` 和 `.manualControl` profile：不显示 `Relative sensitivity`，也不显示提示。
- 检查其它 profile，且 group 中无 lack sensitivity node：显示 `Relative sensitivity`，不显示提示。
- 检查其它 profile，且 group 中至少一个 node 的 `isExternalLightSensorCapableLuminaire == true`：显示提示。
- 检查窄屏布局：右侧提示换行时，左侧 `Relative sensitivity` 和 help 按钮不被压缩，提示整体与标题垂直居中。
- 运行 iOS 构建验证：
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 非目标

- 不改变 profile 保存逻辑。
- 不改变同步逻辑。
- 不改变设备 sensitivity 参数写入逻辑。
- 不修改 `isExternalLightSensorCapableLuminaire` 的判定规则。
- 不引入新的 SDK 依赖或 Auth 信息。
