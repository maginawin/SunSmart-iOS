# Editor 无法进入与解绑 Space：样本根因及同步改进方案

日期：2026-09-16。用户已确认第一阶段计划，客户端实现与验证记录见第 11 节。未调用线上写接口、未操作真机、未提交或合并。

## 1. 结论

本次首要问题是 **App 本地生命周期和身份不一致**，现有证据不支持“云端 500 个设备配置损坏”或“两台手机有效配置无法合并”作为本次直接原因。

- 云端：500 个设备、17 个实体组、2 个全局场景；本地：这些对象均为空，创建/修改时间均为 0，未有成功同步时间。
- 本地业务记录 `state=1`（normal）、`permission=2`（Editor），但恢复记录 `recoveryPhase=retired`。前者允许用户点击，后者拒绝导入和解绑。
- 数据库 `subNetworkKey=""`，而导出器在内存对象作用域下找到了与云端相同的 NetKey/AppKey；说明持久化身份与内存使用的子网身份不同。
- 云端样本运行当前生产 Profile 校验：无问题；运行生产 `SpaceSyncCleanupPolicy.normalize`：500 个设备、0 项修复、0 个孤立订阅、0 个拓扑硬错误。
- 临时隔离探针执行生产恢复逻辑与导入前缀，复现了 `retired` 下 `update → spaceRemovalPending`、`beginUnbind → nil`，均无需云端配置有任何差错。

应保留阻止空壳上传、阻止错误身份控制设备的保护；必须修复恢复流程，并取消“任何恢复失败都封死页面和解绑”的产品行为。

不能承诺自动猜中所有相互矛盾的用户意图。可交付的目标应是：兼容差异自动消化，身份/生命周期错误自动恢复，真正的配置冲突只冻结受影响写操作；用户始终有查看状态、重试、保存副本与退出的入口。

## 2. 样本对照与证据边界

输入：

- `/Users/maginawin/Downloads/tmp/space_server_data.json`，约 12.38 MB，读取 `data`。
- `/Users/maginawin/Downloads/tmp/Space_兴东2_20260916_175741_363+0800.json`，4,396 bytes，读取 `spaces[0]` 与 `_debugInspection.spaces[0]`。

| 项目 | 云端 | 手机导出 | 判断 |
|---|---|---|---|
| Space UUID | 与本地相同 | 与云端相同 | 不是导错 Space |
| NetKey / AppKey | 均为 index 5 | 完整对象与云端相同 | 未发现样本中的密钥差异；不在文档记录密钥 |
| nodes / deviceCount | 500 / 500 | 0 / 0 | 本地不是一份完整恢复副本 |
| groups | 17 | 0 | 不是少量 Group 合并冲突 |
| scenes | 2 | 0 | 指全局场景；各 Profile 自带场景另计 |
| schedules / switches / emergencyFireControllers | 均为空 | 均为空 | 一致 |
| spaceData | schema 1，triggerZones 空 | 同样 schema 1，triggerZones 空 | 本例不是旧版空数组覆盖新拓扑 |
| createTimestamp | 1788226475 | 0 | 本地符合分享占位记录特征 |
| updateTimestamp | 1789525945 | 0 | 云端修改时间为 2026-09-16 10:32:25 +08 |
| lastUploadCloudTimestamp | 不适用 | null | 本机从未记录成功恢复/提交基线 |
| source | 1 | 3 | 云端来源与本地分享入口不同，不能单独视为冲突 |
| 业务状态 / 权限 | role=editor | normal / Editor | 与恢复记录矛盾 |
| 恢复状态 | 不适用 | retired | 直接触发两处拒绝 |
| 持久化 subNetworkKey | 不适用 | 空字符串 | 需要先完成身份绑定 |
| pendingImport / pendingDeletionCleanup | 不适用 | false / false | 导出时未显示正在导入或设备删除清理 |

17 个组的地址为 CD60…CD70，Profile 均为 type 8，每个含 3 个场景，relay=2。499 个设备有组，1 个设备为 `groupState=0, groupAddress=""`；该空地址是已有兼容逻辑允许的表示。UUID/主单播地址未发现重复，拓扑清理校验也未发现元素地址重叠等结构错误。

`_debugInspection.uploadable=false` 是诊断导出的标志；`issues=[]` 仅表示导出器未收集到诊断问题，**不代表配置完整、可上传或生命周期正常**。这份本地 JSON 不应作为“完整副本”覆盖云端。

rawLocal 的 Mesh 查询按内存对象的子网身份限定，因此其空列表证明该导出作用域未读到设备；不能据此推断整个手机数据库、其他 Space 或归档目录都没有历史数据。

## 3. 两条错误如何触发

### 3.1 进入 Space 的直接链路

`SiteViewController.selectSpaceAction → loadSpaceReqeust → SpaceData.update`。

`ImportData.swift` 的 `update` 首先检查 UUID，随后要求恢复状态为 active。读取失败、removing 或 retired 都会返回 `spaceRemovalPending`，此时尚未做云端 Profile/设备预检。控制器把所有 rejected 统一映射为 `configuration_reload_invalid`，停止导航。

这说明文案误导：本例是本机旧恢复状态拒绝了一次新恢复，并非已证明云端数据不能恢复。

进入路径的全部 rejected 分类：

