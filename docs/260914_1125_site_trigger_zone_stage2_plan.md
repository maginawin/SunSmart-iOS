# Site Trigger Zone 连接阶段 2：检测、成员草稿与云保存方案

日期：2026-09-14。状态：**方案已确认，客户端增量已实现，阶段 2 发布验收未完成**。初版方案仅核对阶段 1 实现；后续确认记录见下，开发验证与发布条件见 [阶段 2 开发记录](260914_1208_site_trigger_zone_stage2_development_status.md)。

## 目标与交付边界

阶段 2 完成当前 Space 的合格 Proximity 设备检测、三种模式加入当前 Site Zone 的**未保存草稿**、成员展示/移除，以及点击该 Zone 的 Save 后写入 Site `extensionData` 并经 GET 回读确认。切 Space 保留草稿；切 Zone 或真正退出页面提示未保存。涉及成员变更的云保存后显示设备配置待同步，不把“保存成功”表述为现场联动生效。跨 Space Key、邻接拓扑与设备下发仍属于阶段 3。

阶段 1 已交付的连接状态、Retry、同 Space 复用和退出清理继续作为前置条件。正式版 Quick Start 目前只连接，并显示暂不能添加的提示；阶段 2 完成后才移除该过渡提示。

## 现状与必须修正的缺口

| 模块 | 当前事实 | 阶段 2 要求 |
| --- | --- | --- |
| `SiteTriggerZoneData` / Controller | `members` 只检查数组；`supportsEmptyZoneEditing` 要求全部 Zone 为空；真实条目只渲染空行 | 验证受支持的成员格式，非空 Zone 按 Space/设备完整展示；未知格式原样保留、只读 |
| `SiteTriggerZoneCoordinator` | add/delete 立即本地 commit 并同步；行 Save 只提交已有数据；远端授权判定为“至少一个可编辑 Space” | 成员编辑与持久化分离；Save 只提交选中 Zone；所有旧、新成员 Space 均重新核对有效权限与远端信息 |
| `SiteTriggerZoneCandidateReader` | 已有 `(siteId, spaceId, nodeUUID)` 身份、当前地址与 Group 地址；只读候选，无触发元素映射 | 补齐元素地址到稳定设备身份的映射和完整性检查，地址只作当前会话解析 |
| 三模式 Browse 面板 | Site 设备不可点，Trigger 无结果；Quick 只有连接动作；`canAddDevice = false` | Site 专用可操作候选回调、Quick Adding/Pause/Stop、Trigger 列表、Manual 明确加入；Group/Space 原行为不变 |
| Mesh 回调 | SDK 已有 `addGlobalMessageObserver`；Site 阶段 1 未注册消息观察者 | 只在目标连接有效时按会话版本注册/处理；不覆盖全局 `messageDelegate` |

## 推荐冻结的业务规则

