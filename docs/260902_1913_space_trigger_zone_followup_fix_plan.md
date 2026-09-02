# Space Trigger Zone 后续问题修复方案

## 1. 目标与边界

本方案基于 2026-09-02 当前 `trigger-zone-july` 工作树，覆盖以下问题：

1. Proximity Lighting 统一拓扑的单设备邻居数量保护；
2. Device Restore 时 Group Path、Group Trigger Zone、Space Trigger Zone 的统一地址迁移；
3. Space Trigger Zone 页面补充 `Devices not synced` 与直接重新同步；
4. Space Trigger Zone 的跨 Group Test；
5. Neighbor Set 成功条件补充 Enabled 校验；
6. Path/Zone 达到 32 个后的提示正确读取本地化。

本轮仅形成实施方案，没有修改 App、SDK、资源、Target 或依赖行为。

---

## 2. 关于 Access Payload 与“255 个邻居”

### 2.1 Access Payload 是什么

Access Payload 是 Bluetooth Mesh Access Layer 中实际承载“Opcode + Parameters”的业务消息。Neighbor Set 的 Group/Space 结构不会直接发给设备；App 会把统一拓扑编译为每台设备的 Neighbor Set，再由 Mesh Upper/Lower Transport 分段发送。

当前 SDK 默认使用 32-bit TransMIC：

- 不分段 Access PDU 最多 11 字节；
- 超过 11 字节会自动分段；
- 每个分段承载 12 字节 Upper Transport 数据；
- SegN 只有 5 bit，因此一条消息最多 32 段；
- 扣除 4 字节 TransMIC 后，Access PDU 最大为 380 字节。

Bluetooth Mesh 官方资料也明确说明，长 Access Message 会由 Upper Transport 拆成 12-octet 分段。参考：

- Bluetooth SIG Mesh Protocol 1.1：https://www.bluetooth.com/specifications/specs/mesh-protocol/
- Bluetooth SIG Mesh Feature Enhancements Summary：https://www.bluetooth.com/mesh-feature-enhancements-summary/

### 2.2 当前 Neighbor Set 的实际长度

当前 Sunricher Neighbor Set 包含：

| 内容 | 字节数 |
| --- | ---: |
| Vendor Opcode | 3 |
| Proximity Lighting 主/子命令 | 2 |
| Relay AppKey Index | 2 |
| Enabled | 1 |
| Relay | 1 |
| TTL | 1 |
| Neighbor Count | 1 |
| 每个 Neighbor Address | 2 |

所以 N 个邻居对应的 Access PDU 长度为 `11 + 2N` 字节。

| 邻居数 | Access PDU | 含 32-bit TransMIC 的 Upper Transport 数据 | 分段数 | 结果 |
| ---: | ---: | ---: | ---: | --- |
| 184 | 379 字节 | 383 字节 | 32 | 当前协议上限内 |
| 185 | 381 字节 | 385 字节 | 33 | 超过 SegN 能表达的 32 段 |
| 255 | 521 字节 | 525 字节 | 44 | 当前协议无法作为一条消息发送 |

如果将来改用 64-bit TransMIC，Access PDU 上限会降为 376 字节，对应最多 182 个邻居。

### 2.3 结论与建议

需要关注 Access Payload。`Neighbor Count` 是 U8，只说明字段最多能表达 255；它不代表当前 Mesh 报文能装下 255 个地址。

当前 Neighbor Set 没有分页序号、偏移量或追加语义，不能由 App 简单拆成多条命令；连续发送多条大概率会被设备理解为多次“整表覆盖”。若产品必须支持 255，需要先扩展 Vendor 协议并由固件支持分片组装/提交。

建议本次采用：

- 字段理论上限：255；
- 当前 App/SDK 的有效硬上限：184；
- 最终产品上限：`184` 与固件实际资源上限中的较小值。

