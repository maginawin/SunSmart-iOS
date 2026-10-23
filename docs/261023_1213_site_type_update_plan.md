# Site 类型改为 siteType：需求分析与待确认方案

日期：2026-10-23。状态：用户已确认，App 改动、11 组定向回归及六品牌 Debug 构建已完成；真机及服务器回读待验收。

## 结论与数据契约

需求合理。`isHdbSite` 是二元判断名称，而当前功能是项目类型选择；改用可空字符串 `siteType` 能直接表达类型及旧项目未指定类型的状态。null 是兼容状态，UI 仍只提供 Standard / HDB 两个选项。

- 功能配置路径：`sites.site.siteType`，值仍是 builds / roles / targets 规则对象。
- Site 数据路径：`site.extensionData.siteType`，值为 JSON null 或精确字符串 `"Standard"` / `"HDB"`。继续使用现有 extensionData，不另加 Site 顶层镜像字段或数据库列。
- 当前配置为 Debug/Release 开启，创建类型选择仅限 HSmart；改名保留这些配置。其他品牌仍可读取并使用明确标记为 HDB 的项目，按现有权限控制入口。

| 输入 | 有效类型 | 建议保存/导出 | HDB Configuration |
| --- | --- | --- | --- |
| 首次加载或导入时缺少 siteType | Standard | `siteType: null` | 隐藏 |
| `siteType: null` | Standard | `siteType: null` | 隐藏 |
| `siteType: "Standard"` | Standard | 保留 `"Standard"` | 隐藏 |
| `siteType: "HDB"` | HDB | 保留 `"HDB"` | 满足现有功能规则、角色和编辑权限时显示 |
| 只有旧 isHdbSite，不论 true / false / null | Standard | `siteType: null`，移除旧 key | 隐藏 |
| 新旧 key 同时存在 | 只按 siteType 判断 | 只输出 siteType | 按新类型和现有权限判断 |
| siteType 为布尔、数字、未知字符串或大小写不符 | Standard，不开启 HDB | 规范化为 null | 隐藏 |

新建项目默认显式保存 `"Standard"`，选 HDB 才保存 `"HDB"`；禁止从品牌、Space 的 hdb 数据或旧 true 推断 HDB。

**兼容后果：当前只保存 `isHdbSite:true` 的测试/已有项目也归入 Standard，不再显示 HDB 入口或触发 HDB 初始化/设备配置。这是本方案按“旧项目不要转成 HDB”的明确解释。已有 Lighting Zones、设备记录和地址占用保留，不因字段转换自动清空或释放；本期不新增旧项目转为 HDB 的编辑入口。**

本方案已确认并替代 `261021_1002_HDB_site_type_analysis_plan.md` 及 `261023_0954_create_site_design.md` 中关于 isHdbSite 持久化和配置路径的约定；其他创建表单行为不变。

## 当前实现及必要改动

核对分支 `feat/HDB-261020`，HEAD `1673c3b8`；分析开始时工作树干净。当前工程已新增 HSmart，共六个品牌，不能沿用旧文档的五品牌假设。

### 1. 共享模型与存储

实际类型存储在 `SiteExtensionData.fields`，`SiteExtensionStore` 把完整本地/服务器/待同步状态保存到 SQLite `site_extensions.payload`。Site 普通保存不会替代此独立扩展表，Site.copy/clone 和导出会读取扩展表。

修改 `SiteExtensionData.swift`、`SiteData.swift` 及必要的 Store 访问方法：

