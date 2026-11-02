# Edit site 对齐 Create site：分析与开发方案

日期：2026-11-02。状态：用户已确认整体范围并完成 App 实施，相关行为回归及六品牌 Debug generic iOS 构建通过。Site type 按原显示条件展示现有类型、保持只读。真实 UI、服务器回读及网关效果待人工验收。

## 结论与验收目标

建议复用当前 Create site 的完整表单和交互，将创建与编辑的提交行为分开。Edit site 固定显示标题 `Edit site`，底部为 `DONE`；加载已有 Site，点击后保存该 Site。按钮与 CREATE 使用同一校验策略，编辑时重名检查排除自身，不增加“必须修改过才可点击”的条件。

这不只是替换标题和按钮：旧编辑页仅支持名称、时区、图标，新增七项标准属性还没有编辑提交、待同步及回执确认能力。本次必须同时补齐，否则会出现页面可输入但保存后丢失或无法重试的问题。

## 当前事实与分析边界

| 环节 | 当前实现与本次影响 |
| --- | --- |
| 创建表单 | `SiteCreateViewController` 已包含 Project name、Country/Region、City、Time Zone、条件显示的 Site type、Description、位置说明、Street address、Postal code、当前位置按钮、Latitude/Longitude、Site icon。 |
| 编辑入口 | Site 列表菜单与 Site 详情菜单均通过 `permissionOperates.contains(.edit)` 控制，当前仅 Site owner 可编辑；两个入口均先调用 `SitePropsEditCoordinator.prepareDraft` 再打开 `SiteEditViewController`。 |
| 旧编辑表单 | 标题取 `site.name`，底部已使用 DONE；其布局和字段仍是旧版本。已有时区未同步提示、在线确认、离线说明、返回后 Toast 和网关同步结果。 |
| CREATE 可用性 | 名称非空且不是全普通空格、长度不超过 32 个 Character、无重名；没有正在显示的坐标错误；未在提交中。坐标编辑中清除提示，结束编辑或提交时重新校验。国家、城市、时区虽有星号，当前未作为禁用条件。 |
| 草稿与回显 | `SiteCreationDraft` 只有创建初始化，没有从已有 Site 完整恢复的入口；城市需要目录 Entry，存储值则是 GeoNames ID 纯数字字符串。 |
| 本地保存 | 七项标准属性已进入 Site 模型和 SQLite。`SiteData.save` 对已有行先读取数据库值，只有显式 `standardPropertiesPatch` 才修改标准属性；仅给内存赋值再调用普通 save 不会保存编辑值。 |
| 属性更新 | `SitePropsFieldMask`、编辑草稿、更新快照和 `SitePropsAPIClient.update` 目前仅追踪名称、图标、时区。retrieve 已请求并解析七项标准属性。 |
| 其他使用方 | props 合并/确认策略还服务于进入 Site 的时区协调、完整 Site 导入、首次上传回执；标准属性同时被完整导出、分享/导入和重载使用。增加 pending 字段时需保护这些调用方，不能让时区成功清掉元数据待同步记录。 |
| Site type | 位于独立的 `extensionData.siteType`，关联 HDB/Trigger Zones 行为。用户已确认本页只读，不启动类型转换或扩展数据写入。 |

上述事实来自当前源码；没有本轮设备或服务器运行证据。原创建方案文档中较早的 number 坐标约定已被当前代码更新：本次以现有 String/null 输出及兼容解析为准。

## 表单与复用方案

比较三种方式：直接在旧 Edit 页补控件会产生两份布局和定位生命周期；直接把创建成功回调改成编辑回调，会混淆 Site/Mesh 新建与编辑保存；推荐提取 Create 已有的共享表单实现，由 Create/Edit 各自处理提交。

实施时形成轻量 `SiteFormViewController` 和共享表单草稿，限定在 Site 创建/编辑使用；不建设通用表单框架。原两个控制器保留入口职责：创建调用原 `SiteData.add` 与 `onCreated`，编辑调用原协调器与返回/刷新回调。共享输入、搜索、坐标提示、图标、定位请求和取消、键盘避让、时钟刷新，后续两页采用同一套规则。

