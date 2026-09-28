# Lights 批量删除：确认方案与设计说明

日期：2026-09-28。状态：用户已确认最终方案，并明确按任务串行发送；组播两次间隔 1000ms，第二次完成后再间隔至少 1000ms 才开始下一任务，不穿插其他删除任务。App/SDK 实施与自动化验证已完成，真机验收及 SDK 正式发布待完成。

## 1. 结论与需求理解

以私有 Mesh Vendor `48/02` 替代多选时的逐台 SIG Reset 是可行的优化方向，但不能仅按页面的“全选/整组选中”决定广播范围。必须补齐 Vendor 订阅、共享 Gateway、发送回执、ACK、连接中断及本地清理语义。

用户已明确：

- 原始选中 1 个设备时保留现有流程。
- 多选使用私有协议。广播每目标发 3 次、间隔 1000ms；组播每目标发 2 次、间隔 1000ms；单播每目标发 1 次，相邻单播发送间隔 200ms，不开启 ACK 自动重发，失败可确认 Force Delete。
- Lights 全选且还有其他设备时，提供“仅删除选中的灯 / 删除 Space 全部设备”选项。用户选择后者才能扩大本地与物理删除范围。
- Space 绑定 Gateway 时，提示全部删除将一同删除 Gateway，以及其他关联 Space 将失去此 Gateway；想保留 Gateway 必须先与当前 Space 解绑。用户仍选择全部删除，即将 Gateway 纳入目标，不因存在 Gateway 自动降级成保留它。
- TTL 与其他控制命令相同，完整沿用 App 的现有有效发送策略，不新增此次删除专用的 TTL 下限或覆盖。
- 当前 Proxy 在删除集合内时，其整个任务必须最后发送；不在集合内时不需要专门调整。所有命令发送结束后，至少等待 3 秒，再统一计算/展示结果。
- 非 Proxy 任务按原有稳定顺序串行发送：当前组两次发送间隔 1000ms，第二次提交完成后再等至少 1000ms，才开始下一任务，无论下一任务是组播还是单播；这两个等待间隔内均不穿插其他删除任务。单播提交完成后至少间隔 200ms 再开始下一任务，不阻塞等待 ACK，ACK 仍异步收集。
- 用户已确认按本方案实施。

推荐目标：删除范围可解释，兼容现有本地清理与同步；满足条件时才合并命令。广播三次只是交付策略，不等于逐台退网确认。不能用本地删除成功宣称离线节点也已退网。

## 2. 当前核对基线

| 对象 | 核对结果 |
| --- | --- |
| App | `fix/delete-devices-260928` / `3fe9f11b` |
| 初始工作树 | 只有用户提供的两份分析文档未跟踪，无生产代码改动 |
| 本地 workspace | `SunSmartLocal.xcworkspace`，包含 App、Pods、本地 SDK |
| SDK realpath | `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` |
| SDK | `one-dev` / `a05b869`，无未提交差异 |
| 固件参考 | `/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware` / `585c45a` |
| 验证边界 | 静态读取及官方 TTL 资料核对；未编译、未发包、未运行真机 |

参考：[原 App 删除分析](260928_1622_device_delete_reset_command_analysis.md)、[固件对照分析](260928_1714_firmware_app_delete_reset_comparison.md)。固件仓库中的行为不能自动代表全部在用 PID/历史固件。

## 3. 已证实的遗漏与约束

### 3.1 协议表示、接收范围与安全降级

SDK 当前 SET opcode 是 `0xF0780A`，编码后的 Access 字节是 `F0 78 0A 48 02`。需求里的 `0xF00A78` 应理解为 Vendor 功能与 Company ID 的描述，不应直接替换 SDK opcode 常量。单播响应是 `F3 78 0A 48 02 00`；末尾 `00` 表示接受操作，早于真正退网、擦除和重启。

新流程由 App 使用当前 Space 的 NetKey/AppKey 构造 Mesh 消息，经已连接 Proxy 转发。DST 放 `FFFF`、Group 地址或 Vendor Model 所在元素的单播地址；不把 Proxy 的地址误当作目标，也不走 Force Reset 页的 BLE `0x08` 广播。

Lights 的 `visibleDevices` 同时经过灯类型和名称筛选。判断“所有灯已选中”必须比较选中集合与当前 Space 完整灯集合，不能使用按钮勾选状态或可见项数量。判断广播范围还要检查配置未完成、页面隐藏和同密钥的额外节点，不能只使用过滤后的 `realNodes`。

普通业务组归属来自 `Node.group`，与 Vendor 订阅不等价。默认 `groupSubscriptionModelIDs` 只列灯控 SIG 模型；当前有针对 Up/Down Light 的额外 Vendor 订阅分支，并非所有灯都具备它。固件 `model_has_dst()` 对普通组地址检查模型订阅。因此，整组选中但 Vendor 未订阅时直接组播可能毫无效果。

已确认：没有 Sunricher Vendor Model 对应组订阅的设备回退私有单播。业务组已完整选中时，可以让明确已订阅且密钥正确的设备参与组播，未订阅设备各自单播；不必因为其中一台未订阅就取消其他设备的组播优化。实际订阅者中存在未授权设备、绑定/订阅同步状态不确定时，不使用该不安全组播。此次不为了删除而临时给设备补订阅，不改变历史入组机制。

### 3.2 `FFFF` 包含已明确同意删除的关联 Gateway

