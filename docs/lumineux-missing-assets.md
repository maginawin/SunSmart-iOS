# Lumineux 资源接入与待提供清单

核对日期：2026-08-28。Lumineux 现使用专属构建期资源合并：公共 catalog 先复制到 `DERIVED_FILE_DIR`，再由 Lumineux 完整 asset set 覆盖同名资源，原生 actool 只编译这份生成 catalog。旧双 catalog 顺序方案已废弃；不使用运行时染色或改写共享图片调用。英文和简体中文三设备 UIKit 矩阵、截图审阅、Release 签名与 SunSmart Debug 回归均已完成。

## 本次已下载并打包

- 57 组同名图标：原有 54 组（Tab 10、导航 10、设备/分组/场景按钮与尺寸变体 26、收藏/加载/等待/能耗 8），加本轮页面稿补充的 3 组。
- 首批原稿来自四个用户提供的 Figma 框架：[Tab](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=9338-252618)、[导航](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=9338-259821)、[按钮](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=9338-290273)、[其他](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=1038-38735)。
- 43 份完整节点矢量导出保存在 `Lumineux/DesignAssets/Figma`；资源名、节点 ID、原有 iOS 逻辑尺寸逐项记录在 `Lumineux/DesignAssets/icon-manifest.json`。仅机械缩放生成 1x/2x/3x PNG，不重绘或改色。
- 两份已提供 Logo 保留为源文件；catalog 使用 `AppIcon`、`launch_logo`（88pt）、`launch_logo_120`（120pt），`AccentColor` 为 `#4D738A`。两组显示 Logo 现统一从 `app_logo_1024.png` 高清原图缩小生成，88px 小图仅存档、不再放大使用；避免原小图自带的灰色圆角和细节模糊。AppIcon 仅派生文件去除 alpha，源图不变。
- 所有资源位于 `Lumineux/Assets-Lumineux.xcassets`；原 SunSmart、SLGSync 资源没有修改。缺少的新图继续使用现有共享原图，不能理解为 Lumineux 所有图标已完全换色。

### 2026-08-28 页面稿补充

| 使用位置 | 同名资源 | 原始节点 | iOS 逻辑尺寸 |
| --- | --- | --- | --- |
| Sites 浮动添加按钮（Site 添加空间入口同名复用） | `add` | `16001:24116` | 48 × 48pt |
| Welcome 协议勾选态（其他同名选择入口自动复用） | `select` | `5776:95965` | 30 × 30pt |
| Space 底部添加按钮 | `space_add` | `16001:97684` | 30 × 30pt |

本轮来源为 [Sites](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=16001-24109)、[Welcome](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=5776-95955)、[Space](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=16001-97645)。均导出整个节点，保留透明留白并提供 1x/2x/3x；未把页面文字、进度或原生控件烘焙成图片。

[Launch](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=0-10522) 与 Welcome 的 Logo 已有对应素材，页面补充阶段未替换；后续质量修正已使用 [1024px 原稿](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=0-39925) 重生成两组显示 Logo，尺寸与资源名不变。Space 的排序按钮实际使用 `space_sort`，不能据此把另一用途的 `order_down` 标记为已补；其他选择态也不共用这张实心圆勾选图。当前四张页面均未包含空状态插图。

## 剩余数量如何计算

原清单按 SLGSync 的 128 组资源，扣除 4 组 Logo 和与 SunSmart 图片内容一致的 30 组 FireAlarm1.5 资源，得到 94 组品牌资源。

现有素材覆盖其中 **28 组**（首批 25 + 页面补充 3），剩余 **66 组**待提供或确认沿用；另外已打包的 **29 组**是 Tab 正常态、导航及按钮配对状态等，因此总数是 57，不是从 94 中扣除 57。数量均按资源名称计，不按 PNG 文件计，不能等同于运行时已生效。

## 待提供或确认沿用

请后续提供以下资源的 Lumineux 设计节点/导出包，或者标记“沿用原图”。优先补其余选择/筛选图标，以及 Site/Space/Group/Scene 空状态插图。不会用 SLG 绿色图标替代，也不会在共享 Swift 中自动换色。

| 分类 | 剩余组数 |
| --- | ---: |
| 通用操作与加载（Common） | 7 |
| 设备（Device） | 4 |
| 能耗（Energy） | 4 |
| 固件与升级引导（Firmware） | 10 |
| 分组与开关（Group） | 8 |
| 路径（Path） | 3 |
| 策略与图表（Profile） | 24 |
| 场景（Scene） | 2 |
| 项目列表（Site） | 1 |
| 空间（Space） | 2 |
| 定时（Timed） | 1 |
| 合计 | 66 |

### 通用操作与加载（Common，7 组）

- `filter_selected`
- `menu_select`
- `order_down`
- `order_up`
- `server_select`
- `user_big`
- `value_buoy`

### 设备（Device，4 组）

- `device_scan`
- `device_select`
- `switch_proxy_instructions_1`
- `switch_proxy_instructions_2`

### 能耗（Energy，4 组）

- `energy_csv`
- `energy_device`
- `energy_light`
- `energy_phone`

