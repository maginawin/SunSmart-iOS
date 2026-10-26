# Create Site 页面与扩展数据方案

日期：2026-10-23。范围：App 端 Create Site 页面及元数据；已按确认方案实施，自动化验证完成，真机 UI 与云端回读待验收。

2026-10-26 新需求：根据用户提供的 siteprops 接口字段，将创建页元数据从 `extensionData` 调整到 Site 标准字段，经纬度改为 number。第 13 节方案已获用户确认，city 按后续调整保存纯数字 GeoNames ID 字符串；当前已按方案实施，结果见第 14 节。第 13 节存储规则替代前文对应规则，前述验证结果不覆盖本次变更。

2026-10-23 后续需求：Country / Region 的列表、搜索与代码存储已按用户确认方案实施，见第 9 节；验证结果见 9.7。最新输入行规则见 9.9，替代此前关于右侧箭头和无键盘浏览入口的描述。第 1～8 节是前一阶段记录，其中 Country 仅占位的行为已被第 9 节替换；此前验证结果不作为本次新增功能的验证结果。

2026-10-23 City 后续需求：用户已确认第 10 节需求与第 11 节开发方案，并已授权实施。City 功能及相关自动化验证已完成，结果与待人工验收项见第 12 节；早期阶段的验证不替代本次结果。

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

## 9. Country / Region 开发方案与实施记录

日期：2026-10-23。实施基线：`feat/HDB-261020` / `18527863`，实施前只有本文档的既有未提交修改。用户已确认本节方案并要求继续开发；本次修改限于 App，不修改 SDK、服务器或固件，不提交 Git。

### 9.1 已确认的产品规则

1. 国家目录使用随 App 打包的 JSON；每项保存稳定代码、英文名、简体中文名。Site 的 `extensionData.countryRegion` 保存大写两字母代码，例如 `CN`、`SG`、`US`；未选择保存 null。语言变化只改变显示名称，不修改 Site 数据或触发上传。
2. 英文和中文界面均按**英文名称 A–Z** 排列，切换语言保持条目顺序；中文界面显示简体中文名称。用户已确认此口径。
3. 保留既有规则：初始可以未选择，仍允许 CREATE；一旦点选国家，只能换选其他国家，不提供恢复为未配置的操作。国家列表和搜索结果都没有 None / Clear 项。
4. 点击右箭头展开全部列表并变成下箭头，不唤起键盘；点击中间输入框也立即展开国家选择列表，同时唤起键盘，用户随后输入搜索文字。点选结果立即更新草稿、收起列表和键盘，不增加 Done 确认步骤。
5. 点击选择面板及输入行外部，或者点击向下箭头，只关闭列表、收起键盘、丢弃临时搜索文字，**不更新原来的 Country / Region 值**。原值是当前草稿最后一次点选确认的代码；尚未点选过时为 null。
6. 搜索文本与已选代码独立。清空输入只清除筛选条件；未点选新国家就结束搜索时，恢复原值对应的名称或 Not configured。即使输入恰好等于完整国家名称或代码，也不自动确认。只有点击有效目录项才改变国家，不能保存任意手工填写的国家／地区名。
7. 本次完成 Create Site 的选择、存储和按语言解析名称；City、定位与时区联动继续保持现状。国家代码不影响账号服务器区域 `SiteData.region`。当前 Edit Site 没有国家字段，本次不新增其展示或编辑入口。

### 9.2 Figma 已核对事实与布局

已通过 Figma connector 读取两份屏幕结构和对应字段的完整设计上下文、截图：

- [展开列表屏幕](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=661-5812)，字段节点 `661:5843`。
- [搜索结果屏幕](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=661-6014)，字段节点 `661:6045`。

| 部分 | 设计与拟实施行为 |
| --- | --- |
| 输入行 | 44 pt 高，10 pt 圆角，0.5 pt 浅灰边框；保留搜索图标，右侧箭头独立点击 |
| 面板 | 与输入行同宽、间隔 2 pt；固定 204 pt 高、8 pt 圆角，深灰半透明背景，内部滚动 |
| 选项 | 设计普通条目高 36 pt、条目间隔 4 pt，面板内边距 4 pt；白色 13 pt 文本、左右内边距 20 pt；实际选中项高亮 |
| 少量／无结果 | 面板保持同样高度，结果靠顶部；无结果显示本地化提示，不生成可选占位项 |
| 展开方式 | 设计结构为表单内展开，下方 City 等字段向下移动；采用现有 UIStackView 内的固定高度面板，不遮盖下方表单 |
| 长名称 | 完整名称可换行，单个条目按需要增高，面板高度保持不变；不让长名称挤压箭头或越出面板 |

尺寸沿用项目 SCRXFrom / SCRYFrom 的适配惯例，以 375 pt 设计宽度为基准；“固定高度”指不随结果数量变化。搜索态示例输入 `C`，显示 Canada、China、France，证明当前设计意图包含大小写不敏感的名称子串匹配；截图里的少量国家是示例，不是完整数据集。

设计标题包含多余的字母 `e`，实际文案继续使用现有正确的 `site_create_country` 本地化键。初始继续显示 Not configured；展开未选择／进入搜索后显示 Search country / region。不会把设计中第一项的视觉高亮当成自动默认选择。

### 9.3 JSON 目录、语言和搜索

新增 `SunSmart/country_regions.json`，由轻量 `CountryRegionCatalog` 负责解码、校验、排序、按代码查找和搜索，运行时完全离线；缓存目录加载结果及搜索名称，不按每次输入重复读取文件。

| JSON 内容 | 约定 |
| --- | --- |
| 顶层版本 | `schemaVersion` 为目录文件格式版本；与 Site extensionData 的版本独立 |
| 国家条目 `code` | 唯一、大写、ISO 3166-1 alpha-2 代码 |
| `names.en` | 非空英文显示名称，作为默认名称和排序依据 |
| `names.zh-Hans` | 简体中文显示名称；发布目录要求全量补齐，运行时缺译回退英文 |

