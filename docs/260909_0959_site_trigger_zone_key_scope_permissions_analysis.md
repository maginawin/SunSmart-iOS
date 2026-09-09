# Site Trigger Zone：Key 作用域、完整空间展示与权限补强分析

日期：2026-09-09。工作树：`site-trigger-zone`。这是对 [首轮分析](260909_0934_site_trigger_zone_brainstorm_analysis.md) 的补充；2026-09-09 17:45 根据本会话上一轮对 [Site Trigger Zone 原型](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=619-5084) 的核对记录回填已确定内容。仅更新分析文档，没有修改业务代码、SDK 或设备状态；原源码检查和测试结果保留其原分析时点，不作为本次重新验证的结果。

**已确定的需求**

- 触发遵循所属 Group Profile，包括相关亮度、保持、Photocell 和手动覆盖规则；Site Zone 不增加强制开灯优先级。具体现场表现仍需按固件版本验收。
- 当前手机用户需要具有该 Site Trigger Zone 全部成员 Spaces 的编辑权限才可编辑，范围不是整个 Site 的无关 Spaces。
- 展示该 Site Zone 时必须保留其所有 Spaces；只有 Visitor 权限时显示 `Visitor`，无访问权限时显示 `No access`。后者为 `no acceess` 的英文拼写修正建议。
- 固件只使用配置的 Key 转发；同一个 Group Path 的设备必须使用同一个 Key。此条作为用户给定的固件约束，不再假设固件能按每条邻居关系自动选择 Key。
- “编辑权限”按现有业务能力理解为 Owner 或 Editor；Owner 已具有编辑能力，不因为枚举不是 `.editor` 而降为只读。

**原型已核对的内容与未决边界**

- Site 入口、按 Zone / Space 展示及搜索、三种添加模式（Quick add / Trigger add / Manually add）、目标 Space 选择、New only、连接失败 Retry 和 Quick add 开始/暂停均已在原型中表达；一个 Zone 有三个 Space 的示例，不能按固定两 Space 实现。
- Owner / Editor / Visitor / No access 及整个 Zone 的 View only 与上述权限需求基本一致；No access Space 仍保留摘要分区。
- 原型已包含 Remove / Configuration、按 Space 与设备展示同步结果、STOP、选择后 RE-SYNC、进度及通信范围提示，不能把同步失败恢复画面列为完全缺失。
- Test / Reset / Delete / Save、未保存切换、Group 替换及 Profile 失效卡片存在，但按钮出现不等于操作语义已经确定。具体待决策项见第 9 节；不将上一轮推荐方案整体转为已批准需求。
- 依据为原型页 `619:5084` 的结构化信息及嵌入位图辅助核对，未验证可点击交互。Manual 成功/失败标注反向须修正；旧式位图的 Sequence 页签不构成已确定的 Site Sequence 范围。具体节点索引已回填到首轮分析的“已核对的原型功能范围”之后。

**1. currentApplicationKey 的准确含义**

它是当前 Mesh Manager 的计算属性，不是固定的 Primary Key，也不是某个设备永久归属的 Key。

正常情况下，SDK 从当前 Mesh Network 的 applicationKeys 中，取第一把绑定到 `currentNetworkKey.index` 的 AppKey。切换 currentNetworkKey 后，下次读取 currentApplicationKey 就会得到对应子网的 AppKey。

| 场景（网络加载切换成功之后） | currentNetworkKey | currentApplicationKey |
| --- | --- | --- |
| 进入 Site 页面 | Site Primary NetKey | 绑定该 Primary NetKey 的 AppKey |
| 进入 Space A 页面 | Space A NetKey | Space A AppKey |
| 进入 Space B 页面 | Space B NetKey | Space B AppKey |
| 从 Space 返回 Site，Site 再次显示并完成切换 | Site Primary NetKey | Primary AppKey |
| 仅在后台拉取 Site 数据 | 不应更改正在显示的 Space 上下文 | 继续对应当前活动 Space |

Site 的切换发生在 `viewDidAppear` 中：若 Mesh UUID 不匹配或者当前不是 Primary，调用 `setMeshNetworkConnected(... site.meshNetworkId, connected: false)`。`connected: false` 只表示不在该调用中主动打开连接，仍会装载并替换当前网络上下文。

