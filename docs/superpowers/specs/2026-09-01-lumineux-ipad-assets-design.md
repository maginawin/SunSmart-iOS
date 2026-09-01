# Lumineux iPad 图片补齐设计

## 目标

为 Lumineux 补齐 iPad 运行路径实际加载的高清图片，不通过等比例拉伸或插值放大 iPhone PNG，保持现有品牌颜色、透明背景、线条锐度和布局语义。

## 输出范围

生成以下 7 个资源集的 @2x、@3x PNG，共 14 张图片：

- `auto_big`
- `profile_chart_daylight_ipad`
- `profile_chart_manual_control_ipad`
- `profile_chart_occupancy_ipad`
- `profile_chart_occupancy_daylight_ipad`
- `profile_chart_occupancy_standby`
- `profile_chart_occupancy_standby_ipad`

首轮输出放在独立交付目录中，并保留 `.imageset` 目录结构；未经用户后续确认，不写入 `Lumineux/Assets-Lumineux.xcassets`。

## 生成方式

### `auto_big`

- 使用工程内现有 `auto_big` 的 iPad 尺寸与轮廓作为几何模板。
- 使用 Lumineux `auto` 的蓝色、透明度和视觉风格作为品牌标准。
- 输出尺寸为 112×112 px（@2x）和 168×168 px（@3x）。

### Profile 图表

- 使用 SLGSync 已有的对应 iPad 图片作为宽屏几何模板，保留虚线网格、折线路径、人物位置及透明区域。
- 使用 Lumineux 对应 iPhone 图片作为内容和配色标准，不对 iPhone 图片做整体拉伸。
- 常规 iPad 图输出尺寸为 980×467 px（@2x）和 1470×701 px（@3x）；如果模板边界存在 1–3 px 的历史差异，统一到工程主资源的标准尺寸。

### Occupancy Standby

- Lumineux 缺少 `profile_chart_occupancy_standby` 的 iPhone 和 iPad 资源。
- 使用 SLGSync 对应 iPhone、iPad 图片作为几何模板。
- 使用 Lumineux 已有 `profile_chart_occupancy` 和 `profile_chart_occupancy_daylight` 的蓝色线条、人物和透明度作为品牌标准。
- iPhone 版输出尺寸为 424×467 px（@2x）和 636×701 px（@3x）；iPad 版使用 Profile iPad 标准尺寸。

## 质量约束

- 输出必须保留透明通道，不增加背景色。
- 虚线、折线、圆环、文字和人物边缘必须清晰，不出现插值模糊或光晕。
- @2x 与 @3x 分别按目标像素画布生成，不能由较小成品二次放大。
- 图形内容、节点顺序、人物位置与现有工程模板一致，不增加或删除元素。
- 不改变其他 Lumineux、SLGSync 或共享资源。

## 验证

- 检查每张 PNG 的像素尺寸、PNG 格式和 Alpha 通道。
- 按资源集逐张与几何模板叠加检查关键线段、虚线和人物位置。
- 将 @2x、@3x 图片以原始像素查看，确认边缘锐利且没有放大锯齿。
- 输出一张预览拼图供人工确认，并列出所有最终文件路径。
