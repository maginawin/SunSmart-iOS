# GroupPathSequenceDeviceAddView 布局优化需求分析草案

## 1. 文档状态

- 当前状态：分析草案，等待需求确认。
- 本轮范围：只分析现状、需求完整性和设计选项，不修改业务代码。
- 目标组件：`GroupPathSequenceDeviceAddView` 及其直接承载的添加方式内容。

### 1.1 已确认决策

- `adding content view` 的基础高度固定为 160。
- 默认提示、Quick Add、Trigger Add 和 Manually Add 单行状态均使用基础高度 160。
- Manually Add 展开到 2～3 行时，允许内容卡片和父视图按现有规则动态增高。
- 不引入内容卡片内部纵向滚动，不移除 Manually Add 现有多行展开能力。
- 采用“公共 `GroupPathSequenceDeviceAddView` + 显式高度策略配置”。
- 不为 Space Trigger Zone 提前新增 View 子类，也不让 Space Controller 继承 Group Controller。
- Space Trigger Zone 继续保持隐藏；本任务不增加开发入口、不修改 More 列表，也不改变其发布条件。
- 对本组件及 selected 内容进行横纵向缩放全面清理，不保留相关 `SCRXFrom` 或 `SCRYFrom`。
- selected 状态完成本轮固定值改造后，先由用户校验实际 UI，再根据校验结果提出下一轮精细优化，不在本任务中提前重排 selected 布局。
- 首次进入 Group Path Sequence 页面时默认 closed；选中 Path 或 Zone 后继续沿用当前行为，自动切换为 open。
- 已确认采用推荐实现路径：公共 View 统一状态与外壳布局，通过显式高度策略区分 Group 固定基础高度与 Space 动态 selected 高度。
- 已确认父 View 改用固定值直接约束标题、菜单和内容卡片；默认提示采用本组件专用的三列等宽配置；selected 内容全面去除横纵向缩放但本轮不重排现有控件关系。

## 2. 已确认的现状

### 2.1 默认展开原因

`GroupPathSequenceDeviceAddView` 当前将 `collapsed` 初始化为 `false`，并在初始化末尾刷新展开 UI，因此只要页面存在 Path 或 Trigger Zone，底部添加视图就会以展开状态显示。

两个 Group Path Sequence 子页面在选中 Path 或 Zone 后还会主动调用 `setCollapsed(false, ...)`。因此当前行为分为：

- 页面首次进入、尚未选择 Path/Zone：默认展开并显示步骤提示。
- 选中 Path/Zone：保持或切换为展开，显示可添加内容。

将初始 `collapsed` 改为 `true` 即可满足“首次进入默认 closed”，同时保留“用户选中 Path/Zone 后自动展开”的现有行为。

### 2.2 当前 closed 高度不是目标高度

当前 closed 高度由以下项目组成：

- 顶部间距：6（经过 `SCRYFrom`）
- 标题行：40（经过 `SCRYFrom`）
- 底部间距：14（经过 `SCRYFrom`）
- 底部 safe area

因此当前结果是 `60 + safeAreaBottom`，不是目标的 `44 + safeAreaBottom`。

### 2.3 当前 open 高度是动态的

当前 open 高度由标题行、标题与菜单间距、菜单栏、内容卡片间距、动态内容高度、底部间距和 safe area 共同计算。

三个 selected 子视图都会报告自己的动态首选高度：

- Quick Add：根据默认过滤器或双过滤器布局返回不同高度。
- Trigger Add：根据普通或 Group Filter 布局返回不同高度。
- Manually Add：根据设备列表 1～3 行动态增加高度。

因此“adding content view 固定为 160”与现有动态高度机制不是简单的常量替换，需要先明确它对 selected 状态和 Manually Add 多行展开的约束。

### 2.4 默认提示位置漂移原因

默认步骤提示使用一个居中的横向 `UIStackView`：