编辑行为如下：

- 字段顺序、样式、长度限制、国家/城市搜索、位置说明、定位按钮和图标选择与 Create 相同。Site type 按当前创建页的显示条件展示，只读且不显示可点击箭头；保留持久值，旧 null 可以显示有效 Standard，但不得因打开/保存而写成 Standard。
- 标题固定 `Edit site`，不随项目名称修改；DONE 复用现有 `done` 国际化 Key。现有 `edit_site` 英文为 `Edit Site`，为严格匹配指定大小写，增加页面专用 `site_edit_title`（英文 `Edit site`、简中 `编辑项目`），不修改其他菜单文案。
- 项目名称重名查询排除当前 Site 的 ID 与 region 身份，仍拒绝同区域其他 Site 的同名；不能直接复用创建页的无排除查询，否则原名称会把 DONE 禁用。
- 不把 dirty 状态作为 DONE 可用条件。没有变化且没有 pending 时正常关闭，不重复保存、更新时间戳或发请求；没有新变化但存在 pending 时，沿原路径重试。
- 保留编辑专用的时区未同步入口，纳入同一表单校验和提交保护；它不得绕过 DONE 校验提交无效坐标。
- CREATE 的外部行为、默认值和新建后进入 Site 的行为保持现状；共享化需要同时回归创建页。

## 已有数据回显与草稿规则

1. 沿用进入编辑前的在线回读/离线本地加载。草稿带完整原始值及编辑值；初始化只回填，不创建 Site/Mesh，不提交本次编辑。
2. 名称、图标、时区、描述、街道、邮编和经纬度来自已有 Site。时区为空时维持空值，不使用手机时区补齐。初始化即更新描述字数、placeholder、图标选中和按钮状态。
3. 国家按存储代码显示本地化名称；城市根据国家异步读取现有离线目录，把纯数字 ID 映射到内部 `geonames:` 标识。该过程只解析显示信息，不能调用“用户选择城市”的联动入口覆盖已存时区/坐标。
4. 城市目录加载失败、ID 未收录或国家是旧自由文本时，展示原始值作为回退，保留原始存储值；不自动清空、重新推断城市或阻止编辑其他字段。用户明确重新选择时才替换。
5. 存储中没有坐标/时区来源记录，回显数据统一视为初始值，不通过数值相等猜测城市来源。用户本轮选择另一城市，才按 Create 规则覆盖坐标/时区；随后换国家只清除本轮城市派生值，手工/GPS 值保留。
6. 未编辑的旧文本、空值及未识别国家/城市保持原值；仅用户实际修改的字段做现有规范化及提交差异计算，防止点 DONE 顺便裁剪旧长文案、修剪旧文本或清空无法解析的城市。
7. 经纬度沿用范围及空值规则：纬度 -90～90、经度 -180～180，允许 0、负数、单独填写一项和留空；非数字、非有限数、越界必须阻止保存并保留输入。国家/城市/时区为空本身不禁用 DONE。
8. 定位、城市检索及回显请求均核对当前页面、请求身份和 Site/账号/区域上下文。DONE、关闭、离页、后台和手动接管按现有取消规则处理；迟到结果不得覆盖新草稿或已保存数据。提交前再检查当前编辑权限及 Site 正常状态，避免打开后失权/删除仍写入；正常旧空数据仍可保存。

## 保存、同步与恢复

### 标准字段契约

以下字段位于 `/sitespace/update/siteprops` 的 `props`，与 `siteName`、`imageId`、`timezone`、`updateTimestamp` 同级，不写入 extensionData。

