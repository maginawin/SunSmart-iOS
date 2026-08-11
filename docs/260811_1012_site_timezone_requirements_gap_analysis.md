# Site Time Zone 需求完整性与开发前置分析

## 1. 结论

当前需求已经覆盖了主要 UI 页面和多数用户操作，但还不能直接进入开发。核心原因不是 UI 细节，而是服务器字段契约、时区偏移语义、旧 Site 的数据来源、失败后的持久化重试，以及 Site Time Zone 与现有 Mesh 时间同步的关系尚未闭合。

建议先确认本文第 6 节中的关键业务规则，再形成最终设计与实施计划。

## 2. 已核对的当前实现

### 2.1 Edit Site 当前入口

- Sites 列表和 Site 内页都使用通用 `InfoEditViewController` 编辑 Site。
- `InfoEditViewController` 同时服务于 Space、Scene 等其他编辑场景，直接向其中加入 Site 专属 Time Zone 会扩大回归面。
- 工程已有 `SiteEditViewController`，但当前没有业务入口，且 Done/Cancel 尚未实现；它已属于四个品牌 target，可作为 Site 专用页面重建。
- 当前标题是动态 Site name，不是固定 `Edit Site`，与本次补充要求一致。

### 2.2 当前保存和服务器同步

- 当前点击 Done 后先直接修改 `site.name`、`site.imageId` 和 `site.lastUpdate`，保存本地数据库，然后加入通用 Cloud Sync 队列。
- 当前 Site 新建和更新都通过 `/sitespace/sync/siteprops` 上传完整 Site 数据。
- 工程中尚无 `/sitespace/update/siteprops`，也没有“仅发送实际变更字段”的 Site 属性更新模型。
- 当前 `SiteData` 仅用 Site 级 `lastUpdate`、`lastUploadCloudTimestamp` 和 `syncCloudError` 表达整体同步状态，不能区分 name、icon、timezone 分别是否待同步。

### 2.3 当前服务器数据导入

- Sites 列表刷新使用 `/sitespace/get/sitelist` 返回的简要 Site 数据。
- `/sitespace/get/siteprops` 只在进入 Site 内页时请求。
- 因此用户可以从 Sites 列表直接打开 Edit Site，但此时不保证已获取服务器的 `data.timezone`。
- Site 列表和完整 Site 属性目前共用 `SiteData.update(siteJsonData:)`。如果只在 `/get/siteprops` 中保证 timezone 字段存在，就不能把“列表回复没有 timezone”错误解释为“服务器未配置”。

### 2.4 本地数据库与导入导出

- `SiteData`、SQLite sites 表、copy/clone、服务器 export/import 当前都没有 timezone。
- 现有数据库迁移模式是在启动时检查列是否存在并增列。
- `lastUpdate` 是秒级 Unix 时间戳。同一秒内连续保存时，需要避免更新时间不递增而导致待同步判断失效。

### 2.5 时区 JSON

- `all_utc_timezones.json` 当前有 397 条记录，分为 Africa、America、Asia、Atlantic、Australia、Europe、Indian、Pacific 八组。
- 文件中没有 `Etc/UTC`，需要按需求在列表最前面人工增加 UTC 组和唯一一行。
- ianaId 无重复，utcOffset 格式均为 `+HH:mm` 或 `-HH:mm`，包含半小时和 45 分钟偏移。
- 文件中的 utcOffset 是静态标准偏移，例如 `America/New_York` 为 `-05:00`、`Europe/Paris` 为 `+01:00`。它不表示夏令时期间的实时有效偏移。
- `TimeZone(identifier:)` 按 ianaId 计算 Local time 时会应用夏令时。因此列表/服务器字符串中的静态 utcOffset 与当日 Local time 的真实偏移可能不同。

### 2.6 当前设备与网关时间同步

- 现有 Timed 流程在发送 Scheduler 前发送 Time Set，时区来源仍是手机 `TimeZone.current`。
- WiFi Gateway 在 Proxy Ready 时也会自动发送一次 Time Set，时区来源仍是手机 `TimeZone.current`。
- 因此若本期只新增 Site timezone 的存储、展示和服务器同步，而不调整上述链路，Site timezone 不会改变当前 Mesh 设备或网关实际使用的时区。
- “本期不做 gateway sync”必须明确是否也表示暂不改变 Timed 和 Proxy Ready 的现有手机时区行为。

