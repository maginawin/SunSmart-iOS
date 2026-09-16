# debug_features 构建模式与角色组合可见性方案（待确认）

> 入口范围已于 2026-09-15 更正，见 [Site Trigger Zone 入口纠正](260915_1050_site_trigger_zone_entry_correction.md)。`builds AND roles` 规则仍有效；本文将示例映射到 Space More 及使用 `space.permission` 的描述已作废。

## 1. 核心规则

每个功能由一个规则对象管理，包含允许展示的构建模式列表 `builds` 和角色列表 `roles`。

**是否展示 = 当前构建模式在 builds 中，并且当前页面对应的角色在 roles 中。**

列表内部满足任意一个值即可；两个列表之间必须同时满足。缺失或无效规则默认隐藏。

本方案取代上一版布尔开关设计。Debug 和 Release 都读取配置，Release 可以按规则展示功能。本阶段仅修订方案，不修改 App 代码或创建实际 JSON。

## 2. 配置结构

保留 `SunSmart/debug_features.json` 文件名和嵌套页面层级，以 `sites.site.triggerZone` 为例：`sites`、`site` 是分组对象，`triggerZone` 是包含以下字段的规则对象。

| 字段 | 类型 | 用途 | 示例功能推荐值 |
| --- | --- | --- | --- |
| `builds` | 字符串数组 | 允许展示的构建模式 | 仅包含 `debug` |
| `roles` | 字符串数组 | 允许展示的当前资源角色 | 包含 `owner`、`editor` |

不添加额外总开关；任意列表为空即对所有用户隐藏。暂不增加父级继承、品牌覆盖或通配符，每个功能规则独立完整，避免默认值隐式扩大展示范围。

虽然文件仍名为 `debug_features.json`，其职责已扩展为功能可见性配置，名称不再意味着 Release 全部关闭。

### 2.1 构建模式配置

| 需求 | builds 中的值 |
| --- | --- |
| 仅 Debug 展示 | `debug` |
| Debug 和 Release 都展示 | `debug`、`release` |
| 仅 Release 展示 | `release` |
| 全部隐藏 | 空数组 |

当前工程使用 `#if DEBUG` 识别构建模式：定义 `DEBUG` 为 debug，否则为 release。该规则依赖最终编译条件，与安装渠道、连接调试器、App 内 Debug 菜单无关。后续如果增加自定义构建配置，需要明确其编译条件归属。

### 2.2 角色配置

项目现有 `Permission` 定义于 `SunSmart/Common/Data/SiteData.swift`，包含三个角色：`owner`、`editor`、`visitor`。

| 需求 | roles 中的值 |
| --- | --- |
| 仅 Owner 展示 | `owner` |
| Owner 和 Editor 展示 | `owner`、`editor` |
| 所有角色展示 | `owner`、`editor`、`visitor` |
| 全部隐藏 | 空数组 |

显式列出角色，不依据枚举数值大小推断权限等级。所有角色指当前三个已定义角色，未来新增角色时需要显式更新配置。角色缺失或无法识别时隐藏。

### 2.3 九种组合

下表单元格描述允许展示的人群，未提及的构建模式和角色均隐藏。

| builds 策略 | 仅 Owner | Owner、Editor | 所有角色 |
| --- | --- | --- | --- |
| 仅 Debug | Debug 的 Owner | Debug 的 Owner、Editor | Debug 的 Owner、Editor、Visitor |
| Debug、Release | 两种构建的 Owner | 两种构建的 Owner、Editor | 两种构建的 Owner、Editor、Visitor |
| 仅 Release | Release 的 Owner | Release 的 Owner、Editor | Release 的 Owner、Editor、Visitor |

首期列表方案在所选构建模式之间使用同一组角色。若后续需要“Debug 所有人、Release 仅 Owner”，应扩展为按构建模式分别配置角色；这不属于本轮列出的九种组合。

## 3. 角色取值范围

配置路径用于组织功能，不自动推断角色来自哪个模型。由页面传入其操作资源的当前角色，避免把 Site 的汇总权限用于某个具体 Space。

