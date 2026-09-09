# Site Trigger Zone：跨 Space 能力分析与分阶段验证建议

首轮分析日期：2026-09-09，源码快照为 App 工作树 `site-trigger-zone`、HEAD `8322422a`。2026-09-09 17:45 根据原型对照回填已确定内容。本次仅更新开发文档，不修改 App、SDK、配置或服务端，不执行设备下发；下文源码与测试证据仍对应原分析时点。

后续需求已收敛：触发遵循 Group Profile；编辑权限覆盖本 Site Zone 的全部 Spaces；无权限 Space 仍需展示摘要；固件只用配置的 Key 转发且同一 Group Path 必须同 Key。以 [后续补强分析](260909_0959_site_trigger_zone_key_scope_permissions_analysis.md) 为准，本文中相关待确认项和混合 Key 候选不再作为当前推荐方案。

原型来源：[One SunSmart / site-trigger-zone-prototype](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=619-5084)，依据本会话上一轮的原型核对记录回填。本次区分“已确定需求”“已核对的原型事实”和“待确认方案”：原型事实不代表底层执行规则已确定；Test / Reset、最低成员数、恢复方式等候选建议不因本次回填而转为已批准需求。

**已核对的原型功能范围**

| 功能 | 原型已表达的内容 | 开发分析边界 |
| --- | --- | --- |
| 入口与查看 | Site 菜单 Trigger Zone；Zone / Space / 设备分层；按 Zone 或 Space 名搜索；单 Zone 有三个 Space 的示例 | 不按固定两个 Space 建模；搜索结果不能作为权限或保存成员的完整来源 |
| 添加 | Quick add、Trigger add、Manually add；目标 Zone、Space 选择、New only；连接中、失败 Retry；Quick add 开始/暂停 | 三种模式不是新增待发现入口；自动入选规则、New only 含义、默认连接 Space、切换保留规则仍待定义 |
| 权限展示 | Owner / Editor / Visitor / No access；含 Visitor 或 No access 的 Zone 整体 View only；受限 Space 分区保留 | 与后续补强分析一致；受限摘要字段、占用和权限未知仍需独立契约 |
| 编辑与同步 | Test / Reset / Delete / Save；未保存切换提示；Remove / Configuration；按 Space 与设备展示进度；STOP、选择失败项 RE-SYNC、通信范围提示 | 同步失败页已存在；分类不等于执行顺序，进度分母、按钮业务语义与退出恢复尚未全部定义 |
| 异常展示 | Profile 变化后保留禁用设备；Group 删除后选择替代 Group；Space removed 占位和 View only | 状态画面不证明设备已清理，也不确定替换后的设备集合或修复授权 |

原型页 `619:5084` 没有可执行的 Prototype reactions，流程依据为结构化文字、画布连线及 13 个嵌入位图的辅助核对。已发现 Manual 连接成功/失败标注反向（标注 `619:10941` / `619:10943` 对照画面 `619:10908` / `619:10909`），以及嵌入位图 `619:10903` / `619:10910` 带 Sequence 页签而主原型没有该范围；前者应修正，后者在另有明确需求前不能作为新增 Site Sequence 的开发依据。入口、三种添加、权限和同步画面的代表节点分别为 `619:5305`、`619:6220` / `619:6588` / `619:6998`、`619:7404`、`619:10898` / `619:10899`。

**结论**

现有邻近照明拓扑可以作为基础，但 Site Trigger Zone 不只是把 Space 页面扩大选择范围。必须一起解决统一邻居表、跨子网通信、跨 Space 编辑占用、同步记录及旧客户端兼容。

推荐方向是：Site Zone 独立存储；设备最终配置统一规划；保留 Space 密钥与原业务归属；按实际需要补充跨 Space 通信能力；复用 Sync Devices 展示与会话基础，增加明确的 Site 同步上下文。

当前不能承诺只改 App 即可完成。先用小规模设备验证固件的转发 AppKey、Relay、TTL、Photocell 和手动覆盖语义，再确定最终密钥部署范围。

**证据边界**

