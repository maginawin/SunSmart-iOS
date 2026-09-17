# debug_features 开发方案（待确认）

> 本版本已被 [构建模式与角色组合可见性方案](260915_1027_debug_features_visibility_rules_plan.md) 取代。下文的布尔开关、Release 恒关闭及编辑权限参与菜单显示等规则不再作为实施依据。

## 1. 目标与首期范围

在 `SunSmart/devices_config.json` 同目录新增 `SunSmart/debug_features.json`，集中管理开发中功能在 Debug 构建中的可见性。首期以 `sites.site.triggerZone` 为示例接入。

推荐规则：Debug 下由 JSON 开关决定是否允许展示；Release 下统一返回关闭。功能入口仍须满足原有业务权限。

本文是待确认方案，本阶段仅保存文档，不创建功能配置、不修改业务代码和工程配置。

## 2. 当前工程事实

| 检查项 | 当前情况 |
| --- | --- |
| 现有 JSON 加载 | `Common/Mesh/Device/MeshDeviceConfigInfo.swift` 从 `Bundle.main` 读取 `devices_config.json` |
| 示例入口 | `SpaceViewController` 的 More 子页面使用 `SpaceMoreViewController` |
| 入口生成 | `SpaceMoreViewController.makeOptions()` 在拥有 `space.groupOperates` 的编辑权限时加入 `.triggerZone`，当前没有 Debug 限制 |
| 页面跳转 | 点击 `.triggerZone` 后再次检查编辑权限，再展示 `SpacePathTriggerZoneController`；当前搜索到的有效创建入口只有这一处 |
| 同名功能 | `GroupPathSequencePageController` 内还有 Group 级别的 `Trigger Zone` 页签，对应 `GroupPathSequenceTriggerZoneController` |
| 品牌 target | `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`、`Lumineux`，五个 target 均打包现有设备 JSON |
| 编译模式 | 工程级 Debug 定义 `DEBUG`；其余四个品牌 Debug xcconfig 显式包含 `DEBUG`，Release 不包含；SunSmart 使用工程级条件 |

这里存在命名层级差异：用户描述为 Site Trigger Zone，实际控制器和数据采用 Space 命名。建议保留业务配置路径 `sites.site.triggerZone`，首期映射到上述 More 页入口，避免改动现有模型命名。

## 3. JSON 结构与取值语义

### 3.1 层级

使用真正的嵌套 JSON 对象，点号仅用于文档描述路径，不将整个点分路径作为 JSON 字段名。

| 层级 | 字段 | 类型 | 说明 |
| --- | --- | --- | --- |
| 根对象 | `sites` | 对象 | Sites 页面域 |
| `sites` 下 | `site` | 对象 | 单个 Site 页面域 |
| `sites.site` 下 | `triggerZone` | 布尔值 | Site Trigger Zone 在 Debug 下的展示开关，首期设为 `true` |

首期直接以 `sites` 作为根字段，不额外重复包装 `debug_features`，不引入远程配置、品牌覆盖、运行时设置页或配置热更新。

### 3.2 可见性规则

| 构建模式 | `sites.site.triggerZone` | 编辑权限 | 入口表现 |
| --- | --- | --- | --- |
| Debug | `true` | 有 | 展示，允许进入 |
| Debug | `true` | 无 | 隐藏 |
| Debug | `false` | 任意 | 隐藏 |
| Debug | 缺失、无效或加载失败 | 任意 | 隐藏 |
| Release／未定义 `DEBUG` | 任意 | 任意 | 隐藏，不允许通过该入口进入 |

`false` 表示关闭这个开发功能，不表示解除 Debug 限制并向 Release 开放。未接入该管理器的其他业务功能维持其已有可见性。

功能正式发布时，应单独提交移除该功能入口上的开发开关判断及对应 JSON 字段，保留业务权限判断；单纯修改或删除 JSON 字段不会让它自动在 Release 上线。

## 4. 加载与访问设计

建议新增 `SunSmart/Common/Config/DebugFeatures.swift`，包含轻量的嵌套配置模型和统一访问入口。

1. 使用 Foundation 与 `Decodable` 解析嵌套结构，为页面提供可由编译器检查的属性访问，避免页面自行拼接字符串查找键值。
2. 管理器内部使用 `#if DEBUG` 区分构建模式。Debug 首次访问时从 `Bundle.main` 同步加载一次并缓存；Release 直接提供全部关闭的结果，不读取 JSON。
3. 配置为包内静态资源。修改后重新构建、安装并启动 App 生效，不写入数据库或 UserDefaults。
4. 缺少某级对象、字段或字段为 `null` 时，对应功能默认关闭；布尔字段只接受 JSON 布尔值，不将字符串或数字转换为开关。
5. 文件不存在、读取失败、JSON 语法错误或已知字段类型错误时，整份配置回退为全部关闭；Debug 输出一次简短诊断，不弹出用户提示、不导致 App 崩溃。
6. 额外未知字段忽略，不自动产生新功能；新增功能仍需补充明确的模型属性和页面接入点。
7. 将解析逻辑与 Bundle 加载分离，便于使用内存数据验证缺失字段、损坏配置及默认关闭规则。

配置只管理开发功能的页面可见性与入口可达性。它不会移除 Release 包内的页面类、图标或底层协议实现，也不作为权限系统的替代品。

