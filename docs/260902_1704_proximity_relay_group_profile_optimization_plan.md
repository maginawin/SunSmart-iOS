# Proximity Lighting 转发次数按 Group Profile 归属优化方案

## 1. 需求结论

本需求合理，建议采用，并明确为以下统一规则：

> Group Sequence、Group Trigger Zone、Space Trigger Zone 只定义设备之间的直接邻居关系；每台设备的转发次数始终实时读取该设备唯一所属 Group 的 Profile。

由此得到两个互不混淆的配置维度：

| 维度 | 唯一数据来源 | 合并规则 |
| --- | --- | --- |
| 设备直接邻居地址 | Group Sequence、Group Trigger Zone、Space Trigger Zone | 三类关系求并集、去重、排序 |
| 设备转发次数 | 设备所属 Group 的 `profile.proximityLightingNumber` | 按设备分别取值，不做 Space Zone 内统一 |

例如：

- Group A 的 Profile 转发次数为 1；
- Group B 的 Profile 转发次数为 3；
- A1 与 B1 被加入同一个 Space Trigger Zone。

最终应为：

- A1 的邻居包含 B1，转发次数仍为 1；
- B1 的邻居包含 A1，转发次数仍为 3；
- 保存 Space Trigger Zone 时，不要求 Group A 和 Group B 的 Profile 设置相同。

## 2. 当前源码事实

### 2.1 三类 Path/Zone 当前都没有单独保存转发次数

当前数据模型已经符合“不额外保存”的方向：

- Group Sequence 只保存有序设备地址；
- Group Trigger Zone 只保存设备地址数组；
- Space Trigger Zone Item 只保存 `groupAddress` 与 `deviceAddress`；
- `proximityLightingNumber` 只存在于 Group Profile，并由本地数据库及云端 Profile JSON 持久化。

因此不需要新增、删除或迁移 Space Trigger Zone/Group Path/Group Trigger Zone 的转发次数字段，也不需要修改云端 Schema。

### 2.2 App 业务模型是单设备单普通 Group

当前 Group 成员页只允许选择：

- 尚未加入 Group 的设备；
- 已经属于当前 Group 的设备。

SDK 侧 `node.group` 返回设备所属的一个普通 Group，`group.nodes` 也以该归属关系反查成员。正常 App 数据中，同一灯具不会同时成为两个普通业务 Group 的成员。

因此，“同一设备属于多个 Group 且两个 Profile 转发次数不同”不是正常业务场景。真正合法的多 Group Space Trigger Zone 场景是：不同设备分别属于不同 Group，各自使用各自 Group Profile 的转发次数。

### 2.3 设备侧允许不同设备使用不同转发次数

SDK 的 Proximity Lighting Neighbor Set 会向每台设备分别写入：

- Enabled；
- Relay；
- TTL；
- AppKey Index；
- 该设备的完整邻居地址表。

协议和当前 SDK 都没有要求同一个 Space Trigger Zone 中所有设备的 Relay 相同。因此按设备下发不同 Relay 在技术上可行。

需要特别区分：

- Profile 页面所称“邻居节点数量”，在设备配置中对应 Relay/传播范围参数；
- Neighbor Addresses 是统一拓扑编译出的直接邻居地址表；
- Relay 不应由 Neighbor Addresses 的实际条目数推导，两者也不要求相等。

## 3. 对现有“统一合并拓扑”的影响

### 3.1 统一合并仍然必要

用户担心 Group Sequence 后续保存会再次改掉 Space Trigger Zone 下发的数据，这个判断是正确的风险提醒，但解决方式不是让各页面分别保存一份转发次数。

正确做法仍是所有入口共用同一个目标计算器：

1. 先合并 Group Sequence、Group Trigger Zone、Space Trigger Zone 的直接邻居关系；
2. 再根据每台设备唯一所属 Group 的当前 Profile 取得 Relay；
3. 生成该设备唯一的最终目标；
4. Group Path Save、Space Trigger Zone Save、Profile Save、Group Sync、设备恢复同步都只消费这一最终目标。

这样，Group Sequence 后续保存可以合法改变邻居地址表，但不能从另一个页面或另一个 Group 带入不同的 Relay；Relay 始终由当前所属 Group Profile 决定。