- 当前工程锁定远程 SDK `release` 的 `a6246b1b0409824a3227a9c7cad8140219feb182`。
- 指定本地 SDK `nordic-sig-mesh-sdk-worktrees/one-dev` 存在，HEAD 与锁定 revision 一致，检查时工作树干净。因此下述 SDK 源码分析对应当前锁定版本。
- 已读取当前 App、SDK、私有协议的相关实现，并核对 Bluetooth SIG 对密钥与 TTL 的说明。
- 未读取服务端实现、未验证实际接口行为，不能认定服务端已具备多 Space 原子锁、版本控制或新字段透传能力。
- 未检查现场设备的密钥列表、Model Bind、固件资源上限，未做构建、真机 UI、BLE/Mesh 或服务器联调。源码具备配置能力不等于所有已安装设备具备该能力。
- 历史记忆仅用于定位统一拓扑及生命周期边界，关键结论已在本工作树重新核对；旧分析文档中的 target、路径和源码行号不直接作为当前事实。

**1. 当前实现能复用什么、缺什么**

| 当前事实 | 对 Site 功能的影响 | 当前源码证据 |
| --- | --- | --- |
| Group Path 只连前后相邻设备；Group Zone 与 Space Zone 内成员互为邻居；最终取并集 | Site Zone 应作为新的一层关系来源加入同一计划，不能单独覆盖设备表 | `SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift`，`makePlan` |
| 每个设备只有一个目标：Enable、Relay、Neighbor Addresses；Relay 来自所属 Group Profile | 不应为 Site Zone 另设一个直接覆盖 Group Relay 的值 | 同上；`GroupProximityLightingData.swift`，`makeGroupSnapshot` |
| 当前上限为每设备 184 个合并后的邻居 | 限制要计算全部 Path/Zone 的并集，不能只检查 Site Zone 成员数 | `ProximityLightingTopologyPolicy.swift`，`maximumNeighborCount`、`mutation` |
| Space Zone 存在 `SpaceData.triggerZones`，Item 仅有 Group Address、Device Address，并从全局 Mesh Manager 解析对象 | Site 成员必须携带 Space 与稳定设备身份，不能直接复制当前 Item | `SunSmart/Main/Space/TriggerZone/Model/SpaceTriggerZone.swift` |
| Planner 明确以单个 Space 加载网络、Group Profile 和 Zone，数据不完整时拒绝生成计划 | 新增 Site 汇总上下文；不可把缺失的远端 Space 当成空配置 | `GroupProximityLightingData.swift`，`ProximityLightingTopologyContext`、`ProximityLightingTopologyPlanner` |
| 邻居命令仅有一个 `relayAppKeyIndex`，目前取全局 `currentApplicationKey.index` | 同一设备不能通过现有命令为每个 Zone/邻居单独指定不同转发 AppKey | `Node+MessageHandles.swift:354`；`SyncDevicesCellModel.swift:665`；SDK `SunricherVendorSet.swift:213` |
| 当前 Target、CurrentState、ACK 后 Node 缓存及成功判断未包含转发 AppKey、TTL | 只变 Key/TTL 可能漏同步；旧缓存不能证明新配置已应用 | `Node+SyncData.swift:1640`；`SyncDevicesCellModel.swift:400`；SDK `VendorServerDelegate.swift:356` |
| Classic、Professional 新增流程未设置 `.mainNetwork`；SDK 使用当前 NetKey 配网 | 普通 Space 新设备不能视为已具备 Primary 通信能力 | `DeviceAddClassicModeController.swift:1317`；`DeviceAddProfessionalModeController.swift:1352`；SDK `MeshDeviceProvisioningManager.swift:327` |
| SDK 在要求 `.mainNetwork` 时可补 Primary NetKey/AppKey，并绑定支持的 Models | 有基础工具可复用，但不应直接全局打开标志，扩大所有 Model 的绑定范围 | SDK `Node+Messages.swift:764`；`Node+Config.swift:29` |
| Site 页面会切换到 Primary 上下文；Space 页面使用各自子网 | Site 页面不能直接依赖当前 Key 去初始化尚无 Primary 的设备；任务必须显式指定网络上下文 | `SiteViewController.swift:245`；`SpaceViewController.swift:400` |
| Sync Devices 已拆出 Task Builder、Execution Session、Coordinator、ResultCollector | 可新增 Site 专用计划与结果适配，避免再把全部业务塞回 VC | `SunSmart/Main/Space/Model/SyncTaskPlanBuilder.swift`、`SyncExecutionSession.swift`、`SyncResultCollector.swift` |
| Space 活跃编辑者检查与 30 秒心跳按单个 Space 进行 | 角色检查不等于跨 Space 独占编辑许可 | `SpaceViewController.swift:957`、`:1032`、`:1079` |