| 功能上下文 | 角色来源 |
| --- | --- |
| Site 自身功能 | 当前 `site.permission` |
| Space 内的功能 | 当前 `space.permission` |
| Group／Device 等归属 Space 的功能 | 所属 `space.permission` |

示例功能虽然使用 `sites.site.triggerZone` 这个业务路径，实际由 `SpaceMoreViewController` 展示并编辑当前 Space 的触发区域，因此使用 `space.permission`。用户在其他 Space 拥有 Editor 身份，不会使当前 Visitor Space 的该功能自动展示。

规则数据可缓存，角色及可见性结果不做全局缓存。切换 Site／Space、重新显示页面或收到权限变化通知时，使用当前角色重新计算。

## 4. 可见性与操作权限

现有 `SpaceMoreViewController.makeOptions()` 通过 `space.groupOperates.contains(.edit)` 决定是否展示 Trigger Zone。`groupOperates` 除了检查角色，还会受 `disableEditorPermission` 和 `meshOTADistribution` 影响。

为满足“所有角色展示”，建议作如下分工：

1. **菜单是否展示：** 仅使用构建模式与角色的组合规则。移除该菜单生成处把 Group 编辑权限作为显示条件的判断。
2. **是否允许进入编辑页：** 点击时重新检查可见性，再执行现有 Group 编辑权限校验；无编辑权限时使用既有 `no_permission` 本地化提示，阻止进入。
3. **实际业务操作：** 保留已有业务权限、锁定状态和同步限制。显示规则不授予编辑、保存或设备操作权限。

由此，“所有角色展示”可以让 Visitor 看见入口，但当前 Trigger Zone 是编辑页面，Visitor 点击后仍受原有权限限制。Owner／Editor 在暂时无法编辑时也可能看见入口但不能进入。

这是本方案相对上一版的明确行为变化：临时编辑限制不再隐藏入口。如果希望 Visitor 可以进入只读 Trigger Zone 页面，需要另行设计只读状态、按钮展示及保存限制；本期推荐保持现有编辑页面，采用上述提示行为。

## 5. 加载、校验与访问

建议使用共享管理器 `FeatureVisibility`，文件建议为 `SunSmart/Common/Config/FeatureVisibility.swift`，职责名称与新的双模式语义一致。包含构建模式枚举、功能标识、规则模型以及组合判断。

- Debug 和 Release 都从 `Bundle.main` 加载 `debug_features.json`，首次读取后缓存规则。
- 使用 `Decodable` 和明确的功能标识，页面不直接读取 JSON，也不重复编写构建模式分支。
- 构建模式由管理器内的编译条件确定；当前资源角色由调用页面传入。
- 将配置解析、Bundle 加载与组合判断分离，以便验证异常输入和两种真实编译模式。
- 资源为包内静态配置，修改后重新构建安装生效，不引入远程下发、设置页、UserDefaults 覆盖或热更新。

### 异常规则

| 情况 | 处理 |
| --- | --- |
| 文件缺失、读取失败、JSON 整体语法错误、根结构无效 | 所有已接入配置的功能隐藏 |
| 功能对象缺失、父分组缺失 | 对应功能隐藏 |
| builds／roles 缺失、为 null、类型错误 | 对应功能隐藏 |
| 列表为空 | 对应功能隐藏 |
| 列表含未知值、大小写错误或非字符串元素 | 整条功能规则无效并隐藏，不保留其中有效值继续放行 |
| 重复的有效数组值 | 按集合语义去重，结果不变 |
| 规则内的额外未知字段 | 忽略，不参与可见性判断 |

单个功能规则错误应隔离到该功能，不使其他有效功能失效；实现时需要独立解码每条规则，不能直接让一处叶子解析失败导致整棵模型抛错。已知父分组类型错误时，其下功能全部隐藏。

Debug 输出简短的一次性配置诊断；不新增用户可见文案或弹窗。构建前验证应将无效配置报告为失败，以便在交付前发现拼写错误。

