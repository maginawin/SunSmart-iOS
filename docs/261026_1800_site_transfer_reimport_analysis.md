# Site 往返转移后导入及再次转移异常分析

日期：2026-10-26。下文现场分析对应修复前 HEAD `6c6dbd5d`；首次分析未修改业务代码、手机数据或服务端。后续按用户授权实施的经纬度格式兼容及验证结果见文末。

## 结论

本次是三个环节叠加：**旧的本地 Owner 状态把第一次导入错误地导向详情页；接收转移成功后的响应被经纬度类型校验拒绝；本地失败后仍允许重发已经成功的接收请求，最终得到资源不存在。**

核心兼容缺陷已用日志原始响应和当前生产解析代码复现：服务器返回字符串形式的经纬度，`SiteStandardProperties.Patch` 只接受 JSON 数字。该校验会在任何 Site 元数据、权限及恢复状态更新之前退出。

手机 A 的项目和 Mesh 数据仍存在，Site 停留在 `permission=owner / state=waitDeleted`，界面因此拒绝进入。**现有材料不能证明服务器最终没有 Owner，也不能证明 A 在接收成功之后仍被服务器拒绝访问。** 日志中的 `4010` 发生在真正接收转移之前；接收成功后没有 A/B 的权限读取证据。B 失去访问权符合转出后的正常表现，但缺少 B 日志来独立确认。

## 对象与证据

- 日志：`/Users/maginawin/Desktop/transfer and reimport error logs.txt`。
- 容器：`/Users/maginawin/Desktop/com.azoula.sunsmart.hsmart`，对应 A；用户标识前缀 `0AE5F478`，日志用户名 `iPhone XS_5431`。
- B：分享信息中的 Owner 用户标识前缀 `6e7902ca`，用户名 `one`。
- 本次 Site：`E20DBA25-5610-4C90-9727-B545770F70F2`，名称“项目 4”。容器中另有同名历史项目，分析按 UUID 区分。
- 当前源码：分支 `feat/HDB-261020`，HEAD `6c6dbd5d6d01d88b80fa4af67b3ac3d665abe96b`。未取得手机安装包与该 revision 的构建绑定信息；源码行为、日志路径和容器结果一致。
- 时间采用 HTTP 缓存响应头 `Date` 换算为 UTC+08:00；缓存数据库行的 `time_stamp` 未作为本次响应时间使用。

## 实际发生顺序

| 阶段 | 直接证据 | App 行为与结果 |
| --- | --- | --- |
| A 发起转出，17:47:22 | 日志 4–24 行，`/site/ownertrans` 成功，Owner 为 A | 创建转移记录。日志没有 B 的接收过程 |
| A 第一次扫描返回的转移码 | 日志 38–60 行，`/share/info` 成功，Owner 已是 B，`type=ownertrans`、`status=A` | 服务端分享信息已表明当前 Owner 不是 A |
| 首次“导入”实际进入详情 | 日志 64–85 行，只发送 `/get/siteprops`，未发送 `/share/receive`；返回 HTTP 500、业务码 `4010 Role Not Found` | 显示“无权限”，将本地 Site 标为 `waitDeleted`，随后返回并刷新列表 |
| 自动刷新列表，17:48:00 | 日志 89–120 行；容器缓存 entry 3 补齐被日志截断的响应 | 目标 Site 不在 `sites` 中；`events` 含该 Site 转给 B 的 `OwnerTransfer`；弹出已转移提示 |
| A 第二次扫描，17:48:06 | 日志 126–151 行，分享仍有效，Owner 仍是 B | 这次本地 Site 已非 `normal`，进入 `SharePermissionSelectionController` |
| 输入密码后真正接收，17:48:09 | 日志 191–213 行，`/share/receive` 返回 HTTP/业务码 200；缓存 entry 18 保存完整响应 | 服务器确认成功；App 随后尝试本地导入 |
| 成功响应在本地被拒绝 | 响应的 `latitude` 为字符串 `"22.545540"`，`longitude` 为字符串 `"114.068300"`；生产解析器实测抛出 `invalidField("latitude")` | `SiteData.import` 无法完成，接收页显示配置保存失败并停留；本地 `waitDeleted` 未恢复 |
| 再次点击接收 | 日志 215–238 行，向相同接口发送相同转移凭据；返回 `4004 Resource Not Found` | 显示“资源未找到”。符合转移记录已在前一次成功接收时消耗的表现 |

