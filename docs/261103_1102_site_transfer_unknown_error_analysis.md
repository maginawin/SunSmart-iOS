# Site 转移提示 Unknown error：原因、引入提交与修复方案

日期：2026-11-03。范围：App；初始分析后已按用户最新指令实施下述最小调整。

## 用户指定的实际修改

用户明确要求移除“Owner 不同就返回 Unknown error”。本次在已有转移缓存的 `share/info` 成功路径移除 Owner 相等条件；仍校验 Site ID、token、type 与转移密码，并持久化返回凭据。列表和详情共用协调器，因此同时生效。

`ownertrans` 创建或修改密码响应仍保留现有 Owner 校验。本次没有增加详情权限查询、重建转移任务或状态 C 判定；下文原建议方案仅保留分析记录，不是本次实施内容。初始原因分析描述的是修改前行为。

回归已覆盖 Owner 不同且 status=C 的查询成功、返回密码保存、错 Site/token/type 或缺密码仍失败、创建响应 Owner 不同仍失败；现有转移协调器和 Site 导入两组测试均通过，`git diff --check` 通过。`SunSmartLocal.xcworkspace` / SunSmart / Debug / generic iOS / `CODE_SIGNING_ALLOWED=NO` 编译通过；本地 SDK 为 `one-dev`，revision `dbcf6f1`，SDK 工作树无改动。编译输出包含原有页面捕获及不可达 default 警告。未操作真机或线上转移；此调整保证不再因查询响应 Owner 不同而阻止展示，不能单独证明该服务器转移任务仍可被接收。

## 结论

本次 `/sitespace/share/info` 的 HTTP 和业务码均为 200。App 查询已有转移缓存后，发现响应中的 `owner.userId` 与当前账号不同，在 `SiteTransferCoordinator.credentials` 中拒绝该响应，随后将校验失败转换为 `.network(.unknown)`，页面显示 `Unknown error`。

**直接触发点已确认；“成功查询但归属不匹配”的缓存缺少核实及恢复分支。不能通过删除 Owner 校验来修复。** 当前仅 `4004/resourceNotFound` 会清理缓存并创建新任务；本次返回 200，不会进入该路径，重复点击会继续查询原缓存。

上述校验和错误分支由 **`88761abee10d49c66971e30cb2a3d01532d4de87`，2026-10-26** 引入，提交标题 `feat: update site API and site props`，正文包含 `fix: transfer project issues`。AuthorDate 为 14:19:48 +0800，CommitDate 为 19:13:17 +0800。这是本次 Unknown error 行为的引入点，不代表旧转移缓存首次产生的日期，也不能推导发布版本。

现有材料无法确定服务器当前 Owner 是谁，也不能确定旧缓存是历史版本、其他客户端完成转移后遗留，还是其他过程产生。响应有 `status=C`，但仓库内没有查到足以确认其含义的接口契约；不能把 C 直接写成“已完成/已取消”，更不能据此盲目重建。

## 证据

输入文件：

- `/Users/maginawin/Desktop/transfter logs.txt`
- `/Users/maginawin/Downloads/Site_日出日落_20261103_105728_316+0800.json`

文档不保存转移 token、密码、Mesh Key 或完整账号信息。当前请求/导出账号记为 A，分享响应 Owner 记为 B；二者是不同 UUID，并非仅大小写不同。

| 检查项 | 结果与解释 |
| --- | --- |
| 请求 | 只记录了一次 `.shareInfo`；没有 `.transferSite` 创建请求 |
| 响应 | HTTP 200、业务码 200、message=success，JSON 已完成解码 |
| 分享身份 | type=ownertrans；Site ID 与导出项目一致；响应 token 与请求 token 一致；密码字段存在 |
| Owner | 响应为 B，请求和导出当前账号均为 A；命中 Owner 校验失败 |
| 分享状态 | status=C，sharerRole=owner；后者不是“当前请求账号是 Site Owner”的证明 |
| 本地 Site | permission=1（owner）、state=1（normal）；lastUpdateTimestamp 与 lastUploadCloudTimestamp 均为 1793673665；pendingSitePropsMask=0、syncCloudError=null |
| 本地配置 | 1 个 Space、1 个 Gateway；Space 有 14 个 nodes、1 个 Group、0 个 Scene；Site/Space inspection issues 均为空 |
| Space 状态 | joined、active、writable；pendingUpload/pendingImport/pendingDeletionCleanup 均为 false；membershipNetworkMatches=true |

导出中的 `uploadable=false` 是 DEBUG 检查文件的固定用途标记，不表示 Site 无法转移或同步。`hasCompleteExportSnapshot=false` 表示没有对应的完整导出快照文件，不是本次校验失败的条件。

DEBUG 导出主动排除了 `transferCode`、`transferPassword`；不能因 JSON 没有这些字段就认定数据库没有缓存。结合转移入口的源码和 `.shareInfo` 请求可确定此次使用了缓存查询路径，但无法从该导出独立恢复缓存写入历史。

日志末尾 debugger hang 不在错误分支中；本次也没有设备命令、网关命令或 Site 配置上传请求。没有证据将错误归因于 Scene、经纬度或 Mesh 配置。

