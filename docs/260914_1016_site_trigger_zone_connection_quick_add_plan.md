# Site Trigger Zone：Space 连接与 Quick add 需求分析及开发方案

日期：2026-09-14。阶段：需求与方案待确认；本次仅分析，未修改业务代码、SDK 或设备状态，也未运行构建与真机测试。

## 结论

交互方向合理：首次打开以 Quick add 等待用户启动；切入 Trigger add / Manually add 时自动连接；同一 Space 的连接在切换分类和 Quick add 暂停时复用；切换 Space 时取消旧会话并连接或等待启动新 Space。**完整的“感应设备加入 Site Zone 并可保存、同步到设备”不适合一个开发 session。** 当前 Site 页面尚未具备真实成员写入能力，不能把连接成功或 UI 出现 Adding 当成完整交付。

建议分三个可验收阶段：① 连接会话、状态 UI、三模式切换及生命周期；② 检测、Site 成员草稿、真实 Zone 保存及云端回读；③ 跨 Space Key/拓扑下发、失败恢复与真机联调。若只安排一个 session，建议先完成①；不能把②③的结果预先承诺为已实现。

## 已核对的实现基线与设计

| 来源 | 发现及影响 |
| --- | --- |
| `SiteTriggerZoneViewController` | Site 面板通过 `GroupPathSequenceDeviceAddView.configureBrowse` 展示候选；`canAddDevice = false`，未注册 Mesh 监听，真实模式未处理设备点击。Space 选择是 `candidateSelection.spaceID`；候选异步请求已有 request ID 防过期机制。 |
| `GroupPathSequenceQuickAddView` | Browse 模式下 Start / Pause / Stop 的点击被明确拦截，且每次 `configureBrowse` 都重置为 `.stop`；连接状态若只存于按钮，异步刷新会抹掉。 |
| Trigger / Manual 浏览 | Trigger 固定展示未连接空态，Manual 是只读候选；二者现在均不会加入真实 Site Zone。 |
| `SiteTriggerZoneData`、`SiteTriggerZoneCoordinator` | `members` 当前新建为空数组；`supportsEmptyZoneEditing` 要求所有 Zone 都为空。Coordinator 只处理空 Zone 的增删与云同步。真实非空成员、权限、渲染、保存、设备同步均缺。 |
| `SpacePathTriggerZoneController` | 已有两类 Proximity Profile 的组过滤、`SensorStatus.presenceDetected` 和 vendor proximity trigger 判定、去重/忽略已添加规则、Quick 自动加入和 Trigger 候选逻辑；目标是固定的单 Space、单 Zone。 |
| SDK `MeshLibManager` | `isMeshNetworkConnected` 是全局布尔值；`setMeshNetworkConnected` 返回 `Void` 且网络装载失败可直接返回。`meshNetworkDisconnect` 操作全局连接。SDK 提供全局连接/消息观察者，但回调必须校验目标 Mesh UUID、NetKey 和会话版本。 |
| [Connecting，635:5779](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=635-5779) | 结构化 Figma 节点是 **Quick add**，显示选择器、资格提示及“Connecting to {Space}”加转圈图标；无 Start 操作。 |
| [Connection failed，635:6028](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=635-6028) | 结构化 Figma 节点是 **Trigger add**，显示错误图标、“Connection failed”和 Retry；计划把同一连接状态用于三种分类，不把 Figma 的固定 343pt 宽度直接套到现有动态面板。 |

历史 [候选展示方案](260912_1119_site_trigger_zone_add_panel_plan.md) 已明确上一阶段只展示/筛选设备，Quick Start 是空操作。本需求是对该边界的后续扩展；同时应遵守 [跨 Space Key 与权限分析](260909_0959_site_trigger_zone_key_scope_permissions_analysis.md) 中的显式网络上下文要求。

## 建议冻结的状态与转移

连接状态属于页面选中的 **Space 会话**，添加状态属于选中的 **Zone + Quick add**；两者分离。会话至少绑定 siteId、zoneId、spaceId、meshUUID、subNetworkId、页面实例及递增 request token。只有 SDK 连接成功且当前全局上下文与目标身份一致才算 `connected`；Bluetooth Proxy 尚未就绪时不应只凭网络对象已装载报成功。建议连接超时按现有 SDK 代理就绪语义设定单一可测试阈值，具体秒数在实现时与产品/SDK 现有规范对齐。

