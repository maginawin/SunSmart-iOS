# Sensor Cal. noteLabel 截断问题分析与修复计划

## 1. 结论

`LightSensorTargetSensorValueView.noteLabel` 的英文文案和本地化资源是完整的，源码也已经设置 `numberOfLines = 0`。问题不是文案缺失，也不是显式限制为两行。

直接原因是：在 iPhone 11 / iOS 18.3.2 上，`noteLabel` 最终得到的高度只够显示两行；`UILabel` 默认 `lineBreakMode` 为 `.byTruncatingTail`，所以第三行未获得布局高度时，第二行末尾的 `target.` 被显示为 `tar...`。

结构性原因是：当前 Sensor 卡片把多行 Label 放在一个由内部约束撑高、再嵌入纵向 `UIStackView` 的自适应高度 View 中，但没有显式提供以下多行布局保护：

- 没有把 `lineBreakMode` 明确设置为 `.byWordWrapping`；
- 没有提高 `noteLabel` 的垂直抗压缩优先级；
- 没有按最终可用宽度维护 `preferredMaxLayoutWidth`。

因此卡片高度完全依赖 UIKit 在布局阶段自动推导多行 Label 的固有高度。iOS 26 当前会重新计算出足够高度，但 iOS 18.3.2 的实际真机结果表明该隐式计算路径不稳定，最终沿用了不足的两行高度。

在未取得 iPhone 11 运行时 frame、`preferredMaxLayoutWidth` 和 Auto Layout trace 前，可以确认“Label 实际高度不足且按默认规则截断”；“旧版 UIKit 在嵌套 Stack View 中使用了不足或过期的多行测量宽度”是当前最符合源码与真机现象的高概率触发机制，需要在实施后的 iPhone 11 布局检查中闭环确认。

## 2. 源码证据

### 2.1 文案完整

英文资源 `calibration_target_sensor_value_note` 的内容为：

> If ambient light remains strong even at 0% dim level, you can manually enter a lower sensor reading value as the target.

资源末尾包含完整的 `target.`，不存在本地化截断或字符串拼接问题。简体中文资源也完整。

### 2.2 Label 没有限制两行，但缺少完整内容高度保护

`SunSmart/Main/Group/View/LightSensorCalibrationModeView.swift` 中：

- `noteLabel.numberOfLines = 0`；
- Label 左右边与 `inputRow` 相等，顶部连接 `inputRow`；
- 下方 `dimLevelView` 连接到 `noteLabel.bottom`，卡片底部再连接 `dimLevelView.bottom`；
- 没有固定 Sensor 卡片高度；
- 没有设置 `lineBreakMode`、垂直 Content Compression Resistance 或 `preferredMaxLayoutWidth`。

`LightSensorTargetSensorValueView` 又作为 arranged subview 放入 `LightSensorCalibrationViewController` 的纵向 `calibrationContentStackView`。这条约束链理论上能够随 Label 增高，但当前缺少对多行固有高度的显式保护。

### 2.3 UIKit 行为与现象一致

当前 Xcode iPhoneOS SDK 的 `UILabel.h` 明确说明：

- `lineBreakMode` 默认是尾部截断，并同时用于单行和多行；
- `numberOfLines = 0` 仅表示不限制行数；
- 当 View 高度不足时，文字仍按 `lineBreakMode` 截断；
- 多行 Label 的 Auto Layout 固有高度可以使用 `preferredMaxLayoutWidth` 计算。

因此 `numberOfLines = 0` 本身不能保证文案完整展示。

### 2.4 不是简单的屏幕宽度问题

当前布局的水平间距均按屏幕宽度缩放，且 iPhone 11 默认逻辑宽度并不小于 iPhone 12/15。结合 iPhone 11 / iOS 18.3.2 失败、iPhone 12/15 / iOS 26+ 正常，更符合 UIKit 版本、布局重算时机或设备显示设置触发的高度计算差异，而不是单纯“屏幕太窄”。

实施时仍需要同时检查 iPhone 11 是否启用了 Display Zoom、Bold Text 或非默认文字大小，避免把设备设置变量误判为纯系统版本差异。

### 2.5 历史与影响范围

该 `noteLabel` 自 Sensor Cal. 初始实现提交起就采用当前布局方式，后续 inputRow 自适应调整没有改变它的多行高度策略；最新 Night Cal. 文案调整也没有修改 Sensor 的 Label 或其约束。

该 View 位于共享业务源码中，修复会影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart 等引用共享文件的 target。预计不需要改本地化、资源、target 配置、依赖或 NordicSigMeshSDK。

