# Create Site 页面与扩展数据方案

日期：2026-10-23。范围：App 端 Create Site 页面及元数据；已按确认方案实施，自动化验证完成，真机 UI 与云端回读待验收。

## 1. 已确认需求与本次更新

新增独立的 Create Site 弹出页面，复用现有创建、时区选择、图标、数据库事务和云同步机制。页面只编辑草稿，点击 CREATE 后一次性创建 Site；关闭不产生 Site 或 Mesh 数据。

后续交互要求：Create Site 禁止下拉手势关闭，展示前为承载的导航控制器设置 `isModalInPresentation = true`，从时区选择返回也不解除。保留右上角关闭与创建成功后主动关闭。

该交互修改的 `check_site_hdb_type.sh` 回归与 SunSmart Debug / generic iOS 构建通过；实际下拉手势及从时区页面返回后的表现待人工验收。

用户已确认以下边界：

1. Country / Region、City 是可点击控件，点击暂时没有效果，后续再增加弹窗或页面；本期默认 null，CREATE 时保存 null。
2. Description、Street Address、Postal Code、Latitude、Longitude 支持填写和保存。字符上限分别为 300、300、100、50、50，保存前 trim 前后空白。
3. 新增字段进入 `site.extensionData`；Project Name、Site Icon、Time Zone 继续使用既有 `siteName`、`imageId`、`timezone`，不重复保存。
4. Time Zone 保持现有选择功能。新建默认值仍按最初要求匹配手机时区与 JSON，找不到显示 Unknown；不改变现有编辑/克隆的时区机制。
5. 在 Time Zone 与 Description 之间增加 Site Type 块，默认 Standard Site；点击后弹出 Standard Site / HDB Site 单选项与 Cancel、Done。取消原先进入表单前的类型选择步骤。

实施细节随更新方案确认：经纬度按本次文本长度约束建议保存为 string/null，不增加数值范围校验；Site Type 继续遵循现有品牌 feature visibility（当前仅 SunSmart 显示，其他品牌不显示并保持 Standard）；Use current location 暂无定位行为；本期不扩展 Edit Site 的新增字段编辑能力。用户已确认经纬度类型与品牌范围，按本方案实施。

## 2. Figma 与页面行为

- [Create Site 完整设计](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=656-3435)
- [Why location matters 展开设计](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=656-5750)

已通过 Figma connector 读取结构化层级、关键子节点及截图。设计是浅色背景的 modal sheet：固定顶部标题与关闭按钮，中部滚动表单，固定底部 CREATE 和安全区。按后续体验优化要求，键盘弹出时 CREATE 保持页面底部并被键盘遮挡，不随键盘上移；输入控件不提供额外 Done 工具栏。仅表单可视区域跟随键盘缩小，保留输入框滚动可见、拖动收键盘和单行输入的系统 Return 收键盘行为。设计稿的长画布和局部裁切不作为手机实际固定高度。

表单左右约 20 pt，普通控件约 44 pt 高、10 pt 圆角，字段间隔约 16 pt。采用项目现有 UIKit、SnapKit 和缩放/主题惯例，兼容 iPhone 小屏、iPad、键盘及长本地化文案。

