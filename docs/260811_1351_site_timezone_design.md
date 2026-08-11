# Site Time Zone 与 Edit Site 分量同步设计

## 1. 文档状态

- 日期：2026-08-11
- 状态：需求与设计已确认，可进入实施计划与开发阶段
- 适用工程：SunSmart、Archipelago、SLG Sync Plus、SylSmart
- 设计参考：One-SunSmart Figma 的 Edit Site、Time Zone、确认、离线及同步状态画板

## 2. 目标

本功能为 Site 增加固定 UTC offset 的 timezone 属性，并在 Site 专用编辑页完成展示、选择、Local time、分量更新和失败重试。

核心目标如下：

1. Site 本地模型和数据库保存 timezone。
2. Edit Site 展示 Time Zone、Local time 和 Site Icon 标题。
3. Time Zone 选择页从 all_utc_timezones.json 加载、分组和搜索数据。
4. 新建 Site 默认使用手机当前时区，克隆 Site 优先继承源 Site。
5. Edit Site 使用 retrieve 接口获取最新 Site props，使用 update 接口提交实际变化。
6. name、imageId、timezone 的未同步状态可持久化，App 重启后仍可重试。
7. 保留原 Site 整包同步流程，并在整包数据中增加 timezone。

## 3. 非目标

- 不修改 Timed 的 Time Set 行为。
- 不修改 WiFi Gateway Proxy Ready 时的 Time Set 行为。
- 不使用 IANA 夏令时规则计算 Local time。
- 不实现 Site timezone 向 gateway 或 Mesh 设备的同步。
- 不实现 gateway sync status；本期统一展示 No gateways。
- 不提供清空 timezone 的 UI 或空值上传能力。
- 不重构 CloudSynchronizationManager 的整体架构。
- 不修改 Space、Scene 等继续使用 InfoEditViewController 的业务。

## 4. 核心决策

### 4.1 单一版本时间

- site.lastUpdate 是 Site 唯一的本地版本时间。
- retrieve、update 和原整包 sync 中的 updateTimestamp 均对应 site.lastUpdate。
- Edit Site 产生实际修改时更新 site.lastUpdate。
- 不增加第二套 Site 版本时间，也不增加 needsFullSiteSync。

### 4.2 timezone 真值

- timezone 线上和本地统一使用完整格式：ianaId (UTC±HH:mm)。
- 示例：Indian/Comoro (UTC+03:00)。
- ianaId 是展示标题，不参与夏令时计算。
- UTC offset 是 Local time 的计算真值。
- 相同 offset、不同 ianaId 视为不同 timezone。

### 4.3 同步范围

- Edit Site 主动提交时使用 /sitespace/update/siteprops。
- 进入 Edit Site 前使用 /sitespace/retrieve/siteprops。
- 新建和克隆 Site 继续使用 /sitespace/sync/siteprops。
- 原 Sites/Site 页面根据 needUploadCloud 触发整包同步的行为保持不变。
- 整包同步数据增加 site.timezone，因此也能同步 name、imageId 和 timezone。

## 5. 架构与组件

### 5.1 SiteEditViewController

启用现有 SiteEditViewController，负责：

- Site 编辑草稿；
- Name、Time Zone、Site Icon UI；
- Local time 生命周期；
- Done、关闭和 Not synced to server 点击处理；
- timezone 确认弹窗和离线弹窗；
- 启动 Site props 提交流程。

页面标题继续显示当前 Site name，不采用固定 Edit Site 标题。

### 5.2 Time Zone 选择页

独立页面负责：

- 加载 timezone catalog；
- UTC 首组和 Region 分组；
- 搜索及空结果；
- 选择 timezone；
- 将结果回传 Site 编辑草稿。

选择时不直接写 SiteData 或数据库。

### 5.3 Site timezone 值对象

统一负责：

- 解析和组装完整线上字符串；
- 保存 ianaId 和固定 offset 分钟；
- 输出 ianaId、UTC±HH:mm 和完整字符串；
- timezone 相等判断；
- 根据固定 offset 计算 Local time；
- 校验云端非空 timezone。

ianaId 不要求存在于 JSON，以支持手机 identifier 不在 bundled catalog 中的情况。offset 必须符合 UTC±HH:mm，分钟范围为 00 至 59，总 offset 绝对值不超过 14 小时。

### 5.4 Timezone catalog

