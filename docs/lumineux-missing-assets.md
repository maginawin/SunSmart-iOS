/opt/homebrew/Library/Homebrew/cmd/shellenv.sh: line 18: /bin/ps: Operation not permitted
> 目录说明：已接入的 Lumineux 资源按 SLGSync 的十二个业务分组保存；SLGSync 不存在的同名资源只参考 SunSmart 的业务目录归类。该规则不代表复用或复制 SunSmart 图片，也不改变下文对缺失素材的判断。

# Lumineux 资源接入与待提供清单

核对日期：2026-09-01。Lumineux 继续使用专属构建期资源合并：公共 catalog 先复制到 `DERIVED_FILE_DIR`，再由 Lumineux 完整 asset set 覆盖同名资源，原生 actool 只编译这份生成 catalog。旧双 catalog 顺序方案已废弃；不使用运行时染色或改写共享图片调用。本轮 new3 已接入 28 对原始 Retina PNG 对应的 29 个资源，未生成 1x、未重编码、未修改生产 Swift。当前合同为 source catalog 121 组、SLGSync non-Fire 覆盖 83 / 94、待提供 11、额外已打包 33、已提供总数 116；Task 6 的合并 catalog 验收为 695 = 121 Lumineux + 574 Common。Task 5 六组合 focused UIKit 矩阵已全部通过并完成人工截图核对；Task 6 正常 DerivedData 构建/签名尚待执行，不能引用下方较早批次的验证记录作为本轮结果。

## 本次已下载并打包

- 83 组同名图标：原有 72 组（Tab 10、导航 10、设备/分组/场景按钮与尺寸变体 26、收藏/加载/等待/能耗 8、页面稿补充 3、紧凑状态/扫描图标 4、Profile／Safe Mode 补充 4、用户文件夹提供的 `auto` 1、Common Retina PNG 6），再加本轮 Device 2、Energy 3、Group 3、Path 3 组 grouped Retina PNG；另有 4 组空状态插图，因此已提供资源总数为 87。已有的 `sync_loading_small` 同时改用完整 24pt 组件节点，数量不重复计算。
- 首批原稿来自四个用户提供的 Figma 框架：[Tab](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=9338-252618)、[导航](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=9338-259821)、[按钮](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=9338-290273)、[其他](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=1038-38735)。
- 52 份完整节点矢量导出保存在 `Lumineux/DesignAssets/Figma`；资源名、节点 ID、原有 iOS 逻辑尺寸逐项记录在 `Lumineux/DesignAssets/icon-manifest.json`。仅机械缩放生成 1x/2x/3x PNG，不重绘或改色。
- `auto` 的原始 2x/3x PNG 单独保存在 `Lumineux/DesignAssets/Provided`，catalog 保留这两份源文件的原始字节，1x 由 2x 机械缩小生成。本轮六组 Common PNG 保存在 `Lumineux/DesignAssets/Provided/Common`，只使用用户提供的 2x/3x 原文件，1x 槽位按项目现状留空，不生成图片。
- 两份已提供 Logo 保留为源文件；catalog 使用 `AppIcon`、`launch_logo`（88pt）、`launch_logo_120`（120pt）和系统启动页专用的 `lumineux_launch_logo`（88pt），`AccentColor` 为 `#4D738A`。三组显示 Logo 现统一从 `app_logo_1024.png` 高清原图缩小生成，88px 小图仅存档、不再放大使用；避免原小图自带的灰色圆角和细节模糊。AppIcon 仅派生文件去除 alpha，源图不变。
- 所有资源位于 `Lumineux/Assets-Lumineux.xcassets`；原 SunSmart、SLGSync 资源没有修改。缺少的新图继续使用现有共享原图，不能理解为 Lumineux 所有图标已完全换色。

### 2026-08-28 页面稿补充

| 使用位置 | 同名资源 | 原始节点 | iOS 逻辑尺寸 |
| --- | --- | --- | --- |
| Sites 浮动添加按钮（Site 添加空间入口同名复用） | `add` | `16001:24116` | 48 × 48pt |
| Welcome 协议勾选态（其他同名选择入口自动复用） | `select` | `5776:95965` | 30 × 30pt |
| Space 底部添加按钮 | `space_add` | `16001:97684` | 30 × 30pt |

