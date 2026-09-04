# Lumineux new3 Retina 资源接入设计

## 背景与目标

用户在 `/Users/sr/Documents/SunSmart/assets/new3` 提供了新一批 Lumineux 2x/3x PNG。本轮继续使用此前 Common、Device、Energy、Group、Path Retina 资源的接入方式：只接入能通过文件语义、像素画布、SLGSync 同名资源轮廓和生产调用点交叉确认的缺失资源；原始 PNG 字节保持不变；asset catalog 保留空的 universal 1x 槽位，不生成 1x 文件。

`FireAlarm1.5` 完全不在本轮范围。已接入资源不因 `new3` 中的重复导出而覆盖；无法唯一映射到当前缺失资源的文件也不导入。

## 已确认接入范围

本轮从 28 对源 PNG 接入 29 个同名资源。`button/Group 160` 同时用于 `distributor_nodes_highlight` 与 `updatating_nodes`；SLGSync 中这两个 imageset 的 2x/3x PNG 本来就逐字节相同，因此 Lumineux 也以同一对用户源文件生成两个同名覆盖。

### Common（1 组）

| new3 用户文件（省略倍率后缀） | 最终资源名 | 2x / 3x 像素 |
| --- | --- | --- |
| `Proximity/images/Controls/Edit Menus/Single Action` | `value_buoy` | 100 × 73 / 150 × 109 |

`value_buoy` 的两个倍率画布存在设计源自身的取整差异，不能强制改成同一整数逻辑高度；测试固定原始像素和 SHA-256。生产 `BuoySliderView` 继续通过 cap insets 拉伸图片，不修改调用代码。

### Firmware（9 组）

| new3 用户文件（省略倍率后缀） | 最终资源名 | 2x / 3x 像素 |
| --- | --- | --- |
| `button/Group 160` | `distributor_nodes_highlight` | 72 × 40 / 108 × 60 |
| `button/Group 160` | `updatating_nodes` | 72 × 40 / 108 × 60 |
| `images/version` | `firmware_cloud_version` | 192 × 140 / 288 × 210 |
| `icon/images/download` | `initiator` | 60 × 60 / 90 × 90 |
| `Group 194` | `mesh_distributor_guide_4` | 528 × 108 / 792 × 162 |
| `Frame 161` | `mesh_upgrade_guide_1` | 344 × 202 / 516 × 303 |
| `Group 192` | `mesh_upgrade_guide_2` | 288 × 108 / 432 × 162 |
| `button/space_add_3` | `mesh_upgrade_guide_3` | 288 × 80 / 432 × 120 |
| `icon/space_device` | `single_device` | 60 × 60 / 90 × 90 |

### Profile（17 组）

| new3 用户文件（省略倍率后缀） | 最终资源名 | 2x / 3x 像素 |
| --- | --- | --- |
| `图表2` | `adjust_speed_fast` | 579 × 326 / 869 × 489 |
| `图表1` | `adjust_speed_slow` | 579 × 326 / 869 × 489 |
| `Scheme 4` | `daylight_scheme4` | 312 × 240 / 468 × 360 |
| `Scheme 5` | `daylight_scheme5` | 312 × 240 / 468 × 360 |
| `Scheme 6` | `daylight_scheme6` | 312 × 240 / 468 × 360 |
| `Scheme 7` | `daylight_scheme7` | 312 × 240 / 468 × 360 |
| `images/lightsensor20` | `daylight_standalone_sensor` | 40 × 40 / 60 × 60 |
| `Defined` | `power_state_defined` | 132 × 132 / 198 × 198 |
| `Off` | `power_state_off` | 132 × 132 / 198 × 198 |
| `Restore` | `power_state_restore` | 132 × 132 / 198 × 198 |
| `button/数据表` | `profile_chart_daylight` | 424 × 467 / 636 × 701 |
| `数据表` | `profile_chart_manual_control` | 424 × 467 / 636 × 701 |
| `Proximity/数据表` | `profile_chart_occupancy` | 424 × 467 / 636 × 701 |
| `Proximity/images/sensor_move` | `profile_person` | 40 × 40 / 60 × 60 |
| `images/sensor_move` | `profile_person_big` | 60 × 60 / 90 × 90 |
| `Group 116` | `profile_proximity_lighting` | 670 × 408 / 1005 × 612 |
| `Proximity/images/数据图表` | `sensor_manul_override_timeout` | 656 × 282 / 984 × 423 |

### Scene 与 Space（各 1 组）

| 分类 | new3 用户文件（省略倍率后缀） | 最终资源名 | 2x / 3x 像素 |
| --- | --- | --- | --- |
| Scene | `Proximity/images/Scene/images/编组` | `scene_data_add` | 48 × 48 / 72 × 72 |
| Space | `Proximity/images/Property 1=code2` | `locked` | 60 × 60 / 90 × 90 |

## 明确排除

