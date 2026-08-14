# Site 网关名称时区同步颜色需求分析与方案

## 结论

经需求更正，第一处目标不是 Time Zone Sync 页面，而是 Site 页面 `GatewayListView` 中 `Overview` 右侧的 Gateway 名称；第二处仍是 `SiteGatewaysMenuView` 中的 Gateway 名称。

需求范围已经完整。当“需要同步时区”的 Gateway 同时处于选中状态时，名称仍使用 `#BB4D00`，原有选中下划线、状态点和交互保持现状。

本文按以下已确认口径规划：

- `#BB4D00` 等价于 RGB `(187, 77, 0)`。
- 需要同步时区的 Gateway，无论是否选中，名称均使用 `#BB4D00`。
- 不需要同步时区的 Gateway 保持现有逻辑：选中时名称使用 `Bar_Color`，未选中时使用 `ImportantText_Color`。
- `Overview` 保持现状，不应用时区同步颜色。
- `SiteGatewaysMenuView` 中需要同步时区的 Gateway 名称使用 `#BB4D00`；其他 Gateway 和 Add Gateway 行保持现有 `titleColor`。
- 两个控件除 Gateway 名称颜色外，其他 UI 与交互全部保持现状。

## 当前源码事实

### Site 页面 Overview 右侧 Gateway 名称

- 横向列表由 `GatewayListView` 展示，单项控件是 `GatewayItemView`，名称控件是 `titleLabel`。
- `GatewayListItem` 当前包含 ID、名称、连接状态、选中状态和 `GatewayModel`，没有“需要同步时区”字段。
- `GatewayItemView.update(with:)` 当前只按选中状态设置名称颜色：选中使用 `Bar_Color`，未选中使用 `ImportantText_Color`。
- `Overview` 也是 `GatewayListItem`，但没有 Gateway 状态和 `GatewayModel`，需要继续作为普通导航项处理。
- Gateway items 至少在 `SiteViewController` 的 Header 构建和 Gateway 云同步成功刷新两个位置生成；新增展示状态时必须统一收口，避免两个入口颜色不一致。

### SiteGatewaysMenuView

- `GatewayMenuData` 当前只有 `name` 与连接 `status`，没有时区同步状态。
- 菜单对所有 Gateway 名称和 Add Gateway 行统一使用外部传入的 `titleColor`，默认是白色。
- 菜单的连接状态只用于 Gateway 图标，不能代表是否需要同步时区。
- 菜单使用可复用的 `CustomTableViewCell`；必须在每次配置时显式恢复普通名称及 Add Gateway 行的颜色，避免橙色残留。

### 已有逐 Gateway 同步判定

- `SyncGatewaysContextSelectionPolicy.select` 已根据最终 Site UTC offset、服务器 Gateway offset、本地 dirty override、权限范围和标准化 Gateway ID 选出需要同步时区的 Gateway。
- Owner 检查全部已识别 Gateway；Editor 只检查绑定到 Editor Spaces 的 Gateway；Visitor 不产生同步目标。
- 服务器缺少或无法解析某个已识别 Gateway 的 `timezoneOffset` 时，该 Gateway 会被视为需要同步。
- `timeZoneReviewState` 只有待同步数量，没有具体 Gateway ID，不能直接用于两个名称控件。

## 需求完整性检查

| 项目 | 状态 | 分析 |
| --- | --- | --- |
| 目标颜色 | 已明确 | 按 `#BB4D00` 处理。 |
| Site 横向列表目标 | 已明确 | `GatewayListView` 中 `Overview` 右侧的 Gateway 名称。 |
| Site 菜单目标 | 已明确 | `SiteGatewaysMenuView` 中的 Gateway 名称。 |
| Overview | 已明确建议 | 保持现状，不参与同步颜色。 |
| 不需要同步的 Gateway | 已明确 | 保留原有选中与未选中颜色逻辑。 |
| 需要同步且被选中 | 已确认 | 橙色优先；选中下划线继续展示。 |
| 菜单其他控件 | 已明确 | 图标、背景、字体、布局、分隔线、Add Gateway 和交互保持现状。 |
| 证据不足或无法关联 ID | 已明确建议 | 保持现状，避免把未知状态显示成确定的待同步。 |
| 权限范围 | 可复用现状 | Owner 全部、Editor 绑定范围、Visitor 不标记。 |
| 国际化 | 无新增工作 | 不新增用户可见文案。 |
| 多 target | 需要验证 | 相关文件属于共享业务，需要验证四个 App target。 |

## 方案对比

### 方案 A：共享待同步 Gateway ID，向两个 View Model 传入显式状态（推荐）

- 复用现有同步选择策略生成待同步 Gateway ID 集合。
- `GatewayListItem` 与 `GatewayMenuData` 分别增加明确的 `needsTimeZoneSync` 展示字段。
- `GatewayItemView` 和 `SiteGatewaysMenuView` 只根据该字段决定名称颜色，不读取服务器、Node 或权限数据。

优点：两个位置使用同一业务真值；权限、ID 标准化、缺失 offset 和 dirty override 不会漂移；View 仍然只负责展示。