| 表单 | 字段 | 输出 |
| --- | --- | --- |
| Country/Region | `countryRegion` | 新选项为大写 ISO2，如 `SG` |
| City | `city` | GeoNames ID 纯数字字符串，如 `795565`，不含 `geonames:` |
| Description | `description` | 字符串/null |
| Street address | `address` | 字符串/null，不发送 `streetAddress` |
| Postal code | `postalCode` | 字符串/null，保留前导零 |
| Latitude/Longitude | `latitude` / `longitude` | 复用当前模型的数值字符串/null；本地仍为 Double?，解析兼容旧数字响应 |

### 提交流程

1. DONE 先收起输入、取消定位/搜索、完整校验，生成本次提交快照。关闭只丢弃本轮草稿；进入页原有属性回读行为保持不变。
2. 在现有 `SitePropsEditDraft`、`SitePropsCommitPlan`、`SitePropsUpdateSnapshot` 中补齐标准属性原值/目标值与逐字段变化。扩展现有 bit mask，保留前三位含义，复用现有 pending mask/timestamp 数据库列，无需新增表或结构迁移。
3. 基于最新本地状态合并本轮真正修改的字段，不用整份旧表单覆盖无关更新。仅变更字段形成显式 Patch；清空发送 null，未修改字段省略。先在同一保存事务写入名称/图标/时区、标准属性 Patch、时间戳及 pending；成功后再开始网络提交。
4. 本地保存失败恢复内存与 pending，停留表单并可再次点击；不得先关闭或显示成功。重复点击和确认弹窗回调受同一提交状态保护。
5. 在线按现有 props update 提交全部待同步字段；响应必须确认对应字段的值和版本。旧响应不能清除新修改的 pending；缺少字段不能充当 null 清空的确认。回读只在待同步字段全部匹配时按现有规则确认，不允许未发送的字段或单独时区回执消除其他 pending。
6. 离线或请求失败保留已落库的修改与 pending，重进/重启后可重试；不自动回退成服务器旧值。成功持久化后沿原 finishEditingHandler 退出和刷新，普通更新与时区更新复用原 Toast/提示流程，明确区分本地保存与服务器成功。
7. 若包含时区实际变更或未同步时区，保留原在线确认/离线说明和 `SiteTimeZoneEditSyncCoordinator` 流程。属性保存确认之后才进入网关同步；城市选择引起的时区变更也必须走此流程。仅改地址、描述、坐标等不新增网关命令。
8. 原 Site 列表和详情的 `siteDidChange`、`timeZoneSyncDidFinish` 回调继续更新列表、详情项目名称及网关时区状态；编辑页标题始终固定。

### 必须核对的共享链路

- `SitePropsEditPolicy`：变更计算、待同步合并、retrieve 确认、ACK 值/版本校验及本地 pending 清理同时认识新增字段。
- `SitePropsEditCoordinator` / API：真实传递显式 Patch；本地保存和提交快照内容一致；迟到 ACK 不覆盖新标准属性或清空较新的修改。
- `SiteEntryTimeZoneSyncCoordinator` 与首次上传回执：仅处理属于本次时区请求的字段，保留其他元数据及 pending；不能以一个 timezone ACK 认定全部字段已同步。
- `ImportData`、完整上传和不同 Site 实例的保存：保持“缺字段不覆盖、明确 null 清空、待同步本地修改受保护”；普通 save 继续保护数据库中的最新元数据，不整体放开为内存覆盖。
- `extensionData`、Trigger Zones、Space/Group/设备配置：本次标准字段提交不重建这些数据，尤其不能复用创建草稿生成的空 extensionData 覆盖已有区域。

外部边界：已有创建方案记录 update/sync 将支持七项字段，App 可按现有接口继续实施；本轮没有线上证据证明 update 已支持全部 string/null、部分字段及回显语义。后端团队负责确认字段接收、明确 null、缺字段保留、响应内容/版本及后续 retrieve 一致性；若不满足，由其团队修正，不修改服务端代码或部署。SDK、固件无新增配套需求；时区网关运行效果仍需按既有流程联调。

## 实施计划与验证