本轮来源为 [Sites](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=16001-24109)、[Welcome](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=5776-95955)、[Space](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=16001-97645)。均导出整个节点，保留透明留白并提供 1x/2x/3x；未把页面文字、进度或原生控件烘焙成图片。

[Launch](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=0-10522) 与 Welcome 的 Logo 已有对应素材，页面补充阶段未替换；后续质量修正已使用 [1024px 原稿](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=0-39925) 重生成两组显示 Logo，尺寸与资源名不变。Space 的排序按钮实际使用 `space_sort`，因此页面补充阶段没有据此推断 `order_down`；该资源后来使用用户单独提供的同名语义 PNG 接入。

### 2026-08-29 空状态插图

| 同名资源 | Figma 节点 | iOS 逻辑尺寸 | 导出 |
| --- | --- | --- | --- |
| `site_empty` | `0:11425` | 353 × 298pt | 2x / 3x |
| `space_empty` | `2090:132420`（No spaces 页面中的 `images/空页面插画`） | 240 × 194pt | 2x / 3x |
| `group_empty` | `0:2719` | 343 × 288pt | 2x / 3x |
| `scene_empty` | `0:4474` | 343 × 288pt | 2x / 3x |

四组均为 Figma 完整节点的原始 PNG 导出，未重绘、重着色或修改共享 Swift；其中 `space_empty` 按实际 No spaces 页面使用的新空盒插图接入，不再沿用旧的层级示意图。

### 2026-08-29 24pt 状态与扫描图标

| 同名资源 | Figma 节点 | iOS 逻辑尺寸 |
| --- | --- | --- |
| `sync_success_small` | `0:18004` | 24 × 24pt |
| `sync_failed_small` | `0:18014` | 24 × 24pt |
| `sync_waiting_small` | `0:18424` | 24 × 24pt |
| `sync_loading_small` | `0:19394` | 24 × 24pt |
| `device_scan` | `0:19460` | 24 × 24pt |

五组均取自用户提供的 [24pt 状态图标组件](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=9339-293204)，保存完整组件画布并生成 1x/2x/3x。`device_scan` 从待提供清单移除；其余四组是已有运行时状态资源，其中 `sync_loading_small` 原先已经打包，但本轮从内层圆环节点纠正为完整 24pt 组件节点。

另一份 [30pt 设备状态组件](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=9338-150316) 与公共 catalog 的设备分类、同步/离线状态资源一致，本轮不重复放入 Lumineux catalog。`power24`、`repair` 等没有可确认的一一对应资源名，仍保留公共实现，不做猜测替换。

### 2026-08-29 外部 PNG 文件夹

从用户提供的 `/Users/sr/Documents/SunSmart/assets` 中接入根目录的 `icon@2x.png` / `icon@3x.png`，按视觉语义、40pt 尺寸和真实调用点唯一映射为 `auto`。该图只替换 iPhone 使用的 40pt 同名资源；iPad 仍使用独立的 `auto_big`。

同目录的扫描图与已接入 `device_scan` 一致；两组加减号、电源图及黑色加号要么已有明确版本，要么无法唯一映射到待补名称，因此没有覆盖现有资源。没有依据文件夹层级或临时导出名猜测替换。

### 2026-08-29 Profile 与 Safe Mode 补充

| 使用位置 | 同名资源 | Figma 节点 | iOS 逻辑尺寸 |
| --- | --- | --- | --- |
| Profile 占用／日光曲线 | `profile_chart_occupancy_daylight` | `16001:174597` | 212 × 234pt |
| Profile 上电状态选中项 | `schedule_target_select` | `16001:174651` | 30 × 30pt |
| Group Sensor 移动状态 | `sensor_move` | `16001:174616` | 20 × 20pt |
| Safe Mode 设备选中项 | `device_select` | `0:17954` | 30 × 30pt（18pt 图形居中） |

四组均直接使用 Figma 完整节点的 PDF 矢量导出，生成 1x／2x／3x；没有改色、重绘或修改共享图片调用。`device_select` 只在 18pt 原图外增加透明留白，以适配项目原有 30pt 同名资源画布。`sensor_move` 是此前按 SLGSync catalog 范围统计时遗漏的 Lumineux 品牌资源，因此不从下方原 60 组清单中扣减。

