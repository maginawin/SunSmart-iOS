# Up Down Light 顶部 OnOff 控件设计

## 背景

当前单灯控制页顶部用 `lightGrayBgView`、`lightBgView`、`lightImageBtn` 组合展示灯的 OnOff、亮度和色温效果。启用 Tunable White 后，Color temp 滑条会先更新本地 `node.temperature`，再通过 `updateData(refreshControlPanel: false)` 立即刷新顶部背景 tint，不需要等待设备回包。

Up Down Light 设备需要保留这条即时反馈链路，但顶部视觉需要改成上下发光结构。目标设备判定为 `CID 0x0A78` 且 `PID 0x2491`，其他灯类型保持现状。

## Figma 对齐

Figma 节点：`124:4796`，名称为 `up down cct button - on`，整体尺寸为 `210 x 200`。

结构和尺寸如下：

- `up cct image`：`x=5, y=0, width=200, height=94`
- `down cct image`：视觉位置为 `x=5, y=106, width=200, height=94`
- 上下图片中间间隔：`12`
- `up down cct separator image`：`x=0, y=96, width=210, height=8`
- `up cct tag`：`x=73, y=62, width=64, height=24`
- `down cct tag`：`x=73, y=114, width=64, height=24`

tag 样式：

- 背景色：`rgba(255,255,255,0.75)`
- 圆角：`10`
- 文本颜色：`#272536`
- 文本字号：`12`
- icon 尺寸约 `6 x 8`
- value label 尺寸约 `36 x 17`，相对 tag 中心向右偏移约 `6`

本地资源已包含对应图片：

- `up cct image`
- `down cct image`
- `up down cct separator image`
- `up cct tag icon`
- `down cct tag icon`
- `up down cct image`

其中 `up down cct image` 是完整组合参考图，不作为主要实现资源。实现应使用上下两张独立图片，才能分别按 up/down ratio 和 brightness 调整透明度。

## 设计方案

新增 `UpDownLightView` 作为独立顶部控件，只在 Up Down Light 设备上使用。

`UpDownLightView` 的职责：

- 展示上半区发光图。
- 展示下半区发光图。
- 展示中间 separator。
- 展示 up/down 百分比 tag。
- 处理整块点击并回调外层切换 OnOff。
- 根据亮度、色温、upRatio、downRatio 更新视觉状态。

`DeviceLightViewController` 的职责保持为状态编排：

- 普通灯继续使用 `lightGrayBgView + lightBgView + lightImageBtn`。
- `node.supportsUpDownRatioControl == true` 时显示 `UpDownLightView`，隐藏旧三件套。
- emergency sign 保持现状，不走 `UpDownLightView`。
- slider、quick button、设备回包仍统一调用 `updateData(...)` 刷新页面。

## 布局规则

iPhone 上 `UpDownLightView` 外层尺寸为 `210 x 200`，整体 centerX 与旧 `lightBgView` 对齐，top 与旧 `lightGrayBgView` 一致。

内部布局按 Figma 固定比例：

- 主体上下发光图片位于内部 `x=5` 的 `200 x 200` 区域。
- 上图贴顶部，高度 `94`。
- 下图贴底部，高度 `94`。
- 上下图之间保留 `12` 间隔。
- separator 使用 `210 x 8`，水平占满外层，`y=96`。
- up tag 使用 `64 x 24`，水平居中，`y=62`。
- down tag 使用 `64 x 24`，水平居中，`y=114`。

iPad 使用与当前旧灯图一致的放大策略：以旧高度 `238` 为基准，按 Figma 外层比例 `210 / 200` 等比放大宽度和内部尺寸。

## 状态与视觉规则

`UpDownLightView` 不显示原来的 `lightImageBtn` 开关图标。整个 view 都可以点击切换设备 OnOff。

tag 始终显示，包括灯灭状态。tag 展示配置比例，不表示当前是否亮灯：

- up tag 文案：`"\(upRatio)%"`
- down tag 文案：`"\(downRatio)%"`

色温 hint 复用现有规则：

- 使用 `node.getEffectiveTemperature100(temperature: node.temperature)` 得到色温百分比。
- 使用 `Node.getCctMixColor(temperature100:)` 得到 tint color。
- 单亮度模式和色温模式的 hint 规则与现有 light control page 保持一致。

亮灯时透明度：

- `upAlpha = CGFloat(upRatio) * CGFloat(brightnessPercent) / 10000.0`
- `downAlpha = CGFloat(downRatio) * CGFloat(brightnessPercent) / 10000.0`

灭灯时：

- 上下发光图片仍保持显示，但不再使用亮灯状态的 brightness/ratio alpha。
- 使用普通 light off 的 hint/tint 样式处理 `up cct image` 和 `down cct image`，使视觉效果与当前普通 light off 背景一致。
- separator 保持显示。
- up/down tag 保持显示。

接近白光的可见性需要保留现有灰底补偿思路。实现时可在 `UpDownLightView` 内部为上下半区增加灰底图片层，使用与现有 `lightGrayBgView` 相同的白光区间判断，避免 50% 色温附近发光图和背景过近导致边界不清。

## 数据流

现有即时刷新链路保持不变：

1. brightness slider 改变时，`applyBrightnessValue(...)` 更新 `node.lightness` 和 `node.isOn`。
2. CCT slider 改变时，`applyCCTValue(...)` 更新 `node.temperature`。
3. up/down ratio slider 改变时，更新 `node.upRatio`。
4. 上述变更都通过 `updateData(refreshControlPanel: false)` 刷新顶部状态。
5. 设备命令仍由现有 throttle 回调发送。
6. 设备回包后仍通过 `meshNetworkManager(...)` 再次触发 `updateData()`。

`UpDownLightView` 只消费本地状态，不直接发送 Mesh 命令。

## 边界

- 只影响单灯控制页。
- 只影响 `CID 0x0A78 / PID 0x2491`。
- 不改变普通灯、DALI 控制页、group 控制页、emergency sign 页面。
- 不改变 up/down ratio 的存储方式；继续使用 `Node.PreConfiguration.upRatio`。
- 不新增 Auth 信息。
- 不调整 target 配置或依赖。

## 验证

实现后需要验证：

- 普通 tunable white 灯仍使用旧顶部 OnOff 控件。
- `CID 0x0A78 / PID 0x2491` 使用新的 `UpDownLightView`。
- brightness slider 改变时，上下发光透明度即时变化。
- Color temp slider 改变时，上下发光颜色即时变化。
- up/down ratio slider 改变时，tag 文案和上下发光透明度即时变化。
- 灯灭后 tag 仍显示，上下发光图片切换为普通 light off 的 hint/tint 样式。
- 点击 `UpDownLightView` 能切换 OnOff。
- iPhoneOS 构建通过：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