**2. 先明确“整个 Site Zone 都亮”的业务语义**

已确定：设备接收到 Site Zone 触发后，亮度、保持时间、渐变、Photocell、手动覆盖等仍由各自所属 Group Profile 决定，Site Zone 不增加强制开灯优先级。拓扑建议仍为同一个 Site Zone 的有效成员互为直接逻辑邻居，继续按现有 Group/Space 邻接关系传播；交叠 Zone 是否允许继续扩散仍待明确。

这与“所有成员无条件同时达到同一亮度”不同。后者可能需要单独的固件触发类型、优先级或新的 Zone 语义；不应把保存动作偷偷变为 AUTO/强制开灯。

例：Space A 的 Path 为 A1—A2—A3，Space B 的 Path 为 B1—B2—B3；Site Zone 为 A2、B2。保存后 A2 的邻居为 A1、A3、B2，B2 的邻居为 B1、B3、A2。实际触发能传播到哪些节点，还受固件 Relay、去重、密钥、无线覆盖和各节点 Profile 状态约束。

尤其需要验证：

- A2 触发后 B2 是否把事件按自己的配置继续转发；返回方向也要验证。
- Relay=0/1/2 的真实含义、跨不同 Relay Group 后是否重置传播预算。
- 无传感器灯具可以作为被触发成员，但只有具备相应传感能力的设备能作为本地感应源。
- 同一设备属于多个 Site/Space Zone 时，是否按共享邻接图继续扩散到另一个 Zone；若产品要求 Zone 严格隔离，现有单一邻居表无法表达这一边界。
- 去重是否跨 AppKey/子网生效；两个传感器同时触发、交叠 Zone 和环路不能造成持续重触发或异常延长保持时间。

私有协议把 `0x41/0x02` 定义为一份应用索引、Enable、Relay、TTL、Neighbor Count 和地址表，ACK 仅返回成功/错误码，没有回读完整配置。`0x41/0x00` 定义了事务号与源地址；当前文档仍不足以证明所有在用固件的实际转发策略。

本地协议：`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/_protocols/sunricher_protocol_vendor.md:277`、`:828`。

**3. Primary NetKey/AppKey 的选择**