目录范围以实施时固定版本的 ISO 3166-1 正式分配代码集合为准，覆盖国家和地区；不把大洲、世界、未知地区或历史退出代码列成可选项。两字母代码是 ISO 推荐的通用形式，适合作为与语言无关的存储值。[ISO 3166 说明](https://www.iso.org/iso-3166-country-codes.html)

显示名称采用 Unicode CLDR **48.0.0**，固定 revision `4d06be52b51bb2f75688d0abe55c52a66afed790` 的 [英文地区名称](https://github.com/unicode-org/cldr-json/blob/4d06be52b51bb2f75688d0abe55c52a66afed790/cldr-json/cldr-localenames-full/main/en/territories.json) 和 [中文地区名称](https://github.com/unicode-org/cldr-json/blob/4d06be52b51bb2f75688d0abe55c52a66afed790/cldr-json/cldr-localenames-full/main/zh/territories.json)。代码集合按 [RIPE NCC 公布的 ISO 3166 国家／地区代码表](https://www.ripe.net/community/internet-governance/internet-technical-community/the-rir-system/list-of-country-codes-and-rirs/) 2026-10-23 快照过滤，生成 249 项，498 个中英文名称与固定 CLDR 原文逐项一致。JSON 的 source 记录版本、revision、代码源 URL、源文件 SHA-256 和获取日期；独立代码快照存于 `Tests/Site/Fixtures/country_region_iso_codes.txt`。Unicode 许可随 `country_regions_LICENSE.txt` 一起打包，不将 CLDR 的大洲／历史／未知地区等其他键作为可选国家。

现有 `all_utc_timezones.json` 是城市／时区目录：同一国家重复出现，没有国家代码，也存在城市或区域修饰名，不能通过简单去重得到完整国家目录。保持时区资源和行为不变。

语言依据 App 实际选中的本地化（与 NSLocalizedString 一致），不依据服务器区域、手机 Region 或单独的首选系统语言猜测。中文本地化使用 `zh-Hans`，其他语言或缺译回退 `en`；不强制改变整个 App 的语言。目录缓存保留原始双语名称，展示时解析，避免将首次加载的语言永久缓存。语言切换后重新进入／重新启动按新语言渲染；本次不引入全 App 热切换语言机制或跨重启保存创建草稿。

搜索规则：

- 对英文名、简体中文名做包含匹配；忽略英文字母大小写、重音和全半角差异，忽略查询前后空白。代码使用完整代码匹配，例如 `CN`。
- 不依赖当前显示语言限制搜索字段；英文界面输入“中国”也能找到 China，中文界面输入 `China` 也能找到中国。
- 空查询返回全部条目；过滤后仍按统一英文名称排序，不按命中字段或输入顺序重新排列。
- 中文输入法组合阶段保留输入，不截断或写入草稿；组合完成后更新结果。仅输入文本或按 Return 不自动选中第一项。
- 本次“模糊搜索”落实为上述包含匹配，不额外引入错拼纠正或拼音搜索服务。

### 9.4 交互状态与生命周期

状态只需要“收起／展开浏览／展开搜索”，另存已确认代码和临时 `query`。选择值归属 SiteCreationDraft；控件显示快照和查询归属当前创建页。

草稿的 `countryRegionCode` 是唯一可保存的值，初始为 nil，仅由有效条目的点选事件更新。控件通过 `CountryRegionSelectionState` 保留该值的显示快照，并管理 mode 和 query；只有拥有者通过账号／页面上下文检查并接受点选后，才同步更新显示快照。`query` 只用于过滤列表，所有输入、失焦、收起、Return 和 CREATE 路径均不得将它写回国家代码。搜索期间原值始终保留，因此关闭时只需丢弃 query 并按原值重新渲染，不需要先覆盖原值再回滚。每次重新打开都以最近一次确认值为准，不以第一次打开页面时的值为准。

| 操作 | 结果 |
| --- | --- |
| 收起时点箭头 | 先结束其他输入，query 置空，显示全部列表；箭头朝下，不弹键盘 |
| 收起时点中间输入框 | 立即展开全部国家列表，query 置空，同时弹出键盘，随后按输入过滤；保留原值（nil 或已确认代码） |
| 已展开时点中间输入框 | 浏览态切换到搜索态并弹键盘，列表继续显示；继续点击正在输入的文本不重置 query |
| 输入／删除查询 | 只更新筛选结果；删至空返回全部列表；不提供清空已选值的按钮 |
| 点击国家条目 | 唯一确认入口：将该条目代码交给草稿，更新本地化名称，清理 query，收起键盘和列表 |
| 点击向下箭头 | 关闭列表并收起键盘、丢弃 query；不更新原值；恢复原代码对应名称，原值 nil 则显示 Not configured |
| 点击面板及输入行外部 | 与点击向下箭头一致；不自动确认输入文字、第一条结果或高亮项 |
| 按 Return／结束编辑 | 结束搜索、收起列表并丢弃 query；不更新原值，即使输入是精确的名称或代码 |
| 点击时区、Site Type、其他输入或 CREATE | 先完成上述收起／恢复，继续原操作；不能把未确认的查询文本提交为国家 |
| 离开、关闭创建页、进入后台 | 收起列表并结束输入；页面还存在时保留草稿选择；关闭整个创建页则与其他草稿一起丢弃 |
| 创建失败后重试 | 保留已选代码及其他草稿，继续沿用现有错误提示与事务重试 |

收起入口区分“点选后收起”和“取消搜索后收起”，收尾清理可重复执行且不会修改已确认值。列表点选先确认代码再执行清理，后续失焦或结束编辑回调不得恢复成点选前的值。外部点击识别排除输入框、箭头、列表选项和列表内部滑动；点击其他表单操作时先取消本次搜索，再执行原操作。

| 打开前原值 | 输入及操作 | 关闭后值 |
| --- | --- | --- |
| null | 输入任意文字，点击外部或下箭头 | null，显示 Not configured |
| null | 输入 China 或 CN，不点选，按 Return 或 CREATE | null；CREATE 继续按原有可空规则保存 null |
| CN | 输入 US、United States 或无结果文字，不点选后关闭 | CN，按当前语言显示 China／中国 |
| CN | 将搜索文字删空后关闭 | CN，不变成 null |
| CN | 点击 United States 条目 | US；再次打开后未选择关闭，仍为 US |

键盘处理继续使用创建页 keyboardLayoutGuide 和表单滚动，将国家输入行加入当前编辑控件的可见性处理；优先同时露出输入行与固定面板。极小可视区域允许外层表单滚动查看，不按结果数改变面板高度。列表内部滑动用于浏览国家，避免被外部点击收起手势截获；点击选项必须先完成选择，不能被失焦回调提前撤销。CREATE 继续固定页面底部，不随键盘上移；不增加输入附件 Done 工具栏。

箭头点击区与文本编辑区独立，保证可点中；VoiceOver 分别表达文本输入、展开／收起和已选项。过滤后更新滚动位置，避免继承上一份结果的越界偏移。账号／服务器区域改变、页面关闭和提交中沿用现有上下文与防重保护，回调不得向失效草稿写值。

### 9.5 实现取舍与完整数据链

已核对当前共享使用方：`SiteCreationSelectionRow` 同时用于 Country、City、Time Zone、Site Type，内部是不可交互的 label stack，没有 UITextField 或独立箭头动作。直接将它整体改成搜索行会联动另外三种控件，所需改动大于新增国家专用组合控件。

新增 `SiteCountryRegionField`，组合 UITextField、独立箭头按钮和固定高度 UITableView，沿用当前字体、颜色、圆角、SnapKit、搜索图标与箭头资源。保留通用选择行的现有接口和其他使用方。已比较现有 `MenuPopView`、`GatewayAPNMenuView` 和设备筛选菜单：它们分别是全局 Window 气泡、APN 分组菜单或固定两项操作菜单，不具备本次表单内编辑／筛选能力；不为本任务改造这些公共弹窗或新建通用下拉框框架。

必要修改及顺序：

1. 增加双语目录与 `CountryRegionCatalog`，固定来源、验证全量代码及名称，提供可注入语言的解析与搜索方法。
2. 在 `SiteCreationDraft` 增加可空国家代码；生成 extensionData 时只读取该确认值并写入已有 `countryRegion`，其余字段、siteType 和 Trigger Zones 保持原机制。点选写入入口验证代码存在于目录；输入框内容不进入创建页普通文本字段收集，也不在 CREATE 时转成国家代码或名称。
3. 接入 `SiteCountryRegionField`、上述状态转换、键盘和退出清理；输入框成为 first responder 时展开列表，外部点击与下箭头共用取消搜索路径，列表点选使用唯一确认路径。给搜索占位、无结果提示及必要可访问性文案补齐英／中本地化。
4. 复用现有 `SiteData.add(...extensionData:)` → `site.save()` / `SiteExtensionStore.bootstrap` 的首次原子存储；不先创建空 Site 再追加保存。
5. 复核 durable extension 导出、`SiteExtensionStore.receive` 导入合并、Site props 回读、`SiteData.copy`／clone、Trigger Zone 完整对象替换对代码的保留，补充行为夹具。已有完整对象通路如无失败证据不修改。
6. 将新 Swift 和 JSON 加入实际共享此入口的全部 target。当前工程除规则列举的 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 外，还有已包含创建页源码的 **HSmart**，资源与编译配置也须覆盖。

国家代码仍在现有可空字符串字段内，无需新增数据库列或升级 Site extensionData schemaVersion，无需 Nordic SDK 新 API。已有保存路径只在首次创建时 bootstrap，因此国家代码必须随草稿一次传入，普通 site.save 不会替换已有扩展对象。

兼容约定：

- 缺字段／null 是合法旧数据，不强迫用户补选，不在读取时变更 lastUpdate 或补上传任务。
- 部分云响应缺少 countryRegion 时保留已知值；显式 null 仍按既有协议处理。UI“不允许清空”只约束新建表单，不能因此忽略服务端显式值或破坏同步规则。
- 外部返回未知代码或旧名称字符串时保留原值，解析不到名称就展示原值；不得因本地目录不认识而清空、自动改写或拒绝整个 Site。只有本次新建表单选择写入规范代码。
- 切换语言不变更持久值；修改其他属性、Trigger Zone 或克隆 Site 不重建一个丢失 countryRegion 的扩展对象。
- JSON 加载失败时提示失败并停止本次选择，保留原草稿；仍按既有可空规则允许创建，不拿示例列表替代完整目录。

外部契约仍需联调：服务器的 siteAdd / siteUpload、Site 读取和涉及完整 extensionData 的 props 更新应接受并原样保留 `countryRegion` 的两字母字符串或 null；跨端写入也应使用同一代码约定。本轮未取得服务器和其他客户端的运行证据，不能声明这些接口已经验证。若存在过滤／名称约定冲突，由后端或对应客户端团队调整；本任务只实施 App，不修改其代码或配置。App 开发可独立完成，跨端发布前需确认契约。

### 9.6 验证边界与实施状态

实施后的最小有效自动验证：

- 目录：固定来源集合与 JSON 一致、代码唯一且格式正确、中英名称齐全、英文排序与重音、资源缺失／损坏、英文回退。
- 搜索与状态：英文／中文／代码、`C` 可命中 France、空查询、无结果、输入法组合；分别以 nil、CN 为原值覆盖点击外部、下箭头、Return、失焦和 CREATE，确认无点选时保持原值；完整输入 China／CN 也不能自动保存；删空查询不清除 CN；点 US 后才替换，后续失焦不撤销新选择；首次未选仍允许创建。
- UI 交互：收起时点击输入框必须同时显示列表与键盘；浏览态点击输入框进入搜索，正在搜索时重复点击不重置文字；外部关闭手势不能吞掉选项点击或列表滚动。以上实际交互依赖运行验收，纯状态夹具不能替代。
- 持久化与兼容：CN／null 的编码解码、真实 SQLite 重载、创建回滚和重试；缺字段保留、显式 null、未知字符串保留、双语显示不改变代码；克隆和 Trigger Zone 更新保留国家。
- 优先扩展 `scripts/check_site_creation.sh` 及现有 SiteCreationDraft／Metadata、HDB SQLite 持久化夹具；新增国家目录与交互策略测试验证行为，不用源码字符串断言代替 UI 运行。
- 实施一轮完成后构建 SunSmart Debug / generic iOS；新资源和源码涉及 target membership，稳定后覆盖全部上述受影响品牌。构建前重新核对当前本地 workspace、SDK realpath 与状态，不复用文档中旧依赖状态当作当前结果。

最短人工验收：打开 Create Site，直接点击空的国家输入框，确认列表与键盘同时出现 → 输入任意文字／完整名称／代码，不点选，分别点击外部和下箭头，均恢复 Not configured → 箭头展开全部列表并选 China → 搜索、删除文字，再分别从外部和下箭头关闭，均恢复 China → 改选 United States，关闭后以及再次打开未选择关闭后均保持 US → 创建并核对保存值。另以从未点选的草稿输入 China 后直接 CREATE，验证保存 null。检查长名称、小屏／iPad、键盘与列表滚动、点击时区后返回保留选择、关闭无落库、失败重试；之后重启核对导出代码，再联调上传和回读。按 App 中英文分别核对同一代码的名称解析；已保存 Site 的 Edit Site 国家展示不在本次 UI 验收范围。

用户已确认上述全部规则并授权实施：**点击输入框即展开列表；只有点选条目才更新国家代码；所有未点选的关闭路径都保留原值（null 或最近确认的代码），搜索文字永不进入持久数据。**实际自动化结果和未验证项见下节。

### 9.7 本次实施与验证结果

- 已完成目录、英文排序、双语名称与搜索、固定高度列表、原值恢复、点选确认、键盘与退出清理，以及草稿到 `extensionData.countryRegion` 的代码写入。既有完整扩展对象存储、导入导出、克隆与 Trigger Zone 逻辑无需修改。
- `scripts/check_site_creation.sh` 通过：包括全量代码快照、中英名称／回退／排序／搜索、资源缺失／损坏、组合输入、取消后保留 nil／代码、精确输入不自动确认、选中后重复收起仍保留新代码、草稿编码，以及部分响应／显式 null／未知字符串／Zone 替换保留国家的行为检查。
- `scripts/check_site_hdb_persistence.py .local-sdk/nordic-sig-mesh-sdk` 通过：生产创建／保存／重载／copy／clone 与扩展存储在真实 SQLite 夹具中执行，国家代码在重载、普通保存、克隆及失败回滚后重试中保留。SDK 网络创建由夹具替代，不代表 Mesh 或云端运行验收。
- `scripts/check_site_hdb_type.sh` 通过，包含现有类型兼容与创建完成列表刷新行为。
- 新 Swift、JSON 与许可已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六个 target，配置无重复项；project 与英／中 strings 语法检查通过。
- 本次构建使用 `SunSmartLocal.xcworkspace`，SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `e7c1a7f`，SDK 工作树干净且未改动。稳定 DerivedData 为 `SunSmart-feat-HDB-261020-Codex`；Debug、generic iOS、禁用签名，串行构建。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六个品牌 Debug / generic iOS 构建均退出 0，并明确输出 `BUILD SUCCEEDED`。逐个核对六个产物，国家 JSON、许可文件均与源文件一致，英／中搜索占位及无结果文案均已打包。现有弃用／资源等警告未纳入本次修改。
- 文档与代码差异检查通过；正式依赖锁文件未变化，SDK 无未提交改动。新增功能尚未提交 Git。
- 真机 UI 与云端上传／回读未执行，按 9.6 的最短路径由用户验收；未自动安装或运行设备。纯状态测试不覆盖 UIKit 手势、输入法回调次序、布局和键盘体验。

### 9.8 展开／收起动画优化

- 国家列表展开采用 0.24 秒、收起采用 0.20 秒的缓入缓出过渡，列表高度、透明度、箭头旋转及下方表单布局同步变化。内部列表保持原固定高度，通过外层容器裁切展开，避免逐帧改变列表内容布局。
- 快速重复点击从当前动画进度接续；重复失焦／取消回调不重启动画。收起时立即禁用选项交互，选择与取消仍沿用原规则，不在动画完成回调中变更国家代码。
- 遵循系统“减少动态效果”设置；页面退出、进入后台及提交时直接完成收起。表单可见区域随布局调整，避免另起滚动动画与展开动画叠加。
- 本轮仅修改共享 UI 展示与控制器联动，无资源、target 配置或 SDK 改动。真机待检查箭头／外部点击开合、连续快速开合、搜索键盘出现及关闭时的动画手感，以及开启“减少动态效果”后的表现。
- 本轮 `scripts/check_site_creation.sh` 通过；修正键盘回调选择器的重载歧义后，SunSmart Debug / generic iOS 构建退出 0，输出 `BUILD SUCCEEDED`。沿用 9.7 的 workspace 与 SDK，本轮仅重建代表品牌 SunSmart；以上检查不替代实际动画验收。

### 9.9 输入行移除箭头并使用系统清除按钮

- 移除 Country / Region 输入行右侧的右箭头／下箭头及其独立点击入口。点击输入框获得焦点，同时展开列表和键盘；仍由点选、点击外部、Return 或失焦结束搜索，列表高度和淡入淡出动画保留。
- 使用 UITextField 的 `clearButtonMode = .whileEditing`：获得焦点且文本非空时显示系统 clear 按钮，空文本或失焦时按系统规则隐藏。清除按钮只清空查询并立即恢复全部国家列表，保留输入焦点、键盘和已确认代码；随后不点选而关闭仍恢复原国家名称或 Not configured。
- 真机最短验收：输入搜索文字 → 点系统 clear，确认列表恢复全部且键盘保留 → 再次输入并点击外部，确认恢复原值。分别以尚未选择和已选择国家检查，并确认右侧不再显示箭头。
- 本轮 `scripts/check_site_creation.sh`、`git diff --check` 通过；SunSmart Debug / generic iOS 构建退出 0，输出 `BUILD SUCCEEDED`。系统 clear 按钮的实际显示和点击体验尚待真机验收。

## 10. City 需求分析与已确认边界（2026-10-23）

### 10.1 结论与已明确的 UI

城市数据可以随 App 内置为分国家 JSON，并支持完全离线选择、搜索和时区关联。用户先确认了城市覆盖口径、中文缺失回退、自动填写时区和经纬度，以及第 10.4 节边界规则；随后确认第 11 节开发方案并授权实施。实现结果见第 12 节。

已通过 Figma connector 只读获取 [City 设计节点 666:8301](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=666-8301) 的结构：输入行 44 pt、位置图标、系统清除样式按钮、城市名左对齐、国家名右对齐。设计面板高 164 pt，样例包含不同国家；这两处以本次用户文字要求为准，改用 Country 当前的 204 pt 面板（含顶部间距的展开容器 206 pt，沿用项目缩放），结果严格限制在已选国家／地区内。

- Country 与 City 采用相同的可编辑搜索行和展开／收起交互，图标、标题、placeholder 与选项内容可配置；Country 继续使用搜索图标，City 使用现有位置图标。
- City 获得焦点后展开列表与键盘，placeholder 为 `Search city`／`搜索城市`；没有搜索文字时展示该国家在已确认目录中的完整城市集合，列表滚动，不按结果数改变面板高度。
- 未确认国家代码时点击 City，提示 `Please select Country / Region first.`／`请先选择国家 / 地区。`，不弹 City 列表和键盘。仅在国家输入框键入名称但未点选，不算已选择国家。
- 右侧国家名通过现有 `CountryRegionCatalog` 按 App 语言解析，不在每条城市数据里重复存中英文国家名。
- Country 控件最新规则以 9.9 为准：无箭头，clear 只清除搜索文字；City 保持一致。

### 10.2 离线数据可行性与实测限制

优先候选为 [GeoNames 数据导出](https://download.geonames.org/export/dump/)，它提供地点 ID、国家代码、行政区、经纬度、IANA 时区及可独立关联的多语言名称；字段定义和 CC BY 4.0 许可见 [官方说明](https://download.geonames.org/export/dump/readme.txt)。应固定数据快照和转换规则，打包来源、许可、修改说明及版本，随 App 发布更新，不在运行时调用 GeoNames API。

`cities500` 的官方口径是人口超过 500 的地点或部分行政中心，并非全球全部法定城市。其他阈值更高的目录覆盖更少；全量居民点则包括大量村庄。原始 `cities500` 还包含城市片区、历史／废弃地点等类别，正式目录需依据 [feature codes](https://www.geonames.org/export/codes.html) 明确纳入集合，不能仅凭文件名把所有记录当成城市。用户已确认首版采用经类型清理的 cities500，以城市／城镇和行政中心为主体，排除历史、废弃地点及不需要的城市片区；具体可复现的筛选规则见 11.1。

2026-10-23 实际下载核对（仅临时分析，原始数据未放入工程）：

| 项目 | 本次结果与含义 |
| --- | --- |
| 原始 cities500 | 236,640 条、246 个国家／地区代码；ZIP 13,902,532 字节。官网 readme 的“约 185,000”是概数，本次实际文件已不同 |
| 规模较大的国家 | 美国 21,785 条、中国 16,055 条；后续需在后台加载当前国家并按需缓存，不能按国家目录 249 条的规模直接推定主线程性能 |
| 基础 JSON 体积实验 | ID、英文候选名、空中文、行政区代码、时区和坐标，紧凑 JSON 共 37,361,278 字节，约 35.6 MiB；未含中文译名、搜索别名和行政区名称，也未做类别清理。这不是最终包增量或运行内存结论 |
| 国家目录差异 | 原始城市数据含当前国家目录没有的 XK；当前目录中的 AQ、BV、HM、UM 无匹配城市记录。保持现有国家集合，不因城市来源自动扩展国家选项；合法无城市和文件缺失必须区别处理 |
| 同国重名 | 按“国家＋忽略大小写 ASCII 名”统计有 14,422 组重名；名称不能作为唯一标识 |
| 时区差异 | 有 16 个 IANA 标识不在现有 `all_utc_timezones.json`，涉及 851 条原始记录；不能无条件直接调用现有 identifier 匹配并假定成功 |

原始 ZIP SHA-256：`8c9b0ad3de5a80493b48344d964972685405380cd2ae2206dc70fce2bf52ac9e`。以上数量均为本次原始文件统计，不是最终产品数据承诺。

名称需通过 [分国家 alternate names](https://download.geonames.org/export/dump/alternatenames/) 的语言标签关联，不能从无语言标签的别名串猜中文。抽样只统计关联到 cities500 ID 且未标记 historic 的 `zh`／`zh-CN`／`zh-Hans` 名称：新加坡 121 条中 61 条有中文，美国 21,785 条中 6,817 条有中文；这只说明名称存在，不证明译名质量、简繁体或唯一性已经合格。当前不能保证每个城市都有准确中文名。

建议英文优先使用有语言标签的常用英文名，缺失时使用可读的拉丁字母名称；ASCII 转写不等于经过校对的英文译名。简体中文优先选可信简体译名，缺失时回退英文展示；不批量生成未经校对的中文地名冒充权威名称。若要求全量准确双语，需要另外确定可满足覆盖率的数据产品或人工补齐范围，城市范围与工作量都将变化。

已比较 [Countries States Cities Database](https://github.com/dr5hn/countries-states-cities-database)：它也提供城市时区，当前声明国家／州多语言和 ODbL 许可；不能据此推定城市中文名称完整。它可以作为备选，当前没有证据表明换用后即可同时解决全量覆盖和中文缺失问题。

### 10.3 已确认的三项关键需求

1. **城市范围**：采用上述 cities500 为基础的城市／城镇目录，展示已选国家在清理后目录中的全部条目，不只返回热门项，不承诺包括每一个小镇／村落。
2. **双语回退**：已有可信中文名则使用中文，缺失回退英文／拉丁字母名；其他语言默认英文。无需全量人工补齐中文。
3. **选择副作用**：选不同城市后更新 Time Zone、Latitude、Longitude，之后仍可手动修改；再次点选同一城市不覆盖手动修改。保留现有说明文案的这项行为。

### 10.4 已确认的其他边界规则

以下默认规则已经用户确认，本次实施按此执行：

| 场景 | 确认行为 |
| --- | --- |
| 模糊搜索 | 仅在已确认国家内匹配城市的中英文名称和已收录别名，忽略大小写、重音和首尾空白；初版为子串匹配，不额外引入拼写纠错。空 query 展示全部，英文名稳定排序；同名按行政区和 ID 排序 |
| 搜索与确认 | 只点选条目才更新城市。输入完整名称、Return、外部点击、失焦、CREATE 都不隐式选第一项；取消恢复原城市。系统 clear 只清查询，不清已确认值；输入法组合期间不提前过滤 |
| 同国内重名 | 保留右侧国家名，左侧仅重名时补州／省，必要时补下级行政区；例如 `Springfield, Illinois` 与 `Springfield, Georgia`，两者可能属于不同时区。不能只显示完全相同的“Springfield / United States”供用户盲选 |
| 国家变化 | 只有确认了不同国家代码才清空 City，取消搜索或重复选择同一国家不清空。记录各字段来源：清除仍来自旧城市的坐标、将仍来自旧城市的时区恢复为创建页初始默认值；手动修改过的字段保留。新选其他城市时再按 10.3 的覆盖规则处理 |
| 两个搜索控件切换 | 同时只展开一个；进入另一个先取消当前 query 并恢复确认值。共享外部点击、滚动、后台、页面退出和提交清理，不能让旧控件的失焦回调撤销新选择 |
| 创建必填性 | 沿用当前可空契约：未选国家／城市仍可 CREATE，不从现有红色星号推导新增强制校验；无城市地区和缺数据不能使合法创建路径被完全阻断 |
| 无城市／无结果／读取失败 | 分别显示“该国家暂无可选城市”“未找到城市”“加载失败”；保持已确认草稿，不能自动跨国搜索、伪造城市、改用首都或把读取失败当作空列表 |
| 异步加载和搜索 | 结果必须同时匹配当前国家、查询代次和有效页面上下文；切国家、退出或提交后忽略旧结果。快速输入／切换不允许旧结果回填，也不允许选中另一国家的记录 |
| 经纬度精度 | 自动填充使用数据中的城市代表点，不等于 Site 实际地址／GPS 位置；保持可手动修正，不顺带实现 Use current location 或反向地理编码 |
| 数据更新与旧 Site | 城市目录随 App 更新；旧 Site 不因名称、目录或时区变化自动改写／上传。目录无法识别的已有城市值原样保留，不据此拒绝整个 Site |

### 10.5 开发方案需要遵守的现有依赖边界

- 共享控件：`SiteCountryRegionField` 目前只有 Create Site 一个生产使用方，可做最小必要扩展，使图标、placeholder、选项副标题、空状态和确认值来源可配置。保留 Country 既有语义和未提交的 clear 按钮改动。`SiteCreationSelectionRow` 还用于 Time Zone、Site Type，不应为 City 把这些行改成文本输入。
- 资源组织：建议放 `SunSmart/CityCatalog/`，目录下包含版本／来源 manifest、许可、`countries/CN.json`、`countries/US.json` 等。城市记录包含稳定 ID、中英文名称／必要别名、行政区、IANA 时区、经纬度；国家从文件／catalog 上下文获取。使用真实资源文件夹打包，避免数百个 JSON 平铺工程或最终 bundle。manifest 区分合法空目录和缺文件。
- 身份与保存：建议草稿持有城市稳定 ID，`extensionData.city` 继续 string/null，例如 `geonames:1796236`；不要保存当前语言展示名作为身份，不把查询串写入数据。此格式仍是待确认契约，需要和其他客户端／服务器使用方对齐。已存在的未知／旧名称字符串不迁移、不清空。无需为此新增数据库列或改变 Trigger Zone schemaVersion。
- 一次性创建：`SiteCreationDraft` → `SiteData.add(...timezone:extensionData:)` → 数据库事务及 `SiteExtensionStore.bootstrap` 是实际首次保存路径。城市、确认国家、最终时区与坐标应在同一次 CREATE 中提交。普通 `site.save()` 不会重新覆盖已有扩展对象，不能先创建再依赖补一次普通 save。
- 传播路径：现有 durable extension 导出、Import／props 回读、部分响应合并及 copy／clone 已按完整对象处理 `city`；需用城市非空值验证，而不是另建同步流程。缺字段保留与显式 null 规则继续适用；创建失败后草稿保留，重试不丢城市。
- 时区：城市必须关联 IANA identifier，不能只保存 `UTC+08:00`，也不能按国家取唯一时区。[IANA 说明](https://www.iana.org/time-zones) 明确时区规则会更新。现有 `SiteTimeZoneValue`／`all_utc_timezones.json` 使用固定偏移语义，本次不默认为要引入夏令时自动切换；若用户期望严格显示当地当前民用时间，需要单独确认这一范围。城市接入前必须核对缺失 identifier、别名和固定偏移的来源，补齐或映射有依据的条目；不能随意拿同偏移地区替代，不能改动已有 Site 的持久值。
- 品牌与外部边界：当前共享入口实际覆盖 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六个 target。新资源与源码需覆盖这些 target；目前没有必须修改 SDK 的证据。服务器／其他客户端需接受并保留约定的城市字段，不涉及自动修改服务端或固件；跨端契约和云端回读仍需联调。

### 10.6 定稿后的验证范围

具体开发步骤和验证安排见 11.5。必要验证包括：目录代码／ID唯一性、合法空国家、重名区分、中英回退、坐标与 IANA 映射、全部国家资源完整性；仅本国搜索、组合输入和取消保留；国家切换与手动覆盖、旧异步结果丢弃；真实 SQLite 创建／重载／回滚重试及 extension 的缺字段／null／旧字符串、导入导出和克隆保留。

优先扩展 `scripts/check_site_creation.sh` 与现有 Site 持久化夹具。资源与 target membership 改动稳定后按项目规则验证六品牌 Debug / generic iOS；不使用 Simulator、不自动运行真机。人工验收覆盖小屏／iPad、键盘、长城市／国家名、重名项和列表滚动；云端回读另行联调。数据加载和搜索的性能结论需实测最大国家样本，不能用 JSON 字节数推定。

分析阶段已完成代码链路只读检查、Figma 结构读取、公开来源核对及临时数据统计；需求确认后形成下面的开发方案。以上均为文档与只读分析，没有修改 Swift／资源／工程，没有构建或执行 App 测试，也没有进行真机／云端验收。

## 11. City 开发方案（2026-10-23，已确认并实施）

### 11.1 数据生成与资源组织

1. 增加离线转换脚本，输入固定快照的 cities500、alternateNamesV2、行政区名称及 IANA 数据。来源日期、版本、SHA-256、过滤规则和人工修订记录写入 manifest；脚本可复现输出，App 构建和测试不下载网络数据。大体积原始压缩包留在生成缓存，不加入 App 资源。
2. 城市 feature code 白名单为 `PPL`、`PPLC`、`PPLA`、`PPLA2`、`PPLA3`、`PPLA4`、`PPLA5`、`PPLG`，即普通居民点、首都、行政中心和政府所在地；不保留城市片区、历史／废弃地点、零散聚落等其他类型。仅接纳当前 Country 目录内的国家代码。对上一轮原始快照试筛得到 **225,061 条、244 个有记录的国家／地区**；最终双语和一致性检查完成后，以 manifest 结果为准，不为了凑数量保留错误记录。
3. 英文名称优先取有效英文别名，否则取可读的 ASCII／拉丁字母名；中文依次优先可信的 zh-Hans、zh-CN、zh 名称，排除历史／已过期名称，必要简繁转换在生成阶段完成并记录来源。preferred、short 等标记和稳定排序决定同级优先级；冲突用小范围人工修订表处理，不采用运行时机器翻译。保留必要的中英搜索别名并去重，不打包全部语言。
4. 目录固定为 `SunSmart/CityCatalog/manifest.json`、`LICENSE.txt`、`countries/<ISO2>.json`。每个国家文件保存国家代码、城市列表和必要的行政区名称表；城市项包含稳定数字 ID、中英名称、搜索别名、行政区引用、IANA identifier、经纬度。不重复每条城市的国家名称，不在城市项重复保存 UTC offset。
5. manifest 覆盖现有全部国家；合法无城市的国家生成空列表并记录数量，缺文件／校验失败单独报错。对城市 ID 唯一性、国家归属、非空英文回退名、坐标范围、时区映射和行政区引用做生成期校验。损坏记录列入报告并在交付前处理，不静默丢弃导致宣称覆盖范围不实。
6. 预先计算同国、同展示语言重名组；重名时补州／省，仍重名时补下级行政区。行政区仍不足以区分时补城市代表点坐标，保留全部不同 ID，不因重名合并记录。消歧文案按整个国家计算，不能随搜索结果变化而时有时无。
7. 使用真实文件夹资源保留 bundle 内层级，加入全部六个品牌；验证每个产物中的 manifest、国家文件、许可和本地化。记录最终原始 JSON 大小与代表国家解析／搜索耗时；分析阶段的 35.6 MiB 不作为最终包体积承诺。

### 11.2 复用搜索控件及目录加载

- 将现有 `SiteCountryRegionField` 的 UI 部分提取为仅本创建页使用的 `SiteLocationSearchField`，Country 与 City 各持有一个实例。配置项只包括图标、标题／搜索 placeholder、行主副文本、空／加载／失败状态及回调；沿用现有查询与确认值分离的语义，不建立通用表单框架。
- 保留当前无箭头、系统 clear、204 pt 面板、开合动画、减少动态效果和已选高亮。城市右侧国家名不变；长城市／行政区与长国家名允许换行，不能相互覆盖；固定面板内部滚动。
- 新增 `CityCatalog`，只在打开 City 时后台解析当前国家、预计算搜索文本并稳定排序；缓存最近两个国家，避免一次加载全球目录。UI 展开后可显示加载态；轻量国家目录仍沿用现有加载逻辑。
- 输入匹配在后台执行，约 120 ms 合并连续输入；每次输入、换国家或关闭均更新请求代次。回到主线程时同时核对国家、query、代次、账号／服务器上下文、页面有效性和提交状态；选项点击也重新核对国家和记录 ID。取消后已完成的旧请求不能重新展开列表或改写草稿。
- 控制器统一管理当前展开字段，复用外部点击、键盘可见性和退出清理。点击输入行可进入编辑，但不得吞掉系统 clear、光标定位、列表点选与内部滚动。先关闭旧字段再打开新字段，重复失焦／关闭保持幂等。

### 11.3 草稿状态、自动填充与一次性保存

在 `SiteCreationDraft` 增加城市 ID／已选目录项、创建时的默认时区快照，以及 Time Zone、Latitude、Longitude 三项各自的值来源（默认、城市、手动）。这些来源只用于本次创建草稿，不写入持久化协议。通过明确的选择城市、选择国家、手动改时区和手动改坐标入口更新，不能用“当前值是否等于自动值”反推是否手动修改。

| 输入事件 | 草稿与界面更新 |
| --- | --- |
| 选择不同城市 | 先验证记录属于当前国家、坐标及共享时区匹配成功，再一次性写入城市、时区和两项坐标；三项来源均改为城市 |
| 重选同一城市 | 结束搜索，保持三项当前值及其来源 |
| 手动确认时区／编辑坐标 | 仅相应字段改为手动来源；仅获得焦点不算修改，手动清空坐标也算手动修改 |
| 确认不同国家 | 同步清空 City；旧城市来源的坐标清空，旧城市来源的时区恢复创建页初始快照（可能为 Unknown）；逐字段保留手动值；旧城市搜索请求失效 |
| 重选同一国家／取消搜索 | 保留城市、时区和坐标 |
| City 记录或时区资源不可用 | 不提交半个选择，保持原草稿并提示加载失败；国家／城市仍可为空，不新增创建阻断 |
| CREATE／失败重试 | 结束未确认的搜索，把确认后的国家、城市、最终时区和坐标一次性交给现有创建事务；失败保留完整草稿，成功按现有逻辑退出 |

控制器自动填写后必须同步更新两个坐标输入框、时区行和 Local time；CREATE 当前会从输入框收集文本，不能让旧 UI 文本覆盖新草稿。经纬度使用点号十进制、保留合理源精度，最终沿用已有 string/null 契约。字段归属判断基于稳定 ID，不依赖当前语言的展示名。

持久化建议定为 `extensionData.city = "geonames:<ID>"` 或 null；`countryRegion` 仍为 ISO2，`timezone` 仍在既有 Site 字段。查询文字和本地化名称不保存。复用完整 extensionData 的存储、导入导出、copy／clone、props 回读及部分字段合并，不新增数据库表、同步任务或 schemaVersion。未知城市值、旧名称字符串继续原样保留，当前实现不扩展 Edit Site 的城市编辑。

### 11.4 时区目录补齐及必要校正

自动选城与手动选择必须使用同一 `SiteTimeZoneCatalog`。因此补充现有 `all_utc_timezones.json`，而不是在城市目录旁再放一套偏移规则；延续固定偏移，不引入夏令时切换、定时更新或旧 Site 自动迁移。

本轮在原快照及拟定白名单基础上，交叉核对了 [GeoNames timeZones](https://download.geonames.org/export/dump/timeZones.txt) 和 [IANA tzdata 2026e 源文件](https://data.iana.org/time-zones/releases/tzdata2026e.tar.gz)。新增标识的拟用固定偏移如下，实施时用冻结来源与对应 Zone／Link 再验证：

| UTC offset | 新增 IANA identifier |
| --- | --- |
| -07:00 | America/Ciudad_Juarez、America/Creston |
| -05:00 | America/Atikokan、America/Cayman、America/Grand_Turk |
| -04:00 | America/Blanc-Sablon、America/Grenada、America/Guadeloupe、America/Kralendijk、America/Lower_Princes、America/Marigot、America/Montserrat、America/St_Barthelemy |
| -03:00 | America/Coyhaique |
| +01:00 | Arctic/Longyearbyen |
| +05:00 | Asia/Yekaterinburg |

另外，城市所用的既有标识中有 6 项与 GeoNames rawOffset 不一致，不能全部照抄。已读取 IANA 2026e 中 africa、asia、southamerica 的实际 Zone 定义，计划如下：

| 标识 | App 当前值 | 本次计划 | 依据与影响 |
| --- | --- | --- | --- |
| Africa/Casablanca、Africa/El_Aaiun | +01:00 | +00:00 | IANA 2026e 的 Zone 定义自 2026-09-20 后采用固定 0:00 |
| America/Asuncion | -04:00 | -03:00 | IANA Zone 自 2024-10-15 后固定 -3:00；另见 [2025a 发布说明](https://www.iana.org/time-zones/releases/2025a) |
| Asia/Almaty、Asia/Qostanay | +06:00 | +05:00 | IANA Zone 自 2024-03-01 后固定 5:00；另见 [2024a 公告](https://lists.iana.org/hyperkitty/list/tz-announce%40iana.org/thread/UXFL4DEZCXJVZW6E24Y2HLSXVB2ILFVE/) |
| Africa/Windhoek | +02:00 | 保留 +02:00 | IANA 当前基础偏移为 2:00；不采用 GeoNames 的 rawOffset 1.0 |

这是确保新增城市自动填写正确且与手动选择一致的必要资源修正。共享使用方包括 Create Site 默认时区／自动填写、Create／Edit 的手动时区列表，以及使用目录取得默认值的旧数据初始化路径；这些路径今后会读到新值和新增标识。已保存的非空 timezone 不根据目录被动改写，不发起批量同步。保持现有条目的相对顺序，新标识按 region 合理插入；Arctic 新分组以及既有目录测试的固定条目数要同步处理。

### 11.5 实施顺序、文件边界与验证

用户已确认以下实施顺序，实际结果见第 12 节：

1. **准备目录与时区**：增加数据生成／校验脚本、`CityCatalog` 资源和模型，补齐上述共享时区目录；输出清理数量、中文覆盖率、空国家、重名组、资源体积和全部城市时区可解析性报告。目录检查必须离线可复跑。
2. **实现草稿联动**：扩展 `SiteCreationDraft` 的明确状态入口，补充选择／换国家／手动覆盖／取消／失败行为测试；在接入 UI 前验证不会留下跨国家的城市或半更新值。
3. **复用并接入 UI**：提取搜索控件，Country 保持现有行为，接入 City、双字段互斥展开、后台查询和生命周期清理；补齐 English／简体中文的提示、空状态、错误、加载及可访问性文案。
4. **核对持久链路**：扩展现有创建与真实 SQLite 夹具，以城市 ID、自动和手动坐标／时区覆盖创建、重载、回滚重试、copy／clone、导出／导入、缺字段保留、显式 null、未知字符串和 Trigger Zone 更新。没有失败证据时不修改已正确的公共存储／同步代码。
5. **打包与编译**：核对实际 local workspace、SDK realpath 和状态；新增资源／共享 Swift 加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart。先完成相关回归，再串行运行六品牌 Debug / generic iOS 构建与产物资源检查；不运行 Simulator、不修改 SDK、正式远端依赖或后端。

最小自动验证集合：扩展 `scripts/check_site_creation.sh` 和 `scripts/check_site_hdb_persistence.py`，将已有但目前未被 scripts 引用的 `SiteTimeZoneCatalogTests` 接入创建页回归入口。重点新增“同国同名但不同 ID／时区”“不同国家同名不串结果”“快速 A→B→A 的旧请求晚到”“退出后加载完成”“仅手动改纬度后换国家”“自动填充后 CREATE 不被旧输入文本覆盖”“同一城市重选不覆盖手动值”等行为。包含目录加载失败、合法空列表、英文回退、缺字段与旧字符串；不以源码文本匹配代替这些行为验证。

人工最短验收：空国家点 City 提示 → 选国家并查看全部城市 → 中英搜索、clear、取消和重名选择 → 确认城市自动填写时区／坐标 → 手动修改、重选同城及改选其他城市 → 切国家检查清理／保留 → CREATE 后重启核对数据。补看小屏／iPad、长名称、键盘和列表滚动；最大国家首次加载和连续搜索需运行测量。用户负责真机和体验验收，本次不自动安装／运行。

跨端联调契约：后端／其他客户端应接受并原样保留 `city` 的命名空间 ID 字符串或 null、ISO2 国家和现有时区／坐标格式，缺字段不能当作显式清空。App 可以独立完成实现；联调与其他端支持在发布前验证，由对应团队处理其代码，不能以 App 构建或离线夹具通过替代。城市本身不新增固件命令，时区继续走现有 App 同步链路。

### 11.6 当前状态

需求和方案均已确认，实施与自动化验证已完成，未进行 Git 提交。真机 UI／性能与云端回读待人工验收，详细边界见第 12 节。

## 12. City 实施结果与验收（2026-10-23）

### 12.1 已完成内容

- Country 与 City 共用 `SiteLocationSearchField`，沿用无箭头、系统 clear、204 pt 面板、开合动画和点选确认；City 使用位置图标、`Search city`、左城市／右国家列表。未选国家时提示，不展开 City；空目录、无匹配和加载失败分别呈现。控件内的文字／clear 点击由 UITextField 处理，图标与边缘点击单独转发，避免未选国家时重复提示。
- 共享 `SiteLocationSearchState` 区分确认值与 query，以国家上下文和请求代次拒绝过期结果。城市目录按国家在后台加载，连续输入合并 120 ms，保留最近两个国家缓存；两个字段互斥展开，外部点击、失焦、后台、退出与提交使用统一收尾。
- `SiteCreationDraft` 管理城市及三项自动填充值的来源：换城市一次性更新，重选同城保留手动值；换国家清城市，逐字段保留手动值，仅清理旧城市自动值。时区自动值恢复本次创建的初始快照。输入框与草稿同步刷新，CREATE 继续使用现有原子创建路径。
- `extensionData.city` 保存 `geonames:<ID>` 或 null；本次没有修改公共数据库／云同步实现。国家与城市仍允许为空，查询文字不进入数据；未知／旧城市字符串遵循现有兼容保留规则。Edit Site 城市编辑、定位、夏令时自动切换不在本次实现范围。
- 共享时区目录新增 16 个标识、修正第 11.4 节列出的 5 个过时偏移，保留 Windhoek +02:00；新选城市与手动时区列表使用同一目录，没有自动迁移已有 Site 的非空时区。

### 12.2 最终城市资源

- 225,061 条城市记录、249 个国家文件，41,700 条有中文名，其他按已确认规则回退英文／拉丁字母名。经类别清理后，AQ、BV、HM、IO、UM 为合法空列表；这与原始快照的空集合不同，不是缺文件。
- 国家 JSON 合计 39,371,235 字节；加 manifest 和许可，共 39,406,689 字节（约 37.6 MiB，未压缩）。不是 IPA 下载增量或运行内存测量。
- 原始数据有 137 个行政区引用未在行政区名称表中找到，manifest 逐项记录；缺少该级信息时保留城市和时区，用更下级行政区／坐标处理重名，不伪造行政区名称。
- 一处人工修订保留 GeoNames 的 `Greater Napanee` 主名称，避免英文别名将它与同坐标的另一条 `Napanee` 合并成无法区分的展示；两个 ID 均保留。规则、来源与原因在 `scripts/site_city_name_overrides.json`，有针对性回归。
- `scripts/generate_site_city_catalog.py` 从指定离线源目录生成；`scripts/simplify_city_names.swift` 仅在生成阶段做简体转换。manifest 记录原始源文件、国家／时区参考表及修订表的 SHA-256，城市文件各自有字节数、记录数和 SHA-256。原始约 196 MiB 别名压缩包未加入工程；App 和构建／测试不依赖联网下载。

### 12.3 自动验证结果

- `scripts/check_site_creation.sh` 通过：既有元数据／Country／草稿检查，以及全量 249 文件完整性、225,061 个全局唯一城市 ID、全部城市时区匹配、中英搜索与回退、重音／宽字符、重名区分、非法／缺失／损坏资源、合法空列表；覆盖选城原子性、跨国拒绝、手动覆盖、重选同城、换国恢复及 nil 初始时区。
- 共享时区目录测试已接入该脚本，检查新增标识及已审核的固定偏移。真实后台 loader 夹具覆盖旧 A 请求已在执行时发生 A→B→A、旧结果晚到、关闭后回调、缓存命中／两国淘汰和加载失败。输入法组合的模型状态检查通过，不等于 UIKit 输入法实际事件顺序已验收。
- `scripts/check_site_hdb_persistence.py .local-sdk/nordic-sig-mesh-sdk` 通过：生产创建／保存／加载／copy／clone 与 extension store 在临时真实 SQLite 中运行，城市 ID、坐标和时区经重载保留，创建失败回滚及重试不丢值。元数据测试覆盖缺字段保留、显式 null、未知 ID／旧名称和 Trigger Zone 更新；SDK 网络分配由夹具替代，没有连接 Mesh 或服务器。
- 当前 Mac CLI 的美国目录加载、完整性校验及索引约 0.677 秒，四次搜索合计约 0.049 秒；这是未优化 CLI 夹具的单次记录，仅用于确认真实规模路径可执行，不代表 iPhone 主线程、列表布局或用户体验性能结论。
- workspace 为 `SunSmartLocal.xcworkspace`，SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `e7c1a7f`，工作树干净且本次未改 SDK。App 实施基线为 `feat/HDB-261020` 的 `3e95b6e0`，此前 Country 修改已包含在该基线。
- 稳定 DerivedData 使用 `SunSmart-feat-HDB-261020-Codex`。City 初版完成时，SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六品牌 **Debug / generic iOS / CODE_SIGNING_ALLOWED=NO** 串行构建全部退出 0，并逐一确认 `BUILD SUCCEEDED`。后续截图反馈修正的验证见第 12.5 节。未运行 Simulator、Release 或自动真机测试。
- 六个最终产物逐一核对：249 个城市文件、manifest、许可、国家目录、时区目录与源码哈希一致；English／简体中文的全部新增城市提示与源文案一致。核对仅针对明确的产品资源，不将 Finder 的 `.DS_Store` 元数据作为打包文件。project／strings 语法及 `git diff --check` 通过；正式依赖声明和锁文件未修改。

### 12.4 待人工验收与外部联调

最短操作：空国家点 City，应只提示先选国家 → 选 China，City 中输入 `SH`／`上海`，确认仅本国结果、clear 恢复列表、取消保留原值 → 选择 Shanghai，检查时区与坐标自动填写 → 手动修改纬度／时区，重选同城应保留 → 改选另一城市应重新填写 → 改选国家，检查城市清空、自动值清理、手动值保留 → CREATE 后重新进入／重启核对保存数据。

另检查中英文、同名城市、小屏／iPad、长名称换行、键盘与内外层滚动、快速开合、减少动态效果，以及最大国家首次加载／连续搜索的实际体验。城市代表点不等于实际 Site 坐标，可继续手动修正。关闭创建页不得落库，失败后重试应保留选择。

云端尚未联调：验证 siteAdd／siteUpload 上传后回读保留 `countryRegion`、`city`、坐标和既有 timezone，缺字段／null 按既有规则处理，并由后端／其他客户端团队确认命名空间 ID 契约。没有修改固件、服务器、运行配置或执行部署；编译和离线测试不能替代以上验收。本次没有自动安装 App，也没有 Git 提交、推送或合并。

### 12.5 Shenzhen 搜索截图反馈（2026-10-23）

用户真机截图显示两条 `Shenzhen, Guangdong,`，后续行政区文字未呈现，右侧 China 与左侧文字未垂直居中。核对内置 CN 目录及实际标题生成规则后，两条记录分别为：

| GeoNames ID | 中文名 | 完整英文选项 | 纬度／经度 |
| --- | --- | --- | --- |
| 1795565 | 深圳 | Shenzhen, Guangdong, Shenzhen | 22.54554／114.0683 |
| 1795566 | 深镇 | Shenzhen, Guangdong, Maoming Shi | 22.1823／111.11793 |

这是不同地点的同音英文名，不应按 `Shenzhen, Guangdong` 前缀去重。标题生成已提供下级行政区；这次修正聚焦呈现。共享 cell 原先将两列设为顶部对齐，已改为垂直居中；两列明确按词换行、不限行数并避免垂直压缩，使用 UILabel 的自然文本高度替代固定段落行高，保留单行最小高度与既有外边距。长城市／国家名推动行高自适应，204 pt 面板高度不变。Country 复用同一 cell，因此长国家名也适用；资源、数据 ID 和选中行为未修改。

补充真实目录回归，验证两个 ID 均能搜到，中文名、完整英文标题及坐标可区分。UIKit 绘制没有自动运行，截图所示裁切的具体系统排版路径未做运行级复现；修正后需人工再次搜索 Shenzhen，确认两条完整名称换行可见、China 在整块城市文字旁垂直居中，并检查滚动复用和长国家名。

本次修正后 `scripts/check_site_creation.sh` 全部通过，包含新增 Shenzhen 用例；SunSmart 的 Debug / generic iOS 构建退出 0，输出 `BUILD SUCCEEDED`。仅共享行布局与回归用例变化，没有资源／品牌条件差异，选代表 target 验证，未重复六品牌构建。未自动安装或运行真机，未提交 Git。

**20:15 真机复验补充**：用户第二张截图确认上述第一轮修改仅修复垂直居中，长名称依然裁切，不能视为换行验收通过。完整标题在目录测试及控制器传值中仍然存在；当前剩余问题位于 cell 排版，尚无运行时 label bounds 记录。

第二轮改为明确的宽度与高度计算：在配置 cell、测量行高和宽度变化时，先按列表可用宽度测量国家列（上限 45%），再将剩余宽度设置为城市的多行排版宽度；用两列 `sizeThatFits` 所需高度的较大值作为文字区域高度，并让两个 UILabel 填满该高度。短文本由 UILabel 自身垂直居中。复用时重新计算，空 detail 的 Country 行恢复整列宽度，204 pt 面板不变。这一改动处理标签尺寸与行高的依赖，不再仅依赖 StackView 对多行 intrinsic size 的推算。实际换行与滚动复用仍需真机确认。

第二轮 SunSmart Debug / generic iOS 构建已通过（`BUILD SUCCEEDED`），`scripts/check_site_creation.sh` 及 `git diff --check` 通过。这些检查不证明 UIKit 最终文字绘制已通过；保留“重新搜索 Shenzhen，两个完整名称均换行可见，滚动后仍正确”的人工验收项。

## 13. Site 标准属性与经纬度数值化方案（2026-10-26，已确认）

### 13.1 结论与范围

将本次创建页的地址、国家、城市、邮编和坐标改存 Site 标准字段是可行的。接口同样支持 `description`，建议此次一起迁出，避免保留一个重复定义的标准属性。用户明确不需要兼容旧 `extensionData` 中的这些字段，因此不做旧字段迁移、回退读取或双写；用户自行删除测试项目，App 不执行批量删除。

“标准字段已存在”指用户提供的服务端契约。当前 App 的 `SiteData` 和 `sites` 表还没有这些属性，需要补齐本地模型、持久化、创建、导入导出和属性回读。只修改创建页请求，会在数据库重载后丢失数据。

本次仅开发 App。新字段仍只在 Create Site 输入，Edit Site 新增表单和这些字段的增量编辑留待后续需求。本次会调整共享读取／持久化，使现有编辑、同步和克隆能保留新字段。无需修改 Mesh SDK、固件、服务器或其运行配置。

分析基线：工作树 `feat-HDB-261020`，分支 `feat/HDB-261020`，HEAD `2984cd47`；开始分析时无未提交改动。本轮仅更新本文档，没有运行 App 构建、真机或接口请求。

### 13.2 当前接口用途与完整数据链

| 操作 | 当前入口和接口 | 本次处理 |
| --- | --- | --- |
| CREATE | `SiteCreateViewController` → `SiteCreationDraft` → `SiteData.add`，先完成本地创建 | 将标准字段在第一次保存前赋值；扩展数据仅承担原有扩展职责 |
| 首次上传 | `SyncOperation.syncSite` → `siteAdd` → `/sitespace/sync/siteprops` | 新属性位于请求 `site` 对象，与 `siteName`、`timezone` 同级；坐标是 JSON number |
| 普通上传／批量新增 Space | `siteUpload` → 同一个 `/sitespace/sync/siteprops` | 复用同一 Site 导出，完整保留标准属性 |
| Site 列表、详情、分享加入 | 服务端 Site 对象 → `SiteData.import/update` | 从 Site 顶层读取并持久化新字段 |
| Edit Site 现有名称、图标、时区 | `SitePropsEditCoordinator` → `SitePropsAPIClient` → `/sitespace/update/siteprops` | 接口现在已经使用；本次不新增这些元数据的编辑控件或编辑提交入口 |
| 属性读取 | `/sitespace/retrieve/siteprops` → `SitePropsAPIClient` 和既有合并策略 | 请求并解析新字段，与其版本一起合并保存 |
| Trigger Zone 保存 | `SiteTriggerZoneCoordinator` → `/sitespace/update/siteprops` | 已在使用该接口上传 `props.extensionData`，继续保留其行为 |

因此，“后续扩展 Edit Site 才通过 update 修改这些新增字段”是对的；“当前尚未使用 update 接口”不对。创建后不需要额外追加一次 update：首次 sync 应一次提交完整标准属性。

已核对的重要依赖：

- `SpaceSyncCleanupCoordinator.prepareBatch` 在上传前重新从数据库加载 Site，标准字段必须真实落库，不能仅留在创建页或内存对象。
- `SiteData.copy()` 被克隆和调试导出复用，新增字段必须一起复制；`cloneData()` 的身份、时间戳和既有时区规则继续沿用。
- `SitePropsEditPolicy.mergeRetrieve` 会推进 `lastUpdate`，而完整 Site 导入按版本判断是否覆盖。新字段必须随属性回读一起保存，并覆盖“部分回读后再收到同版本完整对象”的补全场景，避免只推进版本而遗漏数据。
- `SiteExtensionData.metadataKeys` 目前还负责补 null 和比较规范化；`SiteExtensionState.receive` 有相应缺字段合并逻辑。迁出时需要同步移除这七项的专用处理，保留 `siteType`、Trigger Zone、未知扩展字段及原有冲突／回执逻辑。

### 13.3 字段映射与建议规则

下表的标准字段名用于 sync 请求的 `site` 对象，以及后续 update 请求的 `props` 对象。

| 创建页／原扩展字段 | 标准字段 | App 持久类型 | 规则 |
| --- | --- | --- | --- |
| `latitude` | `latitude` | `Double?` | JSON number/null，建议有效范围 -90～90 |
| `longitude` | `longitude` | `Double?` | JSON number/null，建议有效范围 -180～180 |
| `countryRegion` | `countryRegion` | `String?` | 沿用已确认国家代码，如 `CN`、`SG`，不改成本地化名称 |
| `postalCode` | `postalCode` | `String?` | 保留前导零，例如 `018983` |
| `city` | `city` | `String?` | 按用户本次调整，保存 GeoNames ID 的纯数字字符串，例如 `"795565"`，未选择为 null |
| `streetAddress` | `address` | `String?` | 按用户明确映射，仅写 `address`，不再额外写同级 `streetAddress` |
| `description` | `description` | `String?` | 建议一并迁出；App 属性可命名为 `siteDescription`，JSON 仍为 `description` |

接口示例同时列出 `address` 和 `streetAddress`，本次按用户指定采用 `address`，不从示例自行改变映射。示例中的 `type`、`imageId` 类型不用于推翻现有项目契约；现有 `site.type`、整数图标 ID、时区格式保持原规则，Standard/HDB 继续是 `extensionData.siteType`。

`city` 的本地标准属性和接口值统一使用纯数字字符串，不带 `geonames:` 前缀，也不改成 JSON number 或城市名称。当前目录的原始 `record.id` 已是整数，创建时直接转换为字符串即可；目录内部检索／选中标识可继续沿用现有格式，需要按持久值查目录时在边界转换。城市名称继续按语言显示，无需改写城市资源或兼容旧 extensionData。

经纬度建议行为：

1. 输入框和编辑中的草稿保留文本，允许输入负号、小数点等中间状态；在 CREATE 前解析为 `Double?`，落库使用可空 REAL，上传使用 number。
2. 空／全空白转换为 nil，对外发送 null；`0` 是合法数字，不等同于未配置。允许只填一项，不新增成对必填要求。
3. 非空但无法解析、非有限数值（NaN／Infinity）或越界时阻止创建，定位到对应输入框并显示国际化提示，保留草稿。不能默认为 0，也不能静默清空或钳制到边界。
4. 保留现有国家／城市切换和手动覆盖规则。切换国家清除的自动坐标在提交时成为 null；手动坐标继续保留并接受相同校验。
5. 不额外固定小数位数、不先转 Int；数值化会自然消除无意义的尾随零。城市目录本身已有 Double 坐标和范围校验，无需重新生成资源。

本方案已确认，替代早期“坐标按任意 string/null 保存且不做数值范围校验”的规则。

### 13.4 最小完整实施步骤

1. **模型与 SQLite**：在 `SiteData` 增加上述可空标准属性；在现有 `sites` 表增加可空列，并补齐 create/load/loadAll/save/copy。沿用现有保存事务和失败恢复，不新建元数据表。即使所有测试项目都删除，SQLite 表仍可能存在，因此保留必要的 add-column 结构升级；不从旧扩展 JSON 搬运任何值。
2. **创建入口**：调整草稿输出，标准属性与扩展数据分别生成；`SiteData.add` 在首次事务保存前接收标准属性。坐标校验发生在 Mesh/Site 创建之前。取消不落库，保存失败继续使用原回滚与重试路径。其他 `SiteData.add` 使用方默认获得 nil 属性。
3. **导出与导入**：在现有 Site 导出中加入顶层属性，复用到 siteAdd、siteUpload、clone 和调试导出。完整导入与属性回读共享字段转换规则，先校验再应用，避免错误响应造成部分字段更新。
4. **属性回读与合并**：扩展 retrieve 的请求字段、远端快照和现有合并／持久化流程。缺字段保留当前值，显式 null 清空对应可空字段，合法 number 包含整数和小数，拒绝把 Bool 当数字。过期响应不覆盖新值，保存失败恢复内存状态且不推进确认版本。处理部分响应与完整响应同版本时的字段补全，不整体放宽版本门禁；旧响应和仍待上传的本地修改仍受保护。
5. **减少扩展字段职责**：停止生成七项元数据、补 null 和相关专用合并处理；保留整个 `site_extensions` 表以及 HDB／Trigger Zone 状态机、未知字段保留机制。不增加旧字段回退、双写或一次性数据清理。
6. **必要回归与提示**：更新创建、国家／城市选择、SQLite、导入导出与 Site props 行为测试。若增加坐标提示，复用已有提示组件；无合适 Key 时补 English／简体中文并核对六品牌资源归属。

复用选择：现有 `SiteData`、SQLite 表、Site 导出及属性合并机制均是相关入口的共享边界，直接补齐它们即可。只在 HTTP payload 临时转换无法保证重载和复制；新增独立存储服务则会引入第二份标准属性来源，本次无此必要。

本次不提前扩展新字段的 Edit Site dirty mask／编辑 UI／增量提交功能。现有 update 修改名称、图标、时区，以及 Trigger Zone 保存，均应保留本次标准字段，不因未提供而清空它们。上传失败／取消继续依赖原有 Site 待上传状态，重试从已保存的标准属性重建相同含义的请求。

### 13.5 验证边界

优先扩展现有测试，不新增临时 Xcode 工程：

- `scripts/check_site_creation.sh`：空值、0、负值、小数、合法边界、非法文本／非有限数／越界；未配置字段允许创建；国家切换、城市自动填写及手动覆盖不退化。检查输出坐标是真正的 JSON number，扩展对象不再自动带出七项字段。
- `scripts/check_site_hdb_persistence.py`：在临时真实 SQLite 上运行生产创建／保存／加载／copy／clone；覆盖 REAL/null、邮编前导零、旧空表加列、事务失败回滚后重试、重新打开数据库仍保留属性。SDK 网络分配仍由夹具替代。
- Site props 和导入导出行为：sync 的 site 层级及 update 的 props 层级；city 以纯数字字符串往返且仍能关联目录记录；正常回读、缺字段、显式 null、坐标整数／小数、坐标 Bool／字符串错误类型、过期响应、同版本补全、保存失败；编辑既有属性或 Trigger Zone 后不丢标准属性。现有 API contract 文本检查只作为补充，不能替代行为夹具。
- `scripts/check_site_hdb_type.sh`、`scripts/check_site_trigger_zones.sh` 及直接受影响的同步准备／上传回执用例：确认清理 metadataKeys 不改变 Site Type、区域保存和回执规则；只运行与实际改动有关的回归。
- 实施完成后先核对本地 workspace 和 SDK realpath，运行 SunSmart Debug / generic iOS 构建。当前实际共享品牌还包括 HSmart，共六个 target；若新增文件／资源归属存在跨品牌编译风险，合入前覆盖全部受影响品牌，否则共享逻辑以代表 target 构建验证。

人工最短验收：创建含国家／城市／地址／描述／邮编、负数和 0 坐标的 Site → 首次同步 → 重启重载 → 修改既有 Site 名称／图标，再保存一个 Trigger Zone → 重新拉取，核对标准属性保留且坐标为 number。另验证全空元数据创建、非法坐标纠正后创建、首次上传失败后重试。由于本次不增加 Edit Site 字段展示，数据核对需结合现有 DEBUG 导出或服务端回读，不能仅凭页面存在认定持久化成功。

本轮分析未执行上述测试、构建、真机或服务器联调；前文通过结果仅属于此前实现。

### 13.6 服务端与跨端配套边界

用户已说明 update 和 sync 将支持这些字段，App 可据此实施。仍需后端团队在发布／联调时验证：

- `/sitespace/sync/siteprops` 的 `site` 和 `/sitespace/update/siteprops` 的 `props` 均接受同一字段名及 number/null 坐标；`address` 按本次街道地址映射处理。
- Site 列表、详情 `/sitespace/get/siteprops`、分享返回和 `/sitespace/retrieve/siteprops` 能返回标准属性。仅接受上传但不回传，无法满足重装／其他客户端恢复。
- 属性更新只影响请求提供的字段；只改名称／图标／时区或 extensionData 时不得清空其他标准属性。明确 null 与缺字段语义，并保证版本与回读内容一致。
- 确认 `countryRegion` 接受当前大写 ISO2，`city` 接受 GeoNames ID 的纯数字字符串（如 `"795565"`）或 null；示例中的小写国家代码和城市名称不足以证明这些取值约定。

以上属于接口契约和外部验收，相关代码／配置／部署由后端及其他客户端团队负责。本次不会修改它们，也不以 HTTP 成功、App 构建或离线测试宣称服务端已完整支持。

### 13.7 已确认的实施范围

建议按七项字段整体迁出（包含 `description`）、街道写 `address`、坐标 `Double?/number/null` 并校验范围、不兼容旧扩展数据、暂不扩展 Edit Site 新字段编辑的范围实施。

用户已调整城市取值：`city` 保存 `"795565"` 这样的 GeoNames ID 纯数字字符串，未选择为 null，不带 `geonames:` 前缀。国家继续按方案使用大写 ISO2。用户随后确认整体实施范围，包括 description 一并迁出、坐标校验和上述 city 取值约定。


## 14. 标准属性实施与验收（2026-10-26）

### 14.1 已实施

- 创建页七项元数据移到 Site 标准属性；本地 SQLite 增加可空列并执行必要的表结构升级。经纬度为 Double／JSON number，city 为如 `"795565"` 的字符串，街道写 `address`，描述写 `description`；空值保持 null，邮编保留前导零。
- 输入期间保留草稿文本，CREATE 前验证坐标可解析、有限且位于合法范围；允许空值、0、负数及单项填写。无效输入定位到对应输入框并显示中英文提示，尚未创建 Site 或 Mesh。原国家／城市选择、自动填充与手动覆盖规则保留。
- 新字段覆盖创建首次保存、数据库单条／列表加载、copy／clone、同步导出、完整导入、props 读取与现有编辑保存。新字段的 Edit Site 控件和增量写入未扩展，创建仍通过 sync 一次提交。
- 属性合并区分缺字段和显式 null。支持同版本完整响应补全；晚到响应和未完成的本地属性修改受保护。完整导入自身的资源处理可能提高 Site 时间戳，因此分别检查导入前版本与异步等待后的版本，避免自身提高版本后拒收本次属性；保存失败恢复属性与相应版本。
- 取消 extensionData 对七项字段的自动生成、补 null 和专用合并；保留 Site Type、Trigger Zone、未知字段及原有冲突处理。不读取或搬运旧扩展字段，不执行测试项目删除。
- 沿用现有文件和资源归属，没有新增 App 源文件或改写工程配置。开始实施时 `project.pbxproj` 已有 49 行增加／49 行删除，本次保留；没有修改 SDK、后端或固件，也未提交、推送或合并。

### 14.2 验证记录

已通过：

- `check_site_creation.sh`：标准属性类型／空值、坐标边界及非法输入、草稿保持、国家／城市切换、纯数字 city ID 与目录关联，以及原有目录完整性和异步搜索回归。
- `check_site_hdb_persistence.py .local-sdk/nordic-sig-mesh-sdk`：真实临时 SQLite 的旧空表加列、首次创建、失败回滚后重试、重新打开数据库、load/loadAll、copy／clone、REAL 与 null 保存；Site Type 和既有 HDB 持久化回归同时通过。
- 新增 `check_site_props.sh`：现有 props policy／API parser 测试；生产 APIClient 和 EditCoordinator 的回读、缺字段／null、非法类型、保存失败回滚、编辑期间字段保留、请求失败重试、晚到 ACK；现有 Site 进入时区 policy／coordinator 测试及元数据保留用例。
- 上述脚本还提取实际 Site 导入的标准字段预检、基础属性版本更新和保存代码，使用明确的 Mesh／Space 边界夹具覆盖同版本补全、导入自身版本增长、等待期间新版本、非法响应和保存失败。该夹具不执行完整 Mesh／Space 导入，不替代服务器或设备联调。
- `check_site_hdb_type.sh`、`check_site_trigger_zones.sh`：Site Type、创建完成入口、Trigger Zone 解析、回执、候选和拓扑相关回归通过。
- `check_site_zone_cleanup_batch.py .local-sdk/nordic-sig-mesh-sdk`：真实 SQLite 与同步准备／回读／清理入口回归通过，覆盖失败阻断导出后重试、取消、重启和并发清理归属。
- 六个 target 均包含现有 Site 共享源码及相同 English／简体中文资源；project／strings 语法检查和 `git diff --check` 通过。

独立记录的既有检查问题：

1. `check_site_sync_gateways.sh` 在首个布局用例退出：测试期望网关项最小 112 pt，现有实现为 100 pt。实现与测试文件均与 HEAD 完全相同。本次未修改布局；脚本后续用例不计为通过，相关时区测试已由 `check_site_props.sh` 单独执行。
2. `check_space_recovery_receipts.py` 的综合夹具缺少 `Node.macAddress` 与 `HDBConfigurationStore`，编译失败。改用 HEAD 版本的相关夹具和提取源码复现相同错误。本次未扩展其 HDB 测试边界，不将该综合脚本列为通过；本次 props 重试／ACK 与版本保护由针对性行为夹具验证。

本地 SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `e7c1a7f`，本次未修改。构建入口为 `SunSmartLocal.xcworkspace`，稳定 DerivedData 为 `SunSmart-feat-HDB-261020-Codex`；最终 SunSmart Debug / generic iOS / `CODE_SIGNING_ALLOWED=NO` 构建退出 0，输出 `BUILD SUCCEEDED`。本次为共享逻辑与既有共享 strings 内容修改，已核对六品牌归属，使用代表 target 构建；未运行其他品牌构建、Release、Simulator 或真机。

### 14.3 待人工与外部验收

按 13.5 的最短路径核对创建、非法坐标纠正、首次同步失败重试、重启重载，以及现有编辑／Trigger Zone 保存后字段保留。确认 sync、retrieve、详情和分享回读支持 number/null 坐标、纯数字字符串 city 与 address 映射。App 代码／隔离测试不证明后端字段保留或实际 UIKit 表现；本次未连接服务器测试，也未安装／运行真机。

### 14.4 旧同步实例覆盖标准属性修复（2026-10-26）

评审问题已用真实 SQLite 和生产 `confirmSiteUpload()` 复现：详情导入通过另一实例补充 city 等字段后，同步任务仍保存其旧 Site，导致最新元数据被覆盖。`prepareBatch()` 为导出返回新实例，并不会替换回执持有的实例。

`SiteData.save()` 现在默认保留数据库最新的七项标准属性；仅创建新记录时采用实例初值，导入和 props 接收入口则显式传入已通过版本策略的字段补丁。读取、按字段合并、写入及扩展初始化共用现有 `configurationTransaction`，失败回滚并释放保存点；成功后回填实例属性。缺字段保留数据库值，显式 null 清空，普通回执或编辑名称不会复活旧值。创建、克隆和首次导入仍可完整写入元数据。已丢失的本地字段可在服务器仍保留数据时通过正常详情／props 回读重新补全，不从旧 extensionData 猜测恢复。

本轮验证：

- 扩展 `check_site_hdb_persistence.py`，新增 `SiteStandardPropsPersistenceTests.swift`：执行生产导入的元数据／版本／保存片段、完整 EditCoordinator 和生产上传回执，覆盖分离实例、同版本导入、props 回读、Site Add／addSpaces 回执、旧编辑实例保存、缺字段／null、保存失败、重复失败后重试及重新打开数据库。同步准备的新实例交接由真实数据库 load 重放，Mesh／Space 导入和网络传输为夹具边界，未将其称为完整 App 同步验收。
- `check_site_props.sh`、`check_site_creation.sh`、`check_site_zone_cleanup_batch.py`、Site props API contract 及上述 SQLite 回归通过；`git diff --check` 通过。
- `check_space_recovery_receipts.py` 仍遇到 14.2 已记录的夹具缺少 `Node.macAddress`／`HDBConfigurationStore` 编译错误，未计为通过，未扩大到无关夹具修复。
- 使用同一 `SunSmartLocal.xcworkspace`、SDK `one-dev` revision `e7c1a7f`（干净且未修改）和稳定 DerivedData，SunSmart Debug / generic iOS / 禁用签名构建退出 0，输出 `BUILD SUCCEEDED`。本轮共享逻辑没有品牌条件分支或资源归属变化，使用代表 target；未执行真机或服务器联调。

最短人工验收：对已有城市／坐标的 Site 完成详情或 props 回读，再执行同步／重试，重启后确认字段仍一致；服务端显式清空某字段后重复同步，确认旧值不会恢复。