- 在已有共享模型文件内定义字符串枚举，例如 `SiteExtensionData.ProjectType`，通过可空 `siteType` 表达三种存储状态；业务判断使用有效类型或只读派生 `isHdbSite`。派生 Bool 不是持久化字段，不再允许独立写入。
- 现有 `SiteData.SiteType: Int` 表示 office / warehouse / school / other，与本需求不同；保留其 `type` 和既有协议值，不复用或重命名它。
- 展示读取失败时继续隐藏 HDB；创建 Space、添加设备等修改路径继续使用可抛错的持久读取，不将存储故障当作合法 Standard。
- 旧 key 从编码、导出及语义比较中移除；不根据其值生成新 HDB 类型。通过统一解码/编码规则覆盖 data、serverData、pending/submitted 的 base/target 及 archivedPendings，避免恢复旧快照重新带回旧字段。
- 无需批量更新数据库或提升 Trigger Zone schemaVersion；读取时兼容，下一次正常保存/导出写新格式。保留 Trigger Zones、创建元数据和其他未知字段，保留同步 operationId、版本及恢复记录。

### 2. 局部回包与同步比较

`SiteExtensionState.receive` 当前对缺少类型字段的响应实行 patch 合并，且禁止用缺字段回包确认未完成的类型变更。`normalizedFields` 当前同时用于编码和相等比较；新方案必须分开存储表示与有效类型比较。

- 首次加载没有 siteType：null / Standard。
- 已有明确新类型，后续响应省略 siteType 或整个 extensionData：保留已知类型。缺字段是没有更新此字段，不代表明确清空。
- 有效新响应显式 siteType=null / Standard：按已有时间戳、冲突和 pending 规则接收为 Standard；不能被旧 isHdbSite=true 覆盖。
- 比较时将缺失/null/Standard 视为同一有效类型，避免旧格式与显式 Standard 产生同版本假冲突；编码时仍保留 null 与显式 Standard 的区别。
- pending 若包含从 Standard 到 HDB 的变化，缺少 siteType 的回包不能确认成功；只修改 Trigger Zone 而类型未变时，继续允许合法缺字段回包按已有合并规则确认。
- 旧 isHdbSite 不再参与冲突判断。保持未知业务字段、Zone 对象和真实类型变化的完整比较，不能整体放宽一致性检查。
- 覆盖现有 Site 导入/导出、siteAdd/siteUpload、Site props 回读、Trigger Zone 整对象保存、copy/clone；复用现有同步队列，不新增上传通道或伪造云确认。
- Trigger Zone 云内容指纹目前编码整个 extensionData。格式变化可能改变指纹，应验证旧计划按现有机制重新核对，不因 null/Standard 表示差异误确认设备任务，也不复用不匹配的旧回执。

### 3. 配置、创建表单与业务使用方

- `debug_features.json` 将 isHdbSite 改为 siteType；`FeatureVisibility.Feature.siteTypeSelection` 更新路径。创建能力仍只检查 build/target，保留通用角色检查，使用入口不依赖创建品牌限制。
- `SiteCreationDraft`、`SiteTypeSelectionAlertView`、`SiteCreateViewController`、`SiteData.add` 统一传递枚举；默认 Standard，Done 只改草稿，CREATE 首次保存类型。类型选择关闭时新建 Standard，保留失败回滚、重试和其他表单草稿。
- UI 继续复用现有 Standard Site / HDB Site 本地化文案，不展示 null 选项，不新增资源或页面。
- 业务统一依据新字段：Space More 显示和点击复核、新 Space 的 63 个 Lighting Zones 初始化、添加设备时 MAC 规则及收尾、HDBDeviceSyncContext、配置服务、Sync Device 计划与执行时复核、同步状态缓存失效。只改变类型来源，不改变 HDB 命令或设备协议。
- Store 只在有效 HDB 状态切换时继续使节点同步缓存失效；null 与 Standard 之间不应触发 HDB 行为变化。

### 4. 存量数据与删除/恢复一致性

已确认 `SpaceSyncCleanupCoordinator` 当前仅在 Site 为 HDB 时调用 `finishSensorGroupCleanup`；该方法处理删除日志中已 cleaned 的 sensorGroupId，并校验无设备引用及 Group 归属后才收尾。旧 true 项目改按 Standard 后，该入口会跳过，需纳入本次关联处理。