### 3.2 当前冲突判断的实际范围

当前实现并没有要求 Space Trigger Zone 中不同设备的 Relay 相同。现有 `RelayConflict` 只在“同一个设备地址同时出现在多个 Group Snapshot，且这些 Group 的 Relay 不同”时成立。

由于正常业务模型已经保证单设备单 Group，这套冲突模型在正常数据中不会触发，却带来以下问题：

- 文案容易被理解为跨 Group Space Zone 必须统一 Profile；
- Planner 引入了不必要的多 Group 成员集合与可空 Relay；
- Group Path、Space Zone 添加和保存入口都增加了冗余阻断分支；
- 自动化测试强化了一个不属于产品合法状态的约束。

因此建议移除“不同 Group Profile 必须统一 Relay”的产品约束。

## 4. 完整性边界

### 4.1 Space Trigger Zone 的 `groupAddress` 仍需保留

不保存 Relay 不等于删除 `groupAddress`。该字段仍用于：

- 标识成员所属 Group；
- 验证该设备是否仍属于该 Group；
- 过滤非 Proximity Lighting Group；
- 支持跨 Group 展示、筛选、测试能力判断及云端恢复。

Relay 应通过该成员的有效 Group 归属读取当前 Profile，而不是把当时的数值复制到 Zone Item 中。

### 4.2 非法或陈旧的多 Group 数据不能静默选值

如果旧数据、异常订阅或恢复失败导致同一设备出现多个普通 Group 归属，这属于 Group 成员关系异常，而不是 Space Trigger Zone Relay 冲突。

建议处理原则：

1. 运行时仍以 App 的唯一 `node.group` 归属为准；
2. Space Zone Item 的 `groupAddress` 与实际归属不一致时，继续由清理/校验逻辑忽略或移除；
3. 增加诊断日志，记录设备地址、Zone Group 与实际 Group；
4. 不要求用户为了修复异常成员关系而把所有 Group Profile 的 Relay 改成相同；
5. 如检测到 Mesh 订阅层存在多个普通 Group，应进入 Group 成员修复流程，而不是在拓扑 Planner 中任意选择一个 Profile。

### 4.3 行为会按触发设备所属 Group 呈现差异

允许跨 Group Zone 内每台设备使用不同 Relay 后，同一个 Zone 从 Group A 设备触发和从 Group B 设备触发，传播范围可能不同。这是按 Group Profile 分治的自然结果，应作为产品语义接受并纳入真机验收，而不是视为数据不一致。

### 4.4 新 App 无法完全约束旧 App

当前版本可以通过统一 Planner 防止本版本内各入口互相覆盖，但旧版 App 若仍使用旧的局部计算逻辑，仍可能重新写入不完整邻居表或错误状态。正式发布时需要明确最低兼容版本，或保证新 App 下一次 Group/Space 同步能够重新修复设备目标。

## 5. 优化实施方案

### 阶段一：收敛拓扑策略语义

1. 将 Planner 的成员归属从“设备地址对应多个 Group Snapshot”收敛为“设备地址对应唯一 owner Group”。
2. 每个 Target 的 Relay 直接取 owner Group 当前 `profile.proximityLightingNumber`。
3. 保留三类拓扑关系的全局并集、去重和排序逻辑。
4. 保留无有效 Proximity Group 设备的禁用语义；有有效 Group 但邻居为空时仍保持 Enabled。
5. 不根据 Space Zone 的其他成员 Profile 改写本设备 Relay。

### 阶段二：移除误导性的冲突阻断

1. 移除纯策略层的 `RelayConflict`、`relayConflicts`、`hasRelayConflict`。
2. 移除 Group Path Save、Space Trigger Zone Save、Space 添加设备及节点差量计算中的 Relay 冲突阻断。
3. 删除不再使用的中英文 `proximity_lighting_relay_conflict` 文案，并同步检查所有共享 Target。
4. 将异常归属处理保留在 Space Zone Item 有效性校验及 Group 成员一致性检查中。

### 阶段三：统一所有写入入口

逐项确认以下入口都通过统一 Planner 生成 Relay 与邻居表，不允许页面自行拼装 Relay：