- 跳过 `.DS_Store` 和任何 `FireAlarm1.5` 内容。
- 跳过 `icon/Nav`：图形轮廓精确对应已经接入的 `firmware_delete`。
- 跳过 `images/download`：图形轮廓精确对应已经接入的 `server_download`。
- 跳过 `Proximity/images/数据表`：图形轮廓精确对应已经接入的 `profile_chart_occupancy_daylight`。
- 跳过根目录 `Group 160`：其 54 × 30pt 画布没有准确的当前缺失资源映射。
- 不把 30pt 的 `icon/space_device` 缩小成 20pt 的 `energy_light` 或 `distributor_single_device_highlight`。
- 不把 iPhone 图表放大或拉伸成未提供的 iPad 图表。
- 不生成任何新的 `@1x.png`，不修改源 PNG 的像素、颜色、透明度、格式或元数据。

## 文件组织与构建数据流

每个源文件按最终资源名复制到 `Lumineux/DesignAssets/Provided/<业务分类>`，并以相同字节复制到 `Lumineux/Assets-Lumineux.xcassets/<业务分类>/<资源名>.imageset`。每份 `Contents.json` 恰有 universal 1x、2x、3x 三个条目；1x 条目不含 `filename`，2x/3x 指向按最终资源名保存的 PNG。

`Lumineux/DesignAssets/asset-groups.json` 新增 29 项分组映射。现有 `Merge Lumineux Assets` 构建阶段继续先复制 Common catalog，再用 Lumineux 完整 asset set 同名覆盖；不修改合并器、Xcode 工程配置或生产 Swift。

接入后的数量合同为：

- Lumineux 源 catalog：92 组增至 121 组，即 119 个 imageset、AppIcon、AccentColor。
- SLGSync 94 组非 FireAlarm 品牌范围：已覆盖 54 组增至 83 组，待补 40 组降至 11 组。
- 额外已打包资源维持 33 组；已提供资源总数由 87 组增至 116 组。
- 合并 catalog 仍为 695 组，其中 121 组由 Lumineux 同名覆盖，574 组保留 Common 资源。

## 生产调用点与 UI 边界

- Common：真实 `BuoySliderView` 加载并拉伸 `value_buoy`。
- Firmware：真实 `MeshFirmwareUpgradeHeaderView`、`MeshFirmwareListViewController`、`BleFirmwareUpdateViewController`、`FirmwareVersionViewController` 和 `MeshFirmwareUpgradeGuideView` 加载本轮图标及说明图。
- Profile：真实 Power State、Adjust Speed、Daylight Sensor、Manual Override、Proximity Lighting 指引与 Profile phase 视图加载本轮图片；iPad 仍回退到当前公共的 `_ipad` 资源。
- Scene：真实 `SceneAddDataListViewCell` 加载 `scene_data_add`。
- Space：真实 `SpacesViewCell` 加载 `locked`。

现有生产代码均继续使用 `UIImage(named:)`，Lumineux 构建期合并 catalog 自动完成同名覆盖。本轮不修改 `SunSmart/` 生产 Swift；若真实 UIKit 验证发现当前约束无法容纳新图，先停止并向用户报告，不自行调整布局。

## 测试与验收

实施遵循测试先行：

1. 先扩展 `LumineuxAssetTests.swift` 的分组、总数、源 SHA-256、精确像素、空 1x、catalog/source 字节一致性合同到 121 组，并确认测试因资源尚未接入而按预期失败。
2. 先扩展 `LumineuxRuntimeTests.swift` 与临时 reference catalog 到 121 组，使用真实生产页面/组件验证 29 个资源来自独立编译的 Lumineux catalog，检查图片 bounds、父视图包含关系、约束歧义和页面快照，并确认缺图阶段按预期失败。
3. 最小接入 29 个 imageset 后，运行素材、分组、合并器、生成器、Xcode 配置、Nordic SDK 依赖和 `git diff --check`。
4. 在 iPhone SE 3、iPhone 16、iPad Pro 11 M4 的 en-US 与 zh-Hans-CN 六种组合运行 focused UIKit 测试并人工检查全部新截图；编译通过不能替代布局检查。
5. 使用正常 `/Users/sr/Library/Developer/Xcode/DerivedData3` 路径构建 `SunSmart.xcworkspace` 的 Lumineux 真机 Debug，不更新依赖、不安装或启动 App；验证 `codesign --verify --deep --strict`、Bundle ID、签名 Team、695 组合并 catalog 和 121 组 Lumineux 覆盖。

## 完成后仍待提供的 11 组

| 分类 | 资源名 |
| --- | --- |
| Energy | `energy_light` |
| Firmware | `distributor_single_device_highlight` |
| Group | `auto_big`、`member_add`、`switch_save_un` |
| Profile | `profile_chart_daylight_ipad`、`profile_chart_manual_control_ipad`、`profile_chart_occupancy_daylight_ipad`、`profile_chart_occupancy_ipad`、`profile_chart_occupancy_standby`、`profile_chart_occupancy_standby_ipad` |

FireAlarm1.5 不纳入上述 11 组统计，也不在本轮更新其资源或清单状态。

## 文档与 Git 边界

完成后更新 `docs/lumineux-missing-assets.md` 和 `Tests/Branding/README.md`，记录 29 组映射、4 对排除素材、121/695 数量、focused UIKit 矩阵、截图审阅、正式构建与签名结果。

本设计文档按 brainstorming 流程单独本地提交。资源、测试、脚本和结果文档的实施改动保持未提交；除非用户后续明确要求，不提交、不推送，也不改动两个远程。