| 事件 | Quick add | Trigger add / Manually add |
| --- | --- | --- |
| 首次进入并选中合格 Space | `Click to start`；不主动连接 | 不适用，默认 Quick add |
| 从 Quick add 切入，Space 未连接 | 自动进入 `Connecting` | 自动进入 `Connecting` |
| 切入时正在连接或已失败 | 保持原会话的 `Connecting` / `Connection failed` | 保持原状态，失败由 Retry 显式重试 |
| 切入时已连接 | Quick 只有 Start 后才自动加入；暂停/停止不改变连接 | 使用当前连接，Trigger 才监听候选，Manual 展示可操作设备 |
| Quick Start | 若目标 Space 已连接则直接进入 Adding；否则显示 Connecting，成功后自动进入 Adding；失败进入 Connection failed | 不适用 |
| Quick Pause | 停止自动加入，保留 Space 连接与已加入草稿 | 切模式时暂停 Quick 自动加入；不暗中继续追加 |
| Quick Stop | 建议停止自动加入并回到 `Click to start`，**不主动断开同一 Space**，与 Pause 的差别是按钮/UI 状态 | 不适用 |
| Quick 中切换 Space | 取消旧连接/监听，必要时断开旧 Space；新 Space 回到 `Click to start` | — |
| Trigger / Manual 中切换 Space | — | 取消旧连接/监听，必要时断开旧 Space；新 Space 立即 `Connecting` |
| 超时、主动断连或连接失败 | `Connection failed` + Retry；Retry 开始一轮新连接；过期回调不得改变新 Space/Zone | 同一连接状态和 Retry 行为 |

连接失败、Connecting、Connected 的状态必须在三种分类共享。切换 Zone 时建议停止上一 Zone 的自动加入/候选监听，保留同一 Space 的有效连接，再将目标改为新 Zone；切换 Site 或离开本页面时释放本页面持有的观察者/定时器，按确切的连接所有权断开，并让 Site 页面恢复 Primary 网络上下文。进入帮助页等临时覆盖场景需单独判断，避免无意重连。

## 需求尚未完整的决策点

1. **“加入”的持久化时机。** 建议沿用 Space Trigger Zone：感应后立即进入当前 Site Zone 的本地草稿，`Save` 才提交 Site `extensionData` 并触发后续设备同步；切 Zone、切 Space、退出、Reset、Delete 时必须定义未保存草稿如何保留或提示。当前真实 Zone 不支持非空成员，必须先冻结成员 schema（稳定 siteId/spaceId/nodeUUID、Group 身份和当前地址）、兼容旧数据与服务端回读规则。
2. **连接断开后的行为。** 建议意外断开后停止 Quick 自动加入并显示 `Connection failed` + Retry，避免无限自动重连、误收别的 Space 消息。Bluetooth 关闭、权限不足、Space 数据缺失应保留可区分的原因；不能全部等同于“超时”。
3. **未连接的 Manual 页面。** 既有方案允许只读离线浏览；本需求要求切入时自动连接。建议保留候选列表/筛选但禁用 Identify 和真实加入，直到目标连接成功；`Connecting`/失败状态覆盖操作区。Trigger 同理在连接成功前不展示感应结果。
4. **切换 Space 后的旧草稿。** 建议旧 Space 已加入当前 Zone 的本地草稿保留；只停止其监听/连接，新 Space 的 `Click to start` 或 `Connecting` 按分类决定。否则跨 Space 建 Zone 的核心目的会在切换时丢失。
5. **选中 Zone、页面生命周期和后台。** 建议切 Zone 立即停 Quick 自动加入但不切换同一 Space 的连接；页面真正退出时清理；App 进入后台时暂停侦测，回前台重新核对准确的 Mesh 上下文。不把过期连接回调写入当前 Zone。
6. **跨 Space 设备配置。** 仅把成员写入 Site JSON 并不等于现场联动可用。需确认统一转发 Key、设备绑定、邻接拓扑、ACK/重试、同步状态以及现有 Group/Space Zone 的共存规则。相关分析已有基础，但尚需协议/固件及真机验证。

