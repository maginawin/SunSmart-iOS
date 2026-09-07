# Proximity / Predictive Lighting 两类 Profile 全链路分析与修复确认

日期：2026-09-07。**本轮只分析，不修改业务代码，不执行真实设备、服务器写入或 Git 操作。**

## 1. 范围、基线与结论

- 当前工作区：`trigger-zone-sep`；分析基线 HEAD 为 `3e7c9a3785b1af51144aeba88c43aa046badc20f`，同时检查已有删除恢复改动。分析期间这些已有文件被其他操作暂存，部分测试也继续变化；本轮没有暂存、回退或覆盖它们。本报告针对本轮实际读取的源码，不代表其他并行修改的最终交付状态。
- 旧版参照：仓库中既有兼容分析使用的 `954c51999a5be2e24d7d56f0def0e87a2bd8a2be`（1.2.0）。本轮重新读取该提交的导出与设备同步实现。其他已发布版本须补版本号/提交后加入验收，不能把一个旧版的结果推广到全部历史版本。
- SDK：当前 Package.resolved 锁定 `86f5ec9e40148b9cd93e0512702337fcec41dd40`。已按该 revision 核对数据库与 Group.nodes 实现，而不是直接把本地 one-dev 或其他 DerivedData checkout 当作发布版本。
- 范围包含 Profile 7 / Profile 8、Group Path、Group Trigger Zone、Site → Space → More → Trigger Zone，以及成员/设备删除、恢复、云导入导出、跨 Site/Space 身份、权限与同步确认。

**结论：正常的新版本拓扑计算已有实质修复，但目前还不能保证用户提出的全部兼容与不循环要求。** 有四项当前删除恢复改动引入的闭环缺口建议先修；另外，新旧读写协议和旧端设备算法存在既有边界，不能靠清除新 App 的同步提示解决。

特别区分：

1. 配置逻辑完整、云端已确认、真实设备已配置是三个状态，不能互相代替。
2. 新 App 的本地保护不是服务器上的“新版写入优先”。
3. 同一 UUID 出现在不同 Site/Space 本身不是错误；设备重置后保留真实 UUID 是正常输入。
4. 一台普通灯重配进入另一个 Mesh 后，旧 Mesh 不再能控制它、因而存在待同步设备，是物理状态差异；这与 App 的云同步死循环不是一回事。

## 2. 已有正确处理，不建议推倒重做

| 功能 | 当前处理 | 本轮评价 |
| --- | --- | --- |
| 两个 Profile 的身份 | 7 为 proximityLighting，8 为 proximityLightingWithPhotocell | 不需要重编号或将旧类型映射为其他 Profile |
| Group Path | 只连接相邻非空槽位；同一设备可有意重复出现 | 空槽不能当失效设备删除；不能跨空槽自动连线 |
| Group / Space Zone | 有效成员形成邻居集合，与 Path 取并集并去重 | 正常新端不应再互相覆盖两类邻居来源 |
| Relay | 来自设备所属合格 Group 的 Profile | Space Zone 不应另建一份 Relay 权威值 |
| 设备地址 | 使用 vendor model 所在 Element 地址归一化 | 不能只用 Primary 地址判断 Path 中设备是否存在 |
| 容量 | 统一上限 184，超限不生成该目标的破坏性修改 | 保留防线；不能靠截断数组消除 Sync 提示 |
| 不完整上下文 | unavailable 不等于空拓扑；不生成 Disable | 这是必要保护，不应为了“无提示”移除 |
| 导入失效拓扑 | 有本地数据时保留；无可用本地数据时尽力导入基础信息并保持保护 | 不能把基础信息可见称为完整恢复成功 |
| 保存数据库 | GroupInfo/Profile 事务与 Profile 回读；加载失败不再当默认 Profile 正常导出 | 已有保护应保留 |
| SAVE | Group 和 Space 页面走共同生命周期与完整拓扑任务 | 不等同于 AUTO；不要额外发送强制开灯命令 |
| 删除 | 新 context 捕获网络及 Space；持久化删除意图；只清理确认删除集合 | 方向正确，下面需补确认与退出生命周期 |

主要源码：`GroupProximityLightingData.swift` 的 Context/Planner、`ProximityLightingTopologyPolicy.swift`、`ProximityLightingTopologyReconciler.swift`、`ProximityLightingLifecycleCoordinator.swift`、`Node+SyncData.swift:1621`、GroupPathSequencePageController.saveAction、SpacePathTriggerZoneController.saveAction、Database.swift:1031–1065。

