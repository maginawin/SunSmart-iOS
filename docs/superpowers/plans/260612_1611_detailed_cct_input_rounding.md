# Detailed CCT Input Rounding Plan

## 背景

用户要求在 Light Control page 和 Group Control page 中，当选择 detailed CCT 滑条后，点击右侧色温值按钮弹出的输入框在 CONFIRM 时按以下规则处理色温值：

- 色温值只能是 10 的倍数。
- 输入值按四舍五入计算成 10 的倍数。
- 若结果大于最大支持值，则按最大值计算。
- 若结果小于最小支持值，则按最小值计算。

## 已核查事实

- 右侧色温值按钮来自 `DeviceLightControlPanelView` 的 detailed CCT view，点击后通过 `editCCTRequested` 回调分别进入设备页和组页。
- 设备页入口：
  - `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - `showCCTInputAlert()` 调用 `showIntegerInputAlert(...)`。
  - 当前 `showIntegerInputAlert` 只把输入值 clamp 到 `controlPanelView.currentCCTRange`，没有按 10 取整。
- 组页入口：
  - `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - `showGroupCCTInputAlert()` 调用本文件内的 `showIntegerInputAlert(...)`。
  - 当前同样只做 range clamp，没有按 10 取整。
- CCT slider 本身已设置 step 为 10：
  - `DeviceLightControlPanelView.setupUI()` 中 simple/detailed CCT slider 都设置 `step = 10`。
  - `CustomDeviceSlider.value` 已用 `roundf(value / step) * step` 实现滑动取整。
- Device Parameter 的绝对色温范围已有类似算法：
  - `DeviceParameterCctRangeData.roundedToStep(_:)` 使用 `(value + step / 2) / step * step`。
- 当前仓库没有发现可直接复用的单元测试 target，验证应以输入案例核对和 iPhoneOS build 为主。

## 根因判断

问题真实存在：滑条路径已经会按 10 取整，但手动输入路径绕过了 slider step 逻辑，只做了范围夹紧。因此 detailed CCT 输入框可能把非 10 倍数的色温值写入 UI、设备状态并下发到 Mesh。

## 方案选择

### 方案 A：只在两个 CCT confirm 回调里分别取整

优点是改动最小；缺点是设备页和组页会各自复制算法，后续容易再次不一致。

### 方案 B：在现有控制面板相关代码中增加一个 CCT 输入标准化 helper

推荐此方案。把“手动输入 CCT 值如何标准化”的规则集中到一个小 helper 中，设备页和组页都调用同一规则。helper 只处理手动输入值，不改变 slider、quick buttons、brightness 输入和其他页面行为。

### 方案 C：修改 `showIntegerInputAlert` 为通用 step 输入框

不推荐。它现在同时服务 brightness 和 CCT，扩展成通用 step 输入容易扩大行为面，还会把 CCT 特有规则带到普通整数输入组件中。

## 推荐实现方案

采用方案 B，改动范围控制在以下文件：

- `SunSmart/Main/Device/View/DeviceLightControlPanelView.swift`
  - 增加 CCT 手动输入标准化 helper。
  - 规则顺序为：先四舍五入到 10 的倍数，再 clamp 到传入的支持范围。
  - 不改变 `configure(...)`、`setCCTValue(...)`、slider 事件和 quick button 事件的外部语义。
- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 在 `showCCTInputAlert()` 的 CONFIRM 回调中，对原始输入值调用 helper。
  - 用标准化后的值更新 `controlPanelView`、`node.temperature`，并下发 `MeshAPI.setNodeColorTemperatureState(...)`。
  - brightness 输入保持现状。
- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - 在 `showGroupCCTInputAlert()` 的 CONFIRM 回调中，对原始输入值调用同一个 helper。
  - 用标准化后的值调用 `applyGroupCCTValue(...)`、更新 control panel，并下发 group CCT。
  - `showGroupCCTLimitMessageIfNeeded(...)` 的判断目标调整为标准化前后是否发生范围夹紧，或标准化后的目标是否超出部分成员设备范围，避免 `6504 -> 6500` 这种四舍五入后仍合法的输入误报 limit。

## 处理顺序

1. 用户输入整数。
2. 对输入值四舍五入到最近的 10 倍数。
3. 将四舍五入结果按当前页面支持范围 clamp。
4. 用最终结果更新 UI 状态、本地模型和 Mesh 下发值。

示例：

| 支持范围 | 输入 | 四舍五入结果 | 最终值 |
| --- | ---: | ---: | ---: |
| 2700...6500 | 3123 | 3120 | 3120 |
| 2700...6500 | 3125 | 3130 | 3130 |
| 2700...6500 | 2694 | 2690 | 2700 |
| 2700...6500 | 6504 | 6500 | 6500 |
| 2700...6500 | 6506 | 6510 | 6500 |

## 不纳入范围

- 不修改 simple CCT slider 行为。
- 不修改 CCT quick button 值和显示。
- 不修改 brightness 输入。
- 不新增本地化文案。
- 不修改 Auth、target 配置、资源或依赖。
- 不改 SDK。

## 验证计划

1. 静态检查设备页和组页的手动输入路径都调用同一标准化 helper。
2. 用代码级输入案例核对：
   - 3123 -> 3120
   - 3125 -> 3130
   - 2694 -> range lowerBound
   - 6504 -> 6500
   - 6506 -> range upperBound
3. 确认 brightness 输入路径仍只按原逻辑 clamp，不受 CCT 取整影响。
4. 确认 slider 路径仍由 `CustomDeviceSlider.step = 10` 控制，不出现重复下发或回调变化。
5. 运行 iPhoneOS 构建：
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 待确认点

推荐按“先四舍五入到 10，再按当前支持范围 clamp”的方案实施。若最大/最小支持值理论上不是 10 的倍数，则最终值会按需求优先落到支持范围边界；当前项目的 CCT 范围配置路径看起来也是按 10 步进维护。