统一负责：

- 解析 all_utc_timezones.json 的 397 条数据；
- 在列表最前增加 UTC 组和 Etc/UTC；
- 保留 JSON Region 与组内原始顺序；
- 搜索；
- 获取新建 Site 的手机默认 timezone。

### 5.5 Site props 提交协调器

两个 Edit Site 入口共用同一协调器，负责：

- retrieve 请求和回复校验；
- timestamp 与 pending 合并；
- 编辑草稿原子提交；
- pending 字段并集；
- update 请求快照；
- update 回复校验；
- 成功后的 pending 清理；
- 旧整包同步完成后的 retrieve 对账。

协调器只服务 Site 编辑，不接管原全局整包同步调度。

## 6. 本地数据设计

### 6.1 SiteData

新增以下语义：

| 属性 | 类型语义 | 默认值 | 说明 |
|---|---|---|---|
| timezone | 可空字符串 | nil | 完整格式；nil 表示未配置；读写时把空字符串规范化为 nil |
| pendingSitePropsMask | 字段集合 | 空集合 | 标识 siteName、imageId、timezone 中尚未同步的字段 |
| pendingSitePropsTimestamp | 可空 Int64 | nil | 当前 pending 逻辑修改的 updateTimestamp |

pending mask 使用字段集合语义，至少包含 siteName、imageId、timezone 三位。Site 当前 name、imageId、timezone 就是待同步目标值，不额外保存一份 pending value。

### 6.2 数据库迁移

- Site 表增加 timezone 可空列。
- Site 表增加 pending mask，旧数据默认空集合。
- Site 表增加 pending timestamp，旧数据默认 nil。
- 迁移不为旧 Site 自动生成手机 timezone。
- 旧 Site 首次进入 Edit Site 时由 retrieve 获取服务器 timezone；请求失败则继续使用本地值。
- 数据库读取和保存必须覆盖 timezone、pending mask 与 pending timestamp。
- 同一 Site 的内存复制需要保留 timezone；克隆 Site 继承或生成 timezone，但必须把 pending mask 重置为空、pending timestamp 重置为 nil。
- timezone 进入云端 export/import 和整包同步数据；pending mask 与 pending timestamp 仅为本地状态，不上传服务器，云端导入时初始化为空。

### 6.3 持久化原则

- 新修改必须先原子写入 Site 当前值、site.lastUpdate、pending mask 和 pending timestamp，再发送网络请求。
- 本地写入失败时不发送 update。
- 请求发出前创建不可变快照，包含字段集合、字段值和 timestamp。
- App 终止后通过 Site 表恢复 pending。

## 7. Time Zone 数据与显示

### 7.1 列表

- 第一组固定为 UTC，仅一行 Etc/UTC 和 UTC+00:00。
- 其余 8 个 Region 及行顺序保持 JSON 原顺序。
- 总计 9 组、398 行。
- 每行展示 ianaId 和 UTC±HH:mm。
- Region、ianaId、offset 暂不国际化。
- 当前选中项不显示勾选或额外高亮。
- 不提供 None、Not configured 或清空选项。

### 7.2 搜索

搜索词先 trim 前后空格，再进行不区分大小写的包含匹配。

匹配属性：

- region；
- ianaId；
- JSON 原始 utcOffset；
- 展示形式 UTC±HH:mm。

Region 命中时展示该 Region 的全部行；其他属性命中时仅展示对应行。结果保持原分组和原顺序，隐藏空分组。清空搜索词恢复完整列表，无结果显示 No time zones found.。

### 7.3 Local time

- 使用 timezone 完整字符串中的固定 offset。
- 每 0.5 秒读取新的当前 Date 并重新计算，不累加上一次显示值。
- 格式固定为 Local time · yyyy-M-d h:mm:ss a。
- AM/PM 固定为英文。
- 页面显示或回到前台时立即刷新。
- 页面不可见、进入后台或释放时停止定时器。
- timezone 未配置或无法解析时不显示 Local time。

## 8. 新建与克隆 Site

### 8.1 正常新建

1. 读取手机当前 TimeZone identifier。
2. identifier 在 JSON 中精确命中时，使用 JSON 静态 offset。
3. 手机时区为 UTC 时，统一使用 Etc/UTC (UTC+00:00)。
4. identifier 不在 JSON 时，保留手机 identifier。
5. 非 JSON identifier 的固定 offset 使用当前 secondsFromGMT 减去当前 daylightSavingTimeOffset。
6. 新 Site 整包同步时增加完整 site.timezone，其他流程不变。