最后一项确认了“成功后重试资源不存在”，没有服务器内部记录，不能进一步断言具体是删除、状态过滤还是其他失效实现。

## 原因与源码依据

### 1. 第一次导入错误地相信本地 Owner 缓存

`SitesViewController.loadShareInfoRequest` 的 `.site` 分支只匹配 `allSites` 中相同 ID、`permission == .owner` 且 `state == .normal` 的项目，就直接打开详情并返回。该分支丢弃了分享数据携带的 Owner，没有比较 B 与当前用户 A。

而 `ReceivingType.init(shareData:)` 已经读取 `owner.userId`，也已经将返回的临时 Site 标为非当前用户所有。因此所需信息已在 App 内，问题是后续路由没有使用它。

“尚未刷新 Sites 列表”是第一次错误的触发条件。详情的无权限处理将项目设为 `waitDeleted`，并在 1.5 秒后通知列表刷新，解释了为什么第二次扫描会走另一条流程。该错误没有消费返回的转移任务，因为第一次根本没有调用接收接口。

相关源码：[SitesViewController.swift](../SunSmart/Main/Site/Controller/SitesViewController.swift)、[SharePermissionSelectionController.swift](../SunSmart/Main/Share/Controller/SharePermissionSelectionController.swift)、[SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift)。

### 2. 接收成功响应与新增属性解析契约不一致

`SharePermissionSelectionController.receiveSiteRequest` 将响应中的 `site`、`provisioner`、`exclusions` 合并后交给 `SiteData.import`。网络层只解析 JSON，没有将经纬度字符串转换为数字。

`SiteData.update` 一开始执行 `SiteStandardProperties.Patch(siteJsonData)`。其经纬度校验要求值能转为 `NSNumber`，并拒绝布尔值、非有限数及越界数；当前实现也拒绝合法十进制数字字符串。服务器本次确实返回字符串，所以导入在创建 `SiteImportTrace` 和持久化之前失败。这与日志没有目标 Site 的导入阶段记录、数据库仍保留旧状态相符。

该前置校验及 `SiteStandardProperties` 在当前分支提交 `6c6dbd5d`（2026-10-26，`feat: update site API and site props`）中引入。历史代码没有这一整包拒绝条件。现有 `SiteStandardPropsIntegrationTests` 还将字符串 `"80"` 作为非法经度夹具，说明测试契约没有覆盖现场接口实际返回的兼容格式。

成功接收响应没有 `role` 字段。当前接收流程原本在导入成功后显式设置 `site.permission = .owner`；本次未执行到该位置。缺少 `role` 不能解释已复现的经纬度解析失败，也不能据此判断服务器没有给 A 分配 Owner。

相关源码：[SitePropsEditPolicy.swift](../SunSmart/Main/Site/Model/SitePropsEditPolicy.swift)、[ImportData.swift](../SunSmart/Common/Data/ImportData.swift)、[NetworkRequest.swift](../SunSmart/Common/Network/NetworkRequest.swift)。

### 3. 接收已经成功与本地恢复失败没有分开处理

`receiveSiteRequest` 只有在导入及 `site.save()` 都成功之后，才恢复 `normal / owner`、安排同步、通知列表刷新并退出接收页。任何导入失败统一映射为：

> 无法在此手机保存配置，之前保存的数据已保留。请重试恢复。

因此这次“保存失败”不是磁盘写入失败的证据；确定的失败发生在字段解析。失败分支没有保存“服务器接收已成功、待完成本地恢复”的独立结果，也没有转为读取已接收 Site 的恢复流程。用户重试仍发送原来的接收操作，于是得到 `4004`。

这里需要区分三个状态：服务器是否已完成接收、本地数据是否成功导入、页面是否能进入。当前流程将后两项失败表现为整体接收失败。

## 容器中的最终状态

以只读 SQLite 连接查询，未改写原容器。