## 行为链与历史

1. Site 列表和详情的转移菜单先检查同步门槛，再共同调用 `SiteTransferCoordinator.prepare`。
2. 协调器检查当前账号、地区、Site 创建身份以及 Owner/normal 状态；存在非空缓存码时查询 `.shareInfo`。
3. 查询成功后校验 type、token、Site ID、Owner、密码。此次仅 Owner 条件明确不成立，返回 `.unknown`。
4. 页面读取 `Failure.message`，经 `NetworkApiError.unknown.localizedDescription` 显示国际化的 `Unknown error`。
5. 错误分支不写缓存、不修改 Site 状态、不创建新任务。因此本次失败本身没有执行新的所有权转移，也没有改变本地配置。

`88761abe` 的父版本对成功响应主要读取 token、转移密码并直接展示二维码，没有当前 Owner 校验。同一响应在旧逻辑下不会因 Owner 不同而显示本次错误，但可能继续展示不属于本轮有效转出任务的二维码；恢复旧行为不是正确修复。

该提交同时实现了有效缓存复用、4004 后重建、接收成功清理旧缓存、条件持久化、并发及迟到响应保护。现有测试甚至明确要求不同 Owner 返回 unknown，因此普通测试通过并不覆盖现场需要的恢复行为。

当前接收成功后，`SharePermissionSelectionController` 已调用 `site.save(clearTransferCredentials: true)`。普通 Site 保存从数据库合并缓存，`ImportData` 已不再从普通 Site 快照恢复 `shareId`。不应重复添加同一清理逻辑，也不应把普通响应缺字段解释为缓存作废。仅本机成功接收后的清理仍不足以覆盖历史缓存、跨客户端生命周期等情况；本次缺少接收全过程，具体来源未定。

分析时工作树从 `3e305a4e` 变为 `0fae4fa5`（外部提交了已有改动）；转移相关源码未变化。本任务不改动这些外部提交或其他文件。

## 建议修复方案

### 补充：为什么点击 Transfer Site 会请求 share/info

当前菜单不是每次都新建转移任务：没有非空 `transferCode` 时调用 `/sitespace/site/ownertrans`；已有缓存时先调用 `/sitespace/share/info`，验证后复用原二维码。明确修改转移密码则直接调用 ownertrans。查询缓存返回 4004 时，清空后再调用 ownertrans。

这种“有缓存先查询”的设计至少可追溯到 `d042f2a22`（2024-08-05 10:06:48 +0800，`0.4版本分享、权限接口对接`），不是 2026-10-26 才把创建接口改成查询接口。10 月 26 日引入的是共享协调器和此次触发的 Owner 校验/unknown 分支。

`share/info` 的 body 只有两个参数：

| 参数 | 当前来源与持久化 |
| --- | --- |
| token | `SiteData.load(siteId:)` 从当前地区的 SQLite `sites.transferCode` 读取；创建任务成功时由 ownertrans 响应 `data.token` 写入；有效 share/info 响应也经条件更新保存。它是转移码，不是登录鉴权 token |
| userId | `UserData.currentUserId = Keychain.getUUID()`；读取当前 App Bundle 对应 Keychain 的 uuid，首次不存在时生成 UUID 并保存。这里是 App 持久用户标识，不是从 Site 的 owner 字段复制，也不能准确称作登录账号 |

对应密码保存在 `sites.transferPassword`：创建响应使用 `passwd`（缺失时回退本次提交密码），查询响应使用 `transPasswd`。share/info 查询本身不发送该密码。数据库加载后会恢复这些字段，因此重新进入或重启仍会查询已有缓存。

当前成功接收 Site 会原子清空这两个缓存字段；查询明确 4004 也会条件清空。现场 JSON 排除了这两个敏感字段，现有日志也没有更早的写入请求，所以只能确认本次 token 来自数据库缓存，不能确认它当初在哪一次操作写入。历史版本还曾从 Site 导入响应 `shareId` 写入 transferCode，这一路径已在 88761abe 移除。

### 1. 在现有协调器内区分响应校验结果

继续严格核对账号/地区/生命周期、Site ID、token 和 type；Owner 不同应成为可诊断的“转移缓存归属冲突”，与结构缺失、错 Site、错 token、网络失败分开。

- 同 Site、同 token、ownertrans 且 Owner 为当前账号：继续按现有合法响应规则复用。状态字段的有效/终态规则需以接口契约补齐，不猜测字母含义。
- 同 Site、同 token、ownertrans，但 Owner 为其他账号：进入下述归属核实；不能直接展示这个码，也不能直接当成无权限或 4004。
- Site/type/token 不匹配、必要字段缺失：拒绝，不自动重建。
- 保留已有 4004 重建分支及断网、超时、权限错误处理，不把所有失败都视为缓存过期。

### 2. 用现有 Site 详情接口核实当前权限，再受控恢复

对明确的 Owner 冲突调用 `.siteInfo(siteId:)`，路径 `/sitespace/get/siteprops`。采用该接口现有的 `data.uuid` 与 `data.role` 契约核对目标 Site 和当前账号角色；不要误用只返回编辑属性的 `.sitePropsRetrieve`（`/sitespace/retrieve/siteprops`）。

