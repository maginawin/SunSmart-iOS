# Sync Space 定时 JSON 契约与服务器／网关对接示例

> 2026-11-06 更新：第 1～11 节及 `space_timed_v2_demo.json` 保留为 v2 历史契约。用户已确认第 12 节的 v3 结构及回写规则，App 实现与验证记录见第 13 节。新增 `space_timed_v3_demo.json` 为不含密钥的结构示例；服务器、网关配套和真实 Mesh 验收仍待对应执行方完成。

结论：服务器经网关配置定时后，需要同时维护 **Space 的业务定时、节点槽位绑定、各 Scheduler Model 的设备观察结果及兼容投影**。只写 `space.schedules` 可以表达目标，不能证明设备已配置；只写 `node.schedules` 不能让 App 可靠恢复各 Model 的同步状态。

本文基于 2026-11-05 当前工作区源码。**Profile 定时在当前 App 中只读；网关执行、服务器存储／回读以及真实触发尚未联调。** 本次仅新增文档、JSON 和离线校验脚本，没有修改业务代码、服务器或固件。

## 1. 版本、文件与使用范围

- App 工作树：`feat-device-scene-261028`，分支 `feat/device-scene-261028`。开始分析时为 `2354ac91db5f02820249b860dcbf08964477fe6a` 加已有暂存改动；结束核对时这些改动已进入 `b6f56743b9ebd09f46544ed6ebed3cde1eee6611`，包含 `nodeSlots.generation` 移除。本任务没有执行 commit，相关生产源码无新的未提交差异。
- 实际 SDK：`.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。首次分析为 `c8ef744d9591b57511f96db7362c931978a707a5`；本次补充核对为 `3dbd5566a300422aab47e2dd20c77164f887b22b`。两 revision 之间仅涉及其他任务的 DeviceLeave／TimeZoneSet 文件，本节依赖的 Scheduler 编解码／投影／存储源码未变化。补充期间 SDK 另有离线生命周期任务的工作区差异，本任务没有修改或提交 SDK；正式远端 `release` 是否包含此 revision 未验证。
- 历史改动说明见 [generation 移除记录](261105_1143_timed_node_slots_generation_analysis.md)。本文的字段和行为均重新核对当前代码，不以旧文档中的 SDK HEAD 代替当前状态。

| 文件 | 内容／读法 |
| --- | --- |
| [space_timed_v2_demo.json](261105_1429_space_timed_json_demo/space_timed_v2_demo.json) | 一个 Space 的**相关字段节选**：13 条业务定时、4 个节点、Group／Scene 引用和 Model 快照；根结构对应一个 Space 对象 |
| [timed_state_cases.json](261105_1429_space_timed_json_demo/timed_state_cases.json) | 36 个相互独立的状态／兼容／非法输入案例；每个 `spaceFragment` 单独阅读，不能把它们拼成一个 Space |
| [scheduler_wire_examples.json](261105_1429_space_timed_json_demo/scheduler_wire_examples.json) | 16 个设备寄存器样例，含解码字段、10 字节十六进制和 Base64；包含 App 不支持编辑的原始观察值 |
| [scheduler_snapshot_demo.py](261105_1429_space_timed_json_demo/scheduler_snapshot_demo.py) | 服务器可直接运行的纯 Python 示例：业务参数、位编码、两类 Base64、完整调用及断言；无 SDK 依赖 |
| [scheduler_snapshot_generated.json](261105_1429_space_timed_json_demo/scheduler_snapshot_generated.json) | 上述 Python 程序的实际输出，包含两个 Model 的快照及配套 node.schedules |
| [verify_demos.py](261105_1429_space_timed_json_demo/verify_demos.py) | 使用当前生产策略和 SDK 编解码的只读校验器 |

示例中的 UUID、名称、地址、指纹和时间均为合成数据。**省略了 Device Key、NetKey、AppKey、完整 Composition、订阅／绑定及其他业务字段，不能直接上传、导入或覆盖真实 Space。** 指纹由校验器在内存中重建的合成设备身份产生，不能复制给真实节点。实际对接须基于服务器已有完整 Space 修改相关字段，保留其他配置和身份；新节点须来自实际配网结果。

`case`、`meaning`、`expected`、`spaceFragment`、`description`、`parametersHex`、`transitionTimeRaw` 是文档包装，不是新增的云端协议字段。

## 2. Sync Space 中的位置及数据流

当前 App 上传入口是 `/sitespace/sync/spaceprops`，参数形状为：

```json
{
  "siteId": "<existing-site-id>",
  "spaceId": "<existing-space-id>",
  "spaces": [{"uuid": "<existing-space-id>"}],
  "userId": "<current-user-id>"
}
```

上面仅说明包装层，省略了 Space 的完整内容，不能直接发出。真实 `spaces` 元素为完整对象；本次 demo 展示的正是该对象内部相关部分。读取入口为 `/sitespace/get/spaceprops`。Site 整体上传则位于 `site.spaces[]`；v2 分享文件的 `{format:"sunSmartSpace",formatVersion:2,space:...}` 是另一种包装，**不用于 Space API**。

| JSON 路径（从单个 Space 开始） | 用途／所有者 |
| --- | --- |
| `schedules[]` | 用户想要的定时定义，包括启停、时间、目标和尚未完成的移除意图 |
| `spaceData.timedSchemaVersion` | 业务定时格式版本：1 为旧的 `id=slot`；2 为业务 ID 与节点槽位分离 |
| `schedules[].nodeSlots[]` | 每个配网实例的物理 slot 预约，属于业务配置，不是成功回执 |
| `nodes[].schedules[]` | 节点已知 Scheduler 内容的旧格式兼容投影，`id` 是物理 slot |
| `nodes[].custProps.schedulerModelStates` | 按 Element／Model 保存的设备观察快照，以及原始兼容投影字节 |
| `nodes[].elements[]` | Composition，确定哪些 Element 实际具有 `1206`／`1207`、Time、Scene、Light LC Model |
| `nodes[].groupAddress/groupState`、`groups[].profile` | 决定 Group 目标、Auto On 的 Owner Model，以及退出组状态 |
| `scenes[]`、`groups[].scenesDatas[]`、`spaceData.sceneConfigurations[]` | Scene 定时所引用的场景、成员和配置，不是另一套定时列表 |
| `nodes[].scenesDatas[]` | 节点 Scene 存储观察；实际联调还须核对 Scene 已存好。主 demo 为聚焦定时未展开此块 |
| `nodes[].timezoneOffset/timestamp` | 最近已知的节点时区偏移／Mesh 时间，不是定时的触发时间 |
| `updateTimestamp` | Space 配置版本时间，Unix 秒；不同于上面的节点时间 |
| 所属 **Site** 的 `timezone` | IANA 时区标识，例如 `Asia/Singapore`；不是 Schedule 或 Space 的新增字段 |

导出路径为 `Schedule.load` → `Schedule.encode` → `SpaceData.export`，同时导出节点投影和快照。导入先规范化／校验定时、身份和引用，再解码 `Schedule`，恢复节点 Model 快照并持久化，最后从这些配置重新计算同步任务。`group.info.bindSchedules`、节点 `scheduleIds` 等是本地关联／派生状态，不是服务器还需要额外写入的定时字段。

## 3. `space.schedules[]` 全字段说明

以下是当前 `Schedule.encode` 的字段。建议服务器显式写全字段；不要依赖导入器对旧数据的缺省修复。

| 字段 | JSON 类型／值 | 意义与空值规则 |
| --- | --- | --- |
| `id` | 非负整数 | Space 内唯一、稳定业务 ID。v2 可大于 15，不能直接拿来发 Mesh；v1 仅 0…15 |
| `name` | 字符串 | 展示名；可为空，不是身份 |
| `enabled` | `true`／`false` | 业务启停。false 保留定义及预约槽位；不等于删除或同步失败 |
| `selectTarget` | 0、1、2、3 | 见下一节 |
| `action` | 0、1、2、15 | 0=Off，1=Auto/On，2=Scene Recall，15=No Action；15 常用于业务删除 tombstone |
| `fadeTime` | 整数，秒 | UI 为 0…60；payload 校验接受 0…63。生产下发用秒分辨率，SDK 构造器把 steps=63 截为 62；新服务写入建议限制 0…60，不将 63 解释为 63 秒 |
| `hour` | 整数 0…23 | Site 当地时间的小时；无逐条 UTC offset 字段 |
| `minute` | 整数 0…59 | 分钟；App 下发固定 second=0 |
| `dayOfWeek` | 整数 0…127，位掩码 | bit0 周一至 bit6 周日，见下表。0 可导入但不触发，UI 不允许保存未选重复日的正常定时 |
| `deviceAddresses` | 4 位十六进制字符串数组 | 设备 **Primary Unicast Address**，例如 `"0300"`；没有直接设备目标时为 `[]` |
| `groupAddresses` | 4 位十六进制字符串数组 | Group 地址，例如 `"C001"`；没有 Group 目标时为 `[]` |
| `sceneAddress` | 4 位十六进制字符串或 `null` | 实际是 **Scene Number**，不是 Element 地址。无 Scene 时写 null；不要写 `"0000"` 或 v2 的 `""` |
| `profiles` | 对象数组 | 仅 Profile 定时使用，其他类型通常 `[]` |
| `nodeSlots` | 对象数组 | v2 显式数组；`[]` 表示还没有绑定。v2 缺失或 null 会规范化为 `[]`。v1 不携带 |
| `needDeleteNodeAddresses` | 4 位十六进制字符串数组 | 已从目标移除、设备侧尚需清理的旧直接节点 |
| `needDeleteGroupAddresses` | 同上 | 尚需清理的旧 Group 引用 |
| `needDeleteSceneNumbers` | 同上 | 尚需清理的旧 Scene Number 引用；不是节点地址 |

`second` 虽在 CodingKeys 中声明，但当前 Schedule 编解码不读写它。`year/month/day/second/transitionTime/sceneNumber` 属于节点寄存器字段，不要代替业务层的字段写到 `space.schedules`。

旧数据缺字段时，入口默认填充 `name=""`、`enabled=false`、`selectTarget=0`、`action=15`、`fadeTime/hour/minute/dayOfWeek=0`、`sceneAddress=null`；目标数组和 `profiles` 缺失可为空。这是旧格式兼容，**不是创建新定时的推荐默认值**；显式错误类型仍可能拒绝导入。

| 重复日 | `dayOfWeek` |
| --- | --- |
| 周一／周二／周三／周四／周五／周六／周日 | 1／2／4／8／16／32／64 |
| 工作日 | 31 |
| 周末 | 96 |
| 每天 | 127 |
| 周一、三、五 | 21 |
| 没有选择任何重复日 | 0；不代表一次性定时，也不代表每天 |

### 3.1 四类目标及当前支持边界

| `selectTarget` | 业务类型 | 正常数据组合 | 当前 App 行为 |
| --- | --- | --- | --- |
| 0 | Groups | `groupAddresses`，action 0/1，其余直接目标为空 | 将组展开到实际成员节点，各节点单独绑定 slot |
| 1 | Devices | `deviceAddresses`，action 0/1 | 直接节点；仍会根据节点实际 Group/Profile 选择 Auto On 的 Owner |
| 2 | Scene | `sceneAddress`，action 2，其他直接目标为空 | 根据 Scene 的 kind 展开 Group 成员或直接设备成员；不能只读 `groupAddresses` |
| 3 | Group Profile | `profiles[]`，通常 action 2 | 导入保留、列表显示；创建／编辑／启停／删除／一般同步受保护，不能期待 App 替服务器补配 |

这些是正常业务组合，不代表底层校验器会拒绝全部不合理组合。服务器创建时应遵守互斥目标和动作匹配。

合法空目标包含 Group／Device 空数组和 Scene `sceneAddress:null`；保留业务行，后续仍可编辑。它们与“整个定时删除完成、从 schedules 移除”不同。非空 Scene 必须在同一 Space `scenes[].number` 存在；新设备 Scene 还依赖 `spaceData.sceneConfigurations`。

Profile 项的字段为 `groupAddress`（Group 十六进制地址）、`profileSceneNumber`（Profile 场景号，例如 `"FF01"`）、可选 `groupName`、可选整数 `type`。当前 Schedule 对 `type` 没有自己的枚举校验；展示元数据若填写，应与对应 Group Profile 一致。Group Profile 的既有类型为 1=Occupancy+Daylight、2=Vacancy+Daylight、3=Occupancy、4=Vacancy、5=Daylight、6=Manual Control、7=Proximity Lighting、8=Proximity+Photocell。Profile 场景属于 `groups[].profile.scenes`，不能当成普通用户 Scene 随意新建。

**Profile 的物理执行规则不是由当前 App 的 `Schedule.schedulerEntry` 实现的。** 主 demo 只展示一个服务器自行管理、已存好 Profile 场景并由网关写入 Recall 的数据示意；对应固件行为、Profile Scene 建立顺序和回读需外部团队确认。App 对相关 Group 拓扑也有保护，不能仅因列表未出现 Unsync 就判定设备配置成功。

### 3.2 `nodeSlots[]` 的完整含义

| 字段 | 值／状态 | 约束 |
| --- | --- | --- |
| `identity.nodeUUID` | UUID 字符串 | 当前配网节点 UUID；服务器统一输出大写规范形式 |
| `identity.unicastAddress` | `"0100"` 等 4 位十六进制 | 节点 Primary 地址，范围 0001…7FFF；不是 Owner Element 地址 |
| `identity.deviceKeyFingerprint` | 64 位十六进制 SHA-256，Timed／快照当前生成小写 | **对 Device Key 的大写 HEX 文本做 UTF-8 编码后 SHA-256**，不是对 16 字节原始 Key 做哈希。Timed 身份比较需精确一致 |
| `slot` | 整数 0…15 | 此节点上的物理 Scheduler Index；同一业务定时在不同节点可以不同 |
| `state` | `"assigned"` | 此业务已占有该槽；可能尚未发送、已成功、停用、失败或部分成功 |
| `state` | `"pendingRemoval"` | 此节点不再需要该目标，仍保留槽位等待全部 Model 清理确认；不能提前复用 |

没有 `synced`、`failed`、`enabled` 等其他 binding state，也没有本轮需要新增的服务器 `generation`。旧 `nodeSlots[].generation` 无论值是什么均忽略，下一次正常导出／上传移除；**不能连带移除其他模块的同名字段**，例如 Scene pending operation 仍有自己的 generation。

同一业务不能重复绑定同一个配网身份；同一节点的同一 slot 不能同时归属两条业务。App 对节点所有 Scheduler Model 的有效占槽做并集，并保留停用槽／pendingRemoval，按每个节点最多 16 条计划控制容量；Space 总业务数可以超过 16。未知 Model 必须先读，不能假设空并抢占。

UUID、地址、Device Key 指纹三者共同防止重置后地址复用。对完整 Nodes 快照中已不存在的旧身份，App 会移除失效 binding，并移除不能继承的直接地址引用；这不授权服务器用不完整 Nodes 列表做修复，也不代表可只改指纹迁移真实设备。

## 4. 设备寄存器：`nodes[].schedules[]`

这一层没有 `enabled`、`name`、`selectTarget` 或业务 ID。`id` 为物理 slot，与业务关联必须经过 `nodeSlots`。

| 字段 | 当前 App 常规写入值 | SDK 可表达的设备原始值／含义 |
| --- | --- | --- |
| `id` | 每节点分配的 0…15 | Scheduler Index |
| `year` | 启用 100；停用 0 | 0…99=年份后两位，100=任意年；0 作为停用是 **App 约定**，不是 SIG 专用禁用枚举 |
| `month` | 4095 (`0xFFF`) | 12 位月份掩码，bit0 一月至 bit11 十二月；0 不触发 |
| `day` | 0 | 0 任意日，1…31 指定月中日期 |
| `hour` | 业务 hour | 0…23 指定时；24 任意时；25 每天随机一时 |
| `minute` | 业务 minute | 0…59 指定分；60 每分；61 每15分；62 每20分；63 每小时随机一分 |
| `second` | 0 | 0…59 指定秒；60 每秒；61 每15秒；62 每20秒；63 每分钟随机一秒 |
| `dayOfWeek` | 业务周掩码 | 0…127；0 不触发 |
| `action` | 业务 action | 0 Off、1 On、2 Recall、15 No Action |
| `transitionTime` | 秒整数投影 | `Int(entry.transitionTime.interval ?? 0)`：小数秒截断，unknown 投影为 0；不是 8-bit raw value |
| `sceneNumber` | Scene 号整数，否则 0 | 例如业务 `"000A"` 对应节点数值 10；`"FF01"` 对应 65281 |

当前 UI 的周期模型是“重复星期 + 固定时分”。一次性日期、按年／按月、随机时分秒、每15分等并非当前业务编辑能力；原始寄存器可保留这些观察数据，不应凭 `nodes[].schedules` 的表达能力宣称 App 支持编辑它们。

SIG 规定 Schedule 时间字段是本地时间；Year=0 是具体年份值，Month／DayOfWeek 全零不触发，Action=15 表示无动作。服务器应区分这些标准语义和本项目的停用／清理约定。[Bluetooth SIG Mesh Model 1.1，§5.1.4](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)

**停用：** 保留 slot，将 `enabled=false` 映射为 year=0，其他时间和动作保留。SDK `isEnabled` 只判断 `action != 15 && year != 0`，不检查周掩码／月份；因此它不是“未来一定会触发”的证明。

**清理：** 当前 App 发送 `SchedulerRegistryEntry()` 的完整默认值：year=100、month=0、day=0、hour=24、minute=60、second=60、dayOfWeek=0、action=15、transition raw=63 (`0x3F`)、sceneNumber=0。这是本地 SDK 实际清理格式，transition unknown 在此不能推广成新业务定时的推荐值；固件接受性须联调。

SDK `isValid` 的定义是“整条 entry 不等于上述默认清理值”，**不是 `action != 15`**。只把 action 改成 15，其他字节留旧，可能仍被视为残留占槽。清理成功后，Model 中该 slot 可以缺失，或显式存默认清理 entry；旧兼容投影通常不再包含它。

## 5. `custProps.schedulerModelStates`：不能丢失的 Model 快照

| 字段 | 类型／含义 |
| --- | --- |
| `schemaVersion` | 整数 1；与 `spaceData.timedSchemaVersion=2` 是两套独立版本 |
| `nodeUUID` | 所属节点 UUID |
| `unicastAddress` | 所属节点 Primary 地址 |
| `deviceKeyFingerprint` | 与该节点当前 Device Key 精确匹配的指纹，算法同上 |
| `models[]` | 仅列出**已有权威观察**的 Scheduler Setup Model 容器 |
| `models[].elementAddress` | Model 实际所在 Element 的单播地址；= Primary + `elements[].index` |
| `models[].modelId` | 字符串 `"1207"`，Scheduler Setup Server；不是 `1206`，也不是 Light LC 的 `130F` |
| `models[].entriesData` | Base64 字符串：该 Model 各 entry 的10字节参数串接；按 slot 排序导出 |
| `legacyEntriesData` | 同样的 Base64 10字节串接，对应 `nodes[].schedules` 的兼容缓存，保留未取整的原始编码 |

每条10字节依次打包：Index 4、Year 7、Month 12、Day 5、Hour 5、Minute 6、Second 6、DayOfWeek 7、Action 4、TransitionTime 8、SceneNumber 16 bit，低位开始、小端排列。**不含 SchedulerActionSet 的 opcode，也不是 JSON 字符串的 Base64。** 单容器最多16条、160字节，无重复 slot。

Transition raw 的高2位是分辨率（0.1／1／10／600 秒），低6位为 steps；steps=63 为 unknown。App 普通 fadeTime=5s 编码为 `0x45`，0s 编码为 `0x40`，不要把5s直接填成 raw=5（那是0.5s）。原始字节参与同步相等判断，连0秒的不同编码也可能构成差异。

| JSON 形式 | 状态含义 | 后续动作 |
| --- | --- | --- |
| 没有 `schedulerModelStates` 键 | 旧数据没有各 Model 的可靠快照 | 不能从 `node.schedules=[]` 推断所有 Model 为空；按需读回 |
| 有快照，`models=[]` | 所有 Model 观察未知 | 先读回 |
| 仅列出部分 `models` | 列出的已知，遗漏的支持 Model 未知 | 不补造空容器 |
| 某容器 `entriesData=""` | 这个 Model 已知为空，空字节的 Base64 是空字符串 | 可以据此判定该 Model 无占槽 |
| 某容器含10字节条目 | 已知条目，包括启用、停用或默认清空条目 | 解码后比较 |
| `schedulerModelStates:null`、错误身份、错误 Model 地址／重复容器、损坏 Base64／长度 | 声明了损坏的新快照 | 拒绝，不降级伪装成旧格式 |

`models` 的身份和地址必须匹配真实 Composition；支持的 `1207` 若在 Primary Element，也必须读写和记录，不能一律跳过 Primary。

`legacyEntriesData` 必须与 `nodes[].schedules` 一一对应，字段投影也必须一致。**它直接编码节点当前的 `schedulerActions` 兼容缓存；不能笼统理解为“把全部 models 的 entriesData 合并一次”。** 该缓存可能来自 SDK 的中性合并、App 的 Owner 筛选、云端原样恢复，或完整读取失败后的旧缓存恢复，具体算法见下面的 5.3。每个 Model 的完整观察仍需保留，不能用兼容缓存代替它。

新快照导入后恢复原始字节；只经过旧 `node.schedules` 的导入会重建月份、限制特殊时分秒并丢失部分 transition 精度。因此即使旧投影“看起来完整”，也不能替代新快照。

### 5.1 先用业务场景区分两个字段

可把 `entriesData` 看成“**某一张物理 Scheduler 表的已知内容**”，`legacyEntriesData` 看成“**旧代码仍在使用的单张节点兼容表的精确内容**”。二者用同一种字节编码，来源和用途不同。

| 问题 | `models[].entriesData` | `legacyEntriesData` |
| --- | --- | --- |
| 一台节点有几个？ | 每个已知 Scheduler Setup Model 各一个 | 整台节点一个 |
| 来自哪个内存变量？ | `allSchedulerModelEntrys[model]`，按 Model 再按 slot 分层 | `schedulerActions`，只按 slot 分层 |
| 同一 slot 在两个 Model 中参数不同时？ | 两份都保留，可以看到冲突 | 最多保留一份，无法描述两者同时存在 |
| 是否包含业务 ID／名称／目标？ | 不包含，只含物理 slot 及寄存器字段 | 同样不包含 |
| 为什么需要它？ | 判断 Owner 是否正确、其他 Model 是否有残留、是否可分配／释放槽位 | 无损恢复既有兼容缓存，支持仍读取该缓存的代码，并与旧 `node.schedules` 对应 |
| 是否是另一组要额外发送的定时？ | 否，是观察快照 | 否，不因这个字段再发一次命令 |
| 是否加密、压缩或哈希？ | 都不是；Base64 仅将二进制变成 JSON 可存的文本 | 同左 |

例如 Auto On 应在 LC Model，普通 Model 中却遗留相同 slot 的旧 On：仅看 legacy 可以只看见一条“正确”定时，而 `entriesData` 能证明普通 Model 还未清理。App 据此继续生成清理任务，防止同槽在不同 Model 中重复生效。

### 5.2 `entriesData` 的实际生成算法

**服务器不需要引入 iOS SDK。以下 Python 使用整数移位、10字节小端转换和标准库 Base64，即可生成完全相同的内容。** 可直接运行的完整文件为 [scheduler_snapshot_demo.py](261105_1429_space_timed_json_demo/scheduler_snapshot_demo.py)，完整输入、调用及输出见第5.6节。

先看一条“slot0，工作日08:00 On，渐变5秒”的完整生成过程。下面代码单独复制即可运行：

```python
# SINGLE_ENTRY_GENERATION_EXAMPLE
import base64