- 三个步骤项宽度由各自文字的 Auto Layout 结果决定。
- 步骤项只设置最小宽度和最大宽度，没有等宽约束。
- Stack 使用 `.fill`，没有使用等分布局。

因此不同语言、不同提示文字长度会改变每一项的实际宽度，第二项虽然位于整体 Stack 中间区域，但不能保证自身中心始终等于卡片水平中心。

需求给出的公式可以精确落地为：

- Stack 左右各 16。
- 三个步骤项之间各 16。
- Stack 使用等宽分布。
- 每项宽度自动得到 `(addingContentView.width - 16 × 4) / 3`。

这样第二项中心会稳定落在 `addingContentView` 的水平中心，不依赖提示文字长度。

### 2.5 影响面不只一个页面

`GroupPathSequenceDeviceAddView` 当前被以下三个控制器复用：

- Group Path Sequence 的 Sequence 页面。
- Group Path Sequence 的 Trigger Zone 页面。
- Space Trigger Zone 页面。

其三个内容子视图也由该公共组件统一创建。公共步骤视图 `GroupPathSequenceDeviceAddStepView` 还被 Profile、设备添加说明和设备强制重置页面复用。

因此：

- 直接修改 `GroupPathSequenceDeviceAddView` 会同时影响三个使用页面。
- 直接把公共步骤视图全局改成等宽三列，会影响与本需求无关的页面。
- 推荐让步骤视图新增可配置的等宽三列布局，并只由本组件的三个提示视图启用，默认行为保持不变。

### 2.6 多 target 影响

相关文件同时加入了以下四个品牌 target：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

实现完成后需要同步进行四个 target 的 generic iPhoneOS 构建验证。

## 3. 可直接确定的布局契约

### 3.1 closed

- 初始状态为 closed。
- 标题行顶部贴父视图顶部，间距为 0。
- 标题行固定高度 44。
- 仅显示标题和右侧箭头。
- 按当前需求描述，closed 使用 `arrow_up_black`。
- 整体高度为 `44 + safeAreaInsets.bottom`。
- safe area 内不显示菜单和内容卡片。

### 3.2 open

按照当前文字要求，静态高度可计算为：

- 标题行：44
- 添加方式菜单行：44
- 菜单与内容卡片间距：8
- 内容卡片：160
- 内容卡片与 safe area 间距：8
- 底部 safe area

因此 open 总高度应为 `264 + safeAreaInsets.bottom`。

标题行与添加方式菜单行之间没有额外间距。内容卡片左右边距均为 16，圆角保留但不再缩放。

### 3.3 箭头状态

根据“closed 显示向上图标，当前向下图标用反了”的明确描述，推荐将现有状态映射整体反转：

- closed：`arrow_up_black`
- open：`arrow_down_black`

点击标题行仍负责在 closed/open 之间切换。

### 3.4 safe area

统一使用运行时 `safeAreaInsets.bottom` 作为高度真值，并让约束和高度回调使用同一来源，避免同时叠加全局 safe-area 常量造成双算或设备差异。

## 4. 当前需求中的关键冲突

### 4.1 固定 160 与 Manually Add 多行展开冲突（已确认）

Manually Add 当前允许通过右侧按钮从 1 行展开到最多 3 行，父视图会随行数增加高度。固定 160 后，2～3 行设备列表无法在保持现有布局的同时完整显示。

已确认采用以下处理方式：

1. **160 作为默认提示和 selected 单行状态的固定高度；Manually Add 展开多行时允许内容卡片和父视图按现有规则增高。**
   - 保留现有功能和交互。
   - 默认与大多数 selected 状态保持统一高度。
   - 严格意义上不是所有 open 状态都固定为 160。

未采用：

1. **所有 open 状态严格固定 160，Manually Add 始终只显示一行并通过横向分页浏览。**
   - 高度契约最简单、最稳定。
   - 会移除现有 2～3 行展开能力，不符合“selected 状态保持现在布局”。