184 只是传输层硬上限，不代表固件一定能保存 184 个邻居。正式发布前仍需固件确认内存上限，并用真实设备验证 `max-1 / max / max+1` 与 `ret = 2`。

---

## 3. 修复一：统一邻居容量保护

### 3.1 App 统一拓扑层

在 `ProximityLightingTopologyPolicy` 中建立唯一容量定义和校验结果：

- 统一 Planner 完成 Sequence、Group Zone、Space Zone 合并和去重后，再检查每台设备的最终邻居数；
- 校验对象是最终邻居并集，不单独限制某个 Path 或 Zone；
- 记录超限设备地址、实际数量和允许上限；
- 不截断、不随机丢弃邻居，也不生成部分设备配置。

Group Path Save、Space Trigger Zone Save 和两个页面的 Re-sync 都必须先检查同一个 Planner 校验结果：

- 有超限时显示中英文提示；
- 不写 Group/Space 逻辑数据；
- 不标记 Cloud Dirty；
- 不进入设备同步页。

新增提示建议：

- English：`A device can have up to %d neighbors. Reduce the devices in Paths or Trigger Zones and try again.`
- 简体中文：`每个设备最多支持 %d 个邻居。请减少路径或触发区域中的设备后重试。`

### 3.2 非页面发送链路

当前 Neighbor Set 还可能从设备加组、延迟同步、恢复和 Emergency 等链路构造。所有 Neighbor Set 构造点需要统一经过容量检查，避免页面保护被其他入口绕过。

对于导入或旧数据中已经超限的拓扑：

- 保留原始逻辑数据，禁止静默截断；
- 设备同步应明确失败并输出容量错误；
- 用户回到 Path/Trigger Zone 页面时能够看到 `Devices not synced`，点击后得到容量提示。

### 3.3 SDK 防御

本地 SDK 路径存在，实施时同步修改 SDK：

- 在读取消息 Parameters、创建 Access PDU 之前做消息预校验，避免邻居数转换为 U8 时发生运行时失败；
- 在 Access Layer 增加通用的最大 Access PDU 检查，低安全级别不超过 380 字节，高安全级别不超过 376 字节；
- 超限通过现有消息发送失败通道返回，不创建可靠消息等待上下文、不进入分段队列；
- 不截断地址、不把 255 自动压成其他值、不发送格式与长度不一致的报文。

SDK 的通用 Payload 保护可以同时防止其他未来消息生成超过 32 段的数据。

### 3.4 测试

- 纯策略：183、184、185、255；
- 多个小 Path/Zone 单独不超限，但合并后超过上限；
- 重复边去重后刚好回到上限；
- 超限时 Group/Space Save 都不持久化、不标记 Cloud Dirty；
- SDK：184 可编码并形成 32 段，185/255 在发送前返回明确错误且不崩溃；
- 所有 App Neighbor Set 构造点必须经过统一保护。

---

## 4. 修复二：Space 级 Restore 地址迁移

### 4.1 统一所有权

新增一个由 `SpaceData` 持有的 Proximity Lighting 地址迁移入口，输入旧、新 Vendor Model Element Address。Device Restore 不再只在 `Node.updateResoreData` 内修改当前 Group。

迁移入口负责当前 Space/Subnetwork 下的：

1. 所有 Group Sequence Point；
2. 所有 Group Trigger Zone member address；
3. 所有 Space Trigger Zone item device address。

使用 Vendor Model 所在 Element Address，与 Planner 的地址归一化规则保持一致；替换全部匹配项，而不是每条 Path/Zone 只替换第一个。

### 4.2 Space 解析

Restore 页面虽然通常持有 `space`，但 Site 入口可能传入空值。调用时按以下顺序解析：

1. 页面已有 Space；
2. 新节点 subnetworkId；
3. 旧节点 subnetworkId；
4. Site 当前 meshNetworkId。

无法确定唯一 Space 时不跨 Space 猜测迁移，记录错误并保留现有 Restore 失败状态。

