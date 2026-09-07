# 旧 App 覆盖新版 Proximity 配置：原因分析与兼容规划

分析日期：2026-09-07。范围：SunSmart `954c51999a5be2e24d7d56f0def0e87a2bd8a2be`（1.2.0）与 `fd520c932eb50d9aac140041d3e557b1fd5b4795`；当前 HEAD 为后者。开始分析时工作树干净。本轮仅新增分析文档，未修改业务代码、SDK、数据库、资源、依赖或服务器。

**后续决策（2026-09-07）：用户明确服务端无法改造，只修改 App，并建议手机 B 等编辑端同步升级。当前执行范围以 [仅 App 修复方案](260907_1157_app_only_proximity_compatibility_fix_plan.md) 为准。本文的服务端方案保留为原始分析，不再列入实施范围。**

## 1. 结论与证据边界

这不是“旧 App 不认识新的 Profile 枚举”导致的单一问题，而是旧新数据位置不一致、全量 Space 覆盖、Profile 默认回退与新版拓扑清理相互叠加。另有独立的 Mesh 风险：旧版 Group 同步只使用 Group 拓扑，会覆盖新版 Space Zone 增加的邻居。

已确认：

1. 两个提交的 `Profile.swift`、`Database.swift` 没有差异。Profile 7 是 Proximity Lighting，8 是带 Photocell 的 Proximity Lighting，1 是 Occupancy sensing with daylight harvesting。两份 Package.resolved 的 Nordic SDK revision 同为 `86f5ec9e40148b9cd93e0512702337fcec41dd40`；未发现这两个提交之间的枚举或 SDK pin 变化能解释 7/8→1。
2. 旧版只读取顶层 `triggerZones`，缺失就设为 `[]`；新版导出只写 `spaceData.triggerZones`，并在其中写入 `proximityLightingSchemaVersion=1`。
3. 旧版改 Group 名称会保存 GroupInfo/Profile、发出 Space common change，最终上传整份 Space。该链路不以 Group 的 Mesh 同步完成为前置条件。
4. 两版都有 Profile 导入/落库/加载失败后静默使用默认 Profile 的路径；默认 type 正是 1。但本次 7/8→1 究竟首先发生在 GET、B 导入、B 本地重载、B 导出还是 A 本地重载，尚无本次日志证明。
5. 新版将非 Proximity Group 的 Path、Group Zone 和 Space Zone 成员移除；无 schema 旧快照中的这类修复不会自动被视为导入错误。因此错误 Profile 可能从显示异常进一步变成已持久化的数据删除。

本次用户描述是现象依据；当前源码与两个 Git 快照是机制依据。9 月 4 日仓库报告中有相似故障，但不能当成本次复现的服务器或数据库证据。本轮未访问生产接口、未读取 A/B 数据库、未进行真实 Mesh 操作。

## 2. 字段兼容对照

| 内容 | 954c519 | fd520c9 | 兼容结论 |
| --- | --- | --- | --- |
| Group Profile | `groups[].profile`，type 1…8 | 相同位置与类型 | 应保持原有 id/type/参数，不能主动映射 7/8→1 |
| Group Path / Group Trigger Zone | `groups[].proximityLightingPath.paths/zones` | 相同结构，但导出和归一化要求 Profile 合格 | 旧版能识别；错误 Profile 会在新版触发清理 |
| Space Trigger Zone | 顶层 `triggerZones`；缺失清空 | `spaceData.triggerZones`；无 spaceData 才读顶层 | 单向嵌套输出不能被旧版读取 |
| Proximity schema | 无版本标记 | `spaceData.proximityLightingSchemaVersion=1` | 数据 schema 不等于写入端具备安全编辑能力 |
| Node 已观测 Proximity 状态 | enabled / relay / neighbors | 同名字段 | 只是设备状态缓存，不能替代完整逻辑配置 |
| Group 同步的邻居目标 | Group Path 与 Group Zone 的并集 | Group 与 Space 拓扑的并集 | 旧版可能把 Space 邻居删掉 |
| Space Zone SAVE 的目标 | 只计算 Space Zone；无邻居可 Disable | 使用统一拓扑 | 旧版即使能显示 Zone，也不代表保存安全 |
| Space 写入请求 | siteId + spaces 数组 | 新增外层 spaceId | 服务端必须兼容旧请求，并逐 Space 校验身份与范围 |