## 3. 当前改动新引入：建议优先修复

以下 A1–A4 可独立修复，不要求改真实 Device UUID，也不应通过关闭拓扑完整性校验来解决。

### A1｜P1：删除后重新添加，已确认上传仍不能结束删除回执

**源码证据**：`DeviceScheduleAddressCleanup.swift:52–56` 要求提交中不含旧 UUID，且不复用旧 Element 地址，才移除 cleaned 回执。`SpaceConfigurationSafety.swift:109–112` 又把任何残留回执当作拒绝远端导入的条件；`resume` 跳过 cleaned 项。

**复现步骤**：

1. 新 App 在 Space A 添加设备 D，建 Profile 7/8 的 Group，配置 Path/Zone，并正常同步。
2. 手机断开互联网但保留 BLE，在 A 删除 D，等待本地拓扑清理完成。
3. 在联网上传之前，把重置后的 D 重新添加到 A；使用新的单播地址也能触发，因为真实 UUID 不变。
4. 恢复网络，完成上传和逻辑快照 GET 回读。
5. 另一手机修改 A 的 Group 名称/Path，再让本机刷新 A。

**结果**：上传可以成功，cleanup 也不是 pending，但旧回执一直存在；之后的远端快照被 `localDeletionOrRecoveryPendingUpload` 跳过。可能表现为本机始终不更新而非始终显示红色 Sync 图标。不同 UUID 重用旧地址也有同类问题。

**验证**：本轮直接执行生产 `SpaceDeletionJournal`：正常删除快照确认后剩余 0 条；同 UUID 新地址重新添加后确认仍剩余 1 条；另一 UUID 复用旧地址后仍剩余 1 条。

**建议**：删除意图绑定入网世代/被删除实例；显式重新配网应使旧删除意图被后续本地操作取代。确认时核对本次操作版本及已回读的完整当前快照，不以“该 UUID 必须永远不存在”作为终止条件。旧的、尚未完成物理/本地清理的删除不能随意清除。

### A2｜P2：首次 Site 上传成功，没有结束该 Site 下的删除回执

**源码证据**：`CloudSynchronizationManager.swift:877–879` 对 siteAdd 跳过配置回读；新增的 `confirmSpace` 只在 verifiedConfigurationIds 包含目标 Space 时确认本地回执（914–916），但仍更新 lastUploadCloudTimestamp。setOwnerProvisioner 只调整资源，没有补回执确认；后续二次提交的旧注释代码并未执行。

**复现步骤**：

1. 无互联网时创建 Site/Space，添加设备、配置 Group，然后删除其中一个设备，完成本地清理。
2. 恢复网络，让首次 Site 创建上传成功。
3. 保持本机无新编辑，由另一手机修改同一 Space 的 Path/Zone 后，本机重新进入。

**结果**：Site/Space 已被标记上传成功，不一定再排队上传，但删除回执仍阻止远端数据应用。后续一次额外有效上传可能解除，不能因此视为初次上传闭环正确。

**建议**：在首次创建和资源调整完成后，执行受控的配置回读与回执确认；或者持久化一个必定执行的待确认任务。不能不验证就确认，也不能标记全部同步完成后依赖用户偶然再编辑。

### A3｜P1：解绑前直接上传绕过回执确认，重新导入可能被旧回执锁住

**源码证据**：SpaceViewController.unbindSpace（约 880–900）直接调用 spaceUpload，只更新上传时间戳，不经过 CloudSynchronizationHandle.confirmSpace。解绑成功后 `MeshNetwork+SunSmart.swift:461–486` 删除 Space/Mesh/扩展数据，但没有归档或清理新建的删除日志。相同账号/区域/meshUUID/networkId 下重导入仍读到该日志；ImportData.swift:1458–1462 在 initialize 分支执行前返回 skipped。

**复现步骤**：

1. B 以 Editor 导入 A 分享的 Space，离线删除 D，完成本地清理。
2. 恢复网络并在正常后台上传尚未完成时操作 Unbind；该入口会取消已有同步并直接提交待上传快照。
3. 等待解绑成功和本地数据删除完成，再以相同账号重新导入同一 Space。
4. 检查 Space 的 Groups/Path/Zone 是否实际落库，而不只检查是否返回了 Space ID。

