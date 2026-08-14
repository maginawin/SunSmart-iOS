# Site 网关时区同步名称颜色设计

## 目标

在 Site 页面准确标识需要同步时区的 Gateway，仅改变两个位置的 Gateway 名称颜色：

- `GatewayListView` 中 `Overview` 右侧的 Gateway 名称。
- `SiteGatewaysMenuView` 中的 Gateway 名称。

需要同步时区的 Gateway 名称使用 `#BB4D00`，即 RGB `(187, 77, 0)`；不需要同步时区的 Gateway 完全沿用现有颜色逻辑。

## 已确认需求

### GatewayListView

- `Overview` 保持现状，不应用时区同步颜色。
- 需要同步时区的 Gateway，无论选中或未选中，名称均使用 `#BB4D00`。
- 需要同步时区的 Gateway 被选中时，继续通过原有下划线表达选中状态。
- 不需要同步时区的 Gateway 保持现状：选中名称使用 `Bar_Color`，未选中名称使用 `ImportantText_Color`。
- 连接状态点、同步云端失败图标、字体、布局、可见项计算和点击逻辑不变。

### SiteGatewaysMenuView

- 需要同步时区的 Gateway 名称使用 `#BB4D00`。
- 不需要同步时区的 Gateway 名称继续使用调用方传入的 `titleColor`。
- Add Gateway 行继续使用原有 `titleColor`。
- Gateway 在线状态图标、选中背景、字体、布局、行高、分隔线、滚动与选择回调不变。

## 范围外

- 不修改 Time Zone Sync 页的 `SyncGatewayCell`。
- 不改变 Gateway Time Set、Time Status、BLE/Mesh 扫描或连接流程。
- 不改变 Site timezone 仲裁、Review Sync banner、Gateway 云上传或重试规则。
- 不新增或修改用户可见文案和本地化资源。
- 不调整品牌资源、target 配置或依赖。

## 现有状态与问题

- `GatewayItemView.update(with:)` 当前只根据 `GatewayListItem.isSelected` 设置名称颜色，没有时区同步状态。
- `GatewayListItem` 当前包含 ID、名称、连接状态、选中状态和 GatewayModel，没有显式的 `needsTimeZoneSync`。
- `GatewayMenuData` 当前只有名称与连接状态，无法区分时区同步状态。
- `SiteViewController` 在 Header 构建、Gateway 云同步成功刷新和菜单打开时分别构造展示数据，容易在新增字段后出现入口不一致。
- `timeZoneReviewState` 只有待同步数量，没有 Gateway ID，不能用于逐 Gateway 标色。
- `SyncGatewaysContextSelectionPolicy.select` 已具备正确的逐 Gateway 选择能力，应继续作为唯一业务判定来源。

## 设计方案

### 1. 共享颜色语义

在现有 Site Gateway UI 源码中定义一个模块内共享的时区待同步名称颜色，值固定为 `#BB4D00`。`GatewayItemView` 与 `SiteGatewaysMenuView` 使用同一颜色定义，避免两个位置出现数值漂移。

不把该颜色加入全局品牌主题，也不修改 `Bar_Color`、`ImportantText_Color` 或菜单 `titleColor`，因为它只表达本次特定业务状态。

### 2. 复用逐 Gateway 待同步判定

将 `SyncGatewaysContextBuilder` 内部生成 target descriptors 的过程整理为可复用查询。输入仍为：

- 当前 Site ID 与目标 Site timezone。
- 最新服务器 Site/Gateway 快照。
- 当前 Mesh Network。
- 当前 Site 下的 GatewayModel 集合。

查询继续调用 `SyncGatewaysContextSelectionPolicy.select`，保留以下既有规则：

- 使用标准化 Gateway ID 关联服务器 Gateway 与本地 GatewayModel。
- Owner 检查全部已识别 Gateway。
- Editor 只检查绑定到 Editor Spaces 的 Gateway。
- Visitor 不产生待同步 Gateway。
- 缺失或无效的服务器 Gateway offset 视为待同步。
- GatewayModel 为 cloud dirty 时，本地 Node offset 覆盖尚未刷新的服务器 offset。
- 当前有效 offset 已等于目标 Site offset 时，不属于待同步。

Time Zone Sync 页面创建完整 Context 时继续使用该查询；Site 页面只读取查询结果中的标准化 Gateway ID 集合。不得在 View 或 Controller 中复制 offset、权限或 ID 归一化规则。

### 3. Site 页面待同步 ID 查询

`SiteViewController` 提供一个只读的待同步 Gateway ID 查询，只有以下证据同时成立时才返回结果：

- 存在最新的服务器时区快照。
- Site 本地 timezone 可解析。
- Site 本地 timezone 与服务器最终 timezone 一致。
- 当前 Site 的 Mesh Network 可加载。

任一条件不成立时返回空集合，让名称保持现状。未知状态不得被显示为确定的待同步状态。

查询在每次构造 Header items、Gateway 云同步成功后刷新 items，以及打开 `SiteGatewaysMenuView` 时重新执行，确保两个展示位置使用当前数据。

### 4. GatewayListView 展示模型与颜色优先级

`GatewayListItem` 增加 `needsTimeZoneSync`，默认值为 false。默认值确保 `Overview` 与其他既有构造入口保持原行为。

`SiteViewController` 使用一个统一 helper 构造 Gateway list items；Header 首次展示与 Gateway 云同步成功后的刷新都调用这个 helper。每个 Gateway 通过标准化 ID 是否位于待同步集合内获得展示状态。

`GatewayItemView` 的名称颜色优先级固定为：

