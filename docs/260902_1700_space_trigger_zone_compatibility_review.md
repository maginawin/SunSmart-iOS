# Space Trigger Zone 与 Group Path/Trigger Zone 完整兼容性 Review

## 1. Review 目标与范围

本报告评审当前 App 中以下三类 Proximity Lighting 拓扑配置：

1. `Proximity Profile Group > Path > Sequence`
2. `Proximity Profile Group > Path > Trigger Zone`
3. `Space > More > Trigger Zone`

重点回答：

- `Space > More > Trigger Zone` 当前是否能正常使用；
- 三者是否会互相覆盖，能否共存；
- `Space Trigger Zone` 是否已经可以完整替代 `Group Trigger Zone`；
- 当前还缺少哪些发布前修复与真实环境验收。

本轮以 2026-09-02 当前工作树 `trigger-zone-july` 的 `HEAD 62a11059` 为基线。App 实际解析的 Swift Package 为：

- `NordicSigMeshSDK`
- `release` 分支
- revision `86f5ec9e40148b9cd93e0512702337fcec41dd40`

本轮仅新增本 review 文档，没有修改业务代码、SDK、资源、Target 或依赖。

---

## 2. 总结论

### 2.1 是否能正常使用

结论不是简单的“能”或“不能”：

> 当前 Space Trigger Zone 的入口、编辑、保存、本地持久化、云端序列化、设备差异计算和 Group/Space 拓扑合并链路已经贯通；原先“保存空 Space Zone 会禁用 Group Proximity Lighting”“Group 与 Space 最后保存者覆盖前者”的核心错误已经在当前 HEAD 修复。

但是，当前仍不适合直接宣布“功能完整可用、可以正式放量”：

- 大 Zone 或三类关系合并后没有统一邻居数量/报文容量保护，合法 UI 操作可能产生超过协议 U8 或固件资源上限的邻居表；极端情况下会在 SDK 执行 `UInt8(neighborAddresses.count)` 时触发运行时失败。
- Device Restore/重新入网导致设备地址变化时，当前只迁移 Group Sequence 和 Group Trigger Zone 地址，没有迁移 `space.triggerZones`，Space Zone 会遗留旧地址。
- Space 页面没有 Group Path 页面等价的 `Devices not synced` 状态提示；失败后虽可重新进入页面再次 Save 触发重算，但用户不容易发现仍有设备未同步。
- 跨 Group Space Zone 的 Test 按钮被禁用，当前 UI Test 本身也只验证主动灯控地址/顺序，不等价于真实 PIR 邻近传播验收。
- 尚无本轮真实设备、真实固件容量、真实服务器双端 Round Trip 和实际布局验收结果。

因此建议发布状态定义为：

| 阶段 | 建议 |
| --- | --- |
| 开发自测/受控联调 | 可以进入 |
| 小规模现场试测 | 可以，但应限制 Zone 规模，并避免用 Restore 场景作为通过依据 |
| 正式发布/宣称完整可用 | 暂不建议 |
| 删除或隐藏 Group Trigger Zone | 不建议 |

### 2.2 三者是否可以和平共处

在当前 App 的核心拓扑计算中，可以。

当前已建立统一拓扑：

```text
Final neighbors per device
  = Group Sequence edges
  ∪ Group Trigger Zone edges
  ∪ Space Trigger Zone edges
```

最终地址会去重、排序，再与设备缓存比较。Group 页面保存时会带上当前 Space Zone；Space 页面保存时会带上所有 Group Path/Zone。因此当前版本内交替保存不再按“最后保存者”互相覆盖。

但“源码已经合并”不等于“跨版本、设备、服务器完整兼容”已经证明。旧 App、设备 Restore、超大邻居表、固件容量及服务器 Round Trip 仍是兼容性边界。

### 2.3 Space Trigger Zone 是否完整覆盖 Group Trigger Zone

结论：

> 在单个 Zone 的设备侧拓扑语义上，Space Trigger Zone 可以表达 Group Trigger Zone；在当前完整产品生命周期和容量模型上，不能称为完整替代。

如果同一 Group 的 A、B、C 同时加入某个 Group Trigger Zone 或某个 Space Trigger Zone，两者都会生成：