## 3. Figma 核对结果

### 3.1 与文字需求一致的部分

- Edit Site 增加 Time Zone 区块和 Local time，并在图标上方增加 `Site Icon` 标题。
- Time Zone 选择页包含搜索框、UTC 首组、Region 分组、ianaId 与 UTC offset。
- 确认弹窗、离线弹窗、Sites 页不可关闭的同步状态底部卡片、成功状态和普通 Site 更新 Toast 均存在。
- 成功状态明确展示 `Saved successfully`、`No gateways`、`No gateways configured — no sync needed.` 和底部 Done。

### 3.2 设计稿与文字需求的冲突

- 用户提供的 `399:13623` 实际是 `Local time` 文本节点，不是 `Not synced to server` 状态。通过 Figma 文件内文本检索确认，实际状态文本节点是 `399:13745`，状态容器是 `399:13740`；它位于 Time Zone 标题同行右侧、timezone 行上方，视觉区域为 138 × 20。实现时应保持该视觉布局，并为整个状态容器提供可点击区域。
- 未同步状态所在画板把图标区标题写成了 `Size Icon`，与主画板和文字需求的 `Site Icon` 不一致；实现统一使用 `Site Icon`，不采用该画板笔误。
- Figma 中 `Asia/Shanghai` 示例被配成 `UTC-08:00`，与真实时区及 JSON 的 `+08:00` 都不一致，不能把示例值当业务规则。
- 确认弹窗的 Figma 注释要求先从服务器获取 Site 时区及网关同步状态，但文字需求又明确本期不开发网关同步，并暂认所有 Site 都是 No gateways。
- Figma 的时区列表示例只展示了少数 Region，实际应以 JSON 的八个 Region 和人工 UTC 组为准。

### 3.3 新分量更新与现有整包自动同步的重叠

- 当前 `SiteData.needUploadCloud` 只比较 `lastUpdate` 和 `lastUploadCloudTimestamp`。
- 当前两个 Edit Site 入口保存 name/icon 时都会更新 `site.lastUpdate`，随后显式加入 `CloudSynchronizationManager.syncSite`；Sites 页面加载后也会自动把所有 `needUploadCloud` Site 加入整包同步。
- 因此新 Edit Site 若只把更新时间写入 `lastUpdate` 并持久化 props pending，即使不再显式调用整包同步，也可能被 Sites 页自动调用 `/sitespace/sync/siteprops`，绕过新的 `/sitespace/update/siteprops`、失败状态和字段级重试规则。
- 不能简单在本地提交时把 `lastUploadCloudTimestamp` 提前改成新值来规避，因为 Site 的 `lastUpdate` 还会因本地 Provisioner 地址和 Mesh exclusion 等非 props 数据变化而更新；提前推进上传时间可能把尚未整包上传的 Mesh 数据错误标记为已同步。
- 用户最终确认不为两条同步链路增加调度隔离：Edit Site 页面主动使用分量更新；未进入 Edit Site 而由原有 Sites/Site 页面触发同步时，继续使用整包同步。整包数据新增 timezone 后也可以同步 Site 的 name、imageId、timezone。

## 4. 需要补全的业务规则

### 4.1 服务器请求字段

文字中同时出现了 `site.timezone`、`sitem.timezone` 和 `time.timezone`。必须明确：

- `/sitespace/sync/siteprops` 新建 Site 时 timezone 的准确 JSON 层级；
- `/sitespace/update/siteprops` 的完整请求体、字段名、是否包含 `siteId`、`userId`、`updateTimestamp`；
- 分量更新 name、imageId、timezone 时字段名及数据类型；
- timezone 清空是否允许、如何表示；
- 成功回复中是否返回服务器最终 timezone 和 updateTimestamp。

### 4.2 timezone 的本地真值与 DST

已确认选择以下第 1 种语义：

1. `ianaId + JSON 静态 utcOffset` 是真值，Local time 按固定 utcOffset 计算，不应用夏令时；ianaId 只作为标题展示。
2. 不采用按 IANA 规则和日期动态计算 offset 的方案。