### 4.3 持久化与 Cloud Dirty

- 先在内存中完成所有引用扫描，得到变更的 Group 集合和 Space Zone 是否变化；
- 没有匹配项时不保存、不标记 Dirty；
- 有变化时只标记一次 Cloud Dirty，再分别保存受影响的 GroupInfo 和 SpaceData；
- 每个受影响 Group 更新 Group Sync State；
- 保留 Restore 完成后的 Space address-change 通知。

虽然需求描述为“写入后标记”，实施顺序建议继续沿用项目现有的 write-ahead 约定：先标记 Cloud Dirty，再持久化引用，避免 App 在两步之间退出造成“本地已改但永不上传”。这里的“统一”是一次迁移只标记一次，而不是每个 Group 各标记一次。

### 4.4 测试

- 旧地址同时存在于 Sequence、Group Zone、Space Zone，全部替换；
- 同一结构中出现多处旧地址，全部替换；
- 无关 Group/Zone 保持不变；
- 旧、新地址相同为 no-op；
- 只保存发生变化的 Group，Cloud Dirty 仅标记一次；
- 页面有 Space 与 Site 入口无 Space 两种 Restore 路径；
- Restore 后重新编译统一拓扑，新地址继承原 Group/Space 邻居关系，旧地址不再出现。

---

## 5. 修复三：Space 页面 Devices not synced 与 Re-sync

复用 `GroupPathSequencePageController` 的现有样式、资源和本地化 key：

- Space Trigger Zone 页面显示红色 `Devices not synced`；
- 页面出现时重新编译持久化后的统一拓扑；
- 比较当前 Space 中所有合格 Proximity Group 设备，而不只检查当前 Space Zone 成员。

必须检查全部合格设备，因为删除 Space Zone 成员后，原成员已不在当前 Zone 中，但设备可能仍保存旧的 Space 邻居。只扫描当前成员会漏掉这种失败。

点击后：

1. 重新生成统一 Plan；
2. 先执行邻居容量校验；
3. 没有差异则隐藏提示；
4. 有差异则使用 Space Trigger Zone 的同步类型进入 Re-sync；
5. 成功返回页面后再次计算并隐藏提示；
6. 失败则继续显示，供用户再次重试。

不新增文案和图片资源。

---

## 6. 修复四：跨 Group Space Zone Test

### 6.1 Test 启用条件

Space Zone 只要存在至少一个有效 Item 就启用 Test，不再要求所有 Item 的 `groupAddress` 相同。

### 6.2 测试组件输入

把共享 Test View 从“一个 Group”调整为：

- 去重、稳定排序后的 Group Address 列表；
- 按 Zone 当前顺序得到的 Device Address 列表。

Group Sequence 和 Group Trigger Zone 继续传入单个 Group 地址，保持原行为；Space Trigger Zone 传入全部 Group 地址。

### 6.3 执行顺序

首次点击 Start 时：

1. 按稳定顺序向每个 Group 依次发送 Unacknowledged Off；
2. 保留现有预等待；
3. 继续按当前 Zone 顺序，每 0.5 秒打开一个设备；
4. Pause/Resume 只暂停逐设备点亮，不重复发送 Group Off；Stop 后重新 Start 才重新执行 Off 阶段。

该 Test 仍是地址和设备位置检查，不代表真实 PIR 邻居传播测试。

### 6.4 测试

- 单 Group Sequence/Zone 行为不变；
- 两个及多个 Group 时 Test 可点击；
- Group 地址去重后每个只发送一次 Off；
- 所有 Group Off 均发生在第一个设备 On 之前；
- Device 顺序、Pause、Resume、Stop 保持现状。

---

## 7. 修复五：Neighbor Set 成功条件

Neighbor Set 的目标固定包含 Enabled = true。成功条件统一为同时满足：

- Enabled 为 true；
- Relay Number 与目标一致；
- Neighbor Addresses 排序后与目标一致。