**结果**：旧 cleaned 回执仍存在；resume 不处理它，新的 initialize 导入被当作“保留本地修改”跳过，然而原本要保留的本地配置已经被解绑删除。

**建议**：解绑前上传纳入共同回读/确认入口；成功解绑或明确丢弃本地 Space 时，按身份及生命周期归档旧恢复状态，避免它影响新的一次导入。保留诊断备份可以，但不能让归档继续作为活跃拦截器；也不能在解绑尚未成功时提前丢弃删除意图。

### A4｜P1：保留本地配置时，也跳过了远端权限和密码变更

**源码证据**：新增早退在 ImportData.swift:1459–1462 / 1470–1472；远端 role、访客保护、owner/editor、userEvents 的处理在约 1594–1665，因而不会执行。现有 Space 的 import 入口也不会事先刷新 role。

**复现步骤**：

1. B 为 Editor，离线删除设备或选择本地恢复，尚未完成服务器确认。
2. A 修改该 Space 的编辑权限/密码，使 B 后续 GET 中出现 role 变化或 EditorPasswdChanged（需要接口联调确认返回形态）。
3. B 恢复联网并读取 Space，检查响应确实携带变化，同时检查本地 permission / requiresPasswordVerification。

**结果**：只要回执仍在，本机整个响应被跳过，仍保留旧权限/密码验证状态；若新权限已不允许上传，则“先上传才能解除导入保护”的策略也无法自然完成。服务器可能另行拒绝请求，心跳也可能稍后通知失权，不能据此认为该 GET 的权限处理正确。

**建议**：将认证授权及服务端状态元数据处理与逻辑配置合并分开。先验证响应身份、应用权限/密码事件，再决定是否保留本地拓扑；失权后的待上传操作应进入明确只读/归档/待重新授权状态，不能继续循环上传。测试 GET 仍为 200 且含变化、以及接口直接返回权限错误两种情况。

## 4. 既有兼容问题：需要产品选择，不是当前删除补丁新引入

### B1｜新端输出的 Space Zone 旧版仍可能读不到

- 当前 ExportData.swift:439–445 输出 `spaceData.triggerZones`，未同时输出顶层兼容字段。
- 已核对旧版 ExportData / ImportData 使用顶层 triggerZones。旧端重传时不会自动保留不理解的新字段。
- Group 的 profile 和 proximityLightingPath 位置则保持兼容，不能把问题归因于 7/8 枚举不认识。

**复现**：A 新版配置跨 Group Space Zone 并上传 → B 旧版重新获取 → 对比实际响应嵌套字段与 B 页面 → B 仅改 Group 名称并上传 → A 重新获取。记录每一步原始逻辑字段，不靠 deviceCount 或 HTTP 200 判断。

**建议**：如必须保留旧版只读展示，可评估由单一权威配置生成顶层兼容投影（新 App 双写需要服务端透传验证）。若新旧字段同时存在且冲突，新 App 以新格式为准。双写不能当成旧版安全编辑的解决方案。

### B2｜“新 App 一律覆盖旧 App”目前没有可验证的判定依据

当前配置保护能拒绝失效引用、缺损 Profile，以及“本地有 Space Zone、旧输入丢失/清空 Zone”的特定情况。但完整、自洽的旧快照仍可能被当作正常远端更新：例如只使用 Group Path/Group Zone 的 Space，旧端上传一份 type 7 且 Path 已为空的完整配置。

`SpaceConfigurationIntegrityPolicy` 明确允许合法完整的 7/8 → 普通 Profile 切换；ImportData 的远端采用仍主要看 updateTimestamp/初始化/保护状态。schema=1 不是可信的新客户端写入能力凭证，也没有服务器 revision/基础版本/删除意图可以区分合法降级与旧端默认覆盖。

**复现**：A 新版保存 Path；B 旧版持有更早的空 Path，之后上传完整、时间戳更新的 Space（可用脱敏合成快照复现）→ A 导入。保证输入 Profile 完整、成员自洽、无本地 Space Zone，以隔离结构保护。

**建议及边界**：