还需定义服务器返回格式错误、ianaId 无效、ianaId 与 offset 不匹配时的处理。推荐将无效值按“未配置”展示并记录诊断日志，不让页面崩溃。

### 4.3 旧 Site 获取 timezone 的时机

从 Sites 列表直接进入 Edit Site 时，建议先请求 `/get/siteprops`，成功后以服务器值初始化编辑草稿；失败时仍允许用本地缓存进入，但需明确是否显示加载/错误状态。

本地存在未同步 timezone 时，服务器较旧或缺失的 timezone 不应覆盖本地待同步值。列表简要回复缺少 timezone 也不能清空本地值。

### 4.4 编辑草稿与退出

建议编辑期间只修改草稿，不直接改共享 `SiteData`：

- Time Zone 选择后返回 Edit Site，只更新草稿；
- 点击 X 关闭时丢弃 name、icon、timezone 全部未提交修改；
- 点击确认弹窗的 Cancel 只关闭弹窗，保留草稿并停留 Edit Site；
- 只有离线弹窗 Got it 或正式提交动作才写本地 Site、更新 lastUpdate。

否则选择时区后点击 X 会留下未保存的 SiteData 变更，与现有编辑页行为不一致。

### 4.5 失败与重试状态

当前描述同时包含两种失败 UI：

- 已回到 Sites 页后，在 `Time zone sync status` 中显示 `Saved failed`；
- Edit Site 页显示可点击的 `Not synced to server`。

建议定义为同一份持久化 pending 状态的两个呈现：在线请求失败后保留本地修改；Sites 页先显示 Saved failed，之后重新进入 Edit Site 时显示 Not synced to server，点击它按 Done 流程重试。

为保证杀 App 后仍可重试，至少要持久化待同步字段集合，不能只保存一个内存 Bool。还要明确普通 name/icon 更新失败后是否同样保留本地修改并进入 pending 状态。

### 4.6 Done 的完整分支

还需补充：

- name、icon、timezone 都无变化时，是否直接关闭且不发请求、不显示 Toast；
- timezone 不变但 name/icon 变化，网络离线时的行为；
- timezone 变化且 name/icon 也变化，确认弹窗 Cancel 后三项是否都不保存；
- 在线检查通过但请求期间断网，是否进入 Saved failed；
- 请求失败后点击同步结果页 Done，是否仅关闭卡片并保留 pending；
- 重试成功后如何清除 Not synced 和 Sites 列表已有的云同步失败图标。

### 4.7 时区选择页细节

建议明确：

- Region 和组内排序按 JSON 原顺序，UTC 固定第一组；
- “模糊搜索”定义为 trim 后，对 region、ianaId、JSON 原始 utcOffset 做不区分大小写的包含匹配；
- 搜索结果保留原分组和原顺序，空组不展示；
- 空搜索恢复全部列表；
- 无结果时展示何种空状态；
- 当前选中项是否需要勾选或高亮；
- 搜索 `UTC+08:00` 是否应匹配原始 `+08:00`。若严格只搜 JSON 属性，则不会匹配前缀 UTC。

### 4.8 国际化

除 timezone 数据本身的 ianaId、utcOffset 和 Region 外，以下均为用户可见文案，应按工程规则提供 English 和简体中文：

- Time Zone、Local time、Site Icon、Search time zones；
- Not synced to server；
- 确认、离线、同步状态、成功/失败、No gateways、Toast 的所有文案和按钮。

需要确认 Local time 的日期字符串是固定 `yyyy-M-d h:mm:ss a` 英文 AM/PM，还是随 App 语言本地化。Figma 和文字示例当前倾向固定英文格式。

### 4.9 新建与克隆

- 普通新建 Site 默认使用手机当前 IANA 时区是明确的。
- 还需定义 Clone Site：继承原 Site timezone，还是按手机当前时区重新初始化。
- 手机当前 TimeZone identifier 不在 JSON 时，需要定义回退策略；不建议仅按相同 offset 随机选择另一个 IANA zone。

## 5. 初步技术方向

