# Lumineux Profile 与 Safe Mode 资源补充设计

## 目标

仅为 Lumineux 补入四组已确认的同名资源，使 Profile、定时选择、传感器状态和 Safe Mode 设备选择使用 Lumineux 设计。保持现有构建期 Asset Catalog 合并机制，不修改共享业务代码、SunSmart／SLGSync 资源、其他 target、服务器配置或品牌运行逻辑。

## 已确认资源

| 资源名 | Figma 节点 | iOS 逻辑尺寸 | 处理方式 |
| --- | --- | --- | --- |
| `profile_chart_occupancy_daylight` | `16001:174597` | 212 × 234pt | 使用完整图表节点，生成 1x／2x／3x |
| `schedule_target_select` | `16001:174651` | 30 × 30pt | 使用完整选中态节点，生成 1x／2x／3x |
| `sensor_move` | `16001:174616` | 20 × 20pt | 使用完整传感器图标节点，生成 1x／2x／3x |
| `device_select` | `0:17954` | 30 × 30pt | 保留 Figma 18 × 18pt 图形，将其居中放入透明 30pt 画布，再生成 1x／2x／3x |

四组设计色均以 Figma 导出为准；涉及品牌色的图形使用 `#4D738A`。不手绘路径、不基于 SunSmart／SLGSync 图片改色，也不把页面文字或动态状态烘焙进图片。

## 方案选择

采用 Lumineux 独立同名覆盖：原始 Figma 矢量保存在 `Lumineux/DesignAssets/Figma`，倍率 PNG 位于 `Lumineux/Assets-Lumineux.xcassets`，并在 `Lumineux/DesignAssets/icon-manifest.json` 记录节点、尺寸和来源。构建时由现有合并器用这四组完整 asset set 覆盖公共同名资源。

不采用以下方案：

- 运行时 `withTintColor` 或修改 `UIImage(named:)` 调用，因为会改变共享 Swift 行为并扩大回归范围。
- 直接修改 `SunSmart/Assets.xcassets`，因为会影响 SunSmart 及其他共用公共图库的 target。
- 复用 SLGSync 绿色资源或根据视觉相似度猜测资源名，因为不能保证 Lumineux 品牌色与真实调用一致。

## 数据流与边界

Figma 节点是唯一设计输入。资源生成只创建四个 Lumineux `.imageset` 及其 1x／2x／3x PNG，并更新 Lumineux manifest、品牌资源测试和缺失资源清单。公共 catalog、共享 UIKit 页面、颜色常量和现有合并脚本逻辑保持不变。

`device_select` 的 Figma 节点本身是 18 × 18pt，而项目同名资源及 Safe Mode 列表均按 30 × 30pt 使用；因此只增加透明留白，不缩放或重绘内部图形。其他三组按完整节点的原始画布生成，不做裁切。

## 验证标准

1. 先增加会失败的品牌资源测试，固定四个资源名、Figma 节点、逻辑尺寸、倍率完整性及来源文件。
2. 生成后验证每组 `Contents.json` 与 1x／2x／3x 尺寸正确，`device_select` 的 18pt 内容在 30pt 画布中居中。
3. 运行 Lumineux 配置检查和资源合并测试，确认四组来自 Lumineux，未覆盖资源仍来自公共 catalog，源 catalog 不被修改。
4. 使用真实 UIKit 调用点验证：Profile 图表、定时选中态、Group 传感器状态和 Safe Mode 设备选择；至少覆盖 iPhone 16 的英文与简体中文布局，并检查截图无模糊、裁切、错图或约束问题。
5. 构建 Lumineux target，确认 Asset Catalog 编译、Wen Xu 签名和现有构建期合并流程正常；同时执行 SunSmart Debug 回归，确认公共品牌未被改变。

## 清单变化

原 SLGSync 范围的 60 组待补清单移除 `profile_chart_occupancy_daylight`、`schedule_target_select` 和 `device_select`，剩余 57 组。`sensor_move` 是此前只按 SLGSync 覆盖范围统计时遗漏的额外 Lumineux 品牌资源，不从原 60 组中扣减。