### 2026-08-31 Common Retina PNG 补充

| 用户文件 | 同名资源 | iOS 逻辑尺寸 | 导出 |
| --- | --- | --- | --- |
| `Property 1=filter` | `filter_selected` | 30 × 30pt | 2x / 3x |
| `images/select` | `menu_select` | 30 × 30pt | 2x / 3x |
| `Property 1=order_down` | `order_down` | 30 × 30pt | 2x / 3x |
| `Property 1=order_up` | `order_up` | 30 × 30pt | 2x / 3x |
| `images/select_2` | `server_select` | 30 × 30pt | 2x / 3x |
| `images/user` | `user_big` | 88 × 88pt | 2x / 3x |

六组均逐字节保存用户提供的 Retina PNG，不缩放、不改色、不重绘；对应 imageset 只填写 2x 与 3x 文件，1x 保持空槽。`images/select_3` 无唯一待补资源映射，因此未接入；`value_buoy` 仍待提供。

### 2026-08-31 Device、Energy、Group、Path Retina PNG 补充

| 用户文件 | 同名资源 | iOS 逻辑尺寸 | 导出 |
| --- | --- | --- | --- |
| `Frame 133` | `Device/switch_proxy_instructions_1` | 310 × 328pt | 2x / 3x |
| `Frame 132` | `Device/switch_proxy_instructions_2` | 287 × 312pt | 2x / 3x |
| `images/Hard-Drive20` | `Energy/energy_device` | 20 × 20pt | 2x / 3x |
| `images/csv` | `Energy/energy_csv` | 20 × 20pt | 2x / 3x |
| `images/phone20` | `Energy/energy_phone` | 20 × 20pt | 2x / 3x |
| `images/press` | `Group/switch_press` | 30 × 30pt | 2x / 3x |
| `images/press_long` | `Group/switch_press_long` | 30 × 30pt | 2x / 3x |
| `images/save` | `Group/switch_save` | 40 × 40pt | 2x / 3x |
| `箭头左` | `Path/path_direction_left` | 31 × 12px / 47 × 18px | 2x / 3x |
| `箭头右` | `Path/path_direction_right` | 31 × 12px / 47 × 18px | 2x / 3x |
| `images/add` | `Path/path_item_add` | 9 × 9pt | 2x / 3x |

十一组均逐字节保存用户提供的 Retina PNG，imageset 仅填写 2x 与 3x，1x 保持空槽。PNG 文件字节与运行时布局属于不同层次：`switch_proxy_instructions_1` 的 310 × 328pt 原图在 iPhone 现有 324/310 约束下约有 1.2% 纵向压缩；用户已确认影响可忽略，本轮不改生产 Swift。`new2/icon/路径` 暂不处理；`energy_light`、`auto_big`、`member_add`、`switch_save_un` 没有接入。

## 剩余数量如何计算

SLGSync 的 128 组范围扣除 4 组 Logo 和与 SunSmart 内容一致的 30 组 FireAlarm1.5 资源后，非 Fire 范围为 94 组；本轮覆盖数为 **83 / 94**，待提供数为 **11**。另有 **33** 组额外已打包资源，因此已提供资源总数为 **116**。Lumineux source catalog 为 **121** 组（119 个 imageset 加 AppIcon、AccentColor）；Task 6 构建产物需验证 merged catalog 为 **695 = 121 Lumineux + 574 Common**。

## 待提供或确认沿用

仅保留下列 11 组非 FireAlarm 待提供资源。请后续提供 Lumineux 设计节点/导出包，或者标记“沿用原图”；确认前继续使用现有共享原图，不用 SLG 绿色图标替代，也不在共享 Swift 中自动换色。

| 分类 | 待提供资源 |
| --- | --- |
| Energy | `energy_light` |
| Firmware | `distributor_single_device_highlight` |
| Group | `auto_big`、`member_add`、`switch_save_un` |
| Profile | `profile_chart_daylight_ipad`、`profile_chart_manual_control_ipad`、`profile_chart_occupancy_daylight_ipad`、`profile_chart_occupancy_ipad`、`profile_chart_occupancy_standby`、`profile_chart_occupancy_standby_ipad` |