| 项目 | 结果 | 含义 |
| --- | --- | --- |
| `sites` 目标记录 | `permission=1`、`state=2` | 对应 `owner + waitDeleted`，不是本地角色被清空 |
| Site 创建/更新/上传时间 | 17:47:01 / 17:47:03 / 17:47:03 | 未完成接收后的状态恢复 |
| 子空间 | “空间 1”，`1F84E19B-E62E-400A-B419-FB7A9E70F08C`，Owner、normal | 子空间记录仍在 |
| Mesh | 目标网络、主/子网密钥、手机 Provisioner 节点仍在 | 未发现本次把网络数据删除的证据 |
| 主密钥对照 | 接收响应与容器主 NetKey/AppKey 的材料、索引、绑定等一致 | 排除响应主密钥与持久化主密钥不同这一候选原因；未输出密钥 |
| Space Membership | `joined`、`initialized=true` | 没有目标 Space 正处于退出流程的持久证据 |
| Space Recovery | `active`、`writable`，存在完整导出备份 | 不是等待冲突恢复状态导致的这次拒绝 |
| 两个业务数据库完整性 | `PRAGMA quick_check` 均为 `ok` | 未发现结构损坏；不等于验证了所有运行时写入条件 |

`SitesViewController` 对 Owner 且 `waitDeleted` 的 Site 显示已转移样式，点击时提示“已转移”并直接返回。因此，即使服务器已经把 Owner 还给 A，当前本地状态也足以造成 A 无法进入项目。

## 影响范围与验证

不仅影响转移接收：同一个 `SiteData.update` 被 Sites 列表导入、Site 详情、分享权限页使用；Site 属性读取/更新也直接复用 `SiteStandardProperties.Patch`。字符串坐标会在相关响应中触发同类拒绝，具体表现取决于调用方是否检查失败结果。代码属于品牌共享代码；现场证据仅来自 H-Smart。

容器缓存的 17:48:00 列表实际含 6 个 Site。用当前生产解析器逐条验证：5 个带字符串经纬度的 Site 全部失败，只有 `ADD398DB...`“项目 2”的经纬度为 `null`，能够通过。与日志只出现“项目 2”的 Site 导入阶段记录吻合。所以不能把“刷新列表”当作已经验证可行的恢复办法。

本轮在临时目录编译了直接调用生产 `SiteStandardProperties.Patch` 的 Swift 诊断程序，结果如下；临时文件已自动移除：

| 输入 | 结果 |
| --- | --- |
| 日志中真实接收响应 | 拒绝 `invalidField("latitude")` |
| 仅把纬度转换成 JSON 数字 | 拒绝 `invalidField("longitude")` |
| 同时把经纬度转换成 JSON 数字 | 属性解析通过 |
| 经纬度为 `null` | 属性解析通过 |
| 经纬度缺字段 | 属性解析通过 |

这是解析阻断的运行证据，不是完整 App 导入、真实设备或云端恢复验收。没有修改业务代码，没有构建 App，没有自动操作真机或请求线上转移接口。

## 后续修复与恢复边界

必要的 App 修复应覆盖以下三点，不应仅在接收页面跳过属性校验：

1. 分享导入路由以当前分享信息的 Owner 为依据，避免本地旧 Owner 状态绕过真正的接收流程；保留扫描自己尚未转出的项目直接进入的合法行为。
2. 在共享 Site 属性解析入口兼容已证实的合法数字字符串，继续拒绝布尔、空白/非数字、非有限和越界值，保留缺字段与 `null` 的语义；不放宽 Mesh 身份、权限与完整性校验。同步调整测试契约，覆盖列表、详情、转移接收和属性 API 的实际格式。
3. 接收返回成功后，将本地导入失败作为待恢复处理，记录必要的接收完成状态并通过已授权 Site 的读取重试导入；重进或重启也能继续，不重复消费转移凭据。区分格式解析失败和存储失败。对失败/超时、迟到响应和再次点击保持同一结果，不能仅凭本地 Owner 缓存强行解锁。

存量恢复的最短核对方式：在修复后的兼容解析基础上，读取本次 Site 对 A 的当前 `/get/siteprops` 或 `/get/sitelist` 权限。如果 A 已是 Owner，应恢复既有 Site/Mesh 并完成后续地址同步；若服务器仍返回 `4010`，才需要后端核对转移成功后的角色写入。现阶段保留容器与备份，不通过清空缓存、修改本地 `state` 或重建 Site 代替权限核对。