- A 的邻居：B、C
- B 的邻居：A、C
- C 的邻居：A、B

所以“设备最终行为表达能力”相同。

但是两者仍有以下不可忽略的差异：

| 维度 | Group Trigger Zone | Space Trigger Zone |
| --- | --- | --- |
| 数据归属 | `group.info.proximityLightingPath.zones` | `space.triggerZones` |
| 管理入口 | 单个 Proximity Group 的 Path 页面 | Space 的 More 页面 |
| 设备范围 | 当前 Group | Space 内所有合格 Proximity Group，可跨 Group |
| Zone 上限 | 每个 Group 最多 32 个 | 整个 Space 最多 32 个 |
| Test | 当前 Group Zone 可用 | 仅同 Group Space Zone 可用，跨 Group 禁用 |
| Restore 地址迁移 | 当前代码会迁移 | 当前代码未迁移 |
| 旧数据/旧 App | 已有稳定字段与流程 | 需要新字段、版本兼容和迁移策略 |

尤其是数量语义不同：多个 Group 各自可以拥有 32 个 Group Zone，但整个 Space 只有 32 个 Space Zone。因此在多 Group Space 中，Space Trigger Zone 并不具备 Group Trigger Zone 的等量配置容量。

---

## 3. 三类功能的正确理解

### 3.1 Sequence 是“链”

Sequence 保存有顺序的 Point。App 只把每个设备前后相邻的有效 Point 编译成直接邻居。

```text
A - B - C - D
```

得到：

| Device | Direct neighbors |
| --- | --- |
| A | B |
| B | A, C |
| C | B, D |
| D | C |

空 Point 会中断关系：

```text
A - empty - B
```

A 与 B 不会成为直接邻居。

当前模型上限：

- 每个 Group 最多 32 条 Sequence；
- 每条 Sequence 最多 200 个 Point。

### 3.2 Group Trigger Zone 是“Group 内的团”

同一个 Group Zone 内的所有有效设备彼此互为邻居，是一个全连接子图。

Group Zone 不保存顺序，只保存设备地址数组；每个 Group 最多 32 个 Zone，但当前没有单 Zone 设备数上限。

### 3.3 Space Trigger Zone 是“可跨 Group 的团”

Space Zone 的每个成员保存：

- `groupAddress`
- `deviceAddress`

只有以下 Group 的成员可以加入：

- `proximityLighting`
- `proximityLightingWithPhotocell`

同一个 Space Zone 内的有效设备同样彼此互为邻居。它与 Group Zone 的主要差异不是设备协议，而是作用域和数据所有者：Space Zone 可以把不同 Proximity Group 的设备连在一起。

当前 Group 成员管理页只允许选择“未归组设备”或“已属于当前 Group 的设备”，SDK 的 `node.group` / `group.nodes` 也按第一个普通 Group 订阅表达单一归属。因此正常 UI 流程下，一台设备只属于一个普通 Group。统一规划器中的“同设备多 Group Relay 冲突”检查主要是导入、旧数据或异常订阅的防御线，而不是当前正常产品流程必须支持的多 Group 成员模型。

### 3.4 设备不知道 Path 或 Zone 对象

设备侧不保存 `Sequence 1`、`Group Zone 2` 或 `Space Zone 3`。App 会先把三类逻辑结构编译成每台设备唯一的：

- Enabled
- Relay Number
- Neighbor Addresses

然后使用 Sunricher Vendor Proximity Lighting 命令写入设备。

主要命令：

| 子命令 | 作用 |
| --- | --- |
| `0x41/0x01` | 启用/禁用 Proximity Lighting |
| `0x41/0x02` | 写完整邻居表、Enabled、Relay、TTL、转发 AppKey Index |
| `0x41/0x03` | 仅修改 Relay |
| `0x41/0x00`、兼容 `0x04` | 运行时 Trigger/源地址反馈 |

Quick Add/Trigger Add 还会监听标准 SIG `Sensor Status 0x52` 的 Presence Detected；Identify、Path/Zone Test 则分别使用标准 Health/灯控消息。这些辅助消息不能替代真实 Proximity Lighting 邻居传播验收。