slot = 0                  # 当前节点的物理槽位，不是 Space 业务 id
year = 100                # 任意年；App 停用时写0
month = 4095              # 12个月全部选中
day = 0                   # 任意日期
hour, minute, second = 8, 0, 0
day_of_week = 31          # 周一至周五：1+2+4+8+16
action = 1                # On
fade_seconds = 5
transition_raw = (1 << 6) | fade_seconds  # 秒分辨率=1，steps=5，结果0x45
scene_number = 0          # 非 Scene Recall

# 每个字段占据自己的位区间；Python int 可以保存完整80位。
packed = (
    slot
    | (year << 4)
    | (month << 11)
    | (day << 23)
    | (hour << 28)
    | (minute << 33)
    | (second << 39)
    | (day_of_week << 45)
    | (action << 52)
    | (transition_raw << 56)
    | (scene_number << 64)
)
entry_bytes = packed.to_bytes(10, byteorder="little")
entries_data = base64.b64encode(entry_bytes).decode("ascii")

assert len(entry_bytes) == 10
assert entry_bytes.hex().upper() == "40FE7F8000E013450000"
assert entries_data == "QP5/gADgE0UAAA=="
print(entry_bytes.hex().upper())
print(entries_data)
```

运行输出：

```text
40FE7F8000E013450000
QP5/gADgE0UAAA==
```

上例用固定有效值展示编码；第5.6节完整实现会检查动态输入。**用来保存快照的输入应是网关已确认的节点寄存器内容**。同样的字节可先作为待发送命令参数生成，但不能在设备确认前就把目标值存成成功观察。

服务器为一张 Model 表生成 `entriesData` 的顺序：

1. 从节点 Composition 找出全部受支持的 Scheduler Setup Model（`modelId=1207`）。
2. 对每个 Model 准备 `{slot: 已确认的寄存器参数}` 字典。未知用 `None` 表示，整个 Model 容器省略；已知空用 `{}` 表示，保留容器并输出 `entriesData=""`。
3. 对已知字典的 `(slot, entry)` 按 slot 数字升序排序。字典键就是物理 slot；不是业务 id，也不是数组位置。
4. 按上述移位公式将字段合成整数，用 `packed.to_bytes(10, "little")` 生成10字节。完整实现的函数名为 `pack_entry(slot, entry)`，代码见第5.6节。
5. 用 `b"".join(...)` 按 slot 顺序拼接这些**原始字节**。例如 slot0 与 slot3 拼成20字节；不存在的 slot1／2不填空白，也不补默认条目。
6. 用 `base64.b64encode(payload).decode("ascii")` 对整个字节串编码，保留所需的 `=` padding，无换行。

导出函数本身不再按 `isValid` 过滤条目；正常设备回执处理遇到默认清理 entry 时已经把该 slot 从缓存移除了。若合法历史快照显式保留默认清理 entry，导出仍可保留它。不要混淆“收到清理结果后的缓存处理”和“把已有缓存编码”的两个阶段。

**正确顺序是 `Base64(entryBytes0 + entryBytes3)`，不是 `Base64(entryBytes0) + Base64(entryBytes3)`。** 前者编码一个20字节整体，后者是两个各带 padding 的字符串，无法作为这里要求的统一二进制数据解码。

### 5.3 `legacyEntriesData` 的实际生成算法：先明确缓存来自哪里

服务器先准备已确定的兼容表 `legacy_entries = {slot: entry}`，然后调用第5.6节的 `encode_entries(legacy_entries)`，即可得到 `legacyEntriesData`；同一份表通过 `readable_legacy()` 生成 `node.schedules`。**编码算法与每个 Model 的 entriesData 完全相同，区别只是输入哪张表。**

App 导出时对应的输入是当时的 `schedulerActions` 缓存，导出阶段不会重新执行下面任何一种投影。

当前维护 `schedulerActions` 的路径如下：

| 路径 | 如何得到兼容缓存 | 为什么如此处理 |
| --- | --- | --- |
| SDK 接收 `SchedulerStatus`／`SchedulerActionStatus` 后，或调用 `rebuildSchedulerActions()` | 遍历 `schedulerSetupModels`，再遍历各表；跳过 `entry.isValid=false` 的默认清空条目；以 slot 为键写入新字典；同 slot 后遍历的有效条目覆盖前者 | SDK 不依赖 App 的 Group Profile／业务动作，先提供中性的节点观察汇总 |
| App 的 SchedulerActionSet 成功回写，已提供实际 Model，调用 `rebuildTimedSchedulerActions()` | 对每个 slot 找唯一业务定时；优先用业务 action 判定 Owner；业务 action 是 noAction 或没有对应业务时改用该物理 entry.action；只保留有效且来自所选 Owner 的 entry | App 知道 Auto On／Group Profile，兼容缓存应反映当前业务所选 Model，其他 Model 的残留仍保留在原始表中 |
| 云端导入 `restoreSchedulerModelSnapshot` | 分别解码 `models[].entriesData` 和 `legacyEntriesData`，直接赋给两份缓存；不重新合并 | 保留这次上传时的两层观察，不擅自改变既有兼容投影 |
| SDK 的 `getSchedule(index:nil)` 完整读取失败 | 将失败节点的各 Scheduler Model 缓存标为未知，恢复读取前保存的 `schedulerActions` 和 `scheduleIds` | 不把半次读取视为完整设备状态；兼容缓存仍可能保留历史值 |
| 旧的 App 回写分支未提供 Model | 仅按 slot 更新／删除 `schedulerActions` | 缺少 Model 来源，不能凭这一结果构造完整的各 Model 快照 |

这里的 SDK 遍历顺序来自 `getFunctionModels` 对 `node.elements` 的遍历，不是“永远优先 LC”、不是按响应时间戳选最新，也不是按 `models` JSON 数组随意排序。正常 Composition 中按 Element index 枚举；后端重建时需固定为该节点实际 SDK／Composition 顺序。

App 的 Owner 计算仍用第8.1节规则。例如节点无 Group，业务 On 选择普通 Scheduler；节点属于自动 Group，业务 On 选择 LC Scheduler。**选定 Owner 没有该 slot 时，App 投影不会为了凑一条记录而改选非 Owner 残留。** 兼容缓存可能为空，而其他 Model 仍有残留，故删除和同步都不能只依赖 legacy。

SDK 的 `isValid` 比较全部寄存器字段是否等于默认清理 entry；停用的 year=0 不是空条目，仍参与投影。动作为15但其余字段不是默认清理值也可能参与投影。

#### 同样的 Model 快照，可以有不同的合法 legacy

新增案例 `same_slot_sdk_neutral_projection` 和 `same_slot_app_owner_projection` 的节点、业务和两张原始表完全一样：节点无 Group，业务 slot0 希望每天08:00 On，普通 Model 已08:00，LC Model 遗留09:00。

| 项目 | 内容／Base64 |
| --- | --- |
| 普通 Model `0100`，slot0=08:00 | `QP5/gADgH0UAAA==` |
| LC Model `0101`，slot0=09:00 | `QP5/kADgH0UAAA==` |
| SDK 中性合并后 legacy | `QP5/kADgH0UAAA==`，后遍历的 LC 覆盖同槽 |
| App 按普通 Owner 投影后 legacy | `QP5/gADgH0UAAA==` |
| 两个案例的同步判断 | 都是 `cleanup-entry-residual`；普通 Owner 已正确，但 LC 同槽未清理 |

App 快照校验要求 legacy 和 `node.schedules` 一致，但**没有强制 legacy 等于某种固定合并结果**，所以两种快照都能合法导入。

另一个新增案例 `unknown_models_preserve_legacy` 中 `models=[]`，`legacyEntriesData` 却非空。这对应读取失败后的状态：历史兼容缓存仍在，但各 Model 不能作为当前可靠观察。不能把这条 legacy 复制进每个 Model 来“补齐”快照。

### 5.4 10字节的精确布局

下面 offset 从整个80-bit记录的最低位开始计数；字节也是小端。Index 是10字节的一部分，但不属于76-bit的纯 Schedule Register 内容。

| 字段 | bit offset | 位数 | 输入 |
| --- | --- | --- | --- |
| Index | 0 | 4 | 物理 slot，0…15 |
| Year | 4 | 7 | 寄存器 year |
| Month | 11 | 12 | 月份掩码 |
| Day | 23 | 5 | 日期 |
| Hour | 28 | 5 | 小时 |
| Minute | 33 | 6 | 分钟 |
| Second | 39 | 6 | 秒 |
| DayOfWeek | 45 | 7 | 星期掩码 |
| Action | 52 | 4 | 0／1／2／15 |
| Transition Time | 56 | 8 | **原始编码**，不是秒数 |
| Scene Number | 64 | 16 | 整数场景号；低字节在 byte8，高字节在 byte9 |

等价算法是把各值左移到 offset 后按位 OR，得到80-bit整数，取其10字节小端表示。也可直接按位写入10字节数组。JavaScript 的普通 Number／32-bit位运算不能完整保存80-bit内容，需用 BigInt 或逐字节写入。

这10字节不含：Opcode、Element Address、Model ID、条目个数、长度前缀、CRC、业务 id。Element／Model 身份在外层容器里。发送 SchedulerActionSet 时 opcode 另加；不能把带 `0x60` 或收到的 `0x5F` 的完整报文一并放入 entriesData。

### 5.5 完整换算例：工作日08:00 Auto On，5秒渐变

取主 demo 的业务 id=100，在节点 A 分配 **slot=0**，Owner 为 `0101` LC Model。业务 id=100 不进入编码；只使用这个节点上的 slot=0。

寄存器参数为 year=100、month=4095、day=0、hour=8、minute=0、second=0、dayOfWeek=31、action=1、transition raw=69 (`0x45`)、sceneNumber=0。

| 字节 | 参与字段 | 计算结果 HEX |
| --- | --- | --- |
| byte0 | slot低4位 + year低4位左移4 | `40` |
| byte1 | year高3位 + month低5位左移3 | `FE` |
| byte2 | month高7位 + day低1位左移7 | `7F` |
| byte3 | day高4位 + hour低4位左移4 | `80` |
| byte4 | hour高1位 + minute左移1 + second低1位左移7 | `00` |
| byte5 | second高5位 + dayOfWeek低3位左移5 | `E0` |
| byte6 | dayOfWeek高4位 + action左移4 | `13` |
| byte7 | transition raw：秒分辨率 `01` + steps=5 | `45` |
| byte8／9 | sceneNumber=0 的小端两字节 | `00 00` |

因此单条的 Hex 为 `40FE7F8000E013450000`，将这10个二进制字节做 Base64 得到 **`QP5/gADgE0UAAA==`**。不要先把20字符的 Hex 文本转 UTF-8 再 Base64，那会编码出另一份数据。

下面继续展开主 demo 节点 A 的完整快照：

| 缓存 | 按 slot 升序排列的内容 | 字节数 | Base64 |
| --- | --- | --- | --- |
| 普通 Model `0100` | slot1 停用 Off，slot2 Scene Recall，slot4 Off | 30 | `Afh/YAHgD0AAAEL+fyAB4C9FCgBE/n9AAeAPRQAA` |
| LC Model `0101` | slot0 工作日08:00 On，slot3 每天10:00 On | 20 | `QP5/gADgE0UAAEP+f6AA4B9FAAA=` |
| legacy 兼容表 | slot0、1、2、3、4 | 50 | `QP5/gADgE0UAAAH4f2AB4A9AAABC/n8gAeAvRQoAQ/5/oADgH0UAAET+f0AB4A9FAAA=` |

此例不同 Model 没有同槽冲突，SDK 中性合并和 App Owner 筛选会得到相同兼容表；所以 legacy 恰好是两表条目合并后按 slot 排序。即使在此例中，也不是将两个 Base64 字符串直接拼接。

### 5.6 服务器可直接运行的完整 Python 示例

下面代码与 [scheduler_snapshot_demo.py](261105_1429_space_timed_json_demo/scheduler_snapshot_demo.py) 一致，仅依赖 Python 3 标准库，不需要 Swift、iOS SDK 或本仓库其他文件。复制整个代码块保存成 `.py` 后即可运行；也可以直接运行提供的文件：

```sh
python3 docs/261105_1429_space_timed_json_demo/scheduler_snapshot_demo.py
```

完整运行结果已保存为 [scheduler_snapshot_generated.json](261105_1429_space_timed_json_demo/scheduler_snapshot_generated.json)。程序演示“输入业务参数 → 构造待下发 entry → 假设网关已确认 → 按 Model 组织观察 → 生成两个 Base64 字段及 node.schedules”。实际系统必须由网关结果填充确认观察，示例没有执行通信、数据库或身份授权。

| 输入变量 | Python 形状／含义 |
| --- | --- |
| `weekly_entry(...)` 参数 | enabled、hour、minute、day_of_week、action、fade_seconds、scene_number，直接使用业务可读值 |
| `model_entries` | 按实际 Composition 顺序排列的 `(Element地址, slot字典或None)` 列表；`{}`=已知空，`None`=未知 |
| `legacy_entries` | 已确定的单张兼容表；`build_node_fragment` 不替调用者擅自选择生成策略 |
| `identity` | 现有节点 UUID、Primary 地址及指纹；示例复用合成节点身份，不含 Device Key |

`transitionTimeRaw` 只作为程序内部寄存器字段，输出 `node.schedules` 时转换成整数秒，不新增同名云端字段。

```python
# SNAPSHOT_CODEC_REFERENCE
import base64
import json