- 仅改 App：保留可用的新端配置快照，对来源不明的破坏性差异保留并让用户确认；明确选择新端本地完整副本后再上传/回读。不能静默无限反复覆盖服务器，也不能仅按手机时钟判断写入端能力。
- 真正强制新版优先：需服务端可信写入能力/版本冲突检查，覆盖所有写入口及后台投影；旧端仅允许查看或受限元数据修改。没有服务端约束，就不能承诺所有编辑端同时安全。
- 从新安装且无备份的手机，无法凭空恢复云端已经丢失的 Path 槽位、Zone 划分及 Profile 参数。
- 不建议简单禁止所有 7/8 → 1：用户明确降级应继续合法，并清理相关拓扑。

### B3｜旧 App 的设备同步算法不能由新 App 升级替换

已核对旧版 Node.getNodeSyncProximityLighting：目标只来自当前 Group Path/Group Zone，没有 Space Zone 邻居。新 App 则使用 Group + Space 的完整并集。

**复现**：A 新版为两个 Group 建跨组 Space Zone，配置设备成功 → B 旧版打开其中一个 Group 并实际同步设备 → A 新版再次读回设备 Enabled/Relay/Neighbors。

**预期风险**：旧端可能删除 Space 增加的邻居，新端重新出现真实的 Need Sync。即使服务器完美保留全部逻辑 JSON，这个 BLE/Mesh 行为仍然存在。

**建议**：拥有新版拓扑的 Space，应让所有有编辑/设备同步权限的手机升级。新 App 可以再同步恢复设备，但不能阻止旧 App 下一次改回去；不能通过隐藏新端 Need Sync 或删除 Space Zone 达到表面无提示。

### B4｜跨 Site/Space：常规隔离已有修复，仍有需补齐的边界

1. 当前拓扑 Context 按 meshUUID + networkId 取目标网络，成员检查同时核对网络和订阅，删除 context 也捕获目标身份。正常重新配网导致 UUID 相同，不应单凭此判断发生串库；现有执行测试覆盖了不同 Site 的相同 UUID/地址。
2. `GroupProximityLightingData.swift` 的 makePlan(for:contextGroup:) 仍先使用 `SpaceData.load(subNetworkId:)`；Database.swift:631 的查询没有 meshUUID，遍历后返回最后一项。若不同 Site 复用了相同 NetKey/Network ID，可能取到另一 Site，再因后续 meshUUID guard 返回 unavailable。结果是不能生成应有任务，而不是错误生成空拓扑 Disable。**建议 P2 补完整作用域查询**；普通新建随机 NetKey 不必靠“碰撞概率”解释故障。
3. SDK 锁定版本的 Group.nodes 使用全局 manager；Proximity 核心已绕开，但 ProfileSettings 等调用仍有。当前正常导航应由 Space 持有 Mesh 上下文，不足以断言这些 UI 调用必然串网；建议增加“保留旧页面/后台回调同时切网”的测试，确认后再扩大修改范围，不默认重构整个 SDK。
4. 如果实际上传 A 后，B 的 GET 在服务器端就丢失同 UUID 的设备，需检查服务端 (Site/Space, nodeUUID) 归属、缓存/任务键与删除逻辑。本轮没有服务端源码或实际响应链，**不认定服务器全局 UUID 唯一约束已经被证明有错**。

### B5｜Photocell 保存失败前已有副作用，建议一并收口

ProfileSettingsViewController.saveAction 在调用 Group 生命周期保存回调之前，会保存 requiredFunctionTypes/preConfiguration，删除再保存 ProfileLightSensorTemplate，切换类型时也会清空 Day/Night 预配置和设置校准重置。之后回调被保护状态或数据库失败拒绝时，这些副作用并未统一回滚。

**复现**：选一个 Profile 8 Group，修改 Day/Night 模板/阈值，模拟 GroupInfo/Profile 落库失败；SAVE 显示失败后比较 Profile 行、预配置、模板表与重新进入的页面。另测从 8 切到 7 时保存失败。

**建议 P2**：先完成只读校验，持久化相关 App 配置纳入同一成功边界；SDK/设备副作用在成功后应用或有可恢复记录。它不是本轮删除补丁引入，不应混为新回归；但与用户指定两个 Profile 的完整一致性相关。

## 5. 哪些新版可覆盖，哪些无需修复