补充：1.2.0 源码已有 Space Trigger Zone 页面和模型，不能简单称其“完全没有 Space Zone 功能”。实际缺口包括云端字段位置，以及 Group/Space 两套不同的设备同步算法。可以让它显示相同数组，但不能据此承诺它能安全修改与同步新版拓扑。

## 3. 按复现过程还原

### 3.1 B 首次导入旧版 A 的分享

A、B 使用相同 Group Profile / Path / Zone 格式，因此能够显示符合源码预期。后续新版本必须保持这些旧字段的可读性，尤其是 Profile id/type、Path 点位顺序及 Zone 成员。

### 3.2 A 升级并配置 Space Trigger Zone

新版输出的 Space 扩展在 `spaceData`。如果服务端按新版结构返回，旧版 B 在下次导入时仍只找顶层字段，因此把 Space Zone 置空。这一步不需要用户明确删除任何 Zone。

即使 B 的 Profile 始终保持 7/8，它按 Group-only 拓扑计算的目标也可能与 A 已写入的 Group+Space 邻居不同，从而出现需同步提示。是否还有 Profile/Scheduler 等任务，需要看 B 本次任务列表；不能把所有提示一概归因于 Space Zone。

### 3.3 B 只修改 Group 名称

旧版流程：GroupAddViewController 修改名称 → `finnished()` 保存图标、当前 Profile → `.common` 通知 → Space 更新客户端时间戳 → CloudSynchronizationManager 导出整个 Space → `/sitespace/sync/spaceprops`（或相关嵌套 Site 上传）。

因此“无视 Group 同步提示仍能上传”是当前 common change 的既有行为。名称本身不需要 Mesh 同步；问题在于这个小变更携带了本机所有其他字段，包括本机已经变空或退化的配置。

旧版导出顶层 `triggerZones: []`，且不会透传未知的 `spaceData`。这不仅是“遗漏一个新字段”，还是“用空值表达了自己其实未读取到的数据”。服务端如果采用整份替换或把顶层空数组当新版清空指令，就可能删除新版 Space Zone。

### 3.4 Profile 为什么变成 type 1

单纯旧新枚举不兼容的假设已被排除。需沿以下几个检查点找出首次变化：

| 检查点 | 需要比对 | 可区分的问题 |
| --- | --- | --- |
| A 保存后上传与立即 GET | Group 稳定身份、Profile id/type/参数 | A 导出或服务端转换是否已退化 |
| B 进入收到的 GET | 同上，Profile 是对象还是缺失/错误类型 | 旧客户端投影/服务端返回问题 |
| B 导入完成的内存与落库回读 | GroupInfo.profileId 与对应 Profile 行 | 非事务保存失败、错误作用域、加载失败 |
| B 改名前后及上传前 | 同一 Profile 是否出现新 UUID、type 1 | 编辑保存或导出重新加载的默认回退 |
| A 再次 GET、导入及重载 | 服务器 type 与本地 type | 区分 B/服务器覆盖与 A 自身加载问题 |

源码中的具体回退：

- `GroupInfo` 构造时默认 Profile 为 `.occupancy_daylight`；如果 Profile 对象或 id 缺失、类型不合法，导入可保留默认对象；若 type 字段缺失，导入直接以 1 尝试解析。
- 导入先删除当前 Space 的 GroupInfo/Profile，再逐个创建保存，没有把全批操作做成失败回滚事务。
- `saveExtension()` 先写 GroupInfo.profileId，后写 Profile；保存 Bool 被忽略，可能只留下引用。
- `GroupInfo.load` 找不到 Profile 时保留构造出来的默认 Profile。导出又从数据库重新 load GroupInfo，可能把原本正确的内存对象替换成默认对象并上传。
- Profile 数据库中非法 raw type 也会回退到 `.occupancy_daylight`。

历史仓库报告提到 `regulatorAccuracy NOT NULL` 的跨版本表结构问题。该问题在两个指定提交中都没有专门兼容，但它要求手机保留相应历史数据库。B 若为全新安装且只使用这两个指定版本，不能仅凭相似现象把它认定为本次原因。需用本次数据库列定义与实际 SQL 错误确认。

### 3.5 A 收到退化配置后的二次清理

新版 Reconciler 只允许 type 7/8 参与拓扑。收到 type 1 后：

