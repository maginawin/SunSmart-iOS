# Space Main 设备名称过滤设计

## 1. 背景与目标

在 `Site → Space → Main` 页面中，将四个设备分类页左下角的设备数量图片改为可点击的过滤入口。用户可以按名称过滤 Lights、Switches、Sensors、Others 中展示的设备，并在当前 Space 页面实例存续期间共享同一个过滤条件。

本功能仅改变设备卡片的可见范围，不改变原始设备数据、容量统计、Lights 全量控制、修复、同步或其他页面的数据源。

## 2. 设计依据

- 过滤菜单 Figma：<https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=381-258&t=TJ1DGtzjzPl1j2Ou-11>
- 空搜索输入 Figma：<https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=381-462&t=TJ1DGtzjzPl1j2Ou-11>
- 已有条件搜索输入 Figma：<https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=381-991&t=TJ1DGtzjzPl1j2Ou-11>

当前代码结构的关键事实：

- `SpaceViewController` 的 Main 子页面为 `DevicesViewController`。
- `DevicesViewController` 再创建 Lights、Switches、Sensors、Others 四个分类控制器。
- 四个分类分别持有自己的 `SpaceFunctionFooterView`，没有现成的跨分类过滤状态。
- `SpaceFunctionFooterView.countBtn` 当前不可交互。
- Lights 当前使用同一设备数组承担展示、`ALL`、编辑、修复和状态计算，实施时必须拆分完整集合与可见集合，避免过滤改变业务语义。
- `space_device_count_selected` 的 1x、2x、3x 图片已存在于当前 worktree，属于实施前已有资源，不重新生成或覆盖。

## 3. 功能范围

### 3.1 包含范围

- `Site → Space → Main → Lights`
- `Site → Space → Main → Switches`
- `Site → Space → Main → Sensors`
- `Site → Space → Main → Others`
- 按名称搜索
- Reset
- 英文与简体中文本地化
- iPhone 与 iPad 布局适配

### 3.2 明确不包含

- Search by Address
- Search by MAC
- Group、Scene、Timed、More 一级页面中的过滤
- 从 Group、Scene、Timed、More 进入的任何设备列表过滤
- 从 Main 四分类进入的设备详情或其他深层页面过滤
- 过滤条件持久化到 `SpaceData`、数据库、UserDefaults 或云端
- 扩展 Sensors 当前尚未实现的真实设备列表业务

## 4. 状态架构

采用“当前 Main 页面实例共享过滤会话”的方案。

- `DevicesViewController` 创建并持有一个名称过滤会话。
- Lights、Switches、Sensors、Others 创建时接收同一个会话。
- 会话保存已提交且已 Trim 的关键词，并派生过滤是否启用。
- 搜索提交或 Reset 后，会话通知四个分类刷新可见集合与左下角按钮图片。
- 各分类保存或读取完整业务集合，并单独派生可见集合；UICollectionView 的 data source、索引访问、长按和编辑选择只能使用可见集合。
- 数量、Lights `ALL` 控制、修复、同步和状态计算继续使用完整集合。
- 过滤规则保持为无 UIKit、无 Nordic SDK 依赖的纯逻辑单元，以便使用独立 Swift 测试验证。

### 4.1 生命周期

- 首次进入 Space Main 时，关键词为空，默认不过滤。
- 在 Lights、Switches、Sensors、Others 之间切换时，共享同一个关键词。
- Push 或 Present 到更深页面后返回时，`DevicesViewController` 及会话仍存在，因此保留过滤条件。
- Pop 当前 Space 返回 Site 后，会话随页面实例释放；再次进入 Space 时创建空会话并恢复默认。
- 不通过全局通知或单例保存过滤会话，避免多个 Space 页面或其他设备列表互相影响。

## 5. 左下角按钮与菜单

### 5.1 按钮状态

- 无有效关键词：使用 `space_device_count`。
- 有非空关键词：使用 `space_device_count_selected`。
- 标题始终显示原始数量/容量，不显示过滤结果数量。
- 只在 Main 四分类中启用点击；`SpaceFunctionFooterView` 的其他使用方保持当前不可点击行为。
- 编辑状态下沿用现有 Footer 显隐规则，过滤条件本身不被清空。

### 5.2 菜单

