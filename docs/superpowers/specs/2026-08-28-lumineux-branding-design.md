# Lumineux 品牌接入设计与协议核对清单

> 历史方案，已被用户的“完全参考 SLGSync，只替换独立同名资源和主题色”要求取代。下面的唯一资源前缀、UIImage helper、额外控件改色和 102 次测试记录均属于已撤回的上一版，不能作为当前实现或验收依据。当前范围见 `docs/superpowers/plans/2026-08-28-lumineux-resource-only.md`，当前素材和验证见 `docs/lumineux-missing-assets.md`、`Tests/Branding/README.md`。

日期：2026-08-28。

状态：本轮独立配置、Logo、主要品牌控件及协议副本已接入并完成验证；中英文三设备 UIKit 测试及五品牌构建通过，未提交或推送 Git。协议正文、业务策略、真机验收及尚未统一的共享图像/提示配色仍待后续处理，见下文。

## 1. 已确认的范围

- App 显示名称：`Lumineux`。
- Bundle ID：`com.azoula.sunsmart.Lumineux`。
- 签名：用户已在 Xcode 选择 Wen Xu；保留现有 `JTD3WYUC58`，不更换账号、Team、证书或描述文件。
- 主色、按钮色、滑块色：`#4D738A`，即 RGB `(77, 115, 138)`。
- Logo：采用用户指定的两个 Figma 节点，不自行修改图中文字或配色。
- 协议：先原样复制 SLGSync 的两份 HTML，正文修改和翻译另行确认。
- 服务器、云端身份、空间默认设置：明确排除，等待产品经理确认。

## 2. Figma 来源与已保存素材

