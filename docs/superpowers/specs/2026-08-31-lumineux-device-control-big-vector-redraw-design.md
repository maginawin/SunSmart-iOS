# Lumineux Device Control Big 图标矢量重绘设计

## 目标

以当前已确认正确的 `device_control_off` 与 `device_control_on` 40pt Retina 图标为视觉基准，生成对应的 56pt `_big` 图标，替换 Lumineux 现有错误资源。生成过程不得对 80/120px PNG 做插值放大。

## 方案比较

1. 参数化矢量重绘：从正确普通版提取颜色、圆心、半径、线宽和电源符号路径，在目标画布直接绘制。输出清晰、几何稳定，推荐采用。
2. 自动轮廓追踪：把 PNG 转成路径后再缩放。能避免普通位图缩放，但容易引入多余节点和不规则抗锯齿边界。
3. 高质量位图放大：使用 Lanczos 等算法从 120px 放大到 168px。实现最简单，但仍属于插值放大，不满足本次约束。

采用方案 1。

## 资源合同

- `device_control_off_big`：透明背景、Lumineux 蓝色外圆描边和蓝色电源符号。
- `device_control_on_big`：Lumineux 蓝色实心圆和白色电源符号。
- 视觉结构相对普通版整体按 `56 / 40 = 1.4` 等比例放大，包括外圆、内部符号和线宽。
- 分别直接绘制 `112×112` 的 2x PNG 和 `168×168` 的 3x PNG；两套倍率不得互相缩放生成。
- 与正确普通版保持相同的 sRGB 色值、透明背景语义、圆角线帽和抗锯齿风格。
- 删除旧的错误 1x PNG，并在 `Contents.json` 中保留不带文件名的 universal 1x 空槽，与当前普通版资源合同一致。

## 修改范围

只修改以下两个 imageset，不修改生产 Swift、其他 Device/Group 资源或用户现有改动：

- `Lumineux/Assets-Lumineux.xcassets/Device/device_control_off_big.imageset`
- `Lumineux/Assets-Lumineux.xcassets/Device/device_control_on_big.imageset`

## 验证

- 自动检查 2x/3x 画布分别为 112px 和 168px，PNG 为 RGBA，1x 槽为空。
- 检查关键颜色与普通版一致，透明/实心状态正确。
- 在透明背景上按原始尺寸检查边缘、圆度、线宽、圆角端点和中心对齐，不出现插值模糊或锯齿异常。
- 运行 Lumineux 资源合同测试和覆盖 iPad `_big` 资源的 focused UIKit 测试，并人工检查实际布局截图。
- 保留用户现有暂存改动，不提交、不推送本轮生成资源，除非用户另行要求。