| 原因 | 当前用途 | 必要边界与建议 |
|---|---|---|
| spaceIdentityMismatch | 响应 UUID 与目标不一致 | 必须拒绝应用该响应；不可连接错误网络。可留在状态页面重新获取 |
| spaceRemovalPending | phase 非 active，或恢复记录读取失败 | removing 需要完成/协调旧事务；retired 且已重新获授权应建立新代际；读取损坏应独立报告。不可都永久挡在入口 |
| staleImportPreparation | await 后账号、代际、本地版本、数据库版本变化，或取消 | 丢弃旧结果正确；对最新请求做有限重试，取消不应报“云端损坏” |
| missingRequiredArray | nodes/groups/scenes/schedules 缺失或类型错误 | 不可当空数组覆盖；重拉完整快照，保留已验证数据 |
| Profile 校验不通过且无可用本地快照 | 缺 id/type、字段范围/类型错误、Photocell 场景或日夜引用异常等 | 不应虚构配置；可按明确旧格式迁移，否则冻结相关配置编辑，提供诊断页面 |
| meshNetworkUnavailable | 本地 Mesh 容器不可用 | 先补齐经过认证的 Site/Space 依赖；不可归因于云端配置冲突 |
| configurationStagingFailed | Group/Node 解码失败，原始修复副本保存失败，或 beginImport 失败 | 区分数据解码和本地存储/生命周期原因；拒绝提交有必要，拒绝页面导航无必要 |
| configurationPersistenceFailed | 数据事务、落库回读、拓扑回读或 finishImport 失败 | 不可宣称同步成功；保留原快照，提供重试与状态，不回滚 Mesh sequence/IV 状态 |

并非所有异常都会 rejected：有可用旧快照时，非法 Profile 通常返回 skipped；非法拓扑可保留本地快照，无旧快照时也有导入可解码部分而禁止拓扑修改的降级路径；旧 schema 可能清空本地 Zone 时返回 skipped 并阻止覆盖。现有机制已有降级能力，但入口/状态处理未统一。

同一文案另外还用于 Space 页面刷新，以及“从云端重载”操作。后者连网络失败、返回结构异常、导入后仍 blocked 也会显示该文案，所以不能从英文提示倒推出数据具体哪里坏了。

另有一层 `intoSpace` 防护：Owner/Editor 已属于云端 Space 但 `lastUploadCloudTimestamp=nil` 时，会提示尚未同步而不进入。仅删除 rejected 导航判断仍解决不了这个样本，也可能使空壳获得错误写入能力。

### 3.2 unbind 的直接链路

`SiteViewController.unbindSpace`：

1. 取消后台同步。
2. Editor 若 `needUploadCloud || hasPendingUpload`，先 `uploadBeforeUnbind`；失败即返回。
3. `beginUnbind` 要求 phase=active，失败也用 `configuration_upload_unconfirmed` 提示。
4. 然后才计算回收地址并请求 `/sitespace/space/unbind`。
5. 云端成功后若本地 `space.delete()` 失败，也复用同一提示。

样本 `lastUpdate=0, lastUploadCloudTimestamp=nil`，故 `needUploadCloud=false`。retired 的归档逻辑会清空 submission 和活动 blocked marker；样本也没有 blockedReason。按此状态，最直接路径是第 3 步失败，**甚至没有发出 unbind 请求**。无需假设服务器拒绝解绑或读回内容冲突。

其他可能触发该提示的原因包括：待提交恢复状态非法、未知提交结果与 GET 不一致、权限/代际在异步过程中变化、本地导出/检查点失败、提交回执持久化失败等；部分网络或权限错误会显示其自己的错误。

所以：本例正常 App UI 确实可能将 Editor 困住。Owner 从成员管理回收权限仍是独立的服务器侧路径，但不能把“只能求 Owner 踢出”作为合格的退出设计。

## 4. 状态为什么会变成这样

### 已证实的实现缺口

1. `SharePermissionSelectionController` 单 Space 分享预览创建 `create=0, meshNetworkId="", source=.share` 的对象；join 成功只设置权限、密码、业务 normal 状态并 save，未完成规范子网身份绑定或新恢复代际初始化。
2. `SpaceData.import` 仅在本地不存在记录时，从 netKey 解析正确的 networkId；本地已有占位记录会直接复用。随后 `activateImport` 基于此时的对象身份运行。
3. `SpaceData.update` 开头先检查/使用恢复记录并保存 metadata。直到中段“子网 key 丢失”分支才修改 `self.meshNetworkId`；事务内部也有相同修改。
4. 恢复文件按 account、region、meshUUID、networkId 定位。networkId 改变意味着换了一份恢复记录，先前对 active 状态的判断不再代表后续目标。
5. 删除 Space 会留下 retired 记录，以阻止旧异步回调复活已经删除的空间；这本身必要。新分享若在错误身份上激活，就不会清掉真实子网的旧 retired 代际。
6. Site 整体导入走 `SpaceData.import → activateImport → update`，直接点击 Space 走 `update`，两条入口的生命周期准备也不同。

### 与样本高度吻合的形成链

旧 Editor 正常使用 → unbind/权限回收后的本地删除，真实子网留下 retired → 再接受同一个 Space 的单独分享，落库存储空 networkId 的占位记录 → 导入先在空身份下激活/保存 metadata → 根据云端 netKey 将内存对象切到真实身份 → 真实身份仍 retired → beginImport 无法获得 active 恢复目录 → 配置尚未落库，留下内存真实身份与数据库空身份分裂。

之后同一个内存对象再次进入，直接返回 spaceRemovalPending；unbind 返回 nil。此链解释了样本中“密钥可读、DB subNetworkKey 空、业务 normal、恢复 retired、配置为空”的组合。

**证据边界：** 两份 JSON 不包含先前操作日志，不能证明用户确实执行过上面每一步。该形成机制由源码支持，且身份切换的关键失败边界已在隔离探针复现；完整 UI 顺序仍需真机确认。不能把所有失败都归因于跨 App 版本或 500 个设备规模。

另一个潜在问题：恢复文件键未包含 Space ID，但内容 identity 会校验 Space ID。同 Site 多个未初始化的空 networkId 占位对象可能指向同一文件并产生 identity mismatch。样本未证明发生了此分支，应纳入身份修复测试，不能简单删除 identity 校验。

## 5. 建议方案

### P0：先修当前死锁，不要求后端改造

**A. 统一有授权依据的恢复入口，先身份后生命周期再数据。**