---

## 4. 当前 App 完整调用链

### 4.1 入口与权限

`SpaceMoreViewController.makeOptions()` 会在 `space.groupOperates` 包含 `.edit` 时显示 Trigger Zone；点击后再次校验权限并打开 `SpacePathTriggerZoneController`。

因此当前入口已经正式可达，不再是早期版本中的隐藏开发入口。

### 4.2 编辑与候选过滤

Space 页面会：

1. 从 `space.triggerZones` 创建工作副本；
2. 仅保留仍属于当前 Space、且 Group Profile 合格的 `(groupAddress, deviceAddress)`；
3. 提供 All eligible groups 与单 Group 过滤；
4. 提供 Quick Add、Trigger Add、Manually Add；
5. 支持在当前 Zone 内复用已在其他 Zone 使用的设备；
6. 添加成员时保存明确的 Group 地址，不再直接依赖 `node.group` 反推；
7. 检测导入、旧数据或异常订阅造成的同一设备多 Group Relay Number 冲突，并阻止有歧义的保存/添加。

### 4.3 保存与统一拓扑规划

Space Save 顺序为：

1. 停止当前编辑；
2. 再次清理无效 Zone Item；
3. 取得 old/new Space Zone 副本；
4. 用 new Zones 作为 proposed override，与所有 Group Sequence/Group Zone 一起编译统一拓扑；
5. 检查受影响设备是否有 Relay 冲突；
6. 仅对 old/new Space Zone 成员并集生成设备差异任务；
7. 逻辑有变化时先标记 Cloud Dirty，再保存 `space.triggerZones`；
8. 无设备任务时直接发送 common 变更通知；
9. 有任务时进入 `SyncDevicesViewController(.spaceTriggerZones)`。

Group Path Save 同样先以尚未持久化的 proposed Group Path 编译统一拓扑，确认无冲突后再落盘，并把预计算任务传给同步页。同步页不会脱离 Space 上下文重新计算。

### 4.4 空 Space Zone 的当前语义

当前语义已经正确：

- 空 Space Zone 贡献 0 条边；
- 新增 1～32 个空 Zone 不改变 Group Path/Group Zone 目标；
- affected device 集合为空，所以不产生 Mesh Task；
- 不会再因为 Space 邻居为空发送 `proximityLightingEnabled(false)`；
- 只保存逻辑数据并触发云同步。

只要设备仍属于合格的 Proximity Lighting Group，统一目标就是 Enabled；没有邻居表示写空邻居表，而不是关闭 Proximity Lighting。

### 4.5 本地与云端数据

两套逻辑结构独立保存：

```text
Group:
  proximityLightingPath:
    paths
    zones

Space:
  triggerZones
```

当前导出会显式写出 `triggerZones`，包括空数组；导入缺失或非法字段时归一化为空数组。Group Path/Zone 也有对应的导出、导入和空 Point 恢复逻辑。

这证明客户端序列化链路存在，但不能代替真实服务器“上传非空 → 清空 → 另一客户端下载”的 Round Trip 验收。

---

## 5. 已确认正确的兼容行为

### 5.1 三类关系合并去重

统一策略分别处理：

- Group Path 的前后节点；
- Group Zone 的同区全连接；
- Space Zone 的同区全连接。

所有关系最终放入每台设备的 Set，再排序输出。相同边由多个来源产生时只保留一次。

示例：

```text
Group Sequence: A - B - C
Group Zone: A, C
Space Zone: A, C, D
```

最终：

| Device | Neighbors |
| --- | --- |
| A | B, C, D |
| B | A, C |
| C | A, B, D |
| D | A, C |

### 5.2 删除 Space 关系会回退到 Group 关系

删除 Space Zone 或成员后，受影响节点重新按完整统一拓扑计算。只有 Space 贡献被移除，仍由 Group Sequence/Zone 提供的邻居会保留。

### 5.3 Group 与 Space 交替保存不再互相覆盖

当前 Group 和 Space 保存入口均复用统一 Planner，并使用 proposed override 参与计算。因此：

