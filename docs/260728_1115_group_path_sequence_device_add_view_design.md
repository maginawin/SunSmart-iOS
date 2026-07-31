# GroupPathSequenceDeviceAddView 固定布局与展开状态设计

## 1. 文档状态

- 状态：已完成需求澄清与分段设计评审，等待最终文档确认。
- 范围：设计与后续实现只覆盖公共添加 View、其直接内容、调用方布局策略和聚焦测试。
- 不在本设计中启用 Space Trigger Zone 入口。
- 不在本设计中对 selected 状态进行新一轮视觉重排。

## 2. 目标

修复 `GroupPathSequenceDeviceAddView` 首次进入页面默认展开、closed/open 高度不精确、箭头方向错误、默认提示列随文案漂移，以及组件内横纵向尺寸依赖 `SCRXFrom`、`SCRYFrom` 的问题。

实现后：

- 首次进入 Group Path Sequence 页面时默认 closed。
- 选中 Path 或 Zone 后自动 open。
- Group 页面使用固定的基础内容高度。
- Manually Add 多行展开能力保留。
- 隐藏的 Space Trigger Zone 继续复用公共 View，但 selected 内容保留动态高度。
- selected 状态只做固定 point 改造，后续由用户真机校验后再提出视觉优化。

## 3. 非目标

- 不修改 Space More 列表，不展示或启用 Space Trigger Zone。
- 不新增 Space 专用 View 子类。
- 不让 Space Controller 继承 Group Controller。
- 不重构 Path/Zone 的数据模型、设备添加业务、Mesh 消息处理或保存流程。
- 不修改 `TitleSelectView`、`AdaptiveTextView` 等通用组件内部。
- 不新增或修改用户可见文案、本地化资源、依赖或 target 配置。
- 不顺手处理本组件之外的其他 `SCRXFrom`、`SCRYFrom`。

## 4. 已确认方案

采用“公共 View + 显式高度策略配置”。

公共 `GroupPathSequenceDeviceAddView` 统一负责：

- closed/open 状态。
- 标题、箭头、添加方式菜单和内容卡片的外壳布局。
- safe area 处理。
- 当前添加方式内容的显隐。
- 高度计算与高度变化回调。

调用方只负责选择高度策略：

- Group Path Sequence 的 Sequence 页面：固定基础内容高度策略。
- Group Path Sequence 的 Trigger Zone 页面：固定基础内容高度策略。
- Space Trigger Zone：动态 selected 内容高度策略，入口继续隐藏。

公共 View 不读取 Group、Path、Zone 或 Space 业务数据。

## 5. 状态设计

### 5.1 closed

- 组件初始化状态为 closed。
- 只显示标题行和右侧箭头。
- 标题行顶部与组件顶部间距为 0。
- 标题行固定高度为 44。
- 箭头使用 `arrow_up_black`。
- 添加方式菜单和内容卡片隐藏。
- 整体高度为 `44 + safeAreaInsets.bottom`。

### 5.2 open

- 点击标题行从 closed 切换到 open。
- 标题行继续保持 44。
- 箭头切换为 `arrow_down_black`。
- 添加方式菜单和内容卡片显示。
- 再次点击标题行恢复 closed。

### 5.3 自动展开

- 首次进入页面不自动展开。
- 用户选中 Path 或 Zone 后，Controller 继续主动将组件切换为 open。
- 取消选择不强制切换为 closed，保留组件当时的展开状态。
- 切换 Quick Add、Trigger Add、Manually Add 不改变 closed/open 状态。

### 5.4 状态保留

closed/open 往返只改变可见区域、箭头和高度，不重置：

- 当前添加方式。
- Quick Add 的 adding/pause/stop 状态。
- 过滤条件。
- 是否显示已添加设备。
- Trigger Add、Manually Add 的设备列表与选择。
- Manually Add 当前展开行数。

### 5.5 无数据状态

- 没有 Path 或 Zone 时，调用方继续隐藏整个组件。
- 隐藏状态高度为 0。
- 创建首个 Path 或 Zone 后，组件按默认 closed 状态出现。

## 6. 固定布局

### 6.1 外壳约束

移除当前通过顶部 6、标题 40、标题与 body 间距 4、底部 14 拼接出来的 Stack 高度。

改为直接约束：

- 标题行：顶部 0，高度 44。
- 添加方式菜单：顶部贴标题行底部，高度 44。
- 内容卡片：顶部距离菜单底部 8。
- 内容卡片：左右距离父 View 16。
- 内容卡片：底部距离 safe area 8。
- 内容卡片圆角保持现有视觉值，但改为固定 point。

父 View 的约束和高度回调使用同一组集中布局常量，禁止分别维护重复数字。

