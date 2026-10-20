# HDB Site 类型分析与开发方案

日期：2026-10-21。工作树：`feat-HDB-261020`，分支：`feat/HDB-261020`，HEAD：`bdd4243d`。

状态：用户已确认方案，App 实施、定向回归、五品牌 Debug 构建与最终审查已完成。真机体验及服务器回读待人工验收；未提交。下文方案保留为已确认基线，执行结果记录在文末。

## 结论与已确认范围

需求合理，建议采用现有 `SiteExtensionData` 增加 Bool 字段的方案。创建能力由包内配置决定，已创建 Site 的类型由持久数据决定，HDB 页面仍受当前 Space 的权限限制。

用户已补充确认：

- `sites.site.isHdbSite.targets` 仅限制新建时的类型选择；其他品牌导入或云同步取得 `isHdbSite=true` 的 Site 后，可以使用 HDB Configuration。
- 旧项目统一按 `isHdbSite=false` 处理，不根据已有 HDB Space、Lighting Zones 或品牌推断类型，不做旧项目升级为 HDB 的迁移。
- 本期没有类型编辑功能，创建选择不使用 `isHdbSite.roles` 限制；此配置仅保留给未来编辑功能。

必要关联修改：新增 Space 的 63 个 HDB Lighting Zones 初始化也必须检查所属 Site 类型。仅修改菜单会留下 Standard Site 隐性分配地址、地址不足时无法创建 Space 的行为。

## 分析时的代码证据（实施前）

| 环节 | 已确认行为与影响 | 依据 |
| --- | --- | --- |
| 配置 | 用户已新增 `sites.site.isHdbSite` 并移除 HDB Configuration 的 targets，当前尚无对应功能枚举或创建选择读取逻辑 | [debug_features.json](../SunSmart/debug_features.json)、[FeatureVisibility.swift](../SunSmart/Common/Config/FeatureVisibility.swift) |
| 创建 Site | `SitesViewController.addSite` 立即调用 `SiteData.add`，追加列表、导航并提交云同步；`SiteData.add` 创建 Mesh、保存 Site | [SitesViewController.swift](../SunSmart/Main/Site/Controller/SitesViewController.swift)、[MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift) |
| 扩展数据 | `SiteExtensionData.fields` 可保留未知字段；独立 `site_extensions` 表保存整个扩展状态，Site 普通保存只 bootstrap，避免覆盖既有扩展 | [SiteExtensionData.swift](../SunSmart/Common/Data/SiteExtensionData.swift)、[SiteExtensionStore.swift](../SunSmart/Common/Data/SiteExtensionStore.swift)、[Database.swift](../SunSmart/Common/Data/Database.swift) |
| 重载 | `SiteData.load/loadAll` 创建对象时没有装载独立扩展表；直接读对象的默认 `siteExtensionData` 不能保证获得持久值 | [Database.swift](../SunSmart/Common/Data/Database.swift) |
| 导入/导出/云同步 | Site 更新调用 Store.receive；导出读取独立表；首次 siteAdd 和后续 siteUpload 均使用同一 Site.export 输出 | [ImportData.swift](../SunSmart/Common/Data/ImportData.swift)、[ExportData.swift](../SunSmart/Common/Data/ExportData.swift)、[CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) |
| 属性读取与 Trigger Zone 保存 | Edit Site 读取 props 时会接收扩展；Trigger Zone 保存提交完整 extensionData，并保留其他字段，需要回归新标记不会丢失 | [SitePropsEditCoordinator.swift](../SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift)、[SiteTriggerZoneCoordinator.swift](../SunSmart/Main/Site/TriggerZone/SiteTriggerZoneCoordinator.swift) |
| HDB 菜单 | 展示与点击都经 `canShowHDBConfiguration`，目前只检查配置及 Space 的 group edit 能力，可在同一入口增加 Site 判断 | [SpaceMoreViewController.swift](../SunSmart/Main/Space/Controller/SpaceMoreViewController.swift) |
| 新增 Space | `SiteData.addSpace` 使用 HDB 功能规则决定是否分配 63 个地址并初始化 HDB；地址不足会在创建 subnet 前失败 | [MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift) |
| 拷贝/克隆 | Site.copy 已从独立表读取扩展，cloneData 基于 copy；新标记应随源 Site 保留，不进入新建类型选择 | [SiteData.swift](../SunSmart/Common/Data/SiteData.swift)、[Database.swift](../SunSmart/Common/Data/Database.swift) |