| UI | 初始状态与本期交互 | 保存规则 |
| --- | --- | --- |
| Project Name | 使用 `SiteData.getNextSiteName()`，沿用本地区现有名称编号，不改成 Project 前缀 | 对应 `siteName`；1～32 个 Swift Character；拒绝空/全普通空格及当前服务器区域同名，沿用现有规则 |
| Country / Region | null，显示 `Not configured`，保留搜索图标及箭头；可点击但无动作，不弹提示、不导航、不修改草稿 | `countryRegion: null` |
| City | null，显示 `Not configured`，保留位置图标与说明；可点击但无动作，不弹提示、不导航、不修改草稿 | `city: null` |
| Time Zone | 用页面打开时的手机 IANA identifier 匹配时区目录；显示如 `Asia/Shanghai` 与 `UTC+08:00`，允许手动选择 | 匹配/选择成功写现有规范字符串 `Asia/Shanghai (UTC+08:00)`；不匹配为 nil，界面显示 `Unknown` |
| Local time | Figma 有当前选中时区的本地时间预览，复用现有格式与生命周期计时方式 | 不保存；时区未知时隐藏，不能显示伪造时间 |
| Site Type | 放在整个 Time Zone 块（含 Local time）之后、Description 之前；标题 `Site Type`，行内容默认为 `Standard Site` 加右箭头；无下方说明、无右侧副值 | 复用 `extensionData.isHdbSite`；Standard=false，HDB=true |
| Description | null，placeholder 为 `Brief description (optional)`；固定约 85 pt 高，超高内容在控件内部滚动；显示计数 | 去除前后空白/换行后保留前 300 个 Character；空内容存 null |
| Why location matters | 默认收起；点击整行展开，再点收起，箭头方向变化 | 仅页面状态，不保存 |
| Street Address | null，展示设计稿地址 placeholder；可编辑，沿用 44 pt 输入行，长内容随光标横向滚动 | trim 后保留前 300 个 Character；空内容存 null |
| Postal Code | null，展示设计稿邮编 placeholder；可编辑，长内容随光标横向滚动 | trim 后保留前 100 个 Character；空内容存 null |
| Use current location | 保留图标、按钮外观与 `Most accurate` 标签；暂不接定位，点击不改变已填写内容 | 不申请定位权限，不调用定位/地理编码 |
| Latitude / Longitude | 并排可编辑，保留 `Decimal` 和示例 placeholder；不将示例当初始值 | 各自 trim 后保留前 50 个 Character；建议 string/null，空内容存 null |
| Site Icon | 默认 `site_1`，复用现有选择样式与全部 28 个图标，4 列布局 | 对应 `imageId`，不按 Figma 缩减为 24 个 |

Project Name 的现有实际行为是超长输入截到 32 字符并提示；不自动 trim 名称、不新增字符黑名单、不改变重名比较规则。CREATE 前再次校验，防止页面停留期间其他刷新带来同名。

五个可编辑扩展字段按用户可见字符计数，不按 UTF-8 字节或 UTF-16 单元计数，不切断 emoji 或组合字符。复用同一规范化方法，按字段传入 300/300/100/50/50 上限。输入法 marked text 阶段不截断；组合完成后处理超限；正常编辑不在每次敲空格时 trim，以免影响连续输入；保存时统一 trim → 前 N 个 Character → 尾部 trim，确保截断恰好停在空白处时也没有尾部空白。采用 whitespacesAndNewlines，空结果写 null；保留内部空格及 Description 内部换行。

仅 Description 增加设计稿中的字数计数；其他字段不额外新增计数 UI。经纬度仅落实本期字符限制，不擅自增加经纬度范围、格式、成对必填或地点联动；可用标准键盘输入负号与小数点。以后用于计算时再明确解析与有效性规则，不能把本期保存的任意文本直接作为计算输入。

CREATE 的业务禁用条件只有 Project Name 不合法。Time Zone 为 Unknown、所有新增元数据为 null 均允许创建。提交中的防重复点击是短暂操作状态，不新增字段必填约束。设计稿 `*` 照原样保留。

### Site Type 交互

- 复用 Time Zone 选择行的圆角、内边距、字体、底色和右箭头；将右侧副值与辅助说明设为可选，不复制或显示 UTC offset，不在 Site Type 下显示 Local time。
- 标题为 `Site Type`，初始行文本为 `Standard Site`；选择 HDB 后行文本为 `HDB Site`。用户未要求给该标题增加 `*`。
- 点击行前收起键盘，再展示 `Site Type` 弹窗。两个单选项为 `Standard Site`、`HDB Site`，底部为 `Cancel`、`Done`。
- 每次打开时以表单当前类型初始化弹窗临时选择；点选只改变弹窗选择态。Cancel 丢弃临时选择；Done 更新表单草稿和行文本并关闭弹窗。
- Done 不调用 `SiteData.add()`、不创建 Mesh、不写数据库、不触发云同步；真正写入 `isHdbSite` 只发生在 CREATE。切换类型保留名称、时区、描述、地址、邮编、经纬度与图标草稿。
- 复用现有单选弹窗与本地化键，支持传入初始选择，将原 Continue 动作改为 Done 草稿回调。保留单弹窗防重入和现有禁止点击遮罩关闭行为；关闭整个创建页应一起释放子弹窗。
- 新位置仍受 `FeatureVisibility.shared.canSelectSiteType` 控制；当前 SunSmart 显示此块，其他品牌隐藏此块并固定 Standard。本期不扩大 HDB 的品牌开放范围。

