# Site Trigger Zone 3A 实物协议关卡清单

日期：2026-09-14。状态：测试前准备；没有向设备发送配置命令。适用范围是一个明确可回退的测试 Site，且新建的独立测试 Zone **只包含 Space 1 与 Space 2**。日志中的既有 Zone 横跨 Space 3，不能直接作为本关卡对象。

后续范围核对及用户要求见 [3A 测试 Site 范围与旧 Zone 重叠处置](260914_1926_site_trigger_zone_3a_test_site_scope.md)：测试 Site 已确认，但用户要求暂缓现场操作，先补 Debug Log；本清单目前仅作为以后自行测试时的关卡，不是正在执行的现场指令。

离线协议核对、RET 与缓存的证据边界、被动日志字段见 [3A 协议证据与被动日志](260914_2029_site_trigger_zone_3a_protocol_evidence_and_passive_logs.md)。

## 已核实的起点

- 当前日志 Site 的 `get/siteprops` 回读业务成功，完整 `extensionData` 与本机云基线一致；这只确认云目标。
- Space 1、Space 2 的本机 Node 清单各有三台；这六台的缓存仅列各自 Space Key/Bind，未列 Site Primary Key/Bind。该清单不是设备读回。
- 两个 Space 的 `groupInfos.proximityLightingPath` 目前为空，缺少可证明迁移后保留原 Path 的现场基线。
- 标准 Config 层有 NetKey/AppKey/Vendor Model App 的 Get/List，可核对设备上的索引与绑定；Vendor 邻居写入支持转发 AppKey 索引、TTL 和邻居，返回 RET，但现有协议与 SDK 未找到对应 Get。本机 Node 缓存收到 Set 后也不保存 TTL/转发 Key。仅靠 RET 不能证明设备断开 App 后的跨 Space 联动，也不能证明断电保持。
- 当前 SDK 队列默认用 `currentApplicationKey` 发送 Vendor 控制消息。正式发送器必须显式锁定传输 Key，且把它和 payload 内的转发 Key 区分。

## 按顺序执行的现场检查

| 步骤 | 操作及所需证据 | 通过条件 |
| --- | --- | --- |
| 1. 锁定测试范围 | 指定可回退 Site、Space 1/2、两边要参与的设备和当前固件版本；保存修改前的 Site/Space 目标及设备清单，不把 Key 值写入记录。 | 现场可以撤回测试配置，Space 3 和生产联动不在写入范围。 |
| 2. 建立旧 Path 基线 | 先在 Space 1、Space 2 各建立一条可实测的 Group Path，记录触发端和响应端；App 断开后及设备重启后各测一次。 | 每条旧 Path 在原 Space Key 下独立工作，且恢复方法已实测。 |
| 3. 核对 Key 与容量 | 对目标节点使用 Config Get/Status 或明确的设备清单核对 Site Primary NetKey/AppKey 身份、Vendor Model Bind 和可用 Key 容量；区分“未装”“已装”“无法读取”。 | 所有需要转向 Primary 的节点和同 Space 受影响 Path 节点均可完成安装/绑定；未知不当作缺失。 |
| 4. 建立独立 Zone | 新建只含 Space 1/2 设备的 Site Zone，先云保存并 GET 确认目标版本；不要用既有跨 Space 3 的 Zone。 | 仅预期成员改变，旧 Path 目标仍可恢复。当前正式设备同步入口尚未开放，不能将 Save 视为设备测试。 |
| 5. 受控配置与过渡 | 用隔离诊断流程按 Space 先部署该 Space 所有受影响节点的 Primary Key/Bind，再配置完整合并邻居、转发 Key、TTL；逐条记录 Config Status、Vendor RET、失败/超时和实际现场状态。中途有意停止一次，检查旧 Path。 | 任一时点不丢旧 Path/Zone 的必要行为；若一遍按 Space 部署造成不可接受的过渡中断，改评估“两轮预部署 Key → 两轮激活”，正式发送器暂停。 |
| 6. 跨 Space 联动与持久性 | 在两边分别触发，验证双向响应；断开 App/Proxy 后重复，重启或断电恢复后重复；同时重测旧 Group Path。 | 双向跨 Space 和原 Path 在无 App 参与时稳定工作，设备恢复后仍保持目标。 |
| 7. 故障和回退 | 对连接失败、ACK/RET 丢失、部分设备不可达分别记录可观察结果；按修改前完整目标恢复，再重测旧 Path。 | 可明确识别未知/部分成功，回退后原关系正常；不能仅凭缓存值宣称成功。 |

## 放行条件

只有云目标、Key/Bind、转发 Key/TTL、邻居容量、双向现场联动、旧 Path 保留、断线/断电与故障回退全部有证据，才进入 3C 设备发送器。若固件没有邻居配置 Get，正式账本需明确依靠对应目标版本的 RET 加受控现场验收；跨手机无此证据时保持“设备状态未验证”。若任何设备或固件组合无法满足上述条件，记录型号/版本与阻断原因，继续保持正式设备同步入口关闭。

测试 Site 已明确为 `Sep 11 site trigger zone`，但现有跨 Space 3 的旧 Zone 与拟测的 Space 1/2 成员完全重叠，且用户已要求暂缓本人配合的现场操作；因此**可回退的独立写入范围和实物协议结果仍缺失**。`MtestiPhone15` 上的隔离 UI 宿主已补齐新规划源码并验证部分页面布局，不能替代 Mesh 现场关卡。项目规则禁止 Computer Use 控制电脑；后续只在用户自行测试并提供日志时继续核对现场行为，在此之前不开放发送器。