Space 在 `viewDidLoad` 调用 `setNetworkConnected()`，后者使用 `space.meshNetworkId` 调用同一 SDK 方法，默认连接参数为 true。其他恢复/重载入口也会调用它。

上述加载通过异步队列执行。因此“页面已出现”与“Key 已切换且 Proxy 可用”不是同一个完成点；同步开始前必须校验加载成功、Mesh UUID、NetKey、AppKey 绑定关系和实际连接条件，不能根据页面类型猜测。

原型另明确描述“选 Zone 后立即连接空间节点”及“添加窗口内切换模式连接空间节点”。这只能证明原型存在连接动作，不能解决一个 Zone 涉及多个 Space 时的目标选择。Site 浏览上下文、添加会话目标 Space、Site 同步任务上下文必须分别识别；添加期间 `(current)` 标签、页面位置或首个成员 Space 都不能代替已确定的目标身份。默认选择、是否复用连接及 Manual 是否必须先连接属于第 9 节待决策项。

切换页面修改的是 App 当前上下文，**不会仅因这一动作把设备中保存的邻近照明转发 Key 或 Kinetic Publication 改掉**；只有后续下发相关配置才会改变设备。

源码：

- App `SunSmart/Main/Site/Controller/SiteViewController.swift:235`、`:246`。
- App `SunSmart/Main/Space/Controller/SpaceViewController.swift:343`、`:703`、`:711`。
- SDK `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:182`、`:200`、`:205`、`:1058`、`:1068`。

**SDK 的几个边界**

- currentApplicationKey 找不到与当前 NetKey 匹配的 AppKey 时，会退回第一把 AppKey；因此返回非空不等于 Key 正确。
- 没有网络或没有密钥时还存在生成 Key 的兜底。Site 预检应直接核验已有明确 Key 记录，不通过该 getter 猜测或创建跨 Space Key。
- mainNetworkKey / mainApplicationKey 虽然用于访问 Primary，但也有回退 current 的行为；不能把调用 mainApplicationKey 当作已证明 Primary 存在。
- 如果未来在同一 Primary NetKey 下新增 Site 专用 AppKey，currentApplicationKey 仍然只是挑选该 NetKey 下第一把 AppKey，不会自动识别“Site Proximity 用途”。必须显式保存用途到 AppKey 的映射。
- NetKey Index 与 AppKey Index 是两种索引，不能假设数值相同；应检查真实绑定关系及 Key Refresh 状态。

**2. 必须分开的两种 Key**

| 概念 | 用途 | 当前情况 |
| --- | --- | --- |
| App 本次消息的传输/加密 Key | 将配置命令发送到设备并获得响应 | 地址发送的普通 Access 消息使用 currentApplicationKey；按 Model 发送的普通路径通常优先使用 node.parentApplicationKey（前提是 Model 已绑定），否则回退绑定列表中的 Key；SIG 配置消息另按 DevKey 处理 |
| 邻近照明配置中的 relayAppKeyIndex | 告诉固件以后用哪把 AppKey 发送触发 | 当前多个入口直接填 currentApplicationKey.index |

SDK `MeshMessageManager.swift:155` 根据地址/Model/消息类型选择发送重载；`MeshNetworkManager.swift:528` 的 acknowledged Model 发送路径优先选择节点 parentApplicationKey。该 Key 又由节点业务子网归属解析，并不直接等于页面 currentApplicationKey。

因此合理流程可以是：使用 Space A 的可达通道为 A2 部署跨 Space Key，再通过设备已支持的应用通道发送配置，命令内容指定 Primary 转发 Key。**“本次用 Space Key 发送”和“设备以后用 Primary Key 转发”可以是不同的配置意图**；指定转发 Key 已安装且绑定的设备行为仍需真机验证。

反例：从 Site 下发后 A2 的转发 Key 为 Primary，随后在 Space A 修改原 Group Path，现有 `SyncDevicesCellModel.swift:665` 会把 currentApplicationKey 即 Space A Key 填入邻居配置。即使邻居表保留了 B2，也可能把跨 Space 通信破坏。

更隐蔽的反例：只改变转发 Key，邻居、Enable、Relay 都没变，当前差异计算不生成任务；SDK ACK 后又没有缓存转发 Key/TTL，重进页面后仍无法判定真实目标是否已应用。