- 分享加入、Site 导入、直接 Space GET、重载统一复用恢复准备步骤。
- 区分分享占位记录和已完整初始化的 Space。占位记录不具备上传资格；0 个设备本身不能被用来判定空壳，因为合法空 Space 也存在。
- 从成功且匹配当前请求的受认证响应解析 Site/Space、NetKey/AppKey 索引绑定和派生 networkId，在任何恢复状态读取、检查点、回执创建之前确定不可变导入身份。
- 确认重新加入意图/当前成员资格且无正在执行的删除后，对 retired 启用新 generation，复用既有 archive/activateImport 机制。旧 pending upload、旧回调不得跨代继承。
- removing 必须协调完成旧操作再重建；不能在所有 update 里无条件 activateImport，避免延迟 GET 把用户刚退出的 Space 复活。
- 已初始化 Space 的真实密钥冲突/Key Refresh 必须走已有网络身份处理，不能把占位身份修复扩展成任意换密钥。
- 暂存、事务与保存使用固定作用域；成功后同步替换内存与数据库对象。失败不能只留下内存已换身份、数据库仍旧身份。
- 占位恢复记录用稳定账号/地区/Site/Space 身份区分，或暂不创建子网级恢复记录；旧子网记录需有安全兼容/迁移路径，不能全删文件。

**B. 进入、控制、编辑、上传、离开分别决定。**

保留现有权限模型，增加明确的恢复结果/可用能力，避免再让单个 Bool 决定所有行为：

| 状态 | 页面行为 | 配置行为 | 退出行为 |
|---|---|---|---|
| 有效云端 + 本地空壳 | 自动恢复，展示进度 | 完整提交后开放编辑上传 | 可离开 |
| 有效旧快照 + 拉取失败 | 展示最后成功副本和状态 | 符合权限/网络身份的既有操作按范围开放；不做危险覆盖 | 可离开 |
| 局部 Profile/拓扑异常 | 展示有效对象与异常项 | 冻结受影响配置，保留原始字段，不导出成默认配置 | 可离开 |
| 无可信快照 | 展示恢复/状态页，不伪装成真正空 Space | 暂不发 Mesh 命令或上传 | 可离开 |
| 权限失效/身份错误 | 展示授权或退出页 | 不允许控制、编辑和上传 | 可清理本机并独立处理成员关系 |

这不是只改提示：需要使 Site 列表也能访问恢复状态和退出，不把修复功能全部藏在进不去的 Space 页面里。

**C. 解绑成员关系不依赖成功上传完整配置。**

- 没有本地有效编辑（本次样本）：直接完成服务器成员解绑流程，无须上传空壳，也不应被旧 retired 配置记录挡住。
- 有未上传修改：默认先尝试同步；失败后提供保存可恢复副本并离开的选择，清楚说明这些修改未同步。归档内容与云端成员关系分离，退出后不得后台继续写该 Space。
- 建立独立、可持久化的解绑意图和重试状态。服务器已确认解绑但本地清理失败，应显示“已离开，正在清理”，不能宣称云端同步未确认。
- 网络不可用时可以“从本机隐藏/待联网完成离开”，但不能显示服务器已解绑成功。权限已不存在应视为目标已达成，而非逼用户重新获取权限才能退出。
- 解绑和重入串行化；旧解绑回调不得删除新加入的实例。
- 现有 API 的回收地址参数在客户端可省略，但后端是否允许、是否能延后回收需核对。不能直接删 guard 后沿用旧路径：`getRecycleAddressData` 在发请求前可能移除本机 provisioner 节点并修改 localAddress，应调整为准备回收计划、服务端确认后完成，失败可恢复。
- 回收手机的未用分配范围应与仍被设备使用的地址区分；离开 Space 不意味着重置或删除 Space 内设备。未知资源占用宁可暂留待核对，不释放后重复分配。

### P1：App 自动处理可判定差异，减少跨手机摩擦

1. **按语义规范化。** 复用当前空 groupAddress、ALL、旧扩展读取和引用清理策略；补充明确的版本迁移。只对集合排序，路径、场景执行顺序等有业务顺序的数组不得统一排序。缺字段、null、空集合是否等价按字段契约确定。
2. **有基线才做三方合并。** B=上次确认配置，L=本地意图，R=最新服务端；L=B 用 R，R=B 保留 L，L=R 直接确认。没有基线的空壳只恢复云端，不能执行“空数组代表用户删除”的合并。
3. **按实体与操作范围合并。** 独立组、单纯改名等可自动组合。删除需要明确删除记录；设备身份、归属、Profile 类型转换、场景引用和拓扑依赖必须作为相关操作一起检查，不能逐字段拼出从未存在的配置。
4. **真正的同项冲突只限制该项。** 双方同时改变同一个字段且值不同，或一方删除另一方编辑时，保留双方候选并提示具体差异。其余有效对象仍可查看；用户仍可离开。
5. **观察缓存与配置意图分开。** 设备在线状态、接收缓存、统计值不触发用户配置冲突；现有 configurationData 已排除一部分缓存，应扩展成统一且有版本的语义模型。
6. **未知字段透传与能力标记。** 旧版不认识的新配置不能在重存时丢弃；新 App 的改进无法约束所有已发布旧 App，需要后端配合保护。
7. **提供可解释的诊断。** 记录脱敏身份摘要、导入阶段、生命周期代际、原因码、数据完整性和修复摘要；错误分别报告网络、权限、存储、待恢复、真正冲突。只在 DEBUG 打印必要日志，不输出完整密钥。

### P2：后端参与，解决竞态而不是只改善提示

当前客户端可见协议仍主要以整 Space 数据和 updateTimestamp 同步；样本的 versionSEQ=-1 不能被当作可靠的并发条件。源码未看到可证明后端原子比较并提交的 baseRevision 契约，不能宣称后端完全没有并发控制。

建议与后端明确：