- 点击左下角按钮后，在按钮上方、屏幕左下角展示菜单。
- 借鉴当前右上角 `MenuPopView` 的视觉资产、定位、遮罩关闭和动画方式。
- 根据 Figma 调整设备过滤菜单的宽度、圆角、阴影、行高和内容间距。
- 菜单仅展示：
  1. `Search by Name`
  2. 分隔线
  3. `Reset`
- 不显示 Address 和 MAC。
- 点击菜单外空白区域只关闭菜单，不改变已提交的过滤条件。
- 设备过滤菜单的定制不得改变现有右上角菜单或其他 `MenuPopView` 调用方的表现。

## 6. 搜索输入交互

- 点击 `Search by Name` 后关闭菜单，展示 Figma 对应的遮罩与顶部悬浮搜索框。
- 搜索框自动聚焦并弹出键盘。
- Return Key 显示为 `Search`。
- 输入框使用系统默认 clear button。
- 已存在过滤条件时，输入框回填已 Trim 的关键词。
- 输入过程只修改本次草稿，不实时更新设备列表。
- 点击键盘 `Search` 时：
  - 去掉输入内容首尾空格；
  - 保留关键词中间的原始空格；
  - 非空时提交为共享关键词；
  - 空字符串或全空格等同 Reset；
  - 提交后关闭搜索框与键盘，并刷新四个分类。
- 点击 `Cancel` 或搜索遮罩空白区域时：
  - 关闭搜索框与键盘；
  - 丢弃本次草稿；
  - 保留进入搜索框前的已提交条件。
- 点击菜单中的 `Reset` 时立即清空共享关键词、关闭菜单，并刷新四分类与按钮图片。

## 7. 名称匹配规则

### 7.1 通用规则

- 关键词已执行首尾 Trim。
- 使用忽略大小写的子串匹配。
- 不合并、不删除关键词中间的空格。
- 不匹配 Address、MAC 或其他隐藏字段。

### 7.2 Lights

- 设备名称包含关键词时展示。
- 当 `space.displayDeviceNamePrefix` 开启时，设备名称或所属组名称任一包含关键词即展示。
- 当 `space.displayDeviceNamePrefix` 关闭时，只匹配设备名称，不匹配组名称。
- `ALL` 作为显示名称为 `ALL` 的伪条目参与相同的忽略大小写子串匹配；不匹配时隐藏。
- `ALL` 在过滤结果中可见并被点击时，仍控制完整 Lights 集合，而不是可见结果。
- 编辑态 Select All 仅选择过滤后可见的真实设备，不选择隐藏设备，也不包含 `ALL`。

### 7.3 Switches

- 按 `DeviceSwitchData.name` 匹配。
- 编辑、长按、删除和详情跳转的索引必须映射到过滤后的可见 Switch 数据，不能继续使用完整数组下标。

### 7.4 Sensors

- 设计接口按 Sensor 的实际展示名称匹配。
- 当前 `DeviceSensorsViewController` 尚无真实 Sensor 列表 data source，本期不新增 Sensor 业务。
- Sensors 仍接入共享过滤状态、按钮图片和空状态，以保证跨分类状态一致。

### 7.5 Others

- Dongle 按 `DeviceDongleData.name` 匹配。
- Emergency Fire Controller 按 `DeviceEmerFireData.name` 匹配。
- 编辑、长按、删除、监控和详情跳转均使用过滤后的可见 Item 映射。

## 8. 刷新、排序与业务隔离

- 设备添加、删除、改名、通知刷新或重新进入分类时，在最新完整集合上重新应用当前关键词。
- 分类切换不清空关键词。
- Lights 原有排序完成后，再由排序后的完整集合派生可见集合；过滤本身不改变顺序。
- Footer 原始数量保持现状：
  - 不因过滤结果数量变化；
  - 不因无匹配结果归零。
- Lights `ALL`、修复提示、同步状态、在线状态读取等继续基于完整集合。
- 编辑态只能选择和操作当前可见结果；Select All 只覆盖当前可见真实设备。
- Group、Scene、Timed、More 及其深层设备列表始终展示完整数据。
- Main 四分类进入的设备详情和其他深层列表始终展示完整数据。

## 9. 空状态