- 保存 Space Zone 不会擦除 Group Path/Zone；
- 之后保存 Group Path/Zone 也不会擦除 Space Zone；
- 逻辑数据继续按 Group/Space 各自所有权保存，设备只接收合并后的物理目标。

### 5.4 差量任务

目标与设备缓存一致时不生成任务；仅 Relay 不同时只发 Relay Set；邻居不同时发完整 Neighbor Set；设备被旧版本误禁用但邻居/Relay 已一致时只发 Enable。

---

## 6. Review Findings

### P1：邻居数量与报文/固件容量没有统一上限保护

这是当前最明确的正式发布阻塞项。

证据链：

- Space 最多允许 500 个真实 Mesh Node；
- Group Trigger Zone 和 Space Trigger Zone 都没有单 Zone 成员上限；
- 统一拓扑还会把 Sequence、Group Zone、Space Zone 的邻居求并集；
- SDK 的 Neighbor Set 直接把 `neighborAddresses.count` 转成 U8；
- 没有在 UI、Planner、任务创建或 SDK 编码前看到统一上限校验。

当一个设备的最终邻居超过 255 时，`UInt8(neighborAddresses.count)` 不可表示；即使低于 256，也可能先超过 Mesh Access Payload 或固件邻居资源，设备返回 `ret = 2`。

影响三类功能，不是 Space 独有问题；统一合并后更容易在多个看似合理的小配置叠加时超限。

建议：

1. 由固件明确单设备最大邻居数和最大可接受 Access Payload；
2. 在纯拓扑 Planner 输出阶段统一校验最终邻居数，而不是分别限制单个页面；
3. 保存前阻止落盘和设备下发，并显示中英文可理解提示；
4. SDK 编码层再增加不可绕过的防御性校验，禁止整数溢出；
5. 增加边界值 `max-1/max/max+1/255/256` 自动化与真机测试。

### P1：Device Restore 只迁移 Group 地址引用，没有迁移 Space Trigger Zone

`Node.updateResoreData(oldNode:)` 当前会把旧设备地址替换到：

- Group Sequence Path Item；
- Group Trigger Zone addresses。

但整个 Restore 文件和相关调用链没有更新 `space.triggerZones[*].items[*].deviceAddress`。

后果：

1. 设备 Restore 后获得新地址；
2. Group Sequence/Group Zone 继续指向新设备；
3. Space Zone 仍保存旧地址；
4. Planner 会忽略旧地址，或用户进入 Space 页面后清理该 Item；
5. 原跨 Group 关系丢失，且云端可能继续保存旧引用，直到用户再次保存。

这说明 Group Trigger Zone 当前仍拥有比 Space Trigger Zone 更完整的设备生命周期支持，也是“Space 已完整替代 Group”的直接反例。

建议把设备地址迁移做成 Space 级统一引用迁移，覆盖 Group Path、Group Zone、Space Zone，并在写入后统一标记 Cloud Dirty。

### P2：Space 页面缺少清晰的设备未同步状态与一键重试入口

Group Path 页面进入时会重新编译统一拓扑，并显示 `Devices not synced`；用户可直接重新同步。

Space Trigger Zone 页面没有等价提示。设备同步失败后：

- 逻辑 Zone 已经本地保存并可能上传云端；
- 用户可以重新进入页面再按 Save，因为 old/new Zone 成员仍会被纳入 affected addresses；
- 但页面没有明确告诉用户哪些设备仍失败，也没有专门的 re-sync 操作。

这不是数据覆盖错误，但会降低弱网、Proxy 切换、15 秒超时场景下的可恢复性。普通 Proximity Lighting Task 当前也没有自动重试。

### P2：跨 Group Space Zone 没有可用的页面 Test

Space Zone Header 只有在全部 Item 的 `groupAddress` 相同时才启用 Test；真正体现 Space 价值的跨 Group Zone 不能使用该 Test。

此外，现有 Path/Zone Test 只是 App 主动关闭 Group、再逐灯点亮，用于检查地址/位置。它本身不能证明 Neighbor Set 已写入，也不能证明真实 PIR 触发按 Relay 传播。

因此跨 Group Space Zone 必须单独设计真实运行测试，不应以当前 Test 按钮或编译成功作为验收结果。