### 6.2 Group 基础高度

Group 固定高度策略下：

- 标题行：44。
- 添加方式菜单：44。
- 菜单至内容卡片：8。
- 内容卡片基础高度：160。
- 内容卡片至 safe area：8。
- 底部 safe area。

因此 Group open 基础高度为：

`44 + 44 + 8 + 160 + 8 + safeAreaInsets.bottom`

即：

`264 + safeAreaInsets.bottom`

### 6.3 Manually Add 多行

- 默认提示和 selected 单行状态的内容卡片高度均至少为 160。
- Manually Add 展开到 2～3 行时，使用 160 与实际首选内容高度中的较大值。
- 父 View 按增加后的内容卡片高度同步增高。
- 不引入卡片内部纵向滚动。
- 不移除现有展开/收起按钮或横向分页。

### 6.4 Space 动态高度

Space Trigger Zone 继续隐藏，但源码仍需保持可编译。

Space 高度策略：

- closed 外壳行为与公共 View 一致。
- 默认提示内容高度至少为 160。
- selected 内容使用 160 与当前动态首选高度中的较大值，以容纳 Group Filter 和额外提示。
- 本任务不启用入口，也不对 Space selected 布局进行视觉验收承诺。

## 7. 默认提示三列布局

### 7.1 目标

三个步骤提示不再根据不同文案宽度改变水平位置，第二个步骤始终位于内容卡片水平中心。

### 7.2 约束

- 步骤容器左右边距各 16。
- 三个步骤项之间间距各 16。
- 三个步骤项等宽。
- 单项宽度由 Auto Layout 自动得到：

`(addingContentView.width - 16 × 4) / 3`

- 每个标题只在自己的等宽列内换行。
- 第二列中心与内容卡片中心严格重合。
- 图标、文字和连接线继续保持现有视觉关系，只把尺寸改为固定 point。

### 7.3 复用隔离

`GroupPathSequenceDeviceAddStepView` 还被 Profile、设备添加说明和设备重置页面复用。

因此：

- 公共步骤 View 增加显式的等宽三列布局配置。
- 本添加组件的 Quick、Trigger、Manually 默认提示启用该配置。
- 其他调用方默认配置与现有布局保持一致。
- 不对其他页面做隐式全局改版。

## 8. selected 内容缩放清理

### 8.1 清理文件

以下文件中的 `SCRXFrom`、`SCRYFrom` 全部替换为对应固定 point：

- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift`

包括：

- Auto Layout 约束常量。
- 固定宽高。
- 圆角。
- 菜单宽度、行高和定位偏移。
- Collection View spacing 与 inset。
- 首选内容高度计算。
- 按钮水平偏移。
- 注释中已废弃的缩放代码。

### 8.2 公共步骤 View

`GroupPathSequenceDeviceAddStepView` 不做无差别全局缩放清理。

本组件启用的等宽三列配置使用固定 point；公共步骤 View 的旧默认布局保留，以避免影响无关页面。

### 8.3 保持现状的含义

本任务对 selected 内容只做以下改变：

- 移除横纵向缩放。
- 适配 160 基础高度。
- 保证现有约束在固定值下可编译、无明显冲突。

本任务不主动改变：

- 过滤器数量和排列。
- 菜单内容。
- 按钮位置关系。
- 设备 Cell 视觉结构。
- Collection View 行列和分页规则。
- Quick Add 操作流程。
- Trigger Add 刷新和识别流程。
- Manually Add 展开方式。

完成后由用户校验 selected UI，再单独提出下一轮优化需求。

## 9. 高度数据流

### 9.1 输入

高度计算只依赖：

- View 是否隐藏。
- closed/open 状态。
- 调用方选择的高度策略。
- 当前添加方式。
- 当前显示默认提示还是 selected 内容。
- Manually Add 当前行数与首选内容高度。
- `safeAreaInsets.bottom`。

### 9.2 触发时机

以下事件刷新首选高度：

- 初始化并完成首次布局。
- closed/open 切换。
- safe area 变化。
- Quick/Trigger/Manually 模式切换。
- 默认提示与 selected 内容切换。
- Manually Add 行数变化。
- selected 子视图报告的首选高度变化。

### 9.3 输出

- View 继续通过现有高度变化闭包通知 Controller。
- Controller 继续更新底部 View 的高度约束。
- 新高度与上次高度差不超过现有容差时不重复回调。
- 页面出现后的切换继续使用现有 0.25 秒父布局动画。
- 初始布局不执行不必要的入场动画。

### 9.4 safe area

- `safeAreaInsets.bottom` 是唯一 safe-area 高度真值。
- 不在公共 View 内叠加 `kSafeAreaBottomHeight`。
- safe area 为 0 时公式仍成立。
- safe area 改变时同时刷新约束和高度回调，避免两者不一致。

## 10. 调用方职责

### 10.1 Group Sequence

`GroupPathSequenceViewController`：

- 明确配置 Group 固定高度策略。
- 页面首次进入时不主动 open。
- 选中 Path 后继续主动 open。
- 继续持有 Path、设备、Quick Add 和 delegate 业务状态。

### 10.2 Group Trigger Zone

`GroupPathSequenceTriggerZoneController`：

- 明确配置 Group 固定高度策略。
- 页面首次进入时不主动 open。
- 选中 Zone 后继续主动 open。
- 继续持有 Zone、设备、Trigger Add 和 delegate 业务状态。

### 10.3 Space Trigger Zone

`SpacePathTriggerZoneController`：

- 明确配置 Space 动态 selected 高度策略。
- 继续直接组合公共 View。
- 不新增子类。
- 不修改入口状态。

`SpaceMoreViewController`：

- 不加入 `.triggerZone`。
- 现有隐藏状态保持不变。

## 11. 边界处理

- English 与简体中文步骤文案均限制在等宽列内换行。
- iPhone 和 iPad 使用相同固定 point，不再按设计稿比例缩放。
- Collection View 的设备项宽度仍根据容器实际宽度计算，固定 spacing/inset 后重新得到结果。
- 160 高度不足以容纳 Manually Add 多行时使用动态增高，不压缩或裁剪设备列表。
- Space 双过滤器内容超过 160 时使用动态增高。
- closed 时刷新按钮和 Manually Add 展开按钮隐藏。
- open 后附件按钮根据当前模式和数据恢复现有显示规则。
- 不因布局切换清理 Mesh 消息状态或设备数据。

## 12. 测试设计

### 12.1 聚焦源码契约测试

新增独立源码契约测试，至少验证：

- 默认状态为 closed。
- closed 使用向上箭头。
- open 使用向下箭头。
- 标题高度为 44。
- 菜单高度为 44。
- 内容卡片基础高度为 160。
- 卡片顶部与底部间距均为 8。
- 卡片左右边距均为 16。
- Group open 基础高度为 `264 + safe area`。
- Manually Add 使用 160 与实际内容高度中的较大值。
- 存在 Group 固定策略和 Space 动态策略。
- 默认提示启用左右 16、项间 16、三列等宽配置。
- 五个目标文件中不存在 `SCRXFrom`、`SCRYFrom`。
- Space More 的实际选项列表仍未加入 `.triggerZone`。

测试使用独立 `swiftc` 编译运行，不依赖 Simulator。

### 12.2 静态检查

- 运行 `git diff --check`。
- 检查目标文件无新增硬编码用户可见文案。
- 检查未修改本地化、资源、依赖和 target membership。
- 检查改动未扩散到无关模块。

### 12.3 iPhoneOS 构建

相关 View 同时属于四个品牌 target，必须直接使用 generic iPhoneOS、关闭签名构建：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

不使用：

- Simulator。
- shell 包装。
- 日志重定向。

### 12.4 真机 UI 验收

构建通过不能证明布局正确。真机至少检查：

- 首次进入 Sequence 和 Trigger Zone 均为 closed。
- closed/open 箭头和高度正确。
- 有、无底部 safe area 的设备表现正确。
- 选中 Path/Zone 自动 open。
- English、简体中文的第二步提示严格居中。
- 三个提示标题列宽一致。
- Quick、Trigger、Manually selected 状态仍可操作。
- Manually Add 1～3 行切换不裁剪。
- closed/open 往返不丢失状态。

selected 状态的视觉细节由用户在本任务后继续校验，不把后续 UI 优化计入本任务完成条件。

## 13. 影响文件

预计修改：

- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddStepView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceAddDeviceCell.swift`
- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`
- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift`
- `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`

预计新增：

- `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`

明确不修改：

- `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`
- 本地化文件。
- Asset Catalog。
- 依赖配置。
- Xcode target membership。

## 14. 完成条件

同时满足以下条件才视为实现完成：

- 需求中的 closed/open 状态与固定高度契约全部落地。
- 默认提示三列等宽且第二列严格居中。
- 约定的五个目标文件不再包含 `SCRXFrom`、`SCRYFrom`。
- Manually Add 多行动态增高保留。
- Space Trigger Zone 继续隐藏且源码可编译。
- 聚焦契约测试通过。
- `git diff --check` 通过。
- 四个品牌 scheme 的 generic iPhoneOS 构建通过。
- 自动化和构建结论与真机 UI 待验收项明确区分。