2. **所有 open 状态严格固定 160，Manually Add 多行内容改为卡片内部纵向滚动。**
   - 外部高度固定。
   - 会引入新的滚动交互，并与当前横向分页、父 table 滚动形成嵌套，不建议。

### 4.2 Space Trigger Zone 当前入口状态与复用边界

源码确认 Space Trigger Zone 当前属于“实现代码存在，但正常 UI 入口未启用”的隐藏功能：

- `SpaceMoreViewController.Options` 保留了 `.triggerZone`。
- 点击 `.triggerZone` 时也保留了创建并展示 `SpacePathTriggerZoneController` 的逻辑。
- 但 `makeOptions()` 当前只加入 BLE、Device Parameters、Energy Data，以及按条件加入 Mesh 和 Content Display，从未把 `.triggerZone` 加入实际列表。
- 因此正常用户路径无法看到或进入该功能；这不是权限过滤，而是入口选项尚未启用。

当前代码预留的产品入口路径是：

1. 进入某个 Site 下的 Space。
2. 切换至 Space 底部的 `More` 页签。
3. 在 More 功能列表点击 `Trigger zone`。
4. 先校验当前用户是否拥有 `space.groupOperates` 的 edit 权限。
5. 通过模态 Navigation Controller 展示 `SpacePathTriggerZoneController`。

第 3 步目前不可执行，因为 More 的实际选项数组未加入 `.triggerZone`。当前也不存在用于开启该入口的隐藏手势；More 页长按 BLE 只会加入 Mesh OTA 测试入口。

如果后续需要开发期进入，推荐使用独立、明确的开发功能开关决定是否把 `.triggerZone` 加入 More 列表；不要复用 Mesh OTA 长按手势。当前已确认本任务继续保持 Space Trigger Zone 隐藏，不增加任何入口。功能正式发布时，再把展示条件替换为经过确认的产品能力与权限条件。

Space Trigger Zone 已直接创建并配置 `GroupPathSequenceDeviceAddView`，并在其 Quick/Trigger/Manually 子视图中增加 Group Filter 和 compact filter 行。现阶段不推荐再建立 `Space...DeviceAddView` 子类，原因如下：

- 两个页面的共性是同一套 closed/open 外壳、三种添加模式和步骤提示布局。
- Space 差异目前属于内容配置、过滤数据和高度策略，而不是一种新的 View 类型。
- 继承会迫使父类暴露更多当前为 `private` 的布局细节，形成脆弱的父子类耦合。
- 当前隐藏功能仍在开发，提前建立子类会固化尚未稳定的差异。

推荐采用“公共组件 + 显式配置”的组合方式：

- `GroupPathSequenceDeviceAddView` 负责统一的 closed/open 状态、基础布局、箭头、safe area 和基础高度。
- Group Path Sequence 使用新的固定布局策略。
- Space Trigger Zone 暂时使用独立的内容高度策略，保留双过滤器布局。
- 后续 Space 功能稳定后，如果出现无法通过配置表达的结构性差异，再评估拆分公共基类或独立组件；当前不预设继承层级。

### 4.3 固定 160 与 Space Trigger Zone 双过滤器布局冲突

Space Trigger Zone 复用同一个组件，并在 selected 状态增加 Group Filter 行或额外提示。现有部分内容首选高度会超过 160。

由于 Space Trigger Zone 当前没有正常 UI 入口且仍在开发，推荐本需求只对 Group Path Sequence 的 Sequence/Trigger Zone 两页启用固定 160 基础高度。公共 closed/open 外壳可以同步获得本次修复，但 Space selected 内容继续使用动态高度，避免尚未完成的双过滤器布局被 160 高度挤压。

### 4.4 “移除缩放”的精确范围（已确认）

已确认按“不进行缩放”的完整解释执行：