### 5.1 已确认方向：Site 专用编辑页 + 值对象 + 可持久化分量更新

- 使用现有但未启用的 `SiteEditViewController` 建立 Site 专用页面，保持 `InfoEditViewController` 的 Space/Scene 等调用不变。
- 建立独立 Site timezone 值对象，统一负责服务器字符串解析、ianaId/offset 展示、上传字符串组装、Local time 计算和相等判断。
- 使用编辑草稿比较 name、imageId、timezone 的真实变化；timezone 相等判断包含 ianaId，因此相同 offset、不同 ianaId 仍是变化。
- 为 `/update/siteprops` 建立字段级 patch，并持久化 pending 字段集合；响应成功时只清除本次请求快照中确实成功且未再次被用户改变的字段。
- 让 Sites 列表和 Site 内页两个编辑入口共用同一提交协调器和结果状态，避免两套行为漂移。

用户已确认采用此方向。其优点是边界清晰、回归面小、能满足失败重试和字段级更新。代价是要补充 Site 专属 UI、数据库迁移和同步状态模型。

### 5.2 备选方向：扩展通用 InfoEditViewController

给通用编辑页增加可选 Time Zone 配置、异步 Done 和同步状态回调。文件改动可能较少，但会把 Site 专属服务器流程塞入同时服务 Space/Scene 的通用组件，状态组合复杂，回归范围明显更大，不推荐。

### 5.3 不推荐方向：只在现有 Done 回调中直接请求

该方案可以快速完成正常在线路径，但无法可靠处理 App 重启后的 Not synced 重试、旧 Site 服务器真值、字段级 pending、请求快照竞争和现有 Cloud Sync 的并发，不满足完整需求。

## 6. 建议的确认顺序

1. 确认新建与更新接口的准确请求/回复 JSON。
2. 确认 JSON 静态 offset 与 DST 动态 offset 的真值规则。
3. 确认本期 Site timezone 是否只用于 UI/服务器，还是要改变 Timed 与 Proxy Ready 的 Time Set。
4. 确认失败后本地保留、pending 持久化和再次进入 Edit Site 的重试行为。
5. 确认旧 Site 打开 Edit 前的 `/get/siteprops` 获取策略。
6. 确认 Done、关闭、无变化、普通字段失败等边界分支。
7. 确认搜索、空结果、选中态、日期格式和 Clone Site 细节。

## 7. 2026-08-11 第一轮确认结果

### 7.1 新增分量更新 API

- 新增 `/sitespace/update/siteprops`。
- body 顶层包含 `userId`、`siteId`、`props`。
- `props` 中 `siteName`、`imageId`、`timezone` 均为可选，仅发送实际变化的字段。
- `props.updateTimestamp` 必传，延续当前 App 设计，使用秒级 Unix timestamp。
- 成功回复 `data` 返回最终 `siteName`、`imageId`、`timezone` 和 `updateTimestamp`。
- 本地更新时间建议使用单调递增规则：取当前 App 秒级 Unix timestamp；若不大于 Site 当前 `lastUpdate`，则使用 `lastUpdate + 1`，避免同一秒连续修改无法标记为新版本。

### 7.2 新增进入编辑页前的属性获取 API

- 新增 `/sitespace/retrieve/siteprops`。
- body 顶层包含 `userId`、`siteId`、`props`；需要获取的 `timezone`、`imageId`、`siteName`、`updateTimestamp` 以 null 表示。
- 成功回复位于 `data.props`。
- 进入 Edit Site 时请求该接口，并比较本地与云端 `updateTimestamp` 后决定编辑草稿的数据来源。
- 该请求允许失败；失败时不提示用户，静默使用手机本地数据进入编辑页。

### 7.3 已确认的范围与架构

- 文中 `sitem.timezone` 和 `time.timezone` 都是笔误，统一为 `site.timezone`。
- Local time 只使用 JSON 的固定 utcOffset 计算，不应用夏令时；ianaId 只作为标题展示。
- Saved failed 与 Not synced to server 使用同一份可持久化 pending 状态，App 重启后仍可重试。
- 本期不修改 Timed 和 WiFi Gateway Time Set，二者继续使用手机当前时区。
- 使用 Site 专用 `SiteEditViewController`，不向通用 `InfoEditViewController` 塞入 Site 专属流程。