1. **成员契约。** 首次非空写入标记为 `schemaVersion = 2`。每个成员保存 `spaceId`、`nodeUUID`、所属 `groupAddress`、设备主地址快照 `primaryAddress` 和 `deviceAddress`；Site/Zone 身份由父级提供。`deviceAddress` **沿用 Space Trigger Zone**：优先取 Sunricher Vendor Model 所在元素地址，否则取 Node 主地址；收到的 Sensor/vendor 触发源地址只用于定位 Node，不作为持久化成员地址，Manual 加入也使用同一规范化规则。长期去重键为 `(siteId, spaceId, nodeUUID)`，不能跨 Space 按短地址去重。现有 Group 没有已证实的稳定 ID，`groupAddress` 只作为所属 Space 内的当前绑定快照；Group 删除、地址复用或 Profile 失效时标记引用失效并阻止静默重绑。解析时保留未知扩展字段，重复/缺字段/未来版本整体只读，不丢成员或改写旧数据。
2. **草稿与筛选。** 选中 Zone 时从已保存版本复制一份页面草稿；Quick 检测即加入，Trigger 只产生候选，Manual 从合格设备列表选择。Trigger/Manual 沿用现有“首次选中、再次点击加入”手势；**任一模式的设备加入草稿后**，若目标 Space 连接及会话身份仍有效，则 Identify 该设备。不能在首次选中或已断连时误发 Identify；帮助文案明确说明。当前 Zone 成员不可重复；“Include added”仅允许从其他 Site Zone 再加入。筛选以有效草稿覆盖已保存的当前 Zone，同一设备在多个合格 Group 中出现时沿用候选读取器的归属规则，歧义数据不可加入。
3. **连接与侦测。** 只接受 `SensorStatus.presenceDetected == true` 和 vendor proximity trigger 两类消息；以触发元素地址映射当前 Space 内的合格设备。每次处理均验证页面、账号/region、siteId、zoneId、spaceId、meshUUID、subNetworkId、连接状态、模式、Quick Adding 状态、候选快照版本与权限。切 Space/Zone、断连、后台或退出立即停止旧目标侦测；旧回调即使排队到达也不能进入新 Zone。消息观察者随目标会话版本重新注册/撤销，避免全局单例回调混用。无需先改 SDK。
4. **Quick 状态。** Start 在已连接时进入 Adding，未连接时先 Connecting、成功后才 Adding；Pause 暂停采集而保持连接及草稿；Stop 停止采集并回到 Click to start，也保持同 Space 连接。切到 Trigger/Manual 暂停 Quick；切 Zone 让 Quick 重新等待 Start。意外断连进入 Connection failed，Retry 只恢复连接，不自动续加，需再次 Start。
5. **未保存导航。** 切 Space 保留当前 Zone 草稿。切 Zone、返回/关闭页面时若成员有变更，提供 Save / Discard / Cancel：Save 先完成云端确认再切换，失败或冲突留在原 Zone；Discard 仅丢该页面未提交的成员变更；Cancel 保留当前页面。后台暂停侦测但保留进程内草稿，回前台重新核对连接。推荐跨进程重启**不保留尚未点 Save 的页面草稿**；已点 Save 但网络失败的持久化 pending 继续沿用现有恢复机制。Reset 只丢弃该 Zone 未保存变更、恢复已保存成员；已保存成员需通过 Remove 后 Save 才改变。非空 Zone 的 Delete 在阶段 2 禁用，待阶段 3 有设备清理计划后开放；Test 和设备 Sync 同样保持禁用。
6. **Save 语义。** 保存前重新读取服务器版本、完整成员 Space 清单及 Owner/Editor 有效权限；覆盖新增和被移除的 Space，未知/缺失/失权即阻止提交并保留草稿。`/sitespace/update/siteprops` 的 `props.extensionData` **每次必须发送完整 extensionData 对象**，不是只发送当前 `triggerZones` 片段；以服务端对象为基线只替换选中 zoneId 的成员，保留其他 Zone 和未知扩展字段，提交后经 `siteInfo` GET 回读校验。若基线变化或同一 Zone 已被他人改动，显示冲突并保留草稿，不自动覆盖。云保存必须保留变更前后成员快照或等价版本化待同步记录，不能在 GET 确认后丢掉阶段 3 需要的旧成员清理依据。接口更新均会被接受，服务器自行生成更新时间；客户端 GET→POST→GET 不是原子并发保护。用户接受本阶段暂不补 CAS，改由实际使用中的工程规范降低风险。建议规范明确同一 Site 串行编辑、编辑前刷新、保存回读完成前其他客户端不改动该 Site 的 `extensionData`；并发覆盖风险仍需明示，不得宣称已从技术上消除。
7. **保存后的状态。** 非空 Zone 在重进页面、跨 Space 和权限变化后均从已确认成员重建展示；访问受限的 Space 仍占一个分区，未知访问状态不得伪装为 Visitor/No access。Save 的成功提示应区分“Saved to cloud”和“Device sync pending”；即使云端回读成功，设备状态仍是 pending/unknown。阶段 3 才能标记设备配置完成。

## 开发顺序与可审查增量

| 增量 | 主要改动 | 完成判定 |
| --- | --- | --- |
| 2A 数据契约与草稿 | v2 成员解析/兼容、权限策略、当前 Zone 草稿和筛选投影、非空条目渲染 | 旧空 Zone/未知字段不回归；跨 Space 同地址、重复成员、失权和失效 Group 样例通过 |
| 2B 侦测与交互 | SDK 全局消息观察者适配、元素映射、会话隔离、Quick/Trigger/Manual 操作及未保存提示 | 两类消息、迟到消息、快速切换、Pause/Stop/Retry、切 Space 保留与切 Zone/退出提示通过 |
| 2C 云保存 | 选中 Zone 的权限与版本预检、提交/GET 回读、冲突和失败恢复、状态文案 | 仅该 Zone 改动被确认；其他 Zone/未知字段保留；网络失败不误报成功，重进可恢复已确认成员 |

