# Simulate Fault 需求完整性分析

## 结论

需求范围、权限口径、按钮事件边界、固定 tag、按钮状态、自适应高度、滚动兜底、品牌 target、本地化和 iPad 页面宽度边界均已确认。最终方案采用“独立弹窗组件，Light 页面直接接入”，正式规格见 `docs/superpowers/specs/260716_1114_simulate_fault_design.md`。

本轮只完成代码与 Figma 结构核查及设计确认，不修改业务代码。正式规格经用户审阅后，再编写详细实施计划。

## 已确认的代码事实

### 真实设备详情入口

- Light：`DevicesViewController` → `DeviceLightsViewController` → 长按 Light item → `DeviceLightViewController`。
- 已确认本功能仅接入 `DeviceLightViewController` 的右上角 More 菜单。
- 8-key power switch、Emergency Fire Controller、Wi-Fi Gateway、普通 kinetic switch、dongle、未绑定 virtual device、DALI 和 `DeviceBaseViewController` 均不在本次范围内。

### 菜单实现现状

- Light 菜单由 `DeviceLightViewController.moreClick()` 独立组装。
- “最下面一栏”需要在 Light 页面组装完原有菜单后，最后 append `Simulate Fault`。
- `MenuPopView` 默认点击 item 后会先触发回调并关闭菜单，适合随后展示底部抽屉。
- 当前工作区已经存在未提交的 `menu_debug` 与 `black_debug` 资源，后续应复用并检查它们在共享 Assets 与四个品牌 target 中的可见性，不应重复创建。

### 权限真值层

- `SpaceData.deviceOperates.contains(.edit)` 是当前会话的有效编辑能力真值。
- 它不仅覆盖字面 Owner/Editor，也会在 Visitor、Editor 被临时降级、Mesh OTA 分发期间移除 `.edit`。
- 已确认本功能使用该 capability 作为菜单显示条件，而不是直接比较 `permission == .owner || .editor`。
- Owner 和正常 Editor 可见；Visitor、被临时降级的 Editor、Mesh OTA 分发限制期间不可见。

### 品牌 target 范围

- 已确认 SunSmart、Archipelago、SLG Sync Plus、SylSmart 全部开放本功能。
- 菜单、弹窗、本地化和图片资源均走共享实现，不增加品牌条件分支。
- 实施后需要确认新增/修改资源对四个 target 均可见，并按项目构建条件检查受影响 target。

### 国际化文案

- English：按 Figma 原文使用 Simulate Fault、Motion Sensor、Photocell Sensor、Light Status、Minor (3)、Major (2)、Critical (1)、Normal、Fault、Dim、Flicker、Dim Flicker、Off。
- 简体中文：模拟故障、移动传感器、光感传感器、灯具状态、轻微 (3)、严重 (2)、紧急 (1)、正常、故障、调光、闪烁、调光闪烁、关闭。
- 用户明确修正的最终译文为：Critical (1) → 紧急 (1)，Dim → 调光，Dim Flicker → 调光闪烁。
- 所有用户可见文案进入 English 与简体中文 `Localizable.strings`，不硬编码。

## Figma 结构核查

设计节点：`295:12911`。

- 参考画布：375 × 812 pt。
- 背景遮罩：黑色，30% 透明度。
- Figma 参考稿中的底部内容区从 y=426 开始，到屏幕底部约 386 pt；该数值只作为当前 375 pt 画布的视觉结果，不作为实现中的固定高度。
- Header：`black_debug` 图标与 `Simulate Fault` 标题。
- 三个状态区：Motion Sensor、Photocell Sensor、Light Status。
- 每个状态区包含左侧标题、右侧严重级别 tag，以及按钮集合。
- Motion Sensor：Normal、Fault；tag 为 Minor (3)。
- Photocell Sensor：Normal、Fault；tag 为 Major (2)。
- Light Status：Normal、Dim、Flicker、Dim Flicker、Off；tag 为 Critical (1)。
- 已确认三个 tag 均为固定内容，不随按钮点击、设备状态或事件回调变化。
- 手机宽度下 Light Status 为 4+1 两行；需求要求 iPad/宽屏下一行展示完整 5 个按钮。
- 点击内容外遮罩需要关闭抽屉；点击按钮只向页面控制器抛出事件，不关闭抽屉。

### 事件交付边界

- 已确认本轮只把按钮点击转换为强类型事件并回调给 `DeviceLightViewController`。
- Motion Sensor 事件：Normal、Fault。
- Photocell Sensor 事件：Normal、Fault。
- Light Status 事件：Normal、Dim、Flicker、Dim Flicker、Off。
- 本轮不发送任何 Mesh/vendor 命令，不展示成功或失败提示，也不在按钮点击后关闭弹窗。
- `DeviceLightViewController` 只接收事件并预留后续处理边界，不在本轮增加模拟故障业务逻辑。