展开说明保留设计的四部分：位置用于日出日落与自动化；街道和邮编提供近似位置；经纬度提高精度；字段可选。文案全部国际化，新增英文与简体中文。Figma 的城市自动填充、以后可随时编辑等说明不代表本期已实现相关能力；本期不因这些说明扩展定位或编辑流程。

## 3. 当前实现与方案取舍

### 已证实的创建链路

`SitesViewController.addSite()` → 按 feature visibility 选择类型 → `SiteData.add()` → 创建 Mesh、保存 Site 与扩展数据 → 刷新列表、进入 `SiteViewController(addSite: true)` → 入队 `syncSite` → 导出完整 Site → `siteAdd` / `siteUpload`。

当前类型选择配置仅对 SunSmart 开放；其他品牌默认 Standard。当前没有上述表单，类型选择后就创建。更新后所有品牌都先直接打开创建表单，类型选择改在表单内部；品牌配置保持不变，真正创建延迟到 CREATE。

当前名称验证、时区选择和图标网格已在 `SiteEditViewController` 实现，但该控制器依赖已存在的 Site 和远端 props 编辑协调器。直接复用整个编辑控制器会迫使打开页面就创建 Site，不适合取消语义。

因此建议新建 `SiteCreateViewController` 与轻量草稿模型；复用 `SiteTimeZoneSelectionViewController`、`ImageCollectionViewCell` 和现有资源。将当前私有嵌在 SitesViewController 文件中的 `SiteTypeSelectionAlertView` 移到可复用视图文件，支持初始选择与 Done 回调，移除旧入口中的类型选择/创建绑定。必要时抽取名称验证小策略和页内轻量选择行，不把整个 Edit Site 改造成通用表单框架。

### 已确认的数据保存边界

新增七个元数据字段进入 extensionData，Site Type 复用已有 `isHdbSite`；现有 name/icon/timezone 保留原位置，不新增 `projectName`、`siteType` 或另一份 timezone 镜像字段。

Time Zone 现有字段不仅用于展示，还影响 props 编辑同步、首次上传确认、Site 进入时检查以及网关/Mesh 时间设置。Project Name 和 Site Icon 也已有列表、编辑、导入导出消费者，不能只迁移创建入口。

## 4. 推荐的 extensionData 契约

保持现有根对象，新增七个可空字段，不增设独立数据库表或另一套同步队列：

```json
{
  "schemaVersion": 1,
  "triggerZones": [],
  "isHdbSite": false,
  "countryRegion": null,
  "city": null,
  "description": null,
  "streetAddress": null,
  "postalCode": null,
  "latitude": null,
  "longitude": null
}
```

这是全新 Standard Site 的完整扩展对象示例。HDB 创建时 `isHdbSite` 为 true；已有 Trigger Zone 数据、schemaVersion 和未知字段原样保留。当前 schemaVersion 1/2 控制 Trigger Zone 能力，新增可选元数据不应升级版本或把旧项目的 2 改回 1。

字段类型建议：七个新增字段统一为 string/null。经纬度由本次补充明确为每项 50 字符的文本输入，因此将上一版建议的 number/null 改为 string/null，以免数值转换丢失用户输入格式；邮编也不转数值，以保留前导零。`"0"`、`"-1.2801"` 等非空文本均应保留，不能把 0 当成未配置。国家/城市选项编码及未来定位策略不在本期定义。该经纬度类型已获用户确认。

未填写的字段保持 null；填写后的字符串规范化再保存。`Not configured`、`Unknown`、placeholder 和本地化提示均不进入数据。

完整 Site 中，与本页有关的片段如下；省略其他现有 Site 字段，并非完整请求：

```json
{
  "siteName": "Site 1",
  "imageId": 1,
  "timezone": "Asia/Shanghai (UTC+08:00)",
  "extensionData": {
    "schemaVersion": 1,
    "triggerZones": [],
    "isHdbSite": true,
    "countryRegion": null,
    "city": null,
    "description": "Main lobby lighting",
    "streetAddress": "1 Marina Boulevard",
    "postalCode": "018983",
    "latitude": "1.2801",
    "longitude": "103.8501"
  }
}
```