- HDB 初始化、设备配置和菜单只允许显式新 HDB 类型。
- 对已有 HDB 删除记录的收尾，依据现存待处理日志和存储状态判断，保留方法内地址引用、归属及持久化验证；不能因类型改名永久遗留 cleaned 地址记录。无日志时不执行，也不因存在历史 HDB 数据批量清理地址。
- 普通导入导出、删除、复制及已有异常数据的恢复仍能处理保留的数据。`SpaceRecoveryViewController` 已允许按 hdbLoadFailed / 已有 hdb 数据进入恢复，保留这一独立条件，不把“能恢复旧数据”误写成“项目是 HDB”。
- 本期不自动改设备订阅/发布，不清空旧 HDB 状态，不扩展恢复架构；若回归揭示超出此改名导致的其他问题，单独报告。

## 实施与验证边界

确认后按共享模型/合并规则 → 创建和配置 → 消费方与遗留清理 → 回归与构建的顺序实施。主要改动复用现有文件；未计划新增工程文件、依赖或 SDK API。

| 验证 | 必须覆盖 |
| --- | --- |
| `check_site_hdb_type.sh` | 三态、缺字段、非法值、旧 true 不迁移、新旧 key 冲突、对象/字符串解析、旧 key 不输出、null/Standard 等价比较、缺字段不能确认新 HDB pending |
| `check_site_hdb_persistence.py` | 真实 SQLite 首次保存、重载/重开、失败回滚和重试、旧 payload 及 pending/base/target 读取、copy/clone、读取错误 |
| `check_site_creation.sh` | 新建显式类型、默认 Standard、元数据保留和表单草稿 |
| `check_feature_visibility.sh` | 当前六品牌及 Debug/Release 规则、HSmart 创建选择、Standard/null 隐藏、HDB 按角色显示、其他菜单不变 |
| `check_hdb_space_creation.py` | Standard 不分配 HDB 地址，HDB 初始化、地址不足及保存失败回滚 |
| `check_site_trigger_zones.sh` 及相关同步夹具 | 整对象更新保留新类型、null/Standard 不引入假冲突、失败重试、版本顺序和指纹边界 |
| 现有 HDB 集成、导入恢复、Group 生命周期和 Site 批量清理夹具 | 类型读取服务入口、旧数据仍可维护、已有删除记录收尾、类型变化后旧执行上下文失效 |

根据实际生产路径选用上述脚本中的相关用例，脚本中抽取旧方法名或 Bool 测试替身同步更新；已有夹具未覆盖的必要行为补行为测试，不以源码字符串检查代替运行。

生产代码完成后再核对本地 workspace、scheme 和 SDK realpath，使用 Debug generic iOS 无签名构建；优先验证本次唯一提供创建选择的 HSmart，并覆盖共享逻辑的代表品牌 SunSmart。由于修改六品牌共享配置资源，稳定后合入前覆盖其余受影响品牌 Debug 构建，串行复用稳定 DerivedData。不使用 Simulator，不自动操作真机。

人工最短验收：HSmart 新建 Standard/HDB → 分别进入 Space More → 退出重进；导入缺字段及旧 isHdbSite=true 的项目，确认仍为 Standard；新 HDB 经服务器保存、回读和另一客户端导入后仍为 HDB；检查 Standard 无新 HDB 初始化、HDB 的现有流程继续可用。

## 外部契约与当前验证状态

- App 可以独立完成改动。服务端责任方需确认 extensionData 对 siteType 的 null/字符串原样保存及回读，覆盖 Site 创建、上传、props 更新和 GET；若服务端存在旧 key 白名单/转换，由其团队处理，不修改服务器或固件代码。
- 旧 App 只认识 isHdbSite，新 App 将只输出 siteType；旧 App 不保证识别新 HDB 项目。需要多客户端使用 HDB 时应同步升级，不能双写旧 true 来规避这次数据契约。
- 本轮实施和自动化结果见下节；未运行真机或服务器联调，历史测试结果未作为本次通过证据。


## 实施与验证记录（2026-10-23）