当前普通同步模型和 Emergency 同步模型各有一份相同判断，两个位置一起修改并增加回归检查，避免不同 Target 的成功语义漂移。

重点用例：Relay 和 Neighbor 已匹配但 Enabled 为 false 时，必须仍判定为未成功。

---

## 8. 修复六：32 个 Path/Zone 的本地化提示

以下三个入口统一读取已有本地化 key 的 value：

- Sequence 达到 32 条；
- Group Trigger Zone 达到 32 个；
- Space Trigger Zone 达到 32 个。

本次只修复本地化调用，不修改现有英文/中文 value，不新增 Target 资源。检查 English 与简体中文文件语法，并增加三个入口的源码契约测试。

---

## 9. 实施顺序

1. 先补容量、Restore、跨 Group Test、同步状态和成功条件的 RED 测试；
2. 实现 App 统一容量校验和中英文错误提示；
3. 实现 SDK 消息预校验及通用 Access PDU 上限保护；
4. 实现 Space 级 Restore 地址迁移并移除 Node 内旧的局部 Path/Zone 迁移；
5. 实现 Space `Devices not synced` 与 Re-sync；
6. 扩展共享 Test View 支持多个 Group；
7. 补齐两处 Neighbor Set 成功条件和三个上限提示本地化；
8. 运行聚焦测试、SDK 测试、资源语法检查和 diff 检查；
9. 对所有引用 NordicSigMeshSDK 及共享业务代码的品牌 scheme 做 generic iPhoneOS 构建，不使用 Simulator；
10. 按真实设备矩阵完成 Mesh、Restore、跨 Group Test 与失败恢复验收。

---

## 10. 预计影响文件

App 侧主要涉及：

- `ProximityLightingTopologyPolicy.swift`
- `GroupProximityLightingData.swift` 或新增的 Space 级迁移文件
- `GroupPathSequencePageController.swift`
- `SpacePathTriggerZoneController.swift`
- `GroupPathSequencePathTestView.swift`
- `MeshNetwork+SunSmart.swift`
- `DeviceRestoreViewController.swift`
- `SyncDevicesCellModel.swift`
- `EmerFireAlarmSyncCellModel.swift`
- English、简体中文本地化文件
- Group/Space 聚焦测试与检查脚本

SDK 侧主要涉及：

- `SunricherVendorSet.swift`
- Access PDU/Access Layer 的发送前长度校验
- `ProximityLightingVendorMessageTests.swift`
- 新增的 Access Payload 边界测试

不修改云端 Schema、Space Trigger Zone JSON 格式、现有 Path/Zone 数量上限、Profile 规则或设备协议字段。

---

## 11. 验收边界

自动化与构建通过可证明：

- 超限不崩溃、不截断、不落盘、不进入同步；
- 三类拓扑继续统一合并；
- Restore 三类地址引用一致迁移；
- Space 未同步提示和 Re-sync 路由存在；
- 跨 Group Test 的命令顺序正确；
- Neighbor Set 成功条件完整；
- 中英文资源和所有相关 target 可编译。

仍必须用真实设备证明：

- 固件实际最大邻居资源；
- 184 邻居、32 段报文在真实 BLE/Mesh 环境是否可靠；
- 固件返回 `ret = 2` 时 App 的失败展示；
- Restore 后设备与服务器的完整 Round Trip；
- 多 Group Off 后逐设备点亮的现场效果；
- 手动断连、Proxy 切换和部分成功后的 Re-sync。

---

## 12. 待确认决策

建议确认以下口径后实施：

> 暂不把 255 作为当前可发送上限；本轮使用 184 作为 32-bit TransMIC 下的 App/SDK 硬上限，并等待固件给出更小的实际资源上限。如果业务必须支持 255，则先暂停容量部分的 App 实施，转为设计带分片/提交语义的新 Vendor 协议及固件支持。

其余五项可按本方案直接实施。