| 用途 | Figma 节点 | 本地文件 |
| --- | --- | --- |
| 88 × 88 Logo | [launch_logo](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=0-39936&m=dev) | [launch_logo_88.png](/Users/sr/Documents/SunSmart/sun-smart/Lumineux/DesignAssets/launch_logo_88.png) |
| 1024 × 1024 Logo | [app_logo_1024](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=0-39925&m=dev) | [app_logo_1024.png](/Users/sr/Documents/SunSmart/sun-smart/Lumineux/DesignAssets/app_logo_1024.png) |
| Sites 配色参考 | [Sites_more](https://www.figma.com/design/P4AaSxu8SJe2Tf2gpyTFT9/Lumineux_260814?node-id=16001-24109&m=dev) | 本轮只读取设计，不重做页面 |

两个 Logo 的图内文字均为 `LumiSmart intelligent controls`。用户已指定它们为最终素材，因此按原图保留；App 的系统显示名称仍为 `Lumineux`。

保存方式：读取设计上下文后，使用 Figma 原尺寸 PNG 渲染结果。终端直接下载 Figma 资源域名时 DNS 解析失败，经过网络权限重试仍失败，因此使用 Figma 工具支持的内联图片返回通道；未重绘、缩放或修改返回图片的像素。

这两份文件保留为设计源素材。Asset Catalog 使用 1024 原图生成逻辑尺寸 88/120 对应的 1x、2x、3x 图片，AppIcon 为不含透明通道的 1024 PNG；没有重绘、改字或改色。资源尺寸和主题色检查已通过。

| 文件 | SHA-256 |
| --- | --- |
| launch_logo_88.png | `e8dff81fb85b0a314d04f0000a6cde86bf48c895c1c5a179db6717c2eaff7152` |
| app_logo_1024.png | `f0a30a66da6258705d242523f466b976f2655f2713476df74cd538c30240d17e` |

## 3. 接入方案

采用与 SLGSync 相同的多 target 思路：独立品牌配置和资源，共享现有业务代码。

方案比较：独立配置配合少量品牌分支适合当前范围；复制整套品牌图片便于逐图定制，但需要维护大量副本；统一重构所有品牌为配置对象便于后续扩展，但会扩大本次回归范围。本次选择第一种。

### 3.1 工程和依赖

- 为 Lumineux 建立独立 Base、Debug、Release 配置，并在两种构建配置中启用 `Lumineux` 条件编译标识；不启用 `SLGSync`。
- 整理独立 Info.plist 和 Entitlements，保留现有蓝牙后台模式和 Wi-Fi 信息能力。
- 保留用户已确认的 Team；仅调整品牌配置归属，不触碰签名账户。
- 修正复制的 Info.plist 在工程中的机器绝对路径引用。
- 在 Podfile 的 Common 抽象 target 下声明 Lumineux，生成自己的 Pods 配置和嵌入脚本。
- 继续使用现有 NordicSigMeshSDK release 依赖，不修改 SDK 源码。

### 3.2 Logo 与资源隔离

- 为 Lumineux 单独接入 AppIcon、启动页、欢迎页和侧边栏 Logo。
- 品牌专用资源优先使用唯一名称，明确设置 AppIcon 和读取入口，避免依赖同名资源的隐式覆盖顺序。
- 通用图片仍复用共享资源；不直接替换 SunSmart 或 SLGSync 的现有文件。
- 欢迎页和侧边栏分别核对尺寸、宽高比、圆角及完整约束链。保留 Logo 的原图排版和颜色。

### 3.3 颜色与 Sites 参考

以下四个现有品牌入口在 Lumineux 分支统一为 `#4D738A`：

| 入口 | 角色 |
| --- | --- |
| `Bar_Color` | 主色、选中态、链接等 |
| `Bottom_Done_Color` | 操作按钮和弹窗操作 |
| `Title_Done_Color` | 保存、创建等操作文字 |
| `Slider_Color` | 滑块高亮轨道 |

Sites 设计中还出现以下配色：页面背景 `#F8FAFC`、卡片白色、未选中分段文字 `#9CA3AF`、卡片标题 `#272536`、辅助文字 `#94A3B8`。它们作为页面核对依据，不据此全局更改所有品牌的文字和背景颜色。

优先复用现有 `SitesViewController`、`SitesViewCell` 和 `CustomSegmentedControl`。本次不新增示例站点、不修改列表数据结构，也不复制 Figma 中的状态栏或系统时间。

检查仅代表品牌的硬编码紫色和带色图片，包括分段选中态、收藏、添加、扫描、灯光控制、上下光比例、场景编辑和同步提示。只替换属于 Lumineux 品牌的表现；其他品牌保持原值。成功、错误、警告等语义色和 Logo 内的绿色不统一染成蓝色。

已实现的图片入口采用 `UIImage.brandPresentationImage(named:)`，仅在 Lumineux 编译条件下处理 40 个明确列出的资源名称；普通 UIButton 初始化及相关直接刷新入口均已接入。保留图像尺寸、比例、透明度、白色字形和中性灰像素。非 Lumineux 分支直接读取原图，不修改共享 Asset 文件。

覆盖普通选择/添加/收藏、设备扫描、灯光增减与开关、上下光比例、空间标签、Group/DALI 开关、AUTO、固件删除、设备恢复、撤销、组选择和排序等已核对的品牌控件。应急测试标签和等待背景保留原有 0.12/0.08 透明度，Scene OFF 初始及刷新描边使用品牌蓝。

### 3.4 尚未统一的共享图像与提示配色

本次不是全量资源换肤，以下仍沿用原样，不能视为已经完成蓝色适配：

- `site_empty`：Sites 空页说明插图，含旧紫色和图内英文；页面外部文案仍走现有国际化。
- `firmware_cloud_version`：固件页顶部云端图像；本次只处理其中的普通删除操作按钮。
- `function_test_icon`、`rx_tx_cable_icon`：应急测试标题图标。
- `PJEightKeySwitchWaitingSpinnerView`：提示转圈的原有轨道/进度色；不是已迁移的按钮或等待背景。
- 其他图表、引导图和未逐项核对的共享图像仍保留原资源。上述清单是本轮已确认的例子，不是全仓剩余数量统计。

其中普通提示图标并不必然需要新设计稿，后续可以继续逐项适配；复杂插图需结合最终 OEM 视觉要求决定。色温滑块的暖/冷渐变、灰色禁用态及成功/警告/故障色继续保留其语义。

### 3.5 名称和国际化

- 欢迎页和侧边栏继续读取 `appName`，不硬编码新的页面名称。
- 定位等权限文案按 Lumineux 独立处理；同时提供 English 和简体中文，不能直接把共享文案全部替换为 Lumineux。
- 新增或修改的可见文案优先复用现有国际化 Key。

## 4. 已复制协议与改动量

已保存：

- [Privacy Policy.html](</Users/sr/Documents/SunSmart/sun-smart/Lumineux/Privacy Policy.html>)
- [User Agreement.html](</Users/sr/Documents/SunSmart/sun-smart/Lumineux/User Agreement.html>)

两份副本与 SLGSync 源文件逐字节一致，已加入 Lumineux 的 Copy Bundle Resources，没有替换原文。它们不是可直接发布的最终 Lumineux 协议。

统计口径：排除脚本、样式、注释和 HTML 标签，统一空白与 HTML 空格实体，包含页面 `<title>`、标题和正文；按最长名称优先匹配，避免把 `SLG Sync Plus` 中的 `SLG` 重复计数。邮箱及 HTML 链接另计。

| 名称类别 | Privacy Policy | User Agreement | 合计 |
| --- | ---: | ---: | ---: |
| `SLG Sync Plus` | 6 | 6 | 12 |
| `SLG Lighting Inc` | 1 | 9 | 10 |
| 独立 `SLG` | 5 | 41 | 46 |
| 品牌名称出现次数 | 12 | 56 | 68 |
| 涉及品牌名称的源码行数 | 10 | 32 | 42 |

68 是出现次数，不是 68 个不同条款。同一段可能多次出现名称。

### 4.1 品牌名称位置

- Privacy Policy：第 7、124、135、139、143、151、164、211、303、335 行。
- User Agreement：第 7、111、114、118、122、130、134、142、150、162、166、174、182、186、190、226、230、234、238、298、306、310、314、318、322、330、334、338、342、350、362、366 行。

App 名称、品牌简称、公司主体应分别核对。`SLG Lighting Inc` 对应的公司主体不能仅凭 App 名称推断；本轮保留原文，不做自动替换。

### 4.2 联系邮箱

| Privacy Policy 行号 | 显示邮箱 | 实际 mailto 地址 | 状态 |
| --- | --- | --- | --- |
| 257 | support@slgus.com | support@slgus.com | 需要 OEM 联系方式 |
| 303 | support@slgus.com | support@mericher.com | 显示与实际链接不一致 |
| 339 | support@slgus.com | support@mericher.com | 显示与实际链接不一致 |

共 3 组联系方式。后续修改应同时处理显示文字和 href，不能只改页面可见文字。

### 4.3 旧品牌网页地址和其他确认项

- 两份 HTML 各有 3 个带旧品牌路径的网页元数据 URL，共 6 处：Privacy Policy 第 10、11、104 行；User Agreement 第 10、11、91 行。这些是 oEmbed 和 canonical 引用，不是 App 当前协议入口。
- User Agreement 第 358、362、370 行涉及 Texas、Houston 和协议签订地点，列为内容确认项，本轮不修改，也不提供条款适用性结论。
- 两份现有 HTML 都是英文。协议翻译和最终发布文案在用户确认正文改动后处理，本轮不自行生成。
- 已通过实际 bundle 内容及欢迎页、“关于”页的协议路由测试；没有只修改未使用的协议 URL 常量。

| 文件 | SHA-256（与 SLGSync 原件相同） |
| --- | --- |
| Privacy Policy.html | `25c028291a17557bd9bb4d9f79b491f5dde9186868d5de2bd16fc593aed0d969` |
| User Agreement.html | `39e7a4ddbb8d996fabef0ea84191135ae68f7a81e5bfc32c17ac221dd5fc2d40` |

## 5. 明确不处理

- 不设置专用 `appKey`、`appSecret`，不复制 SLG 的云端身份。
- 不修改默认服务器、可选地区、首次地区选择或菜单中的服务器入口。
- 不继承 SLGSync 的色温快捷按钮和详细控制默认值。
- 不更换 Bugly App ID，不改 Mesh 设备协议或 SDK。
- 不修改协议正文、邮箱、公司主体、地域条款及翻译。
- 不改动其他品牌资源，不提交或推送 Git。

## 6. 验证记录

复现命令与测试边界见 [Tests/Branding/README.md](/Users/sr/Documents/SunSmart/sun-smart/Tests/Branding/README.md)。测试使用临时 XCTest 工程编译实际 App 与生产 UIKit 视图，未向正式工程或 AppDelegate 加入测试入口。

| 检查 | 结果 |
| --- | --- |
| Debug/Release 实际配置与 PBX 资源关系 | 通过：名称、Bundle ID、Team、签名类型、版本、编译条件、plist、资源和 Pods 归属 |
| Logo/图标与协议 | 通过：88/120 逻辑尺寸的三倍率资源、无透明通道的 1024 AppIcon、精确蓝色、源图 SHA-256、两份协议逐字节一致 |
| 英文 UIKit 运行测试 | 17 项 × 3 设备 = 51 次通过，0 失败、0 跳过 |
| 简体中文 UIKit 运行测试 | 17 项 × 3 设备 = 51 次通过，0 失败、0 跳过 |
| 实际布局 | 已导出两种语言的截图并检查代表页面；所有测试窗口的几何/状态断言通过，诊断日志无约束冲突或不平衡的 appearance 警告 |
| Lumineux Debug / Release | Debug 实际 App 与测试宿主构建通过；正式 workspace 的真机架构 Release 签名构建通过 |
| Release 签名完整性 | `codesign --verify --deep --strict` 通过；证书 `Apple Development: Wen Xu (Y4NBSLQQ63)`，Team `JTD3WYUC58`，Bundle ID 正确 |
| 其他品牌最终构建 | SunSmart、Archipelago、SLG Sync Plus、SylSmart 的最终 Debug 模拟器构建均通过 |
| SDK / 未确认的业务设置 | SDK 依赖检查通过，两个既有 Package.resolved 未改；服务器、请求头、空间默认值和 SLGSync 原文件未改 |
| 代码复核 | 配置与主题任务复核通过；最终两项普通图标/派生色遗漏已修复并通过限定范围复核，未发现修复引入的重要回归 |

设备矩阵为 iOS 18 的 iPhone SE 3、iPhone 16、iPad Pro 11 M4，语言为 `en/US` 与 `zh-Hans/CN`，合计 102 次测试运行。现有 Bugly 二进制的 arm64 slice 属于真机，不能用于 arm64 模拟器；本次使用已有的 x86_64 模拟器 slice，没有升级或替换依赖。真机架构 Release 使用 arm64。

测试覆盖启动页、Welcome 协议勾选与禁用态、菜单、Sites 空页和卡片控件、按钮/滑块回调、普通图标像素、DALI 开关、AUTO 加载恢复、Dongle 编辑、固件删除入口、组选择、应急测试/RxTx 状态及场景描边。实际设备命令、云端写入、删除操作均未执行。Group AUTO 的 Mesh 发送路径、Restore 整页自动蓝牙扫描不在运行测试中触发，对应图片入口另做源码与资源契约核对。

未在真实 iPhone/iPad 上安装、启动或连接设备验证；签名构建成功不代表真机功能和视觉已验收。其他四个品牌进行构建及条件分支/工程配置核对，没有逐个品牌运行完整 UI 测试。

本机临时证据目录为 `/private/tmp/lumineux-branding.m6gWea`：`verified-en.xcresult`、`verified-zh.xcresult`、`verified-release.log`、`verified-build-*.log`、`verified-*-screenshots` 和 `verified-*-diagnostics`。临时文件不进入仓库，清理系统临时目录后可按 README 重跑。

## 7. 下一步

1. 根据第 4 节确认协议中的 App 名称、品牌简称、公司主体、联系方式和地域内容，再修改正文与翻译。
2. 产品确认服务器、云端身份和空间默认设置后，单独处理这些业务配置。
3. 按第 3.4 节决定剩余共享图像/提示配色是否继续统一，并在真实设备上完成最终视觉及设备功能验收。