后端团队只需协助只读核对：以目标 Site UUID、17:48:09 的接收成功请求和 A/B 用户标识定位记录，确认任务最终状态、当前 Owner，以及 A/B 的 Site 权限读取结果。若确有“任务消耗但无新 Owner”，由后端负责原子性和数据修复；本轮证据尚未确认该服务端缺陷，也没有执行后端修改。App 的上述三项修复可以独立推进。

验收应覆盖未刷新列表的 A→B→A、预先刷新的同一路径、合法字符串/数字/null/缺字段坐标、接收成功后本地失败再重试/重启，以及转回时原网络和子空间数据保留。最终需分别确认 A 获得访问权、B 已转出、转移不被重复提交。

## 2026-10-26 经纬度兼容实施结果

按用户后续授权，仅完成上述第 2 项：共享 `SiteStandardProperties.Patch` 接受 JSON number 或可转换的数字字符串，经范围及有限性校验后统一保存为 `Double`；字符串两端空白会被去除。缺字段保留原值，`null` 清空；空字符串、布尔值、非数字、非有限数和越界值仍被拒绝。导出及上传继续使用 JSON number。

- `scripts/check_site_props.sh` 通过：覆盖现场字符串、数字及混合格式、范围端点、非法输入、空值、属性读取、保存失败回滚和重试。
- `scripts/check_site_hdb_persistence.py` 通过：真实 SQLite 上执行生产 Site 元数据导入及保存逻辑，重新打开数据库后坐标为数值，再次 JSON 导出仍为 number；已有读回、回执和失败恢复回归通过。Mesh、网络传输仍为测试边界。
- `SunSmartLocal.xcworkspace` / `HSmart` / Debug / generic iOS / `CODE_SIGNING_ALLOWED=NO` 构建通过。SDK 来自 `.local-sdk` 映射的 `one-dev`，revision `e7c1a7f`，没有修改 SDK。共享解析没有品牌条件分支，本次选现场对应的 HSmart 作为代表构建。
- 原转移入口的旧 Owner 缓存判断，以及服务器接收成功后本地失败的恢复流程未在本次授权范围内修改，不能将坐标兼容通过表述为完整转移流程已修复。
- 未自动安装或运行真机、未操作线上转移任务。人工验收：使用新构建刷新 Sites 并导入带经纬度的 Site，确认不再因坐标格式报保存失败；现有“项目 4”的服务器 Owner 状态及恢复仍按上一节核对。

## 2026-10-26 追加：接收成功后再次转移提示资源未找到

本节依据用户新提供的聊天日志，目标为“项目 5” `533B2134-DF33-45F2-94C3-30B3FEBCB495`；不将之前导出的“项目 4”容器当作这个新项目的设备快照。为避免记录可用于访问的凭据，将 A 首次创建的转移码记为 `T_A`，B 转回时的码记为 `T_B`。

### 已确认的原因

**再次转移查询了上一轮已经失效的 `T_A`。App 没有清理旧码，也没有在旧任务不存在时创建新转移任务。** 当前错误不是经纬度导入失败，也没有证据表明本次 Site 本身被删除或 A 再次失去读取权限。

| 日志任务 | 请求及结果 | 结论 |
| --- | --- | --- |
| task 9 | A 调用 `/site/ownertrans`，成功得到 `T_A` | 第一轮转移记录创建成功 |
| task 10 / 13 | A 查询 `T_B`，返回 Owner 为 B、同一 Site | B 已发起转回；此时 `T_A` 与 `T_B` 是不同的转移记录 |
| task 11 / 12 | 第一次扫描仍被本地 Owner 缓存导入详情，出现 `4010`，随后刷新 | 前文的导入路由缺陷仍存在，但不是后续 `4004` 的请求对象 |
| task 14 | A 使用 `T_B` 接收成功，随后目标 Site 完成导入阶段 | 坐标字符串已不再阻断这次接收 |
| task 15 / 16 | 接收后的 Site 上传成功，随后列表成功导入目标 Site | 接收后续流程已执行 |
| task 17 / 20 / 21 | A 读取同一 Site 详情成功，继续导入 Space 数据 | Site 仍存在，A 能读取该 Site |
| task 18 / 19 / 22 | 点击“转移”实际发送 `/share/info`，参数始终是旧 `T_A`，均返回 `4004 Resource Not Found` | 失败对象是旧转移记录；这些点击没有发出新的 `/site/ownertrans` 请求 |

