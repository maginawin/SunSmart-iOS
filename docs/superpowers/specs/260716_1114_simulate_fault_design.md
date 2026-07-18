# Simulate Fault 设计规格

## 1. 目标

在 Light 设备详情页 `DeviceLightViewController` 的右上角菜单最末尾增加 `Simulate Fault`。仅当前 Space 具备有效编辑能力时显示。点击后在当前 Light 设备页面内展示底部弹窗，弹窗提供 Motion Sensor、Photocell Sensor、Light Status 三组模拟事件按钮。

本轮只把按钮事件传递给 `DeviceLightViewController`，不发送 Mesh/vendor 命令，不展示结果提示，不维护故障状态。

## 2. 范围

### 2.1 包含

- `DeviceLightViewController` 右上角 More 菜单。
- `Simulate Fault` 底部弹窗、遮罩、展示与收起动画。
- Motion Sensor、Photocell Sensor、Light Status 三个自定义状态区。
- collection view 按钮的自适应换行、高度计算与点击反馈。
- 9 种强类型按钮事件。
- English 与简体中文本地化。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个品牌 target。

### 2.2 不包含

- 8-key power switch、Emergency Fire Controller、Wi-Fi Gateway、普通 kinetic switch、dongle、未绑定 virtual device、DALI、`DeviceBaseViewController` 或其他设备页面。
- Mesh/vendor 模拟故障命令。
- 按钮选中状态、故障状态持久化或设备状态联动。
- NordicSigMeshSDK 修改或依赖切换。
- 全局设备菜单协议、基类或菜单架构重构。

## 3. 权限规则

菜单展示和弹窗展示前的最终校验统一使用：当前 Space 是否具备有效编辑能力。

该条件以 `space.deviceOperates.contains(.edit)` 为唯一真值层：

- Owner：正常情况下显示。
- 正常 Editor：显示。
- Visitor：不显示。
- 被临时降级的 Editor：不显示。
- Mesh OTA 分发限制期间：不显示。

如果用户打开菜单后、点击 `Simulate Fault` 前权限已变化，展示前校验阻止弹窗出现。弹窗展示期间如果权限变化并失去 `.edit`，弹窗自动关闭。

## 4. 菜单设计

- 菜单项标题：`Simulate Fault`，使用本地化 key。
- 菜单图标：`menu_debug`。
- 菜单项只能添加到 `DeviceLightViewController.moreClick()` 生成的 items 最末尾。
- 菜单项不受 Debug/Release 条件编译影响，符合权限条件时两个配置均显示。
- 点击菜单项后先关闭 `MenuPopView`，再展示底部弹窗，避免两个浮层重叠。
- 其他设备页面的菜单保持现状。

## 5. 组件架构

采用“独立弹窗组件，Light 页面直接接入”方案。

### 5.1 DeviceLightViewController

职责：

- 按有效编辑能力追加菜单项。
- 展示、关闭并持有当前弹窗实例。
- 接收强类型 `SimulateFaultAction`。
- 在页面退出或权限丢失时清理弹窗。

控制器不负责弹窗内部布局，也不在本轮处理 Mesh/vendor 命令。

### 5.2 SimulateFaultOverlayView

职责：

- 覆盖当前 `DeviceLightViewController.view`。
- 管理遮罩、底部 content、滚动容器和安全区。
- 管理展示/收起动画与重复展示保护。
- 汇总三个状态区事件并向控制器回调。

### 5.3 SimulateFaultSectionView

作为三个自定义状态区的共享布局实现，分别配置为 Motion Sensor、Photocell Sensor、Light Status。

职责：

- 展示左侧标题和右侧固定 tag。
- 管理内部不可滚动 collection view。
- 根据按钮数量与可用宽度计算行数及自身高度。
- 把 item 点击转换为对应 action。

### 5.4 SimulateFaultButtonCell

职责：

- 展示固定尺寸按钮。
- 提供瞬时按压反馈。
- 松手或取消触摸后恢复默认样式。
- 不保存选中态。

### 5.5 SimulateFaultAction

定义以下 9 种强类型事件：

- Motion Sensor：Normal、Fault。
- Photocell Sensor：Normal、Fault。
- Light Status：Normal、Dim、Flicker、Dim Flicker、Off。

事件由 cell → section → overlay → `DeviceLightViewController` 单向传递。不得通过显示标题或裸 index 在控制器中反推事件。

## 6. 视觉与布局

### 6.1 Overlay 与 content

- Overlay 四边约束到 `DeviceLightViewController.view`，遮罩、点击区域和 content 都不得越过当前设备详情页面容器。
- 遮罩为黑色 30% 透明度。
- content 左右和底部贴合页面，顶部左右圆角为 20 pt。
- content 宽度始终等于当前 Light 设备页面可用宽度，不扩展到物理 iPad window。
- content 不设置固定高度。
- content 高度由 header、三个状态区、区间距、上下内边距和底部安全区的完整垂直约束推导。
- Figma 中约 386 pt 的高度只是 375 × 812 pt 参考画布的布局结果，不作为常量。

### 6.2 高度与滚动

- 正常情况下 content 由内容自然撑开，外层不滚动。
- 手机上 Light Status 换成两行时弹窗自然增高。
- 宽屏上一行容纳五个 Light Status 按钮时弹窗自然变矮。
- content 顶部不得越过当前页面安全区域。
- 极小可用高度、大字号或未来文案扩展使自然高度超过可用高度时，弹窗限制最大高度并启用内部垂直滚动，确保 header、tag 和所有按钮均可访问。
- 状态区内部 collection view 始终不可滚动，其高度必须覆盖全部 item。

