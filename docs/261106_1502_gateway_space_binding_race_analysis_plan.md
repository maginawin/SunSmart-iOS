# Gateway 首次绑定 Space 后同步被旧快照反转：分析与修复记录

日期：2026-11-06。状态：已按确认方案实施，目标回归及 SunSmart generic iOS 构建通过；待真实网关验收。另有一项既有 Site 时区回归失败，见末尾记录。

## 结论

第一次 SAVE 的问题来自 App 内“保存目标 → Site 云端刷新 → 本地导入 → 同步计划重建”的竞态。绑定接口已成功，但 Site 返回的 `gatewayPreconfigured.associatedSpaces` 仍为空；新保存的 Gateway 未及时递增本地修改代次，旧快照可以覆盖新目标。同步页随后根据被覆盖的目标自动重建，新增绑定转成了删除。

日志实际记录了 `ConfigNetKeyAdd(1)` 成功，随后 `ConfigNetKeyDelete(1)` 和 `gatewaySubnetAppkeyDelete(1)` 成功。这个“成功”只说明错误目标下的任务执行完毕，不代表用户要求的绑定完成。

解绑走同一保存和刷新链，存在反向风险：旧快照恢复已经删除的关联，计划重建后又添加回来。已用生产策略、同步上下文和差异计算方法做可控时序复现；用户这份日志没有执行解绑，不能把复现结果当作解绑真机日志。

推荐修复 App 保存事务及同步目标一致性，保留增量任务，并补完整性终检。无需每次 SAVE 都强制执行完整 Recovery；目前不需要 SDK、固件或服务器修改，也不涉及数据库或 export JSON 结构、字段语义变化。

## 核对范围

- 工作树：`feat-daylight-saving-261024`；分支：`feat/daylight-saving-261024`；HEAD：`71dd7e0b67ff33c1a448dd16de08719c4c45ee69`。
- 输入：[bind gateway logs.txt](</Users/maginawin/Desktop/bind gateway logs.txt>)，共 1374 行。文档仅记录命令名、索引及状态，不复制密钥、凭据或完整请求体。
- 入口：Site → `WiFiGatewayViewController`（共享 `GatewayViewController`）→ Associated Spaces → SAVE → `SyncDevicesViewController`。普通 SAVE 为 `.devices([node])`；Devices not synced 为 `.gatewayRecovery`。
- 原有未提交修改：`project.pbxproj`、`SiteDaylightSavingTimePresentation.swift`、英文资源、相应 DST 测试和 `261105_1100_site_dst_hint_analysis_plan.md`；全部保留。
- 日志没有记录安装包 Git HEAD。以下结论来自本次日志、当前源码和可控复现的相互印证，不声称已重建相同安装包。

## 日志证据与全部现象的对应关系

| 日志位置 | 观察到的事实 | 解释 |
| --- | --- | --- |
| 273、294、297–317 | 第一次 SAVE；reference 返回空；bind 返回 HTTP/business 200 | 云端关联修改成功，不等于 Mesh 配置完成 |
| 318–340，尤其 339 | 立即请求 Site；同一响应的 `refSpaces` 含 Space 1，但 `gatewayPreconfigured.associatedSpaces=[]`，`gatewayInfo.subnetAppkeyIndexs=[]` | 关联关系和 App 上传的网关配置快照暂时不同步 |
| 342–395 | Site 导入与网关同步交错执行 | 存在覆盖本次保存目标的时机 |
| 344、407 | `ConfigNetKeyAdd(index=1)`，成功回执 | 新增流程只推进到第一条 Key 配置 |
| 409–432 | 随即 `ConfigNetKeyDelete(index=1)`、`gatewaySubnetAppkeyDelete(index=1)`，均成功 | 新增被反转成解绑；中间没有完成该 Space 的 AppKey 和 Model Bind |
| 442 | 后续 register 上传 `associatedSpaces=[]`、仅主网 NetKey/AppKey | 错误的空目标继续被上传，扩大到重进显示 |
| 470–488 | 返回、KEEP EDIT、第二次 SAVE | 用户描述与 UI 事件顺序一致 |
| 509、531 | reference 已含 Space 1；随后的 Site 快照仍是空的预配置关联 | 第二次 SAVE 触发拓扑冲突处理；之后旧快照仍可覆盖本地 |
| 607 | 返回 Site 时仍收到上述不一致快照 | 本地 Gateway 关联为空时，Site 筛选得到空列表 |
| 682、685 | 重进 Gateway，reference 返回 Space 1 | 页面重新用关系接口恢复目标，暴露未完成的 Mesh 绑定 |
| 899–1251 | 进入 Recovery；重新初始化、添加 NetKey/AppKey、绑定模型、设置关联索引及服务器信息；最终上传含 Space 1 的预配置和 Key 状态 | 完整恢复把缺失配置补齐，并上传正确目标 |
| 1327 | Site 快照的预配置关联和关联索引均包含 Space 1 / index 1 | Site 筛选恢复显示 |

