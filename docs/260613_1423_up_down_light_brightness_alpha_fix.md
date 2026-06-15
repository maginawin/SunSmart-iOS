# UpDownLightView 亮度透明度与 tag 百分比修复

## 问题

测试发现 `UpDownLightView` 还有两个显示问题：

- 色温在 `45...55` 附近时，调节亮度不会影响 up/down 主图片透明度。
- `up cct tag` 和 `down cct tag` 显示的是原始 up/down ratio，没有按当前亮度百分比重新计算。

## 根因

上一轮修复为了保留中心色温的灰色 hint 层，在 `45...55` 分支中把主图片 `imageAlpha` 固定为 `1`。这会让中心色温时的 up/down 主图片不再响应亮度变化，而其他色温值仍使用 `0.5 + brightness / 200`。

tag 文字原先直接展示 `upRatio` 和 `downRatio`，没有乘以 `brightnessPercent`。

## 修复

- 中心色温只保留 `grayAlpha = 0.5` 的 hint 层，不再覆盖主图片 `imageAlpha`。
- 主图片透明度在所有色温值下统一使用 `0.5 + brightness / 200`，再乘以对应的 up/down ratio。
- tag 展示值改为 `ratio * brightnessPercent / 100`，使用四舍五入并显示整数百分比。

## 示例

- up/down ratio 为 `50/50`，亮度为 `50%` 时：
  - up tag 显示 `25%`
  - down tag 显示 `25%`
- up/down ratio 为 `100/0`，亮度为 `33%` 时：
  - up tag 显示 `33%`
  - down tag 显示 `0%`