正式开放功能时，将 `builds` 调整为同时包含 `debug` 和 `release`，并设置目标 `roles`；无需移除代码中的统一可见性判断。

## 6. Site Trigger Zone 首期接入

推荐示例配置：`builds` 仅包含 `debug`，`roles` 包含 `owner`、`editor`。

| 当前角色 | Debug | Release |
| --- | --- | --- |
| Owner | 展示 | 隐藏 |
| Editor | 展示 | 隐藏 |
| Visitor | 隐藏 | 隐藏 |

进入编辑页仍需满足第 4 节的业务权限。

改动位置：

- `SpaceMoreViewController.makeOptions()` 根据规则与当前 `space.permission` 决定是否加入 `.triggerZone`。
- `.triggerZone` 点击分支在创建 `SpacePathTriggerZoneController` 前重新判断可见性，随后保留现有编辑权限校验。
- 复用现有权限变化通知刷新菜单，补充页面再次显示时的刷新，防止角色变化后菜单残留。
- 长按 BLE 插入 Mesh 测试入口仍使用统一菜单构建结果，验证插入索引及点击映射。

首期仍只控制 Site／Space More 页入口。Group → Path Sequence 内独立的 Trigger Zone 页签保持原行为；已有数据、同步和拓扑逻辑保持原行为。

## 7. 工程改动范围

| 文件 | 计划变更 |
| --- | --- |
| `SunSmart/debug_features.json` | 新增嵌套规则对象 |
| `SunSmart/Common/Config/FeatureVisibility.swift` | 新增规则解析、缓存和组合判断 |
| `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift` | 菜单显示、角色刷新与点击校验接入 |
| `SunSmart.xcodeproj/project.pbxproj` | 五个品牌同步加入 Sources 和 Resources |
| `Tests/`、`scripts/` 下对应文件 | 规则矩阵、异常配置及菜单行为验证 |

`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`、`Lumineux` 共用配置。两种构建模式均必须包含 JSON，检查最终 `DEBUG` 条件和各品牌宏。无需变更 SDK 或依赖；复用现有本地化提示。

## 8. 验证与验收

### 规则验证

- 覆盖三种 builds 策略 × 三种 roles 策略 × 两种构建模式 × 三种实际角色，共 54 个基本判断场景。
- 使用定义和未定义 `DEBUG` 的实际编译版本分别验证，确认 Release 会加载配置、Release-only 在 Debug 隐藏。
- 验证空列表、缺失字段、未知角色、类型错误、损坏 JSON、单条错误隔离以及加载缓存。
- 验证同一用户切换不同角色的 Space、运行中角色变化、点击时权限已变化的情形。
- 验证所有角色展示配置下，Visitor 看见入口但仍不能进入现有编辑页；OTA／临时编辑限制保留。

### 构建与资源

- 直接运行 `xcodebuild` 验证五个品牌的 Debug 和 Release，使用 iPhoneOS SDK、generic iOS destination、关闭代码签名校验。
- 核对资源打包、源文件归属和有效编译条件。
- 不使用 Simulator，不以 shell 包装或日志重定向执行 iOS 构建。

### 实际布局与交互

- 在 iPhone、iPad 真机验证显示／隐藏后的列表收拢、滚动、条目点击、BLE 长按插入和页面再次显示时的刷新。
- 检查完整 collection view 约束关系、content inset、itemSize 和弹出页面尺寸，覆盖英文、简体中文及 iPad 横竖屏。
- 检查 Group Path Sequence 的同名页签仍正常。
- 保存实际布局测试证据；若缺少真机，明确记录未完成，不能以编译或静态检查替代。

## 9. 待确认实施基线

采用 `builds` 与 `roles` 两个允许列表，二者同时匹配才展示；示例默认 Debug + Owner／Editor；角色取当前 Space 的 `permission`；显示不授予编辑权限，原有业务限制在点击及操作阶段保留；五个品牌统一接入，首期不扩展 Group 同名页签或只读页面。