### 7.4 已确认的 timezone 线上格式

- 新建同步、分量更新、retrieve 和原 `/get/siteprops` 统一使用完整格式：`ianaId (UTC±HH:mm)`，例如 `Indian/Comoro (UTC+03:00)`。
- App 从 JSON 读取 ianaId 和静态 utcOffset 后组装完整格式；服务器回复也返回同一完整格式。
- 示例中的 `Indian/China` 是笔误，正常回复应返回实际保存的有效值，例如 `Indian/Comoro (UTC+03:00)`。
- 本地解析时以完整格式为协议输入，Local time 使用其中的固定 UTC offset，不根据 IANA 规则应用夏令时。

### 7.5 已确认的 retrieve 时间戳合并规则

- 本地有 pending 时，先执行第 7.19 节的内容对账；对账未通过则本次编辑草稿使用完整本地 Site props，不以较新的云端回复覆盖本地待同步意图。
- 本地无 pending 且云端 `updateTimestamp` 大于本地：采用云端返回的有效 Site 可编辑属性并写入本地；但云端 timezone 缺失、为 null 或空字符串时，不清除本地已有 timezone。
- 本地 `updateTimestamp` 大于云端：保留本地数据和 pending，不用旧云端数据覆盖。
- 时间戳相等且本地存在 pending：本地优先，避免失败待同步数据被 retrieve 回复覆盖。
- 时间戳相等且本地没有 pending：云端优先；若内容一致则不重复写数据库。
- 云端缺少或无法解析 `updateTimestamp`：静默使用本地数据。

### 7.6 已确认的进入 Edit Site 顺序

- 用户点击 Edit Site 后，先执行 `/sitespace/retrieve/siteprops`，请求结束并完成时间戳合并后再展示 `SiteEditViewController`。
- 有网络时，在原页面展示不可操作的加载状态；请求成功则合并数据，请求失败则不提示错误并使用本地数据。
- 无网络时跳过 retrieve 请求，直接使用本地数据展示编辑页。
- 不采用“先展示编辑页、稍后用 retrieve 回复刷新”的方式，避免云端结果覆盖用户已经开始编辑的草稿。

### 7.7 已确认的仅 name/icon 变化时的离线与失败行为

- Done 后先将实际变化保存到本地，更新 `updateTimestamp`，并持久化对应 pending 字段。
- 有网络时返回 Sites 页面并调用 `/sitespace/update/siteprops`；成功 Toast 显示 `Site updated.`，失败 Toast 显示 `Failed to update site.`，失败时保留本地数据和 pending。
- 无网络时不显示 timezone 专用的 `You are offline` 弹窗；直接返回 Sites 页面，显示 `Failed to update site.`，保留本地数据和 pending，等待后续重试。
- 如果本地数据库保存失败，则停留 Edit Site，不发送服务器请求。

### 7.8 已确认的统一 pending 重试规则

- `siteName`、`imageId`、`timezone` 任一字段存在 pending 时，Edit Site 均显示 `Not synced to server`。
- 点击该提示与 Done 使用同一流程：合并历史 pending 与本次新修改，仅发送两者并集中的实际字段。
- 待发送内容包含 timezone 时，走 timezone 确认弹窗、离线弹窗和同步状态卡片流程；仅包含 name/icon 时，走普通更新与 Toast 流程。
- 成功后只清除本次请求快照中仍未再次变化的字段；请求期间产生的新修改继续保留为 pending。

### 7.9 已确认的编辑草稿与退出行为

- Edit Site 内修改 name、icon、timezone 时只更新编辑草稿，不立即修改本地 `SiteData`。
- 从 Time Zone 页面选择后返回时，只更新草稿和 Local time。
- 点击右上角关闭按钮时丢弃本次新草稿；进入页面前已持久化的 pending 保持不变。
- timezone 确认弹窗点击 Cancel 时只关闭弹窗，保留草稿并停留 Edit Site，不写本地、不发请求。
- Done 时没有新变化且没有 pending：直接关闭，不发请求、不显示 Toast。
- 没有新变化但存在 pending：按统一 pending 重试规则执行。

