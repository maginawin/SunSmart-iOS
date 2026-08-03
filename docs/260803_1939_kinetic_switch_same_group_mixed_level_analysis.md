# 机械能开关长按时亮度与色温联动：Log 与源码分析

## 1. 结论

本次异常的直接原因已经可以从 Log 确认：**用于长按调亮度的按键与用于长按调色温的按键，最终都把代理节点的 Generic Level Client 发布地址配置成了同一个虚拟组 `0xCCA0`。**

在当前 EnOcean / Kinetic Switch 协议实现中，Dim Up / Down 与 CCT Up / Down 的按键 Vendor payload 并没有独立的“亮度/色温类型”字段；两者都通过 Generic Level Move 实现。真正区分控制对象的是：

- 亮度按键发布到主虚拟组；
- 色温按键发布到另一个 CCT 虚拟组；
- 灯具的亮度 Generic Level Server 与 Temperature Generic Level Server 分别订阅这两个不同地址。

本次四个长按动作全部落到 `0xCCA0`。如果 Tunable White 灯具的亮度 Level Model 和色温 Level Model 都订阅了 `0xCCA0`，一次 Level Move 会被两个 Model 同时处理，因此表现为亮度和色温一起变化。

这不是手机 BLE 发送质量造成的随机串包。Log 中的 Access PDU、代理 Model Publication 和 Vendor Key Set 都是确定性的，而且均得到 ACK / Success。手机之间行为不同，更符合**各手机本地 Switch 数据、虚拟组数据、设备 Composition/Subscription 缓存或 App/SDK 版本不一致**。

## 2. 本次配置发送了什么命令

### 2.1 目标与基础信息

- App 本地 Primary Element：`0x0001`
- 代理节点：十进制 `4358`，即 `0x1106`
- 代理节点 PID：`0x2013`
- 机械能开关 MAC：`E2158BE6CD58`
- 按键数量：4
- Vendor Set opcode：`0xF0780A`
- Vendor Status opcode：`0xF3780A`
- 使用 AppKey：Index `1`

Log 中包含完整 EnOcean Security Key。该字段属于设备认证信息，对外转发 Log 时应脱敏。

### 2.2 添加机械能开关到代理节点

发送：

- `enOceanAdd(keyCount: 4, securityKey: ..., macAddress: E2158BE6CD58)`
- Access parameters：`36 01 04 [16-byte security key] 58 CD E6 8B 15 E2`

其中 MAC 在 payload 中按低字节顺序写入。代理返回：

- `0x36 01 00`
- `ResponseCode.enOceanAdd`
- `isSuccessful: true`

这只能证明代理接受了面板绑定，不证明后续按键地址语义正确。

### 2.3 配置代理节点的 Client Model Publication

每个按键写入前，SDK 先设置代理节点对应 Client Model 的 Publication，再发送 `enOceanSwitchKeySet`，让代理保存该按键配置。

本次反复设置了：

| Model | Model ID | Publication | 用途 |
| --- | ---: | --- | --- |
| Scene Client | `0x1205` | `0xFFFF` | 短按 Scene Recall |
| Generic Level Client | `0x1003` | `0xCCA0` | 长按 Level Move |

所有 `ConfigModelPublicationSet` 都返回 `ConfigModelPublicationStatus(... status: Success)`。

关键异常是：Key 4、3 的 Dim 与 Key 2、1 的 CCT 在写入前，Generic Level Client Publication 全部被设置成 `0xCCA0`，没有出现第二个 CCT 虚拟地址，例如 `0xCCA1`。

### 2.4 四个按键配置

本次是 Scene 4-key 面板，发送顺序如下：

| Key | 短按 | 长按语义 | Log 中目标 | Vendor parameters |
| ---: | --- | --- | --- | --- |
| 4 | Scene 1 | Dim Up | `0xCCA0` | `36 03 58CDE68B15E2 03 01 0100 0900` |
| 3 | Scene 5 | Dim Down | `0xCCA0` | `36 03 58CDE68B15E2 02 00 0500 0900` |
| 2 | Scene 未配置 | CCT Up | `0xCCA0` | `36 03 58CDE68B15E2 01 01 0000 0900` |
| 1 | Scene 未配置 | CCT Down | `0xCCA0` | `36 03 58CDE68B15E2 00 00 0000 0900` |