## 已提供设计中暂不直接替换的内容

- 导航栏深色“+”与 `add` / `space_add` 的品牌色圆形添加按钮用途不同；后两者已按本轮页面中的明确节点补齐，不使用导航图代替。
- `control_add_unactive40` / `control_minus_unactive40` 的命名与视觉状态不一致，暂不推断成 `light_value_add_higtlighted` / `light_value_minus_highlighted` 的按下态。正常态的增减按钮已经接入；需要确认这两个填充圆形是否用于按下态。
- `switch_on/off` 是整颗开关设计，项目现有开关由 UIKit 控件绘制；只保留已有主题入口，不添加图片开关或改共享控件代码。
- 带 ON/OFF/Identify 文字的按钮、静态“45%”进度示例不直接烘焙成新图，避免替换现有国际化文字或动态进度逻辑。
- 其他没有对应此次品牌替换清单、或不能确认一一对应的普通帮助/信息/状态图标保留原实现。已提供的中性图形不代表不同填充、尺寸或业务用途的品牌变体已确认。

## 代码与配置边界

- 已撤回 47 个共享 Swift 文件的上一轮改动。`SunSmart/` 仅 `MacroDefinition.swift` 保留 9 行 Lumineux 分支：四个主题色均为 RGB(77,115,138)，`customId` 保持 0x00；额外 `Purple_Color` 分支已撤回。
- 没有 UIImage/UIButton 换色 helper，没有替换共享图片调用，没有改 Welcome/menu 的共享约束。
- Lumineux target 只编译 `$(DERIVED_FILE_DIR)/LumineuxAssets/Assets-Lumineux-Merged.xcassets`；`Merge Lumineux Assets` 每次构建重建该目录，原两份 catalog 仍保留为 merger 输入及其他 target 资源，不直接进入 Lumineux Resources。
- 名称、Bundle ID、Wen Xu 签名、必要独立 target/Pods 配置、独立启动页及两份协议副本保留。协议仍与 SLGSync 原件一致，SLG 相关正文未改（隐私 12 处、用户协议 56 处旧品牌相关命中，需后续确认）。
- 服务器、云端身份、空间默认值、SDK、Bugly 未处理；无 Git 提交或推送。
- 上一版前缀 catalog 的 4 组派生文件已移出工程，保存在 `/private/tmp/lumineux-prefixed-assets.f8f1Dj` 可恢复；两份原始 Logo 未删除。

## 验证

验证与复现步骤见 `Tests/Branding/README.md`。2026-08-28 页面补充阶段新增 3 组时，中英文三设备矩阵共 54 个通过、6 个严格预期失败负控，无实际失败或跳过；新图标在 Welcome、Sites 和真实 Space 底部组件中通过独立 reference catalog 逐像素来源验证，并已核对相关截图。当时正常 Library 路径的 Lumineux 真机 Debug 构建和签名验证通过，694 组生成资源中 61 组匹配 Lumineux，其余 633 组匹配公共资源。

原合并方案此前已验证新增、覆盖移除恢复 common、Lumineux-only 移除无残留，以及 Release 签名和 SunSmart Debug 回归；本轮未改合并脚本、共享代码或其他 target。旧双 catalog 方案的测试不作为当前方案证据。

2026-08-29 按 SLGSync 使用独立 `slg_launch_logo` 的方式，Lumineux 启动 storyboard 已从共享 `launch_logo` 改为独立 `lumineux_launch_logo`。已在 iPhone SE 3、iPhone 16 和 iPad Pro 11 M4 上通过启动页资源来源与布局测试，并人工核对三张截图；没有改动 SunSmart 共享资源、共享 Swift 或其他 target。
正式 Lumineux 真机 Debug 构建和签名校验通过；当前生成 catalog 为 695 组，其中 62 组匹配 Lumineux，其余 633 组匹配公共资源。