- Group `hasTopology` 设为 false，Path 和 Group Zone 变空。
- Space Zone 中该 Group 的成员引用移除，Zone 容器可以仍在而设备变空。
- 该设备不再有启用的 Proximity 目标；若缓存显示目前 enabled=true，会生成 Disable。
- Group 页面根据 Profile 隐藏 Path 入口；这时可能既有入口隐藏，也有底层 Path 已删除，不能只修复显示条件。

这里必须区分服务端返回形态：

1. 无 schema：type 1 + 残存 Path 会被归一化为非 Proximity；清理记为 repairs，未必有 hardErrors，现有“保留本地快照”保护不会因此触发。
2. 保留 schema 1 且 type 1 + Path 同时存在：预检会拒绝该扩展，已有可用本地快照时应走保留分支。
3. 服务端已返回自洽但退化的 type 1、无 Path、空 Zone：可能通过结构检查，仍无法证明这是用户明确降级。
4. 预检收到 type 7，但随后本地 Profile 落库/重载失败：也可能在后续导出归一化中删除拓扑。

因此本次必须抓实际 A GET 与本地回读，不能断言服务端一定整体删除了 spaceData。即使服务端保留了 Zone，错误 Profile 在新版也可能把该组的 Zone 成员清掉。

### 3.6 云端保护不等于设备保护

旧版 Group 同步忽略 Space Zone；旧版 Space Zone SAVE 又忽略 Group Path/Zone，甚至在自己算出空邻居时禁用 Proximity。它们都修改同一设备的 Enabled/Relay/Neighbor 状态。

服务器保留逻辑 JSON 后，旧版只要仍有设备编辑能力，就仍可能经 BLE/Mesh 执行这些操作。不能通过服务端合并字段让已安装二进制自动获得统一拓扑算法。用户此次只改名而未同步，不能据此认定本次已经发送了 Disable；目前的任务提示只能证明存在待执行风险。

## 4. 能达到的兼容效果

| 场景 | 预期与限制 |
| --- | --- |
| 新版查看/编辑 | 基于受保护、经校验的完整快照显示四类配置；明确的用户修改才产生清理与设备任务 |
| 旧版查看 Group | 服务端继续返回完整旧格式的 Profile/Path/Group Zone；本地落库正常时可正确展示 |
| 旧版查看 Space Zone | 可由服务端从 canonical 数据生成顶层兼容投影；能够解码不代表可安全 SAVE |
| 旧版只改名 | 可规划服务端仅应用指定安全元数据字段，保留全部 Proximity 配置；需要验证旧版成功后本地与再次 GET 的刷新行为 |
| 旧版修改 Profile、Path、Zone、成员或同步设备 | 新特性 Space 上不承诺安全；推荐要求升级，未升级时限制相关写入 |
| B 升级到修复后的新版 | 先隔离旧待上传快照，再拉取 canonical 配置；有完整备份时可恢复，缺失数据不能凭算法凭空重建 |
| 仅修改新 App | 可以保住 A 的可恢复副本并阻止二次清理，但不能阻止 B 改坏云端或直接改设备，无法保证新设备首次导入完整 |

推荐产品策略：对已使用新版统一 Proximity 拓扑的 Space，旧版保留查看；若业务必须允许改名，再增加经过验证的服务端元数据兼容通道。拓扑编辑与设备同步应升级后进行。没有新版特性的历史 Space 保持旧兼容策略，保护状态不能因旧请求传空数组而自动解除。

不能同时无条件保证“旧 1.2.0 保留全部 Editor 操作、无需升级、设备完全不受影响”。如果要求严格保证，应限制旧版在这些 Space 上的编辑/进入能力，并验收线上、离线与缓存权限下的实际表现；服务端拒绝上传本身不足以撤回已经发生的 BLE 操作。

## 5. 推荐实施方案：服务端与新 App 配合

### P0-A：服务端建立受保护的配置与旧写入规则

