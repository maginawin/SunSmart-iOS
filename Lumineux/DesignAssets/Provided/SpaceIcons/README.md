# Lumineux Space 图标

来源：Figma `P4AaSxu8SJe2Tf2gpyTFT9` 的 `18007:18109`，共 60 个组件，按 `客户_Scene01` 至 `客户_Scene60` 顺序对应 `space_picture_1` 至 `space_picture_60`。

此目录保留 Figma 中 500×500 的原始 PNG image fill，逐文件 SHA-256、组件节点和图层节点记录在 `../../space-icons.json`。图片自带的英文名称属于原始图稿，保持原样。

`scripts/prepare_lumineux_space_icons.swift` 按设计组件打包：120×96pt 白色圆角画布（圆角 10pt），原图居中显示为 96×96pt，左右各留 12pt；输出 240×192 的 2x PNG 和 360×288 的 3x PNG，1x 槽位为空。只缩小原始素材，不放大、不重绘、不改色。

Lumineux 使用同名 catalog 覆盖并通过 `SpaceIconCount=60` 开放所有选项。其他品牌未设置该值，继续显示原来的 24 个选项。已有 `imageId` 和索引加 1 的保存规则不变。

检查入口：`Tests/Branding/LumineuxSpaceIconTests.rb`、`LumineuxAssetTests.swift`，以及真实 UIKit 测试 `testSpaceIconPickerShowsAllFigmaIconsAndSavesLastSelection`。