### P2：Neighbor Set 的业务成功检查没有显式校验 Enabled

Neighbor Set 发送时固定携带 `enabled = true`，SDK 在成功回包后会同时更新 Enabled、Relay 和 Neighbor 缓存；这一正常路径成立。

但 `DeviceOperationType.isSuccessful` 对 `.proximityLightingNeighbor` 当前只比较 Relay 和 Neighbor，没有显式比较 `node.proximityLightingEnabled == true`。如果后续 SDK 回包缓存更新被拆分、异常或出现时序问题，同步页可能把 Enabled 未恢复的状态判为成功。

建议把 Neighbor Set 的成功条件写完整，保持与统一目标状态一致。

### P3：到达 32 个 Path/Zone 后的提示没有本地化取值

相关页面调用：

```text
showTipHUD("not_zones_remaining", ...)
showTipHUD("not_paths_remaining", ...)
```

本地化文件虽然存在对应 key，但调用没有 `.localizedString`。用户达到上限后可能直接看到 key。该问题同时存在于 Sequence、Group Trigger Zone 和 Space Trigger Zone。

---

## 7. 对“Space Trigger Zone 完全替代 Group Trigger Zone”的判断

### 7.1 这句话在哪个层面成立

仅在以下限定条件下成立：

- 只比较一个 Zone 产生的设备邻接关系；
- Space Zone 中选择的成员与 Group Zone 完全相同；
- 不考虑每 Group/每 Space 的 Zone 数量差异；
- 不考虑旧数据迁移、旧 App、Restore、页面 Test、失败恢复和云端所有权。

在这个狭义层面，二者都是 Clique，设备收到的最终 Neighbor Addresses 可以相同。

### 7.2 为什么当前不能按产品功能直接删除 Group Trigger Zone

1. **容量不等价**：Group 是每组 32，Space 是全局 32。
2. **配置所有权不等价**：Group Zone 跟随 Group；Space Zone 跟随 Space。
3. **生命周期不等价**：Restore 当前只迁移 Group 数据。
4. **测试能力不等价**：跨 Group Space Zone 的 Test 不可用。
5. **版本兼容未证明**：旧 App 不认识或不合并 `space.triggerZones`，旧版 Group Save 仍可能把设备物理邻居表写回 Group-only 结果。
6. **没有迁移机制**：现有 `proximityLightingPath.zones` 不会自动搬到 `space.triggerZones`。
7. **没有产品互斥或废弃提示**：当前两个入口同时存在，设计语义就是并存，而不是明确替换。

### 7.3 推荐产品定位

当前最稳妥的定位是：

> Group Sequence 和 Group Trigger Zone 管理 Group 内拓扑；Space Trigger Zone 作为跨 Group 拓扑扩展。三者由统一 Planner 合并到设备唯一邻居表。

不建议把 Group Trigger Zone 描述成“临时方案”并立即删除。

如果产品最终仍决定由 Space Trigger Zone 取代 Group Trigger Zone，至少应先完成：

1. Group Zone → Space Zone 的显式、幂等迁移；
2. 重新设计全 Space 32 个 Zone 的容量，保证不低于原每 Group 32 的有效能力；
3. 修复 Restore、成员移除、Group 删除/Profile 切换等引用生命周期；
4. 为旧客户端设置最低版本门槛或服务器写入保护；
5. 确认空数组/非空数组服务器 Round Trip；
6. 建立邻居容量上限和固件错误提示；
7. 提供跨 Group 的可验证测试流程；
8. 迁移完成后再隐藏 Group Trigger Zone，并避免两套数据长期双写。

---

## 8. 当前验证结果

### 8.1 本轮已通过