日志中的 `serverUpdateTimestampNotNewer` 对应 Space 配置时间戳相同而跳过更新，和查询旧转移码失败没有直接关系。XPC、键盘及 debugger hang 信息也不在该错误的请求链上。

### 缓存为什么没有恢复

1. `SitesViewController.transferSite(site:)` 创建任务成功后，将返回的 `token` 保存为 `site.transferCode`。`SiteViewController.transferSite()` 有同样的行为。该字段与 `transferPassword` 会写入 SQLite，重新进入页面或重启也会加载它。
2. 接收成功路径恢复 `state = normal`、`permission = owner`，但没有清理 `transferCode` 或旧的 `transferPassword`。接收的是 `T_B`，不意味着下一轮仍可使用 A 的旧 `T_A`，也不能把已经用于接收的 `T_B` 当作新的转出码。
3. 这次接收响应没有 `shareId`，并返回空 `transPasswd`。`SiteData.update` 只有在版本更新或初始化时、且 `shareId` 能读成字符串时，才替换 `transferCode`；没有“成功接收意味着上一轮转出缓存失效”的处理，也不读取这里的 `transPasswd`。所以成功接收不会自动清掉旧缓存。
4. 两个“转移”入口都只按 `transferCode != nil` 选择 `/share/info`；查询返回 `4004` 后只弹出错误，既不作废缓存，也不尝试创建新任务。连续点击因此重复同一失败。

这是已有转移码生命周期处理缺失，前一轮仅修复坐标类型后，流程能继续执行到这里才暴露出来。现有证据足以定位 App 缺陷，不要求先修改后端。

### 建议的最小完整修复

1. **接收完成时作废上一轮转出缓存。** 在账号、地区和 Site 身份仍匹配，接收成功且本地导入恢复完成后，将旧 `transferCode` 和 `transferPassword` 清空并持久化，再报告本地接收完成。清理不依赖云端 Site 时间戳是否增加；不能在扫码或仅查询分享信息时清空，也不能把缺字段的普通部分响应一律当作作废指令。
2. **为存量失效缓存增加恢复路径。** 用户点击“转移”时，缓存查询成功且返回同一 Site、当前用户为 Owner、类型为 `ownertrans`，才继续复用；只有查询该缓存明确返回业务码 `4004`，才作废对应旧码，在当前账号/地区/Site 仍有效的前提下调用一次 `/site/ownertrans` 创建新任务并展示新二维码。创建接口继续执行服务端 Owner 校验。无权限、断网、超时、未知错误不能被当成旧码失效；失败应可重试，但不能递归无限创建。
3. **列表和详情使用同一段任务获取及结果保存逻辑。** 保留现有“需要同步时先同步”的门槛；统一处理首次创建、有效码复用、失效码重建和持久化失败。区分创建响应的 `passwd` 与查询响应的 `transPasswd`，确保邀请码和密码来自同一有效结果。普通 Site 数据保存不得用旧实例覆盖已经清理或更新的转移缓存；可复用现有 SQLite 事务的字段合并机制，显式转移操作才修改这些缓存字段。
4. **限制迟到响应和重复点击的影响。** 同一 Site 同时只获取/创建一次转移任务；回调检查账号、地区、Site 及本次查询的旧码。旧请求的失败不能清掉较新的成功结果。只更新转移缓存，不为本地缓存清理而修改 Mesh 数据、云端配置时间戳或已有空间。

第 1 项防止再次产生问题，第 2 项使当前已经留下失效码的安装可恢复，因此不能只加接收后的两行清空。针对当前项目，修复后的操作应是“点击转移 → 查询旧码确认不存在 → 创建新码 → 正常展示”，无需删除项目或重新创建网络。

### 相关但独立的事项