1. 在服务器按 Site/Space 稳定身份保存完整 canonical 配置和历史版本。Group 使用 Space 内稳定身份关联，不按名称匹配；如果地址可能重用，需配合实体世代/删除记录。第一阶段可保持现有 JSON 外形，内部对相关配置实行整体保护。
2. 对旧 GET 继续提供 `groups[].profile` 与 `proximityLightingPath`；必要时将 canonical Space Zone 投影为顶层 `triggerZones`。顶层与 nested 只允许一个权威来源，不能变成两个可独立覆盖的副本。
3. 对使用新版功能的 Space，旧上传中缺失 spaceData、顶层 `[]`、默认 type 1、缺失 Path、旧 Node 邻居缓存均不得直接覆盖受保护配置。仅做“缺失字段保留”不够，因为旧版主动输出了空值和默认值。
4. 最小安全策略是拒绝旧客户端对受保护配置的修改。若要保留改名，单独解析已存在 Group 的名称/允许的图标字段，验证身份与删除状态，在事务中只提交这些元数据，忽略随整份快照夹带的旧 Profile/拓扑。无法确认安全范围则整次拒绝，不能用通用深合并猜测用户意图。
5. Group/Node 删除、退组、Profile 降级与 Zone 删除属于关联变更；不能保留 Zone 却接受旧请求删除成员。阶段一统一要求新版操作，后续再增加明确操作类型、删除记录与冲突规则。
6. 新写协议区分未提供、明确置空、具体替换。明确置空必须来自支持新写语义的端且基于匹配的 revision。旧的无版本 `[]` 不作为新功能删除授权；新版有明确操作时则允许真实清空，避免永远无法删除。
7. 引入服务器 revision、基础 revision 校验、幂等操作标识与冲突返回。新端改名采用字段补丁；同一基线并发修改不得最后写入覆盖。旧请求没有基础 revision，不能假设它参与了乐观并发控制，只能按受限策略处理。
8. 同时覆盖 `/sync/spaceprops`、`/sync/siteprops` 中嵌套 Space、初次创建/分享导入相关写入口和对应 GET；识别旧版缺失外层 spaceId 的请求，从已验证的 spaces[].uuid 确定对象，不能降低身份校验。
9. 区分数据 schema 与客户端写能力。`fd520c9` 已会写 schema 1，但没有本方案的保护，不能把“有 schema 1”直接等同于安全客户端；后续写能力标记/协议版本应单独设计。当前显式业务请求头中未见专用兼容能力字段，不能仅凭 User-Agent 或营销版本做全部判断。
10. 旧版忽略服务器新增 revision，且相同 timestamp、相同实体数量会跳过更新。兼容响应需确保真实内容修改能被旧端识别为较新；元数据通道也需验证其上传成功后的本地 timestamp 与下一次 GET。不能简单把新 revision 塞进一个旧版不读的字段就宣称兼容完成。

补充限制：如果旧端本地数据库仍持续生成 type 1，即使服务器保住 type 7，旧端即时显示也可能错误。服务端保护可以阻断传播，旧端自身显示修复最终依赖升级与本地迁移。

### P0-B：新 App 阻断错误输入引发的清理

1. 把 Profile 加载结果区分为完整、缺失、损坏；禁止将自动创建的默认 Profile 视为已确认业务事实。导出失败应明确返回失败并保留 dirty，不能生成新 UUID/type 1 后成功上传。
2. GroupInfo 与 Profile 原子保存并校验回读；服务端导入先 staging 解码/落库验证，再事务替换当前快照。数据库迁移按真实表结构处理，`regulatorAccuracy` 仅在确认旧列存在时按兼容规则修复。
3. 在任何持久化归一化之前保留原始远端快照和最近完整本地快照。将“用户明确修改 Profile”与“外部导入/历史缓存退化”设为不同来源；只有前者或经验证的新协议操作可以直接使用 Profile 降级删除语义。
4. 对旧/来源不明确的快照，如果本地原为 7/8、远端变成 1 或 Path/Zone 缺失/清空，进入待核对状态。保留可用配置、允许进入查看，并阻断相关拓扑删除、Disable、Neighbor 缩减和带有不确定数据的全量上传。不能简单把所有 repairs 都当 fatal，正常历史数据规范化仍需按原因处理。
5. 没有完整本地副本时，把未知拓扑与明确空拓扑区分开。不要因首次导入缺字段就构造 Disable，也不要从 Node neighbors 反推 Path/Zone 后当成恢复完成。
6. 保护放在共享导入、导出、生命周期协调与任务生成入口，覆盖 More SAVE、Group/Profile 编辑、成员变更、Device Restore、延期同步与导入后的修复同步页，避免只在某个 UI 提示处拦截。
7. 上传后在受控新协议上验证服务器返回的配置 revision/digest，必要时 GET 回读；确认一致后才清理对应 dirty。保留读回期间新产生的本地修改，避免并发导出/回读把新 dirty 清掉。

### P1：升级迁移和受损数据恢复