按键 payload 的字段结构为：

`36 03 | reversed MAC | keyIndex | direction | sceneNumber LE | actionType LE`

- `keyIndex` 为 `key - 1`；
- `direction`：Up 为 `1`，Down 为 `0`；
- `actionType = 0x0009`：bit 3 为 Scene Recall，bit 0 为长按动作；
- SDK 对 Dim 和 CCT 都只设置 bit 0，没有额外的 Dim/CCT 区分位；
- 目标组地址也不在该 Vendor payload 中，而是由前一条 Generic Level Client Publication 决定。

四条 `enOceanSwitchKeySet` 均返回 `0x36 03 00`、`isSuccessful: true`。因此代理确实接受了这组配置，但接受的是“所有长按都向 `0xCCA0` 发 Level 消息”的配置。

### 2.5 其他命令

- Proxy Filter：添加 `0xCCA0`，Filter Status 为 Accept List、listSize 5；同样没有看到第二个 CCT 地址。
- 完成后发送 `identify(breathe(count: 1, period: 1500))`，返回成功；与亮度/色温联动无关。
- Cloud `/sitespace/sync/spaceprops` 返回 HTTP 200 / businessCode 200，只代表本地 Space 数据上传成功，不代表真实 Mesh Subscription 或机械能开关行为正确。

## 3. 正常 Log 对比

既有正常配置 Log：

`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/fix/create switch log 260727.txt`

该 Log 的地址明确分流：

- Dim Up / Down：Generic Level Client 发布到 `0xC003`；
- CCT Up / Down：Generic Level Client 发布到 `0xC004`；
- 亮度 Generic Level Server 订阅 `0xC003`；
- Temperature 元素上的 Generic Level Server 订阅 `0xC004`。

因此当前异常 Log 与正常 Log 的决定性差异不是手机型号、SAR 分包数量或 Scene 号码，而是：

| 链路 | 正常 | 本次异常 |
| --- | --- | --- |
| 亮度长按目标 | 主组 `0xC003` | `0xCCA0` |
| 色温长按目标 | CCT 组 `0xC004` | `0xCCA0` |
| 主组与 CCT 组 | 不同 | 有效目标相同 |

## 4. 源码中的形成路径

### 4.1 `subLinkGroupAddress` 缺失时会回退到主地址

`DeviceSwitchData.switchKeys` 对两个 4-key Panel 都采用相同策略：

- Dim 使用 `linkGroupAddress`；
- CCT 使用 `subLinkGroupAddress ?? linkGroupAddress`。

因此，只要该手机本地 Switch 记录的 `subLinkGroupAddress` 是 nil，Key 2 / 1 就会自然回退到主地址。若该字段异常地等于主地址，也会得到完全相同的结果。

本次 Log 只能确认“有效地址相同”，不能仅凭现有输出区分：

1. `subLinkGroupAddress == nil` 后发生 fallback；
2. `subLinkGroupAddress == linkGroupAddress == 0xCCA0`。

其中第一种更符合当前持久化与创建逻辑。

### 4.2 保存页面只检查主组，不检查 CCT 子组

`DeviceSwitchViewController.saveBtnAction` 只有在 `setSwitchData.linkGroup == nil` 时才创建两个虚拟组。

如果已有主组但 CCT 子组缺失、引用丢失或地址相同，该条件不会进入，不会自修复 CCT 子组。随后 `switchKeys` 继续把 CCT 回退到主组。

此外，主组创建使用 guard；第二个 `subLinkGroup` 却使用 `try?`。第二个地址创建失败时，错误被吞掉，代码仍会保存主组地址以及 nil 的 `subLinkGroupAddress`，为后续 fallback 留下状态。

### 4.3 数据库升级与导入允许子组为空

`switchs.subLinkGroupAddress` 是 nullable 字段：