- 首次扫描跳过接收页并产生 `4010` 的旧 Owner 路由问题，在这份新日志中再次出现。若要同时消除该报错，还需要采用分享响应的 `owner.userId` 决定是否允许直接进入；这是前文已列明的独立修复项。
- `ShareChangePasswordController` 也调用 `/site/ownertrans`，但当前忽略成功响应中的 token；分享页初始化时还固定保存二维码值。日志没有改密码操作，也没有证据证明服务端改密码会换码，因此不将它判为本次原因。若将该入口接入同一创建响应保存逻辑，必须一并确保 token 变化时二维码、复制及分享内容同步刷新。

### 验证与当前状态

用户确认后已于 2026-10-26 在 `feat/HDB-261020` 实施，基于 `a5baf86b`（已提交的经纬度兼容修复）。本次改动尚未提交，原有其他工作树改动保留；没有修改 SDK、服务端或固件。

实施内容：

- 列表、详情和转移密码修改统一使用 `SiteTransferCoordinator`。有效旧码核对 Site、Owner、类型后复用；仅查询旧码返回 `4004` 时持久清空并创建一次新任务。其他错误原样失败，不自动重建。
- 同一账号、地区、Site 不并发创建；响应落地前核对账号、地区、成员关系代次、Site 创建身份、Owner/normal 状态及预期旧缓存。缓存使用 SQLite 事务条件更新，普通 Site 保存保留数据库最新缓存，迟到旧实例不能写回旧码。
- 成功接收后，恢复本地权限和状态时原子清空上一轮转出码及密码；保存失败不提示成功。普通 Site 快照不再恢复 `shareId` 缓存，也不会因缺字段清空有效缓存。
- 首次扫描根据分享响应中的 Owner 判断是否能直接进入本地 Site。B 转回的码进入接收页，不再因本地仍是旧 Owner 而误入详情。
- 接收所有权显式启用原有的转回初始化：即使本地仍为 normal 且时间戳相同，也执行地址恢复，并保留原网络及 Space 密钥检查；普通刷新不强制初始化。接收过程在异步边界复核请求上下文。
- 修改转移密码保存服务端返回的 token 与密码，同时更新二维码、复制码和分享图片。即使请求完成前已返回上一级二维码页，仍通知该页面更新。

自动验证：

- `python3 scripts/check_site_transfer.py`：执行生产协调器和 Site 导入包装逻辑，覆盖首次创建、有效复用、失效重建、错误边界、持久化失败及重试、账号/地区/权限/状态/代次变化、取消、重复请求、扫码路由，以及同版本转回初始化、网络身份和 Space 密钥保留。网络与地址分配为测试替身或边界，不代表服务器、Mesh 实测。
- `scripts/check_site_hdb_persistence.py`（`one-dev` SQLite）：真实 SQLite 验证接收清缓存、关闭重开、旧实例保存、条件更新与写入失败重试；既有坐标类型、部分字段、导入回滚和上传回执回归通过。
- `scripts/check_site_props.sh`：标准属性、导入、编辑与时区既有回归通过。
- `SunSmartLocal.xcworkspace` / `HSmart` / Debug / generic iOS / `CODE_SIGNING_ALLOWED=NO` 最终增量编译通过。SDK `one-dev` revision `e7c1a7f`，没有 SDK 差异。新增共享源文件在全部 6 个 target 的 Sources 中各登记一次，工程格式与 `git diff --check` 通过；其他品牌未逐个编译。

最短人工验收：

1. 当前留有失效码的项目直接点“转移”：应只查询旧码一次，`4004` 后创建新码并显示，重复打开应复用有效码；重启后仍能打开。
2. A→B→A，全程不手动刷新 A 的 Sites：A 扫描 B 的转回码应直接进入接收，完成后从列表、详情分别再次转出，B 能用新码接收；确认原 Site、Space 和设备配置保留。
3. 修改转移密码后核对显示、复制和分享的二维码一致；在请求未完成时返回二维码页，也应显示最终有效码。断网或服务端无权限时应报错，不能自动创建新任务。

没有自动安装或运行真机，也没有请求线上转移接口。端到端转移、真实地址分配和 UI 验收仍待人工完成。本轮不新增“服务器已接收但本地持续存储失败/进程中断”的跨端事务恢复机制，不能据此宣称这类故障已自动恢复。