所需最小设计：计划显式包含 siteId、spaceId、meshUUID、节点稳定身份、传输 Key 引用、目标 relayAppKeyIndex、TTL、配置版本；下发时按计划解析和校验，不重新读取全局 currentApplicationKey 推导目标。异步等待和重试后重新验证上下文，但不能让目标 Key 随页面漂移。

现有 MeshMessageHandle 未提供独立 AppKey 字段，不能认为只给 Site Builder 多传一个 Key 就完成。需要检查/补充 SDK 的显式 Key 发送适配或等效的严格会话路由。SDK 按 Model 发送偏向 Space parentApplicationKey，也意味着不能假设切到 Primary 后所有配置消息都会自动走 Primary。

**3. 按新的固件约束统一 Key 范围**

首轮候选中“同一路径内部分设备 Primary 转发、其他设备 Space 转发”不再采用。新增 Key 的接收能力仍可用于分阶段部署，但不能把混合转发模式作为完成状态。

建议将互相连通的邻近照明关系划成统一转发 Key 的范围：

1. 一条 Group Path 的所有有效成员必须同 Key。即使其中有空 Point 导致传播断开，用户给定的整条 Path 同 Key 约束仍需满足。
2. 多条 Path 共享同一个设备时，这些 Path 必须使用同一 Key，因为该设备仅有一份转发配置。
3. Group Trigger Zone、Space Trigger Zone、Site Trigger Zone 的成员也采用统一转发 Key；它们与 Path 的交叠继续合并该范围。这是为保证一致性提出的设计规则，不把超出“同 Path 同 Key”的部分冒充已验证的固件要求。
4. 某范围参与 Site 跨 Space 联动后，统一选定 Site 使用的转发 AppKey；仍保留各 Space Key 和业务归属。
5. 与这些关系完全无交集的 Group/设备继续原 Space 转发 Key，不要求整个 Site 都迁移。

示例：A1—A2—A3、B1—B2—B3 两条 Path，Site Zone 只有 A2、B2，实际统一转发 Key 的范围至少包含六个节点。如果 A3 又通过 Space Zone 关联另一条 Group Path，范围继续扩大。

**同一个 Group 是否全部加入？**

- 固件已给定的最小约束是同 Path，而不是同 Group。没有参与任何相关关系的 Group 成员不一定必须迁移。
- 若为降低新增成员、后续 Path 编辑和维护成本，选择受影响 Group 全体预部署 Key，可以作为工程策略，但要标明其比当前关系的最小范围更大。
- 仅设置 Group 的 network key 不足以替代按设备检查 Key/Bind、转发配置与 ACK；设备支持多个 Key 与使用哪把 Key 转发是两件事。
- 初期建议先准确计算关系范围，再决定是否将受影响 Group 全体作为部署单元；避免为了省分析直接迁移全部 Space。

首次迁移需先使范围内必要节点都具备 Key/Bind，再更新转发配置。设备没有跨节点原子提交，修改转发 Key 期间旧 Path 可能短暂不通；有设备失败时不能将整个范围标为完成。若要求全程无中断，需要固件提供额外迁移能力，当前不能承诺。

退出 Zone 后可以保留 Key；转发模式也可以采用保留既有统一 Key 的策略，以减少再次切换。但要记录这个范围的持久化策略，不因没有 Site Zone 引用就由普通 Space Save 自动退回 Space Key。若主动退回，必须对拆分后的完整 Path/关联范围重新规划并同步，不能逐个节点退回。

**4. 全部 Spaces 可见，不等于全部 Space 配置可读取**

应新增独立的 Site Zone 空间摘要模型。最少包含 spaceId、展示名称/占位、显示顺序、访问等级、状态是否已确认。Zone 详情接口返回完整引用空间清单，并按请求用户附加有效访问等级。

| 用户对该 Space 的权限 | 分区标签 | Site Zone 行为 |
| --- | --- | --- |
| Owner/Editor | `Owner` / `Editor`（或 UI 约定的编辑能力标签） | 只有 Zone 的全部 Spaces 都具备编辑能力且占用检查通过，才整体可编辑 |
| Visitor | `Visitor` | 保留该空间分区，Zone 整体只读；可展示既有 Visitor 授权范围允许的数据 |
| 无访问权限 | `No access` | 保留该空间分区和被授权公开的摘要；不进入空间、不读取其完整设备/密钥配置 |
| 权限尚未取得/网络失败 | 加载或待确认状态 | 不把未知伪装成 Visitor 或 No access；确认前不允许编辑 |