日志没有打印 toast 文本。由第二次 SAVE 的分支及请求顺序推断，对应现有文案 **“Associated spaces changed on another device. The latest data has been loaded.”**，中文为“关联空间已在其他设备上发生变化，已加载最新数据。”这不是发现另一台设备操作的确证，而是本地旧 baseline 与最新 reference 不一致触发的通用提示。

## 源码中的触发链

1. [GatewayViewController.swift](../SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift) 的 `saveAssociatedSpacesIfNeeded()` 先完成 bind/unbind；`persistGatewayConfiguration()` 把草稿写入 GatewayModel，然后立即发送拓扑变更通知。此处没有递增 `lastUpdate`，也没有建立待上传保护。
2. [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 的拓扑通知触发 `loadSiteRequest()`；只有另外的 `siteGatewayDataChangedNotificaitonName` 处理器才递增 generation 并安排上传。普通 SAVE 在同步完成/返回后才通知后者，保护建立得太晚。
3. [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 解析 Gateway 配置时使用 `gatewayPreconfigured`。当前 [GatewayCloudSnapshotMergePolicy](../SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift) 在本地不脏、无上传且身份未变时，允许缺少远端 `updateTimestamp` 的快照进入 `mergeFields`；完整响应中的空关联会替换本地关联。`refSpaces` 含 Space 1 不会阻止这个替换。
4. [GatewaySyncContext](../SunSmart/Main/Device/Gateway/Model/GatewayModel.swift) 的计划闭包比较持久化配置，能检测到覆盖；但 [SyncDevicesViewController.swift](../SunSmart/Main/Space/Controller/SyncDevicesViewController.swift) 的 `onPlanInvalidated` 无条件 `rebuildTaskPlan(resume: true)`。`prepare()` 又把数据库中的旧配置复制到页面持有的 GatewayModel。`.devices` 构建器也会经 `getSyncData(.all)` 从数据库重读 Gateway。
5. [Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift) 看到“网关已知 secondary NetKey 1，但目标关联为空”，因此生成解绑任务。对应 [Node+MessageHandles.swift](../SunSmart/Common/Data/Node+MessageHandles.swift) 发出日志中的删除命令。
6. 同步完成只核对当前计划中任务的执行结果，没有把结果再与最初 SAVE 的目标关联核对。Gateway 页面草稿仍为 `[Space 1]`，baseline 已被 `prepare()` 改成 `[]`，所以 `updateSaveBtnState()` 和 `closeAction()` 都认为仍有未保存修改。
7. 第二次 SAVE 的 mutation policy 发现 `baseline=[]`、`latest=[Space 1]`，走 `.topologyChanged`，把草稿和 baseline 都改成最新关系，显示上述 toast，并提前返回。这次没有继续 Mesh 同步，所以按钮变灰并不代表绑定配置完成。
8. Site 的 `setupData()` 用 `GatewayModel.associatedSpaces` 过滤 Space；因此持久化旧空关联导致 `No Spaces!`。重进 Gateway 的 reference 请求又把目标改成 `[Space 1]`，与缺失 Key/Model Bind 的 Node 状态存在差异，于是显示 `Devices not synced`。

自动失效与重建没有专用 Gateway 日志，因此日志直接证明的是命令反转和旧快照交错；上述内部函数衔接由当前生产源码及下述时序复现证明。现有身份/权限校验本身应保留，需要修正的是采用哪个目标及是否允许自动继续。

## 为什么是两项和七项

两项是任务分组数，不是 Mesh 报文数量。对已完成初始化且项目/MQTT 正常的网关，新增一个激活的 Space 可以只需要：

| 正常增量任务 | 本例需要的配置 |
| --- | --- |
| Associated Spaces | NetKey Add(1)、AppKey Add(1)、Vendor/Time/Time Setup 模型绑定 AppKey 1、gatewaySubnetAppkeyAdd(1) |
| Sync Spaces | gatewaySubnetsRelevanceSet([1]) |

本例恢复日志中的三个 Model Bind 均在 Primary Element `0x0002`：Sunricher Vendor `0x0A78/0x0001`、Time Server `0x1200`、Time Setup Server `0x1201`；Config 消息发往网关主单播地址 `0x0002`。关联 Key index 为 1，主网 index 0 保留。现有路径使用有回执的 Set/Config，修复无需改变 ACK/UNACK、目的地址或重试策略。

这两组任务应完成的是约七条设置命令（以本例模型组成和缺失状态计算），本次实际只执行了第一条新增命令就转向删除。

Devices not synced 打开的七组是现有 WiFi 完整恢复链：Initialize、Associated Spaces、Association Project、Sync Spaces、Server Authorization、Server Information、Verify Configuration。初始化/项目/服务器部分可能重做原本已经成功的配置，不能由“七项恢复有效”推导出“每次绑定必须执行七项”。现有 Verify Configuration 检查 App 内 Node 状态及配置差异，不是重新从硬件独立读回全部 Key/Model 配置。

## 解绑与其他关联入口

- **删除一个或全部关联再 SAVE**：先 unbind，再保存空/剩余关联，再刷新 Site，使用相同竞态链。若旧快照含已删除的 Space，会恢复旧目标；在删除命令已经执行后，自动重建可重新生成 ADD。未执行删除前覆盖则可能漏掉删除。影响取决于交错位置，不能保证每次都以相同 UI 表现出现。
- **同时增加和移除**：同样需要把整轮已确认目标作为一个一致的计划；不能只保护 additions。
- **部分接口成功后失败**：`reconcileAssociatedSpacesAfterPartialSave()` 会应用服务端最新关系，但同样没有在该入口递增待上传 generation；应复用修复后的提交逻辑，保留未完成 Mesh 差异。
- **离线 Force Clear Associated Spaces**：成功清除服务端关系后也直接保存并发拓扑通知，存在旧快照恢复显示的相同窗口。此入口的产品语义仍是清除云端关系，不应被本次修复改成必须在线完成 BLE；下次连接由差异/恢复流程处理剩余硬件解绑。
- **整网关删除**：已有单独删除状态与导入保护，不作为本次扩展目标。
- **WiFi/4G、角色和品牌**：普通 SAVE 在共享基类，4G 也有同源风险；本例真机证据仅为 WiFi。Owner、有效 Space Editor 的权限检查，以及五个品牌的共享路径都须保持。

## 已确认的修复方案

选择 **“保存与导入一致性保护 + 固定增量目标 + 结束校验”**。不建议只延迟 Site 刷新：其他在途请求仍可能覆盖；也不建议把 SAVE 直接改成完整 Recovery：增加不必要初始化/授权，且不能独立解决旧快照覆盖。

1. **在首次刷新/异步下发之前提交本轮已确认的关联目标。** 复用现有 `GatewayCloudSyncGenerationPolicy.next`、`lastUpdate/lastUploadCloudTimestamp` 和上传机制，让保存目标与待上传标记一同成功落盘；检查保存返回值，失败不进入同步/不显示成功。正常 SAVE、部分成功后的 authoritative reconciliation 和 Force Clear 复用同一处提交边界。只读 reference 加载不能盲目标脏或上传。
2. **让旧 Site 响应不能覆盖本轮目标。** 复用现有 preserveLocal 规则；ImportData 在异步等待之后、真正提交 Gateway 之前，重新核对最新持久化代次/上传/删除状态，不能仅依赖 await 前的 `cacheByMac`。对本次修改前发起、在新上传确认后才落地的请求，也要核对请求捕获的版本，阻止跨代回包回写旧 Gateway 切片；Site 其他有效信息仍可更新。不得整体禁止远端合法空配置、其他用户合法修改或正常导入。
3. **SAVE 的任务使用同一份已确认目标。** 在现有 Gateway 上下文及构建器中传递本次目标/代次，准备、差异生成、执行和结束共用；避免 `.devices → getSyncData(.all)` 再独立从数据库选择另一个目标。复用现有任务和执行器，不新增同步页面或持久化状态机。计划因权限、身份或真正的外部修改失效时停止当前轮次，提示重试/重新准备；不得悄悄采用变化后的目标并自动执行反向动作。
4. **保持增量任务完整及依赖顺序。** 添加/解绑任务在目标 Index Set 之前完成；关联变化和历史待重试任务均纳入，未变且已成功的项目/服务器/初始化不重复下发。缺少关联 Key 时明确失败，不能静默跳过后显示成功。最终基于本轮目标、任务回执及实际 Node 差异复核；失败保留 `Devices not synced` 和重试入口，不把错误计划成功当作用户操作成功。
5. **统一成功、失败与页面状态提交。** 成功后 baseline/draft 保持一致，SAVE 变灰且退出无未保存弹框；Site 读取同一份已提交关联。失败/STOP/离页保留已提交目标和未完成设备差异，准确区分“配置已保存、设备未同步”与真正未保存的编辑。上传和后续 Site 读取按同一代次收敛；上传失败/重启沿用现有脏标记重试，不依赖重新打开 Gateway 才恢复。保留迟到 ACK、取消及失效回调保护。

现有 dirty-upload 机制已经能够保护本地目标，缺失的是建立时机、异步提交复核和任务目标传递。只增加必要的运行期目标/请求版本记录；不新增数据库字段、JSON Key、迁移、独立队列或后台服务。若实施发现现有字段不足，需要结构变化，先更新说明和示例另行确认。

外部接口暂按现有语义使用：bind/unbind/reference 提供关联关系，register 上传 Gateway 配置镜像，siteprops 可在上传完成前返回旧镜像；不能将这次暂态不一致直接定性为服务器错误。App 修复不等待服务器或固件发布。服务器团队仅需在联调验收时确认最新 register 成功后，新的 siteprops 能返回对应镜像；若不满足，再作为独立外部配套问题记录。

## 本轮复现与验证边界

临时探针：`/tmp/gateway_race_probe_261106.py`。从生产文件提取并执行 `GatewaySyncContext`、`GatewayCloudSnapshotMergePolicy`、`GatewayCloudAssociatedSpaceMergePolicy`、`GatewayAssociatedSpaceMutationPolicy`、`Node.getNodeSyncGatewayData`。结果：

```text
ADD: [ADD, INDEXES=[1]]
  -> NetKey Add ACK -> import old [] -> plan invalid
  -> prepare/rebuild -> [DELETE]
second SAVE: topologyChanged, no BLE continuation
REMOVE: [DELETE, INDEXES=[]]
  -> removal applied -> import old [1] -> plan invalid
  -> prepare/rebuild -> [ADD, INDEXES=[1]]
dirty-upload control: ADD and REMOVE targets both preserved
```

探针以 JSON encode/decode 模拟关联持久化往返，HTTP、SQLite、Mesh/ACK 时序和 Node 模型为替身；没有执行完整 `SiteData.update`/SQLite 写锁/真实 BLE，也没有运行 UIKit 的自动重建回调。因此它证明生产策略组合可导致方向反转及 dirty 保护有效，不能替代后续真实导入/存储/执行边界回归或真机验收。

本轮以下既有检查均退出 0：

- `python3 scripts/check_sync_preparation.py`
- `python3 scripts/check_sync_task_builders.py`（夹具存在既有 unreachable default 警告）
- `bash scripts/check_gateway_associated_spaces_deferred_save.sh`
- `bash scripts/check_gateway_multi_role_consistency.sh`

已有测试没有串起 SAVE、Site 旧快照导入和执行中计划失效重建；部分为源码合约，所以其通过不否定本问题。

## 确认实施后的最小验证与人工验收

1. 将上述新增/解绑交错复现加入现有测试入口，覆盖旧响应在建计划前、首个 ACK 后、上传确认后才落地的不同位置；补真实关联序列化和 SQLite 提交/重载，避免仅用内存 stub 验证导入保护。
2. 执行现有导入提交和同步失效/停止/重试方法，注入延迟响应、ACK 与取消，断言不会自动生成反向操作；测试完整成功、部分绑定成功、断网、解绑最后一个 Space、同时增删、应用重启和重进。
3. 验证 Owner/Editor/Visitor、权限撤销、网关删除/替换、主网切换、缺 Key、合法空关联、缺字段/旧格式；不放松既有身份或导入完整性保护。复跑上述相关测试及执行器生命周期回归。
4. 如需新增诊断，仅在 DEBUG 下记录操作代次、关联索引摘要、任务类型、导入保留/应用决定和终检剩余差异，不输出密钥或 MQTT 凭据。
5. Swift 修改后核对 `SunSmartLocal.xcworkspace` 和 SDK 实际映射，构建一次 SunSmart Debug / generic iOS，`CODE_SIGNING_ALLOWED=NO`。共享纯逻辑以代表品牌构建；若引入资源、target 配置或 SDK API 风险，再按规则扩大品牌覆盖。
6. 人工：新网关关联一个 Space → 一次 SAVE 完成全部必要命令 → 返回无未保存弹框 → Site 能按网关显示 Space → 重进无未同步差异；再删除关联并 SAVE，确认解绑不反弹，最后一个解绑后 Site 无关联是预期；补一个中途断连后重试及一次 App 重启。

分析阶段未构建 App、未自动操作真机、未访问真实服务端、未修改 SDK/服务器/固件，未 commit/push。

## 实施计划与进度

使用 Superpowers writing-plans / executing-plans / test-driven-development，在当前独立工作树直接实施。目标与约束沿用上文；不使用子代理、不提交 Git、不新增持久化结构。

- [x] 保存和导入保护：`GatewayModel.commitConfiguration(_:) -> Bool` 统一提交配置与 generation；`Database.swift` 成功保存代次变化时更新现有请求上下文的运行期版本；`ImportData.swift` 提交前重读最新 Gateway 并核对响应版本。测试覆盖 SQLite/JSON 往返、失败、旧请求晚到及上传确认后晚到。
- [x] 固定 SAVE 目标：`GatewaySyncContext.prepare` 对 SAVE 校验捕获目标而不替换；同步页的 Gateway 计划失效停止，不自动执行新目标。测试覆盖新增、解绑、权限变化、停止与显式重试。
- [x] 完整增量计划：在既有构建器增加 `makeSaveDevice(node:gateway:)`，使用显式目标、检查 Key 完整性、整合增删依赖并复用现有最终核验；普通 Space 同步保持原路径。测试覆盖历史待重试、同时增删、合法空关联及缺 Key。
- [x] 将正常 SAVE、部分成功 reconciliation、Force Clear 接入统一提交；相关回归、差异审查、generic iOS 构建后更新本记录。

重点边界：请求早于保存或早于上传确认、导入 await 前缓存过期、旧上传回调持有旧 Gateway 实例、最后一个关联被解绑、终检失败不能触发成功回调。现有字段覆盖这些情况，不变更数据库或 export JSON。

## 实施结果与验证记录

### 最终行为

- 每一个 bind/unbind 接口确认成功后，立即把已确认子集及待上传代次写入 SQLite，再发起后续异步请求。后续接口或 reference 失败时，已成功子集不会丢失；未完成草稿仍保留供重试。最终配置持久化失败不进入 Mesh 同步、不显示成功。
- 复用 `GatewayOrphanGuard` 的现有请求 epoch，并增加仅运行期的每网关配置版本。保存或上传确认后，之前发起的 Site 请求不能覆盖该 Gateway 配置；同一响应的其他 Site 字段和无关 Gateway 不因本次保护被整体丢弃。导入在 `Node.import` 的 await 之后重新加载当前 Gateway，保留原身份、角色、dirty、删除与远端版本决策。
- 通用持久化拒绝旧代次实例覆盖新配置，并保留已确认上传代次。只有经过既有导入策略批准的远端替换使用显式导入参数，兼容合法新身份的较低时间戳；没有整体放宽导入权限。
- SAVE 捕获关联集合及配置代次，直接向任务构建器传递该目标。执行中若身份、权限、Key 或目标变化，停止并显示新的中英文重试提示，不再自动重建成反向计划。普通 Space 的自动重建行为保留。
- 复用初始化、绑定、解绑、Index Set 和配置终检任务；Index Set 依赖关联增删完成，终检依赖全部增量步骤。缺少目标或待解绑 Key 时准备失败。已完成且无变化的初始化/项目/服务器信息不重复下发；终检仍基于 App 内 Node 状态与任务回执，不是新增硬件读回命令。
- 正常保存、部分成功对账、Force Clear 共用提交边界。同步停止/失败后目标仍在数据库，既有未同步差异和上传重试负责恢复；返回 Site 的 `retryDirtyGatewayCloudUploads()` 可继续上传，无需先重新进入 Gateway。Force Clear 仍只清除云端关系，不强制 BLE 在线。
- 新增 `gateway_sync_configuration_changed` 的英文、简体中文资源。资源沿用已有共享 `Localizable.strings` variant group，各品牌归属不变；无新源文件 target membership、SDK API 或依赖变更。

### 自动化证据

以下命令退出 0：

| 检查 | 有效覆盖 |
| --- | --- |
| `python3 scripts/check_gateway_association_save.py` | 提取生产 Gateway/数据库保存加载/关联 JSON/控制器异步保存方法，使用 SDK SQLite 真正写入和重载；绑定 dirty、最后一个解绑、上传前后旧响应、旧实例回写、部分成功后请求与 reference 双失败、SQL 失败回滚、合法远端低版本替换 |
| `python3 scripts/check_sync_preparation.py` | SAVE 目标/代次冻结、Owner/Editor/Visitor、权限/身份/删除/Key 变化、准备取消、STOP、离页、迟到结果、显式重试；测试替身匹配 SDK MQTT 类型仅提供 `==` 而未声明 Equatable 的行为 |
| `python3 scripts/check_sync_task_builders.py` | 显式 Gateway 目标、同时增删、关联到 Index Set 的依赖、最终核验、合法空目标、缺失旧 Key 拒绝；既有任务回归 |
| `python3 scripts/check_sync_execution_session.py` | 真实执行会话方法的停止、取消、ACK、迟到回调、执行中失效与调度 |
| `python3 scripts/check_sync_run_lifecycle.py` | 轮次与离页生命周期 |
| `bash scripts/check_gateway_multi_role_consistency.sh` | 既有多角色与导入/上传策略回归 |
| `bash scripts/check_gateway_associated_spaces_deferred_save.sh` | Associated Spaces 的 deferred SAVE 既有合约 |
| `bash scripts/check_wifi_gateway_repair_recovery.sh` | 既有 WiFi 修复/完整恢复路径 |
| `python3 scripts/check_gateway_deletion_context.py` | 删除上下文保护 |
| `scripts/check_gateway_orphan_cleanup.py` | 实际 SQLite 的孤立网关清理、旧回写、重新添加、回滚；以临时 module cache 执行，未改共享缓存或脚本 |
| `git diff --check`、两种语言的 `plutil -lint` | 差异格式与字符串语法 |

本轮也检查了 `scripts/check_site_gateway_metadata_reload.py`。其源码提取原先误包含无关的 `shouldShowGatewayList`，已收紧提取结束标记。之后该套件在 `invalid Site timezone must use supplied phone fallback` 断言失败；用 `--revision HEAD` 加载修改前生产代码复跑，同一断言失败，确认是既有时区问题。未修改时区业务或掩盖该断言，此套件不能记为通过。

新增持久化回归跨过真实 JSON 编解码和 SQLite 边界，并执行生产关联保存异步方法；HTTP/reference、UIKit、Mesh Node/ACK 为受控替身。没有运行完整 `SiteData.update` 联网导入或 App 进程重启，因此新测试中的数据库重载不等同于真实重启验收。任务构建、准备及执行器分别验证，仍需真机串起完整交互链。

### 构建与交接

- `SunSmartLocal.xcworkspace` / `SunSmart` / Debug / iphoneos / `generic/platform=iOS` / `CODE_SIGNING_ALLOWED=NO` 构建退出 0。DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-gateway-association`。
- SDK 来源为 `.local-sdk/nordic-sig-mesh-sdk`，realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `2809c54`；SDK 无修改。构建中的 MQTT 可空比较错误已修正并由最终构建验证；其余既有 Swift capture/deprecation 等警告未扩展处理。
- 本轮核对了共享资源归属，构建代表品牌 SunSmart；未执行其他品牌、Release、Simulator 或真机安装。未修改数据库/export JSON 结构、服务器或固件；未 commit/push，原 DST 未提交改动保留。
- 最短人工验收：新增关联一个 Space → SAVE 完成 → SAVE 灰色且退出无未保存提示 → Site 显示 Space → 重进无 Devices not synced；删除同一关联后 SAVE，确认不反弹且删除最后一个后 No Spaces 为预期；最后补一次同步中途断连后重试及 App 重启，确认目标和剩余差异可恢复。任务数可能包含复用的终检分组，应按实际必要命令与最终状态验收，不以固定“两项/七项”判断成功。
- 未完成项：上述真实 WiFi 网关/服务端/UI 链路验收；4G 共享入口运行验收；既有 Site 时区回归失败另行处理。