## 5. Site Trigger Zone 接入

在 `SpaceMoreViewController` 内集中定义可见性条件：开发功能开关允许展示，并且拥有当前 Space 的 Group 编辑权限。

- `makeOptions()` 使用该条件决定是否将 `.triggerZone` 加入数据源。隐藏时直接不生成条目，使列表正常收拢。
- 点击分支在创建 `SpacePathTriggerZoneController` 前再次检查开发开关，并保留当前编辑权限校验及现有本地化提示。
- 权限变化通知继续调用既有 `reloadOptions()`，撤销权限后入口及时消失。
- 长按 BLE 条目插入 Mesh 测试入口的逻辑继续基于同一 `makeOptions()` 构建数据，验证插入位置与点击映射。

首期边界：只限制 Site／Space More 页的 Trigger Zone 管理入口。Group → Path Sequence 中的同名页签不接入该键；现有 Trigger Zone 的持久化、导入导出、云同步、设备同步和拓扑清理逻辑继续保留，避免因 UI 隐藏改变已有数据行为。

如果期望隐藏的范围也包括 Group 页签，需要在确认时扩大范围，并进一步检查页签数量、切换索引、添加按钮和保存行为。若期望 Release 连底层 Trigger Zone 行为也禁用，则需要另行分析数据兼容性，不能仅使用页面开关完成。

## 6. 多 target 与资源接入

| 文件 | 计划变更 |
| --- | --- |
| `SunSmart/debug_features.json` | 新增嵌套配置，示例开关默认 `true` |
| `SunSmart/Common/Config/DebugFeatures.swift` | 新增模型、加载缓存和编译模式判断 |
| `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift` | 菜单生成和点击跳转接入统一判断 |
| `SunSmart.xcodeproj/project.pbxproj` | 为五个品牌 target 同步添加 Swift Sources 和 JSON Resources 引用 |
| `Tests/`、`scripts/` 下对应验证文件 | 添加配置行为验证及必要的菜单集成验证 |

五个品牌共用同一份 JSON。首期参照 `devices_config.json` 将资源加入各 target 的 Copy Bundle Resources，Debug 与 Release 均可包含文件；Release 通过编译条件保证不读取且开关恒为关闭。无需增加条件复制脚本。

实现时检查各 target 最终生效的编译条件和资源打包结果，避免遗漏 Lumineux，也避免覆盖已有品牌宏。预计无需修改 xcconfig、本地化资源、依赖或 NordicSigMeshSDK。

## 7. 验证与验收

### 7.1 配置行为

- 使用真实解析逻辑验证：`true`、`false`、缺少叶子字段、缺少父对象、空对象、`null`、错误类型、损坏 JSON、文件不可用及未知字段。
- 分别以定义和不定义 `DEBUG` 的方式编译验证程序；确认非 Debug 即使面对全为 `true` 的有效配置，也始终关闭且不调用资源加载路径。
- 验证缓存只加载一次，配置错误不会导致页面或 App 崩溃。
- 通过菜单行为验证开关与权限的组合，以及跳转前的二次检查。

### 7.2 构建与资源

- 使用直接 `xcodebuild` 对五个品牌的 Debug、Release 执行 iPhoneOS 构建，使用 generic iOS destination 并关闭代码签名校验。
- 核对最终编译条件、Swift 源文件参与情况、JSON 资源存在且没有重复复制。
- 不使用 Simulator，也不使用 shell 包装或日志重定向执行 iOS 构建验证。

### 7.3 实际布局与交互

按项目要求，UI 验收必须包含实际布局测试。使用 iPhone、iPad 真机执行以下场景，检查英文与简体中文，以及 iPad 横竖屏：

| 场景 | 验收结果 |
| --- | --- |
| Debug，开关开，有权限 | More 页展示 Trigger Zone，点击正确进入原页面 |
| Debug，开关关／缺失 | 条目消失，列表无空白占位，其他条目布局和点击正确 |
| Release，JSON 中开关为 `true` | 入口仍隐藏 |
| 编辑权限被撤销 | 入口随通知消失，旧点击路径无法继续进入 |
| 长按 BLE 显示 Mesh 测试条目 | 插入索引正确，不误跳转到其他功能 |
| Group Path Sequence 页 | 同名页签及现有交互保持正常 |

检查 collection view 边缘约束、content inset、itemSize、滚动范围及弹出页面尺寸，保留截图与实测结论。若缺少可用真机，应明确记录实际布局验证未完成，不以编译或静态检查替代。

## 8. 实施顺序

1. 确认本方案的布尔值语义、Site 入口范围及五品牌统一生效。
2. 添加 JSON 和统一配置访问层，完成配置行为验证。
3. 为五个 target 添加文件引用，接入菜单生成与点击检查。
4. 完成 Debug／Release 构建、资源检查、真机布局及交互验收。
5. 在 `docs/` 保存实现总结、验证证据和未完成项。

## 9. 建议确认结论

采用嵌套布尔结构；`sites.site.triggerZone` 首期为 `true`；Debug 仍需满足业务权限才展示，Release 恒隐藏；`false`／缺失／无效默认关闭；仅控制 Site／Space More 页入口，五个品牌统一应用。