### 8.2 克隆

- 源 Site 已配置 timezone：原样继承。
- 源 Site 未配置 timezone：使用正常新建规则。
- 克隆仍走原整包同步流程。

## 9. API 契约

### 9.1 Retrieve Site Props

路径：/sitespace/retrieve/siteprops

请求字段：

| 层级 | 字段 | 值 |
|---|---|---|
| 根 | userId | 当前用户 ID |
| 根 | siteId | 当前 Site ID |
| props | timezone | null |
| props | imageId | null |
| props | siteName | null |
| props | updateTimestamp | null |

成功回复位于 data.props，包含 timezone、imageId、siteName、updateTimestamp。

retrieve 允许失败。网络失败、code 非成功、数据缺失或非空 timezone 无法解析时，整次 retrieve 合并作废，静默使用本地数据。

### 9.2 Update Site Props

路径：/sitespace/update/siteprops

请求根字段为 userId、siteId、props。

props 字段：

| 字段 | 必传 | 说明 |
|---|---|---|
| siteName | 否 | 实际变化或历史 pending 中包含时发送 |
| imageId | 否 | 实际变化或历史 pending 中包含时发送 |
| timezone | 否 | 实际变化或历史 pending 中包含时发送；只能发送完整非空格式 |
| updateTimestamp | 是 | 与当前逻辑修改对应的 site.lastUpdate |

成功回复 data 返回服务器最终 siteName、imageId、timezone 和 updateTimestamp。

成功判定：

- code 为 200；
- 回复 updateTimestamp 与请求完全一致；
- 本次发送的每个字段都在回复中原样返回；
- 非空 timezone 能被值对象解析。

未发送字段不通过 update 回复覆盖本地。任一成功条件不满足时，按 update 失败处理。

### 9.3 原 Get 与 Sync

- /sitespace/get/siteprops 的 data.timezone 使用同一完整格式。
- 缺失、null 或空 timezone 不删除本地已有 timezone。
- /sitespace/sync/siteprops 的 Site 数据增加完整 site.timezone。
- 原整包同步的其他字段、触发入口和流程保持不变。

## 10. timestamp 与 pending 规则

### 10.1 timestamp 生成

- 一次逻辑提交生成一个秒级 Unix timestamp。
- 新值取手机当前秒级 timestamp；若不大于 site.lastUpdate，则使用 site.lastUpdate 加 1。
- 同一值写入 site.lastUpdate、pending timestamp 和 update 请求。
- 纯重试且没有新修改时复用 pending timestamp。
- pending 上产生新修改时生成新 timestamp，并让字段并集共享新版本。

### 10.2 retrieve 合并

先验证回复，再执行以下规则：

1. 本地存在 pending，且云端 timestamp 不小于 pending timestamp，所有 pending 字段与本地目标值一致：清除已匹配 pending，再按无 pending 规则继续合并。
2. 本地仍存在 pending：本次编辑草稿使用完整本地 Site props，不把同一云端回复中的非 pending 字段混入草稿；本地待同步意图不被不同的云端值覆盖。
3. 无 pending 且云端 timestamp 大于本地：采用云端有效属性。
4. 无 pending 且本地 timestamp 大于云端：保留本地。
5. 无 pending 且 timestamp 相等：云端优先；内容相同则不重复写数据库。
6. 云端缺少或无法解析 updateTimestamp：使用本地。

timezone 有额外例外：

- 云端 timezone 缺失、null 或空字符串时，不清除本地已有 timezone。
- 本地也没有 timezone 时才显示未配置。
- retrieve 不因云端缺少 timezone 自动创建 pending。

### 10.3 pending 清理

update 成功后只清理请求快照中仍未再次变化的字段。若当前 pending timestamp 或字段值已经不同，说明请求期间产生了新版本，对应 pending 必须保留。

Edit Site update 失败后，原整包同步可能上传相同属性。下次进入 Edit Site 时，retrieve 若满足 timestamp 与字段内容对账条件，则清理已经由整包同步完成的 pending；不修改 CloudSynchronizationManager 的成功回调。

## 11. 进入 Edit Site

Sites 列表和 Site 内页两个入口执行同一流程：