- 老数据库升级时只新增 nullable column，没有为既有 Switch 创建或回填 CCT 组；
- load 时会原样恢复 nil；
- save 时也允许继续保存 nil；
- Cloud/文件导入只有 payload 中存在 `subLinkGroupAddress` 才赋值，缺失时仍为 nil。

这使不同手机即使登录同一个项目，也可能因为安装历史、旧数据库、导入来源或最后一次同步版本不同而持有不同的 Switch 地址状态。

### 4.4 灯具订阅为何会导致两个状态一起变化

SDK 的接收端订阅逻辑是：

- Dim：让灯具亮度 `levelModel` 订阅按键的目标地址；
- CCT：让灯具 `ctlTemperatureLevelModel` 订阅按键的目标地址。

当两个目标都为 `0xCCA0` 时，Tunable White 灯具的两个不同 Generic Level Server 会订阅同一个组。机械能开关长按发出的 Generic Level Move 被两个 Model 同时接收，最终就是亮度与色温联动。

当前 Log 没有出现新的 `ConfigModelSubscriptionAdd`，并不能证明灯具没有错误订阅。更可能的解释是：

- 本地 Model 缓存已经认为相关订阅存在，因此同步规划没有再生成 Add；或
- 该 Switch 是替换面板/重新配置代理，接收灯具的旧订阅仍保留；或
- 本次配置范围只需要更新代理，绑定 Group 没有产生新的接收端任务。

真实设备上的 Subscription List 才是最终真值。

## 5. 手机差异的可能原因排序

### 5.1 极高概率：该手机本地 Switch 的主/CCT 地址状态异常

直接证据：本次 Log 中所有长按有效目标都是 `0xCCA0`，而正常 Log 使用两个地址。

可能来源：

1. 该 Switch 创建于只保存一个组或未回填子组的旧数据阶段；
2. 从 Cloud/文件导入的 Switch 对象缺少 `subLinkGroupAddress`；
3. 创建第二个虚拟组时失败，`try?` 吞掉错误后仍保存了主组；
4. 本地虚拟组被删除、覆盖或 Space 数据合并不完整；
5. 两个地址字段被异常合并为同一个值。

### 5.2 高概率共因：真实灯具仍保留历史错误 Subscription

即使随后只修正代理节点的 CCT Publication，如果灯具的 Temperature Level Model 仍订阅旧主组，Dim 仍可能同时改变色温。

仅“替换机械能开关面板”不会清理接收灯具 Subscription，因为它保留原 Switch 的通讯组与绑定关系。恢复验证应优先删除整个 Switch 数据并完成 Unsubscription，再新建 Switch，而不是只换面板或只点 Re-Sync。

### 5.3 中等概率：两台手机安装的 App/SDK 版本不同

如果异常手机使用旧 App、旧 SDK 或保留旧数据库，可能生成不同的子组与订阅状态。当前源码引用本地 NordicSigMeshSDK，且已包含 `e521355 fix: k4 switch control cct bug`；现有 `CctLevelModelResolverTests` 在本机通过。

不过，旧 SDK 的问题主要是“无 Temperature Model 时错误回退到任意 Level Model”，而本次 Log 已经直接暴露“Dim/CCT Publication 地址相同”。因此 SDK 版本差异可能是历史状态的来源或附加问题，不是对当前 Log 的首要解释。

### 5.4 中低概率：手机本地 Composition / Model Subscription 缓存不同

设备是否需要生成 CCT Subscription，取决于本地 Node Composition 与各 Model 的 `subscribe` 缓存。不同手机若没有同样的最新 Composition/Subscription 状态，Sync 任务可能不同。

这可以解释为什么某台手机会多配、少配或不显示接收端任务，但不能单独解释为什么代理的四个长按 Publication 都是 `0xCCA0`。

### 5.5 低概率：代理固件残留或手机 BLE/SAR 差异

- 当前四个 Key Set 都重新发送并返回成功，不只是使用代理中的旧缓存；
- Mesh 加密与 MIC 校验下，随机传输出错通常会被丢弃或超时，不会稳定地把四个业务地址都变成同一个合法地址；
- SAR 中出现重复 ACK / “Message already acknowledged” 是可靠传输重发行为，不会改变已经解密的 Access PDU 业务字段。