| 顺序 | 工作 | 必要验证 |
| --- | --- | --- |
| 1 | 提取共享表单/草稿，支持已有值回显，保留 Create 行为；接入固定标题、DONE 与只读类型。 | 名称排除自身、按钮状态一致、旧空值、未知国家/城市、回显不覆盖坐标/时区、关闭不提交。 |
| 2 | 扩展编辑协调器、逐字段 pending、显式保存 Patch 和 API 快照/确认。 | 单改每项字段、混合编辑、清空、只改元数据也能提交、无改动关闭、有 pending 重试、保存失败恢复。 |
| 3 | 对齐两个入口与原时区同步，核对导入/完整上传/重载及异步归属。 | 离线保存重启、同字段旧 ACK、不同字段并发更新、时区与元数据混合 pending、迟到定位/城市请求。 |
| 4 | 完成相关回归和构建，提供人工验收步骤。 | 复用现有脚本与行为夹具；构建与设备/服务器验收分开记录。 |

优先使用 `scripts/check_site_creation.sh`、`scripts/check_site_props.sh`、`scripts/check_site_hdb_persistence.py` 的真实 SQLite 夹具，以及 `scripts/check_site_sync_gateways.sh` 中直接相关的时区协调测试；按实际类型改动运行依赖测试。扩展生产模型/协调器/API 的行为回归，不只新增源码字符串断言；因共享表单提取而变化的既有 UI 结构检查同步维护。

重点用例包括：原名可保存而其他 Site 同名拒绝；与 CREATE 相同的坐标编辑/失焦/提交时序；七项均空的旧项目；GPS/城市覆盖后的保存；保存再加载/重启；本地事务失败后重试；请求失败与断网；清空值的服务端回显；旧请求 A 在新编辑 B 后返回；时区成功但其他字段 pending 仍保留；仅修改城市显示信息不产生数据变更；未知目录记录未编辑时不被清空。

所有六个实际 target（SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart）共享此能力。开发阶段运行 SunSmart Debug generic iOS 构建；本方案新增共享文件和标题本地化，稳定后核对六 target 的文件/资源归属，并在合入前完成六品牌 Debug generic iOS 构建。不使用 Simulator，不自动安装真机，不因本次改动默认增加 Release 构建。

最短人工验收：分别从 Site 列表和 Site 详情打开编辑 → 确认完整回显、固定标题、DONE 与只读类型 → 改地址/描述/邮编及 0/负坐标保存并重进 → 清空部分字段保存 → 选择另一城市触发时区确认 → 离线编辑再恢复网络重试；同时验证取消、定位等待中关闭、中英文键盘/长文案/iPad、Create 页未退化。服务端回读与网关真实时区结果单独验收。

## 当前工作树与交接边界

- 分支 `feat/daylight-saving-261024`，本轮核对 HEAD 为 `6f0d6ff5`。开始时工作树干净；分析期间出现他方 `SiteCreateViewController.swift` 当前定位按钮布局修改，本任务未修改该文件，实施前必须在最新状态上保留此改动。
- 已确认 `SunSmartLocal.xcworkspace` 存在，`.local-sdk/nordic-sig-mesh-sdk` 实际指向约定的 `nordic-sig-mesh-sdk-worktrees/one-dev` 且目录存在。实施构建前重新核对依赖状态；本次不修改 SDK。
- 前一轮仅新增方案文档；本轮用户确认后实施。工作未提交，未修改 SDK、固件、服务端或部署配置。


## 实施结果与验证记录（2026-11-02）

已实施：