FIELDS = [
    ("year", 4, 7), ("month", 11, 12), ("day", 23, 5),
    ("hour", 28, 5), ("minute", 33, 6), ("second", 39, 6),
    ("dayOfWeek", 45, 7), ("action", 52, 4),
    ("transitionTimeRaw", 56, 8), ("sceneNumber", 64, 16),
]
DEFAULT_CLEAR = dict(year=100, month=0, day=0, hour=24, minute=60,
                     second=60, dayOfWeek=0, action=15,
                     transitionTimeRaw=63, sceneNumber=0)

def pack_entry(slot, entry):
    if type(slot) is not int or not 0 <= slot <= 15:
        raise ValueError("invalid physical slot")
    for field, offset, width in FIELDS:
        item = entry[field]
        if type(item) is not int or not 0 <= item < (1 << width):
            raise ValueError(field)
    if entry["year"] > 100 or entry["hour"] > 25:
        raise ValueError("reserved time value")
    if entry["action"] not in (0, 1, 2, 15):
        raise ValueError("reserved action")
    # 具体算法：各字段移到固定位置，再组合成80位整数。
    value = (
        slot
        | (entry["year"] << 4)
        | (entry["month"] << 11)
        | (entry["day"] << 23)
        | (entry["hour"] << 28)
        | (entry["minute"] << 33)
        | (entry["second"] << 39)
        | (entry["dayOfWeek"] << 45)
        | (entry["action"] << 52)
        | (entry["transitionTimeRaw"] << 56)
        | (entry["sceneNumber"] << 64)
    )
    return value.to_bytes(10, byteorder="little")

def encode_entries(entries):
    # None 表示未知，应由外层省略 Model；不能编码成空表。
    if not isinstance(entries, dict) or len(entries) > 16:
        raise ValueError("expected known slot dictionary")
    payload = b"".join(pack_entry(slot, entries[slot])
                       for slot in sorted(entries))
    return base64.b64encode(payload).decode("ascii")

def decode_entries(text):
    payload = base64.b64decode(text, validate=True)
    if len(payload) > 160 or len(payload) % 10:
        raise ValueError("invalid byte length")
    result = {}
    for start in range(0, len(payload), 10):
        chunk = payload[start:start + 10]
        value = int.from_bytes(chunk, byteorder="little")
        slot = value & 15
        if slot in result:
            raise ValueError("duplicate slot")
        entry = {field: (value >> offset) & ((1 << width) - 1)
                 for field, offset, width in FIELDS}
        pack_entry(slot, entry)  # 对新生成数据做取值校验。
        result[slot] = entry
    return result

def neutral_projection(model_entries_in_sdk_order):
    result = {}
    for entries in model_entries_in_sdk_order:
        if entries is None:  # 未知；不能据此推断该 Model 为空。
            continue
        for slot, entry in entries.items():
            if entry != DEFAULT_CLEAR:
                result[slot] = entry  # 后遍历的有效同槽条目覆盖前者。
    return result

def readable_legacy(slot, entry):
    result = {field: entry[field] for field, _, _ in FIELDS
              if field != "transitionTimeRaw"}
    raw = entry["transitionTimeRaw"]
    steps, resolution = raw & 63, (0.1, 1, 10, 600)[raw >> 6]
    result["id"] = slot
    result["transitionTime"] = 0 if steps == 63 else int(steps * resolution)
    return result

def weekly_entry(*, enabled, hour, minute, day_of_week,
                 action, fade_seconds, scene_number=0):
    # 对应当前 App 的正常周重复定时；清理 slot 用 DEFAULT_CLEAR。
    if type(enabled) is not bool:
        raise ValueError("enabled must be bool")
    for name, value, low, high in (
        ("hour", hour, 0, 23), ("minute", minute, 0, 59),
        ("day_of_week", day_of_week, 1, 127),
        ("fade_seconds", fade_seconds, 0, 60),
        ("scene_number", scene_number, 0, 65535),
    ):
        if type(value) is not int or not low <= value <= high:
            raise ValueError(name)
    if type(action) is not int or action not in (0, 1, 2):
        raise ValueError("action must be Off=0, On=1 or Scene Recall=2")
    if (action == 2) != (scene_number != 0):
        raise ValueError("Scene Recall requires a nonzero scene_number")
    return dict(
        year=100 if enabled else 0, month=4095, day=0,
        hour=hour, minute=minute, second=0, dayOfWeek=day_of_week,
        action=action, transitionTimeRaw=(1 << 6) | fade_seconds,
        sceneNumber=scene_number,
    )

def build_node_fragment(identity, model_entries, legacy_entries):
    # 这里只生成要并回完整 Node 的字段，不生成完整 Space／密钥／Composition。
    models = [
        dict(elementAddress=address, modelId="1207",
             entriesData=encode_entries(entries))
        for address, entries in model_entries if entries is not None
    ]
    snapshot = dict(schemaVersion=1, **identity, models=models,
                    legacyEntriesData=encode_entries(legacy_entries))
    return dict(
        uuid=identity["nodeUUID"], unicastAddress=identity["unicastAddress"],
        schedules=[readable_legacy(slot, legacy_entries[slot])
                   for slot in sorted(legacy_entries)],
        custProps=dict(schedulerModelStates=snapshot),
    )

def demo_node_fragment():
    # 1. 三条不同的业务定时；示例节点普通 Model=0100，LC Model=0101。
    on = weekly_entry(enabled=True, hour=8, minute=0, day_of_week=31,
                      action=1, fade_seconds=5)
    disabled_off = weekly_entry(enabled=False, hour=22, minute=0,
                                day_of_week=127, action=0, fade_seconds=0)
    recall = weekly_entry(enabled=True, hour=18, minute=0, day_of_week=127,
                          action=2, fade_seconds=5, scene_number=10)

    # 2. 单条编码调用与预期值；生成这些 bytes 不等于设备已成功配置。
    raw = pack_entry(0, on)
    assert len(raw) == 10
    assert raw.hex().upper() == "40FE7F8000E013450000"
    assert encode_entries({0: on}) == "QP5/gADgE0UAAA=="
    assert decode_entries(encode_entries({0: on})) == {0: on}

    # 3. 以下仅假设网关已确认这些表内容；真实服务用实际读回／确认结果。
    model_entries = [
        ("0100", {1: disabled_off, 2: recall}),
        ("0101", {0: on}),
    ]
    # 本例 slot 互不冲突，采用中性兼容表；App 上传的旧 legacy 应原样保留。
    legacy_entries = neutral_projection([entries for _, entries in model_entries])
    identity = dict(
        nodeUUID="00000000-0000-4000-8000-000000000001",
        unicastAddress="0100",
        deviceKeyFingerprint="0a4a91ae6e293dee6cb98cf621ae487d781966980403b7b0472e7807bd676c3b",
    )
    result = build_node_fragment(identity, model_entries, legacy_entries)

    # 4. 停用保留 slot1；默认清理条目可编码，清理确认后的兼容表不保留它。
    assert legacy_entries[1]["year"] == 0
    assert encode_entries({2: DEFAULT_CLEAR}) == "QgYAgHke8D8AAA=="
    assert neutral_projection([{2: DEFAULT_CLEAR}]) == {}
    assert encode_entries({}) == ""
    unknown = build_node_fragment(identity, [("0100", None), ("0101", {})], {})
    assert unknown["custProps"]["schedulerModelStates"]["models"] == [
        {"elementAddress": "0101", "modelId": "1207", "entriesData": ""}
    ]
    return result

if __name__ == "__main__":
    print(json.dumps(demo_node_fragment(), ensure_ascii=False, indent=2))