- 返回同一 Site、当前角色为 owner，且请求上下文和旧缓存仍一致：确认该旧缓存不适合当前账号转出。通过现有 `replaceTransferCredentials(.empty, expected:)` 条件清空旧码/密码，再调用一次现有 `.transferSite` 创建新任务，由服务端执行最终 Owner 授权。新响应仍严格校验 Site、Owner、token、密码后持久化和展示。
- 返回非 Owner 或明确无权限：不创建、不强行修改本地权限；展示明确权限提示，并通过已有 Site 刷新流程协调页面状态。
- 超时/断网/响应格式错误：保留旧缓存，不创建，允许用户重试。角色缺失不能视为 owner；不能只因 HTTP 200 就允许创建。
- 清空保存失败：停止，不继续创建。清空成功后创建失败：保持空缓存；下次显式重试走现有首次创建路径，不能无限重试。
- 核实与创建之间权限仍可能变化；创建 API 的授权不能被前置读取替代。创建返回无权限时按权限失败交付。

权限核实只读取所需身份/角色字段，不在协调器中把整个详情响应导入 Mesh。避免为恢复一个转移缓存引入网关删除、Space 导入或配置版本联动。

### 3. 保留现有一致性保护，补足可诊断性

每次新增异步返回继续执行 `current()` 检查，复用同一 active scope 防重复点击，保留预期缓存条件写。账号/地区切换、成员关系代次变化、Site 删除/权限变化、取消及较新缓存写入后，旧响应不得清理或覆盖数据。

Owner 冲突无法恢复、无权限、响应不一致应使用明确的国际化提示；优先复用已有英文/简体中文 Key。DEBUG 日志仅记录操作阶段、失败原因及匹配布尔值，不打印 token、密码或完整密钥。

列表和详情通过共享协调器统一修复。修改转移密码同样使用该协调器，但显式新密码仍直接走已有创建/更新请求；核对成功后二维码、复制码和分享内容继续使用同一组服务端返回凭据。

不需要修改 SDK、固件或服务端实现，不需要数据库结构迁移、清空项目或重建 Mesh。分析范围覆盖共享品牌（包括工程中的 HSmart）；现场日志未独立标识实际品牌。

### 4. 状态契约待核对项

请接口责任方提供脱敏契约或既有响应证据：`status` 各取值、`owner` 表示任务创建人还是当前 Site Owner、已消费任务是否仍允许 `/share/info` 返回 200。此项只读核对，不要求修改后端。

若契约确认存在仍可查询的终态，需要同时覆盖“Owner 与当前账号相同但任务已终结”的情况；不能只修 Owner 不同这一种样本。当前 Owner 冲突的核实/恢复可独立设计，不依赖把 C 猜成某种终态。

## 验证与验收边界

已使用现有测试替身，在临时目录注入与现场响应同结构的脱敏样本，直接编译并调用生产 `SiteTransferCoordinator`：复现 unknown、仅一次 shareInfo、零缓存写入、零新建请求。没有修改仓库测试文件，也没有访问线上接口。

现有 `scripts/check_site_transfer.py` 的协调器及 Site 导入两组测试均通过。首次执行的导入测试因默认 Clang 缓存目录写入权限失败；将本次进程的 Swift/Clang 缓存指向允许写入的 DerivedData 目录后通过，没有清理共享缓存或调整代码。此结果说明既有测试没有把现场冲突定义为可恢复场景，不代表问题已经修复。`git diff --check` 及新文档空白检查通过。

实施后必要回归：

- 现场 200 + Owner 冲突：详情确认为 Owner 后，仅清理一次、创建一次；新码展示并持久保存。
- 同样冲突但详情非 Owner/无权限/超时/错 Site/缺 role：不得创建或复用旧二维码。
- 有效旧码、4004、首次创建、修改密码，以及 type/token/Site/字段错误。
- 清理失败、创建失败后重试、创建成功后保存失败，旧实例保存不能复活旧码；重启后的缓存连续性。
- 核实及创建阶段发生账号/地区/代次变化、删除、权限变化、取消、重复点击、较新缓存写入，迟到响应必须失效。
- 确认状态契约后补有效/终态以及 Owner 相同/不同的组合。

优先扩展 `scripts/check_site_transfer.py` 和既有 SQLite 持久化测试。生产代码实施完成后按项目规则构建一次代表 scheme 的 generic iOS Debug；国际化或资源归属变化另核对受影响品牌配置。

人工验收使用受控 Site：当前异常项目从列表与详情重新打开转移页；A→B→A 后再次转出；另一客户端完成接收后原客户端重进；修改密码后二维码/复制/分享一致。确认新 Owner 能接收、原 Owner 权限正确回收、原 Space/设备/网关配置保留。

初始分析阶段未构建 App、未运行真机、未发起线上转移；后续实施验证见文档开头。隔离复现只能证明 App 分支行为，不能证明服务器当前归属或方案已经完成真实转移验收。