## 3. 聚焦修复方案

### 3.1 推荐的最小修复

只调整 `LightSensorTargetSensorValueView` 的说明 Label：

1. 将 `noteLabel` 从局部变量提升为该 View 的私有属性，以便在布局完成后读取实际宽度；
2. 保持 `numberOfLines = 0`，显式设置 `.byWordWrapping`；
3. 将 Label 的垂直 Content Compression Resistance 提升为 `.required`，避免外层纵向 Stack View 优先压缩说明文字；
4. 在 `layoutSubviews` 中根据 `noteLabel.bounds.width` 更新 `preferredMaxLayoutWidth`，仅在宽度变化时更新并使固有尺寸失效，确保旋转、iPad、Display Zoom 和不同品牌容器宽度都按最终宽度计算多行高度；
5. 保持现有字体、颜色、文案、水平边距、上下间距、Dim level 布局和交互不变。

项目现有 Fire Alarm 等自适应文本组件已经采用“明确换行 + required 垂直抗压缩 + 在 `layoutSubviews` 同步 `preferredMaxLayoutWidth`”的做法，可复用同一模式，不需要新增通用组件或扩大重构范围。

### 3.2 不推荐方案

- 不把 `numberOfLines` 固定为 3：中文或其他宽度下可能只需两行，也可能需要更多行；验收目标应是完整展示，而不是硬编码行数。
- 不给 `noteLabel` 或整个 Sensor 卡片写固定高度：字体度量、语言、Display Zoom、iPad 宽度变化后仍可能截断或产生多余空白。
- 不修改英文文案来规避换行：当前文案是完整且已确认的产品内容，缩短文案只会掩盖布局缺陷。
- 不调整整个 Calibration 页面或 Night/Plane 卡片：当前问题只发生在 Sensor 说明文字，扩大布局改动会增加回归风险。

## 4. 回归保护与验证计划

### 4.1 静态契约

扩展 `Tests/Group/SensorCalibrationWorkflowContractTests.swift`，保护以下约束：

- Sensor `noteLabel` 保持无限行；
- 明确使用 word wrapping；
- 垂直抗压缩为 required；
- `preferredMaxLayoutWidth` 使用实际 Label 宽度更新；
- 不新增固定三行高度或固定 Sensor 卡片高度；
- 不改变 inputRow 中 Target value、LX、Use sensor reading 的自适应宽度规则。

运行 `zsh scripts/check_sensor_calibration_workflow.sh` 和 `git diff --check`。

### 4.2 实际布局验证

UI 修复必须以实际布局为准，不能仅用编译或源码契约验收：

1. 首要设备：iPhone 11 / iOS 18.3.2，English，进入 Calibration 并切换到 Sensor Cal.；确认说明文字换为三行且完整显示 `target.`；
2. 在该设备记录修复后 `noteLabel.bounds`、`intrinsicContentSize`、`preferredMaxLayoutWidth`、`lineBreakMode`、`hasAmbiguousLayout`，确认 Label 高度覆盖完整三行且没有 Auto Layout 冲突；
3. 回归设备：iPhone 12 和 iPhone 15 / iOS 26+，确认当前正常布局没有额外截断、异常空白或 Dim level 位移；
4. 至少覆盖 English 与简体中文；
5. 检查默认显示、Display Zoom（如设备支持）、Bold Text 和项目支持的文字大小设置；
6. 截图对比完整 Sensor 卡片，确认 Target value、LX、Use sensor reading、说明文字、Dim level 和卡片底部间距均正确；
7. 切换 Night Cal.、Sensor Cal.、Plane Cal.，确认隐藏 arranged subview 后滚动内容高度能正确重算。

### 4.3 构建范围

因修改位于共享源码，实际实施后应按项目规则串行执行四品牌 generic iPhoneOS Debug 无签名构建：

- SunSmart；
- Archipelago；
- SLG Sync Plus；
- SylSmart。

编译通过只代表 target 集成没有破坏，不能代替上述 iPhone 11 真机布局验收。

## 5. 本轮边界与基线

- 本轮仅完成原因分析和修复规划，没有修改业务/UI 实现；
- 分析开始时工作区无未提交改动；
- 现有 `zsh scripts/check_sensor_calibration_workflow.sh` 基线通过；
- 本轮没有修改 SDK、本地化、资源、依赖或 target 配置；
- 真正的跨版本根因闭环和 UI 验收需在实施修复后通过 iPhone 11 / iOS 18.3.2 真机完成。