具体无权限时是否公开真实 Space 名称、节点名称或数量，要由接口展示契约明确。用户已要求保留全部空间的存在与标签；这不意味着需要把受限空间的 Mesh 数据和 Key 下载到手机。若名称也受限，仍需有稳定占位分区而不能直接消失。

当前 `Permission` 只有 Owner/Editor/Visitor，且 Space 首次导入需要 NetKey、未知 role 默认 Visitor。不能直接复用这条导入路径处理 No access：

- 不能为了渲染行而给无权限用户返回 NetKey。
- 不能创建假的 visitor SpaceData 塞进 site.spaces，否则会污染权限、云同步、删除判断和设备计数。
- 不能仅遍历本地 site.spaces，因为没有导入的无权限空间可能根本不在其中。
- 不能使用 compactMap 丢掉无法解析的 Space，造成用户误以为 Zone 只涉及剩余空间。

源码：`SunSmart/Common/Data/SiteData.swift:21`；`SunSmart/Common/Data/ImportData.swift:818`、`:1454`、`:1470`。

编辑能力由完整的服务端清单计算；空清单、部分返回、旧缓存、角色未知都不能由于“已加载的每个空间都是 Editor”而错误放行。离线可显示带时效的缓存摘要，不能把它当作当前有效编辑授权。

原型已有按 Zone / Space 名搜索，因此搜索后的子集也不能替代完整清单参与权限计算、序列化或删除判断；命中一个 Space 不会减少该 Zone 的实际成员和授权范围。

原型不同状态画面展示的 No access 摘要字段不完全一致，有的含 Group 名，有的仅 Space 名和数量。已确定的是保留全部 Space 分区及权限标签，不是这些字段全部获准公开；实际名称、数量、Group 信息仍待接口展示契约确认。原型的 Group deleted、Space removed 与 Profile changed 占位也不能复用 No access 或“加载失败”的状态。

**5. 权限范围已明确，但要额外检查实际配置影响范围**

Zone 编辑条件按用户要求：拥有该 Zone 全部成员 Spaces 的编辑能力，不要求整个 Site 所有 Spaces。以下另外两种范围用于写入预检，不能混为 UI 角色定义：

- 修改前与修改后的成员 Spaces 并集：移除某 Space 后也可能需要清理其设备，因此不能只检查保存后的列表。
- 实际设备下发范围：统一 Key 的范围可能经其他 Site Zone 扩大到本 Zone 之外的 Space。

例：Zone Z1 使用 A/B 两 Space，B 中设备又与 Zone Z2 的 C Space 共用 Path。若 Z1 的这次编辑导致 C 的转发配置也必须改变，仅有 A/B 编辑权限不能越权下发 C。应明确提示需要额外权限或由有权限者完成部署；如果 C 的目标完全不变，不应仅因连通就要求重复修改 C。

初版可采取保守规则：缺少实际写入所需权限时允许保留本地草稿，阻止该次发布/同步，不做半套配置。不要默默删除用户无权访问的 Space 来“修复”Zone。

Owner/Editor 角色与当前编辑占用分开显示。另一 Editor 正在使用 Space 时，本人仍是 Editor；不能把角色标签改为 Visitor。可以另显示 `In use` 并暂停编辑/保存。联合占用机制、同账号两手机、失权中断等仍沿用首轮分析。

原型 `Devices not synced` 弹窗说明需全部相关 Space 的编辑权限，但只有通用 OK 提示。实现判断仍需区分成员空间权限不足、额外实际写入空间权限不足、被占用、权限未知以及单纯设备未同步；不能把所有情况归为同一个权限失败。

Space removed 后的修复授权尚未确定。真正删除的 Space、移出 Site 但仍存在的 Space、仅失权及暂时拉取失败必须分开。不能用“必须取得已不存在 Space 的 Editor 身份”造成不可恢复，也不能未经规则定义就跳过其设备写入授权；修复资格、剩余空间清理和远端交接责任仍待共同决定。

**6. Profile/成员修改引起的跨 Space 影响**

触发遵循 Profile，并不代表任意 Profile 修改都必须全 Site 下发：