Gateway 属于 Site 主网，可关联多个 Space。关联流程会向 Gateway 添加 Space 的 NetKey、AppKey，并将 AppKey 绑定至 Gateway 的 Vendor Model。因此不能仅凭“所有 Space 页面设备已选中”推断 `FFFF` 不会触及 Gateway。

这是源码确认的密钥/绑定关系；该 Gateway 固件是否执行 `48/02` 仍需产品/固件核对。未确认不执行时不能假定安全。

用户已明确修改原建议：若 Space 绑定 Gateway，则在全部删除确认中说明会同时删除 Gateway；需要保留它的用户先自行完成与本 Space 的解绑。继续全部删除时，该 Gateway 进入授权删除集合，不再以保护该 Gateway 为由禁止 `FFFF`。

需要明确删除的是整个 Site Gateway，并清理它在所有关联 Space 的关联；其他 Space 的灯及其他设备不因此删除，但会失去这个 Gateway 的服务。显示网关名称与受影响关联范围，不能只说“从当前 Space 移除网关”。已完成解绑后要按实际密钥/关联同步状态重核，不能仅隐藏 UI 关联就宣称它收不到广播。

这不只是新增一段提示。现有网关删除有独立的服务器授权、`gatewayDelete`、Site 级删除凭据和本地清理；普通 `DevicePermanentDeletionContext` 不能代替。推荐衔接顺序：

1. 在任何退网命令前，冻结当前 Space 和 Gateway 实例，完成全部本地准备及 Gateway 的现有删除权限/联网检查。不能把用户可删除当前 Space 设备自动当作有权删除跨 Space Gateway。
2. 完成 Gateway 服务器删除并可靠记录 `.serverDeleted`。若授权、服务器请求或凭据持久化失败，不开始本轮广播，不绕过为本地强删 Gateway；保留已经发生的服务器变更及恢复依据。
3. 保留 Gateway 当前 BLE 路由和本地 Node，开始 Space 的统一私有退网批次；不调用旧 `resetNodeAfterServerDeletion()`，避免多发 SIG Reset，也不能先删除 Gateway 切断 Proxy。
4. 满足统一收尾条件后，复用 Gateway 的 Site 级清理删除 Gateway 本地记录及所有 Space 关联；广播不能设置“ACK 已确认 reset”为真。
5. 服务器已删除但后续 BLE 失败时，沿用现有 Gateway 的“服务器删除已生效，收尾并记录物理 reset 未确认”语义，不假装 Gateway 完全没删，也不能恢复自动上传把 Gateway 注册回来。普通 Space 节点仍分别按成功/失败处理。

当前 `GatewayDeletionContext` 初始化要求活跃网络为 Site 主网，不能直接在 Space 页强行调用。后续需将其拆成显式 Site 网络快照驱动的服务器/持久化收尾，保留原身份校验；批量发包时保持当前 Space 路由，不在每条命令之间切换主网。没有 Proxy 而选择 Force Delete 时，Gateway 仍需完成上述服务器授权与删除流程，不能只抹本地记录。

对于未被这次确认覆盖的额外接收者，仍需核查和限制范围。所有关联 Gateway 的固件 `48/02` 能力都要在兼容验证中确认；服务器删除成功不能替代物理退网证据。

### 3.3 TTL

使用 App 已有统一的有效发送 TTL 策略：Lab override → 显式请求 TTL → 本机 Provisioner 默认 TTL → SDK network defaultTtl。此次默认不单独指定 TTL；SDK 兜底为 5。它不是读取当前 Proxy 的 Default TTL，也不是读取每个目标节点的 Default TTL。

用户已确认与其他控制命令完全一致：撤销此前建议的 `2...127` 专用预检。不额外限制 Lab 的 0/1，也不强制改成 5；SDK 已有合法性检查和实际传输行为保持一致。不要传 `0xFF`：它是某些固件接口中的默认值标记，不是此 iOS 发送 API 接受的 TTL。诊断日志记录有效值，不据默认值声称全网覆盖。