### 6.3 Header 与状态区

- 弹窗 Header 使用 `black_debug` 图标和 `Simulate Fault` 标题。
- 三个状态区使用 Figma 的内容背景、圆角、内边距、字体和颜色。
- 状态区标题位于左侧，固定 tag 位于右侧。
- tag 内容与颜色固定，不随点击、设备状态或事件回调变化：
  - Motion Sensor：Minor (3)。
  - Photocell Sensor：Major (2)。
  - Light Status：Critical (1)。

### 6.4 Collection view 按钮

- item 固定为 71 × 28 pt。
- 列间距、行间距依据 Figma 保持约 7–9 pt。
- item 左对齐排列，根据 collection view 当前可用宽度计算每行数量。
- 375 pt 页面宽度下，Light Status 为 4+1 两行。
- iPad 等宽页面空间足够时，Light Status 五个按钮为一行。
- 宽度变化后必须重新计算列数、collection view 高度和弹窗自然高度。

## 7. 交互

- 展示时遮罩淡入，content 从底部滑入，建议时长约 0.25 秒。
- 关闭时执行反向动画并移除 overlay。
- 点击 content 外遮罩关闭弹窗。
- 点击 content 空白、Header、状态区或按钮均不得关闭弹窗。
- 点击按钮只产生瞬时按压反馈，松手后恢复默认样式。
- 按钮点击后不保留选中态，重新打开弹窗时也不存在残留状态。
- 按钮点击后弹窗继续展示。
- 当前页面已有弹窗时，重复展示请求不得叠加第二个实例。

## 8. 国际化

所有用户可见文案进入 English 与简体中文 `Localizable.strings`，禁止硬编码。

| English | 简体中文 |
| --- | --- |
| Simulate Fault | 模拟故障 |
| Motion Sensor | 移动传感器 |
| Photocell Sensor | 光感传感器 |
| Light Status | 灯具状态 |
| Minor (3) | 轻微 (3) |
| Major (2) | 严重 (2) |
| Critical (1) | 紧急 (1) |
| Normal | 正常 |
| Fault | 故障 |
| Dim | 调光 |
| Flicker | 闪烁 |
| Dim Flicker | 调光闪烁 |
| Off | 关闭 |

优先复用现有语义完全一致的 key；没有合适 key 时新增 feature-scoped key，并同时补齐两种语言。

## 9. 生命周期与安全边界

- 弹窗事件回调使用弱引用，避免 overlay 与控制器形成循环引用。
- `DeviceLightViewController` 页面退出时关闭并释放弹窗。
- 权限变化为不可编辑时关闭弹窗。
- action 接收方缺失时安全忽略事件；cell 必须正常恢复视觉状态。
- 不把 overlay 添加到全局 window，不影响当前设备页面外的交互。
- 不访问网络，不发送 Mesh/vendor 消息，不修改 `Node` 或 `SpaceData`。

## 10. Target 与资源

- SunSmart、Archipelago、SLG Sync Plus、SylSmart 全部开放。
- 菜单、弹窗、事件、本地化与图片资源走共享实现，不增加品牌条件编译。
- 复用工作区现有 `menu_debug` 和 `black_debug` 资源，不重复创建同名资源。
- 实施时检查共享 Assets 和新增 Swift 文件的 target membership，确保四个品牌 target 都能访问。

## 11. 验证与验收

### 11.1 自动化验证

- 权限判定：有效编辑能力有/无时菜单项显示结果正确。
- 菜单顺序：`Simulate Fault` 始终为 Light 菜单最后一项。
- 事件映射：9 个按钮各自产生唯一且正确的 action。
- 布局计算：375 pt 宽度下 Light Status 为两行，宽屏足够时为一行。
- 高度计算：collection view 高度覆盖全部 item，弹窗自然高度随行数变化。
- 交互合同：按钮点击不关闭弹窗、不保留选中态、不触发命令层。

如果现有测试 target 不适合直接实例化 UI，则把纯事件映射和行数/高度计算抽为可测试逻辑，并以轻量 contract 检查补足菜单接入与本地化完整性。

### 11.2 手工验收

- Owner、正常 Editor、Visitor、降级 Editor、Mesh OTA 限制态。
- 375 pt iPhone、常规大屏 iPhone、iPad 当前页面宽度。
- English 与简体中文。
- 遮罩关闭、content 防误关闭、9 个按钮点击、重复展示、页面退出、权限变化。
- 超高内容时内部滚动可以访问全部内容。

### 11.3 构建验收

- 使用 iPhoneOS generic destination 和 `CODE_SIGNING_ALLOWED=NO` 验证 SunSmart、Archipelago、SLG Sync Plus、SylSmart。
- 不使用 Simulator 作为最终构建验收。
- 不修改或切换 NordicSigMeshSDK。

## 12. 完成标准

- 功能只出现在 Light 设备详情页。
- 菜单权限、位置、标题和图标符合本规格。
- 弹窗视觉、宽度边界、自适应高度、滚动兜底和关闭行为符合 Figma 与确认要求。
- 9 种事件完整传入 `DeviceLightViewController`，且没有任何设备命令副作用。
- 两种语言和四个品牌 target 均通过验收。
- 改动聚焦，不重构无关菜单或设备模块。