- 服务端单调 revision/ETag；上传携带 baseRevision，原子比较成功后分配新 revision，否则返回冲突与当前 revision。
- operationId 幂等提交；可查询未知结果。客户端本地 submission UUID 目前不等价于服务器幂等键。
- GET 返回完整性标记、schema/capabilities、revision；若分页，所有页必须属于同一快照，缺页不得当删除。
- 提交成功返回对应 revision 与内容摘要；解决已写入但响应丢失、读到旧副本、其他端随后修改等歧义，不把连续 GET 不相等自动当作自己上传失败。
- 成员解绑、编辑权限版本和配置版本分开。解绑只要求有退出自己成员关系的资格，不依赖解码完整配置。
- 旧客户端写入需保护它不认识的新字段，或由服务端转成有明确作用域的操作。仅新 App 做上传前 GET 无法防止 GET 与 POST 之间另一台手机提交的竞态。

P0 可独立修复本次；P1 改善多数兼容/冲突体验；P2 才能为并发写入建立端到端保证。无须等 P2 才放出本次修复。

## 6. 快速复现与验收

### 当前问题的操作复现候选（建议测试 Space）

1. 手机 A 为 Owner，手机 B 为 Editor，B 曾成功进入目标 Space。
2. B unbind 并完成本地删除；或 A 回收 B 权限，B 完成本地移除。此步制造真实子网的 retired 记录，保留安装及账号。
3. A 再分享同一个 Space，B 通过单 Space 分享入口重新接受 Editor。
4. B 进入 Site 后点击该 Space；记录首次导入原因，再点击一次并尝试 unbind。
5. 观察是否出现：持久化 subNetworkKey 空、内存真实子网、retired、lastUpdate=0；首次可能是 configurationStagingFailed，之后是 spaceRemovalPending，unbind 请求未发出。

无需先造 500 台设备；该根因发生在数量校验之前，少量设备也能验证。Site 整体恢复、重启、缓存是否存在会改变入口顺序，因此完整 UI 复现仍需按日志确认，不能把一次未重现判为不存在。

### 已执行的隔离复现

复用 `scripts/check_space_recovery_receipts.py` 的生产代码提取方式，在临时脚本 `/tmp/space_sync_analysis_probe.py` 增加探针，未修改仓库测试或业务代码：

- normal Editor，lastUpdate=0，phase=retired：`update=spaceRemovalPending`、`needUpload=false`、`pendingUpload=false`、`beginUnbind=nil`；进入的云端预检调用数为 0，探针网络调用数为 0。
- 用既有 activateImport 建立新代后：导入前缀可继续、beginUnbind 可取得上下文。只证明边界恢复，不代表完整设备导入成功。
- 真实子网 retired，同 Space 创建空 networkId 占位并 activate，再将 networkId 切换回真实子网：真实 phase 仍 retired，beginImport=false，beginUnbind=nil。
- 云端原始样本运行生产 Profile 和清理校验：profilesIssue=none，devices=500，repairs=0，orphanSubscriptions=0，hardErrors=[]。
- 复用的现有恢复回执/导入准备用例通过。未执行 UIKit、SQLite 完整导入、SDK Node 全量解码或真机体验验收。

### 实施时必须覆盖的回归

| 操作 | 修复后期望 |
|---|---|
| 首次加入、同 Space 离开再加入 | 规范身份一致；正确建立新代；完整恢复 |
| 多个同 Site 空占位 Space | 恢复状态不串用，不因空 networkId 冲突 |
| 导入身份准备后强退、落库失败后重启 | 恢复进度可重放，内存/DB 不长期分裂 |
| 导入进行中 unbind/重入 | 旧结果失效；新实例不被旧回调删除 |
| 本地空壳直接 unbind | 不上传空数组覆盖云端；解绑可完成 |
| 本地修改未上传，用户选择离开 | 本地副本保留；成员关系解除；停止旧上传 |
| unbind 成功响应丢失、确认后本地清理失败 | 能查询确认并继续，状态与文案准确 |
| 有效空 Space、无旧基线、有旧基线的显式清空 | 三者不混淆 |
| 旧版缺字段、合法空地址/ALL | 自动兼容；不会把新配置重置成默认 |
| 两台手机同时改独立对象 / 同项冲突 | 前者自动合并；后者只限制相关项 |
| 网关/设备缓存变化但配置不变 | 不触发配置冲突 |
| 账号切换、权限回收、密钥身份冲突 | 不自动复活旧权限，不控制错误网络 |

当前受困账号的临时出口：Owner 回收该 Editor 成员关系可从服务器释放占用，但仍需修复客户端重新加入流程。不要用本地空壳覆盖云端；重试相同 GET 通常无法改变 retired；卸载清数据会影响本机其他未同步数据，不作为默认解决方案。

## 7. 源码定位与交接