- `PathTopologyPersistenceContractTests`：PASS
- `ProximityLightingTopologyPolicyTests`：PASS
- `GroupPathSequenceDeviceAddViewContractTests`：PASS
- `git diff --check`：PASS
- Xcode project 与中英文 Localizable plist 语法检查：PASS
- `Package.resolved` JSON 检查：PASS
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`：`BUILD SUCCEEDED`
- Workspace 当前解析 SDK：`release @ 86f5ec9`
- 本地 SDK 路径存在，HEAD 与 App resolved revision 一致，且工作区干净。

### 8.2 自动化验证能证明什么

自动化已证明：

- 三类输入在纯策略层合并、去重；
- 空 Space Zone 不改变 Group 拓扑；
- 删除 Space 关系后回退到 Group 拓扑；
- Relay 冲突不静默选择值；
- 保存入口使用 proposed override；
- Group/Space 同步 UI 消费预计算任务；
- 当前工程可以编译。

### 8.3 自动化验证不能证明什么

当前仍未证明：

- iPhone/iPad 实际页面约束、触控、长英文/中文、展开收起和滚动；
- Quick Add/Trigger Add 在真实 Sensor/Vendor Trigger 下的稳定性；
- Neighbor Set 的真实 ACK、设备持久化和重启后状态；
- PIR 从 Group 内传播到跨 Group Space Neighbor 的真实行为；
- Relay 深度与 TTL 的现场语义；
- 固件最大邻居数量和 `ret = 2` 边界；
- 同步中断、Proxy 切换、部分成功后的恢复；
- 真实服务器双手机 Round Trip；
- 旧版本 App 与新 `triggerZones` 字段的兼容。

---

## 9. 建议的提测矩阵

### 9.1 Group 基线

1. Sequence `A-B-C-D`，核对每台设备最终邻居。
2. Sequence `A-empty-B`，确认不跨空 Point 建边。
3. Group Zone `A/B/C`，确认三台互为邻居。
4. Sequence `A-B-C` + Group Zone `A/C`，确认合并去重。

### 9.2 Space 共存

1. 保留上述 Group 配置，新增 1～32 个空 Space Zone：0 个 Mesh Task，不出现 Disable。
2. Space Zone 加入同 Group 的 A/C：最终为 Group + Space 并集。
3. Space Zone 加入不同 Group 的 A/D：双方保留 Group 邻居并增加跨 Group 邻居。
4. 删除 Space 成员/Zone：仅移除 Space 贡献，不影响 Group 贡献。
5. 再保存 Group Sequence/Zone：Space 贡献仍存在。
6. 再保存 Space Zone：Group 贡献仍存在。

### 9.3 生命周期与失败恢复

1. Restore 一个 Space Zone 成员并获得新地址，验证 Group/Space 引用都迁移；当前预期会暴露缺口。
2. 从 Proximity Group 移除成员，确认 Group Path、Group Zone、Space Zone 都不再保留无效引用。
3. 删除 Group 或改为非 Proximity Profile，确认相关 Space Item 被清理并上传云端。
4. Neighbor Set 超时、`ret = 2`、部分节点成功后退出 App，再次进入检查同步提示和重试。
5. 设备断电重启后检查邻居表和 Enabled 是否持久化。

### 9.4 容量与服务器

1. 用固件明确的最大邻居数做 `max-1/max/max+1`。
2. 覆盖多个小 Zone/Path 合并后最终邻居超限，而单个页面看起来均未超限的场景。
3. 上传非空 Group/Space Zone，另一台手机下载核对。
4. 清空全部 Group/Space Zone，再从另一台手机下载，确认旧值不会复活。
5. 使用一个旧版本 App 打开并保存同一 Space，确认不会删除 `triggerZones` 或覆盖设备邻居表。

---

## 10. 最终建议

1. 保留 Group Trigger Zone，当前把 Space Trigger Zone 定义为跨 Group 扩展。
2. 在正式发布 Space Trigger Zone 前，优先修复 P1 的容量保护与 Restore 地址迁移。
3. 同步补齐 Space 页面未同步提示/重试入口，以及 Neighbor Set 的完整成功校验。
4. 将跨 Group 真机传播、固件容量、真实服务器 Round Trip 和实际 UI 布局列为发布门禁。
5. 在这些工作完成前，对外不要使用“Space Trigger Zone 已完整替代 Group Trigger Zone”这一表述。

一句话总结：

> 当前版本已经从“互相覆盖”修复为“统一合并”，方向正确、核心源码链路可用；但容量和 Restore 生命周期仍有实质缺口，Space Trigger Zone 目前应作为 Group Trigger Zone 的补充，而不是替代。
