# Night Target Brightness Figma UI 修复分析与开发计划

## 1. 需求结论

本次只调整 `Night Cal.` 未完成状态下的 `Card / Target Night Brightness`，不改变校准流程、调光交互、数值范围、数据保存，也不修改 `Sensor Cal.` 与 `Plane Cal.` 的任何 UI。

目标结构应为：

1. `Target Night Brightness` 标题；
2. `Dim level` 组件；
3. Calibration Learning 描述文字。

卡片不设置固定高度，由标题、Dim level、可换行说明文字及上下间距共同撑开；英文、简体中文、不同屏幕宽度或系统字体布局变化时，高度随内容自适应。

## 2. Figma 结构化设计依据

目标页面节点为 `519:14663`，目标卡片为 `519:14714`。

Figma 中目标卡片的纵向层级与参数为：

| 层级 | 关键参数 |
| --- | --- |
| Card | 左右内边距 16、顶部 16、底部 24、圆角 16、纵向自适应 |
| Header | `Target Night Brightness`，14 pt Regular，20 pt 行高 |
| Control / Dim Level | 位于标题下方 16 pt；内部继续使用现有 Dim level 标题、百分比和滑条交互 |
| Description Container / Calibration Learning | 位于 Dim level 下方 20 pt；12 pt Regular、19.5 pt 行高、颜色 `#8B96A8`，宽度随卡片内容区 |

英文说明文案为：

> Once applied, the device will automatically learn the environment and adjust brightness to maintain the target illuminance. When ambient light drops to zero, the device will stabilize close to the target night brightness.

375 pt 设计稿中卡片宽度为 343 pt、参考高度约 243 pt；实现不应把 243 pt 写成固定高度。

## 3. 当前 App 差异与原因

当前 `LightSensorTargetNightBrightnessView` 位于 `SunSmart/Main/Group/View/LightSensorCalibrationModeView.swift`：

- 现有约束顺序是标题 → 旧说明 → Dim level，说明被放在标题与控件之间；
- 现有英文说明是 `Used only as the sampling brightness...`，与 Figma 的 Calibration Learning 语义不同；
- 现有说明字号为 11 pt，未设置 Figma 的 19.5 pt 行高；
- 现有标题字号为 15 pt，而 Figma 为 14 pt；
- 当前卡片本身没有固定高度，但底部约束落在 Dim level 上。若把说明移到末尾，必须同步把底部约束改到说明标签，才能继续保持完整的自适应高度约束链。

当前模式隔离已经成立：

- `LightSensorCalibrationViewController.updateCalibrationModeUI` 仅在 `mode == .night && !nightComplete` 时显示 `targetNightBrightnessView`；
- `Sensor Cal.` 使用独立的 `targetSensorValueView`；
- `Plane Cal.` 使用独立的 `onPointLuxView` / `offPointLuxView`；
- 三者虽然同处一个纵向 `UIStackView`，但通过独立 arranged subview 的显隐切换，因此本次无需修改 Controller 或共享 Stack。

## 4. 计划改动

### 4.1 Night 专属卡片布局

只修改 `LightSensorTargetNightBrightnessView.setupUI()`：

1. 保留现有 `LightSensorCalibrationDimLevelView`，不改共享 Dim level 组件；
2. 将 Dim level 顶部约束改为连接标题底部，间距 16 pt；
3. 将说明标签移动到 Dim level 之后，顶部间距 20 pt；
4. 将说明标签的底部连接卡片底部，底部内边距 24 pt；
5. 不新增固定高度约束，依靠完整的 top-to-bottom 约束链实现自适应；
6. 按 Figma 将本卡片标题调整为 14 pt Regular，说明调整为 12 pt Regular、19.5 pt 行高和现有 `AssistText_Color`（对应 `#8B96A8`）。

### 4.2 国际化文案

复用现有 `calibration_target_night_brightness_note` Key，不新增硬编码文案：

- English：替换为需求指定的 Figma 英文原文；
- 简体中文：同步提供等义翻译，建议为“应用后，设备将自动学习环境并调节亮度，以维持目标照度。当环境光降至零时，设备将稳定在接近目标夜间亮度的水平。”

当前 `SunSmart/en.lproj/Localizable.strings` 和 `SunSmart/zh-Hans.lproj/Localizable.strings` 已有用户未提交的确认弹窗文案改动。实施时只精确修改上述 note Key，保留其他现有改动。

### 4.3 回归约束

扩展 `Tests/Group/NightCalibrationWorkflowContractTests.swift`，至少锁定：

- Night 卡片继续使用本地化 note Key；
- 约束顺序为标题 → Dim level → 说明 → 卡片底部；
- 说明为多行且使用 Figma 的字号、行高；
- 不对 `LightSensorTargetSensorValueView`、Plane 输入 View 或 `updateCalibrationModeUI` 做结构性修改。

## 5. 预计涉及文件

| 文件 | 变更 |
| --- | --- |
| `SunSmart/Main/Group/View/LightSensorCalibrationModeView.swift` | 调整 Night 专属卡片的子视图顺序、约束与局部文字样式 |
| `SunSmart/en.lproj/Localizable.strings` | 更新 Night 卡片英文说明 |
| `SunSmart/zh-Hans.lproj/Localizable.strings` | 同步简体中文说明 |
| `Tests/Group/NightCalibrationWorkflowContractTests.swift` | 增加 Night 卡片结构和自适应约束回归检查 |

不计划修改 Controller、Sensor/Plane View、SDK、Assets、target 配置或业务逻辑。

## 6. 验证计划

1. 运行 `zsh scripts/check_night_calibration_workflow.sh`，验证 Night UI 合同与既有 Night 工作流约束；
2. 检查差异范围，确认没有修改 `LightSensorTargetSensorValueView`、Plane 输入 View 和 Controller 模式显隐逻辑，并运行 `git diff --check`；
3. 因本次同时修改共享 Swift 文件和本地化资源，分别对 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 执行 generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 构建；不使用 Simulator；
4. 在真实 iOS 设备上进入 Calibration 页面进行布局验收：
   - `Night Cal.` 中标题下直接显示 Dim level；
   - 说明位于 Dim level 下方，英文内容完整且不截断；
   - 切换英文与简体中文、改变可用宽度或字体布局后，卡片高度随说明内容自适应，无重叠、截断和异常空白；
   - Dim level 的减号、滑条、加号、数值更新和触摸区域保持正常；
   - 切换到 `Sensor Cal.`、`Plane Cal.` 前后截图对比，UI 无变化。

当前通过 `xcrun xctrace list devices` 检查未发现可用真实设备。因此实施后可以先完成合同测试、差异检查和四个 target 的 unsigned 构建，但真实设备 UI 验收需要在设备可用时补充；在此之前不会把静态检查或编译通过表述为完整 UI 验收。

## 7. 验收标准

- 仅 `Night Cal.` 未完成态的 `Target Night Brightness` 卡片发生变化；
- 卡片顺序严格为标题 → Dim level → 指定说明；
- 英文说明与需求逐字一致，简体中文同步国际化；
- 卡片高度不固定，说明完整显示并自动撑高卡片；
- `Sensor Cal.`、`Plane Cal.` 的结构、样式、间距和交互均不变；
- 既有用户工作区改动得到保留。