以上片段示例为选择 HDB Site 并填写文本后的结果。第一份全 null 示例仍对应默认 Standard Site。

### 旧项目与部分响应

1. 旧项目缺失的新增字段，读取时视为 null；本地扩展对象编码和导出时补齐显式 null。只读取旧项目不改变 `lastUpdate`、不自动制造待上传任务，不批量联网迁移。
2. 解析远端时保留原始 key 是否存在的证据；不能在 decoder 中直接把所有缺失 key 写成 null。`SiteExtensionState.receive` 当前已经对 isHdbSite/triggerZones 区分缺失与显式值，新增字段延续这个原则。
3. 从未有过字段值的旧数据：缺失与 null 在语义比较中等价，避免补字段引发同版本冲突。
4. 本地/服务器快照已知非空字段：部分响应缺失 key 不能清掉已知值。显式 null 才表示清空。若将来存在这些字段的待提交修改，缺字段的响应不能确认该修改成功；与本次共享比较机制相关的夹具需覆盖这一点。
5. 保留未知键及已有 Trigger Zones、HDB 类型；不把 extensionData 重建成只有新表单字段的对象。无效 JSON 或不合法 Zone 的现有保护继续有效。
6. 普通 `site.save()` 仅 bootstrap 扩展表，不替换已有扩展内容，因此创建时必须在首次保存前注入完整草稿；不能先创建默认 Site，再只改内存属性并调用普通 save。

## 5. 时区与保存链路

### 时区复用边界

`SiteTimeZoneCatalog` 已读取指定的 `all_utc_timezones.json`。但现有 `phoneDefaultValue()` 在无法匹配时会计算 fallback，与本次“找不到显示 Unknown”不一致。

新增严格查找入口供 Create 页面使用：匹配目录中的 IANA identifier 后采用该条目的 utcOffset；未匹配、资源缺失或解析失败则返回 nil。不得按 UTC 偏移猜另一个城市，也不把当前手机时区补给旧项目。已有编辑/克隆调用保留原有 fallback 语义。

UTC offset 按 JSON 及现有 Site 固定偏移语义处理；本期不引入新的夏令时规则。UI 使用目录中的 `Asia/Shanghai` 大小写，可将 IANA 与 offset 分列；存储继续使用现有括号格式，不改成逗号格式。

创建接口需要区分“旧调用使用默认时区”和“新表单明确传入 nil”。显式 nil 不得再被 `SiteData.add()` 内部 fallback 覆盖；仅在有有效时区时设置初始 timezone 待同步标记。导出 nil 沿用现有省略 timezone 的协议行为，不能导出字符串 Unknown。

### 创建与失败恢复

1. Sites 点击创建：直接展示创建表单，默认 Standard；不再先弹出类型选择。具备类型选择能力的品牌可在表单中打开 Site Type 弹窗修改草稿。
2. 表单记录账号和服务器区域上下文，保存草稿。切换账号/区域、页面已关闭或重复点击时不得继续创建到错误上下文。
3. 点击 CREATE：再次验证名称与当前类型可用性，按各自长度上限规范化五个文本字段，准备 imageId、可空 timezone 和含 isHdbSite 的 extensionData，然后调用扩展后的创建接口。Country / Region、City 本期显式为 null。
4. 沿用现有事务和 Mesh 创建失败清理；Site 行及 `site_extensions` 必须一起成功。失败保持页面与草稿，允许重试，不在列表留下半成品、不入队同步。
5. 成功后关闭表单，再使用 `showCreatedSite` 刷新去重、进入现有 Site 详情并入队一次同步。保留关闭动画期间列表刷新不会重复添加同一 Site 的保护。
6. 网络离线不阻止本地创建；上传失败沿用已有待同步/重试。重启从持久数据恢复新增字段，不能依赖仍存活的页面草稿。
7. 继续使用现有 export/import、分享/克隆路径和 `SiteExtensionStore`。Trigger Zone 修改是替换完整 extensionData，必须验证它保留本次新增元数据。