跨 Space 并非标准强制要求使用“Primary”这把特定密钥。当前没有经过验证的桥接方案时，需要让通信端点共享可用的子网与应用密钥，并在处理触发的 Model 上完成绑定；使用当前 Site Primary 是候选实现。AppKey 绑定到特定 NetKey，只有加入 NetKey 不能执行应用消息。[Bluetooth SIG：密钥说明](https://www.bluetooth.com/blog/securing-mesh-proxy-applications/)

建议把以下状态分别管理：

| 状态 | 含义 |
| --- | --- |
| Space 业务归属 | 设备仍属于原 Space/Group，不因加入 Primary 而搬家 |
| NetKey 已安装 | 能参与该子网网络层通信，不等于能处理邻近照明触发 |
| AppKey 已安装、目标 Model 已绑定 | 具备相应应用消息处理能力 |
| 邻近照明转发 AppKey | 当前单份邻居表转发使用哪把 AppKey |
| 普通 Model Publication/Subscription | Kinetic、传感器上报、普通灯控原有发送与接收规则 |

推荐保留 Space NetKey/AppKey、业务归属、普通灯控及 Kinetic 发布配置。增加 Site 所需的通信能力，并单独设置邻近照明转发 Key。不要通过把整个全局 currentApplicationKey 切到 Primary 来顺带重写其他 Model。

SDK 的 `subNetworkId` 在缺失时存在依赖全局当前网络的兜底，`parentNetworkKey` 又依赖此值。Site 汇总必须从稳定 Space Membership 解析身份，迁移前修复或拒绝歧义，不能通过 Key 数组顺序猜测设备属于哪个 Space。

**是否同 Group、Group Path、Space Zone 都要换 Primary？**

不是因为“属于同 Group”就必然全换，但只让 Site Zone 被选中的设备加入 Primary 也未必够。

上述例子中，如果 A2 改用 Primary 转发给 A1、A3，而 A1、A3 只有 Space Key，原 Path 就可能被切断。每条有效传播边的发送 Key 都必须能被接收端及其目标 Model 接受。

已由后续需求确定：固件只使用配置的 Key 转发，同一个 Group Path 的设备必须同 Key，即使空 Point 造成传播断开也不能把同一 Path 分成不同转发 Key。首轮“Site 成员 Primary 转发、同 Path 其他节点继续 Space 转发”的混合候选不再采用。双 Key 接收只能作为部署能力，不能替代最终同 Path 同 Key。

当前建议按 [补强分析第 3 节](260909_0959_site_trigger_zone_key_scope_permissions_analysis.md) 计算统一 Key 范围：完整 Path、共享设备及交叠的 Group / Space / Site Zone 继续合并范围。把所有交叠 Zone 也统一 Key 是一致性设计建议，不把它冒充超出“同 Path 同 Key”的已验证固件要求。上述两条三设备 Path 的范围至少为六台，不能只迁移 A2、B2。

这不等于整个 Site 都必须迁移。若选择“受影响 Group 全体预部署”，属于仍待选择的工程策略；还需追踪跨 Group 的 Space Zone 依赖，并在新增成员或 Path 边时重算。

不要一开始就给所有新设备加 Primary。先保持现有 Space 配网，在首次启用跨 Space 能力时部署必要 Key/Bind，再发布邻接配置。当前 Primary 还服务 Site/Gateway，不只为 Site Trigger Zone 存在。

可额外评估专用的 Site Proximity AppKey，绑定于 Primary NetKey，并只绑定必要 Model。这有助于限定应用权限，但会增加 Key 管理与模型容量要求；若现有一个 Vendor Model 承担多个功能，也不能声称能隔离其中每一种 Vendor 命令。是否采用要结合 Editor 获得哪些密钥、服务端下发范围和固件能力决定。

**现有设备是否全部支持？**

不能根据 App 能构造 ConfigNetKeyAdd 就得出肯定结论。能力清单至少包括 PID/固件版本、当前 NetKey/AppKey/Model Bind 数量、剩余容量、目标 Vendor Model、Neighbor 上限、持久化和重启行为。新设备、升级旧设备、导入设备、Restore 设备均需覆盖。仅凭 `isKeybindComplete` 或 `.mainNetwork` 标记不能证明实际设备已完成 Site 专用配置。

**退出 Site Zone 后能否不退 Key？**

可以把“普通退出 Zone 保留已安装 Key”作为策略，降低反复配置成本。但仍必须更新退出设备和剩余设备的合并邻居表，撤销失效依赖，并记录失败清理；保留 Key 不代表退出动作已完成。

保留安装 Key 与保留 Primary 转发模式是两项决定：若仍沿用 Primary 转发，需要继续保障其本地邻居的接收能力。删掉最后一个 Site Zone 后也必须明确选用哪种模式。

建议记录 Key 的用途/引用关系和安装来源。跨 Site 转移、设备删除、权限撤销、密钥泄露等不能按普通退 Zone 处理；已下发的共享 Key 不会因数据库删记录而失效，必要时需专门撤销/Key Refresh 流程。本文不把自动删 Key 作为第一版普通退出的默认动作。

**4. 无线覆盖不能被 Site 逻辑关系替代**

当前主要邻居同步入口填写 TTL=0，GroupServer 入口使用 defaultTtl，已经存在不同构造入口。新增功能必须明确该字段的统一策略，不能只改一个调用点。

Bluetooth Mesh 的网络 TTL=0 表示消息不会由网络 Relay 继续转发。固件把 Neighbor 配置中的 TTL 如何用于实际发送，需要实测确认。[Bluetooth SIG：TTL](https://www.bluetooth.com/learn-about-bluetooth/feature-enhancements/mesh/mesh-glossary/)

Group Profile 中的邻近照明 Relay 与 Mesh 网络层 Relay/TTL 是不同层次。增加 Primary Key 不等于设备具备可用的跨墙/跨楼层路径。若需要网络 Relay，中间节点也要具有相应 NetKey 及 Relay 能力；纯网络转发本身不需要 AppKey。多个 Space 地理上不连通时，共享 Key 也无法让它们互相触发。[Bluetooth SIG：Mesh 网络与密钥](https://www.bluetooth.com/bluetooth-mesh-networking-primer/)

初期验收必须在 App 断开、网关离线的条件下验证本地设备触发。若业务要求跨物理隔离区域，应另行定义网关/桥接架构，不能假定普通多子网设备会自动桥接。[Bluetooth SIG：Subnet Bridging](https://www.bluetooth.com/mesh-subnet-bridging/)

**5. 权限与 Editor 进入 Space 的处理**

已确定：“所有 Spaces”指当前 Site Zone 的全部成员 Spaces，不是整个 Site 的无关 Spaces。Owner 或 Editor 都具有编辑能力；任一成员 Space 只有 Visitor、No access 或权限未确认时，不能把 Zone 作为完整可编辑对象。原型中的只读示例与此一致。

写入预检另外核对修改前/后成员 Spaces 的并集及实际需要改动设备的 Space。若统一 Key 范围经其他 Zone 扩展并确实需要写入额外 Space，必须具有相应权限；只是存在关联但设备目标不变，不应因此重复要求写入或同步。角色与占用分别判断，不能把被占用的 Editor 显示成 Visitor。

当前 `SiteData.deviceOperates` 对“有任一 Editor Space”就允许一些 Site 设备操作，不能作为 Site Zone 编辑权限复用。`SpaceData.canEditing` 也没有表达整个跨 Space 会话的原子占用。

推荐第一版规则：

| 情形 | 建议行为 |
| --- | --- |
| 具有所需全部 Space 的 Owner/Editor，且没有其他编辑占用 | 取得服务端跨 Space 编辑会话后允许保存/同步 |
| 其中一 Space 被另一用户 Owner/Editor 占用 | 可查看或保留本地草稿，禁止发布及设备下发；明确哪个 Space 被占用 |
| 同一用户同一设备已有 Space 会话 | 由服务端验证后扩展/转移为联合会话，不能只比较 userId 就跳过冲突 |
| 同一账号另一台手机正在编辑 | 仍视为独立会话冲突，用 session/device 身份区分 |
| Site 会话进行时有 Editor 进入相关 Space | 允许读取；编辑/配置需等待或走显式交接，不允许同时覆盖共享设备状态 |
| 同步中失权、租约失效、断网 | 停止新的下发，保留已知 ACK 与未完成记录，恢复后重新验证版本和权限 |
| 只有某个 Space 的编辑权限 | 可查看允许公开的关联摘要；不允许完整编辑涉及其他 Space 的 Site Zone |

服务端最好一次申请全部目标 Space 的租约，携带版本/会话令牌；全部成功才发布，失败时不能留半套占用。续期、释放、崩溃过期、同账号多设备、Owner 交接都要有明确定义。逐个 GET activeUsers 再逐个 heartbeat 不能消除竞态。

只有单 Space 权限的 Editor 修改本 Space Profile/成员时，会影响 Site Zone。建议由服务端依赖关系生成 Site 待修复事件；该 Editor 不直接同步其他 Space。初版若暂未实现这条安全链路，阻止会破坏 Site 依赖的相关操作，并明确显示需要哪类权限。普通命名等不影响依赖的操作不必拦截。

远端空间缺失可能是无权限、未下载或解析失败，不等于已删除。不能据此静默清空整条 Site Zone。

原型还存在“Space removed、Zone View only、提示替换 Group”的未闭合路径。已删除、移出 Site、失权和加载失败必须区分；普通权限校验不能直接证明已删除对象的修复资格。谁可以修复、远端清理由谁完成仍待服务端与产品共同确定，不能通过本次回填推定 Site Owner 获得所有相关设备写权限。

**6. 独立存储与同步展示**

可以并且建议独立于 Space 存储 Site Zone 的业务数据，但设备配置状态不能完全独立：现有设备只保存一份最终邻居表。应做到业务来源分开、最终目标统一、同步原因可区分。

建议的独立记录：

- Site Zone：siteId、zoneId、名称、schemaVersion、revision、成员、删除标记。
- 成员：spaceId、稳定 groupId（若现有未具备则定义稳定映射）、nodeUUID、commissioning/membership 身份、element 标识；Group/Device Address 作为当前映射，不能作为唯一长期身份。
- 拓扑依赖：各 Space/Group 的版本、有效 Profile、成员快照及其完整性标记。
- 每设备目标：合并邻居、Enable、Relay、TTL、转发 AppKey、必要 Key/Bind、目标指纹及来源。
- 同步记录：operationId、目标版本、节点身份、步骤、尝试次数、ACK 结果/错误码、时间、取消/未知结果、成功应用指纹。

一个节点被多个 Site Zone 或本地 Path 共用时，最终配置只生成一次，不应按 Zone 各写一遍。一个 Zone 的同步状态由其依赖的节点当前版本聚合，其他 Zone/Group 的变化可以使旧成功记录过期。

UI 建议保留三个层次：配置已保存、设备同步完成、服务器结果已确认。失败/停止/等待权限/状态未知不应全部折叠成一个布尔值；丢 ACK 时可能设备已应用，只能显示结果未知并按幂等方式恢复。

原型已提供 `Remove` / `Configuration` 两类任务、按 Space 折叠和设备结果、`STOP`、`RE-SYNC`、`Select all` 及 `5/10 done` 示例，应作为同步交互的现有输入。分类位置不证明严格先移除再配置；进度分母是否按设备或步骤计算仍待定义。保存记录、设备应用状态和云回执不能因使用同一成功图标而混淆。通信范围提示只解释通信类失败，不能替代权限、能力、容量或版本错误的原因。

Space 页面继续展示原本的 Group/Profile 同步状态，同时对实际受 Site 配置影响的节点提供独立原因，例如 `Site Trigger Zone sync pending`。如果对普通 Group 同步图标继续做合并展示，必须能区分原因并路由到有权限的 Site 同步入口。不能 Site 同步失败后仍无条件显示设备“全部已同步”，也不能所有失败都误报为 Group 配置失败。

正常 Space Save、Group Profile、设备 Restore、延迟同步都必须读取合并目标，避免回写 Space-only 邻居表。缺少可靠 Site 投影时，对受影响的邻近照明写入暂停，而不是生成一个删掉跨 Space 邻居的空投影。

新增 Site 专用 API/存储优于把新字段塞进现有整份 Space 上传。服务端应明确版本条件写入、空数组与字段缺失的区别、删除墓碑、依赖失效及同步回执合并；恢复/备份需要同时包含 Site Zone 与必要引用信息。历史快照/旧回执不能覆盖较新的配置。

旧 App 的风险仍然存在：即使它不知道 Site Zone 数据，仍能通过旧 Group Save 覆盖设备邻居表或转发 Key。独立服务端表只能防止部分云端数据覆盖，不能阻止离线旧客户端向设备发旧命令。需定义支持版本、受影响 Space 的编辑升级要求和现场使用约束；如需设备级强保证，还需固件授权/版本机制。不能宣称仅服务端加字段就完全兼容。

**7. Save 和 Sync Devices 的建议事务顺序**

1. 取得完整且有版本的 Site/Space 快照，计算旧、新合并图及实际影响范围，检查容量/身份/权限/设备能力。
2. 取得全部受影响 Space 的有效编辑会话，重新校验快照版本，持久化已接受的目标与待同步计划。
3. 使用设备原有可达 Space 子网及配置能力部署缺失 NetKey/AppKey/Model Bind；不能从尚未可达的 Primary 直接开始。按 Space 组织 Proxy 连接，显式携带 Key，不依赖页面全局状态。
4. 先满足全部必要接收端和传输依赖，再下发新的转发模式及合并邻居；接收能力不足的迁移范围暂停激活。涉及无线覆盖的 Relay 基础设施也属于前置条件。
5. 逐条记录 ACK/失败/未知结果及目标版本；迟到的旧会话 ACK 不能把新版本标成成功。停止后不发送新的业务命令。
6. 将结果分别投影到 Site Zone、受影响设备和 Space 摘要，服务器确认后更新云状态。重试前重新核对授权和目标，只重试仍必要的步骤。

设备之间没有现成的原子提交，第二阶段写邻居时仍可能短暂部分生效，失败后的现场状态必须如实展示。若要求严格“全亮能力一次性启用、失败完全不生效”，需要固件提供 staged config/commit 等能力；不能用 App 事务模拟这种保证。回滚同样可能失败，不建议默默覆盖用户的新目标。

复用现有 Sync Devices 页面与 Session，但需要 Site 专用分区、稳定任务 ID、上下文和持久化回执。当前 ResultCollector 只汇总当前模型结果，不能代替跨重启、跨手机的同步账本。SDK Node 状态也需要补转发 Key/TTL 的已知值/未知值与成功回写，或在 App 建立严格等价的版本化记录。

对原型按钮的执行约束：停止新任务不等于撤销已应用配置；在途结果仍须归属于原 operationId 和目标版本。选择失败项重试也要重新核对必要前置步骤，不能绕过 Key/Bind、身份、授权和版本校验。Remove 相关计划必须由旧/新合并目标生成，不可因该分类名称而清空其他 Path/Zone 贡献的邻居或直接退 Key。这些延续既有同步与清理约束，不替代尚待明确的 Save 跳转、STOP 收尾、退出和重试产品流程。

**8. Kinetic Switch 的影响**

单纯新增 NetKey/AppKey、保留 Space Model Bind 和原 Publication/Subscription，从机制上不必破坏 Kinetic Switch。当前 EnOcean Proxy Publication 明确使用 `currentApplicationKey`；如果在 Primary 上下文复用初始化/开关配置，可能错误改成 Primary 发布，造成原 Space 目标不响应或控制边界改变。

所以应限定 Site 部署只操作必要 Key/Bind 和邻近照明字段；Kinetic 的 Proxy 发布 AppKey、目标地址、CCT/Level/Scene/AUTO 等保持各自业务上下文。新增应用绑定也会扩大有权发送到该 Model 的主体范围，需结合实际密钥分发审计，不能只看按钮是否正常。

必须真机回归：短按、长按调光、CCT、Scene、AUTO/OFF、Proxy 更换/重绑/删除，以及在两组不同 Primary/Space Key 配置下的交叉控制与不串控。验证断开 App 后仍可使用；新增 Key、退出 Zone、重启、Restore 后均需覆盖。

**9. 生命周期必须覆盖的触发点**

| 变化 | 应处理的 Site 影响 |
| --- | --- |
| Group Profile 改 Relay、Photocell 或保持策略 | 按实际变化生成设备任务；沿用补强分析 §6，不把普通参数修改一律判为成员失效或全 Site 未同步 |
| Group 切出邻近照明 Profile | 不再作为有效 Site 关系参与规划，生成旧关系所需清理；原型保留禁用成员不代表清理已完成。引用保留方式及切回后的恢复交互仍待确定，已删除关系不能静默自动恢复 |
| Group 成员增删、设备搬组、Space Zone/Path 编辑 | 重算邻居和密钥部署范围，包含原成员和剩余成员 |
| 设备删除、离线删除、Group/Space 删除 | 留删除墓碑和未清理设备记录，不能因本地对象没了就丢任务 |
| Restore、重新配网、地址复用 | 重新绑定稳定身份和元素映射；旧设备的成功回执不可复用到新实例 |
| Site 转让、Space 解绑、权限/密码变更 | 分开处理逻辑依赖、编辑资格、已部署密钥及待同步责任 |
| 云导入、旧 App 写回、备份恢复 | 校验 schema/revision/完整性，拒绝错误快照覆盖可靠状态；权限元数据不能因保留本地草稿被跳过 |
| 多 Zone 重叠、删最后一个 Zone | 保留其他关系，重新确认转发模式、Key 引用和已部署能力 |

原型已表达 Group 删除后的替换入口，但“选择替代 Group”尚未定义为“整组加入”或“重新选择设备”。实现仍需保留稳定设备身份和旧成员清理证据，不能通过地址复用推定替换成功；具体失效引用模型与恢复流程保留为待决策项。

**10. 按验证关卡推进的开发建议**

每阶段先达到验收标准，再进入依赖它的下一阶段。正式 UI 编码和视觉验收可后置，但会影响模型/API 的交互规则应在对应设计定稿前收敛；不能等阶段 7 才发现 Test、草稿、替换 Group 或修复授权改变了数据模型。阶段 1–6 可通过纯逻辑测试、调试入口和小型设备场景验证。

| 阶段 | 交付内容 | 通过后再继续的标准 |
| --- | --- | --- |
| 0：确认语义与盘点 | 固定已确定的 Profile 优先级、Zone 成员 Space 权限和同 Path 同 Key；收敛 Zone 重叠、添加/草稿、Test/Reset、修复和离线规则；记录 PID/固件及容量基线 | 形成可判定成功/失败的场景表；区分已确定需求、原型事实、待决策项与硬件未知能力 |
| 1：最小硬件验证 | 两 Space、每 Space 至少三灯和一个感应源，包含原 Group Path；验证双 Key、转发 Key、Relay、TTL、重启、真实感应 | App 断开后跨 Space 双向触发及原 Path 均符合预期；确认迁移范围与是否要改固件。未通过就先解决协议能力 |
| 2：服务端与权限契约 | 独立 Site Zone API、revision、依赖查询、联合编辑会话、失权/旧版处理 | 两账号/同账号两手机竞争只有一个有效写者；租约丢失/旧版本提交不能写入；旧 Space 上传不清 Site 数据 |
| 3：纯拓扑和身份模型 | Site 成员与完整快照模型，合并计划、容量、依赖/Key 范围；暂不接正式 UI | Path/Group Zone/Space Zone/Site Zone 并集、184/185 边界、重复地址、身份变化、缺失空间、移除节点测试通过；无 Site 数据时旧计划完全一致 |
| 4：密钥部署与 SDK 状态 | 显式网络上下文、必要 Key/Bind 部署、转发 Key/TTL 状态与差异、Restore 支持 | 单独改 Key/TTL 能生成任务；中断后恢复；ACK 丢失/Key 已存在幂等；普通 Publication 与 Kinetic 不变；受影响 target 构建通过 |
| 5：Site Sync 集成 | Site 专用任务与每 Space 分区，复用 Sync Devices/Session，持久化结果与版本 | 部分失败、取消、权限丢失、跨 Space Proxy 切换、重启重试、迟到回包通过；成功节点不被旧任务回写 |
| 6：生命周期与 Space 投影 | 接 Profile/成员/删除/Restore/导入的共享入口；维护依赖，标明 Site 同步原因 | Site 保存后再做所有旧 Group/Space 操作不会覆盖 Site 邻居；单 Space Editor 无越权；删除离线设备仍能恢复清理 |
| 7：正式 UI | Site 入口、Zone/Space 展示与搜索；三种添加模式及连接/暂停/Retry；占用提示；按已收敛规则实现 Save、STOP、RE-SYNC、异常修复；英文 UI 与简体中文本地化 | 覆盖三 Space Zone、只读完整分区、切换添加目标、连接失败及同步恢复；iPhone/iPad 真机完整约束与交互验收，包含旋转/分屏、空态、长名称和权限变化；只编译不算通过 |
| 8：综合发布验收 | 多 Space/多 Zone/边界容量/现场距离/多传感源，旧流程与品牌回归 | 五个共享品牌 target 的 generic iPhoneOS 构建与所需设备实测；服务器回读、断电重启、无 App 运行、Kinetic 和旧功能通过后再启用 |

涉及 SDK、公共资源、本地化或 target 配置时，验证 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 中受影响 target。构建直接使用 xcodebuild，不使用 Simulator。基于变更范围复用现有拓扑、生命周期、持久化、同步会话、Kinetic 回归用例；不通过单纯扩大测试数量替代行为验证。

**下一轮最值得收敛的问题**

已收敛、不再重复确认：权限范围为本 Zone 全部成员 Spaces；额外实际写入不得越权；触发遵循 Group Profile；同 Path 同 Key。

仍待收敛：

1. 多 Zone 重叠是否允许继续传播；是否要求覆盖物理不连通的区域。
2. 首次启用在线授权、迁移短暂不一致及旧客户端升级要求的产品安排。
3. 普通退出保留安装 Key / 转发模式的最终策略；专用 AppKey、整 Group 预部署及撤销维护方案。
4. Test / Reset 的作用对象、新建 Zone 与最低有效成员条件、New only 和三种添加方式的收集规则。
5. 默认连接 Space、模式切换是否复用连接、Manual 是否允许离线草稿选择、未保存切换及跨重启草稿保留。
6. Group 替换和 Profile 恢复时的成员选择、引用保留及确认流程；已删除/移出 Space 的修复资格和清理责任。
7. Save 进入同步的具体交互、进度分母、STOP 收尾、失败退出及重试选择规则。

原型对照中的方案 C 及上述问题的具体推荐仍是候选，不因本次仅回填已确定内容而视为全部批准。后续补强分析继续维护权限与上下文细节；本次不启动功能开发。