1. `needsTimeZoneSync == true`：使用 `#BB4D00`。
2. 不需要同步且已选中：使用 `Bar_Color`。
3. 不需要同步且未选中：使用 `ImportantText_Color`。

选中下划线仍只由 `isSelected` 控制，因此待同步且选中的 Gateway 同时具备橙色名称与原选中下划线。

### 5. SiteGatewaysMenuView 展示模型与颜色

`GatewayMenuData` 增加 `needsTimeZoneSync`。`SiteViewController` 使用与横向列表相同的待同步 Gateway ID 集合构造菜单数据。

菜单 Gateway 行的颜色优先级为：

1. `needsTimeZoneSync == true`：使用 `#BB4D00`。
2. `needsTimeZoneSync == false`：使用现有 `titleColor`。

Add Gateway 行始终使用现有 `titleColor`。每次配置可复用 cell 时都显式赋值颜色，防止先前橙色 Gateway 行的颜色残留到普通 Gateway 或 Add Gateway 行。

## 数据流

1. `SiteViewController` 持有最新远端快照、Site timezone、GatewayModels 与 Mesh Network。
2. 共享 descriptors 查询复用现有 Policy，计算需要同步时区的标准化 Gateway IDs。
3. `SiteViewController` 将 `needsTimeZoneSync` 写入 `GatewayListItem` 或 `GatewayMenuData`。
4. `GatewayItemView` 与 `SiteGatewaysMenuView` 只消费展示字段并选择名称颜色。
5. Gateway 时区同步成功后，现有流程更新 Node offset 与 cloud dirty 状态；下一次 items 刷新或菜单打开重新计算，名称恢复现有正常颜色。

## 异常与边界处理

- 无远端快照、Site timezone 无效或 Mesh Network 无法加载：不标橙，保持现状。
- 服务器 Gateway 缺少 offset：若 ID 可识别且在权限范围内，则标橙。
- 服务器 Gateway ID 缺失或无法标准化：无法可靠对应某个本地名称，不标橙。
- 本地缺少 GatewayModel 或 Node：横向列表和菜单中不存在可关联对象时不新增虚构条目；既有 Review Sync 计数与页面处理不在本需求中调整。
- Gateway 已完成设备同步但云上传尚未完成：沿用 local dirty override，以本地已确认 offset 判断，避免短暂恢复橙色。
- Gateway 连接状态变化：只更新现有状态图标，不影响时区同步颜色判定。

## 预计影响文件

- `SunSmart/Main/Site/Model/SyncGatewaysContext.swift`
  - 提供可复用的 target descriptors 查询，并让完整 Context 继续使用该查询。
- `SunSmart/Main/Site/View/GatewayListView.swift`
  - 扩展 `GatewayListItem`，应用确认后的名称颜色优先级，并承载共享业务颜色定义。
- `SunSmart/Main/Site/View/SiteGatewaysMenuView.swift`
  - 扩展 `GatewayMenuData`，只调整 Gateway 名称颜色并处理 cell reuse。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 统一构造 Gateway items/menu data，向两个 View 传入同一待同步状态。
- `Tests/Site/SyncGatewaysContextTests.swift`
  - 验证共享 descriptors/IDs 查询仍遵守现有业务规则。
- `Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift`
  - 验证颜色优先级、Overview、Add Gateway、复用恢复与构造入口一致性。
- `scripts/check_site_sync_gateways.sh`
  - 将新增聚焦契约纳入现有检查入口。

不预计修改本地化、资源、project target membership 或依赖。

## 测试设计

### 纯策略与数据查询

- Owner：只返回 offset 不匹配、缺失或无效的已识别 Gateway IDs。
- Editor：只返回绑定到 Editor Spaces 且需要同步的 Gateway IDs。
- Visitor：返回空集合。
- ID 大小写、空白与重复数据：标准化并去重。
- local dirty 且 Node offset 已匹配：排除，即使服务器 offset 仍旧。
- local dirty 且 Node offset 不匹配：保留。
- Site 与服务器最终 timezone 不一致或证据不完整：Site 页面查询返回空集合。

### GatewayListView

- 待同步、未选中：`#BB4D00`。
- 待同步、已选中：`#BB4D00`，下划线仍显示。
- 不需要同步、未选中：`ImportantText_Color`。
- 不需要同步、已选中：`Bar_Color`。
- Overview：继续按原选中/未选中逻辑显示。
- 状态点、失败图标、字体和布局相关代码路径保持不变。

### SiteGatewaysMenuView

- 待同步 Gateway：`#BB4D00`。
- 不需要同步 Gateway：现有 `titleColor`。
- Add Gateway：现有 `titleColor`。
- 复用橙色 cell 展示普通 Gateway 或 Add Gateway 时，颜色正确恢复。
- 在线、离线、重置和未激活图标映射保持不变。

### 构建与静态验证

- 运行 Site timezone、Sync Gateways 与新增名称颜色聚焦测试。
- 运行现有 `scripts/check_site_sync_gateways.sh`。
- 运行 `git diff --check`。
- 使用 generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO`，验证 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 不使用 Simulator 作为构建验证。

## 验收边界

自动化测试与 generic iPhoneOS 构建只能验证策略、状态传递、颜色分支和 target 编译，不能替代以下真机验收：

- Site 页面同时存在待同步与不需要同步 Gateway。
- 待同步 Gateway 在选中和未选中之间切换。
- 超过四个 Gateway 时，横向列表切换可见项。
- 菜单中混合展示待同步与普通 Gateway。
- Gateway 同步成功后，横向名称与菜单名称均恢复原有正常颜色。
- 真实服务器快照、权限范围、BLE/Mesh 与 cloud dirty 生命周期符合预期。