- 只改本 Group 亮度/保持等参数，若没有改变邻居或转发范围，就按实际受影响设备生成 Profile 任务；Site Zone 可记录依赖版本更新，但其他 Space 已应用且目标未变的节点不应变成失败。
- 改 Relay，只更新需要变化的设备；来源仍是各自 Group Profile。
- 切出邻近照明 Profile、删除成员或增加共享 Path，才需要重算关系、统一 Key 的范围、相关 Site Zone 有效性和清理任务。
- 多个 Zone 共享设备时，结果以每设备目标指纹判定，而不是“只要某 Group revision 改了就把整个 Site 标成未同步”。

单 Space Editor 的正常操作应尽量保留。只在实际破坏 Site 依赖或需要改动无权空间时进入受限流程；不能只因为某 Group 曾参与 Site Zone 就禁用全部 Profile 编辑。

原型的 `changed profile — devices disabled` 只表达界面上的资格/失效状态，不能证明设备已完成撤销配置。切出邻近照明后有效拓扑与旧配置清理需分别处理；普通亮度、保持或 Relay 修改不得一律显示为成员失效。原型保留禁用设备、删除 Group 后选择替代 Group 的具体引用模型、设备选择及恢复确认尚未确定，不能推定整组自动加入或切回 Profile 自动恢复已删除关系。

**7. 原功能的最小接入边界**

- Group/Space UI 仍按原 Profile 与成员编辑；共享 Planner 增加 Site 关系及固定的转发 Key 策略，避免每个页面各自取 currentApplicationKey。
- 所有生成 Neighbor Set 的入口，包括 Node 普通同步、Sync Devices、GroupServer、设备 Restore/延迟同步及共用消防模型入口，都需要核对 Key 来源；不能只改新 Site 页面。
- 普通 Kinetic、Scene、Schedule 等继续原业务网络和 Publication；不因同 Group 加入 Primary 就重建这些配置。
- Site Zone 的空间摘要和同步回执独立存储；共享设备状态准确包含 Enable、Relay、Neighbors、转发 Key、TTL 的已应用值或未知值。
- Site Sync 显式持有完整快照和网络对象生命期，不临时打开多个 SpaceViewController 拼上下文，也不允许后台 Site 拉取抢走当前 Space 全局网络。

添加流程还必须维护目标 Zone、目标 Space 和当前检测任务的身份。异步连接、检测及重试返回时重新核对这些身份；切换目标后，旧任务不能继续将设备加入新的 Zone / Space。具体取消与连接复用策略待定，但不能让最终目标随全局上下文或迟到回调漂移。

原型没有说明三种添加方式是否临时写传感器/上报/Profile 配置。接入前需核对命令；若存在设备写入，就必须在该写入之前检查相应权限、占用和恢复责任，不能统一延后到 Save。这里是条件性接入约束，不宣称现有模式已经包含或不包含临时写入。

同步页的 Remove / Configuration 只是已存在的展示分类；下发仍服从完整合并目标和依赖顺序。STOP 不证明已应用配置被撤销；迟到结果按原操作/版本记录；RE-SYNC 所选任务仍须满足身份、权限及必要 Key/Bind 前置条件。Save 跳转、停止后退出、手选任务如何补齐依赖以及进度分母仍待产品规则收敛。

**8. 下一阶段验证重点**

| 关卡 | 本轮收敛后的验收要求 |
| --- | --- |
| 规则模型 | Profile 优先级不变；整条 Path 同 Key；共享设备导致范围合并；移除后策略稳定；无 Site 数据时旧输出一致 |
| 权限/展示接口 | A=Editor、B=Visitor、C=No access 时三分区都存在，Zone 不可编辑；三者变为 Editor 后重新校验；未知角色与加载失败不冒充无权限 |
| 原型查看与搜索 | 三 Space Zone 不按两 Space 截断；搜索命中某 Space 后，完整 Zone 的成员、权限和删除判断不受过滤影响；No access 的具体公开字段按最终接口契约验收 |
| 影响范围授权 | 编辑 Z1 引起 Z2/C 的设备变化时不越权；旧、新空间并集的清理授权完整；角色和占用状态分离 |
| Key 上下文 | Site → Space A → Site → Space B 切换正确；后台 Site GET 不改变 Space；加载未完成或 Key 缺失不下发 |
| 添加上下文 | 三模式的 Connecting / Retry 对应明确目标 Space；快速切换 Zone / Space / 模式后，旧回调不污染当前目标；按后续确定的复用与草稿规则补完整交互验收 |
| 消息路由 | 配置传输 Key 与固件转发 Key 独立验证；加入多 AppKey 后按 Model 发送不误选；只改 Key/TTL 仍产生必要任务 |
| 真机 | 两 Space 六灯：完整 Path 统一 Key 后，双向触发遵循各 Profile；普通 Group Save 不把转发 Key 改回 Space；断电、取消、重试后结果准确 |
| 同步界面与结果 | 覆盖原型 Remove / Configuration、按 Space 展示、STOP 和选择 RE-SYNC；分类不破坏任务依赖，部分失败与未知结果不误报全部完成；进度和退出行为按后续确定的规则验收 |
| 回归 | Kinetic/Scene/Schedule/Restore/导入、Space 同步图标、完整英文/中文文案和真实布局；按变更覆盖共享品牌 target |

