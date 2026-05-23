# Change Control Page 选项间距修复计划

## 问题

`DeviceParameterChangeControlPageViewCell` 中已将约束改为：

`tunableWhiteButton.left = singleWhiteButton.right + 8`

但页面上 `Single White` 和 `Tunable White` 的视觉间距仍然明显大于 8。

## 根因

当前 8pt 约束控制的是两个 `UIControl` 容器的边界，不是两个文字 label 的边界。

每个选项内部结构是：

- `UIControl`
- 左侧 radio icon，宽高 30
- label
- button 内部左右 padding

因此从 `Single White` 文本右边到 `Tunable White` 文本左边，实际视觉距离至少包含：

- `singleWhiteLabel` 到 `singleWhiteButton.right` 的 8
- 两个 button 之间的 8
- `tunableWhiteButton.left` 到 `tunableWhiteIconView.left` 的 8
- `tunableWhiteIconView` 宽度 30
- `tunableWhiteIconView` 到 `tunableWhiteLabel.left` 的 4

合计约 58pt，再叠加 Auto Layout 对 `UIControl` 宽度的求解结果，所以看起来仍然很大。

## 修复方向

不要继续调 `tunableWhiteButton.left = singleWhiteButton.right + 8`，因为它不是用户视觉上要控制的距离。

建议把两个选项拆成内容驱动布局：

1. 让 `singleWhiteButton` 宽度由 `singleWhiteIconView + singleWhiteLabel + 内边距` 决定。
2. 让 `tunableWhiteButton.left` 约束到 `singleWhiteLabel.right`，并把间距设为 8。
3. `tunableWhiteIconView` 继续位于 `tunableWhiteButton` 内部左侧。

更稳妥的实现是新增两个 option content container：

- `singleWhiteContentView`
- `tunableWhiteContentView`

每个 content view 内部放 icon + label。然后约束：

- `singleWhiteContentView.left = optionsContainerView.left + 8`
- `tunableWhiteContentView.left = singleWhiteContentView.right + 8`
- 两个 button 作为透明 hit area 覆盖各自 content view，并适当扩大可点击区域

这样可明确保证视觉内容之间的距离是 8，同时不牺牲点击区域。

## 验证点

- 英文下 `Single White` 文本右边到 `Tunable White` 内容左边视觉距离约 8。
- 中文下 `单白光` 与 `可调白光` 不重叠。
- 两个选项整体仍然靠左。
- 点击 radio icon、文字和选项附近区域都能正常切换。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 通过。
