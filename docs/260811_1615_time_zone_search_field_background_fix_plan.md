# Time Zone 搜索框背景偏灰根因与修复计划

## 1. 结论

`searchField.backgroundColor = .white` 本身已经生效，但当前控件是 `UISearchTextField`。该类初始化后使用系统 `roundedRect` 外观；系统圆角外观会在控件自身的 `backgroundColor` 之上绘制搜索框填充，所以最终屏幕上看到的是系统灰色，而不是底层设置的纯白色。

这不是 `Background_Color`、父视图透明度、禁用状态或项目全局 `UIAppearance` 导致的问题。

## 2. 当前源码证据

- `SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift`
  - 搜索控件声明为 `UISearchTextField()`。
  - `setupSearchField()` 设置了 `.white`、10pt 圆角和 0.5pt 边框。
  - 没有关闭控件默认的 `borderStyle`。
- `SunSmart/Common/Macro/MacroDefinition.swift`
  - 页面背景 `Background_Color` 是 RGB(248, 250, 252)，与搜索框目标白色不同。
- 工程搜索结果
  - 没有发现针对 `UISearchTextField` 或 `UITextField` 的全局 `UIAppearance` 覆盖。
  - 没有发现该页面或其导航栈对搜索框设置 alpha、disabled 状态或灰色遮罩。
- UIKit 头文件与 Apple 文档
  - `UITextField.borderStyle` 控制文本框标准外观。
  - `roundedRect` 是系统绘制的圆角文本框样式。
  - Apple 文档同时说明，`roundedRect` 会优先使用标准外观并忽略自定义背景图。

## 3. 运行时复现证据

使用当前 Xcode UIKit 创建与页面配置一致的 `UISearchTextField`，得到以下结果：

- 初始化后的 `borderStyle` 原始值为 3，即 `roundedRect`。
- 设置 `.white` 后，`backgroundColor` 属性仍读取为白色。
- 保留系统 `roundedRect` 时，可见中心像素是 RGB(242, 242, 242)。
- 将 `borderStyle` 改为 `none`、其余白色背景和 layer 样式保持一致时，可见中心像素是 RGB(255, 255, 255)。

这与真机观察一致，说明灰色来自 `UISearchTextField` 的系统外观绘制层，而不是颜色赋值失败。

## 4. 修复方案比较

### 方案 A：保留 UISearchTextField，关闭系统 borderStyle（推荐）

在 `setupSearchField()` 中先关闭系统边框外观，再继续使用现有白色背景、圆角和边框。

优点：

- 最小改动，只处理根因。
- 保留系统搜索图标、clear button、键盘与现有 `.editingChanged` 搜索逻辑。
- 运行时探针已证明最终填充为纯白。
- 不涉及文案、本地化、资源、数据模型、API 或 target 配置。

风险：

- 需要在真机上确认系统搜索图标、placeholder 和 clear button 的垂直位置保持正常。

### 方案 B：改用 UITextField，并自行配置搜索图标

优点：外观完全由项目控制，不再依赖 `UISearchTextField` 默认样式。

缺点：需要新增 left view、内边距和可能的辅助功能配置；改动明显大于当前问题，且容易引入图标尺寸或触控区域差异。本期不推荐。

### 方案 C：设置背景图或操作 UISearchTextField 私有子视图

不推荐。系统 `roundedRect` 会忽略自定义背景图；遍历私有子视图又依赖 UIKit 内部实现，跨 iOS 版本不稳定。即使同时关闭 `borderStyle` 再设置背景图，也比直接使用现有白色背景冗余。

## 5. 推荐修复设计

采用方案 A，仅修改 `SiteTimeZoneSelectionViewController.setupSearchField()` 的外观配置顺序：

1. 明确关闭 `UISearchTextField` 的系统 `roundedRect` 外观。
2. 保留现有 `.white`、10pt 圆角、0.5pt 边框和边框颜色。
3. 保留 `UISearchTextField` 类型及现有 placeholder、搜索图标、clear button、Return Search 和搜索回调。
4. 不修改页面背景、列表卡片、Time Zone 数据与搜索规则。

## 6. 实施计划

### Task 1：补充回归契约

修改 `Tests/Site/SiteTimeZoneUIContractTests.swift`：

- 要求搜索框明确使用无系统边框样式。
- 要求无系统边框样式在白色背景和自定义 layer 样式之前配置。
- 禁止通过私有子视图遍历或背景图绕过系统样式。
- 先运行 focused contract，确认新增检查在修复前失败。

### Task 2：实施最小修复

修改 `SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift`：

- 仅关闭搜索框默认系统边框外观。
- 不改控件类型、布局约束、搜索逻辑、文案与其他页面。

### Task 3：静态与构建验证

1. 重新运行 `SiteTimeZoneUIContractTests`，确认通过。
2. 运行 `git diff --check`。
3. 使用 generic iPhoneOS、关闭签名，直接执行 `xcodebuild` 验证 `SunSmart`、`Archipelago`、`SLG Sync Plus` 和 `SylSmart` 四个 scheme；该选择页源码属于四个 target。

### Task 4：真机验收

至少覆盖一个当前报告问题的真机/iOS 版本：

- 搜索框静止态内部为纯白，与下方白色列表卡片一致。
- 10pt 圆角和 0.5pt 边框完整，无灰色内填充或方角漏色。
- 点击、输入、清空、Return Search、列表过滤和键盘拖动收起保持正常。
- English 与简体中文 placeholder 无截断。
- 如有条件，再抽查另一个 iOS 主版本和四品牌中的至少一个非 SunSmart target。

静态契约和四 target 构建只能证明源码约束与编译成立，不能替代最终像素颜色和交互的真机验收。

## 7. 变更边界

- 预计修改 2 个既有文件：选择页控制器与对应 UI contract。
- 不新增用户可见文案，因此不修改本地化。
- 不修改资源、target 配置、依赖、SDK、数据库、服务器接口或 Mesh 行为。
- 保留当前 worktree 中与 modal dismissal guard、Site update toast 有关的既有未提交改动。

## 8. 参考

- [Apple UITextField borderStyle](https://developer.apple.com/documentation/uikit/uitextfield/borderstyle-swift.property)
- [Apple UITextField background](https://developer.apple.com/documentation/uikit/uitextfield/background)
- [Apple UISearchTextField](https://developer.apple.com/documentation/uikit/uisearchtextfield)