当前三个 FeatureVisibility 业务使用方分别是 Site JSON 导出、Site Trigger Zone 和 Space HDB Configuration；新增创建开关不能改变前两者的角色判定。`debug_features.json` 与共享 Localizable.strings 已确认均属于五个品牌 target。

## 建议方案与优化

### 1. 数据语义

- 唯一持久化字段为 `site.extensionData.isHdbSite`，类型为 JSON Bool。
- 仅布尔 `true` 表示 HDB；`false`、null、缺字段均视为 Standard。字符串 `"true"`、数字 1 等不隐式开启 HDB。
- 新建 Site 在首次保存前明确写入 true/false；旧项目无需批量改库，读取默认为 false，正常输出时补齐显式 false。
- 保留扩展对象中的 Trigger Zones、schemaVersion 和未知字段；此可选标记无需新增数据库列、表或提升 Trigger Zone schemaVersion。
- 仅为新增字段提供类型化访问，不扩展现有 office/warehouse 等 `SiteType`：它们表达场所用途，与 Standard/HDB 不是同一个维度。
- Site 类型读取统一从独立扩展存储取得最新值，避免每个控制器自行读取默认实例。菜单读取失败时隐藏入口；创建 Space 时若存储真实读取失败，应报告错误，不能把读取失败当作合法 Standard 并创建错误类型的 Space。

兼容边界：旧项目首次读取或首次导入缺字段就是 false。已保存新标记的 Site 遇到局部云响应缺字段时，要保留既有 patch 语义，避免一次不完整响应抹掉新 Site 的 true；显式 `isHdbSite:null/false` 则按 false。保留字段是否出现的信息，完成接收合并后再规范化；不得为了补默认值覆盖整个扩展对象或伪造 pending 的云确认。

整个 extensionData 无效与其中一个 key 缺失是不同情况：本任务不放宽现有完整性检查，不把损坏对象强制替换为空对象。扩展状态、pending/base/target 的默认值比较需要一致，避免 missing/null/false 的表示差异引入假冲突。

### 2. 两类开关分别判断

保留用户已经修改的 JSON 结构，内部枚举/方法用“Site 类型选择”命名，使功能开关与持久化 Bool 的用途清楚。

| 决策 | 条件 |
| --- | --- |
| 创建时弹出类型选择 | `sites.site.isHdbSite` 的 builds、targets 匹配当前包；不检查当前 Site 角色，也不伪造 owner 传入通用权限接口 |
| 创建选择未启用 | 直接走现有创建流程并保存 false |
| 展示 HDB Configuration | 最新持久值为 true，再检查 `sites.site.space.hdbConfiguration` 的 builds、当前 `space.permission`，并保留 `space.groupOperates.contains(.edit)` |
| 新 Space 初始化 HDB | Site 为 true 且现有 HDB 初始化配置允许，按新 Space 的 owner 角色继续既有初始化规则 |

对 `FeatureVisibility` 增加独立的 build/target 判定入口，普通 `isVisible(feature, permission:)` 的权限语义不变。创建配置的 roles 即使调整为其他合法角色或空集合，也不能影响本期类型选择；配置本身损坏仍按现有规则关闭该功能分支。

HDB 使用入口不再检查创建开关的 targets。这样已确认的跨品牌导入行为成立，也避免以后关闭“新建 HDB”时意外隐藏已有 HDB Site。

### 3. 创建交互

流程：点击 Add Site → 检查创建开关 → 选择类型 → Continue → 创建 Mesh/Site、保存类型 → 更新列表并进入 Site → 使用原云同步队列上传。

- 标题建议 `Site Type`；选项 `Standard Site` / `HDB Site`，单选，默认 Standard。
- 选项切换只更新弹窗内的临时选择；点击 Continue 才创建。
- 按钮复用 `alert_item_cancel` / `alert_item_continue`，实际英文遵循项目当前 `CANCEL` / `CONTINUE` 风格。
- Cancel 或取消关闭不创建 Mesh/Site、不消耗编号、不更新列表、不提交同步。再次打开恢复默认 Standard。
- 防止连续点击 Add/Continue 导致重复弹窗或重复创建；弹窗关闭完成后再导航，沿用现有 dismiss 回调机制。
- 创建类型在首次 `site.save()` 的 bootstrap 前写入，避免保存完成后仅修改内存导致云端导出仍为 false。
- 当前 `SiteData.add` 忽略 save 返回值；本次需要让创建失败可传回调用方。保存失败时不导航、不排队上传，并只清理本次新建的资源；重试使用当前选择。
- 云同步失败仍保留已成功创建的本地 Site 和类型，复用现有重试队列，不重新创建第二个 Site。