- `SunSmart/Common/Data/ImportData.swift`：SpaceData.import、update、身份切换、导入 rejected 原因。
- `SunSmart/Common/Data/SpaceConfigurationSafety.swift`：恢复作用域、activateImport、archiveDeletedSpace、beginUnbind、uploadBeforeUnbind、beginImport。
- `SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift`、`SpaceSyncCleanupPolicy.swift`：样本实际运行的校验。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`：进入、未恢复基线防护与 unbind。
- `SunSmart/Main/Space/Controller/SpaceViewController.swift`：另外两处通用错误文案。
- `SunSmart/Main/Share/Controller/SharePermissionSelectionController.swift`：单 Space/批量分享占位记录。
- `SunSmart/Common/Data/Database.swift`、`MeshNetwork+SunSmart.swift`：持久化、删除归档、解绑前资源回收副作用。
- `SunSmart/Common/Cloud/DebugCloudJSONExporter.swift`、`DebugCloudJSONRecords.swift`：内存副本、数据库记录与恢复状态的读取范围。

工作树：`sun-smart-worktrees/fix`，分支 fix。开始调查时 HEAD 为 999be5fa，SiteViewController 存在其他任务未提交修改；期间该导出功能由其他任务提交为 5f638c8f，分析结束以该 HEAD 为准，未修改或覆盖其改动。

本地 SDK 映射为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD a6246b1，存在其他任务的 Mesh 时间相关未提交改动；本次未使用新 SDK API、未改 SDK。分析未构建 App、未运行真机。

下一步：用户确认第 8～10 节后实施第一阶段；第二、三阶段另行确认契约与范围。当前交付为分析及可评审实施计划。

## 8. 待确认的实施范围与产品行为

### 8.1 分阶段交付

| 阶段 | 交付内容 | 本次请求确认的范围 |
|---|---|---|
| 第一阶段：恢复与退出闭环 | 身份初始化、历史 retired 恢复、导入一致性、入口降级、独立解绑、地址回收与回执、明确提示、行为回归 | **建议完整实施** |
| 第二阶段：可证明安全的自动协调 | 扩展语义规范化、基线比较、局部冲突展示、已知字段/实体的合并候选 | 后续独立实施；不随第一阶段顺手加入整 Space 自动覆盖 |
| 第三阶段：跨端并发协议 | 服务端 revision、幂等回执、成员权限版本、旧客户端兼容写入 | 需要后端配合，不能由本仓库单独交付 |

第一阶段必须既让当前样本恢复，又给恢复不了的用户一个可用出口；不能只修重入而保留解绑死锁。共享行为覆盖 Owner/Editor/Visitor 的正常边界，但只给拥有退出权限的 Editor/Visitor提供成员解绑；Owner 的删除/转移职责保持现有语义。

### 8.2 建议确认的界面行为

| 用户遇到的情况 | 第一阶段行为 |
|---|---|
| 本例：合法云端、空占位、历史 retired | 自动重新准备身份与恢复代际；成功后正常进入，无需用户选择“云端还是本地” |
| 拉取失败，有可信本地快照且权限/身份仍允许 | 可查看已有数据，显示未完成同步；保留经确认安全的既有控制能力，冻结受保护配置写入 |
| 没有可信副本，或无法确认身份 | 打开轻量恢复状态页，提供 Retry、Leave Space、Back；不显示可配置的假空 Space，不启动 Mesh 控制/同步 |
| 已有完整副本，但 Profile/拓扑检查失败 | 保留已有完整副本；本期继续沿用现有配置保护范围。精细到单个 Group 的编辑解锁放入第二阶段 |
| 没有未同步修改，用户 Leave Space | 直接解绑成员关系，不先上传 Space，不要求云端配置可导入 |
| 有未同步修改，正常同步失败 | 展示 Retry Sync、Keep a Copy and Leave、Cancel；保留副本后离开需要用户在 App 内明确选择 |
| 离线选择离开 | 保存退出意图，页面明确显示 Waiting to Leave，联网后处理；列表保留可见状态入口，不立即隐藏导致用户找不到进度 |
| 服务端已确认退出，本机清理失败 | 显示已退出、待完成本机清理，后台重试清理；不再上传，不再提示云端同步失败 |

界面复用项目导航、提示/动作组件与现有恢复能力；无可信副本时使用独立轻量状态页，避免把未初始化对象交给 SpaceViewController 的设备与 Mesh 生命周期。现有 `ConfigurationFlowGuidanceView` 是配置流程说明，不强行改作恢复页面。

“保留副本”必须区分完整可恢复配置和仅能诊断的原始记录：已验证完整的副本可供后续恢复；无法完整导出的情况保留原始配置与日志，并明确其用途。不能把 `_debugInspection` 文件标成完整备份，也不能让 Release 用户依赖 DEBUG 导出入口。副本入口在退出后仍能访问，且恢复必须重新取得当前权限，不能后台自动上传归档。

若本机存储失败，不能显示“副本已保留”；提供重试/取消，或用户明确同意不保留本机修改后在线离开。该例外不得默认为丢弃，也不能承诺未落盘的退出意图在重启后仍存在。

## 9. 第一阶段执行计划

按以下顺序实施，阶段内由同一写入负责人集成。每个工作包完成对应验证后推进；不在每个工作包结束时重复索要已经确认的实施授权。

### 工作包 A：固定身份与恢复代际

**主要位置：** ImportData、SpaceConfigurationSafety、SpaceData、分享加入入口、SpaceRecoveryState 所在文件。

1. 定义一个导入准备结果，携带已解析的目标身份、请求/账号上下文、初始化状态及失败分类。所有网络入口携带请求开始时的上下文，不能只在响应回来后读取“当前账号”。
2. 单分享、批量分享的占位记录显式按未初始化处理。不得仅通过设备数为 0 或时间戳为 0 推断用户已清空配置。
3. 对完整响应先验证 UUID、密钥结构与绑定关系，解析 canonical networkId，再访问该身份的恢复记录。停止在导入中段修改工作对象的 networkId。
4. 复用 activateImport、generation 和归档：当前授权的首次初始化/重新加入可激活 retired；正在删除或解绑的上下文不能被普通 GET 重启。
5. 已有正常配置沿用其身份；真实身份变化进入独立错误/既有密钥更新处理，不自动搬移设备与删除记录。
6. 对历史空/占位 networkId 的记录做幂等修复。规范子网恢复记录保留现有文件键；占位对象不创建子网级恢复文件。历史空作用域文件仅在 ownership 可验证时归档，不合并不同 Space 的回执。
7. 引入小范围、按 account/region/siteId/spaceId 隔离的成员操作记录，用于新加入意图和退出意图，不依赖 networkId；复用现有原子落盘与保护方式。用于杜绝多个空占位串状态，并连接工作包 C 的退出恢复。

**完成标准：** 真实子网 retired + 数据库占位记录能够建立正确的新代际；同 Site 两个占位互不影响；旧 GET、旧上传和账号切换后的回调不能激活或写入新实例。

### 工作包 B：导入提交一致性与上传资格

**主要位置：** ImportData、Database、ExportData、SpaceConfigurationSafety、SpaceSyncCleanupCoordinator。

1. 以准备好的固定身份和候选对象进行预检、暂存与导入；写入前再次检查成员操作/恢复代际。
2. 复用 pending-import、configurationTransaction 和持久化回读，明确初始化完成的提交点；只有完整保存成功才发布新的页面对象、成功基线和初始化状态。
3. 现有 `configurationTransaction` 只覆盖 App SQLite savepoint，不跨 Mesh 数据库和恢复文件。跨存储仍通过持久化导入意图、幂等重放和最终回读衔接，不能把它当作多库原子事务。
4. 失败时保持可信旧副本，或保持明确的待恢复状态；进程内候选对象不能泄漏成已完成对象。崩溃恢复不恢复整库旧文件，不回退 Mesh sequence/IV 或其他 Space。
5. 未初始化/正在退出的 Space 在单 Space 上传、Site 批量上传和后台恢复入口均不可被当作完整配置发送。Site 同步不因排除一个 Space而生成服务端会误解为删除的请求；沿用并核实当前接口对 spaces 列表的更新语义。
6. 兼容合法空 Space：初始化成功的空配置正常可用；已有基线的明确清空仍可同步。

**完成标准：** 当前云端样本导入后维持 500/17/2 数量与业务配置；失败注入不会把空数组上传；重启可继续未完成导入；内存/数据库/恢复身份不再分裂。

### 工作包 C：解绑独立完成，资源回收可重试

**主要位置：** SiteViewController、SpaceConfigurationSafety、CloudSynchronizationManager、MeshNetwork+SunSmart、现有网络请求类型。

1. 持久化退出意图后阻止该成员代际产生新的配置写入。成员操作记录表达 queued/requesting/unknown/confirmed/cleanupPending 等必要结果，不用配置 active/retired 作为能否请求退出的资格。
2. 没有本地修改时不运行 uploadBeforeUnbind。有本地修改时保留正常同步路径；失败后由用户选择保留副本并离开，归档成功才清除对应活动上传意图。
3. 协调单 Space 和包含它的 Site 批量同步：停止/等待相关任务到可判定边界，保留其他 Space 的待同步工作。取消 Task 不当作服务器未收到请求的证据。
4. 分离地址回收的只读计划与提交后清理。基于同一份 Site/provisioner 快照计算、持久化本次回收范围；准备时不移除手机节点、不改变当前 allocated ranges/localAddress。
5. 复用现有解绑请求。完整且可证明安全的回收信息按现有契约一起发送；恢复配置不完整时，不从缺失设备推断地址未使用。是否允许省略回收字段、如何保留或延后回收，须先以既有接口说明/测试环境确认。
6. 解绑响应成功先保存确认，再清理本地与回收相关状态。失败不提前删除本机配置；结果未知保留 intent，通过能够证明成员资格的结果核对，而非仅以 GET 能否返回配置判断是否仍是 Editor。
7. 403/不存在仅在账号、请求身份及错误语义足以证明该成员关系已消失时视为完成；密码失效、通用登录过期、网络错误不得当成已解绑。
8. 应用前台/重启复用现有 pending recovery 入口恢复退出，按 account/region 隔离。退出 intent 未确认前不发起同一成员的重新加入，以免迟到的解绑删除新关系；保留状态入口和核对操作。
9. 服务端已收到的旧写入/解绑无法由客户端取消保证失效。第一阶段保证本机不再新发、旧回调不污染本机，且不冒充请求成功；服务器重入/迟到写入的强保证列入第三阶段成员版本契约。

**完成标准：** retired/空壳可发起真实解绑而不上传；解绑失败不破坏手机地址与配置；结果未知和确认后清理失败在重启后可继续；不会为退出一个 Space 丢掉其他 Space 的同步。

**外部契约检查是实现内的明确关卡：** 当前仓库只能证明客户端参数可选，不能证明服务器支持所有省略组合或请求幂等。优先查现有契约及安全测试环境；若没有可验证证据，不在生产 Space 试探写接口、不声称后端已兼容。继续完成 A/B/D/E，可把对应服务端问题和精确请求形态交付；涉及服务器行为的能力单独标注待验证。

### 工作包 D：进入降级、明确原因与可用操作

**主要位置：** SiteViewController、SpaceViewController、SpaceData、轻量恢复状态页、英文/简体中文 strings。

1. 将导入结果区分为可正常进入、可查看旧副本、需恢复状态页、授权待处理、已退出；保留底层原因码，不再把所有 rejected 翻译成云端损坏。
2. 复用已存在的 Profile/拓扑保护，统一 UI 和命令入口的能力判断。不能只隐藏编辑按钮而让后台同步、通知回调或 Mesh 自动配置继续执行。
3. 本地快照可用性同时考虑完整性、身份、权限和恢复状态；单凭 lastUploadCloudTimestamp 非空不足以证明当前副本可信。nil 防护改为路由恢复状态页，不直接放行空壳。
4. 所有恢复页均可返回；Editor/Visitor 可进入解绑流程；Owner 显示对应的恢复/管理入口。刷新、密码验证和 Site 自动进入也采用相同结果处理。
5. 最新请求因并发失效时最多自动重新准备一次；取消/离开页面不显示云端数据损坏；持续变化给出可重试状态，避免无限循环。
6. 文案在 en/zh-Hans 同步添加，区分恢复未完成、需重新授权、存储失败、待联网退出、已退出待清理。长文案、按钮复用、iPad 展示和生命周期纳入人工验收。
7. DEBUG 诊断增加阶段、原因、规范身份与持久化身份是否一致、成员/恢复代际摘要；不记录密码和完整密钥。导出诊断补充初始化及退出状态，避免 issues=[] 被误读为全部正常。

**完成标准：** 本例自动恢复后进入正常页面；任一导入失败仍有明确恢复/返回/退出入口；配置保护只控制相应能力，不再决定整个导航是否可用。

### 工作包 E：回归、构建与交付

1. 在现有 Tests/Group 和恢复脚本中加入行为测试。将上一轮临时探针转为固定复现用例，覆盖真实身份解析、持久化及切换后操作，不只断言源码包含某个 guard。
2. 新增故障注入边界：身份准备后强退、App 保存失败、Mesh 保存/回读失败、退出请求响应丢失、退出确认落盘失败、本地清理失败、旧请求晚到、账号切换。
3. 数据夹具使用脱敏/合成身份与密钥，不提交原始现场 JSON。原始 500 节点样本只在本机验证兼容和数量；真实导入/性能结论需要运行证据，不以策略测试代替。
4. 相关验证优先复用 `check_space_recovery_receipts.py`、`check_space_sync_cleanup.py`、`check_space_protection_snapshot.py`、`check_space_sync_readback_reuse.py`；涉及路径时运行 Site/Space mesh ownership、overlay cleanup、删除恢复等对应检查。源码契约检查只作补充。
5. 修改稳定后构建一次 SunSmart：SunSmartLocal.xcworkspace、Debug、generic iOS、CODE_SIGNING_ALLOWED=NO，使用 fix 工作树稳定 DerivedData 目录。先重新确认 workspace/SDK realpath，记录共享 SDK 的实际 revision 和未提交差异；不修改 SDK 时间功能。
6. 本计划预计新增/修改共享页面和本地化资源，核对五品牌 target 归属；合入前覆盖 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的受影响 Debug 构建。不默认跑 Release、Simulator，也不因通过构建宣称真机通过。
7. 真机由用户验收，默认不安装不运行。最短验收：首次加入 → 退出 → 同 Space 重入；历史受困样本恢复；拉取失败进入状态页；未上传编辑保留副本后离开；退出过程中断网再恢复。
8. 最终记录已验证、待人工/后端验证和兼容边界；若某项契约未验证，不能宣布该项完整通过。

建议按“身份与导入”“解绑与资源回收”“入口与提示”“补充回归”组织可审查改动，依赖测试可随对应修复提交。是否创建提交遵循后续用户指令，不在仅批准计划时自动合并或发布。

## 10. 第一阶段验收清单与确认项

| 编号 | 必须达到的结果 | 主要证据 |
|---|---|---|
| A1 | canonical 身份在任何恢复状态操作前确定；占位记录互不串用 | 身份/持久化行为测试 |
| A2 | 历史 retired 的合法重入成功，旧回调不能复活退出对象 | generation/成员上下文测试 |
| A3 | 本例 500/17/2 可恢复，合法空 Space 不被误判 | 真实样本验证与正常空配置用例，App 运行另验 |
| B1 | 无完整基线的占位 Space 从不上传空配置 | 单 Space、Site 批量与后台路径测试 |
| B2 | 导入中断可恢复，其他 Space 和 Mesh 序号不回退 | 故障注入与作用域验证 |
| C1 | 无未同步修改的 Editor 可退出，不依赖配置导入成功 | 请求捕获与状态机行为测试 |
| C2 | 有修改时可在保存副本后退出，副本退出后仍可访问 | 归档/访问测试与人工验收 |
| C3 | 退出失败不提前回收地址；未知结果与确认后清理失败可续做 | 失败/重启测试，服务器契约验证 |
| C4 | 同 Site 其他 Space 的同步与地址仍完整 | 批量同步和多 Space 回归 |
| D1 | 导入失败仍能查看恢复状态、返回或选择退出 | 路由测试与人工 UI 验收 |
| D2 | 权限/身份不确定时不能借恢复入口控制或上传 | 负向行为测试 |
| E1 | 相关自动化及受影响构建通过；运行/后端未验项如实列出 | 命令结果和人工记录 |

本次建议确认的默认决策：

1. 完整实施第一阶段 A～E；第二阶段整合并和第三阶段后端协议单独推进。
2. 恢复失败允许进入状态页；有可信副本时允许查看，不自动解除配置写保护。
3. 同步失败后允许用户选择保留本机副本并离开；不默认丢弃未同步修改。
4. 离线退出显示待完成，并保留可见入口；服务器确认之前不显示已退出。
5. 真机验收仍由用户执行。本次计划确认不包含线上数据修复、自动真机操作、合并或发布授权。

以上范围已由用户确认并开始实施。

## 11. 第一阶段实现与验收记录

### 11.1 已实现的客户端行为

- `SpaceMembershipCoordinator` 先解析规范子网身份，再准备恢复代际；通过候选对象导入，完整提交后发布内存对象。历史 retired 的旧 `unbindRequested` 不再封锁重新加入；正在 removing 的实例仍受保护，交由已有删除恢复流程完成清理。
- `SpaceMembershipStore` 按账号、区域、Site、Space 保存成员状态与代际，使用原子文件和比较后写入。未初始化占位、退出中实例及没有成功基线的新占位均不可上传。
- GET 请求记录开始时的账号/区域/成员上下文；加入、退出及本地删除使旧上下文失效。导入、Site 子任务回收和恢复回执在异步边界重新核对上下文。失效的进入请求最多重新拉取一次。
- 退出流程独立持久化 queued → requesting → unknown/confirmed → left。有未确认修改时先尝试正常同步；失败后允许明确选择保留副本再退出，副本写入失败还可重试、取消或明确选择不保留。不能保存退出意图时仍报告存储失败，不假称重启后可续做。
- 离线退出保留可见状态；联网/前台恢复。未知结果先查询成员资格，随后重试同一成员的退出。密码错误/密码过期不等于已退出，也不再阻止独立退出请求。通用登录错误不视为成功。
- 服务端成功先落盘 confirmed，再执行本地删除；失败保留 confirmed，只重试清理。退出会暂停关联同步任务并重新排队其他 Space；旧配置回调不再写回退出对象。
- 无完整副本时使用独立恢复页，不启动假空 Space 的 Mesh 生命周期。恢复页提供 Retry、Leave Space（非 Owner）、Saved Space Copies 与导航返回。既有完整对象沿用原有权限及配置保护。
- Release 可保留按 Space 限定的原始数据库记录；可导出时同时附带配置内容。副本有完整性标记，不把诊断记录冒充完整配置；Sites 菜单和恢复页均可分享已保存文件，退出后仍可访问。副本不会自动上传，本期未增加一键覆盖恢复入口。
- 新源码与英文/简体中文资源接入五品牌。没有修改 Nordic SDK 或正式远端依赖。

### 11.2 地址回收与服务端验收边界

客户端准备地址回收计划时使用独立 Provisioner，不提前删除手机节点、不改 live allocated ranges/localAddress。仅当 Site 当前只有这个 Space、它已有完整初始化且未受配置保护时，随退出携带已有算法计算的回收计划；同 Site 有其他 Space 或本地配置不完整时保留地址租约，不猜测哪些地址未使用。

不完整配置的实际请求形态为现有 `unbindSpaces`：`siteId`、`spaces: [spaceId]`、当前 `userId`、`addrLists: { device: [], group: [], scene: [] }`；不附带 `provisioner` 与 `exclusions`。**尚未在测试服务器验证该形态。** 仓库中的客户端编码能力不是服务端验收证据。如服务器拒绝，客户端保留退出意图与数据并展示错误，不能宣布已解绑。

现有明确业务错误 4004/4008/4009 沿用项目既有成员失效处理；其严格服务端含义与重试幂等仍需后端确认。通用 401、配置密码失败、超时、断网不会被当作成员退出成功。服务端需要防止迟到写入或跨设备重新加入后的旧解绑；这一强保证仍需要第三阶段 membership revision/条件写契约。

保留租约时也保留 Site 的本地传输状态；本期不自动清掉空 Site，不自动归还无法证明安全的地址。后续地址归还需要明确服务端契约，避免以“清理干净”为由破坏其他配置。

### 11.3 自动化与构建证据

已通过的行为/隔离检查：

- `check_space_membership_lifecycle.py`：生产成员存储、规范身份准备及退出协调；覆盖双占位隔离、retired 重入、空对象上传屏障、保存失败、旧回调、离线/未知/确认后清理重试、配置密码错误、显式 Site 接收和账号切换。SDK 解码、Mesh 实际导入、HTTP 与 App DB 为受控测试边界。
- `check_space_recovery_receipts.py`：生产回执与导入前置检查，覆盖版本/权限变化、异步失效、导入中断、保存失败、上传结果未知及重试。
- `check_space_sync_cleanup.py`、`check_space_sync_readback_reuse.py`、`check_space_protection_snapshot.py`：清理、回读及保护读取。读取次数测试是隔离结果，不作为整 App 性能结论。
- `check_debug_json_export.py`：原始记录读取、敏感账号字段排除、作用域/账号保护与文件行为。
- `check_configuration_database_safety.sh`（指定现有本地 SDK）：真实 SQLite WAL 快照、保存点回滚、连接失败与旧 Profile schema。
- `check_site_space_mesh_context_ownership.sh`、`check_space_delete_cloud_restore.sh`、`check_space_main_overlay_cleanup.sh`：入口/删除恢复/overlay 契约补充检查。其中 Mesh ownership 的旧源码断言未匹配当前 HEAD 的 `nodes:` 参数，本次仅修正该断言以匹配已有行为。

构建入口为 `SunSmartLocal.xcworkspace`，Debug、generic iOS、关闭签名，稳定 DerivedData 为 `SunSmart-fix-cli`。SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 均构建成功；最后的共享逻辑收紧以 SunSmart 增量构建及生命周期/回执行为测试复核，未增加品牌专属路径。工程和两种语言 strings 的 `plutil` 检查、`git diff --check` 通过。未执行 Release、Simulator 或真机安装运行。

App 分支 `fix`，基线 HEAD `5f638c8fd2c8d19f2e81a63514ed0deba0646421`，全部本次修改尚未提交。`.local-sdk/nordic-sig-mesh-sdk` 指向 `nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `a6246b1b0409824a3227a9c7cad8140219feb182`；其已有 Mesh time/ExplicitTimeSet 未提交修改属于其他任务，本次未改动。没有引入新 SDK API。