TTL 0 不经普通 Relay 转发，TTL 至少 2 才允许中继；增大 TTL 也不保证离线、AppKey 不匹配或模型不兼容设备执行。[Bluetooth SIG：TTL](https://www.bluetooth.com/learn-about-bluetooth/feature-enhancements/mesh/mesh-glossary/#ttl)

### 3.4 发送次数、间隔与任务调度

`MeshMessageManager` 普通发送间隔为 200ms，且会合并目标、opcode、参数相同的待发请求。将间隔改为 1000ms 后，与现有节流更容易协调，但一次性把重复命令全部加入普通队列仍可能被合并；背压和其他排队请求也会改变真实间隔。

| 任务 | 次数 | 同目标名义发送时间 | 结果依据 |
| --- | --- | --- | --- |
| `FFFF` 广播 | 3 | 0、1、2 秒 | 三次均完成本任务的写提交，无逐台 ACK |
| 普通组播 | 2 | 0、1 秒 | 两次均完成本任务的写提交，无逐台 ACK |
| 私有单播 | 1 | 不同设备之间至少间隔 200ms | 匹配 `48/02/00` ACK |

使用任务自有的重复调度和任务间节流，复用 SDK 加密、序号、Proxy Bearer；同目标重复间隔 1 秒，组播第二次提交后到下一任务至少 1 秒，单播提交后到下一任务至少 200ms。背压时顺延，不压缩补发或声称空口精确间隔。间隔从实际发送提交记录计算，不从 UI 点击或普通队列入队时间计算；每次独立生成 Network PDU 序号。底层 Network Transmit/Relay 的重复另算。

用户最终决定：非 Proxy 任务不交错，按任务排队串行执行。当前组首发后等待 1000ms，完成第二发，再间隔至少 1000ms 开始下一任务；两个等待间隔都不穿插其他组或单播。单播每台只发一次，完成发送提交后间隔至少 200ms 继续下一任务，不等待本台 ACK 才继续。此处串行的是发包任务，不是将全批次变成逐台阻塞等待 ACK。若组播已经是全批次最后一个任务，则直接从第二次提交完成开始计算至少 3 秒的最终等待，不额外叠加成 1 秒加 3 秒。

该选择使本批次发送更稀疏、时序更直接，但总耗时增加。组播仍使用共享无线信道；在 Managed Flooding 下，不属于该业务组的 Relay 也可能参与转发，组地址主要限制谁处理该 Access 消息，不为该组建立独立信道。不过组播不会预留或持续独占整个 Space 网络，实际传播范围受 TTL、密钥、Relay 和拓扑影响，设备状态上报等业务仍可能同时发生。[Bluetooth SIG：Managed Flooding](https://www.bluetooth.com/mesh-directed-forwarding/)

三次广播或两次组播只能增加接收机会，不能凭次数推导现场丢包率或声明与原 100ms 三发等可靠。按任务串行也不意味着上一任务所有空口中继已完成；当前协议没有这种全网完成通知。

现有 GATT `send` 可以先把分片加入内部队列，SDK 发送返回不能证明 Proxy 已接收。若将“发送完成”作为本地批量删除依据，专用发送入口需要可观察的、属于本任务的完整 GATT 写提交完成或失败结果；若现有接口不能提供，增加最小的任务回执能力。回执上限是交给 CoreBluetooth，仍不是空口/远端 ACK。不能用固定 sleep 掩盖这个边界。

### 3.5 ACK 支持和单播一次

当前 SDK 的 `NodeConfigCode`、`VendorFunctionSet`、`ResponseCode` 尚未覆盖 leave `02`；`SunricherVendorStatus` 不能正常解析该响应，需要补齐。

推荐按需求的严格含义实现“一次”：每台只发送一个私有请求，不开启可靠消息层的自动重发；底层无线重复不算业务重发。SDK 已有 one-shot 发送机制可复用，但其模型接口按第一个 AppKey 选钥，多密钥场景仍需确保使用当前 Space 的明确密钥。

接收匹配至少包含当前任务/网络、源元素地址、响应 opcode、`48/02` 和状态码。其他 Vendor 功能响应不能结束此次等待；非零状态、超时、发送错误均为失败。任务结束后释放自己的监听、Timer 和回执；迟到/重复回调不重复删除，不调用影响其他业务的全局 `cancelAll()`。

成功 ACK 只说明固件接受操作，不证明已经完成擦除。失败后设备也可能因 ACK 丢失而实际退网，强制删除提示需要容纳这种情况。

### 3.6 Proxy 必须整个任务最后发送

所有新多选发送路径都要求当前 Space 的可用 Proxy Ready 会话、匹配的网络/密钥以及发送能力。没有 Proxy 时直接提供取消或 Force Delete；不把命令排队等待未来连接后突然执行。连接前检查一次不足够，每次发送还应核验会话和 Space 身份。

需要将 Proxy 最后解释为严格的阶段边界：

- 先完成所有不会命中当前 Proxy 的删除任务的全部发送；不需要等它们的 ACK 才进入下一阶段。
- 然后才发送 Proxy 所属任务的第一条命令；若是组播，这两条都放到最后；若是单播，只最后发一次。
- `FFFF` 已经覆盖当前 Proxy 时，三发广播本身就是这个最终任务，不另补一次 Proxy 单播。
- 判断是否命中 Proxy 依据实际 Vendor 接收集合，不只看 `node.group` 或逻辑归属。多个组都可能命中 Proxy 时，要拆解/退回单播，保证前序组播不会提前命中它。Proxy 没有 Vendor 组订阅而归入单播时，终末任务就是该单播。
- Proxy 不在授权删除集合时，不调整排序；规划器仍须保证所有命令均不误命中它。
- 每次发送核验 Ready 会话。发送阶段断连或切换 Proxy 时停止未发送任务，不沿用旧排序继续；终末发送已经完成后的预计断连则不倒推之前广播失败。

将发包与等待结果分开：每台单播先注册监听，再受控发送，不逐台等待 2/10 秒才发下一台。ACK 和发送结果持续记录，但不提前汇总完成或删除本地 Node，以免本地删除影响剩余路由；在全部发送终结后的等待阶段统一收尾。

这只能保护当前 BLE 入口，不能保护其他被删除的 Relay/Friend。大量混合任务仍可能在早期中继退网后继续发包。尤其某组只收到首包时，不会因为 App 计划了第二包就延长其生命周期。当前协议下按结果保留失败项并提示 Force Delete；广播无法逐台确认覆盖。要保证任意大网拓扑的完整删除仍需固件协议配合，不把后置等待当作解决中途路径消失的办法。

### 3.7 最后一次发送后至少等待三秒

重新核对发现 `bsp_sys_factory_reset(3000)` 最终调用 `k_work_reschedule()`，每次命令到达都会更新尚未到期的退网任务。Zephyr 文档明确说明该函数替换此前未完成的延时。[Zephyr Workqueue](https://docs.zephyrproject.org/latest/kernel/services/threads/workqueue.html#scheduling-a-delayable-work-item)

因此，同一设备在约 0/1/2 秒收到广播时，通常约第 5 秒才开始 Mesh reset；组播在约 0/1 秒收到时，约第 4 秒才开始 reset。这是理想接收时序下的源码推导，不是实测，且不能假定丢包设备也延后退网。

用户提出最后发送完成后至少等待 3 秒，符合此时序。推荐最终收尾同时满足：

1. 所有计划发送均已完成或被明确终止，没有尚可发送的后台队列/Timer；
2. 距离最后一次实际写提交完成至少 3 秒；
3. 每个单播均已得到有效 ACK、明确发送失败或到达自己的 ACK deadline。

这不是“固定 3 秒一到就超时所有单播”。等待期间持续记录回包和错误；ACK 还没到自身 deadline 时继续等。用单调时钟计算屏障，不能从最后一次入队或按钮点击开始计时。首包前就失败、没有发出任何退网请求时，无需额外空等 3 秒。

3 秒只是最小收尾等待；设备接收可能晚于 App 提交，还存在约 100ms 的擦除调度、Flash 耗时与重启，所以不以计时到达证明实际恢复出厂完成。全部发送后因 Proxy 自身退网产生的断连，不撤销已记录的提交/ACK；未取得 ACK 的单播仍按本任务 deadline 结算。

示例：依次排队三个普通组 A/B/C、两个普通单播 U1/U2、以及包含 Proxy 的组 P，理想无背压时：

| 时间（秒） | 动作 |
| --- | --- |
| 0 / 1.0 | A 首发 / 第二发 |
| 2.0 / 3.0 | B 首发 / 第二发 |
| 4.0 / 5.0 | C 首发 / 第二发 |
| 6.0 / 6.2 | U1 / U2 单播 |
| 6.4 / 7.4 | P 首发 / 第二发，此前其他任务所有命令已发完 |
| 不早于 10.4 | 单播结果也已终结时，开始统一收尾与结果展示 |

上述是调度示意，不是 BLE 抓包或设备验收结果。A 组连续收到两包后，可能约第 4 秒开始退网，此时后续 C、U1/U2、P 任务还未全部发送；按任务串行不能消除早期 Relay 退网的风险，必须保留失败/未确认处理。若本地清理/服务器恢复未完成，最终成功展示继续等待或报告相应失败。

### 3.8 Space 全部设备不只是 Node 数组

Space 还有独立的 `DeviceSwitchData` / 八键开关配置。动能或虚拟开关本身不一定是 Mesh Node，无法靠 `FFFF` 从数据库自动消失；真实电池开关可能同时有 Node 和配置，需要按物理设备去重。

选择删除全部时应纳入这些配置的清理。存在未成功删除的关联代理时，相关解绑/配置清理应保留为待处理项，不假定物理配置已清除。复用现有开关清理时要拆开物理 reset 和本地清理：当前 `deleteSwitch` 会调用静默 reset，不能在新多选路径中意外再发旧 SIG Reset。

“仅删除选中灯”只做现有设备关联清理，不扩大成删除未选择的独立开关。Space、Group、Scene、Schedule 的对象定义仍按现有永久删除语义保留，只移除设备引用；不隐式执行删除 Space。

## 4. 已确认的方案选择

采用有条件合并的私有删除：单选原流程；多选优先 `FFFF` / Group，未订阅者单播。全部删除包含经提示后明确接受的关联 Gateway；广播 3 次、组播 2 次、单播 1 次。非 Proxy 任务按任务串行，Proxy 整个任务最后；发送终结后至少等待 3 秒，并等待单播 ACK 全部终结。固件延迟/两阶段新协议不在本次范围内。

## 5. 方案行为

### 5.1 入口、范围与任务生成

1. 原始选中只有 1 台，直接沿用当前删除流程，不弹整 Space 范围扩展选项。
2. 多选先保存选中 UUID/地址和 Space/网络身份快照。若完整 Lights 集合已选中且有其他 Space 设备或关联 Gateway，询问范围；过滤后的局部全选不自动视为完整 Lights 全选。
3. 建议按钮：`Delete Selected Lights`、`Delete All Devices`、`Cancel`。展示去重后的数量和范围。有关联 Gateway 时同时说明它将从 Site 删除、其他关联 Space 也将失去它；要保留需先与当前 Space 解绑。示例提示：`This will also delete gateway “{name}” from the Site. Other linked Spaces will lose this gateway. To keep it, unlink it from this Space first.` 后续实现同步中英文国际化。用户继续全部删除即接受包含 Gateway，不再另加相同含义的重复确认。
4. 根据明确选择构造最终目标集合，Gateway 使用独立 Site 级 context。当前角色删除权限、Gateway 删除权限、检查点、导入/恢复保护和持久化准备必须预检；服务器操作前的预检失败需取消已准备但未执行的意图。已发生服务器删除时保留凭据，不能当成尚未操作而取消清空。
5. 确认 Proxy、密钥、Vendor 能力与接收范围；有效 TTL 采用与控制命令相同的策略，不增加删除特有门禁。无 Proxy 时普通节点可确认仅本地 Force Delete；包含 Gateway 时仍须完成它的既有服务器删除前置条件。
6. 最终授权集合覆盖相关 Mesh 接收者、包括用户同意删除的关联 Gateway 且兼容性成立时生成 `FFFF` 三发任务。先完成 Gateway 服务器阶段并保存凭据，保留路由，然后才发广播。
7. 否则对完整选中的业务组核对实际 Vendor 接收集合。明确已订阅、密钥正确且无集合外接收者时生成两发组播；未订阅者及其他剩余设备各生成一次单播。不临时补订阅。
8. 对重叠订阅/多元素按 Node 身份去重，每台只归属一个逻辑删除任务；额外检查任何前序组播都不会命中当前 Proxy。无法安全分组时单播，不放宽范围。其他任务全部发送后才启动整个 Proxy 任务。
9. 缺少 Vendor 能力/绑定或兼容性不明的设备不伪装为成功，进入失败/不可执行集合；不自动回退旧 SIG Reset。若广播兼容条件不成立，则重新规划为安全组播/单播。

### 5.2 结果与本地状态

| 结果 | 本地处理 |
| --- | --- |
| 单播匹配 `48/02/00` | 先保存结果；满足全批次三秒等待及 ACK 终结条件后，移除该 Node 并执行永久删除清理 |
| 单播非零 ACK、超时或发送失败 | 保留该节点；最终进入失败列表 |
| 广播三次/组播两次均完成本任务的发送提交 | 保存结果；满足统一收尾条件后，按无逐台 ACK 策略移除任务的已授权目标，不宣称逐台设备已离网 |
| 广播/组播仅部分发送、发送失败或会话失效 | 将该任务覆盖的节点标为失败/结果不确定，保留本地，允许用户最终 Force Delete；已经发出的命令不可撤回 |
| 尚未发送就取消/离开/切换 Space | 不再发送、不删除未执行项；释放本任务资源 |
| 已有部分删除成功 | 保留成功部分，不因其他失败回滚或重订阅 |
| 用户取消 Force Delete | 保留失败部分，保留已完成删除 |
| 用户确认 Force Delete | 重核身份与清理条件，只对失败/未完成集合做本地删除，不再发设备 reset |
| 本地清理或持久化失败 | 独立报告 cleanup pending，保留恢复依据，不能显示全部完成 |
| Gateway 服务器已删除，随后 BLE 失败 | 独立按 Gateway 既有语义完成 Site 级清理并记录物理 reset 未确认，不能把它当作服务器仍存在的普通失败 Node，也不能自动重新注册 |

新 Vendor ACK 不会像旧 `ConfigNodeResetStatus` 一样自动移除 Node。因此 App 必须主动执行“移除 Node + 永久删除清理”，不能只调用现有 `commit()`，因为它要求 Node 已不存在。

优先复用 `DevicePermanentDeletionContext` 的检查点、身份保护、Scene/Schedule 地址清理、光感/开关引用、Proximity Lighting、统计及云同步。不要只删页面数组或复制另一套清理链。一个批次完成后合并刷新、云同步标记和必要的残留节点配置同步。

### 5.3 中断与恢复边界

冻结任务实例和目标 UUID，防止地址复用、Space 切换和迟到回调误删新的设备。删除交互期间阻止重复启动；与正在占用发送链的配置/DFU 等任务发生冲突时返回忙状态，不清空其他任务。

现有 journal 的 `.prepared` 只证明已准备，不能证明 Vendor 已成功提交。推荐在复用 journal 的前提下，以最小兼容字段保存已获得的 ACK 或完整次数的发送提交凭据及目标实例，再做对应本地移除；正常运行遵循最后写提交后至少三秒的屏障。恢复时按原实例幂等收尾，不自动重发退网命令。旧日志缺少新字段时仍采用原来的保守恢复规则。Gateway 继续使用独立 Site 删除凭据，服务器删除已确认后即使凭据写入失败也不得误恢复自动注册；需与现有恢复流程共同验证。

发包与持久化无法形成跨设备原子事务。若 App 恰在发出命令之后、保存结果之前终止，只能保留“结果未确认”，不能自动当成功；设备可能已离网，后续允许明确 Force Delete。需要把这个不可消除窗口与“已有完整凭据的本地清理可恢复”区分开。

## 6. 开发边界与后续阶段

这涉及跨类别清理、Gateway 服务器流程与 SDK 配合。用户已确认实施，App 与 one-dev SDK 的改动同时推进，实施与验证记录见第 9 节。此文档持续更新，不另建同内容分析/总结文档，不自动 commit。

模块边界如下：

- **Lights 入口**：单/多选分流、范围确认、进度和失败/Force Delete UI；复用项目弹窗及中英文国际化。
- **App 批量计划与任务执行**：基于不可变快照决定广播/组播/单播；非 Proxy 任务按任务串行，同目标重复间隔 1 秒，组播第二次提交后至少 1 秒才开始下一任务，单播提交后至少 200ms 开始下一任务；Proxy 整个任务最后；三秒等待与单播 deadline 共同决定收尾。
- **SDK 协议与发送**：补 leave 编码/状态；复用并约束一次发送及接收监听；提供完成广播三发/组播两发所需的最小回执。保持现有普通队列和单设备 SIG 行为。
- **本地永久删除与开关配置清理**：统一成功、强制删除、持久化恢复入口，阻止新多选清理暗中再发旧 reset。
- **Gateway 删除衔接**：复用既有服务器授权和删除语义、Site 删除凭据及全部关联清理；支持从显式 Site 快照执行准备/收尾，把统一私有发包接在两者之间，保留当前 Space 的 Proxy 路由，不提前触发旧 Gateway Reset。
- **依赖发布**：SDK 若有新增接口，记录所需 revision 和差异；正式 App 使用前需要将相应 SDK 发布到正式依赖。仅本机 `one-dev` 编译成功不代表正式远端可构建。

## 7. 实施后的最小有效验证范围

1. **计划行为测试**：单选保留旧路径；筛选全选；完整 Lights 全选的两个范围选项；混合设备；全组/部分组/无组；Vendor 未订阅；重叠订阅；隐藏节点；共享 Gateway；多元素去重；不支持私有协议。
2. **发送行为测试**：模拟时钟和 sender 验证广播 3 次/组播 2 次/单播 1 次；重复间隔 1000ms，组播第二发后到任何下一任务至少 1000ms，单播后到下一任务至少 200ms；组播两发之间和组播后的间隔均不穿插其他删除任务；ACK 等待不阻塞下一发包任务；背压、真实提交计数；Proxy 任务两包均在其他任务全部发送后；多个订阅组不会提前命中 Proxy；最后写提交后三秒屏障不重复叠加组播后的 1 秒，并等 ACK deadline；正确 ACK、非零 ACK、错误源/功能码、迟到/重复 ACK；发送中断连与终末完成后的预计断连分开处理，回调仅结束一次。
3. **数据行为测试**：成功/失败混合；Force 取消/确认；Node 未先删除时的收尾；场景/日程/拓扑引用；真实/虚拟开关配置；日志缺字段及恢复；发送后中断；清理失败保留凭据；Space/Group 等对象不被扩大删除。Gateway 覆盖权限不足、断网、服务器失败、服务器已删后凭据写失败、BLE 失败、Site/所有关联 Space 清理及防止重新注册。
4. **现有检查**：按触及范围复用永久删除清理、配置数据库安全、TTL/协议相关回归，源码匹配结果不当作运行证明。
5. **编译**：稳定后用 `SunSmartLocal.xcworkspace` 构建 SunSmart Debug generic iPhoneOS，使用该工作树稳定 DerivedData；SDK 公共 API、共享本地化/资源配置涉及跨品牌时，合入前覆盖全部受影响品牌。分析阶段不构建。
6. **人工设备验收**：直达/多跳、Proxy 在待删组、离线灯、混合多个组、共享 Gateway、真实/虚拟开关；记录实际次数、提交时间、有效 TTL 与设备最后接收后退网时间，确认本地重进页面和云同步结果。默认由用户运行，不自动操作真机。

重点验收指标：未授权设备不被命中；兼容设备的实际退网；失败设备可保留或明确强制删除；本地配置重载后不复活；选择全部删除时 Gateway 确实从 Site 和全部关联中删除，其他 Space 的设备保留；仅删灯时 Gateway 不被误删。广播成功的显示与日志应表达“指令已发送/本地已删除”，不能显示“所有设备已确认恢复出厂”。

## 8. 证据入口

- [Lights 控制器](../SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift)：`loadDevices`、`updateEditUI`、`deleteNodes`。
- [永久删除清理](../SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift)：`prepare`、`forceRemove`、`commit`、`resume`。
- [Node 消息配置](../SunSmart/Common/Data/Node+MessageHandles.swift)：Gateway 关联 Space 时的密钥添加与绑定。
- [App Mesh 扩展](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)：`subnetAppkeyBindModels`、`deleteSwitch`。
- [Gateway 删除协调器](../SunSmart/Main/Device/Gateway/Model/GatewayDeletionCoordinator.swift)：Site 所属边界。
- [Gateway 删除上下文](../SunSmart/Main/Device/Gateway/Model/GatewayDeletionContext.swift)、[Gateway 控制器](../SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift)：主网身份限制、服务器删除阶段、权限、持久化凭据及跨 Space 收尾。
- [SDK Vendor SET](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift)、[Vendor Status](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift)：opcode、编码、响应能力。
- [SDK 普通发送队列](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshMessageManager.swift)：200ms 和相同请求合并。
- [SDK Node 组订阅](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift)、[默认模型集合](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Utils/MeshUtils.swift)：Vendor 非普遍订阅。
- [SDK 发送回调](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/MeshNetworkManager+Callbacks.swift)、[GATT Bearer](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Bearer/GATT/BaseGattProxyBearer.swift)：one-shot 和内部写队列。
- [SDK TTL 策略](../.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/OutgoingAccessMessageTtlPolicy.swift)、[LabSettings](../SunSmart/Common/Data/LabSettings.swift)：有效 TTL 优先级。
- [固件 prov.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/prov.c)：`op_prov_leave`、3 秒延迟、响应条件。
- [固件 bsp_sys.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/bsp_sys.c)：`bsp_sys_reset` 的 `k_work_reschedule`，重复接收重排退网期限。
- [固件 access.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/patches/nrf_3.2.4/zephyr/subsys/bluetooth/mesh/access.c)：`model_has_dst`。

## 9. 实施计划与执行记录

Goal: 落实第 1–7 节已确认行为，保留单选旧入口。
Architecture: Foundation 计划/执行器 + App 快照与永久清理适配 + SDK 单次 Vendor 发送及 GATT 分片提交凭据。
Tech Stack: Swift、UIKit、NordicSigMeshSDK、现有 SQLite/JSON 恢复机制。Spec: 本文第 1–7 节与用户最终确认。

全局约束：同一 App 工作树及映射的 one-dev；不提交、不发布、不自动真机；正式远端依赖保持不变；中英文文案；所有结果区分提交、ACK、本地清理。

- [x] Task 1：新增 LightsBatchDeletionPlan.swift / LightsBatchDeletionExecutor.swift；先写 Tests/Device/LightsBatchDeletionTests.swift 与 scripts/check_lights_batch_deletion.sh，覆盖目标范围、订阅重叠、Proxy 顺序、背压后的间隔、ACK 和最终屏障。
- [x] Task 2：SDK Vendor SET/Status 增加 leave；新增受控的单次发包入口，复用 SDK 加密/序号/TTL；GATT 记录每批分片的写提交并允许只取消本批未发送分片。先验证分片回执的失败/断连/完成行为，再接入 CoreBluetooth。
- [x] Task 3：扩展删除 journal 的可选发送凭据，验证旧格式与恢复决策；成功凭据写入后才允许本地移除，原实例身份必须匹配。复用开关清理并提供不发 SIG Reset 的入口。
- [x] Task 4：Gateway 显式 Site 快照支持、服务器预阶段与统一收尾；覆盖服务器成功但凭据写失败的保护，不提前删除 Proxy。
- [x] Task 5：新增 LightsBatchDeletionOperation.swift 连接计划/执行/清理，Lights 单多选分流、范围与强制删除 UI、双语文案、五品牌源码资源归属。
- [x] Task 6：执行相关行为回归和适当构建；一次独立完整审查，修复可证实问题；记录 SDK 发布与人工验收待办。

接口核对：Task 1 输出不可变目标 ID/目的地址及次数，Task 2 返回实际分片写提交，Task 3 接收 ACK/完整多播提交证据，Task 4 在发包前服务器删除、发包后本地清理，Task 5 仅由已授权目标驱动这些接口。

Review Focus：未授权订阅者/共享 Gateway；ACK 错配和自动重发；组播后间隔与 Proxy 提前命中；持久化失败或地址复用；服务器已删后的恢复与防重新注册。

Ruling：用户已明确授权实施，不新增确认门；执行记录保留在本任务同一文档，不另建重复计划/总结或自动 commit。SDK 使用直接构造短消息的既有 Access/Upper/Network PDU 类型后交给目标 GATT Bearer，可避免普通队列合并与可靠层重发；不改变普通控制命令队列。

### 当前执行记录（2026-09-28）

- Task 1：计划/执行器行为回归已通过，包括集合外未知订阅者安全降级、主元素无 Vendor 时 FFFF 降级、多组与 Proxy 排序、背压间隔、错误 ACK/超时、部分广播、三秒屏障。
- Task 2：GATT 分片回执行为回归已通过；只取消所属批次，断连/取消/最后分片均只完成一次；每次实际 write 前重核会话。SDK 新增 submitDeviceLeave 明确使用 Space AppKey、原 TTL 策略、无可靠重发。TTL 1 沿用原网络层只本地发送的语义，返回未发生 GATT 提交，不改写 TTL。协议 XCTest 已补充，尚未运行（SDK UIKit/iOS 测试需要支持的测试环境）。
- Task 3：journal 增加可选 leaveReceipt（ACK 或完整提交次数、恢复最早时间、配置实例时间），旧格式回归通过；复用永久清理，独立开关清理禁止附带 SIG Reset/删除组定义。
- Task 4：Gateway 使用显式 Site 快照，在现有 coordinator 的 reset 阶段嵌入整个私有批次；服务器准备和本地收尾继续走原链。新增 HTTP 之前的持久化 uncertain 标记；确认写失败仍保持禁止重新注册，pending flag 可辅助恢复。Gateway 相关行为及现有集成检查通过。
- Task 5：Lights 单/多选分流、范围/网关警告、无 Proxy Force、失败再 Force、双语文案和五品牌源码引用已接入。离开页面/进入后台后停止后续发送，已记录成功凭据留待安全收尾。
- Task 6：SunSmart Debug generic iOS 联合编译已通过；其余品牌验证进行中。配置数据库实际 SQLite/WAL/回滚检查通过。独立只读审查发现并修复两项：unknown 集合外接收者禁止组播；Force 灯成功保留 Gateway 独立清理错误。未运行设备，未提交 Git。

Ruling：未知订阅状态意味着无法排除该节点接收任意业务组命令，因此该批次禁用普通组播；不只检查本地列表中已知订阅者。多元素节点仅当主元素具有当前密钥绑定的 Vendor 模型才允许 FFFF，否则单播到实际 Vendor 元素。
Ruling：SDK 分片队列以 Main Queue 写提交串行化，并为有剩余分片的队列安排继续处理；CoreBluetooth 在 canSend 持续为 true 时不保证额外 ready 回调，不能依赖它确认最后分片。回执仍只到 writeValue 边界。

依赖状态：App 基于 3fe9f11b，SDK 基于 a05b869 + 本次未提交差异；新增 submitDeviceLeave 等 API 必须随 SDK 正式 release 发布后，正式远端入口才具备这些接口。本机 workspace 使用现有映射，未修改正式远端依赖。


### 最终验证与交付

| 验证 | 结果与边界 |
| --- | --- |
| 批量计划/执行器、GATT 回执 | check_lights_batch_deletion.sh 通过；模拟时钟/发送边界，不代表真实 BLE |
| 永久删除恢复与地址清理 | check_device_permanent_deletion_cleanup.sh 通过；旧 journal、最早恢复时间、实例时间及地址复用 |
| Gateway 删除 | check_gateway_deletion.sh 通过；含生产 Context + SDK/数据库替身测试、现有静态集成检查；新覆盖 Space 路由保持、HTTP 未知结果禁止重新注册、pending flag 直接重试 |
| 配置数据库 | check_configuration_database_safety.sh one-dev 通过；实际 SQLite/WAL、隔离、失败检查点、回滚和旧表兼容 |
| TTL | check_lab_light_group_ttl.sh 通过；已有策略和集成契约，不代表多跳空口覆盖 |
| 最终源码构建 | SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 均 exit 0；Debug / iphoneos / generic iOS / CODE_SIGNING_ALLOWED=NO |
| 资源与差异 | 双语 strings、project.pbxproj 格式检查通过；App 与 SDK diff --check 通过 |
| 未运行 | 真机/UI/实际 Mesh 发包、服务器端验收；新增 DeviceLeaveVendorMessageTests iOS XCTest 未执行 |

构建使用既有 SunSmartLocal.xcworkspace 与稳定 DerivedData/SunSmart-fix-delete-devices-260928，正式 project 远端 SDK 声明未改。已有重复资源名、第三方弃用及捕获警告仍存在，未扩大本次改动去处理。代码保留在两个既有工作树中，均未 commit/push/merge。

独立审查的两项 Important 均已修复。另以生产 GatewayDeletionContext 夹具复现并修复了 durable pending flag 较 prepared receipt 更新时的直接重试问题：prepare 采用服务器已删除标记，不会在恢复时降回未确认阶段。实例恢复同时核对 UUID、主地址和创建时间。新增 GATT 发送前会话检查，取消/后台/切换不会让排队分片继续发送。

### 最短人工验收步骤

1. 单选在线灯删除，再选离线灯删除并分别取消/确认 Force；确认单选原交互及结果未变化。
2. 多选两个完整组、一个部分组及无组灯；至少一台无 Vendor 组订阅。查看 DEBUG 的 [DeviceLeave] submitted：组两条间隔至少 1 秒，第二条到下一任务至少 1 秒；单播一次、后续间隔至少 200ms；日志 uptime 是写提交完成时间。Proxy 若在任务内，该任务全部包在最后。
3. 全选 Lights，分别选择 Selected Lights 与 All Devices；后者含传感器/开关配置和绑定 Gateway。检查 FFFF 三条每次至少 1 秒；最后提交至少 3 秒后才收尾，单播若还等 ACK 则继续等待。Group/Scene/Schedule 定义保留，节点引用及独立开关记录清理。
4. 用离线节点、删除途中断连、无 Proxy、取消 Force、确认 Force 各验一次；失败项应保留或只做本地强删，不能多发 SIG Reset。重进页面/重启后成功记录不复活，新配置实例不误删。
5. 在可用于删除验收的共享 Gateway 上选择 All Devices，检查权限/断网/服务器失败及成功场景。成功后 Gateway 从 Site 与所有关联 Space 清除；其他 Space 灯保留；本地清理失败仍显示 pending，Force 灯成功不能掩盖它。

记录所测 PID/固件版本及多跳拓扑。提交回执与 ACK 均不等于已经完成擦除；广播/组播不提供逐台 ACK，最终现场离网情况由设备验收确认。

### 2026-09-28 20:20：修复删除任务被自身记录拦截

用户报告 `batch_delete_context_changed` 提示。源码确认：任务创建 `DevicePermanentDeletionContext` 后，自己的 `.prepared` 记录使 `SpaceConfigurationSafety.isBlocked` 返回 true；任务随后通过 `space.deviceOperates` 检查自身有效性，因删除权限暂时被保护层移除而停止。普通不含 Gateway 的多选路径会在提交命令前退出；直接强制本地删除也会被最终检查拦截。

修复按当前任务持有的 prepared context 提供 journal entry ID，仅在该任务的权限检查中排除这些记录。入口和其他调用者默认仍检查全部待清理记录；同一设备的其他 entry 也不豁免。显式保护标记、待导入/引用清理、损坏日志、权限变化、退出 Space、账号/区域/网络变化、恢复代际变化和后台取消继续生效。未修改发送次数、间隔、TTL、ACK 或 SDK。

新增 `check_lights_batch_deletion_context.py` 并纳入既有批量删除检查。夹具执行生产的记录准备、任务有效性、设备权限和保护文件读取方法，使用隔离文件目录及 SDK/成员关系/检查点边界替身。修复前在“自己的 prepared 记录应允许继续”断言失败；修复后覆盖两个节点的记录归属、清理阶段、外部同节点记录、显式保护、权限/上下文变化及损坏 journal 并通过。它不代替完整 App 或真实 Mesh 验收。

本轮验证：批量计划/执行器/GATT/上下文回归、永久删除地址清理、Space 保护读取、生产删除恢复/部分删除/强删与拓扑清理回归全部通过；SunSmartLocal 的 SunSmart Debug / generic iOS / 无签名构建 exit 0，仍有既有弃用、未使用值及捕获警告。共享逻辑无品牌差异，本轮仅构建代表 target。`git diff --check` 通过，真机未运行。

基于 App `1d4b963b`；本地 SDK 映射 one-dev `2598bd1`，本轮 SDK 无修改。保留开始时已有的 project.pbxproj 和 Info.plist 改动，本轮修复未提交。最短人工回归：连接 Proxy 多选两盏灯删除；再验证失败后的 Force 及无 Proxy 直接 Force，确认不再被本任务的删除记录拦截，正常权限/保护拦截仍保留。