UI 优先复用 `SRAlertView` 作为弹窗容器，使用 Site 专用的轻量两项单选内容，不修改共享菜单选择器的点击即关闭语义。现有 `TitleSelectView/TableSelectView` 均选择后立即关闭，不直接满足“切换选择后再 Continue”的要求。可参考项目已有 `SiteTriggerZoneAlertView` 的定制方式；本次不新增通用选择框架。

新增标题/选项同步补齐 English 与简体中文，例如 `Site Type` / `场所类型`、`Standard Site` / `标准场所`、`HDB Site` / `HDB 场所`。

### 4. HDB 行为与旧项目

- Space More 展示、重新进入及点击复核共用同一个判断。
- Standard Site 创建 Space 不初始化 HDB、不占用 63 个 Lighting Zone 地址，也不受此地址数量检查阻断。
- HDB Site 创建 Space 继续既有 63 个 Zone 初始化、地址不足处理、保存失败回滚及重试路径。
- 旧 Site 即使已有 HDB 元数据，也保持 false 并隐藏 HDB Configuration；保留其既有数据和地址占用，不自动清空、释放、重建或升级类型。
- 导入导出、普通组归属过滤、删除恢复等数据维护机制不受菜单开关阻断。不能用新增 Site 判断阻止已有数据的正常清理/恢复。
- 本期不增加类型编辑页，不修改 HDB Mesh 消息、设备 preparation 或本机感应方案；此前 occupancy 分析是独立任务。

### 5. 其他可选方案

- 新增独立 `siteType: standard/hdb` 枚举字段：适合已有明确多类型扩展需求时采用，但本期只有二元标记且用户已指定协议 key，增加迁移与接口成本，没有必要。
- 继续仅靠 target 判断 HDB：不能表达同一 SunSmart 中 Standard/HDB 共存，也无法让类型随 Site 导入和同步，不满足目标。

推荐采用上面的 Bool + 现有存储 + 分离创建与使用条件方案。

## 实施顺序与文件范围

1. **模型与持久化**：`SiteExtensionData.swift` 增加类型化字段语义；`SiteData.swift`、必要的 `SiteExtensionStore.swift` 接入统一持久读取；对接 Site 导入/导出默认值、局部回包和其他扩展字段保留。复用现有表，不迁移旧项目为 HDB。
2. **配置读取**：`FeatureVisibility.swift` 注册 `sites.site.isHdbSite`，添加只检查 build/target 的创建能力查询；保留用户 JSON 改动和通用角色检查。
3. **创建交互**：`SitesViewController.swift` 接入单选弹窗；`MeshNetwork+SunSmart.swift` 的 Site 创建方法接收默认 false 的类型参数，在保存前写入并返回失败；新增局部 UI 文件时加入五品牌 target，更新两种语言。
4. **行为联动**：`SpaceMoreViewController.swift` 增加 Site 类型前置条件；`SiteData.addSpace` 同步增加类型条件，沿用原初始化/回滚逻辑。
5. **定向验证**：更新现有数据、配置、菜单与 Space 创建回归，必要时增加直接执行生产路径的持久化/创建行为夹具；完成构建与人工验收说明。

SDK、固件和服务器代码均无计划修改。服务端需保持现有 extensionData 任意字段透传契约；当前仅从 App 代码确认请求链路，尚无新字段的服务器回读证据。若服务端丢弃字段，由后端团队确认/修复既有契约并进行联调，不由 App 私改服务器或仅靠本地缓存掩盖问题。

## 验证与验收

优先复用：