**9. 原型对照后仍待确定的业务规则**

| 主题 | 已有依据 | 仍需确定，不能作为本次已确认内容实施 |
| --- | --- | --- |
| Test / Reset | 原型有入口；Site 触发遵循 Group Profile 已确定 | Test 是识别还是联动验证、是否需已同步版本、临时状态恢复；Reset 是否仅丢弃草稿及最终文案 |
| 新建与成员 | 原型有加号/空 Zone、多 Space 示例；成员身份需稳定 | 最低 Space/设备数、空 Zone 保存、一个 Space 多 Group、后续设备自动加入与否、New only 的过滤对象 |
| 三种添加方式 | 原型有三模式、选择 Space、连接/Retry 和暂停 | 自动入选或二次确认、默认 Space、同 Space 切模式复用连接、Manual 离线草稿选择、检测临时写入与恢复 |
| 草稿与导航 | 原型有 SAVE / SWITCH (Without Saving) | 触发哪些切换、取消留在当前页面、保存失败后的停留、跨重启草稿及失权后可保留的数据 |
| Group / Profile 修复 | 原型保留异常卡片；旧关系清理和稳定身份约束仍成立 | 失效引用模型、替换 Group 后设备选择、切回 Profile 的恢复确认，不能推定整组加入或自动恢复 |
| Space 删除/移出修复 | 无访问权限不等于删除；正常设备写入不得越权 | 服务端确认事实、修复角色、已移出 Space 的授权/交接和未清理责任人 |
| Save / STOP / RE-SYNC | 原型有按 Space 同步和重试；目标、设备状态、回执需区分 | Save 是否立即进入同步、进度计数、停止收尾、退出返回、手选重试补齐依赖的交互 |
| 部署与传播策略 | 同 Path 同 Key、Profile 优先级已确定 | Zone 交叠传播、专用 AppKey、整 Group 预部署、退出后保留 Key/转发模式及物理不连通场景 |

原型对照推荐的方案 C 仍是方案建议。本次更新只回填已确定需求、原型证据和由既有约束要求的分析边界，没有批准上述具体候选，也未认定服务端和设备已具备所需能力。上述影响模型/API 的规则需在相应设计定稿前明确，正式 UI 编码可后置。

**原补强分析的验证及限制（本次文档更新未重跑）**

- 已再次核对当前 App 的 Site/Space 生命周期和 SDK getter、网络切换、发送队列、Model 发送的 Key 选择；本地 SDK HEAD 为 `a6246b1`，工作树干净，与首轮锁定版本一致。
- 执行现有 `zsh scripts/check_site_space_mesh_context_ownership.sh`，检查没有全部通过：末尾导入修复断言要求源码中存在连续文本 `groups: groups.filter { !$0.isVirtual }, spaceTriggerZones: self.triggerZones`。
- 当前 `ImportData.swift:2616` 仍使用导入后的 groups、明确的 network nodes 和 self.triggerZones 构造 importedPlan，并传给 getNodeSyncProximityLighting；由于新增 nodes 参数及换行，测试的旧字符串不匹配。这证明该精确文本断言与当前源码不一致，本轮未据此认定运行时跨 Space 导入错误，也未修改或放宽测试。
- 上述是源码契约检查，不能替代异步导航、Proxy 切换、真机 Mesh 或服务端权限验收；后续实施前应修正测试对语义的覆盖并重新建立基线。
- 本轮未构建 App，未访问实际服务端接口，未读写现场密钥或向设备发送命令。