所以这两项不应作为首轮排查方向。

## 6. 与本问题无直接因果关系的 Log

- `Local Vendor Model ... not bound to key`：值得单独整理本地 Model binding 日志，但 Vendor Status 已成功解密并匹配请求，不能解释同地址 Publication。
- Cloud 上传 `status=200`：不代表 Mesh 端配置正确。
- `declaredContentEncodingGzip=true`、`actualBodyGzip=false`：属于 HTTP 请求一致性问题，服务端本次仍成功处理，与机械能开关实时控制无关。
- Identify breathe：仅用于设备识别。

## 7. 建议的验证顺序

### 7.1 先比较两台手机的 Switch 数据

在发送任何 Mesh 配置前输出并比较：

- App 版本、Build、NordicSigMeshSDK commit/version；
- Switch id、panelType；
- `linkGroupAddress`、`subLinkGroupAddress`；
- 两个地址对应的 Group 是否真实存在；
- 两个地址是否相等；
- 四个 `switchKeys` 的 longPress destination。

异常手机的预期命中结果：主地址为 `0xCCA0`，子地址为 nil 或同为 `0xCCA0`。

### 7.2 读取真实灯具的 Subscription List

对每个绑定的 Tunable White Node，分别读取：

- 亮度元素 Generic Level Server 的 Subscription；
- Temperature 元素 Generic Level Server 的 Subscription。

异常状态预期：两个 Model 都包含 `0xCCA0`。

不要只看手机数据库中的 `model.subscribe`；应以真实设备 Config Model Subscription Get/List 结果为准。

### 7.3 做一次干净 A/B 验证

1. 在异常 Switch 仍保持当前错误地址状态时删除整个 Switch；
2. 确认代理解绑、灯具 Unsubscription 都成功，不只看页面“完成”；
3. 新建 Switch，不复用旧 Switch 记录；
4. 新 Log 必须显示两个不同的虚拟地址，例如主组 `0xCCA0`、CCT 组 `0xCCA1`；
5. 确认亮度 Level 只订阅主组、Temperature Level 只订阅 CCT 组；
6. 再分别测试 Dim Up/Down 与 CCT Up/Down。

若删除时没有真实完成 Unsubscription，应先清理残留 Subscription 或重新配置目标灯具，否则仅创建新地址仍可能受到旧订阅影响。

## 8. 后续修复方向（本轮未改代码）

1. 对 4-key CCT Panel 建立强约束：主组与 CCT 子组必须都存在且地址不同；不满足时禁止生成 Key Set。
2. 不再允许 CCT 动作以 `subLinkGroupAddress ?? linkGroupAddress` 静默降级；应显示 Needs Attention 并提供修复入口。
3. 创建两个虚拟组时采用原子结果：第二个创建失败则不保存半成品，或回滚第一个组。
4. 保存/同步前检查“主组存在但子组缺失/相同”的历史数据，并设计显式对账流程。
5. 历史修复不仅要创建新 CCT 组，还要从旧主组移除 Temperature Level Subscription，再添加到新 CCT 组。
6. 增加聚焦日志：Switch 地址对、四键 destination、每个绑定 Node 的亮度/CCT Model element 与 Subscription。

## 9. 验证边界

本分析完成了：

- 当前 Log 的 Access PDU 与业务命令解码；
- App 与本地 SDK 源码链路核对；
- 与既有正常 Kinetic Switch Log 的差异比较；
- 当前 SDK CCT Level Model resolver 的 standalone 测试验证。

本轮未连接真实设备，没有读取设备端 Subscription List，也没有比较两台手机的数据库/导出数据。因此：

- “四个长按有效地址相同”是已确认事实；
- “异常手机的 `subLinkGroupAddress` 为 nil”是最高概率假设，需新增一条状态日志或导出数据确认；
- “灯具两个 Level Model 都实际订阅 `0xCCA0`”与现象高度一致，但仍需设备端 Subscription Get 形成最终闭环。