- `scripts/check_feature_visibility.sh`：五品牌、Debug/Release、创建规则不受 roles 影响；HDB 菜单按 Site 标记、Space 角色与编辑能力判定；其他功能行为不变。现有测试仍期待 HDB 仅 SunSmart 且只注册三个配置，需随新语义更新，不能直接把旧断言当作新需求的标准。
- `scripts/check_site_trigger_zones.sh`：true/false/null/缺字段、对象与 JSON 字符串、未知字段保留、Trigger Zone 保存及回执比较；局部响应不得误清新标记。
- `scripts/check_hdb_space_creation.py`：Standard 不分配 HDB 地址且零可用 HDB 地址时仍可创建；HDB 的 63 个 Zone、跨 Space 地址不重复、地址不足、持久化失败回滚及重试。
- 按实际改动补 `check_hdb_persistence.py` / `check_hdb_import_recovery.py` / `check_hdb_group_lifecycle.py` 的相关用例，证明旧 false Site 的已有数据仍可保存、导出和清理，不机械全量运行所有 HDB 测试。
- 持久化验证须覆盖独立表重新加载、退出重进、Site.copy/clone、云任务重试；隔离的内存 double 不能代替实际 SQLite 保存/重载证据。

生产代码修改完成后核对本地 workspace 与 SDK realpath，使用 SunSmart 的 Debug generic iOS 无签名构建。新增共享 UI 文件/资源涉及五品牌归属时，在稳定后合入前覆盖受影响品牌 Debug 构建；Debug/Release 规则通过现有双模式测试覆盖，如实际引入不同编译路径再补对应 Release 构建。实施结果见文末。

最短人工验收路径：

1. SunSmart 点击 Add Site，默认 Standard；切 HDB 后取消，列表无新增；重开仍默认 Standard。
2. 分别创建 Standard/HDB；进入 Space More，只有 HDB 且允许编辑时展示 HDB Configuration。
3. Standard 创建 Space 不出现预建 HDB Zones；HDB 创建 Space 保持现有初始化。退出 App 后重进结果不变。
4. 导出、云回读/另一客户端导入后类型不丢；其他品牌不出现新建类型弹窗，但可使用导入的 true Site。
5. 旧项目统一隐藏 HDB 入口；不自动删除其既有数据。检查 iPhone/iPad、英文/中文两项选择和按钮布局。

## 实施与验证记录（2026-10-21）

已完成：类型化 Bool、默认值输出与比较、局部回包保留、统一持久读取、build/target 创建开关、默认 Standard 的创建弹窗、HDB 菜单与 Space 初始化联动，以及英文/简体中文文案。UI 采用 `SitesViewController.swift` 内的私有 `SRAlertView` 子类，无新增工程文件或 target 配置。

保留了用户原有 `debug_features.json` 改动及独立 occupancy 分析文档；没有修改 SDK、正式依赖配置、固件或服务器。当前本地 workspace 为 `SunSmartLocal.xcworkspace`，SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision 为 `8c5af55`，核对时 SDK 工作树干净，无新 API 发布依赖。

### 必要的实现调整

真实 SQLite 用例复现：扩展表写入失败后，SQLite 包的 savepoint 仅执行 `ROLLBACK TO`，未释放 savepoint。继续创建时同连接可读到记录，但新连接读不到，说明重试没有完成提交。本次在 `SiteData.add` 外层使用完整 transaction：失败整体 rollback，成功整体 commit，再进行 UI 导航和云同步；不修改 SDK 或无关保存入口。

此调整属于已确认的创建失败/重试一致性范围。测试用真实 SQLite 触发扩展保存错误，运行生产 Site.save、add、load/loadAll、copy/clone 和扩展 Store，验证回滚、重新创建与数据库重开；Mesh 创建/删除和无关元数据采用测试边界，不能据此宣称真实 SDK 磁盘清理或云端已验收。

只读审查发现并复现了弹窗关闭动画与列表刷新交错：新 Site 已保存，后台刷新先将其载入列表，关闭回调又追加一次。本次按 Site id 与 region 检查后追加，保留刷新所得实例；提取实际生产完成方法的测试在修复前失败、修复后通过。数据链路审查未发现需修复问题，UI 审查的上述问题已关闭。

### 已通过的自动化