2A～2C 可分独立评审提交，但**整个阶段 2**以三项均通过为交付口径。阶段 2 不发送设备配置命令，不引入 Key/Auth 数据写入；如果实际侦测需要临时设备配置，先停在需求/协议确认，不把隐式设备写入塞进本阶段。

## 验收与发布门槛

- 纯逻辑及契约测试覆盖旧 schema/未知扩展、重复或损坏成员、跨 Space 同地址、Group/Profile 失效、权限变化、草稿过滤、选中 Zone 单独提交、云冲突/超时/重启恢复；可注入消息源验证源元素、两类触发、重复包、连接断开和旧会话回调。
- UI 改动检查完整约束链，用生产 UIKit 视图的代码驱动布局探针在允许的 `MtestiPhone15` 上自查中英文、320/393/768pt、长 Space/设备名、非空 Zone 多 Space、未保存弹窗、Quick 三状态、Trigger/Manual 候选及动态高度；最终体验仍由人工确认。iOS 构建仍直接使用 generic iPhoneOS 的 `xcodebuild`，不以编译替代布局测试。
- 检查 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`、`Lumineux` 相关 target 的编译与资源归属；新增用户可见文案同步英文和简体中文。运行 `scripts/check_site_trigger_zones.sh`、本阶段新增测试和 `git diff --check`。
- 服务端在测试环境验证 v2 `extensionData` 完整回读、字段保留及权限结果；按已接受的单人串行编辑约束验收，不把它等同于并发保护。实体 Mesh 的端到端侦测及跨 Space 联动留在阶段 3 联调，不以模拟消息冒充现场通过。

## 需要本次确认的取舍

1. 是否按上述 **2A → 2B → 2C** 范围推进阶段 2，且云端保存后明确显示“设备待同步”，不提前宣称联动已生效？
2. Trigger/Manual 是否采用**首次选中、再次点击加入草稿**，加入后且连接有效时 Identify；Quick 断连 Retry 后是否必须再次点击 Start？
3. 未点 Save 的草稿是否只保留在当前页面进程内；切 Zone/退出采用 Save / Discard / Cancel，Reset 只丢未保存改动，非空 Zone 删除延至阶段 3？

前述需求分析与阶段 1 交付记录：[`260914_1016_site_trigger_zone_connection_quick_add_plan.md`](260914_1016_site_trigger_zone_connection_quick_add_plan.md)、[`260914_1102_site_trigger_zone_connection_stage1_delivery.md`](260914_1102_site_trigger_zone_connection_stage1_delivery.md)。

## 确认记录（2026-09-14）

用户确认按 2A→2B→2C 推进，云保存与设备生效分开展示；Trigger/Manual 首次选中、再次点击加入，**任一模式加入草稿后若仍连接目标 Space 则执行 Identify**；Quick 断连 Retry 后仍需再次 Start。未点 Save 的草稿只在当前页面进程内保留；切 Zone/退出使用 Save / Discard / Cancel；Reset 仅丢未保存改动；非空 Zone Delete 延至阶段 3。

接口补充（2026-09-14）：用户确认 `/sitespace/update/siteprops` 支持以 `props.extensionData` 更新 Site Trigger Zones，且每次必须提交完整 `extensionData`。按后续反馈，该更新似乎**无需客户端提供 `updateTimestamp`**；服务器使用自己的时间更新，调用均会被接受。按此接口行为，当前没有可用的版本冲突拒绝契约。

后续取舍（2026-09-14）：用户指定成员处理与 Space Trigger Zone 相同；感应源地址只用于解析 Node，成员 `deviceAddress` 使用 Vendor Model 元素地址或主地址。用户同时接受当前接口存在并发覆盖风险，阶段 2 暂不要求后端 CAS，以实际使用中的工程规范约束为前提继续推进；后端 CAS 不再列为本阶段发布门槛。