原始 500/17/2 样本的生产 Profile/清理策略结果复用第 7 节证据；本轮未将原始密钥或 JSON 加入仓库。**完整 App 导入该样本、500 节点实际体验和线上解绑尚未验收。**

### 11.4 最短人工验收

1. 使用历史受困 Editor 打开 Space：应自动按规范身份恢复；成功后核对 500 个设备、17 个实体组、2 个场景，再退出 App 重进核对持久化。
2. Editor 正常加入 → Leave Space → 再次加入同一 Space：不再被历史 retired 状态拦住。
3. 在测试环境让云端拉取失败：没有完整本地副本时能进入恢复页、返回、重试及请求退出；不能编辑/上传假空数据。
4. 制造未同步编辑并阻断上传，选择 Keep a Copy and Leave：退出后在 Sites 菜单查看/分享副本；诊断副本与完整配置标记明确。
5. 退出时断网/杀进程，重开并恢复网络：未确认前显示待退出；已确认但本机清理失败时只重试清理。测试环境丢弃退出响应，再核对没有重复破坏新成员关系。
6. 同 Site 另有正常 Space 时退出异常 Space：核对正常 Space 配置、地址分配和待同步工作仍在；恢复页英文/中文、大字体及 iPad 分享另作 UI 验收。

客户端自动化、编译、真实 App 验收和服务器契约是不同层级的证据。后两项完成之前，不将本阶段描述为所有跨 App 同步问题已消失。