```

运行后，输出的两个 Model 和兼容缓存字段如下；完整输出（含身份和可读的 `schedules`）见配套 JSON：

```json
{
  "models": [
    {
      "elementAddress": "0100",
      "modelId": "1207",
      "entriesData": "Afh/YAHgD0AAAEL+fyAB4C9FCgA="
    },
    {
      "elementAddress": "0101",
      "modelId": "1207",
      "entriesData": "QP5/gADgE0UAAA=="
    }
  ],
  "legacyEntriesData": "QP5/gADgE0UAAAH4f2AB4A9AAABC/n8gAeAvRQoA"
}
```

这份最小可运行例只有 slot0／1／2，共3条定时；第5.5节展开的是主 demo 的 slot0…4，共5条，因此两者的完整 legacy 字符串不同，单条 slot0 编码完全相同。

生成新快照时，`models[i].entriesData = encode_entries(model_i)`；先确定本次兼容缓存 `legacy` 后，再令 `legacyEntriesData = encode_entries(legacy)`，`node.schedules = [readable_legacy(slot, legacy[slot]) for slot in sorted(legacy)]`。从设备数据新建中性兼容表时可用 `neutral_projection`；如果是在转存 App 上传／读取失败的既有快照，应保留它原有的 legacy，而不是再次强制合并。

实际接入时，只把 `build_node_fragment` 生成的 `schedules`、`custProps.schedulerModelStates` 合并到对应的完整 Node，保留 `custProps` 其他键以及现有 Node／Space 字段。合成 identity 不能用于真实节点；此函数只演示数据构造，不代替身份校验和服务器事务。

参考代码对新生成数据拒绝保留值；当前 App `SchedulerModelSnapshot.entries` 的结构校验主要检查长度、重复 index 和 action，并不等于完整标准语义验证。不能因为某段异常 bytes 暂时通过 App 结构校验，就把它作为网关应写入的有效配置。

数组转为 slot 字典之前还应检查重复 slot，不能让字典覆盖掩盖坏输入。80-bit记录不需要额外校验和；外层身份／版本／Composition 校验仍不可省略。

### 5.7 恢复、同步与删除分别如何用到它们

| 业务功能 | 使用方式 | 错误生成会造成什么 |
| --- | --- | --- |
| App Sync Space／换手机导入 | 先校验身份与 legacy 可读投影，再分别恢复 Model 表和兼容表 | 仅修改 legacy 不修改 `node.schedules` 会因 `legacyProjection` 拒绝；伪造空 Model 会丢失残留证据 |
| 退出重进／App 重启 | SDK 的 `allSchedulerModelActions` 保存各 Model 容器，`schedulesData` 保存兼容表；加载时分别恢复 | 这两列不是云端字段名；不能假定只保存一列就能恢复全部状态 |
| 显示 Unsync／生成同步任务 | 主要比较 Owner 表与目标参数，并检查非 Owner 同槽是否干净 | legacy 看似匹配仍可能显示 Unsync，这是有残留或未知 Model 的合理结果 |
| 16槽容量及新增定时 | 对全部已知 Model 的有效槽做并集，再结合业务预约／pendingRemoval | 只按 legacy 计数可能漏掉其他 Model 占槽；未知不能当作有空位 |
| 删除／Group 或 Scene 移除 | Model 层证明全部清理完成；`needsDelete`／`hasObservedEntry` 也会读取 legacy 作为残留线索 | 提前把两层都清空会让清理任务丢失；只清 legacy 不代表物理删除完成 |
| 云端上传后的回读／恢复确认 | `SchedulerModelSnapshot.spaceData` 将 Model 与条目排序规范化后参与快照比较 | 无序数组差异可规范化，但实际参数／未知状态变化不能忽略；只存顶层定时不足以通过该确认 |
| 小数秒、长 transition、随机时间等设备观察 | 原始 bytes 保存精确值，legacy 数字层只作兼容展示／传输 | `transitionTime=0` 无法区分立即、0.7秒取整、unknown；从可读字段反推 raw 会损失信息 |

导入恢复时**不发 Mesh 指令**；两个字段记录的是设备观察，真正下发仍由后续同步任务决定。保存 JSON 成功与设备已经写入、之后按时触发，是三个不同结果。

服务器最稳妥的更新单位是“同一次已确认观察中的原始 Model 表 + 已确定的兼容表 + 对应 `node.schedules`”。修改一个 slot 时保留其他 slot；有业务意图变更但设备失败时，保留新业务目标及旧／未知观察，不用新期望值覆盖观察来制造同步成功。

## 6. 同步状态怎样从 JSON 得出

业务层没有持久化的单一 `syncState`。`enabled`、`nodeSlots.state`、物理条目和云端上传状态是不同维度。对某条普通定时的某节点，当前 App 依次判断：

| 派生结果（调试名称，不是 JSON 字段） | 条件 |
| --- | --- |
| `not-applicable` | 节点不在目标里、Profile 受保护或不存在适用 Model 等；不等于网关配置成功 |
| `owner-entry-missing` | 未分配 binding，或 Owner 已知但没有该 slot |
| `owner-model-unknown` | 已绑定但 Owner Model 未知 |
| `owner-entry-mismatch` | Owner 已知但参数与业务目标不同 |
| `cleanup-model-unknown` | Owner 已匹配，但至少一个非 Owner 未知 |
| `cleanup-entry-residual` | Owner 已匹配、非 Owner 已知，但同 slot 有有效残留 |
| `synchronized` | Owner 原始参数匹配，所有非 Owner 的同 slot 确认已清空 |

`synchronized` 是当前可信缓存上的比较结果，不证明节点当前在线、时钟仍正确或已在预期时刻触发。删除另走 `deletionIsSynchronized`：所有支持 Model 的同 slot 都已知且不再占用，才能释放 pendingRemoval；未知和部分清理均保留重试意图。

启停操作全失败时，当前 App 会回滚业务 enabled，但已持久化的槽位预约可以保留；部分设备成功时保留新 enabled，失败设备等待同步。服务器若采用“先保存目标、异步执行”的策略，应明确保存的是目标意图，失败时仍保留旧设备观察；不要伪造一次全成功快照。

## 7. 主 demo 的逐条含义

节点 A=`0100`、B=`0200`，同属自动控制 Group `C001`；C=`0300` 无 Group；D=`0400` 属于 Profile 示例 Group `C003`。示例每节点 Primary 为普通 Scheduler，Primary+1 为 Light LC Scheduler；这是演示拓扑，生产必须查 Composition。

| 业务 ID | 类型／状态 | 关联槽和读法 |
| --- | --- | --- |
| 100 | Group Auto On，工作日08:00，已同步 | A slot0、B slot3，均在 LC Model |
| 101 | Group Off，22:00，已停用且同步 | A slot1、B slot4，普通 Model year=0，仍占槽 |
| 102 | Device On，周末09:30，已同步 | C slot0，普通 Model |
| 103 | Group Scene Recall，每天18:00 | `000A` 展开 Group C001；A slot2、B slot5 |
| 104 | Device Scene Recall，每天19:00 | `000B` 从 sceneConfigurations.deviceMembers 展开到 C slot1 |
| 105 | 两设备改成10:00，部分成功 | A slot3 LC 已10:00；B slot6 LC 仍09:00；binding 都是 assigned |
| 106 | 新建 Device Off，23:00，未分配 | C 为目标，但 nodeSlots=[]；发送前必须预约空槽 |
| 107 | 整条定时删除未完成 | 业务 action=15、目标已空；C slot2 pendingRemoval，设备仍保留旧 On |
| 108 | 保留 A、移除 C | A slot4 assigned；C slot3 pendingRemoval；needDeleteNodeAddresses 保留 C |
| 109 | Group 空目标 | 保留业务定义，无设备要执行 |
| 110 | Profile 定时 | D slot0，设备示意 Recall FF01；App 只读，不负责验证／完成此业务配置 |
| 111 | Scene 空目标 | selectTarget=2、sceneAddress=null；不等于普通 Scene Recall 已落地 |
| 112 | 导入的零星期掩码 | C slot4，enabled=true 但 dayOfWeek=0，不会触发；不是 UI 正常新建结果 |

各个非互相兼容的状态放在 `timed_state_cases.json`，包括上述六种 Unsync／同步结果、停用、全部／部分未知、旧快照缺失、binding 缺失/null、删除待清理／部分清理／全部清理／完成、空目标、v1、旧写端丢 v2 字段、旧 generation、旧配网身份、三种非法输入、Group／Scene 目标移除、非默认 noAction 残留，以及16／17槽容量边界。本次还补入两种不同投影的同槽冲突和未知 Model 保留 legacy 三个案例，总计36个。`expected` 仅是校验器预期，不写入服务器 Space。

## 8. 网关配置与服务器保存的执行契约

本节是基于 App 当前行为给服务器／网关团队的对接要求，**不代表这些外部能力已经实施**。服务器写入必须遵守已有编辑权限、并发控制、Space 版本和完整配置存储机制；不要把 App 请求包装当成新网关命令接口。

### 8.1 选择目标及唯一 Owner

| 动作／节点实际归属 | Owner | 同 slot 需要先清理的范围 |
| --- | --- | --- |
| action=1，处于非 Manual Control Group | Light LC Element 的 Scheduler Setup Server | 其他全部 Scheduler Setup Model |
| action=1，无 Group／Manual Control／退出组失败 | 普通 Scheduler Setup Server | 其他全部 Scheduler Setup Model |
| Off／普通 Scene Recall | 普通 Scheduler Setup Server | 其他全部 Scheduler Setup Model |
| 删除或已移除目标 | 无保留 Owner | 节点全部 Scheduler Setup Model |

普通 Owner 优先选非 Light LC 的 Scheduler；只有单 Model 或缺指定 Owner 时沿用 SDK 的兼容回退。`node.groupState`：0 未加入，1 在组内，2 退出组失败；2 不作为当前 Group 目标，仍可能有清理任务。`groups[].scenesDatas[].state`：1 正常，2 待删除；2 不作为新增 Scene 目标。

Group 只是业务目标集合。**Scheduler 配置按每个节点实际 Element 单播**，因为节点 slot、Model 地址和结果不同；不能用 Group 地址把一个 slot 广播给全部节点。请求中的 index 是参数，Mesh destination 是 Model 所在 Element 的地址，两者不能混淆。

### 8.2 执行顺序、命令与回执

| 顺序／条件 | 具体目标与命令 | 参数与 ACK 要求 |
| --- | --- | --- |
| 1. 获取完整当前配置 | 服务器完整 Space、Nodes Composition、目标 Group／Scene、所属 Site 时区 | 确认设备配网身份；不能只按地址复用旧槽位 |
| 2. Model 状态未知 | 对每个支持的 Scheduler Server `1206` 所在 Element 发 `SchedulerGet` `0x8249` | 期待 `SchedulerStatus` `0x824A` 位图；读取已有槽的 `SchedulerActionGet` `0x8248`，期待 `SchedulerActionStatus` `0x5F`，核对来源 Element、index 和参数 |
| 3. 分配及保存意图 | 服务器原子预约 `(Space, 配网身份, slot)` | 先持久化业务及 assigned／pendingRemoval，保留已知观察；失败不能丢失预约或清理任务 |
| 4. 新增／修改／启用，节点有 Time Model | 对 Time Server `1200` 所在 Element 发 `TimeSet` `0x5C` | 每节点批次一次，按 Site 当前偏移动态生成，期待 `TimeStatus` `0x5D`；准备／校时失败阻止依赖它的启用定时。停用、删除不需要先校时 |
| 5. Scene Recall 的前置配置 | 先把对应 Scene 的真实参数写入目标节点并完成 Scene Store | Scene 号／成员／参数与 Space 一致后再配置 Recall 定时；具体 Scene 配置沿用现有 Scene 协议，不能只创建名称 |
| 6. 普通写入／停用 | 对每个非 Owner `1207` 发 `SchedulerActionSet` `0x60` 清同 slot，再对 Owner `1207` 写目标 entry | 参数10字节，期待 `0x5F`；必须核对来源、index、全部 entry。一个节点双 Model 通常至少2条 Scheduler 写入，另可能有1条 TimeSet |
| 7. 删除／移除旧节点 | 对**全部** `1207`（含支持它的 Primary）发 `0x60` 默认清理 entry | 每个 Model 同 slot 均确认；部分 ACK 或仅 action=15 不足以释放绑定 |
| 8. 保存观察及回读 | 按每节点／每 Model 保存已确认结果，重建 node.schedules + legacyEntriesData | 维持其余 slots；不把发送请求、HTTP 200、网关接单当作节点写入成功 |
| 9. 收尾 | 完成清理后释放对应 pendingRemoval，移除已完成旧引用；整条删除完成再移除业务行 | 失败／超时／取消保留待重试状态。正常修改成功保留 assigned，不改成 synced |
| 10. 验收服务器回读 | 更新 Space updateTimestamp，并 GET 完整 Space；App 重新 sync/reload | 时间戳为 Unix 秒，需遵守现有版本／并发规则，避免新意图被旧上传覆盖；只有 node 观察变化也要完整保留快照 |

读回要求以已完成的完整 Model 观察为边界；仅成功写一个 slot 不足以把一个原本未知的整张 Model 表标成“已知且其他都空”。先完整读取或保留未知；只有被证实的结果才能进入快照。

**失败与重试契约：** 用相同 identity／slot 重试同一意图，不因失败新分配槽；超时代表结果不确定，先读回消除歧义；同槽新意图接管旧任务，迟到回执不得覆盖新意图。已成功且参数未变的节点不重复配置。当前 SDK 对 `busy` 有最多3次再排队，但完整 Mesh 可靠传输还有自己的重试／超时；服务器网关的次数、间隔、请求关联和持久任务恢复需由对应团队明确，不能将“3次”当成所有失败的通用协议常量。

App 的同槽任务隔离目前是内存运行机制，不是持久化 generation。服务器需要在自身任务系统保证并发串行／替换及结果归属；不要向 Space 添加未经约定的替代字段。

### 8.3 时区、时间戳与 DST

- `schedule.hour/minute` 为 Site 当地墙上时间，不应在数据库直接转成 UTC 时分覆盖。
- Site `timezone` 保存 IANA ID。当前 `SiteTimeSetMessageFactory` 在发送前通过现有时区服务准备当前偏移；缺失 Site／时区、服务器结果无效或过期、Site 已变化会拒绝该校时前置，不静默用手机时区继续。
- 节点 `timezoneOffset` 是 Mesh 编码整数：`offsetMinutes / 15 + 64`。UTC 为64，UTC+8 为96；不是小时数8，也不是字符串。只有节点时间已知时才应记录已确认值。
- 节点 `timestamp` 是 SDK `TimeStatus.time.seconds` 的 Mesh TAI 秒，0 为未知；不是 Unix 秒，也不是毫秒。SDK 转换为 `UnixSeconds - 946684800 + TAI_UTC_Delta`，Delta 应使用执行时可信值。
- 主例 `updateTimestamp=1793836800` 与节点 `timestamp=847152037` 仅演示同一合成时刻按 Delta=37 的两种数值。不能复用这些固定值发送真实 TimeSet。
- 当前偏移不代表未来 DST 规则已下发。服务器／网关需按 Site IANA 时区处理后续切换并验证设备本地时间；本文不假设已有自动 DST 调度实现，也不新增这类 Schedule JSON 字段。

## 9. 兼容、错误与发布依赖

1. v1：`timedSchemaVersion` 缺省为1，业务 id 必须0…15，nodeSlots 不存在。非 Scene 的历史 sceneAddress 空字符串可规范化为 null。
2. v2：显式写 `timedSchemaVersion=2`，bindings 缺失/null 视作未分配，不从业务 id 猜物理 slot。特定旧写端丢 schema 和所有 bindings、却保留 id≥16 时，App 可提升为 v2 未分配；不能据此宣称设备观察已恢复。
3. 同一节点重复槽、非法 state/slot、损坏快照等仍拒绝。错误或不完整结果不能变成 `schedules=[]` 上传；真实空数组则意味着确实没有业务定时。
4. `custProps` 的其他键、`spaceData` 的其他模块及完整 Group／Scene 配置必须保留。旧写端整块覆盖会损失新快照；服务器存储和返回链路须证明能无损保留。
5. 仍强制要求 `nodeSlots.generation` 的旧 App 可能拒绝新版数据。去字段前应确认客户端版本支持范围；本次没有实现服务端版本隔离，也没有确认远端发布状态。
6. 新设备 Scene 的 schema、revision 和 pending operations 属于 Scene 模块，不能套用 Timed 的 generation 移除规则。Scene 删除还可能带 schemaVersion=2 的删除引用，应沿用该模块既有契约；本文没有将 Scene 全协议替换为定时协议。

| 责任方 | 必要交付 | 验收与发布依赖 |
| --- | --- | --- |
| 服务器团队 | 业务目标、唯一槽位预约、完整 JSON 存储／回读、并发版本及持久任务恢复 | 新旧客户端往返不丢字段；失败／重启可继续；不可只保留顶层 schedules |
| 网关团队 | Composition 解析、单播目标与 Owner 选择、校时、读写和结果关联 | 逐 Model 读回，参数匹配；失败、离线、迟到响应、目标变化均正确 |
| 固件团队 | 确认 Scheduler 清理／停用约定、LC 路由、Profile 场景及时间触发行为 | 真机验证；如有差异另立外部配套任务，由对应团队实施 |
| App／SDK 团队 | 当前契约兼容版本及正式依赖可用 | 本地 revision 不是远端 release 完成的证明；正式发布前核对 SDK 来源 |

## 10. 验证范围与最短联调步骤

离线校验命令：

```sh
python3 docs/261105_1429_space_timed_json_demo/verify_demos.py
```

校验器在内存中补合成 Device Key，执行当前 `TimedSchedulerPayloadPolicy`、`SchedulerModelSnapshot`、Scene 引用／配置校验，抽取生产 `Schedule.schedulerEntry` 和 SDK Scheduler wire codec 验证10字节往返；状态案例调用生产同步差异策略。它验证字段与编码契约，**没有经过完整 Space 导入事务、SQLite 重启、真实服务器映射、UIKit 或 BLE**。Profile 样例的设备效果也不在离线证明范围内。

本次执行结果：

| 检查 | 结果与边界 |
| --- | --- |
| `verify_demos.py` | 主 Space 字段节选、36 个独立案例、16 个 SDK wire 往返通过；执行生产 SDK 中性投影和 App Owner 投影方法，验证同槽冲突、Owner 变化、非 Owner 残留、停用保留及默认清理过滤 |
| `scripts/check_timed_device_slots.py` | 业务 ID／slot 分离、缺失/null 绑定、旧写端、失效身份、容量及请求字段规范化通过 |
| `scripts/check_scheduler_cloud_roundtrip.py` | 70 节点／140 个 Model 容器离线往返通过，保留32个空容器和108个非空容器；未传服务器目录、没有真实后端调用 |
| 纯 Python 可运行示例 | 使用 Python `-I` 隔离模式，在仓库外的临时目录执行成功；结果与文档示例、保存的输出 JSON 一致。为字段节选补入主 demo 的合成 Composition 和内存测试身份后，快照通过当前 App／SDK 校验 |
| JSON／链接／差异检查 | 4 个 JSON 均可解析，无密钥或认证字段；本地文档链接及 diff whitespace 检查通过 |

两个已有脚本使用 `/tmp/sunsmart-timed-json-demo-module-cache` 作为 `CLANG_MODULE_CACHE_PATH` 和 `SWIFT_MODULECACHE_PATH`，没有清理共享缓存。

本次补充重跑更新后的 demo 校验器，执行第5.2节单条换算、第5.6节独立 Python 程序及全部现有二进制样例的逐字节对照。SDK／App 投影方法体来自生产源文件；Node／Model／Group 查询和 slot 对应业务是可控夹具边界，不代表真实 UI／网络／持久化生命周期已验收。前述两个未改动的已有回归结果为首次交付时的结果，本次未重复运行。

本任务是文档交付，不构建 App，不安装真机。已有业务改动的历史构建结果不作为这批服务器示例的联调证据。

最短人工联调：

1. 从测试服务器读取一个完整测试 Space，替换为测试节点真实身份／Composition，新增一条 Group Auto On 和一条 Device Off；确认不同节点可以使用不同 slot。
2. 网关校时并配置；逐 Model 读回。保存完整 Space 后让 App Sync Space、退出重进，确认业务时分、启停和同步提示正确。
3. 修改一条定时时让其中一个节点离线；服务器保留新意图和该节点旧观察。App 应能区分部分成功，恢复在线后只补未完成节点。
4. 停用后确认原 slot 保留、year=0；重新启用可恢复。再删除并模拟某个 Model 清理失败，确认 pendingRemoval 保留，全部清空后才释放。
5. 分别测试 Group Scene、Device Scene；确保先建立场景再 Recall。Profile 独立由服务器／网关／固件验收，App 只读展示不充当成功标准。
6. 重启 App／服务端任务进程，再回读 Space；确认空 Model 与未知 Model 没被混淆，真实本地时刻触发符合 Site 时区，并另测 DST 切换。

## 11. 主要源码证据

| 结论 | 当前入口 |
| --- | --- |
| 业务字段、Codable、停用映射 | [Scheduler.swift](../SunSmart/Main/Timed/Model/Scheduler.swift) 的 TargetType、ScheduleProfile、CodingKeys、schedulerEntry |
| schema、identity、绑定状态、缺字段、旧 generation、容量 | [TimedSchedulerSlotPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift) |
| 预约、已知占槽、清理完成与释放 | [TimedSchedulerBindings.swift](../SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift) |
| Owner／派生同步状态／App 兼容投影 | [TimedSchedulerOwnerPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift)、[MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift) 的 Schedule 扩展、rebuildTimedSchedulerActions、updateData |
| 节点／Space 导出与快照适配 | [ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 的 SpaceData.export、schedulerModelSnapshot |
| 快照格式、身份／投影严格校验 | [SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift) 的 SchedulerModelSnapshot |
| 导入／持久化和快照恢复顺序 | [ImportData.swift](../SunSmart/Common/Data/ImportData.swift)、[Database.swift](../SunSmart/Common/Data/Database.swift) |
| 写入、全失败回滚、删除和回执 | [ScheduleServer.swift](../SunSmart/Main/Timed/Model/ScheduleServer.swift)、[Node+MessageHandles.swift](../SunSmart/Common/Data/Node+MessageHandles.swift) |
| UI 周期／fadeTime 限制、Profile 保护 | [ScheduleAddView.swift](../SunSmart/Main/Timed/View/ScheduleAddView.swift)、[TimedViewController.swift](../SunSmart/Main/Timed/Controller/TimedViewController.swift) |
| API 包装、generation 出口过滤 | [NetowrkReqeustApi.swift](../SunSmart/Common/Network/NetowrkReqeustApi.swift) |
| Scene 类型、成员及引用 | [SceneConfiguration.swift](../SunSmart/Main/Scene/Model/SceneConfiguration.swift) |
| TimeSet 前置与 Site 时区 | [SiteTimeSetMessageFactory.swift](../SunSmart/Common/Data/SiteTimeSetMessageFactory.swift)、[SiteTimeZoneValue.swift](../SunSmart/Common/Data/SiteTimeZoneValue.swift)、[TimedScheduleTimeSyncPolicy.swift](../SunSmart/Common/Data/TimedScheduleTimeSyncPolicy.swift) |

SDK 对照（路径相对于上述实际 SDK）：`nRFMeshProvision/Mesh Messages/SchedulerMessage.swift`、`nRFMeshProvision/Type Extensions/Data.swift`、`MeshLib/Manager/MeshScheduleServer.swift`、`MeshLib/Node/Node+SupportModels.swift`、`MeshLib/Node/Node+Messages.swift`、`MeshLib/MeshDatabase.swift`、`nRFMeshProvision/Mesh Model/TransitionTime.swift`、`MeshLib/Message/ExplicitTimeSetInput.swift`。均位于 `Sources/NordicSigMeshSDK/` 下。


## 12. 2026-11-06：已确认的 v3 精简结构及回写契约

### 12.1 结论与授权边界

**已确认采用 `timedSchemaVersion=3`：共享 JSON 仅保留业务定义、节点槽位、动作地址和任务级状态，删除节点侧两份定时观察 JSON；本地继续使用现有 SDK 的逐 Model 观察缓存。** 需要同步调整状态判断、持久化及恢复，不能只删几个 encode 字段。

两项决定已由用户确认：

1. **单向迁移**：新版读取并转换旧数据，成功转换后只写 v3，不长期双写，不保证旧 App 继续编辑。
2. **保留当前 Group 路由规则**：有 LC 不等于一律用 LC；无 Group、Manual Control、退出组失败继续使用普通 On。

本轮用户补充要求删除 `needDeleteSceneNumbers`，并希望将 `unknown` 合并到 `pendingApply`；本文据此修订为**删除三组待删数组、只保留三状态**。用户随后明确“确认这版结构和回写规则作为实施依据”；本节完整结构、执行约束及数据库内容已获授权，实施结果见第 13 节。

| 核对项 | 当前事实 |
| --- | --- |
| App 工作树／分支 | `feat-timed-simple-261106`／`feat/timed-simple-261106` |
| App HEAD | `71dd7e0b67ff33c1a448dd16de08719c4c45ee69` |
| SDK realpath | `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，由现有 `.local-sdk/nordic-sig-mesh-sdk` 引用 |
| SDK HEAD | `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，核对时无未提交差异 |
| 名称校正 | 当前 JSON 键为 `schedules`，不是 `schedulers`；本次不重命名。新键统一采用用户示例的单数 `actionAddress` |

比较的方向：只删兼容投影、保留共享 Model 快照，改动较少但精简有限；完全删除观察和身份保护，会失去容量、重试、地址复用依据；**推荐共享格式精简、本地观察保留**，代价是任务状态维护及导入后的必要读回。已选兼容策略是单向迁移。

### 12.2 对用户各项问题的直接回答

| 项目 | 当前事实 | 建议 |
| --- | --- | --- |
| identity 仅保留地址 | UUID／指纹可从同一完整 Nodes 快照获得；当前 Nodes 不能反推旧任务的配网实例 | 共享 JSON 仅保留地址，本地绑定和异步任务仍保留完整身份，满足 12.5 的完整快照前提 |
| state | 当前只有 `assigned`、`pendingRemoval`；assigned 含未发送、失败、部分成功、成功、停用 | 改为 12.3 的三状态，不能直接把 assigned 改名 synced |
| slot | 物理 Scheduler Index，0…15；严格来说属于某个 Scheduler Register | 保留。App 对同节点各 Model 的同 index 做统一预约，业务 id 与 slot 仍分离 |
| nodes[].schedules | 旧兼容投影，可能含实际旧值、孤立条目，并非全都能从期望业务重建 | 从 v3 JSON 删除；暂保留 SDK 本地缓存与现有使用方 |
| schedulerModelStates | 身份、Model ID 可推导；实际参数、未知／已知空、非 Owner 残留、孤立占槽不能由业务目标推导 | 从共享 v3 删除；真实观察留在本地／按需读回，actionAddress 只接管路由职责 |
| needDeleteNodeAddresses | 当前代码仍读取，是历史清理意图 | 捕获完整 binding 后可删除 |
| needDeleteGroupAddresses | 当前代码仍读取，也参与 Group 本地关联 | 冻结旧成员 binding 并调整关联／任务入口后可删除 |
| needDeleteSceneNumbers | 现有实现记录旧 Scene 引用，但同 slot 的新目标可覆盖旧 Recall | v3 删除；共同节点 pendingApply 写新场景，旧目标独有节点 pendingRemoval；Scene 删除入口通过绑定和真实读回查残留 |

**“不再放入共享 JSON”不等于“真实设备观察可以推导”。** v3 可以恢复业务及清理意图，但不再保证把逐 Model 原始寄存器无损复制到另一手机。v2 的原始字节备份保证不能沿用到 v3。

### 12.3 建议的三种 state

| v3 值 | 意义 | 占槽与完成条件 |
| --- | --- | --- |
| `pendingApply` | 当前目标尚未确认完成；含未执行、失败、部分成功，以及旧数据缺少可信结果 | 占槽；必要时先读回，若已匹配则不重发，Owner 参数和全部非 Owner 清理确认后变 synced |
| `synced` | 最近可信回执／读取已确认当前期望配置及非 Owner 清理完成 | 占槽；实际下发内容变化后回到 pendingApply；不表示设备在线或已按时触发 |
| `pendingRemoval` | 节点移出目标或整条业务删除，设备尚未全部清理 | 占槽；全部支持的 Scheduler Models 同 slot 确认无有效项后移除 binding |

用户所说“已添加／添加未成功／删除未成功”分别落在 synced／pendingApply／pendingRemoval。pendingApply 统一表示“让当前期望配置最终生效，尚未确认完成”，不要求知道此前是否发送过，因此可以合并原建议中的 unknown。不另外持久化失败次数、错误原因、正在发送等运行细节。

取消的是 **binding.state 的 unknown 枚举**；本地 Model 观察仍须区分“未知”和“已知为空”。前者要求必要的读取／校验，不代表设备空槽，也不意味着 pendingApply 一定要重写：读回发现当前内容已正确，可直接确认 synced。没有可信 slot 归属的记录仍保持未绑定，不能靠 pendingApply 猜一个 slot；属于删除任务但缺结果时保持 pendingRemoval。

状态规则：

- `enabled=false` 是业务停用，仍占槽，成功停用后也可以 synced；不另设 disabled。仅修改名称不触发重写。
- `nodeSlots:[]` 表示尚未绑定，不是成功或失败状态。合法空目标仍保留业务行。整条删除继续沿用现有 action=15 tombstone，所有清理完成后删除业务行。
- 半成功保留 pendingApply／pendingRemoval；具体哪些 Model 成功由现有本地缓存保存。重启后复用有效缓存，缺失或超时不确定时读回，只补未完成部分。
- 启停全失败回滚业务后，状态按回滚后的目标重新核对；部分节点成功则逐节点记录，不能把整条业务结果复制给所有节点。
- 新业务参数、全部相关 binding 及状态必须作为同一次配置提交；不再保存 Timed 的旧 Scene 引用。ACK 后本地保存失败不能导出 synced。重试使用原 slot。
- 回执继续校验 Space／网络、完整配网身份、slot、当前参数、当前路由和运行任务所有权。沿用 TimedSchedulerTaskCoordinator 的接管／取消机制，不新增持久化 generation；迟到回执不能仅按地址和 slot 把新任务写成 synced。
- “删除完成”通过移除 binding 表示，不额外保存 removed；设备清理结果未确认时不能提前释放槽。

### 12.4 actionAddress 的意义与 LC 规则

建议形式：

```json
{"auto_on":"0301","off":"0300","recall":"0300"}
```

三个值均表示**配置该动作所用的 Scheduler Setup Server（1207）所在 Element 的单播地址**，不是 Group 地址、Scene Number，也不是触发时再由 App 发 On/Off 的目的地址。清理范围仍从 Composition 枚举全部 Scheduler Models，不能只遍历这个对象去重后的地址。

规范边界：Scheduler Index 为 0…15；Turn On 是 action=1，没有独立 Auto action。标准动作的影响范围还取决于后续 Scheduler Element 的布局，不能把配置目的 Element 理解为一定只控制单个 Element；LC OnOff 与 Generic OnOff 有状态绑定。来源：[Bluetooth Mesh Model 1.1，5.1.4.2、5.2.3、5.3.5～5.3.6、6.2.3.3](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)。以下是当前 App/SDK 具体选路策略，设备实际 LC 效果仍需运行验收。

| 有效业务归属／Composition | auto_on | off／recall |
| --- | --- | --- |
| 自动 Group，LC Element 同时有 Scheduler Setup Server | LC Element，例如 0301 | 普通 Scheduler Element，例如 0300 |
| 无 Group、Manual Control、退出组失败 | 普通 Scheduler Element | 普通 Scheduler Element |
| 自动 Group，没有可用 LC Scheduler | 回退普通 Scheduler Element | 普通 Scheduler Element |
| 只有一个可用 Scheduler | 复用唯一 Model，可能不在 Primary | 同左 |
| 没有 Scheduler／Composition 不足 | 不猜 Primary，不创建可发送 binding，旧数据保留并报告不可用 | 同左 |

因此用户的两类示例都可成立，但 0300/0301 不是固定偏移。有 130F 不保证同 Element 有 1207；普通 Owner 也不保证是 Primary。当前 SDK 的 lightLCSchedulerSetupModel 查 LC 同 Element 的 Scheduler；ordinarySchedulerSetupModel 优先非 LC，再按现有策略回退。

建议三项必填，均为 4 位大写 HEX 单播地址，属于同一节点且具有支持的 Scheduler Model；不使用 null、0000、缺字段表示“自动猜”。它表达当前 Group 语义下的有效路由，成员、Profile、Composition 变更时重算。只有当前 action 的实际路由／参数改变才使 synced 失效，避免未使用的 auto_on 地址变化导致 Off 定时重写。

路由本身仍有少量可推导重复；为便于执行方直接使用，本次按用户建议展开，不再新增节点路由字典及引用层。Profile 定时保持现有只读边界，不能因添加 recall 地址就认为 App 已支持执行 Profile。

### 12.5 共享 identity 只保留地址的前提

`identity.unicastAddress` 是引用**同一完整 Space 快照**中 nodes[].unicastAddress 的外键。导入时从该 node 的 UUID／Device Key 建立完整本地身份；之后本地 binding 和任务继续对 UUID＋地址＋指纹做匹配，不能每次发送才从当前 Nodes 临时补身份。

必须同时做到：

1. 先校验整份 Nodes、唯一身份／地址、Element 区间、Composition 和 bindings，再持久化。禁止把另一版本的 schedules 片段直接拼到当前 Nodes。导出压缩前也须确认本地 binding 的完整身份与同份 Nodes 一致；不一致时拒绝或走已有明确清理流程，不能只截取地址掩盖身份冲突。
2. 删除／重置／重配／云端替换节点时，在地址复用之前撤销旧任务、移除旧绑定及不能继承的直接目标。永久遗忘沿用现有删除记录，不标为物理清理成功。
3. 单节点更新也比较完整旧／新身份，实例变化时清除旧关系，不能只换 Nodes 后让旧 binding 指向新设备。
4. 外部写端同样必须保证 Nodes 与 bindings 属于同一次完整配置，不能部分合并。若无法满足，应退回保留实例身份的 JSON 结构再确认。

**无法恢复的信息**：如果外部已将旧绑定和新节点错误拼成地址相同的一份 JSON，新读端无法只凭该文件辨别历史归属。采用地址引用意味着依赖完整快照写入契约；不是无条件等价删除。本地复用已有完整 binding，不新增身份映射表。

### 12.6 删除三组待删引用，以当前目标和节点槽位完成收敛

用户要求删除 `needDeleteSceneNumbers`；前稿“必须在 Timed 保存旧 Scene 号”的结论收回。**对已经捕获完整槽位归属的任务，恢复当前期望配置不需要反推旧 Scene 号。** 仍需修改现有依赖旧引用的 Scene 入口，不能只删除字段。

| 删除字段 | 替代规则 |
| --- | --- |
| needDeleteNodeAddresses | 目标变化前捕获完整旧绑定；移出的节点保留 pendingRemoval，按其 slot 清理 |
| needDeleteGroupAddresses | Group 展开到真实成员；变化前冻结旧成员绑定，随后按节点写入／清理，不依赖 Group 继续存在 |
| needDeleteSceneNumbers | 新旧 Scene 共同节点沿原 slot pendingApply 写新 Scene；旧目标独有节点 pendingRemoval；新目标独有节点在容量确认后分配 slot 并 pendingApply |

例如 A 的目标是 N1/N2，B 的目标是 N2/N3：

- N2：沿用该定时原 slot，写 B，失败继续 pendingApply；没有必要保存 A 的号码。
- N1：不再属于新目标，保留原 slot 的 pendingRemoval，失败不能删 binding。
- N3：完成身份／容量校验后预约 slot，pendingApply 写 B。
- 写 B 前满足 B 的 Scene Store 等前置，先清非 Owner 同 slot，再向当前 Owner 写 B；成功覆盖的是 **Scheduler 条目中对 A 的 Recall**，不是删除 Scene A 本身。
- 更换 Scene 成功保存后，失败不将业务 sceneAddress 回滚到 A，继续以 B 为当前目标重试；若保存新业务本身失败，回滚整个配置提交。现有启停“全失败回滚 enabled”是另一条交互规则，不混为一谈。

**单独删除场景 A 的配套检查：**

现有 SceneDeletionTask.makeHandles 已经会按 slot 找当前业务 owner，用其当前 entry 替换旧 Recall；它不是一律清空。因此可以复用“以当前目标 B 接替”的路径。待修改的是 SceneDeletionCascade.prepare、SceneConfigurationStore.deletionReferenceNames、SceneServer.referenceNames 等对 needDeleteSceneNumbers 的依赖，以及检查范围。

建议复用现有 Scene deletionReferences／读回任务，不新增 Timed 历史字段：

1. 删除 A 时收集 A 的当前／待清成员、已知观察仍引用 A 的节点、所有存在未完成 Timed binding 的节点，以及 Scheduler 观察不完整的节点。去重后补入已有 Scene 删除读回任务；在无历史证据的新手机上，这可能覆盖 Space 中全部状态未知的 Scheduler 节点。
2. 读回各 Model 后，只处理真实残留 A 或明确归属本次删除的 slot。仍归属当前目标 B 的槽位走当前目标替换／必要 Scene Store 前置，不释放其 binding；不把整个 B 定时列为被删除的业务。
3. 只有当前 sceneAddress=A 的业务才进入 Scene 的待删 scheduleIDs；B 的节点仅作为检查／清残留对象。B 不能仅因曾用同一 slot 就被级联删除。
4. 逐节点确认不存在 A 残留后再完成该 Scene 清理记录；离线、读取失败、B 的必要前置失败保留原 Scene 删除任务重试。Scene 号在删除完成前仍由既有机制占用，防止旧 Recall 指向复用后的新场景。
5. Scene 清理 ACK 若也完成了 B 的当前配置，应按 Timed 的全 Model 条件重新确认其 binding；不能仅因某条 Scene 删除子任务成功就直接标 synced。

这些是已有删除任务的覆盖／生成规则调整，Scene deletionReferences 的字段、schema、generation 不变。成本是**实际删除 Scene 时**可能增加读回范围；普通 A→B 编辑不必为保留 A 历史增加持久字段或全网读取。

旧数据升级时，先消费旧三组数组并转换所有可确定的清理目标，再清空旧列。历史引用缺失到无法确定节点／slot 时，保留原始旧数据、提示读回或处理，不通过猜 slot 强行迁移。

#### 12.6.1 binding 是什么、存在哪里

这里的 binding 就是 `space.schedules[].nodeSlots[]` 中的**一个数组元素**，表示“业务定时 X 在节点 N 上预约 slot S，并处于什么任务状态”。没有额外的 `nodes[].binding` 表，也不是 Mesh 的 AppKey Model Bind 或设备配对。

同一个节点可以参与多条业务定时，各业务各有自己的 nodeSlots 项；同一节点的同一 slot 只能有一个业务 owner。查找定位用 Space＋schedule.id＋节点完整身份（共享 JSON 用地址引用）＋slot；执行和回执仍需核对当前配置／任务所有权。

例如以下**字段节选**表示定时 104 当前目标是场景 B：0300 的 slot=3 待写 B；0400 已移出目标，其旧 slot=5 待清理。完整 Space 还必须包含节点、场景、权限等，本节选不能直接上传。

```json
{
  "spaceData": {"timedSchemaVersion": 3},
  "schedules": [{
    "id": 104,
    "selectTarget": 2,
    "action": 2,
    "sceneAddress": "000B",
    "nodeSlots": [
      {
        "identity": {"unicastAddress": "0300"},
        "slot": 3,
        "state": "pendingApply",
        "actionAddress": {"auto_on": "0300", "off": "0300", "recall": "0300"}
      },
      {
        "identity": {"unicastAddress": "0400"},
        "slot": 5,
        "state": "pendingRemoval",
        "actionAddress": {"auto_on": "0400", "off": "0400", "recall": "0400"}
      }
    ]
  }]
}
```

0400 必须仍存在于这份完整 Space 的 nodes 中，才能继续访问该配网实例；若永久遗忘节点，走已有删除记录／身份清理流程。actionAddress 在 pendingRemoval 中不限制清理范围，仍清节点全部支持的 Scheduler Models 同 slot。

#### 12.6.2 服务器／网关怎么写入失败和成功结果

下面是外部执行方要实现的**契约建议**，不是声称现有服务器已经这样处理。App 只负责读写这套数据及自身执行，不修改外部实现。

**关键顺序：先持久化目标和 pending 状态，再下发。失败后通常保持原 pending 状态，并不是等失败才补建 binding。**

| 阶段／结果 | 写入共享 JSON 的方式 |
| --- | --- |
| 保存 A→B 新目标 | 同次配置提交写 sceneAddress=B，以及所有节点的新 pendingApply／pendingRemoval；取消旧任务或使旧任务结果失效 |
| 0300 新增／改 B 失败、超时、取消、部分 Model 成功 | 保留该项 slot=3、state=pendingApply，sceneAddress 仍为 B，不新分配 slot |
| 0300 已确认 Owner 为 B、非 Owner 同 slot 清理完成 | 只把该项 state 改为 synced，保留 identity／slot／actionAddress |
| 0400 删除失败或只有部分 Model 清理成功 | 保留该项 slot=5、state=pendingRemoval |
| 0400 全部 Model 同 slot 清理完成 | 从定时 104 的 nodeSlots 移除该项，释放 slot=5；不是改为 synced，也不删除 nodes 中的设备 |
| 定时已整体删除且所有 bindings 清理完成 | 移除整条业务定时；正常空目标业务仍保留，不与删除 tombstone 混淆 |

失败没有改变 state 时，可以不再发送一份完全相同的共享 JSON，但已持久化的 pending 意图必须存在；错误原因、重试次数、逐 Model 进度保留在执行方已有任务记录／App 本地观察中，不加入新公共字段。单节点成功仅更新该节点的 binding，不能把同一 schedule 的其他节点也标成功。

更新应在服务器内部基于最新完整 Space 合并结果并持久化；表中的“只改 state”是字段语义，不是新增 PATCH API。沿用已约定完整 Space 包装／更新机制，对外回读能看到结果。结果有变化时走现有 Space 变更版本／通知机制，保证 App 不因只变状态而漏读。

每个结果都必须匹配发出任务时的当前意图、节点实例、slot 和执行所有权。若用户已把 B 改成 C，迟到的 B 成功／失败都不能更新 C 的 binding。不能将旧完整 JSON 整份回写覆盖新配置，也不能仅靠秒级时间戳判断回执归属；执行方沿用其任务标识／串行替换和条件更新，不向 Space 新增未经确认的 generation。

进程崩溃或成功 ACK 后存储失败，保留 pending 即可恢复；重试前按需读回，已匹配则直接确认成功，避免重复下发。导入 JSON 不触发 Mesh，执行由后续同步任务负责。

### 12.7 对外 JSON 变更清单与示例（已确认）

路径从单个 Space 开始；Site 包装时前缀为 site.spaces[]，Space API 仍为 spaces[]。

| 完整路径 | v2 | 已确认 v3：类型、默认／可空、语义 |
| --- | --- | --- |
| `spaceData.timedSchemaVersion` | 2 | 必填整数 3；缺失只进入旧格式解析，不猜 v3 |
| `schedules[]` 及业务字段 | 当前定义 | 保留现有名称、业务含义 |
| `schedules[].nodeSlots` | 数组，缺失/null 可规范化为空 | 必填数组，可 []；v3 缺失/null 拒绝，旧兼容只在转换器执行 |
| `schedules[].nodeSlots[].identity` | 三属性对象 | 必填对象，只含 unicastAddress；本次不另做扁平化 |
| `schedules[].nodeSlots[].identity.unicastAddress` | Primary 地址字符串 | 保留，必填，4 位大写 HEX，0001…7FFF，引用唯一 node，无默认值 |
| `schedules[].nodeSlots[].identity.nodeUUID` | UUID | 从共享 v3 删除，本地完整身份保留 |
| `schedules[].nodeSlots[].identity.deviceKeyFingerprint` | 64 位指纹 | 从共享 v3 删除，本地保留；实际拼写是 Fingerprint |
| `schedules[].nodeSlots[].slot` | 整数 0…15 | 保留，必填；不接受 Bool、字符串或 null；同节点同 slot 全 Space 唯一 |
| `schedules[].nodeSlots[].state` | assigned／pendingRemoval | 必填字符串，12.3 三值，无缺省成功值；非法枚举拒绝 |
| `schedules[].nodeSlots[].actionAddress` | 无 | 新增必填对象，auto_on／off／recall 均必填有效地址字符串，无 null／默认猜值 |
| `schedules[].needDeleteNodeAddresses` | 地址数组 | 删除，清理职责交给完整 pendingRemoval bindings |
| `schedules[].needDeleteGroupAddresses` | Group 地址数组 | 删除，清理职责交给旧成员 bindings |
| `schedules[].needDeleteSceneNumbers` | 总是输出数组 | v3 删除，不用 []／null 占位；旧读取器只用于迁移，同 slot 新目标覆盖及旧节点清理由 bindings 承担 |
| `nodes[].schedules` | 兼容投影数组 | v3 不输出、不作为真实设备状态恢复来源；旧入口读取用于迁移 |
| `nodes[].custProps.schedulerModelStates` | 含逐 Model 及 legacy 原始字节 | v3 不输出；其余 custProps 保留，删除后空对象可省略 |
| 分享根 `formatVersion` | 2 | 3；format=sunSmartSpace、space 包装不变；云 API 不增加该包装 |

2026-11-07 按用户确认的容错方向调整：v3 接收端忽略上述已删除旧键，不解析其内容，不恢复为设备观察或清理任务，也不因键存在或类型不同而拒绝。nodeSlots、identity、actionAddress 内多余键同样忽略，当前必需字段仍严格验证；本地完整身份仍从实际 Nodes 展开。App 上传继续只输出当前 v3 字段，无需服务器先清理历史数据才能进入 Space。未列出的节点身份、网络 Key、Groups、Scenes、权限及其他 custProps／spaceData 保持原契约；不能删除其他模块的 generation。实施及验证见 [容错调整记录](../261107_1019_space_restore_v3_legacy_node_schedules_analysis.md)。

**变更前的 binding 节选**：UUID 和全零指纹仅作结构占位，不是可导入身份。

```json
{
  "identity": {
    "nodeUUID": "00000000-0000-4000-8000-000000000301",
    "unicastAddress": "0300",
    "deviceKeyFingerprint": "0000000000000000000000000000000000000000000000000000000000000000"
  },
  "slot": 3,
  "state": "assigned"
}
```

**变更后的 Timed 节选**：假设 0300 属于自动 Group，0301 同时有 LC 和 Scheduler。完整 Space 还须含真实 Nodes、Group、网络和权限；本段不能直接导入。

```json
{
  "spaceData": {"timedSchemaVersion": 3},
  "schedules": [{
    "id": 100,
    "name": "Morning Auto On",
    "enabled": true,
    "selectTarget": 1,
    "action": 1,
    "fadeTime": 5,
    "hour": 8,
    "minute": 0,
    "dayOfWeek": 31,
    "deviceAddresses": ["0300"],
    "groupAddresses": [],
    "sceneAddress": null,
    "profiles": [],
    "nodeSlots": [{
      "identity": {"unicastAddress": "0300"},
      "slot": 3,
      "state": "synced",
      "actionAddress": {"auto_on": "0301", "off": "0300", "recall": "0300"}
    }]
  }]
}
```

只有充分成功证据才输出 synced；新建／修改失败应为 pendingApply，不能机械把 assigned 变成 synced。无 LC／非自动 Group 的普通路由示例是 `{"auto_on":"0300","off":"0300","recall":"0300"}`，仍须核对 Composition。

**场景 A→B 尚未成功的最小节选**：

```json
{
  "id": 104,
  "selectTarget": 2,
  "action": 2,
  "sceneAddress": "000B",
  "nodeSlots": [{
    "identity": {"unicastAddress": "0300"},
    "slot": 3,
    "state": "pendingApply",
    "actionAddress": {"auto_on": "0300", "off": "0300", "recall": "0300"}
  }]
}
```

节点仍保留新目标，所以沿原 slot pendingApply 写入 B，不再记录 A。写入失败／结果不确定时保持该状态；完整确认成功后改为 synced。新旧 Scene 目标不同的节点分别按 12.6 处理。

体积估算：原示例 13 条业务、15 个 binding、4 个节点，紧凑 JSON 为 **14,159 bytes**。按建议删字段、补三路地址，并把非待删状态分别全部取 synced／pendingApply，结果 **7,860～7,938 bytes，减少约 44%**。这只是同一字段节选的形状估算，不是真实迁移结果，不含完整项目其他数据；地址和状态必须根据业务判定，不能将估算当转换器或网络性能证据。

### 12.8 数据库与本地恢复结构（已确认）

**无需新增表、列、索引，但已有 BLOB 内容、枚举及列的使用规则发生变化，仍属于必须确认的结构变更。** 本地保留完整 identity，需要分离存储模型与共享 DTO，避免复用 Codable 时把本地防护一起删掉；维护成本是两种编码边界及相应往返测试，复用现有 binding，不新建映射表。

| 表／持久路径 | 当前内容 | 建议变化 |
| --- | --- | --- |
| App `spaces.timedSchemaVersion` INTEGER | 1／2，SQL 默认 1 | 支持 3；旧默认保持 1，新建／成功转换由 App 显式写 3，不能批量改旧行 |
| App `schedules.nodeSlots` nullable BLOB | JSON 数组，完整 identity＋slot＋两状态；NULL 为旧 id=slot | v3 BLOB 保留完整 identity，增加三状态和 actionAddress；非 NULL 数组，可 [] |
| App `schedules.deviceDeleteAddresses` nullable BLOB | 待删直接地址数组 | 完整迁移 bindings 后，v3 行置 NULL，不再作工作队列；保留列供旧格式读取 |
| App `schedules.groupDeleteAddresses` nullable BLOB | 待删 Group 数组 | 同上；不做 DROP COLUMN |
| App `schedules.sceneDeleteAddresses` nullable BLOB | 待删 Scene 数组 | 旧记录转换完整 bindings 后，v3 行置 NULL；保留 SQL 列供旧格式迁移，不再作为 v3 工作队列 |
| SDK `nodePropertys.allSchedulerModelActions` nullable BLOB | 逐 Model 原始观察与未知状态 | 格式不变，继续本地持久化；v3 没有共享观察，不能初始化为已知空 |
| SDK `nodePropertys.schedulesData` nullable BLOB | 兼容缓存 | 格式不变，保留现有使用方；不从 v3 恢复，也不把期望写成真实观察 |
| `SpaceRecoveryState.timedConfigurationBaseline`、`submission.timedConfiguration` | Base64 Data，内部为规范化 Timed JSON | 支持带版本的 v3 内容，包含路由与状态；业务比较和回执比较分开，状态变化不能取消同一意图的在途任务 |
| `SpaceRecoveryState.schedulerModelStatesBaseline`、`submission.schedulerModelStates` | Base64 Data，内部为旧 Model 快照数组 | v1/v2 原义保留；新 v3 不再依赖该维度，版本明确后允许 nil／省略，不能伪造 [] 冒充旧观察 |

恢复文件仍为 `Library/Application Support/SpaceConfigurationRecovery/<scope-hash>.json`，修改已有字段使用规则，不另建恢复系统。旧 prepared/accepted 上传、pending import、删除记录等须先完成或明确恢复，不在中途强改回执版本；不含 Nodes 的历史比较回执不能从当前 Nodes 重建其旧身份。

典型数据库记录前后：

| 记录 | 迁移前 | 迁移后 |
| --- | --- | --- |
| 同一 spaces 行 | timedSchemaVersion=2 | timedSchemaVersion=3，其余身份不变 |
| 同一 schedules 行 | scheduleIndex=100；BLOB 内完整 identity、slot=3、assigned | scheduleIndex=100；同一完整 identity、slot=3，新增 actionAddress；state 依证据为 synced／pendingApply |
| 待删设备 | deviceDeleteAddresses=["0400"]，已找到其旧 slot=5 | deviceDeleteAddresses=NULL；binding 内完整身份、slot=5、pendingRemoval |
| 旧场景引用 | sceneAddress=B，sceneDeleteAddresses=["000A"] | sceneAddress=B，sceneDeleteAddresses=NULL；重叠节点沿 slot pendingApply，旧目标独有节点 pendingRemoval |
| v1 空值 | nodeSlots=NULL，业务 id 是旧物理 slot | 先建立真实绑定；合法无绑定为 []。失败保留旧行，不以空数组掩盖损坏 |

唯一约束 `(meshUUID, subNetworkKey, scheduleIndex)` 不变；scheduleIndex 仍是业务 ID。跨业务的 `(完整配网身份, slot)` 唯一性在配置提交／导入层校验，不增加索引。App／SDK 保存失败沿用现有导入 staging 和恢复，不能假设两个存储天然在同一 SQL 事务内。


### 12.9 完整行为链与单向迁移

| 入口／阶段 | 必须调整的行为 |
| --- | --- |
| Timed 新建／编辑／启停 | 先准备完整 bindings、路由、状态再保存；配置提交失败回滚，合法空目标保留；执行失败保留当前目标及 pending，启停全失败按既有 enabled 回滚规则另行处理 |
| Group 加入／退出／换组／Profile 变化 | 拓扑变化前捕获旧成员槽位；只同步实际目标／当前 Owner 改变的节点；重新加入可接管 pendingRemoval |
| Group Scene／Device Scene 变化／删除 | 同 slot 覆盖当前目标、旧节点按 binding 清理；Scene 删除改用 12.6 的覆盖及读回规则，不能只改 Timed 页面 |
| Node／Gateway 删除与地址复用 | 所有生命周期入口共同撤销旧身份绑定及任务，不能让新节点继承旧 slot |
| 下发／ACK | 更新真实本地观察后，按当前意图确认 binding；部分 ACK 不足以 synced，全部清理后才释放 |
| 重启／重载 | 完整本地身份、任务状态、有效缓存共同恢复；group.info.bindSchedules 等关联不能再依赖被删除数组 |
| 导出／上传／分享 | 同一版本化 DTO 覆盖 Space、Site、分享备份、Node 导出及 inactive Space，不只在一个出口过滤 |
| 完整 v3 导入／换手机 | 校验整份引用和路由，恢复业务与任务结果，不恢复整表观察、不发送 Mesh；首次操作按需读回 |
| 同机导入 | 只有身份、意图／路由和可信配置版本一致才复用本地观察；有远端执行变化时相关缓存失效 |
| 云端回读／恢复 | v3 的业务、bindings、状态、路由参与回读；移除强制共享 Model 快照的旧门槛，保留网络／身份／权限／完整性校验 |

导入的 synced 可表示写端最近确认结果，但不能用期望 entry 填满 allSchedulerModelEntrys，也不能证明其他未绑定 slot 为空。新分配仍需所有相关 Model 的真实占槽并集，未知／无业务归属条目保持占用，不自动覆盖。未变化且已成功的节点不重写；本地缓存有效时只补失败 Model。新手机会增加首次读取成本，离线仍可查看共享任务结果，无法证明安全的新分配／操作需等读回。本次不顺手放宽已有连接与编辑限制。

已选单向迁移的详细边界：

| 输入／客户端 | 建议行为 |
| --- | --- |
| v2，有完整身份／bindings／有效观察 | 先严格按旧规则校验，再依据观察生成三状态、补路由、写 v3；pendingRemoval 保留 |
| v2，无 Model 快照 | assigned 不能判成功；仍在目标的绑定为 pendingApply，必要读回后可直接确认 synced；待删绑定仍 pendingRemoval |
| v2，nodeSlots 缺失/null | 依旧兼容规则成未绑定，不用业务 id 猜 slot；已有物理条目但归属不明时保留占用并读回，不按相似参数擅自认领 |
| v1，id=slot | 只对已确认合法 v1 的 0…15 数据按旧目标／清理历史建立绑定，不能把 id≥16 的损坏 v2 降格为 v1 |
| 冲突 slot、损坏身份／BLOB／快照、旧目标丢失 | 保留原始完整数据，不清空、不强制升级；必要读回，仍无法确定则提示处理 |
| Profile | 保留业务及可确认的外部 bindings，继续只读；不能用普通 Scene 逻辑推断执行成功，证据不足为 pendingApply，App 不因此获得 Profile 下发权限 |
| 访客／只读／权限撤销 | 可读与解释，不能借升级取得编辑／云写权限；保留旧源用于受保护的兼容出口 |
| 旧 App 读取 v3 分享 | formatVersion=3 使支持版本校验的旧 App 拒绝；不能保证更早、无校验版本安全 |
| 旧 App 访问已迁移云 Space | 新 App 无法单方面禁止旧写端覆盖；需要服务器版本隔离／写入门槛，或明确仅支持新客户端，是外部发布依赖 |

迁移以每 Space 为单位：保留原始来源／已有恢复副本 → 旧版本解析 → 建立完整身份、bindings、路由、未完成清理 → 校验 → 持久化与重载核对 → 标记 v3 → 上传及回读。数据与版本转换应作为一次完整配置提交；失败保留旧格式，不能先写版本号。当前 v3 收到旧格式覆盖时走已有冲突处理，不自动倒退或补空绑定覆盖。

还须覆盖权限降级、密码变更、合法旧默认值以及云端修复与本地未上传变更冲突。历史记录仅用于提醒回归维度，不代表当前分支仍存在历史缺陷，本轮未复现这些问题。

### 12.10 实施阶段、源码入口及外部依赖

结构确认后再写可执行计划；以下为本次分析确定的实施范围，未执行：

1. **版本与存储边界**：v1/v2 读取、v3 DTO、本地完整 binding、三状态、失败可恢复的迁移。
2. **任务与清理链**：编辑、启停、拓扑、Scene、删除、重载和回执接管统一；替换三组待删数组生产依赖，实现 12.6 的同槽覆盖、旧节点清理和 Scene 删除覆盖规则。
3. **交换与回执**：所有导入导出、分享、Site、Node 更新和恢复路径按版本工作；不把“无快照”解释成“空表”。
4. **示例与验收**：实现后更新 v3 示例，保留 v2 作为迁移夹具；定向行为回归、真实持久化往返、代表品牌构建，外部验收分开记录。

| 范围 | 模型／读写／任务入口（相对本文件） |
| --- | --- |
| JSON、身份、槽位 | [Scheduler.swift](../../SunSmart/Main/Timed/Model/Scheduler.swift)、[TimedSchedulerSlotPolicy.swift](../../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift)、[TimedSchedulerBindings.swift](../../SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift) |
| SQLite | [Database.swift](../../SunSmart/Common/Data/Database.swift) 的 Schedule.initDatabase/load/save 与 SpaceData；SDK MeshDatabase 的 nodePropertys |
| 路由／结果／任务所有权 | [TimedSchedulerOwnerPolicy.swift](../../SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift)、[MeshNetwork+SunSmart.swift](../../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)、[Node+MessageHandles.swift](../../SunSmart/Common/Data/Node+MessageHandles.swift)、[TimedSchedulerTaskCoordinator.swift](../../SunSmart/Main/Timed/Model/TimedSchedulerTaskCoordinator.swift) |
| Timed 交互 | [ScheduleAddViewController.swift](../../SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift)、[ScheduleServer.swift](../../SunSmart/Main/Timed/Model/ScheduleServer.swift) |
| 拓扑、Scene、删除 | TimedSchedulerBindings.prepareTopology、[SceneDeletionCascade.swift](../../SunSmart/Main/Scene/Model/SceneDeletionCascade.swift)、[SceneConfigurationStore.swift](../../SunSmart/Main/Scene/Model/SceneConfigurationStore.swift)、[DevicePermanentDeletionCleanup.swift](../../SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift)、[GatewayDeletionContext.swift](../../SunSmart/Main/Device/Gateway/Model/GatewayDeletionContext.swift) |
| 交换与恢复 | [ExportData.swift](../../SunSmart/Common/Data/ExportData.swift)、[ImportData.swift](../../SunSmart/Common/Data/ImportData.swift)、[SpaceConfigurationIntegrityPolicy.swift](../../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift)、[SpaceConfigurationSafety.swift](../../SunSmart/Common/Data/SpaceConfigurationSafety.swift)、[DeviceScheduleAddressCleanup.swift](../../SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift) 中的 SpaceRecoveryState |

优先在 App DTO 层完成；SDK 的现有数据库格式可保留。如实施发现必须修改 SDK API／结构，应补说明，涉及新结构重新确认，并先核对共享 SDK 写入负责人。不会修改服务器／固件或部署。

| 责任方 | 必要配套及发布依赖 | 验收 |
| --- | --- | --- |
| App | v3 读写、单向迁移、任务与观察分离，共享逻辑影响五品牌 | 行为／持久化回归，代表 SunSmart generic iOS 构建；有资源、target、SDK 公共 API 风险再补受影响品牌 |
| 服务器团队 | v3 完整存储与回读；Nodes 与 bindings 一致；并发与旧客户端写入约束 | 往返保留状态／路由；旧写端不能破坏新版；HTTP 成功不等于 Mesh 成功 |
| 网关团队 | Composition 与 actionAddress 路由、当前意图的 ACK 归属、持久重试 | 部分成功、迟到、重启及全部 Model 清理；不能只用三个动作地址作为删除范围 |
| 固件团队 | 本方案不要求修改固件，核实已有 LC／On／停用／清理／Scene 行为 | 目标设备真实回读与触发，差异另交外部责任方 |

网关顺序沿用第 8 节：读回 → 预约 → 必要校时／Scene Store → 清非 Owner → 写 Owner → 保存结果；v3 改的是保存格式。配置按各节点实际 Scheduler Element **单播**，index 为该节点 slot；使用 ACK 并核对来源、index、全部 entry 和当前任务。删除遍历全部支持 1207 的 Elements，含 Primary，发默认清理 entry；超时先读回再决定重试，不新建 slot，不重写未变化且成功的节点。次数／间隔由网关执行方确定，本方案不猜测协议常量。

### 12.11 验证范围与已确认依据

按改动范围扩展已有检查，实际结果与夹具边界见第 13 节：

- `check_timed_device_slots.py`、`check_timed_slot_persistence.py`、`check_timed_task_replacement.py`、`check_timed_delete_result.py`、`check_timed_scheduler_single_owner.sh`。
- `check_scheduler_cloud_roundtrip.py`、`check_space_recovery_receipts.py`，以及 Scene 删除相关脚本。
- 至少覆盖真实 v3 编解码→SQLite 保存→重载，以及恢复回执持久化／重开，另有异步接管／迟到 ACK 行为验证；只测纯策略或源码文本不算保存／恢复完成。

行为覆盖：正常新增／停用／启用；空目标、未绑定、旧格式、损坏数据；部分成功、启停全失败回滚、取消、ACK 后保存失败；A→B→A 与迟到回复；Scene A→B 失败仍保留 B，重叠／旧独有／新独有节点分别执行；旧 A 删除不能误删当前 B；无本地观察时读回覆盖；同地址重配；16 槽、未知／孤立条目；Group／Scene 删除后重启重试。必要检查通过后停止扩展验证。

人工最短路径：双 Model 节点新增 Auto On → 一 Model 失败 → 退出重进后只补未完成部分 → 分享换手机导入 → 改 Scene 并模拟离线 → 删除且全部清空后才能复用槽。构建、离线验证、云端回读、Mesh 回执及真实定时触发分别记录。

本节保留结构决策与验收要求；第 13 节记录本轮实际实施和自动化证据。局部 JSON 片段缺少完整 Space 信息，不能直接导入；真实 Mesh、服务器联调与触发行为仍需人工验收。

**已经确认的方向**：单向迁移；保留当前 Group 路由规则；按本轮明确要求删除 needDeleteSceneNumbers。已将用户提出的取消 unknown 建议纳入三状态方案。

**已确认的实施依据**：修订后的 12.7 对外 JSON、12.8 本地内容变化，以及 12.6 的 Scene 删除覆盖和结果回写规则；三状态；仅共享 JSON 压缩身份；三组历史数组与两份节点 JSON 的完整移除范围；分享 formatVersion=3；完整快照与旧写端限制这一外部发布前提。本轮已按以上完整方案实施；没有新增表、公共字段、SDK 数据结构或新的服务端接口。


## 13. Timed v3 实施与验证记录

> 按 superpowers:executing-plans 在当前会话逐项实施；遵循项目要求，不启用子代理、不自动提交。执行记录保留在本节，任务状态不因上下文恢复而重置。

**Goal:** App 使用已确认的 v3 精简格式，保留可靠的节点槽位、三状态、重试和完整身份保护。

**Architecture:** 本地 TimedSchedulerNodeSlot 保留完整身份，外部 DTO 仅输出地址。版本化导入先校验完整 Nodes 再展开身份；状态和路由与业务配置一起持久化，真实逐 Model 观察继续由现有 SDK 缓存维护。现有 Space 导入事务、恢复回执与 Scene 删除任务负责失败恢复，不另建恢复系统。

**Tech Stack:** Swift／UIKit、现有 SQLite、NordicSigMeshSDK；Python 启动现有 Swift 行为夹具，xcodebuild generic iOS。

**Spec:** 本文第 12 节；用户已确认该结构及回写规则作为实施依据。

### Global Constraints

- 三状态为 pendingApply、synced、pendingRemoval；assigned 仅在旧数据读取兼容中出现。
- v3 删除三组 needDelete 数组、nodes[].schedules、custProps.schedulerModelStates；本地 SDK 观察不删除。
- 分享 formatVersion=3，Space timedSchemaVersion=3；保留旧格式单向迁移和失败原数据。
- 保留 Group 路由规则、Profile 只读、合法空目标、网络／节点身份和权限校验。
- 外部服务器／固件只更新契约，不实施；不改共享 SDK；不操作真机、不提交或清理其他工作。
- 使用当前已隔离工作树、SunSmartLocal.xcworkspace，SDK realpath 沿第 12 节；代表构建 SunSmart Debug generic iOS，独立 DerivedData。

### Review Focus

1. 地址相同但节点已重配：导出压缩前拒绝旧身份，导入完整快照建立身份，任务结果不得继承。
2. A→B→C 迟到回执及 ACK 后保存失败：只确认当前目标，保存失败保留 pending，可重启继续。
3. 删除 A 时实际 slot 已归 B：检查残留但不级联删除 B，离线检查保留 Scene 删除记录。
4. v3 缺字段／null／非法 state、slot 冲突、无本地观察：不能伪造空表、成功或容量。
5. 旧云回读、本地迁移及只读权限：不倒退 schema，不用升级绕过权限，不让回执比较阻断恢复。

### Task 1: 版本化 DTO 与真实编解码

**Files:** TimedSchedulerSlotPolicy.swift；Tests/Timed/TimedPayloadTests.swift、TimedDeviceSlotTests.swift。

**Interfaces:** TimedSchedulerActionAddress（Codable/Equatable）；TimedSchedulerNodeSlot.actionAddress；TimedSchedulerPayloadPolicy.decodingSchedules(_:) -> [[String: Any]]?、exportPayload(_:) -> [String: Any]?。canonical、normalizedComparison、backupEnvelope/Payload 继续是统一校验边界。

- [x] 扩展现有 fixture：合法 v3 的地址身份、三状态和路由经过 canonical/backup 往返；由 check_timed_device_slots.py 验证 v3 及旧兼容行为。
- [x] 实现严格 v3 输入校验、完整本地身份展开、共享输出精简；旧 assigned 仅用于旧入口。覆盖非法地址／Model、重复槽、旧键混入、缺字段/null、损坏类型及不支持版本。
- [x] v3 回执规范化无需 Nodes 也能校验其结构；真实导入仍必须完整 Nodes 校验。确认删除节点只删除对应地址引用，其他状态不变。
- [x] 运行 python3 scripts/check_timed_device_slots.py，预期所有旧回归及新增行为通过。

### Task 2: binding 状态、路由与 SQLite

**Files:** TimedSchedulerBindings.swift、Scheduler.swift、Database.swift、ScheduleServer.swift、ScheduleAddViewController.swift、MeshNetwork+SunSmart.swift、TimedSchedulerTaskCoordinator.swift；TimedSlotPersistenceTests.swift、TimedTaskReplacementTests.swift 及对应既有脚本。

**Interfaces:** Schedule.reconcileBinding(on:)、Node.timedActionAddress(contextGroup:)；现有 prepare/commit/reserveForSending/reserveForDeletion 统一产生完整本地 binding，业务 save 不写三组旧列。

- [x] 增加真实 SQLite 编解码/重载测试：pendingApply 保存及完整身份保留；失败不释放，成功确认，pendingRemoval 清空后释放；使用生产编解码与真实 SQLite。
- [x] 将路由、目标和当前设备参数比较纳入 prepare；仅实际需要同步节点进入 pendingApply。同槽换 Scene 不新增 slot；旧节点 pendingRemoval，合法空目标保留。
- [x] 保存参数及 bindings 后再发送；ACK 持久化三状态；结果状态变化不使当前同意图任务自我取消，改参数／删除／地址替换仍取消旧任务。
- [x] 迁移时完整消费旧目标清理数据，成功后旧三列 NULL；失败不升级版本。Profile 保持只读、无证据时 pendingApply。
- [x] 运行 check_timed_slot_persistence.py、check_timed_task_replacement.py、check_timed_delete_result.py；预期 SQLite、接管、删除及旧回归通过。

### Task 3: 所有交换出口与云端回执

**Files:** ExportData.swift、ImportData.swift、SpaceConfigurationSafety.swift、SpaceConfigurationIntegrityPolicy.swift、SpaceData.swift、DeviceScheduleAddressCleanup.swift；既有 cloud/receipt/import 测试。

**Interfaces:** 使用 Task 1 的共享 exportPayload 与 decodingSchedules；导入原始共享对象参与比较，本地完整对象参与保存。新 v3 不要求共享 Model 快照，旧回执继续按原版本验证。

- [x] 增加完整 JSON→解码→保存→重载→导出断言：v3 不重新长出旧键；空/缺/损坏严格区分；新机无观察时不构造整表空缓存。
- [x] 接通 active/inactive Space、Site、分享和 Node 出口；新 Space 显式 v3，旧 Space 成功转换后只写 v3；未完成旧上传／导入按原恢复流程处理。
- [x] 版本化回执比较：状态变化进入比较，旧 schema 不覆盖本地新 schema，节点身份与权限保护保留；完整 v3 导入后才能恢复短地址引用。
- [x] 运行 check_scheduler_cloud_roundtrip.py、check_space_recovery_receipts.py 和所触及导入回归，预期旧路径及 v3 路径通过。

### Task 4: 删除 Scene 与关联生命周期

**Files:** SceneDeletionCascade.swift、SceneConfigurationStore.swift、SceneServer.swift、SyncSceneScheduleTaskBuilder.swift、DevicePermanentDeletionCleanup.swift、GatewayDeletionContext.swift，以及 Group 关联读取入口；现有 Scene 删除行为测试。

**Interfaces:** 保持既有 Scene deletionReferences schema；扩大 prepare 的必要读回覆盖，以当前 Timed owner 和 slot 决定替换或清理。

- [x] 扩展 A→B 未完成、旧 A 删除保留 B、Scene Store 前置与迟到任务测试；复用已有删除持久化和恢复回归，明确 BLE 边界。
- [x] 删除 needDeleteSceneNumbers 的 v3 生产依赖；检查未完成 bindings／未知 Model 节点；只有当前目标为 A 的 schedule 加入待删 scheduleIDs。
- [x] 已归 B 的槽位按当前目标及 Scene Store 前置处理，不释放 B 绑定；读回／写入失败保留既有 Scene 删除记录。更新 Group 派生关联与节点永久删除／换身份入口。
- [x] 运行 check_scene_deletion_cascade.py、check_scene_deletion_flow.py 及相关 Timed/Group 回归，预期无错误释放和错误级联。

### Task 5: 集成验收与示例

**Files:** 本文、v3 示例、受影响 Tests/scripts；不修改 v2 历史示例。

- [x] 以最终实现生成 v3 合成示例并通过生产编码校验，覆盖 pendingApply、synced、pendingRemoval、空绑定和部分失败；记录外部发布依赖。
- [x] 自查完整调用链及 diff；覆盖 Review Focus 的行为测试，必要检查通过后停止扩大。
- [x] 运行受影响的定向回归及 git diff --check；在稳定代码上执行一次 SunSmart Debug generic iOS 构建，CODE_SIGNING_ALLOWED=NO，无 Simulator。
- [x] 更新本节结果、剩余外部／人工验收；交付未提交改动，不执行 commit/push。

### 执行记录

- 初始 HEAD：71dd7e0b67ff33c1a448dd16de08719c4c45ee69；实施开始时唯一未提交文件为本契约文档，原有内容已保留。
- 基线：check_timed_device_slots.py 通过（业务 ID/slot、旧格式、身份修复、容量和回执规范化）。
- 已验证当前为 linked worktree；已有 Pods 和 SunSmartLocal 映射可用。未创建新 worktree。
- Pre-flight：Task 2 消费 Task 1 的本地完整类型；Task 3 只在边界压缩／展开；Task 4 复用 Task 2 的 owner/slot 判断，不将旧 Scene 号重新加入 Timed。Task 3 的历史回执不得借当前 Nodes 重建旧身份。
- 执行方式：按用户项目规则由当前代理顺序实施、自查，不启用子代理；没有提交授权，不执行技能默认 commit 步骤。


### 13.1 最终实现

- 共享 v3 只有地址身份、物理 slot、三状态和三路 actionAddress；本地 SQLite 仍存完整配网身份。导出先核对完整身份，导入先验证完整 Nodes，复用地址不能接管旧任务。
- v3 不输出三组 needDelete 数组、nodes.schedules 或 schedulerModelStates；原 SQL 列保留，迁移完成后为空列。编辑 v3 时也不再临时生成旧清理数组；旧槽位全部由 binding 承接。
- 下发前持久化 pending；匹配当前任务的成功结果更新本节点，失败和存储失败保留 pending；真实读回匹配也可确认 synced。删除须全部相关 Model 清空，之后删除 binding。已匹配的 Owner 和已清空的非 Owner 不重复下发。
- Group Members SAVE 在成员关系回执已发布后准备 Timed 路由，与同次配置事务一起保存，避免动作地址沿用旧 Group。退出失败、Manual Control、无 Group 和无 LC 仍沿用普通路由。
- A→B 在原槽写 B。删除 A 时覆盖未完成 binding、未知观察及残留引用；若槽位当前归 B，先检查／补 B 的 Scene Store，再恢复 B，保留 B 的 binding。B 的参数或任务发生变化后旧结果无权回写。
- v3 云回执不再要求共享 Model 观察，磁盘上对应旧观察字段省略。内部比较使用版本标记表示“不包含该维度”，没有向公共 JSON 增加字段，也没有把未知 Model 伪造成空表。
- 普通节点和网关永久删除同步清理相应 binding，保留其他节点；SDK 仍保存真实观察，本轮未改 SDK 工作树。

### 13.2 单向迁移的实际入口与边界

1. 新建 Space 显式使用 v3。已有 Space 在正常配置预约／提交，或具备写权限、没有未完成上传、已有可信基线且 Mesh 空闲的完整导出入口转换；active 和 inactive Space 共用完整快照转换器。
2. 独立转换器先校验旧格式、身份与清理归属，再补路由并事务保存；它保守将旧 assigned 转为 pendingApply，不凭旧共享观察直接宣告成功。本地准备路径有完整当前观察时可直接确认 synced。
3. v1 使用原 id=slot 规则；独立转换器对支持 Scheduler 的节点保守保留该 index，非当前目标进入 pendingRemoval，以免丢失可能的旧残留。本地路径有可信完整观察时可省略已证实不存在的条目。
4. v2 缺失／null nodeSlots 仍按既有规则视为未绑定；但若同时有旧清理目标却没有可信 slot，转换拒绝。新增回归分别覆盖旧节点和仍属新目标的重叠节点，均保留原数组和原绑定，不猜新槽。
5. 只读、受保护或正在恢复旧回执的 Space 不借迁移获得写权限。无法安全转换的数据保留原源及原版本，由旧兼容出口保留；编辑／预约入口报告现有保存失败，不强制清空。转换成功后不再长期双写 v2。
6. 旧格式导入先沿原校验和持久化流程接收，再由上述可写入口转换；Profile 保持只读。服务器禁止旧客户端覆盖 v3 的版本门槛属于外部发布依赖，本轮未实施。

### 13.3 v3 示例说明

[space_timed_v3_demo.json](space_timed_v3_demo.json) 包含两条业务和三个节点：

| 记录 | 示例含义 |
| --- | --- |
| 定时 104 / 0300 / synced | 自动 Group 中支持 LC 的节点已完成，auto_on=0301，off/recall=0300 |
| 定时 104 / 0400 / pendingApply | 同组不支持 LC 的节点尚未完成，三路均为 0400；体现部分成功 |
| 定时 104 / 0500 / pendingRemoval | 已离开目标的旧节点保留 slot=3，全部 Model 清理后才删除该项 |
| 定时 105 / nodeSlots=[] | 合法空 Group，业务仍保留，没有猜测或预约物理槽位 |

示例由生产 exportPayload 生成，使用内存中的合成身份完成 canonical、formatVersion=3 包装往返、完整身份展开和再次导出等值校验，再移除全部 Device Key。公开文件是结构节选，缺少密钥及完整网络配置，**不能直接导入真实项目**；其中 synced 为说明状态含义的合成数据，不是设备执行证据。v2 历史示例未修改；两个示例规模不同，不用两者文件大小计算精简比例。

### 13.4 验证证据与限制

本轮沿现有脚本验证；涉及 SQLite 编译时使用独立临时 module cache，避免沙箱默认缓存不可写，不清理共享缓存。

| 自动化范围 | 结果与证据边界 |
| --- | --- |
| Timed 结构、槽位、迁移 | check_timed_device_slots.py 通过；含三状态、必填／null、冲突槽、路由、旧格式、地址复用与 Group/LC 规则 |
| 持久化与结果状态 | check_timed_slot_persistence.py 通过；生产 Schedule 编解码、SQLite 写入及新连接重载、完整身份、未知／部分成功／保存失败、删除释放和 NULL 旧列；BLE 由夹具提供 |
| 异步接管与删除 | check_timed_task_replacement.py、check_timed_delete_result.py、check_timed_scheduler_single_owner.sh 通过；匹配当前意图才接收结果，启停全失败回滚／部分成功保留 |
| 导入与云回执 | check_cloud_node_import.py、check_scheduler_cloud_roundtrip.py、check_space_recovery_receipts.py 均通过；v3 回执含磁盘重开、状态不匹配保留与重试确认；网络传输为离线夹具，未连接真实服务器 |
| Scene | check_scene_deletion_cascade.py：213 项断言通过；check_scene_deletion_flow.py 及 check_scene_configuration.py 的 targets（28 项）／save 通过；覆盖清理事务、重进／恢复、B 前置 Scene Store、部分失败及旧任务失效 |
| Group / 删除 | check_group_member_persistence.py、check_gateway_deletion_context.py、check_device_permanent_deletion_cleanup.sh 均通过 |
| 结构示例 | 生产 v3 编码与分享往返、身份展开、再次导出相等通过；公开示例移除合成密钥 |
| iOS 编译 | SunSmartLocal.xcworkspace / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO，最终增量构建退出 0；未运行 Simulator 或真机 |

第一轮编译发现导出器误用了文件私有 decoder，以及 SDK SchedulerRegistryEntry 不支持 Optional 的通用 Equatable 比较，均已改为可用 API 后通过。编译仍有现有依赖警告，未修改 SDK 或无关依赖。Scene 拓扑夹具更新为 v3 状态，同时保留实际 identity/slot、事务失败和重载断言；这类夹具不代替真实 Mesh 验收。

**仍待外部／人工验收**：服务器 v3 存取和回写、旧客户端写入门槛；网关按 actionAddress 和当前任务回写；真实多 Model 节点、分享换机、部分失败重试和真实触发。最短路径：双 Model 新建 Auto On → 模拟一个 Model 失败 → 重进后补失败部分 → 分享换手机导入并读回 → A 改 B 失败后删除 A，确认 B 保留 → 删除 Timed，全部清空后才复用槽。

只修改 App、测试和文档；共享逻辑覆盖五品牌，未新增资源／target 配置／SDK API，代表构建为 SunSmart。未提交、推送、部署或自动操作真机。

最终检查：上述定向回归均退出 0；最终 SunSmart 构建退出 0。v2 示例 SHA-256 仍为 `42da2c90260fef762e4d6f8a97d7c9f9b236fb806e3a7cd970fe6ea2f16f7575`；SDK 工作树无改动。`git diff --check` 在收尾时复核。
