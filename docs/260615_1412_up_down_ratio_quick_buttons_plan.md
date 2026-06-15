# Up/Down Ratio Quick Buttons 更新计划

## 目标

将 `UpDownRatioQuickButtonsView` 中规划的 quick buttons 分组从当前 `100/0, 75/25, 50/50, 25/75, 0/100` 更新为：

- `100/0`
- `70/30`
- `50/50`
- `30/70`
- `0/100`

## 当前代码事实

- 目标实现位于 `SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift`。
- `UpDownRatioQuickButtonsView` 当前通过 `private let values = [100, 75, 50, 25, 0]` 定义 up ratio 数值。
- button 文案由 `"\(value)/\(100 - value)"` 自动生成。
- 点击 quick button 后传出 up ratio value，再由 `DeviceUpDownRatioControlView.setUpValue(_:notifyChanging:notifyChanged:)` 同步 slider、顶部 label、选中态和回调。
- 当前工作区已有 `SunSmart/Main/Group/Controller/GroupViewController.swift` 未提交修改，本次计划不触碰该文件。

## 影响范围

### 需要修改

- `SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift`
  - 只修改 `UpDownRatioQuickButtonsView.values`，将 `[100, 75, 50, 25, 0]` 改为 `[100, 70, 50, 30, 0]`。

### 不修改

- 不修改 slider 取值范围，仍为 `0...100`。
- 不修改 `upValue` / `downValue` 的换算逻辑。
- 不修改 button 样式、尺寸、间距、选中态颜色。
- 不修改 Device / Group 控制器事件接线。
- 不修改本地化、资源、target 配置或依赖。
- 不触碰当前已有脏改的 `GroupViewController.swift`。

## 实施步骤

1. 修改 `UpDownRatioQuickButtonsView.values` 为 `[100, 70, 50, 30, 0]`。
2. 检查 `configure(selectedValue:)` 不需要额外调整：
   - `100`、`70`、`50`、`30`、`0` 会正常匹配选中态。
   - 非 quick button 数值继续不高亮任何 button，保持当前行为。
3. 检查 button title 自动生成结果：
   - `100 -> 100/0`
   - `70 -> 70/30`
   - `50 -> 50/50`
   - `30 -> 30/70`
   - `0 -> 0/100`
4. 运行 `git diff --check`，确认没有 whitespace 问题。
5. 运行 iOS 构建校验：
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 验收标准

- Up/Down Ratio quick buttons 从左到右显示为 `100/0`、`70/30`、`50/50`、`30/70`、`0/100`。
- 点击 `70/30` 时，传出的 up ratio 为 `70`，顶部 label 和 slider 同步为 `70/30`。
- 点击 `30/70` 时，传出的 up ratio 为 `30`，顶部 label 和 slider 同步为 `30/70`。
- 通过 slider 滑到非 quick button 数值时，不选中任何 quick button，保持现有行为。
- iPhoneOS 构建通过，或失败原因与本次改动文件无关且有明确证据。

## 待确认

请确认是否按以上计划执行代码修改。