- 在已有 `SiteCreateViewController.swift` 中提取 `SiteFormViewController`，Create/Edit 分别继承并负责各自提交；共享草稿为 `SiteFormDraft`，保留在已有模型文件中。无需新增 source 文件或改动 project 文件，六品牌沿用原有 Sources 归属。原定位按钮宽度、Tag 和换行调整完整保留。
- Edit 标题固定为 `Edit site`，DONE 与 CREATE 使用同一校验，重名查询按 ID 排除自身。条件显示的 Site type 只读，不写 extensionData。原图标 ID 为 0 等旧值也可保留，首次选择有效图标不会访问负索引。
- 回显已有标准属性与空时区；解析城市标签不覆盖已有坐标/时区；未知城市和未改动的旧长文本原样保留。两个入口保留原权限和刷新回调，补充账号/区域变化后的迟到入口保护。
- 七个标准字段使用独立 pending 位、显式 Patch 和真实 SQLite 保存；原前三位及存储结构不变。提交/回执前轻量读取数据库最新属性，不加载整个 Space 列表，保护其他 Site 实例的更新。属性回执须匹配字段值和版本，缺字段不确认清空；部分时区 ACK 不再把仍有其他 pending 的 Site 标为全部上传。
- 保留普通更新 Toast、时区在线确认、离线说明、网关协调及弹窗关闭后提交顺序。定位/搜索沿用原取消与迟到回调保护，保存失败停留表单并恢复可重试状态。

本轮已通过：

- `scripts/check_site_creation.sh`：创建原有六组回归及新增编辑草稿回显、旧值保留、字段清空、共用按钮策略、城市标签回填不改值。
- `scripts/check_site_props.sh`：七字段逐项变化、混合更新/清空、真实 API payload、缺字段 ACK 拒绝、离线 pending 重试、本地失败回滚、新旧回执及账号切换；原导入及进入 Site 时区策略/协调测试继续通过。
- `scripts/check_site_hdb_persistence.py`：真实 SQLite 编辑保存/清空、排除自身重名、跨 Site 实例不相关字段合并、事务失败、重启重试、旧实例收到旧 ACK 保护新值；原创建/导入/上传回执/类型/复制与恢复回归通过。脚本已在自己临时目录指定 module cache，解决默认缓存目录不可写的环境问题，没有清理共享缓存。
- 单独运行 `SiteTimeZoneEditSyncCoordinatorTests`、`SiteTimeZoneUIContractTests`（路由与资源）、`SiteEditAlertTransitionContractTests`、`SiteUpdateToastUIContractTests`（路由）均通过。后两类 UI contract 属于静态结构检查，不代表 UIKit 运行验收。资源断言已从历史四品牌更新为实际六品牌，并保留 Lumineux 使用合并资产目录的差异。
- `git diff --check`、中英文 strings 和 project 的 plist 语法检查通过。
- 最终代码的 SunSmart、HSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 六个 scheme 均得到 `BUILD SUCCEEDED`。使用 `SunSmartLocal.xcworkspace`、Debug、iphoneos、generic/platform=iOS、`CODE_SIGNING_ALLOWED=NO`；串行复用 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-cli`。SDK realpath 为约定的 one-dev，revision `dbcf6f1`，SDK 工作树干净。
- 逐 target 解析工程确认共享实现和 Localizable.strings 归属，并逐个读取六份构建产物：英文标题 `Edit site`、按钮 `DONE`，简中标题 `编辑项目`、按钮 `完成` 均正确。
- 最后补齐并验证：确认弹窗及后续时区流程使用实际提交值；旧响应对应版本已过期时返回失败，不启动旧时区的后续网关同步；确认期间 pending 已被其他有效流程完成时，DONE 正常关闭，不错误显示一次更新失败。相关 props、SQLite、时区协调和界面结构回归已重新通过，六品牌构建对应此最终代码。

已知验证限制：

- 网关总脚本 `scripts/check_site_sync_gateways.sh` 在首个 `SiteGatewayHeaderLayoutPolicyTests` 用例退出：夹具仍断言最小宽度 112 pt，当前生产策略为 100 pt。两文件均未被本任务修改，本次未改变网关布局来迎合该断言；不能声称总脚本通过。本次涉及的时区协调与编辑路由已单独验证。
- 未运行真机或模拟器，未连接服务器验证新增 props 的实际接收/回读和 null 清空，未验证真实网关时区执行。上述人工验收步骤仍有效。