已有导出使用 durable extension store，云端新增请求提交完整 Site 对象，因此不需要凭空增加新 API。服务器是否保留并回传这些可选键仍需联调确认：`siteAdd`/`siteUpload`、Site 读取和 props 更新必须保留合法未知键和 null。若服务器过滤字段，作为后端配套契约交由对应团队处理；本任务不改后端或固件。

## 6. 开发顺序与影响面

1. **扩展数据及行为策略**：在 `SiteExtensionData` 增加七个可空字符串字段的访问/规范化；必要扩展 `SiteExtensionState` 缺字段合并；添加草稿、五个文本字段的共用 trim/截断方法和创建时区严格匹配策略。
2. **创建原子性**：扩展 `MeshNetwork+SunSmart.swift` 中的 Site 创建参数，让草稿在首次保存前注入；保留旧调用默认行为、事务回滚和 Mesh 清理。
3. **页面与入口**：新增 `SiteCreateViewController`，修改 `SitesViewController` 为直接打开表单和处理创建完成回调；移用现有 Site Type 单选弹窗并增加当前选择/Cancel/Done 草稿语义；复用时区选择、选择行样式和图标资源；处理键盘、滚动、关闭、计时器生命周期和提交防重。
4. **兼容验证与资源归属**：检查 ImportData/ExportData、Site props、Trigger Zone 更新和克隆对新增字段的保留；补齐英/中本地化及五品牌源文件/资源 membership。

涉及所有共享此入口的五个品牌。开发阶段先验证 SunSmart；新增控制器/模型或资源带来 target membership 风险时，在稳定后、合入前完成五品牌 Debug generic iOS 构建。当前时区 JSON 已包含在五品牌资源配置中，不重新复制五份。

无需 SDK 新 API，无需更改正式依赖或修改固件。Edit Site 本期继续编辑原有 name/icon/timezone；新增 Description 与位置字段的后续编辑界面不自动纳入。

## 7. 验证与验收

以下为本次验证范围；实际执行结果记录在第 8 节，不以历史通过结果代替：

| 范围 | 必要检查 |
| --- | --- |
| 草稿 | 默认名取未使用编号；空/全空格/重名/32 与 33 字符；提交前重新校验；中文输入法 |
| Description | nil、全空白、前后空白、内部换行、299/300/301 字符、长文本粘贴、emoji/组合字符；截断和 null 结果 |
| 地址/邮编/经纬度 | 各自 N-1/N/N+1 边界（300/100/50/50）、trim、空转 null、长文本粘贴与组合输入；邮编前导零、经纬度负号/小数/0 和字符串持久化不丢格式 |
| Site Type | 首次默认 Standard；选 HDB 后 Cancel 不变、Done 更新；重新打开选中当前值；切换保留全部其他草稿；Done 不落库；CREATE 持久化 isHdbSite；品牌 gate 和弹窗防重 |
| 时区 | JSON 匹配、不匹配、加载失败；Unknown 仍可创建且 nil 不被 fallback 覆盖；手动选择；有效时区的初始同步标记 |
| 扩展数据 | 旧对象缺字段→null、编码解码、显式 null、非空值、未知键保留、v1/v2、部分响应不清除、同版本比较及待提交确认 |
| 持久化 | 使用现有真实 SQLite 夹具覆盖字段重载、事务失败回滚、失败后重试；取消不落库；仅一次创建/同步；关闭期间刷新不重复 Site |
| 关联路径 | 导出/导入/分享中字段保留，克隆保留元数据，修改 Trigger Zone 与 Edit Site 原字段不丢元数据；HDB/Standard 分流不变 |
| UI 人工验收 | modal 打开关闭、键盘与固定底栏、小屏/iPad、固定描述高度及内部滚动、地址等长文本光标可见、说明展开折叠、28 个图标可选、时区返回保留草稿、长中英文显示；Country/City 点击无副作用；Site Type 顺序/无副值无说明/Cancel-Done 行为 |
| 云端联调 | 创建/上传后读取字段一致；离线创建再联网；旧响应缺字段不覆盖已保存值；后端若不保留字段需明确配套与发布依赖 |

优先复用 `check_site_hdb_type.sh`、`check_site_hdb_persistence.py`、`check_site_trigger_zones.sh` 和现有 Site 时区行为夹具，新增只覆盖当前新行为或失败场景。UI、真机和云端验收单独标记；默认由用户完成，不自动安装真机。