## 分阶段开发与验收

### 阶段 1：连接与 UI（建议下一次 session）

- 在 Site 控制器中增加独立连接会话状态机，使用串行切换和 request token 防止旧 Space 装载/Proxy 回调反抢全局 Mesh；复用 SDK 全局连接观察者，不覆盖其他功能的 `messageDelegate`。连接复用与断开必须校验 `meshUUID + subNetworkId`，避免断开别的页面持有的连接。
- 扩展 Browse 配置及 Quick/Trigger/Manual 共用面板：`Click to start`、Connecting、Connection failed/Retry、已连接展示；支持模式与 Space 的转移，并让异步候选刷新不重置状态。按钮/提示文本国际化（英文、简体中文），优先复用既有 Key；按 Figma 对齐状态行和动态高度。
- 建立可注入连接适配器，对已有连接、成功、装载失败、超时、Retry、切分类、快速切 Space、切 Zone、离开/返回及过期回调做状态测试；扩展生产 UIKit 布局探针验证中英文、长 Space 名、窄屏/iPad、错误按钮和动态高度。使用直接 `xcodebuild` 的 generic iPhoneOS 构建，并检查受共享视图/本地化影响的品牌 target。实际 UI 验收遵循项目规则，不使用 Computer Use。
- 阶段 1 完成口径仅为**连接流程可用**。在阶段 2 尚未完成前，不能把连接成功误称为“设备已加入 Site Zone”；若产品不接受分阶段入口，应在阶段 2 合并前保持 Quick Start 对外不可用。

### 阶段 2：检测、成员与云保存

- 从当前 Space 的合格 Proximity Groups 生成稳定的地址→设备身份映射；复用 Space Trigger Zone 的两种触发消息判断，但要同时校验目标会话、权限、Zone、Space、连接状态，Quick 自动入草稿、Trigger 仅列候选，Manual 明确加入动作。
- 定义 Site Zone `members` schema、成员去重/跨 Zone 过滤、权限和旧版本保护；使真实非空 Zone 可渲染、可编辑、Reset/Remove/Save，并通过 Site props 更新与 GET 回读确认。草稿在切 Space 时保留，在退出时按确认的产品规则处理。
- 单元/契约测试覆盖跨 Space 同地址、重复消息、失权、过期消息、云冲突与重进页面恢复；实际布局与真机感应验证。

### 阶段 3：设备同步与跨 Space 联动

- 依据已确认的协议规划统一转发 Key、Bind/Relay/TTL 与关系拓扑；SDK 显式传输 Key、重试、ACK、状态账本及与既有 Group/Space Path/Zone 的冲突处理。该阶段涉及 SDK 时先核实指定本地开发路径，并对全部引用 SDK 的 target 做构建/运行验证。
- 在至少两个 Space 的真实设备上检验感应、保存、跨网转发、失败重试及旧配置回归；完成后才能宣称 Site Trigger Zone 的“加入并生效”。

## 待用户确认的推荐选择

1. 下一次开发先做阶段 1，完整功能按阶段 2、3 继续；阶段 1 的连接入口是否可以先对外开放，取决于产品是否接受“已连接但暂不能加入”的过渡状态。
2. 感应加入采用本地草稿、点击 Zone 的 Save 后持久化；切 Space 保留草稿，切 Zone/退出按未保存提示处理。
3. 意外断开后显示失败并由 Retry 手动重试；Quick Stop 保留当前 Space 连接；同一 Space 切 Zone 保留连接但停止旧 Zone 的自动加入。

## 后续确认（2026-09-14）

用户确认先交付阶段 1，且正式版本开放 Quick add 的 Start 连接入口；连接成功后须明确提示本阶段暂不能加入设备。阶段 2 感应设备进入本地草稿，仅在 Zone Save 时持久化；切 Space 保留草稿，切 Zone/退出提示未保存。意外断开显示失败并由 Retry 手动重试；Quick Stop 保留连接，同一 Space 切 Zone 保留连接但让 Quick add 恢复到需要点击 Start 的状态。本次阶段 1 的实现与验证另见 [交付记录](260914_1102_site_trigger_zone_connection_stage1_delivery.md)。

## 本次文件范围

只新增本文档。工作区原有 `AGENTS.md` 改动保持不动。