### 固件与升级引导（Firmware，10 组）

- `distributor_nodes_highlight`
- `distributor_single_device_highlight`
- `firmware_cloud_version`
- `initiator`
- `mesh_distributor_guide_4`
- `mesh_upgrade_guide_1`
- `mesh_upgrade_guide_2`
- `mesh_upgrade_guide_3`
- `single_device`
- `updatating_nodes`

### 分组与开关（Group，8 组）

- `auto`
- `auto_big`
- `group_empty`
- `member_add`
- `switch_press`
- `switch_press_long`
- `switch_save`
- `switch_save_un`

### 路径（Path，3 组）

- `path_direction_left`
- `path_direction_right`
- `path_item_add`

### 策略与图表（Profile，24 组）

- `adjust_speed_fast`
- `adjust_speed_slow`
- `daylight_scheme4`
- `daylight_scheme5`
- `daylight_scheme6`
- `daylight_scheme7`
- `daylight_standalone_sensor`
- `power_state_defined`
- `power_state_off`
- `power_state_restore`
- `profile_chart_daylight`
- `profile_chart_daylight_ipad`
- `profile_chart_manual_control`
- `profile_chart_manual_control_ipad`
- `profile_chart_occupancy`
- `profile_chart_occupancy_daylight`
- `profile_chart_occupancy_daylight_ipad`
- `profile_chart_occupancy_ipad`
- `profile_chart_occupancy_standby`
- `profile_chart_occupancy_standby_ipad`
- `profile_person`
- `profile_person_big`
- `profile_proximity_lighting`
- `sensor_manul_override_timeout`

### 场景（Scene，2 组）

- `scene_data_add`
- `scene_empty`

### 项目列表（Site，1 组）

- `site_empty`

### 空间（Space，2 组）

- `locked`
- `space_empty`

### 定时（Timed，1 组）

- `schedule_target_select`

## 已提供设计中暂不直接替换的内容

- 导航栏深色“+”与 `add` / `space_add` 的品牌色圆形添加按钮用途不同；后两者已按本轮页面中的明确节点补齐，不使用导航图代替。
- `control_add_unactive40` / `control_minus_unactive40` 的命名与视觉状态不一致，暂不推断成 `light_value_add_higtlighted` / `light_value_minus_highlighted` 的按下态。正常态的增减按钮已经接入；需要确认这两个填充圆形是否用于按下态。
- `switch_on/off` 是整颗开关设计，项目现有开关由 UIKit 控件绘制；只保留已有主题入口，不添加图片开关或改共享控件代码。
- 带 ON/OFF/Identify 文字的按钮、静态“45%”进度示例不直接烘焙成新图，避免替换现有国际化文字或动态进度逻辑。
- 其他没有对应此次品牌替换清单、或不能确认一一对应的普通帮助/信息/状态图标保留原实现。已提供的中性图形不代表 `user_big` 等不同填充/尺寸用途的品牌变体已确认。

## 代码与配置边界

- 已撤回 47 个共享 Swift 文件的上一轮改动。`SunSmart/` 仅 `MacroDefinition.swift` 保留 9 行 Lumineux 分支：四个主题色均为 RGB(77,115,138)，`customId` 保持 0x00；额外 `Purple_Color` 分支已撤回。
- 没有 UIImage/UIButton 换色 helper，没有替换共享图片调用，没有改 Welcome/menu 的共享约束。
- Lumineux target 只编译 `$(DERIVED_FILE_DIR)/LumineuxAssets/Assets-Lumineux-Merged.xcassets`；`Merge Lumineux Assets` 每次构建重建该目录，原两份 catalog 仍保留为 merger 输入及其他 target 资源，不直接进入 Lumineux Resources。
- 名称、Bundle ID、Wen Xu 签名、必要独立 target/Pods 配置、独立启动页及两份协议副本保留。协议仍与 SLGSync 原件一致，SLG 相关正文未改（隐私 12 处、用户协议 56 处旧品牌相关命中，需后续确认）。
- 服务器、云端身份、空间默认值、SDK、Bugly 未处理；无 Git 提交或推送。
- 上一版前缀 catalog 的 4 组派生文件已移出工程，保存在 `/private/tmp/lumineux-prefixed-assets.f8f1Dj` 可恢复；两份原始 Logo 未删除。

## 验证

验证与复现步骤见 `Tests/Branding/README.md`。本轮新增 3 组后，中英文三设备矩阵共 54 个通过、6 个严格预期失败负控，无实际失败或跳过；新图标在 Welcome、Sites 和真实 Space 底部组件中通过独立 reference catalog 逐像素来源验证，并已核对相关截图。正常 Library 路径的 Lumineux 真机 Debug 构建和签名验证通过，694 组生成资源中 61 组匹配 Lumineux，其余 633 组匹配公共资源。

原合并方案此前已验证新增、覆盖移除恢复 common、Lumineux-only 移除无残留，以及 Release 签名和 SunSmart Debug 回归；本轮未改合并脚本、共享代码或其他 target。旧双 catalog 方案的测试不作为当前方案证据。