同日从新增的三个 Figma 页面及实际 “No spaces!” 页面补入 `site_empty`、`space_empty`、`group_empty`、`scene_empty`。静态素材检查锁定四个源节点、逻辑尺寸和 2x/3x 原始文件哈希；真实 `UIView.showEmptyDataView` 在 iPhone SE 3、iPhone 16、iPad Pro 11 M4 上各通过 1 个来源与布局测试，12 张截图均已人工核对，无错图、裁切或重叠。正式 Lumineux 真机 Debug 构建与 Wen Xu 签名校验通过；合并 catalog 仍为 695 组，其中 66 组来自 Lumineux、629 组保留公共资源。未安装或启动真机 App，也未修改共享 Swift、SunSmart/SLGSync 资源或其他 target。

同日从 Figma `9339:293204` 补入 4 组新同名资源，并把 `sync_loading_small` 纠正为完整 24pt 组件导出。素材、合并器、配置和 SDK 检查通过；真实同步状态 cell 与候选设备扫描按钮在 iPhone SE 3、iPhone 16、iPad Pro 11 M4 的英文及简体中文环境中合计执行 6 个测试，全部通过。12 张最终截图已人工核对，无错图、裁切、重叠或约束歧义。正式 Lumineux 真机 Debug 构建及 Wen Xu / JTD3WYUC58 签名校验通过；生成 catalog 仍为 695 组，70 组 Lumineux asset set 逐组匹配源 catalog，其余 625 组保留公共资源。未安装或启动真机 App，也未修改共享 Swift、SunSmart/SLGSync 资源、合并脚本或其他 target。

同日从用户提供的外部 PNG 文件夹严格只补入 `auto`。静态测试固定原始 2x/3x SHA-256、40pt 逻辑尺寸和三倍率完整性；真实强制 AUTO 弹窗在 iPhone SE 3、iPhone 16 的英文及简体中文环境中合计执行 4 个测试，全部通过，4 张截图人工核对无裁切、重叠或约束歧义。iPad 继续使用尚未提供的 `auto_big`。正式 Lumineux 真机 Debug 增量构建及 Wen Xu / JTD3WYUC58 签名校验通过；生成 catalog 仍为 695 组，71 组 Lumineux asset set 逐组匹配源 catalog，`auto` 覆盖验证通过，其余 624 组保留公共资源。未安装或启动真机 App，也未修改共享 Swift、SunSmart/SLGSync 资源、合并脚本或其他 target。

同日 iPhone 16 真机又出现纯白启动页。构建产物中的专用 storyboard 和 `Assets.car` 均正确；真机 SpringBoard/SplashBoard 日志明确显示系统找到了旧 snapshot、拒绝重新生成且未清除缓存。临时 storyboard 改名、Bundle Version 2 和整机重启均未改变同一 snapshot 命中，相关实验已撤销。用户最终选择严格保持 SLGSync 结构：`Lumineux-LaunchScreen` 继续使用独立 `lumineux_launch_logo`，不增加应用内启动层，不修改 SunSmart、SLGSync 或共享 AppDelegate。当前测试 iPhone 的缓存白屏不作为工程接入成功证据。

同日从 Figma 补入 `profile_chart_occupancy_daylight`、`schedule_target_select`、`sensor_move`、`device_select`。四组素材、合并器、配置与 SDK 检查通过；真实 Profile、Group Sensor 与 Safe Mode 图片加载路径在 iPhone 16 的英文及简体中文环境中合计执行 6 个测试，全部通过。8 张截图已人工核对，无错图、拉伸、裁切、偏移或文字挤压。正式 Lumineux 真机 Debug 构建和 Wen Xu / JTD3WYUC58 签名校验通过；生成 catalog 仍为 695 组，75 组来自 Lumineux，其余 620 组保留公共资源。SunSmart 的 iPhone 16 模拟器 Debug 构建回归通过；未安装或启动真机 App，也未修改共享 Swift、SunSmart/SLGSync 资源、合并脚本或其他 target。