1. Group Sequence 保存；
2. Group Trigger Zone 保存；
3. Space Trigger Zone 保存；
4. Group Profile 修改后的设备同步；
5. Group 成员新增/移除；
6. 普通 Group Sync；
7. Device Restore/重新入网后的修复同步。

当前主要入口已经调用统一 Planner，本阶段以删除遗留旁路、补测试和补诊断为主，不重构无关同步框架。

### 阶段四：自动化回归覆盖

新增或调整以下策略测试：

1. Group A Relay=1、Group B Relay=3，两组不同设备加入同一 Space Zone：允许生成计划，A 设备为 1，B 设备为 3。
2. 跨 Group Space Zone 生成双向直接邻居，但不统一两端 Relay。
3. 保存 Group A Sequence 后，A 设备仍使用 Group A Profile，B 设备仍使用 Group B Profile，Space 邻居关系不丢失。
4. 保存 Group Trigger Zone 后保持相同规则。
5. Group A Profile 从 1 改为 2：只改变 Group A 设备的 Relay，合并邻居表保持不变，Group B Relay 不变。
6. 32 个空 Space Zone 不产生设备任务，也不禁用任何有效 Proximity Lighting Group 设备。
7. Space Zone Item 的 Group 与设备实际归属不匹配时被忽略/清理，不能读取错误 Group Profile。
8. 删除原“相同设备多 Group Relay 不同即要求统一设置”的产品行为测试，改为单 Group 归属不变量与异常数据防御测试。

### 阶段五：真机验收

至少使用两个不同 Relay 的 Proximity Lighting Group：

1. Group A Relay=1，Group B Relay=3；
2. 建立跨 Group Space Trigger Zone；
3. 分别从 A、B 设备触发，确认两种传播范围符合各自 Profile；
4. 依次保存 Group A Sequence、Group B Trigger Zone、Space Trigger Zone，确认 Relay 不被页面保存顺序改变；
5. 修改 Group A Profile 后同步，确认 Group B 不受影响；
6. 断电重启设备与重新进入 App 后复测；
7. 验证 ACK、设备实际行为、App 缓存与云端 Round Trip，不能仅以构建或同步页面显示完成作为通过。

## 6. 建议实施范围

本次优化建议保持聚焦：

- 修改统一拓扑策略、Group/Space 保存入口的冲突分支、相关测试和中英文未使用文案；
- 不新增 Zone Relay 字段；
- 不修改云端 Schema；
- 不改变 Group 单归属产品规则；
- 不改变三类拓扑的邻居合并算法；
- 不顺带处理邻居表容量、Device Restore 的 Space Zone 地址迁移等独立问题，这些应继续按兼容性 Review 中的单独 P1 项推进。

## 7. 验收标准

满足以下条件可认为本优化完成：

1. 不同 Group 的不同设备可在同一 Space Trigger Zone 中使用不同 Relay，不出现要求统一 Profile 的提示。
2. 每台设备所有同步入口都使用其当前所属 Group Profile 的 Relay。
3. Group Sequence、Group Trigger Zone、Space Trigger Zone 只影响邻居关系，不拥有 Relay 副本。
4. 任意保存顺序不会把 Relay 改成其他 Group 的值，也不会丢失另外两类拓扑关系。
5. 空 Zone 不禁用有效 Group 设备。
6. 非法 Group 归属被识别为成员数据异常，而不是通过统一 Relay 掩盖。
7. 聚焦测试、持久化契约、资源语法检查、差异检查及所有引用 NordicSigMeshSDK 的相关 Target 构建通过。

## 8. 最终建议

建议确认采用以下产品定义：

> “统一合并拓扑”只统一直接邻居关系，不统一转发次数。转发次数属于 Group Profile，并按每台设备唯一所属 Group 实时读取。Space Trigger Zone 与 Group Path/Trigger Zone 均不保存自己的转发次数。

在这一前提下，可以移除当前 Relay 冲突阻断。若未来产品允许同一灯具真正同时属于多个普通 Group，则必须另行设计明确的“主 Group/参数所有者”模型；在没有该模型之前，不能通过最后保存者或任意 Group Profile 静默决定设备唯一的 Relay。