## 推荐架构方向

### 菜单接入

在 Light 页面增加一个聚焦的 Simulate Fault 展示入口，并把弹窗 UI 保持为独立可测试组件。Light 页面只负责：

1. 根据权限条件决定是否追加菜单项；
2. 将菜单项 append 到现有 items 的最后；
3. 接收弹窗按钮事件。

由于当前只有一个调用页面，不额外引入跨设备菜单工厂或菜单协议，避免过度设计。

### 弹窗容器

使用独立 UIKit overlay View 覆盖当前设备页面：

- 根层负责遮罩、内容外点击关闭、展示/收起动画和生命周期；
- overlay 安装在当前 `DeviceLightViewController.view` 内，宽度和点击区域都以当前设备详情页面的可用宽度为边界，不扩展到物理 iPad window；
- content 不设置固定高度，由 header、三张状态卡、卡片间距、上下内边距和底部安全区的垂直约束共同推导高度；
- content 内部使用垂直布局，三张状态卡随可用宽度拉伸；
- 手机上 Light Status 换成两行时 content 自然增高；宽屏上一行展示时 content 自然变矮；
- 正常内容高度小于页面可用高度时不滚动；当极小屏幕、大字号或文案增长导致内容超高时，content 最大高度受页面可用高度约束，并启用内部垂直滚动，保证所有内容可访问；
- 不使用系统 `UIAlertController`，因为它不能满足底部贴边、整宽、自适应 collection view 和内容外点击收起的组合要求。

### 状态卡与按钮

- 抽取一个共享的状态卡布局内核，分别配置 Motion Sensor、Photocell Sensor、Light Status 三个自定义 View。
- 每张卡内部使用不可滚动的 `UICollectionView`。
- item 采用固定宽高与间距；根据可用宽度计算每行数量，并通过 collection content height 回写自身高度。
- 已确认 item 只使用瞬时 highlight/按压反馈，手指松开后恢复默认样式，不保持选中态，也不维护 selection model。
- 点击事件统一转换成强类型 action，再由弹窗暴露给当前设备 View Controller。

## 已收口的工程决策

- 增加窄范围自动化验证，覆盖权限判定、菜单顺序、9 种事件映射和布局计算。
- 如果现有测试 target 不适合直接实例化 UI，则抽取纯事件与布局计算逻辑进行测试，并用轻量 contract 检查菜单接入和本地化完整性。
- 最终使用四个品牌 target 的 iPhoneOS 构建完成共享资源和代码验收。

## 可选实现方案

### 方案 A：独立弹窗组件，Light 页面直接接入（已确认采用）

- 优点：改动聚焦；视觉与交互职责独立；Light 页面只增加菜单项、展示入口与事件接收；后续接协议时不需要改弹窗布局。
- 缺点：如果未来扩展到其他设备页，需要再抽取共享菜单入口。

### 方案 B：提前引入统一设备菜单协议/工厂

- 优点：长期可统一所有设备菜单和权限处理。
- 缺点：现有页面结构差异很大，部分继承、部分组合、部分 extension，容易把本需求扩大成菜单架构重构，不符合聚焦原则。

### 方案 C：把弹窗布局直接写进 Light 页面

- 优点：文件数量较少。
- 缺点：设备控制、菜单、遮罩、collection view 高度计算和弹窗生命周期混在同一控制器中，不利于测试与维护，不推荐。

## 初步验收建议

- `space.deviceOperates.contains(.edit)` 为 true：Light 设备页菜单最后一项显示 `Simulate Fault`。
- Visitor、被临时降级的 Editor、Mesh OTA 分发限制期间：不显示该菜单项。
- Visitor、被降级的 Editor、Mesh OTA 限制态：不显示该项。
- 点击菜单项：原菜单关闭，底部抽屉在当前设备页展示。
- iPhone 与 iPad 上 overlay、遮罩和 content 均与当前 `DeviceLightViewController` 页面同宽，不越过页面容器。
- 点击遮罩：抽屉收起；点击 content、卡片或按钮：不误收起。
- 每个按钮都有按压反馈，并向宿主 VC 抛出正确 action；抽屉保持显示。
- 松开按钮后恢复默认样式，重新展示弹窗时不存在残留选中态。
- 任何按钮点击都不发送 Mesh/vendor 命令，也不展示操作结果提示。
- 375 pt 宽度下 Light Status 为两行；iPad 可用宽度足够时为一行。
- 弹窗高度由内部内容与垂直约束得出，不使用固定高度；不同按钮行数会自然改变弹窗高度。
- 当内容总高度超过页面可用高度时，弹窗限制最大高度并允许内部垂直滚动，所有 header、tag 和按钮均可访问。
- English 与简体中文均无硬编码缺失或截断。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 的资源可见性与编译结果均通过检查。