- 未启用过滤且分类无设备时，继续使用当前分类已有空状态，例如 `no_devices`、`no_switches`、`no_sensors`、`no_others`。
- 启用过滤且没有可见结果时，统一展示过滤空状态：
  - English：`No matching devices`
  - 简体中文：`没有匹配的设备`
- 过滤空状态下保留原始数量与 selected 图片，用户可通过左下角菜单执行 Reset。

## 10. 本地化与资源影响

- 新增或复用以下用户可见文案的本地化 Key：
  - `Search by Name`
  - `Reset`
  - `No matching devices`
- English 与 `zh-Hans` 同步更新，禁止硬编码用户可见文案。
- 使用共享 `SunSmart/Assets.xcassets` 中的 selected 图片。
- 共享源码、本地化和资源被 SunSmart、Archipelago、SLG Sync Plus、SylSmart 使用，实施时必须同步检查四个 target。

## 11. 异常与边界处理

- 无匹配结果不是错误，不弹出 HUD 或 Alert。
- Cancel、点击空白区域和系统 clear button 均不得意外提交草稿。
- 关键词变化、设备刷新和页面切换均在主线程更新 UIKit。
- 会话通知使用可释放的弱引用或明确取消机制，不能持有分类控制器造成泄漏。
- 可见集合变化后，清理已不再可见的编辑选择，保证 Select All、删除按钮状态与当前结果一致。
- 菜单与搜索遮罩关闭时恢复键盘和交互状态，避免残留窗口级遮罩阻止其他页面点击。

## 12. 验证方案

### 12.1 纯逻辑聚焦测试

沿用项目现有的独立 Swift 测试方式，覆盖：

- 首尾 Trim。
- 空字符串和全空格等同未过滤。
- 忽略大小写子串匹配。
- 中间空格保持原样。
- Lights 设备名称匹配。
- `displayDeviceNamePrefix` 开关下的组名称匹配差异。
- `ALL` 名称匹配。
- Reset 清空状态。
- Cancel 草稿不提交。
- 完整集合与可见集合隔离。
- 编辑 Select All 只返回可见真实设备。

### 12.2 手工交互矩阵

- 默认图片、selected 图片、原始数量保持。
- 菜单定位、宽度、分隔线、外部点击关闭。
- 空搜索、已有条件回填、系统 clear button、Cancel、遮罩点击、键盘 Search。
- 四分类共享关键词、切换分类、跨分类 Reset。
- 进入深层页面返回后保留；返回 Site 再进入后清空。
- Group、Scene、Timed、More 及其深层设备列表不受影响。
- Lights 组名前缀开关、`ALL` 过滤与完整集合控制。
- 编辑态 Select All、删除、长按和详情索引正确。
- 过滤期间设备新增、删除、改名和通知刷新。
- 未过滤空状态与过滤零结果空状态。
- English、简体中文、iPhone、iPad。

### 12.3 静态与构建验证

- 运行名称过滤聚焦测试。
- 运行 `git diff --check`。
- 使用 generic iPhoneOS、关闭代码签名，直接执行 `xcodebuild` 验证以下 scheme：
  - SunSmart
  - Archipelago
  - SLG Sync Plus
  - SylSmart
- 不使用 Simulator 作为构建验证。
- 构建通过只证明代码、资源和 target 集成正确；菜单、键盘、页面生命周期和真实设备控制范围仍需真机或可交互环境验收。

## 13. 验收标准

1. 初次进入 Space Main 时不过滤，四分类左下角使用默认图片。
2. 任一分类提交非空关键词后，四分类共享该关键词并使用 selected 图片。
3. 名称匹配为首尾 Trim、忽略大小写的子串匹配。
4. Lights 在开启组名前缀时支持按组名展示对应设备，关闭时不匹配组名。
5. `ALL` 参与显示过滤，但其控制范围始终为完整 Lights 集合。
6. Footer 数量、修复和同步逻辑不受过滤影响。
7. 编辑 Select All 只选择过滤后的可见真实设备。
8. Cancel 或点击空白区域不更新已提交条件。
9. 空搜索提交和 Reset 均恢复不过滤。
10. 过滤零结果时显示专用英中空状态。
11. 深层页面返回后保留条件；返回 Site 再进入 Space 后清空。
12. Group、Scene、Timed、More 及所有非 Main 设备列表始终展示完整数据。
13. 四个品牌 target 均能完成 generic iPhoneOS 编译验证。