- `GroupPathSequenceDeviceAddView` 自身的 `SCRXFrom`、`SCRYFrom` 全部移除。
- Quick Add、Trigger Add、Manually Add 三个 selected 内容容器中的 `SCRXFrom`、`SCRYFrom` 全部移除，包括约束、固定宽高、圆角、菜单参数、Collection View spacing/inset 和首选高度计算。
- selected 设备单元 `GroupPathSequenceAddDeviceCell` 中的 `SCRXFrom`、`SCRYFrom` 同步移除，避免容器已固定而内部仍缩放。
- 默认提示使用的公共 `GroupPathSequenceDeviceAddStepView` 仍需保护其他调用页面：为本组件启用固定的三列等宽配置，不把其他页面的既有默认布局顺带改成新布局。
- 本轮只把现有缩放结果改为对应固定 point，并落实已明确的新高度与间距，不提前重新设计 selected 状态；用户将在本任务完成后进行 UI 校验并提出下一步优化。

不扩大到 `TitleSelectView`、`AdaptiveTextView` 等通用组件的内部实现；只清理本组件传给它们的缩放参数。

## 5. 推荐设计方向

在关键冲突确认后，推荐采用以下结构：

1. `GroupPathSequenceDeviceAddView` 保留现有两态逻辑，但默认值改为 closed。
2. 用集中常量表达精确布局：标题 44、菜单 44、卡片顶部 8、卡片高度 160、底部 8、水平边距 16。
3. 高度回调基于状态、页面布局策略和 safe area 计算；Group Path Sequence 的 Manually Add 多行展开允许在 160 基础上增高，Space selected 内容暂时保留动态高度。
4. closed/open 切换只控制 body 显隐、箭头和高度，不重置当前添加方式、过滤器或设备选择状态。
5. 默认提示视图改用“左右 16、项间 16、三列等宽”布局。
6. 公共步骤视图通过显式配置启用等宽三列，默认配置保持现状，避免影响 Profile、说明页和重置页。
7. 公共添加视图通过显式布局策略支持 Group 与 Space 差异，不新增 Space 专用子类。

## 6. 建议验收项

### 6.1 状态与高度

- 首次进入 Sequence 页面且已有 Path：closed，整体高度等于 `44 + safe area`。
- 首次进入 Trigger Zone 页面且已有 Zone：closed，整体高度等于 `44 + safe area`。
- closed 只显示标题行和向上箭头。
- 点击标题行后进入 open，箭头切换为向下。
- open 基础高度等于 `264 + safe area`。
- 再次点击后恢复 closed。
- 无 Path/Zone 时保持当前整块隐藏行为。

### 6.2 选择行为

- 选择 Path 或 Zone 后，是否自动 open 按确认后的交互执行。
- closed/open 往返不改变当前 Quick/Trigger/Manually 选项。
- closed/open 往返不清除设备列表、过滤条件或快速添加状态。

### 6.3 默认提示

- English 和简体中文下三个提示列宽一致。
- 第二个提示的图标、文字列中心始终与卡片水平中心一致。
- 文案换行不会推动其他提示列水平漂移。
- 小屏 iPhone 与 iPad 上不发生横向截断或约束冲突。

### 6.4 selected 内容

- Quick Add 的开始、暂停、停止和过滤器布局保持可用。
- Trigger Add 的设备列表、识别、刷新和分页保持可用。
- Manually Add 的设备列表、识别、分页以及最终确认的多行策略保持可用。

### 6.5 静态与构建验证

- 增加聚焦源码契约测试，覆盖默认 closed、精确高度常量、箭头映射、目标文件不再使用相关 `SCRYFrom`、默认提示等宽布局。
- 运行 `git diff --check`。
- 直接使用 generic iPhoneOS `xcodebuild` 验证 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`，不使用 Simulator、shell 包装或日志重定向。
- 真机检查 safe area、高度动画、两种语言和设备列表交互；构建通过不能替代真机 UI 验收。

## 7. 等待确认的问题

基础高度、Manually Add 展开规则、公共 View 配置方案、Space 继续隐藏、selected 内容横纵向缩放全面清理，以及选中 Path/Zone 后自动 open 均已确认。需求澄清已完成，可以进入方案评审。
