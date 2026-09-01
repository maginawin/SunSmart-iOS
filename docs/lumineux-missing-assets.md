# Lumineux 资源接入与待提供清单

核对日期：2026-09-01。本清单只记录当前 Lumineux catalog 的资源覆盖与仍待提供项；资源按 SLGSync 的十二个业务分组保存，分组仅用于定位，不能据此推断复用或复制 SunSmart 图片。

## new3 Retina 接入

- 本轮把 28 对用户提供的原始 2x/3x PNG 映射为 29 个同名 Lumineux 资源；`button/Group 160` 分别用于 `distributor_nodes_highlight` 与 `updatating_nodes`，两组保留相同 PNG 字节。
- 每个新增 imageset 均只有 universal 1x 空槽以及原始 2x/3x 文件。没有生成 1x PNG，也没有缩放、重新编码、改色或重绘。
- 源文件在 `Lumineux/DesignAssets/Provided/<group>/`；catalog 中对应文件与源文件逐字节相同。完整映射、像素尺寸与 SHA-256 由 `Tests/Branding/LumineuxAssetTests.swift` 固定。
- 本轮明确不导入四对素材：根目录 `Group 160`、`icon/Nav`、`images/download`、`Proximity/images/数据表`；也不导入 `.DS_Store` 或任何 `FireAlarm1.5` 内容。不得将 `icon/space_device` 缩放后当作 `energy_light` 或 `distributor_single_device_highlight`，也不从 iPhone 图表生成 `_ipad` 资源。
- 未修改生产 Swift、Xcode 工程、合并脚本或依赖锁定。Lumineux 继续在构建期将 Common catalog 复制到 `DERIVED_FILE_DIR`，再以完整 Lumineux asset set 覆盖同名资源。

## 当前数量

| 项目 | 数量 |
| --- | ---: |
| Lumineux source catalog | 121 |
| SLGSync non-Fire covered | 83 / 94 |
| SLGSync non-Fire missing | 11 |
| additional packaged assets | 33 |
| provided total | 116 |
| merged catalog | 695 = 121 Lumineux + 574 Common |

其中 121 组为 119 个 imageset 加 `AppIcon`、`AccentColor`；116 为 83 个已覆盖的非 Fire 资源加 33 个额外已打包资源。上述 catalog 合并数是 Task 6 的构建验收合同，尚不能替代本次构建产物检查。

## 待提供或确认沿用

以下是仅剩的 11 组非 `FireAlarm1.5` 待提供资源。请提供 Lumineux 设计节点/导出包，或明确标记“沿用原图”；在确认前继续保留现有共享图片，不用 SLG 绿色资源替代，也不在共享 Swift 中自动换色。

| 分类 | 待提供资源 |
| --- | --- |
| Energy | `energy_light` |
| Firmware | `distributor_single_device_highlight` |
| Group | `auto_big`、`member_add`、`switch_save_un` |
| Profile | `profile_chart_daylight_ipad`、`profile_chart_manual_control_ipad`、`profile_chart_occupancy_daylight_ipad`、`profile_chart_occupancy_ipad`、`profile_chart_occupancy_standby`、`profile_chart_occupancy_standby_ipad` |

## 运行时与验证边界

`testProvidedNew3RetinaAssetsFitProductionControls()` 覆盖 29 个资源的独立 Lumineux source 比对和真实生产容器。`value_buoy` 在实际发送 slider `valueChanged` 后严格检查其布局。`daylight_scheme4...7` 的四个 `DaylightSensorInstructionsViewCell` 有已知的 2.934pt 竖向 hugging 歧义；按已确认边界不修改生产 Swift，测试改为严格断言独立来源、可见性、具体 containment 与截图，而不对这四个 cell 使用通用 `hasAmbiguousLayout == false` 断言。其他组件仍保持严格歧义检查。

静态/脚本回归命令、六组合 UIKit 矩阵和正常 DerivedData 签名构建的执行方法与验收项见 `Tests/Branding/README.md`。Task 5 的六组合人工审图与 Task 6 的构建/签名/合并 catalog 检查均尚待执行，不能以此前批次的结果替代。