| 情况 | 处理建议 |
| --- | --- |
| 旧版有效 Profile/Path/Group Zone/顶层 Space Zone | 新版正常导入并用统一算法工作；补回归，不改旧枚举 |
| 顶层与 nested 同时存在且冲突 | 新版以 nested 为准；不能两个字段轮流互写 |
| 旧端设备邻居已被改坏，但新版逻辑配置完整 | 新版执行正常设备同步可恢复；必须让其他编辑端升级才能避免再次覆盖 |
| 云端异常，本机新版保有完整正确副本 | 用户明确确认本机为准后恢复；先修 A 类闭环，再上传/回读/设备核对 |
| 所有完整副本都已丢失 | 需历史备份或人工重建，不能保证新版自动恢复 |
| 名称变化引发 Space common dirty | 名称上传本身合理；修复夹带旧配置覆盖的冲突语义，不禁用改名上传 |
| Path 的 nil/0 空槽、合法重复设备、空 Zone 容器 | 本身不是损坏；不要为了“清洁”自动删除用户布局 |
| 设备已转去另一个 Mesh，原 Space 仍保留旧成员 | 原 Space 的 Mesh 同步失败可能是真实状态；明确删除/迁移原成员，不改 UUID |
| 缺损 Profile、来源不明的失效引用 | 保留防护，提供可执行恢复；不直接关闭校验 |
| 仅重复 UUID，Site/Space/网络键均各自独立且接口快照正确 | 不需要 UUID 随机化或跨 Space 全局去重 |
| 只读 Visitor | 应能读取完整数据但不能触发配置写入；权限更新须不被待恢复日志阻挡 |

## 6. 建议确认的修复范围

### 第一阶段：建议批准的最小必要 App 修复

1. A1：删除/重新添加世代与回执终止规则。
2. A2/A3：统一所有上传确认入口，补首次创建、解绑和重新导入生命周期；不把 HTTP 成功直接当完整确认。
3. A4：拆开权限元数据刷新与拓扑保留，明确失权后的待处理状态。
4. B4 第 2 项：涉及本功能的 Space 查找补 meshUUID 范围，不扩大到全 SDK 重构。
5. B5：Profile 7/8 保存失败的预配置/模板副作用一致性。
6. 保护状态必须记录阶段和可执行的下一步。恢复后重启/再入不能再次进入同一个无进展循环；不单纯清标记、改时间戳或隐藏 Sync 图标。

### 第二阶段：需要用户明确选择的兼容策略

- **推荐**：参与编辑和设备同步的所有手机升级；旧 App 只保留经验证的查看能力。新端保留完整副本，来源不明的冲突先保护，由用户明确选择新端权威配置。
- 如必须旧 App 继续任意编辑/同步设备，需要服务端规则及旧端能力限制配合；仅修改新 App 无法满足“旧端照常操作且完全不互相覆盖”的保证。
- 顶层兼容投影是可选只读兼容增强，需要先确认服务端是否透传字段及现存旧版本范围，不能当作完整冲突方案。

**待确认**：是否按第一阶段范围修复，并采用“所有编辑端升级；无法识别来源的冲突保留新端完整副本、人工确认后覆盖”的策略？若旧端必须持续编辑，请先确认是否允许服务端配合，再定保证范围。本轮不开始实施。

## 7. 回归与测试验收矩阵

A/B 指两台手机；同时覆盖 Owner/Editor，读验证补 Visitor。Profile 7、8 各执行一次，Profile 8 额外对比 Day/Night scene、lux 阈值和所有 phases 参数。