2026-08-31 从用户提供的 `assets/new` 接入六组 Common Retina PNG，只保留原始 2x/3x，1x 槽位为空。静态素材、分组、合并器、生成器、工程配置与 SDK 依赖检查均通过；真实用户设置、服务器选择、标题选择和静态能耗页面在 iPhone SE 3、iPhone 16、iPad Pro 11 M4 的英文及简体中文环境中合计执行 6 次测试，0 失败、0 跳过。24 张快照已逐张核对，新增图片无拉伸、裁切、重叠或越界。正式 Lumineux 真机 Debug 构建与 Wen Xu / JTD3WYUC58 签名校验通过；生成 catalog 仍为 695 组，其中 81 组逐文件匹配 Lumineux，其余 614 组保留公共资源。`value_buoy` 与 `images/select_3` 未接入；未安装或启动真机 App，也未修改共享 Swift、SunSmart/SLGSync 资源、合并脚本或其他 target。

## 2026-09-01 new3 Retina 素材接入

本轮将 28 对用户提供的原始 2x/3x PNG 映射为 29 个同名 Lumineux 资源；`button/Group 160` 有意同时映射到 `distributor_nodes_highlight` 与 `updatating_nodes`，两份目标 PNG 字节相同。每个新增 imageset 仅有 universal 的 1x 空槽及原始 2x/3x 文件；没有生成 `@1x.png`，没有缩放、重新编码、改色或重绘。源文件在 `Lumineux/DesignAssets/Provided/<group>/`，catalog 对应文件逐字节一致，像素尺寸和 SHA-256 由静态测试固定。

明确排除四对素材：根目录 `Group 160`、`icon/Nav`、`images/download`、`Proximity/images/数据表`；也不导入 `.DS_Store` 或任何 `FireAlarm1.5` 内容。不得把 `icon/space_device` 缩放后复用为 `energy_light` 或 `distributor_single_device_highlight`，也不从本轮 iPhone 图表生成任何 `_ipad` 资源。本轮没有修改生产 Swift、Xcode 工程、合并脚本或依赖锁定。

`testProvidedNew3RetinaAssetsFitProductionControls()` 覆盖 29 个资源的独立 Lumineux source 比对和真实生产容器。Buoy 在 slider 实际触发 `valueChanged` 后严格检查布局。四个 `daylight_scheme4...7` 的 `DaylightSensorInstructionsViewCell` 存在已确认的 2.934pt 竖向 hugging 歧义；按已接受边界不改生产 Swift，测试对它们仍严格检查独立来源、可见性、具体 containment 与截图，但不使用通用 `hasAmbiguousLayout == false` 断言。其他组件继续保持严格歧义检查。

Task 3 的 iPhone 16 focused 运行已产出并人工审阅 18 张附件。Task 5 已在 iOS 18.0（22A3351）的 iPhone SE 3（`9FCF83EB-38F9-4B61-A35E-D88F8665A1B5`）、iPhone 16（`5E6F7D5C-CC01-4760-8D6E-2489835F1748`）和 iPad Pro 11 M4（`1B4321CD-F455-4252-8504-105435A02C9A`）完成 en-US 与 zh-Hans-CN 六组合 focused UIKit 验证，6 次运行全部通过，0 失败、0 跳过。英文、中文结果分别为 `/private/tmp/lumineux-new3-matrix.bEfAtG/matrix-en-accepted.xcresult` 与 `/private/tmp/lumineux-new3-matrix.bEfAtG/matrix-zh-accepted.xcresult`，导出目录分别为 `/private/tmp/lumineux-new3-matrix.bEfAtG/screenshots-en-accepted` 与 `/private/tmp/lumineux-new3-matrix.bEfAtG/screenshots-zh-accepted`；共 108 张附件已逐张人工核对。

iPhone SE 3 的固定高度固件步骤行存在两处已接受的既有越界重叠，仅涉及 `mesh_upgrade_guide_1` 和 `mesh_upgrade_guide_3`；SunSmart 与 SLGSync 使用的对应 2x 画布同样为 344 × 202 和 288 × 80。测试只对该紧凑屏幕组合放宽两张图的行内容 containment，仍验证 Lumineux 独立来源、可见性、有限正尺寸、生产 frame、与固定高度行的有效交集和外层容器 containment；未修改生产 Swift 或 PNG。其余截图中的 buoy、固件、图表、Scene 与 Space lock 等均无错图、不合理拉伸/裁切、重叠或越界，iPad 图表保持 `_ipad` 分支。Task 6 仍须在新的正常 Library DerivedData 中完成 Lumineux Debug 构建、签名与 695/121/574 合并 catalog 证据，尚未执行。