- `check_site_hdb_type.sh`：缺失/null/非法类型默认 false、显式 bool 导出、true roundtrip、未知字段、Trigger Zone 编辑保留、局部回包及 pending 确认边界；正常新建与弹窗关闭期间列表刷新均只显示一条 Site，正常导航与提交同步。
- `check_site_hdb_persistence.py <SDK realpath>`：真实 SQLite 的创建失败回滚、首次类型保存、失败后重试与重开、持久读取、copy/clone、局部导入和 region 隔离；数据库不可用时展示关闭、修改入口抛错。
- `check_feature_visibility.sh`：五品牌 Debug/Release、每种编译组合 216 个通用规则矩阵用例及新增创建开关用例；菜单顺序、Site 类型、Space 角色/编辑能力和既有导出/Trigger Zone 入口。
- `check_site_trigger_zones.sh`：既有 Zone 数据、条目、候选和拓扑回归。第一次因系统 CryptoKit 模块缓存目录不可写中断，显式设置允许写入的 `CLANG_MODULE_CACHE_PATH` 后完整通过；未改业务代码绕过环境错误。
- `check_hdb_space_creation.py`：Standard 零 HDB 可用地址下创建普通 Space，读取错误阻断，HDB 63 Zones、分配/保存失败回滚和重试。
- `check_hdb_persistence.py`、`check_hdb_import_recovery.py`、`check_hdb_group_lifecycle.py`：原 HDB 数据维护与恢复行为。
- JSON 配置结构、两种语言 strings 语法、五品牌资源归属和 `git diff --check`。

SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的 Debug generic iOS 无签名构建均已通过，并核对五个产物内的新配置及英文/简体中文字符串。构建使用稳定目录 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020`，同目录串行。存在项目既有警告；Archipelago 的 quiet 输出出现矛盾的 exit-code-0 错误提示，普通输出复核明确为 BUILD SUCCEEDED。未执行 Release App 构建，双模式配置规则由隔离测试覆盖。

### 待人工/联调

本轮未安装或运行真机，弹窗视觉、选择/取消/继续、iPhone/iPad 布局，以及真实服务器对新字段的保存/回读仍按上文最短路径验收。自动化覆盖了本地行为和请求使用的数据结构，不能替代服务器跨客户端同步及真实 UI 体验。

## 用户确认后的命名与位置整理（2026-10-21）

按用户要求，将完整 Site 扩展数据的共享职责从 TriggerZone 目录提取到 `SunSmart/Common/Data`：

| 文件 | 职责与名称 |
| --- | --- |
| [SiteExtensionData.swift](../SunSmart/Common/Data/SiteExtensionData.swift) | `SiteExtensionData`、JSON 值表示，以及重命名的 `SiteExtensionUpdatePayload`；统一处理 Site 类型、Zones 和未知字段 |
| [SiteExtensionState.swift](../SunSmart/Common/Data/SiteExtensionState.swift) | `SiteExtensionState`、`SiteExtensionPending`，保存整个扩展对象的本地/服务器快照、待确认更新和恢复状态 |
| [SiteExtensionStore.swift](../SunSmart/Common/Data/SiteExtensionStore.swift) | `SiteExtensionStore`，负责独立扩展表的创建、读取、保存、删除和接收 |
| [SiteTriggerZoneData.swift](../SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift) | 保留 Trigger Zone、成员、展示成员、草稿、设备变更记录与引用清理类型 |

同步更新导入导出、普通 Site 保存/复制、属性回读、云恢复、拓扑和清理使用方，以及测试源码列表与五品牌 Xcode Sources 归属。未新增另一套存储或同步机制，也没有改变现有完整扩展对象的合并策略。数据库仍是 `site_extensions`，Codable 字段、JSON key 和 schemaVersion 不变，无需数据迁移。

逐类型核对确认：11 个模型类型及 Store 的实现，除符号重命名外均与整理前一致。HDB 默认值、真实 SQLite 保存/重开、Trigger Zone 数据/候选/拓扑、批量清理与懒加载回归通过。迁移后的 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 均完成 Debug generic iOS 无签名构建，结果为 BUILD SUCCEEDED；未运行真机。工程文件语法、三份共享源码的五品牌归属及旧符号残留检查通过。

额外执行的 `check_startup_ownership_loading.py` 未能编译：测试边界缺少 `SpaceMembershipCoordinator`。使用未修改 HEAD 的脚本、生产代码与测试文件在临时目录复现相同错误，确认是既有夹具问题；本次仅更新其中的 Store 名称，未扩大范围修复该测试。其测试结果不能计为通过；实际 App 编译及批量恢复相关回归另行验证。