1. 覆盖安装后的第一次 Space 使用前，保存本地 GroupInfo/Profile、Path/Zone 和待上传操作的可恢复快照；不要先触发旧队列导出上传。
2. 按 Space 隔离旧全量快照的待上传操作，包括嵌套 Site 上传和退出时 flush。保留用户修改供回放，不直接删除全部未同步编辑。
3. 获取服务器 canonical 最新 revision，校验完整性并事务落库；没有基础 revision 的旧待办不直接重放。可确认的改名等元数据可在最新基线上重新应用。
4. 迁移记录要持久化、可重入，覆盖中途退出、断网和失败重试；升级后仍应对其他未升级手机的旧写入保持保护。
5. 如果服务器已坏，按“已验证的历史服务器版本 → 本地最后完整快照 → 旧完整分享/备份”的实际可用性恢复，并核对真实删除记录与后续合法修改。旧分享通常只是较早时间点，不能保证含有后来新增的 Space Zone。
6. 不能只把 type 1 强改为 7：还需原 Profile 参数、Path 次序、Group Zone、Space Zone、成员与 Relay 来源一致。设备只保留最终邻接关系，同一邻接图可能对应多种 Path/Zone 组合，无法无损反推原始配置。
7. 恢复逻辑配置后，再查询并核对设备的 Enabled/Relay/Neighbors，在授权的正常同步流程中修复差异。云端恢复不等于设备已经恢复。

## 6. 只能修改新 App 时的降损方案

可独立实施 P0-B 和 P1 的本地保护：保留最后完整快照，隔离旧来源覆盖，阻断默认 Profile 导出和破坏性同步，升级时暂停旧全量队列并核对云端。

但需明确三项无法保证：

- B 仍可能把服务器最新快照改坏；A 的本地副本无法替代服务端保护。
- 没有历史副本的新手机/重装手机无法可靠恢复已丢失配置。
- B 仍可通过旧 Mesh 算法修改设备。

仅由新 App 双写 nested/top-level，可改善旧版读取；仍不能解决旧版设备算法、默认回退与并发覆盖，因此只适合作为读兼容措施。也不建议把新版 Space Zone 合成到旧 Group Zone：跨 Group 无法完整表达，且会改变用户看到的 Group 配置并引入重复编辑/删除歧义。

不要让 A 自动反复用自己的“最后好数据”覆盖云端：其他手机可能做过合法删除，缺少 revision 与变更意图的自动回写会制造另一种数据损坏。

## 7. 验证与发布门禁

| 验证场景 | 必须满足的结果 |
| --- | --- |
| 旧 A 创建，旧 B 导入 | Profile 7/8、Path 顺序、Group Zone 完整 |
| A 升级建 Space Zone，旧 B GET | Group 三类配置保持；Space Zone 显示符合选定投影策略 |
| B 不同步，只改名 | A 名称更新，Profile id/type/参数及三类拓扑不变 |
| B 传空顶层/缺失 nested/默认 type 1 | 不覆盖 canonical Proximity；返回结果与兼容策略一致 |
| B 修改 Profile/删除组或成员 | 受保护配置拒绝旧写或要求升级，不产生悬空关系 |
| 新版明确清空 Zone/降级 Profile | revision 匹配时正常完成，并执行完整关联清理 |
| 旧版点击 Group 同步或 Space SAVE | 明确记录旧算法可能改变设备；验证产品限制能否覆盖在线/离线场景 |
| schema 缺失、schema 1 矛盾、未来未知 schema | 保留/隔离策略正确，均不静默把 unknown 转成删除 |
| 相同秒级 timestamp、相同数量但内容不同 | 新协议检测内容变化；旧端投影刷新经过实际验证 |
| A/B 并发、离线队列、嵌套 Site 上传 | 无丢失更新、无绕过保护、可重试且幂等 |
| Profile 缺 id/type、损坏行、孤立 profileId、保存失败 | 不用默认值上传，不清理拓扑；事务失败不替换完整快照 |
| B 带待上传坏快照升级、中断迁移后重启 | 旧全量数据不先覆盖云端，迁移可恢复，安全元数据可回放 |
| A 仍有好副本 / 全新导入 / 所有副本均坏 | 分别验证保留、从服务器恢复、明确无法完整恢复的边界 |

验证层次：先用真实序列化输入与临时数据库做失败注入，再做隔离测试 Space 的双版本真实 HTTP 往返，最后进行两手机和 Mesh 设备回读验收。不要仅比较数量：须比较身份、Profile 参数、Path 顺序、Zone 成员、拓扑 digest 和相关设备状态。