### 7.10 已确认的 Local time 规则

- 使用 timezone 完整字符串中的固定 `UTC±HH:mm` 计算，不调用 IANA 夏令时规则。
- 每 0.5 秒读取新的手机当前 `Date` 并重新格式化，不在上次显示值上手动加秒，避免累计误差和秒数突然 `+2`。
- 页面进入前台或重新可见时立即刷新；页面不可见、进入后台或释放时停止定时器。
- 日期格式固定为 `yyyy-M-d h:mm:ss a`，例如 `2026-8-1 6:06:20 AM`。
- `Local time` 标签支持 English 和简体中文国际化；日期中的 AM/PM 固定使用英文格式。
- timezone 未配置或解析失败时不展示 Local time。

### 7.11 已确认的 Time Zone 列表与搜索规则

- UTC 固定为第一组，仅包含 `Etc/UTC · UTC+00:00`；其余 Region 和组内 timezone 保持 JSON 原始顺序。
- 搜索词 trim 前后空格后，对 `region`、`ianaId`、原始 `utcOffset` 及展示形式 `UTC±HH:mm` 做不区分大小写的包含匹配。
- Region 命中时展示该 Region 下全部 timezone；单条属性命中时仅展示对应行。
- 搜索结果保留原分组和顺序，隐藏空分组；清空搜索词恢复完整列表。
- 无结果时展示国际化文案 `No time zones found.`。
- 当前已选 timezone 不增加额外勾选或高亮，保持 Figma 现状；点击任意行立即返回 Edit Site。

### 7.12 已确认的新建与克隆 Site 默认 timezone 规则

- 正常新建 Site 时读取手机当前时区 identifier。
- identifier 能在 `all_utc_timezones.json` 中精确命中时，使用 JSON 中对应的静态 utcOffset，保存并同步为完整格式 `ianaId (UTC±HH:mm)`。
- 手机当前时区为 UTC 时，统一保存为 `Etc/UTC (UTC+00:00)`。
- identifier 不在 JSON 中时，保留手机当前 identifier；固定 offset 使用手机当前 `secondsFromGMT` 减去当前 `daylightSavingTimeOffset` 计算，不擅自映射为另一个 IANA 时区。
- 克隆 Site 时，源 Site 已配置 timezone 则原样继承；源 Site 未配置时才使用上述手机默认规则。
- 新建和克隆仍沿用现有 `/sitespace/sync/siteprops` 整包同步流程，仅在 Site 数据中增加完整格式的 `site.timezone`，其他同步行为不变。

### 7.13 已确认的服务器 timezone 异常处理规则

- 云端 timezone 缺失、为 null 或空字符串时，不删除本地已有 timezone；本地也没有 timezone 时才按未配置展示。
- 云端 `updateTimestamp` 较新但未返回有效 timezone 时：保留本地已有 timezone；已有 timezone pending 则继续保留，没有 pending 则不因 retrieve 自动创建新的 pending。
- retrieve 本身只负责获取并合并服务器属性，不反向触发本地 timezone 上传；只有用户实际修改 timezone，或重试已有 pending 时才上传。
- 最终采用的 timezone 只要是有效非空值，就使用其中的固定 UTC offset 计算并展示 Local time。
- 云端非空 timezone 必须符合完整格式 `ianaId (UTC±HH:mm)`；ianaId 不强制存在于 JSON，但 utcOffset 必须能被合法解析。
- retrieve 返回无法解析的非空 timezone 时，将整次 retrieve 合并视为失败，静默使用本地数据，不部分应用同一回复中的其他字段。
- update 虽返回 `code = 200`，但本次实际发送的字段没有被原样返回，或回复的 `updateTimestamp` 与请求不一致时，仍视为更新失败并保留 pending。
- timezone 更新失败进入 `Saved failed` 状态；仅 name/icon 更新失败显示 `Failed to update site.`。

### 7.14 已确认的 timezone 清空范围

