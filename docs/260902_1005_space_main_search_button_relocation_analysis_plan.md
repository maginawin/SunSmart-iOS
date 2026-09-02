# Space Main Search by Name 按钮迁移分析与开发计划

## 1. 结论

本需求可以在不改变设备名称过滤规则、过滤会话生命周期、Search 输入与 Reset 行为的前提下完成。核心改动是把 `SpaceFunctionFooterView` 中“设备数量展示”和“Search by Name 入口”拆成两个独立控件，并由 Main 四个分类配置不同的按钮顺序。

建议保持以下现有业务语义：

- 左下角继续展示原始设备数量与 Space 容量，但恢复为不可点击的纯展示状态，图片始终使用 `space_device_count`。
- Main 四分类继续共享当前 `DevicesViewController` 持有的同一个名称过滤会话；切换分类时保留关键词与选中状态，退出当前 Space 页面实例后释放。
- 非空关键词时，新按钮使用 `device_filter_selected`；无关键词时使用 `device_filter`。
- 过滤只改变列表可见数据，不改变容量统计、Lights 全量控制、同步、修复和原始业务数据。
- `space_sort` 在 Main 四分类初始化时被隐藏，但共享 Footer 在退出编辑态时会把它重新显示，这是现有显隐不一致；本次只按指定控件建立相对位置，不主动改变其既有显示条件。

## 2. 当前实现

### 2.1 入口与状态

- `DevicesViewController` 持有一份 `DeviceNameFilterSession`，并注入 Lights、Switches、Sensors、Others 四个子控制器。
- 四个子控制器分别持有自己的 `SpaceFunctionFooterView`，但观察同一份过滤会话。
- 当前 `SpaceFunctionFooterView.countBtn` 同时负责：
  - 展示设备数量；
  - 点击后打开 Search by Name / Reset 菜单；
  - 过滤生效时把图片从 `space_device_count` 替换成 `space_device_count_selected`。
- 四个分类的 delegate 都把菜单锚点传成 `countBtn`，所以菜单目前显示在左下角数量控件上方。

### 2.2 参考实现

`GroupMembersViewController` 与 `GroupDevicesFunctionView` 已提供可复用的交互基准：

- 独立纯图片按钮；
- 正常图片 `device_filter`；
- 选中图片 `device_filter_selected`；
- 按钮尺寸 30×30；
- accessibility label 复用 `device_filter_search_by_name`；
- 点击后以按钮自身作为 `DeviceNameFilterMenuView` 的锚点；
- Reset 后恢复未选中图片。

### 2.3 Footer 当前普通状态顺序

Space Footer 当前右侧按从右到左的约束关系为：`space_add`、`share_delete`、`space_sort`、`sync_failed`。按钮之间使用现有 Space Footer 的水平间距。

编辑状态下 Footer 改为 Cancel / Delete，并隐藏数量、Add、Edit、Sort、Sync 等普通状态控件。新 Search by Name 按钮也应遵守这一状态切换。

## 3. 目标布局

### 3.1 Lights

普通状态下，右侧按钮关系调整为：

`space_add` ← `share_delete` ← `space_sort` ← `device_filter` ← `sync_failed`

其中：

- `device_filter` 位于 `space_sort` 左侧并垂直居中；
- `sync_failed` 需要显示时位于 `device_filter` 左侧并垂直居中；
- `sync_failed` 的显示条件、可用权限与点击同步逻辑保持不变；
- 本次不主动改变 `space_sort` 的既有显示条件；无论它处于显示还是隐藏状态，Filter 与 Sync 的相对约束均保持正确。

### 3.2 Switches、Sensors、Others

普通状态下，新按钮位于 `share_delete` 左侧并垂直居中：

`space_add` ← `share_delete` ← `device_filter`

这些分类现有的 Sort、Sync 显示与业务行为不变。

### 3.3 左下角数量展示

- 保留现有数量文字，例如“25/100”；
- 图片固定为 `space_device_count`；
- 不再响应点击；
- accessibility 语义恢复为静态展示，不再使用 Search by Name 的按钮语义；
- 过滤生效时数量和图片均不变化。

### 3.4 菜单位置

- 四个分类都改为以新的 `deviceFilterBtn` 作为菜单锚点。
- `DeviceNameFilterMenuView` 已根据锚点坐标优先向上展示；新按钮位于底部 Footer，因此菜单会出现在新按钮上方。
- 菜单内容仍只有 Search by Name、分隔线、Reset。
- 点击菜单中的 Search by Name 后，现有顶部搜索输入视图、初始关键词、键盘 Search 提交和 Cancel 行为保持不变。

## 4. 开发方案

### 4.1 调整共享 Footer

修改 `SunSmart/Main/Space/View/SpaceFunctionFooterView.swift`：