构建前核对 SunSmartLocal workspace、scheme 与 SDK realpath；按 AGENTS.md 使用稳定独立 DerivedData、Debug、generic iOS 和禁用签名，不使用 Simulator，不清理共享缓存。

## 8. 实施与验证记录

- 工作树 `feat-HDB-261020`，分支 `feat/HDB-261020`，基线 `cb192f06`；不提交或修改其他任务内容。
- 唯一实现负责人为主代理；独立审查代理只读。数据、创建接口、页面、资源与键盘可见性处理均已实现，代码尚未提交。
- 本地 workspace 为 `SunSmartLocal.xcworkspace`；SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `8c5af55`。SDK 已有未提交修改，本任务未写 SDK，构建结果仅代表这一现有本地依赖状态。
- 行为测试先复现旧扩展数据导出缺少 null，然后验证新兼容逻辑；新增草稿/创建接口用例在接口添加前无法编译，接口实现后通过。没有将编译失败描述为已复现运行时失败。
- `check_site_creation.sh`：通过元数据空值、部分响应、显式清空、待提交确认、Unicode/文本长度/trim、经纬度字符串与严格时区匹配。
- `check_site_hdb_persistence.py .local-sdk/nordic-sig-mesh-sdk`：真实 SQLite 验证通过，包含新表单首次落库、空时区、图标、重启重载、失败回滚、克隆保留。
- `check_site_hdb_type.sh`、`check_site_trigger_zones.sh`：通过，覆盖类型兼容、创建完成刷新去重、Trigger Zone 存储/冲突/权限/拓扑等既有相关行为。
- 项目与英/中 strings 语法检查通过；新源文件加入全部五品牌；保留 project.pbxproj 原有顺序，只增加必要项。
- 首次 sandbox 内 `xcodebuild -list` 因系统服务访问/工作区识别失败；已改为申请允许的沙箱外 Xcode 执行，不调整业务代码绕过环境问题。
- 最终代码的 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五品牌 Debug / generic iOS 构建均退出 0，且明确输出 `BUILD SUCCEEDED`；使用上述本地 workspace、稳定 DerivedData 与 `CODE_SIGNING_ALLOWED=NO`。早期 quiet 构建出现矛盾的 SwiftCompile 诊断，已使用非 quiet 最终构建逐品牌复核成功；未将早期诊断视为通过依据。已有弃用、资源重名等警告未纳入本任务。
- 独立代码审查未发现可确认的缺陷，补充键盘滚动处理后也已复核；这不代替实际 UI 验收。
- 最终资源与文案检查通过：新增文案具有英/中键，图标资源完整；Lumineux 使用生成的合并资源目录，已确认构建产物目录包含全部五个新增 imageset。现有时区目录测试通过，`git diff --check` 通过。
- 已还原 Xcode 自动改动的正式 `Package.resolved` SDK revision；本任务未改依赖配置或 SDK 源码。
- 真机 UI、云端保存回传尚未执行，待用户验收；未自动安装设备，未修改服务器或固件。

### 最短人工验收路径

后续键盘优化验证：CREATE 改为固定安全区底部，移除全部输入附件 Done 工具栏，保留表单避让键盘与当前输入滚动。`check_site_creation.sh` 与 SunSmart Debug / generic iOS 构建通过；这是共享布局的小改动，没有新增资源或品牌编译分支，其他品牌不重复构建。键盘弹出、收起及 Description 编辑的真实表现待人工验收。

1. Sites 点击创建，确认默认名称、手机时区和图标；关闭后列表无新增 Site。SunSmart 显示 Site Type，其他品牌不显示并创建 Standard。
2. 在 SunSmart 切换 HDB：Cancel 保留原选择，Done 更新行文本且保留其他草稿；名称为空或重名时 CREATE 不可用。Country / Region、City 点击无副作用。
3. 填入带前后空格的描述、地址、邮编与经纬度，并粘贴超长文本；检查截断、Description 内部滚动、Why location matters 展开/折叠和键盘下正在编辑的字段可见。切换时区、图标后创建。
4. 重启并通过导出/持久化数据检查新字段、图标、类型与时区；云端上传后读取，确认 null 和字符串原样保留。验证离线创建后联网同步。新增字段的 Edit Site 界面不在本期范围。