代价：需要更新两个展示数据结构和所有 `GatewayListItem` 构造入口，并补充聚焦测试。

### 方案 B：两个 UI 各自计算是否需要同步

- `GatewayItemView` 或 `SiteGatewaysMenuView` 自行读取 `GatewayModel`、Node 或连接状态推断。

缺点：View 无法获得完整远端快照和权限范围；连接状态也不等于时区同步状态，会产生误报，不采用。

### 方案 C：依据 Review Sync banner 是否显示统一标橙

- banner 只有待同步数量，不包含 Gateway ID。

多个 Gateway 时无法区分具体对象，不满足逐名称标色要求，不采用。

## 推荐开发方案

### 1. 收口逐 Gateway 判定

- 保留 `SyncGatewaysContextSelectionPolicy` 作为核心纯策略。
- 将 Context Builder 中“从远端快照、本地 Gateway/Node 和最终 Site 时区得到 target descriptors”的部分提取为可复用查询。
- Time Zone Sync 页面 Context 与 Site 页面名称颜色都复用该查询，最终以标准化 Gateway ID 集合作为 UI 输入。
- 仅在最新远端快照、有效 Site 时区、Site 与远端最终时区、Mesh Network 等证据完整时计算；证据不足时返回空集合并保持原颜色。
- 继续使用现有 local dirty override，避免 Gateway 已完成设备同步但服务器快照尚未刷新时重新被标为待同步。

### 2. 扩展 GatewayListView 展示数据

- `GatewayListItem` 增加 `needsTimeZoneSync`，默认值为 false，以保持 Overview 和其他既有调用兼容。
- 在 `SiteViewController` 统一生成 Gateway list items，避免 Header 构建和云同步回调分别复制映射逻辑。
- Gateway ID 位于待同步集合时置为 true；Overview 始终为 false。
- `GatewayItemView.update(with:)` 的颜色优先级建议为：需要同步时使用 `#BB4D00`；否则按原有选中状态使用 `Bar_Color` 或 `ImportantText_Color`。
- 选中下划线、连接状态点、云同步失败图标、字体、布局、可见项计算和点击逻辑全部保持现状。

### 3. 扩展 SiteGatewaysMenuView 展示数据

- `GatewayMenuData` 增加 `needsTimeZoneSync`。
- `SiteViewController` 使用与横向列表完全相同的待同步 ID 集合生成菜单数据。
- 需要同步的 Gateway 名称使用 `#BB4D00`；其他 Gateway 与 Add Gateway 行继续使用现有 `titleColor`。
- 选中背景、Gateway 在线状态图标、字体、布局、行高、分隔线、滚动与选择回调保持现状。
- 每次配置 cell 时显式设置对应颜色，覆盖复用前状态。

### 4. 刷新与一致性

- Header 首次构建、`setupData()` 后重载、Gateway 云同步成功后的 items 刷新，都调用同一 items 构建方法。
- Site 菜单每次打开时使用当前同一份待同步 ID 查询结果。
- Gateway 完成设备时区同步并持久化本地 dirty override 后，下一次 Site UI 刷新或打开菜单时恢复正常颜色；服务器刷新完成后继续保持一致。
- 本需求不改变 Gateway Time Set、BLE/Mesh、云上传或 Review Sync 流程。

## 测试与验证计划

### 聚焦测试

- 扩展 `SyncGatewaysContextTests`：验证 Owner、Editor、Visitor、ID 标准化、缺失 offset、dirty override 和已同步排除后得到正确 Gateway IDs。
- 为 `GatewayListItem` / `GatewayItemView` 增加契约：待同步颜色覆盖选中与未选中；普通 Gateway 保持原选中/未选中颜色；Overview 保持原色。
- 为 `SiteGatewaysMenuView` 增加契约：待同步 Gateway 使用 `#BB4D00`，普通 Gateway 与 Add Gateway 使用现有 `titleColor`。
- 覆盖 cell 与 item 复用，确保待同步状态切换为普通状态时颜色能够恢复。
- 覆盖 `SiteViewController` 的两个 Gateway items 构造入口，确保使用同一 helper 和同一待同步 ID 集合。

### 静态与构建验证

- 运行 Site timezone、Sync Gateways、GatewayListView 相关聚焦测试及现有检查脚本。
- 运行 `git diff --check`。
- 使用 generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO`，依次验证 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 不使用 Simulator 作为构建验证。

### 真机验收边界

- 自动化和 generic build 不能代替真实服务器快照、BLE/Mesh 与视觉验收。
- 真机应至少验证：Overview 与普通 Gateway、选中/未选中的待同步 Gateway、待同步与已同步 Gateway 混合、超过四个 Gateway 时横向可见项切换、菜单列表和同步完成后的颜色恢复。

## 确认结果

需要同步时区的 Gateway 被选中时，名称仍以 `#BB4D00` 为最高优先级，选中状态只继续通过原有下划线表达；不需要同步的 Gateway 继续使用现有 `Bar_Color` / `ImportantText_Color` 逻辑。