1. 用户点击 Edit Site。
2. 有网络时在原页面显示不可操作加载状态。
3. 请求 retrieve。
4. 校验回复并完成 timestamp、timezone 和 pending 合并。
5. retrieve 失败时静默回退本地数据。
6. 无网络时跳过 retrieve。
7. 合并完成后创建编辑草稿并展示 SiteEditViewController。

禁止先展示编辑器再异步覆盖草稿。

## 12. 编辑草稿与退出

- Name、icon、timezone 只修改草稿。
- 选择 timezone 返回后只更新草稿和 Local time。
- 点击关闭按钮丢弃本次草稿，保留进入前已有 pending。
- timezone 确认弹窗 Cancel 只关闭弹窗，保留草稿并停留编辑页。
- 没有新变化且没有 pending 时，Done 直接关闭，不请求、不显示 Toast。
- 没有新变化但存在 pending 时，Done 或 Not synced to server 执行重试。

## 13. Done 与同步流程

### 13.1 字段集合

待发送字段等于历史 pending 与本次实际变化的并集。只要集合包含 timezone，就进入 timezone 专用确认、离线和状态卡片流程；仅包含 name/icon 时进入普通 Toast 流程。

### 13.2 仅 name/icon

1. 原子保存本地值、lastUpdate 和 pending。
2. 保存失败：停留 Edit Site，显示 Failed to update site.，不发请求。
3. 有网络：返回 Sites，调用 update。
4. update 成功：清理快照对应 pending，更新 lastUploadCloudTimestamp，显示 Site updated.。
5. update 失败：保留 pending 和旧 lastUploadCloudTimestamp，显示 Failed to update site.。
6. 无网络：返回 Sites，显示 Failed to update site.，保留 pending。

### 13.3 包含 timezone 且在线

1. Done 显示 Update Site time zone?。
2. Cancel 只关闭弹窗。
3. Update Time Zone 后原子保存本地值、lastUpdate 和 pending。
4. 返回 Sites 并显示 Time zone sync status。
5. 等待期间卡片不可通过背景、下滑或返回关闭。
6. 调用 update。
7. 成功时显示 Saved successfully、No gateways 和 No gateways configured — no sync needed.。
8. 失败时标题改为 Saved failed。
9. 最终点击 Done 关闭卡片。

### 13.4 包含 timezone 且离线

1. Done 显示 You are offline。
2. 点击 Got it 后保存本地值、lastUpdate 和 pending。
3. 更新本地 Site 的更新时间。
4. 返回 Sites，不发送 update。

## 14. Not synced to server

- siteName、imageId、timezone 任一字段 pending 时显示。
- 位于 Time Zone 标题同行右侧。
- Figma 实际文本节点为 399:13745，状态容器为 399:13740。
- 视觉容器约为 138 × 20，实际触控区域至少 44pt 高。
- 点击执行与 Done 完全相同的字段合并、确认和提交流程。
- App 重启后仍按数据库 pending 恢复。

## 15. UI 与国际化

### 15.1 Edit Site

- 标题：当前 Site name。
- 内容顺序：Name、Time Zone、Site Icon。
- 未配置 timezone：显示 Not configured，不显示 Local time。
- 已配置 timezone：左侧 ianaId，右侧 UTC±HH:mm，下方 Local time。

### 15.2 文案

| English | 简体中文 |
|---|---|
| Time Zone | 时区 |
| Local time | 本地时间 |
| Site Icon | 场所图标 |
| Not configured | 未配置 |
| Search time zones | 搜索时区 |
| No time zones found. | 未找到时区。 |
| Not synced to server | 未同步至服务器 |
| Update Site time zone? | 更新场所时区？ |
| CANCEL | 取消 |
| UPDATE TIME ZONE | 更新时区 |
| You are offline | 当前处于离线状态 |
| Got it | 知道了 |
| Time zone sync status | 时区同步状态 |
| Saved successfully | 保存成功 |
| Saved failed | 保存失败 |
| No gateways | 无网关 |
| No gateways configured — no sync needed. | 未配置网关，无需同步。 |
| DONE | 完成 |
| Site updated. | 场所已更新。 |
| Failed to update site. | 场所更新失败。 |

所有用户可见文案使用本地化 Key，并同时加入 English 和简体中文资源。

## 16. 异常处理