- 新增独立的 `deviceFilterBtn`，直接复用 `device_filter` 和 `device_filter_selected`。
- 将现有过滤激活状态从修改 `countBtn` 图片改为设置 `deviceFilterBtn.isSelected`。
- 取消 `countBtn` 的点击 target 与 Search accessibility label，使其始终为不可交互的数量展示。
- 为 Main 分类增加明确的过滤按钮布局配置，区分 Lights 的“位于 Sort 左侧”与其他分类的“位于 Edit 左侧”；默认不启用，保护其他 Footer 使用方。
- Lights 布局把 `syncBtn` 改为约束在 `deviceFilterBtn` 左侧；其他页面沿用既有布局。
- 编辑状态隐藏过滤按钮；退出编辑时只在已启用的 Main 分类恢复显示。
- 新按钮视觉尺寸保持 30×30；水平间距优先沿用 Space Footer 现有按钮间距，避免改变整条底栏的既有节奏。

不建议把 Footer 拆成多个新 View，也不建议复制 Group Footer；两者会扩大共享 UI 改动并增加状态同步成本。

### 4.2 配置四个 Main 分类

修改以下控制器：

- `DeviceLightsViewController`：启用 Lights 布局模式；菜单锚点改为新按钮。
- `DeviceSwitchesViewController`：启用 Edit 左侧布局模式；菜单锚点改为新按钮。
- `DeviceSensorsViewController`：启用 Edit 左侧布局模式；菜单锚点改为新按钮。
- `DeviceOthersViewController`：启用 Edit 左侧布局模式；菜单锚点改为新按钮。

四个控制器现有的过滤观察、可见数据派生、空结果状态、编辑规则与列表刷新逻辑不改。

### 4.3 保持菜单与过滤逻辑不变

以下文件原则上无需修改：

- `DeviceNameFilterSession.swift`
- `DeviceNameFilterMenuView.swift`
- `DeviceNameFilterSearchView.swift`
- `DevicesViewController.swift`

只有在布局验证发现菜单边缘保护无法满足新锚点时，才对菜单定位做最小修正；当前坐标算法已经支持底部按钮向上展开，预计无需改动。

### 4.4 资源与多 target

- `device_filter`、`device_filter_selected` 已存在于共享 `SunSmart/Assets.xcassets`，SVG 画布为 30×30并保留矢量表示，无需新增或替换资源。
- 共享 Assets 已进入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 target 的 Resources Build Phase。
- 本次不新增用户可见文案，不需要修改英文或简体中文本地化。
- 不涉及 NordicSigMeshSDK、依赖、target 配置或协议逻辑。

## 5. 测试与验收计划

### 5.1 自动化与源码契约

- 增加聚焦的 Footer 契约，验证：
  - 数量控件不再作为过滤入口；
  - 新按钮使用指定的 normal / selected 图片与 30×30 尺寸；
  - Lights 的 Sort、Filter、Sync 约束顺序；
  - Switches、Sensors、Others 的 Edit、Filter 约束顺序；
  - 四个分类打开菜单时传入新按钮；
  - 编辑态隐藏、退出编辑态恢复规则；
  - Group、Scene、Timed、Gateway、EFC 等非 Main 使用方默认不出现新按钮。
- 回归现有 `DeviceNameFilterSessionTests`、菜单/搜索契约与 `DeviceNameFilterExpansionContractTests`。
- 执行 `git diff --check`。

### 5.2 构建验证

按工程规则直接使用 `xcodebuild`，分别对以下共享 scheme 做 generic iPhoneOS、关闭签名的 Debug 构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart
- Lumineux

### 5.3 实际布局与交互验收

UI 改动不能只以编译和静态契约作为完成标准，需要在实际 iPhone 与 iPad 布局中检查：

- Lights 无同步失败与有同步失败两种状态的按钮顺序、间距、垂直对齐和点击区域；
- Switches、Sensors、Others 中 Filter 位于 `share_delete` 左侧；
- `space_sort` 隐藏状态下不存在意外重叠或异常空白；
- 新菜单稳定出现在对应 Filter 按钮上方，左右边缘不越过安全区；
- 空关键词、非空关键词、Reset 后按钮图片正确切换；
- 四分类切换时关键词与 selected 状态保持一致；
- 进入编辑态时 Filter 隐藏，退出编辑后恢复；
- 左下角数量展示不可点击且过滤时不换图；
- Search 提交、Cancel、Reset、无匹配空态以及隐藏项目的业务状态均保持原行为。

若当前环境无法连接真机，则自动化和五 target 构建结果只能作为阶段性证据，真机 iPhone/iPad 布局与交互验收仍需保持为未完成项。

## 6. 本次确认点

建议按以下口径实施：

1. “左下角恢复成纯图片”解释为恢复成纯展示控件：仍保留数量文字，固定使用 `space_device_count`，不可点击。
2. 新 Search by Name 按钮视觉尺寸采用 Group Members 同款 30×30，按钮间距沿用 Space Footer 当前间距。
3. 四分类继续共享同一过滤条件，Search 与 Reset 的业务行为不变。
4. 不在本需求中修正 `space_sort`“初始化隐藏、退出编辑后可能显示”的现有不一致，只建立 Filter 与 Sort 的相对约束。
5. 不改变 Main 之外任何 `SpaceFunctionFooterView` 使用方。

确认以上口径后再进入代码实施。
