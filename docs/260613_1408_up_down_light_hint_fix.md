# UpDownLightView hint 与 0% 亮度修复说明

## 背景

Up/down light 顶部控件 `UpDownLightView` 在测试中发现以下问题：

- 色温 50% 左右时，hint 叠加效果与普通 light control page 不一致。
- upRatio 或 downRatio 为 0% 时，对应的上下发光图片仍可能显示。
- 亮度 0% 或 Off 时，上下发光图片没有按 upRatio/downRatio 计算透明度。
- 亮度调到 0% 后，再点击 OnOff button 或 `UpDownLightView`，需要发送 On 命令并让本地 UI 同步为 On。
- 仅亮度模式下，亮度大于 0% 时不应使用 50% CCT tint，应保持普通 light control page 的原图色倾向。

## 根因

普通 light control page 的顶部灯效分为主图片层和灰色 hint 层：

- On 且有亮度时，主图片 alpha 为 `0.5 + brightness / 200`。
- 支持 CCT 且色温在 `45...55` 时，主图片 alpha 强制为 `1`，灰色 hint 层 alpha 为 `0.5`。
- 仅亮度模式不使用 `Node.getCctMixColor(50)`，而是使用资源原图。
- Off 时使用 off 背景图样式。

`UpDownLightView` 之前只对主色层使用了 `upRatio/downRatio * brightness`，但色温 50% 附近的灰色 hint 层没有乘 ratio；Off 分支还把上下图片 alpha 固定为 `1`。因此在 ratio 为 0 或较低时，仍然会看到不符合预期的 hint/灰色显示。

另外，控制器在亮度滑到 0% 时会把 `node.isOn` 置为 `false`，如果此时又把 0 亮度写入 `trunOffLightness`，下一次开灯可能恢复到 0，导致 UI 仍按 Off 绘制。

## 修复策略

- `UpDownLightView.Configuration` 增加 `supportsCCT`，让 view 区分 CCT 模式和仅亮度模式。
- CCT 模式复用普通 light control page 的主图片 alpha 与灰色 hint 层规则。
- 仅亮度模式使用 `up cct image` / `down cct image` 原图，不再用 50% CCT tint。
- 所有上下图片层和灰色 hint 层都乘以对应的 `upRatio/downRatio`，确保 0% 时完全透明。
- Off 或 brightness 为 0 时，使用灰色 tint，并按 `upRatio/downRatio` 展示透明度。
- `onoffAction` 开灯时，如果保存的 `trunOffLightness` 为 0，则回退到 `node.lightnessRange.upperBound`。
- 关灯或亮度滑到 0% 时，只在当前 `node.lightness > 0` 时保存 `trunOffLightness`，避免覆盖为 0。
- Up/down light 顶部开关状态按 `node.isOn` 展示；普通灯仍保持原来的 `node.isOn && node.lightness > 0` 展示逻辑。

## 验证重点

- 色温 45...55、up/down 为 0/100、50/50、100/0 时，0% 一侧不可见。
- 色温非中心值时，上下图片颜色跟随 CCT tint，透明度随亮度和 ratio 变化。
- 仅亮度模式亮度大于 0% 时，颜色保持原图效果，不被 50% CCT tint 成白色。
- 亮度 0% 或 Off 时，上下图片使用灰色 off 样式，并按 ratio 显示。
- 亮度 0% 后点击 OnOff button 或 `UpDownLightView`，发送 On 命令，本地 UI 立即切到 On。