- retrieve 网络失败、超时、code 错误、数据缺失或非空 timezone 无效：静默使用本地数据。
- 本地数据库保存失败：停留 Edit Site，显示失败 Toast，不发送 update。
- update 请求开始后断网、超时、code 错误或回复不符合契约：保留 pending，按对应 UI 展示失败。
- timezone 无效时不展示 Local time，也不发送无效 timezone。
- 同步状态卡片等待期间不可关闭。
- App 进入后台或被终止时，已落库 pending 不丢失。
- 返回前台后 Edit Site 立即刷新 Local time。

## 17. 测试设计

### 17.1 单元测试

- 完整 timezone、UTC、半小时和四十五分钟 offset 的解析与组装。
- 空值、缺失、格式错误、分钟错误和超范围 offset。
- 相同 offset、不同 ianaId 的差异判断。
- 固定 offset Local time，不受夏令时影响。
- 日期跨日、跨年和正负 offset。
- catalog 397 条数据、UTC 注入、9 个分组和 398 行。
- 搜索 trim、大小写、Region 整组命中、ianaId、原始 offset、显示 offset 和无结果。
- timestamp 单调递增、纯重试复用、新修改升级版本。
- retrieve 的 timestamp、pending 和空 timezone 合并矩阵。
- pending 字段并集、请求快照清理、失败保留和重启恢复。

### 17.2 数据与接口测试

- 旧数据库迁移后原 Site、Space、Scene 数据完整。
- Site 保存、读取、copy、clone、export、import 保留 timezone。
- retrieve 和 update 请求字段、可选字段与回复校验。
- 整包 sync 增加 timezone，其他字段不变。
- code 200 但 timestamp 或已发送字段不匹配时按失败处理。

### 17.3 UI 验收

- 两个 Edit Site 入口行为一致。
- 未配置、已配置、pending、离线、保存中、成功和失败状态符合 Figma。
- 搜索、选择、返回、关闭、Cancel、Got it、Done 全部分支正确。
- Local time 连续更新，无累计误差或明显加 2 秒跳变。
- 等待状态卡片无法关闭。
- English 和简体中文无遗漏、截断和错位。
- 四个品牌 target 的页面、资源和本地化一致。

### 17.4 回归

- InfoEditViewController 的 Space、Scene 等业务保持不变。
- Timed 和 WiFi Gateway Time Set 继续使用手机时区。
- 原 Sites/Site 页面整包同步继续工作。
- 新建和克隆 Site 的整包同步包含 timezone。
- Edit Site update 失败后，整包同步及下次 retrieve pending 对账有效。

## 18. 验证边界

- 静态测试和 xcodebuild 只能证明代码、迁移和 target 编译通过。
- retrieve/update 的真实成功、超时、错误回复和多端 timestamp 合并需要测试服务器联调。
- Local time、前后台定时器和弹窗交互需要真机验收。
- 本期不以 Mesh 设备或 gateway 时区变化作为验收条件。

## 19. 实施约束

- 保留当前工作区已有的 project.pbxproj 和 all_utc_timezones.json 改动。
- 不格式化无关文件，不重构无关同步模块。
- 不新增 Auth 信息。
- 修改公共代码、资源和国际化时同步检查四个品牌 target。
- iOS 构建使用直接 xcodebuild、generic iPhoneOS 和 CODE_SIGNING_ALLOWED=NO。
- 未经用户明确要求不 commit、push 或 merge。

## 20. Figma 节点与已知设计笔误

| 场景 | 节点 |
|---|---|
| Edit Site | 399:13589 |
| Time Zone 选择页 | 399:10399 |
| 搜索结果 | 399:10569 |
| Update Site time zone? | 399:12471 |
| You are offline | 399:12479 |
| Time zone sync status 等待态 | 399:12059 |
| Saved successfully | 420:11912 |
| Site updated. Toast | 399:12125 |
| Not synced to server 文本 | 399:13745 |
| Not synced to server 状态容器 | 399:13740 |

实现时遵循以下修正：

- 用户最初提供的 399:13623 是 Local time 文本，不是 Not synced to server。
- Figma 中 Asia/Shanghai 与 UTC-08:00 的组合错误；offset 以 JSON 和完整 timezone 字符串为准。
- 未同步状态画板中的 Size Icon 是笔误，统一实现为 Site Icon。
- Figma 的 gateway 注释不纳入本期范围，成功状态统一按 No gateways 展示。