- 本期不提供清空 timezone 的用户入口，Time Zone 选择页不增加 `None` 或 `Not configured` 选项。
- App 不通过 `/sitespace/update/siteprops` 主动发送空 timezone。
- 旧 Site 的本地和云端都没有 timezone 时，保持未配置状态且不展示 Local time。
- Site 一旦配置 timezone，本期只能选择其他 timezone 进行替换，不能通过 UI 恢复为未配置。
- 如后续需要支持清空，应另行定义 UI 入口、空值线上协议和多端合并规则。

### 7.15 已确认的 updateTimestamp 生命周期

- 用户提交一组本地实际修改时生成一次秒级 Unix timestamp。
- 若手机当前秒级 timestamp 不大于 Site 原 `updateTimestamp`，使用原值加 1，保证版本单调递增。
- 同一个 timestamp 同时写入本地 Site、持久化 pending 快照和 `/sitespace/update/siteprops` 请求。
- 仅重试已有 pending 且没有产生新修改时，复用原 timestamp，使“服务器已成功但回复丢失”的重试具备幂等条件。
- pending 上又产生新的 name、icon 或 timezone 修改时，才生成新的递增 timestamp，并以新版本提交 pending 字段并集。

### 7.16 已确认的持久化方案

- 采用“Site 表扩展 + 字段掩码 pending”方案。
- Site 表增加 timezone、Site props pending 字段集合和 pending updateTimestamp；Site 当前 name、imageId、timezone 即待同步目标值，不建立独立 pending 数据表。
- pending 字段集合只标识 `siteName`、`imageId`、`timezone` 中哪些字段尚未同步，App 重启后仍可从 Site 表恢复并重试。
- 使用请求快照和 pending timestamp 判断成功回复能否清除对应字段；请求期间若产生更新版本，不清除新版本 pending。
- 不使用 UserDefaults 或单一内存 Bool 作为该功能的持久化真值，也不把现有整体 `syncCloudError` 当作字段级 pending 真值。

### 7.17 已确认的架构与组件边界

- 启用现有 `SiteEditViewController` 管理 Site 编辑草稿、页面交互、确认弹窗和 Local time；保留 `InfoEditViewController` 给 Space、Scene 等现有场景。
- Time Zone 选择页独立负责 JSON 加载、UTC 首组、Region 分组、搜索和选择，只把选择结果回传编辑草稿。
- Site timezone 值对象统一负责线上字符串解析与组装、固定 offset、相等判断和 Local time 计算；catalog 负责 JSON 数据和手机默认时区回退。
- Site props 提交协调器统一服务 Sites 列表与 Site 内页两个入口，处理 retrieve、时间戳合并、本地提交、pending、update 请求和请求快照清理。
- 新建和克隆继续使用整包同步；已有 Site 编辑使用分量更新；本期不修改 Timed、Gateway Time Set 或 Mesh 时区行为。
- 公共代码、资源和国际化同步覆盖 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。

### 7.18 已确认的单一版本时间与最小同步范围

- 始终只维护一个 `site.lastUpdate`；它与 retrieve、update 及原整包同步中的 `updateTimestamp` 指向同一个 Site 版本属性。
- Edit Site 提交时同步更新 `site.lastUpdate`，并把同一个值作为 `/sitespace/update/siteprops` 的 `props.updateTimestamp`。
- 不增加 `needsFullSiteSync`、第二套版本时间或两条同步链路的优先级调度。
- 仅在 Edit Site 提交流程中主动调用 `/sitespace/update/siteprops`；现有 Sites/Site 页面基于 `needUploadCloud` 触发 `/sitespace/sync/siteprops` 的流程保持不变。
- 整包同步数据增加 `site.timezone`，因此原同步链路也可以把 timezone、name 和 imageId 更新到服务器。
- 允许同一 Site 的 Edit Site 分量更新和后续原整包同步都能同步这些属性；本期目标是把行为改动集中在 Edit Site 页面，而不是重构全局云同步架构。

### 7.19 已确认的整包同步后 pending 对账