已实现 `sites.site.siteType` 配置和 `extensionData.siteType` 三态存储。创建草稿、类型弹窗及首次保存使用枚举；已有业务入口继续复用统一持久读取和只读派生 Bool，所有 HDB 判断均来自新字段，没有双写旧 key。旧 true 在本地读取、导入、复制、待同步及归档快照中均不会变成 HDB。

存储编码保留 null / Standard 的区别，语义比较统一按 Standard；缺字段证据保留到远端合并之后。保留真实类型冲突、旧版本拒绝、未确认类型变更及多次编辑的回执顺序保护。`SpaceSyncCleanupCoordinator` 按删除日志执行已有的安全收尾，已有无引用/归属/持久化校验不变，无待处理记录时不写 HDB 数据。

进一步核对确认：`cloudFingerprint` 当前只用于 DEBUG 诊断日志，不是设备回执或可执行任务的确认依据；保留其按实际 JSON 内容计算的行为。新增回归验证旧 key 不影响新格式指纹、null 与 Standard 业务等价但序列化不同、HDB 实际改变类型和内容，无需改动指纹协议或设备任务机制。

本轮以下 11 组定向检查通过：

- `check_site_hdb_type.sh`：三态与非法值、旧 true 排除、新 key 优先、对象/字符串、Zone 保存、局部/迟到回包、同版本冲突、多次编辑回执，以及创建完成回调。
- `check_site_hdb_persistence.py <SDK path>`：实际 SQLite 失败回滚、首次类型保存、连接重开、copy/clone、区域隔离和故障；额外直接植入旧 true 的 data/serverData/pending/submitted/archived 快照，验证 operationId 保留、旧 key 清除、Zone 回执和缓存失效。脚本同时覆盖已有初始化回执的保存/重开。
- `check_site_creation.sh`：新建默认显式 Standard、HDB 草稿与元数据、空值和长度/时区规则。
- `check_feature_visibility.sh`：六品牌及未来品牌规则、Debug/Release、实际类型解析与生产菜单的缺字段/null/Standard/旧 true/HDB 场景、权限和资源归属。
- `check_site_trigger_zones.sh`：Zone 数据/候选/展示/拓扑、同步状态及完整扩展指纹。
- `check_site_zone_cleanup_batch.py <SDK path>`：真实 SQLite 类型变更及回滚、批量清理、重启、失败/取消与同步入口。
- `check_space_sync_readback_reuse.py`：生产清理入口的旧记录收尾、无记录不置脏、失败保留/重试、持久回读及上传保护；日志和地址操作在此为边界替身。
- `check_hdb_integration.py --device-sync`：实际 HDB context/planner/store、类型隔离及上下文失效；Standard 时仍保留被引用地址，引用消失后完成安全收尾，删除失败可重试，无日志不保存数据。
- `check_hdb_space_creation.py`：Standard 普通创建、HDB 的 63 Zone 初始化、地址不足、失败回滚/重试与 feature gate。
- `check_hdb_import_recovery.py`：既有 HDB 数据导入保护、默认恢复和列表刷新。
- `check_hdb_group_lifecycle.py`：既有 Group 归属与空目标目录保留。

构建入口为 `SunSmartLocal.xcworkspace`，SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `e7c1a7f327191a67adb8143e9b588f757892fde7`，核对时 SDK 工作树干净。本任务没有修改 SDK、依赖声明、工程配置、固件或服务器。沙箱内 Xcode workspace 识别失败后，使用获准的沙箱外 xcodebuild 正常识别，未更换 workspace 或清缓存。

所有构建使用 Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO，串行复用 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020`。HSmart、SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 均明确 BUILD SUCCEEDED，并逐个核对构建产物含新 siteType key 和 HSmart 创建规则。构建存在既有警告，无本次编译失败。本次没有运行 Release App 构建，双模式功能规则由上述配置回归覆盖。

尚未验证真机布局/体验、真实 Mesh 设备运行及服务器对新字段的保存/回读。按前述最短人工路径验收；自动化中的数据库/SDK/云替身不代表服务器或固件已验证。`git diff --check` 通过，改动仅涉及本任务 App/测试及文档；修改未提交。