| 编号 | 操作 | 验收要点 |
| --- | --- | --- |
| T01 | 旧版建 Group + Path + Zone → 新版导入 | Profile id/type/参数、槽位、顺序、成员不变 |
| T02 | 新版建 Space Zone → 旧版 GET/仅改名 → 新版 GET | 清晰记录兼容策略；不得把丢失字段当明确删除 |
| T03 | 两个新版轮流改名/查看/退出，共 3 轮 | 非逻辑变化不反复制造相同配置冲突 |
| T04 | Group Path 和跨 Group Space Zone 重叠 | 设备邻居为并集，Relay 按各自 Group |
| T05 | Group/Space SAVE 后取消部分设备同步，再入重试 | 配置保存不丢、未完成任务不假成功、完成后无重复同任务 |
| T06 | AUTO、SAVE、测试触发分别操作 | 相互不混用，SAVE 不额外强制开灯 |
| T07 | 7 ↔ 8、8 → 普通 Profile | 有意变更成功；合法清理准确；Photo 数据一致 |
| T08 | Profile 保存 SQL 失败 | 所有关联配置保持原状态或进入明确可恢复阶段 |
| T09 | 单个/全部/批量部分成功/强制删除 | 只移除确认集合的引用；空 Group/Profile 不误删 |
| T10 | Reset 后本地保存失败并杀进程 | 原目标 Space 恢复清理，不能被其他当前 Space 污染 |
| T11 | 离线删除后同 Space 重新配网，再联网 | 新世代保留；回执结束；其他手机变更可再次导入 |
| T12 | 离线新建 Site 并删除设备，再首次上传 | 创建回读完成，回执结束，后续导入可用 |
| T13 | 删除后解绑直接上传 → 同账号重导入 | 旧回执不拦新导入；Group/Path/Zone 实际落库 |
| T14 | 待恢复期间修改 Editor 权限/密码 | 权限元数据立即处理，不等待原写入成功 |
| T15 | 不同 Site 复用 UUID/地址，另测相同 Network ID | 各自逻辑和缓存隔离；正常任务不被 unavailable 静默吞掉 |
| T16 | 同 Site 不同 Space 重复添加同物理设备 | 云端两份快照稳定；Mesh 失联与云同步问题分开记录 |
| T17 | 历史 dangling refs；选择本地修复后断网/杀进程 | 原始备份保留、确认可重入、上传/回读后结束恢复 |
| T18 | 恢复预览到确认期间 A 又改云端 | 不静默覆盖未审阅的新变化；明确可取消/重审 |
| T19 | 云端非法 Profile / 超 184 邻居 / 缺失成员 | 不自动破坏 Path/Zone，不发送危险 Disable/缩减 |
| T20 | 旧端实际同步设备 → 新端读回 | 验证兼容限制；提示真实差异而非藏提示 |
| T21 | 恢复弹窗 iPhone/iPad、旋转、长文本 | 所有操作可见可点、取消无副作用、返回页面正确 |

每条记录：账号角色、脱敏 Site/Space 标识、meshUUID/networkId 标识、Node UUID/Primary/vendor 地址、上传与 GET 的逻辑字段、updateTimestamp/lastUploadCloudTimestamp、阻断原因/删除阶段、Mesh 读回结果。不要记录认证口令、设备密钥或 NetKey 原文。

## 8. 本轮验证结果及限制

已执行：

- `python3 scripts/check_proximity_scoped_import.py`：本轮执行时版本通过；生产拓扑/删除适配逻辑，SDK、存储与 UI 边界使用替身。
- ProximityLightingTopologyPolicyTests：通过。
- ProximityLightingLifecyclePolicyTests：通过。
- SpaceConfigurationIntegrityPolicyTests：通过，覆盖 Profile 完整性、Photocell 引用、合法类型切换与回读逻辑。
- `check_configuration_database_safety.sh`：使用上述准确 SDK checkout 的 SQLite 源码，通过真实 WAL 备份、事务失败回滚与 legacy NOT NULL Profile 表用例；日志中的约束错误是故意注入的测试输入。
- `check_space_delete_cloud_restore.sh`：通过，属于源码契约而非服务器执行。
- `/tmp/proximity-review-journal.swift`：直接执行生产 journal，复现 A1 的非终止回执。
- `check_site_space_mesh_context_ownership.sh`：以声明的 zsh 运行后仍有一个源码字符串契约失败，要求导入使用旧的 `groups: groups.filter...` 字面表达；当前代码已使用显式 network/nodes，另有执行适配层通过。因此不把这一条直接报告为新的运行时串网缺陷，建议同步维护契约测试。

第一次调用部分脚本时 shell/参数不匹配，已按脚本声明改用 zsh 或补 SDK 参数重试；生命周期测试的首次命令引用了实际上内嵌于 Reconciler 的两个策略文件，随后按真实文件重新编译通过。以上初次调用失败不作为产品缺陷。

本轮没有运行 iOS 构建（没有实现改动），没有使用 Simulator，没有实际布局测试、真实 BLE/Mesh 或服务器写入。A2–A4 为具体源码路径分析与待执行集成复现，不冒充已在用户设备复现；跨服务器身份问题仍需要实际接口证据。后续实现涉及共享 target/本地化/UI 时，按 AGENTS 要求检查相关品牌，并直接运行 generic iphoneos xcodebuild；真机布局及完整云/设备操作验收不能由构建替代。

先前记忆仅用于定位历史排查入口，当前技术结论已重新查源码与测试：MEMORY.md:226–245（生命周期入口），MEMORY.md:453–460（跨 Space 身份的证据边界）。