- 不修改原 `CloudSynchronizationManager` 的整包同步成功回调来清理 Site props pending。
- Edit Site 更新失败后，如果原整包同步随后上传了相同属性，本地 pending 可以暂时保留到下次进入 Edit Site。
- 下次进入 Edit Site 的 retrieve 合并阶段，若云端 `updateTimestamp` 不小于 pending timestamp，且云端返回的全部 pending 字段都与本地待同步目标值一致，则认定这些字段已由其他同步链路完成，并在展示编辑页前清除对应 pending。
- timestamp 或任一 pending 字段不满足对账条件时，继续保留 pending 和本地值，不让云端结果覆盖待同步修改。
- 该规则避免展示已经实际同步成功的 `Not synced to server`，同时保持原整包同步流程不变。

### 7.20 已确认的 Edit Site 数据流

- 进入编辑：有网络时在当前页面显示不可操作加载状态，等待 retrieve 校验、timestamp 合并和 pending 对账完成后再展示编辑页；失败静默使用本地数据。无网络时直接使用本地数据。
- 编辑过程：name、icon、timezone 只修改草稿；选择 timezone 返回后刷新草稿与 Local time；关闭页面丢弃本次草稿但保留既有 pending。
- Done：没有变化且没有 pending 时直接关闭；有实际新变化时生成单调递增的 `lastUpdate`，仅重试旧 pending 时复用 pending timestamp；请求字段为旧 pending 与本次变化的并集。
- 仅 name/icon：先原子保存本地属性、`lastUpdate` 和 pending；有网络则返回 Sites 后调用 update，并显示成功或失败 Toast；无网络返回 Sites、显示失败 Toast并保留 pending；本地保存失败则停留编辑页且不请求。
- 包含 timezone：有网络先显示确认弹窗，Cancel 只关闭弹窗，确认后保存本地与 pending、返回 Sites、展示不可关闭状态卡片并调用 update；无网络显示离线弹窗，Got it 后保存本地与 pending并返回 Sites。
- timezone update 成功时清除仍与请求快照一致的 pending、更新 `lastUploadCloudTimestamp` 并展示成功/no gateways；失败时保留 pending 和旧 `lastUploadCloudTimestamp`，展示 `Saved failed`。
- update 回复只校验本次发送字段，不用未发送字段覆盖本地；code、timestamp 或任一已发送字段不符合约定都按失败处理。
- 新建与克隆继续走包含 timezone 的整包同步；Edit Site 失败后，原 Site 页面仍可按旧逻辑触发整包同步，并在下次进入 Edit Site 时通过 retrieve 对账清理 pending。

### 7.21 已确认的 UI、异常和国际化设计

- Edit Site 内容顺序为 Name、Time Zone、Site Icon；未配置时显示 `Not configured` 且隐藏 Local time，有效值显示 ianaId、`UTC±HH:mm` 和 Local time。
- 任一 Site props pending 都在 Time Zone 标题右侧显示 `Not synced to server`；视觉遵循 Figma，实际点击区域至少 44pt，点击后执行 Done 流程。
- Local time 固定使用 `Local time · yyyy-M-d h:mm:ss a` 和英文 AM/PM；每 0.5 秒以新的当前 Date 和固定 offset 重算；页面显示/回前台立即刷新，离开/后台/释放时停止。
- Time Zone 列表保持 UTC 首组、JSON 顺序和已确认搜索规则，不增加选中勾选、清空选项或额外排序。
- retrieve 失败/无效静默使用本地；本地保存失败停留 Edit Site、显示 `Failed to update site.` 且不请求；请求中断网、超时、服务端失败或回复校验失败统一保留 pending。
- 同步状态卡片等待期间禁止通过背景、下滑或返回关闭；App 后台或终止不丢失 pending。
- 所有新增用户文案通过本地化 Key 同时提供 English 和简体中文；Region、ianaId 和 utcOffset 暂不国际化。已确认的中英文文案对照以后续最终设计文档为准。

## 8. 当前工作区说明

- `SunSmart/all_utc_timezones.json` 和 `SunSmart.xcodeproj/project.pbxproj` 已有未提交改动，本次分析未修改它们。
- JSON 已被加入四个品牌 target 的 Resources，但 project 文件同时包含 Xcode 自动产生的其他排序/注释/空路径变化。后续实施必须保留用户现有改动，并只处理与本功能有关的 project 变更。
- 本文只做静态源码和 Figma 结构化设计分析，未做接口联调、构建、真机、服务器或 Mesh 硬件验证。