若实施共享 App 代码，按项目规则直接用 xcodebuild 做 generic iPhoneOS 无签名构建，检查 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的实际共享影响。若增加 UI/文案，同步 English 与简体中文，并在实际设备上验证完整交互/布局，不用 Simulator 代替。构建成功不能代替服务器与 Mesh 验收。

发布顺序建议：先保存可恢复副本并上线服务端保护，再发布 App 导入/导出与迁移保护，验证混合版本场景，最后开放受控编辑能力。服务端改造范围尚待用户确认；本轮没有执行其中任何写入。

## 8. 本轮离线验证

临时探针：`/tmp/sunsmart_legacy_proximity_probe_260907.swift`。使用当前真实的 `ProximityLightingTopologyPolicy.swift` 与 `ProximityLightingTopologyReconciler.swift` 编译执行，另用合成 JSON 检查顶层/嵌套查找差异。结果：

- Group-only 示例目标为 [0103]，统一拓扑为 [0103, 0106]。
- 将同一 Group 设为不合格 Profile 后，hardErrors=0，Path=0，Group Zone=0，Space Zone 成员=0，目标产生 Disable。
- repairs 本身不会触发 preserveLocalSnapshot。
- 同一合成 nested 载荷，旧顶层查找得到 0 个 Zone，新 nested 查找得到 1 个。

这是实际策略函数执行与合成字段查找验证，未运行完整 App ImportData、SwiftyJSON 导入、SQLite、真实服务端或 BLE/Mesh；它证明机制可发生，不能替代本次复现的 Profile 首次退化定位。仅分析文档变更，不执行无关 iOS 构建。

## 9. 源码与后续取证清单

当前 fd520c9 的关键位置：

- `SunSmart/Main/Profile/Model/Profile.swift:552`：type 映射。
- `SunSmart/Common/Data/ImportData.swift:123`：nested/root 选择；`:221`：Profile 预检；`:1474`：预检与保留策略；`:1666`：timestamp 判断；`:2070`：Group/Profile 创建；`:2383`：导入后规范化。
- `SunSmart/Common/Data/ExportData.swift:349`：GroupInfo 重载；`:433`：spaceData 输出；`:697`：Profile 输出；`:783`：Path 导出资格。
- `SunSmart/Common/Data/Database.swift:936`：Profile 加载失败回退；`:1584`：非法 type 回退；`:1652`：Profile 保存。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1236`：非事务扩展保存；`:1469` 附近：默认 GroupInfo Profile。
- `SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift:236`：非合格 Group 清理；`:310` 附近：Space 成员清理。
- `SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift:330`：规范化结果写回。
- `SunSmart/Common/Data/Node+SyncData.swift:1616`：目标转设备任务；`ProximityLightingTopologyPolicy.swift:165`：Disable 决策。
- `SunSmart/Main/Space/Controller/SpaceViewController.swift:757`：导入修复任务进入同步页。

旧 954c519 的关键位置（行号属于旧提交，须用 git show 查看）：

- `ImportData.swift:1335`：只读根 triggerZones，缺失清空；`:1662`：删除旧 GroupInfo/Profile；`:1677`：Profile 导入；`:1852`：扩展保存。
- `ExportData.swift:157`：GroupInfo 重载；`:178`：顶层 Zone 导出；`:524` 附近：不根据 Profile 类型过滤 Path。
- `GroupAddViewController.swift:76`：编辑选择现有 Profile；`:130`：改名发 common change；`:225`：附带保存 Profile。
- `CloudSynchronizationManager.swift:88` 附近：整个 Space 导出上传；`SpaceViewController.swift:99`：common/device 均可入云队列。
- `Node+SyncData.swift:1616`：Group-only Proximity 同步。
- `Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift:400`：Space-only 同步与空邻居 Disable。

需要本次复现的最小取证：A 新版首次上传及 GET，B 进入 GET、改名上传，A 再次进入 GET；附各阶段 Group 地址、Profile id/type、schema、三类拓扑数量和内容摘要、时间戳、数据库保存结果。诊断输出不要包含 Mesh 密钥或登录凭据。若有 SQLite 错误，再核对 B 的历史安装与 profiles 表列定义。

用户已明确服务端不参与，手机 B 建议同步升级。仍缺本次日志与 B 历史数据库信息，因此 Profile 首次退化点尚不能作最终归因；这不阻碍规划和验证 App 中已经确认的默认回退、全量上传与二次清理保护。
