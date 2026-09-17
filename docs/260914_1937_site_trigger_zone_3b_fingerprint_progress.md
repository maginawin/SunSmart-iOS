# Site Trigger Zone 3B 目标指纹与诊断进度

日期：2026-09-14。状态：只读 3B 实施中；用户已要求暂缓由其配合的真实设备测试，3A 实物协议关卡未通过，设备发送器和正式同步入口继续关闭。依据 [修复执行计划](260914_1748_site_trigger_zone_device_sync_repair_execution_plan.md) 和 [测试 Site 范围核对](260914_1926_site_trigger_zone_3a_test_site_scope.md)。

## 本轮已完成

- 给完整 Site 设备目标生成稳定 SHA-256 指纹。输入含 Site 身份以及所有目标节点的 Space、UUID、地址、Enable、Relay、完整邻居、转发 Key 类型与索引、TTL；排序后编码，避免 Dictionary/Space 遍历顺序改变结果。任务来源 Zone/Path 和已观察的 Key/Bind 准备状态不进入指纹：来源重叠或前置条件完成，不应变成新的设备目标。
- 拓扑不完整、目标转发 Key 或 TTL 未确定时，不生成设备目标指纹。当前测试 Site 的 TTL 仍需 3A 核实，因此 Debug Log 会明确打印 `targetFingerprint=unavailable`，不会把暂定任务伪装成可执行目标。
- 云 `extensionData` 另有独立的稳定内容指纹；Debug Log 的首次 GET、POST 目标、二次 GET 分别携带其值，并保留版本、操作 ID 与 `targetMatch`。云内容指纹仅帮助关联同一次 Save 的数据，不代表设备状态。
- 旧 Zone 横跨三个 Space，而拟新增的两 Space Zone 是其成员子集的特殊情况已补纯逻辑测试：来源增加但完整设备目标不变时不得制造设备任务。
- Group Path、Group Zone、Space Zone 和 Site Zone 的每条定向邻居关系现在保留独立来源。只读任务把**实际增删的边来源**与“同设备/同 Space 的共享来源”分开；删除 Zone 的旧边清理即使与现存 Zone 共用节点，仍归到 Site 级清理集合。Zone 的只读预览显示直接、共享、Site 级暂定任务数；当已删除 Zone 留有清理依据时，导航栏显示 Site 级只读入口。Debug Log 同时列出 `relationshipSources`。
- 设备目标指纹现包含已解析的 NetKey/AppKey 材料身份摘要；即使索引相同，Key 材料轮换也会改变目标身份。读取器拒绝 Key Refresh 中的状态和跨 Space 不一致的 Primary Key 对。摘要不包含原始 Key，不作为设备回执。
- 每个暂定 Space 任务现单独携带从该 Space 本机 Mesh 清单解析的 **Space AppKey 传输候选**；它与节点目标中的转发 Key 引用分开，既不参与设备目标指纹，也不把 `currentApplicationKey` 当作隐式授权。Debug `plan-space` 记录候选 NetKey/AppKey 索引与身份是否解析，`plan-task` 记录转发 Key 索引；不打印 Key 材料。缺候选时加 Key 阻断。传输候选仍须由 3A 对实际会话和设备 Vendor Model Bind 核实，不能用于发送。
- 只读预览产生 `[SiteZoneSync][cache-observation]`，逐节点列出缓存中的启用、Relay、邻居和 Primary Key/Bind 准备状态，明确标记 `evidence=cache ttl=unknown`。添加模式的 Mesh 监听记录 `[SiteZoneSync][trigger-observer]` 的启停与收到的触发源。Debug 构建另在真实页面可见、App 位于前台时开启 `[SiteZoneSync][passive-trigger]` 被动监听，记录实际收到的 Sensor presence 与 Vendor Proximity Trigger、Mesh 源/目标、嵌入的触发地址及当前 Space 连接上下文；进入预览、离开页面或退到后台即移除监听，并以会话标识丢弃迟到回调。该监听不发送命令、不改变触发行为；App/蓝牙断开或 Mesh 无接收时不会有事件日志，不能凭缺失日志证明设备未联动。
- 同一 Debug 页面现在用 `[SiteZoneSync][mesh-session]` 记录所选 Space 连接阶段变化，帮助把“监听启动”和“连接仍有效”区分开；这不读取可能生成 Key 的 AppKey getter，也不在 App 离开页面或后台期间声称持续观察。
- 预览把规划错误归为具体阻断类别：云目标/格式、权限、Mesh、Key、TTL、Primary 准备、邻居容量、地址、成员、Group/Space 拓扑、设备读回和保留的旧目标。无 Space 编辑权限时仍允许对已有完整缓存作只读预览，但明确阻断执行；缓存本身不可用时直接报告权限或 Mesh 清单原因。已确认的空 Zone 旧 schema 1 可继续预览；已确认但无法解析的成员不再被误报为“云端未确认”。中英文文案均已补齐。
- 对原日志中特别明显的“新两 Space Zone 只是既有跨三 Space Zone 的子集”增加无需读 Mesh 的严格证明：若**所有**保留成员变更都被一张未变动的现存 Zone 完整覆盖，且成员的 Space/Node、Group、主地址和设备地址一致，这些编辑只增加或删除关系来源，不改变设备目标。卡片和 Save 提示因此显示“设备状态未验证”，不再凭成员变化宣称“待同步”；只读弹窗解释这个差别。旧变更记录仍保留，不能把来源无差异当作设备已配置。覆盖 Zone 自身变化、部分覆盖、地址不一致、旧地址未解析或云目标未确认时均保持原待同步语义；完整规划和未来读回仍是最终依据。
- 旧/新云目标差异的每项暂定任务现在单独检查设备观察来源。缺失、重复、地址不符、字段缺失及**仅来自本机缓存**均加入 `observations` 阻断；即便以后有可信设备观察，仍保留独立的 `reconciliation` 阻断，要求按实际设备状态重新规划，不能直接把云目标差异当作发送清单。任务和目标指纹仍可用于只读分析，`Plan.isComplete` 不会因补上 TTL/Key 或缓存回显而变成真。纯逻辑测试覆盖精确缓存回显、完整可信观察、缺失、重复和地址不符。当前读取器只产生缓存观察，因此存在实际设备差异时预期仍被阻断；这不改变发送器关闭状态。

验证：`bash scripts/check_site_trigger_zones.sh`（新增权限、阻断分类及来源无差异的正反例）、独立的 `ProximityLightingTopologyPolicyTests`、两种语言的 `plutil -lint` 与 `git diff --check` 通过；含来源无差异状态与提示的最新源码对 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`、`Lumineux` 的直接 generic iPhoneOS Debug 构建通过。`MtestiPhone15` 上的生产控件布局探针与单一 Mesh 清单阻断弹窗，英文、简体中文均为 `PASS`。随后在同一隔离宿主注入两张有覆盖关系的假 Zone，通过生产 Header 打开真实只读预览；卡片设备状态为 `unknown`，弹窗显示“成员新增但没有新增设备目标”，中英文探针均为 `PASS`，人工检查截图中的正文和确定按钮均可见。证据暂存 `/tmp/site-zone-source-only-{en2,zh}.png`。被动监听尚无真实 Mesh 消息实测；多阻断并列及真实 Site 的新弹窗尚未验收。没有改动服务器或发送设备命令。

2026-09-14 后续验证：补上 `observations` 与 `reconciliation` 双重阻断后，Site Trigger Zone 纯逻辑脚本、英文及简体中文 `plutil -lint`、`git diff --check` 通过；上述五个品牌 target 的直接 generic iPhoneOS Debug 构建再次通过。新的双阻断文案尚未在真机上目视验收：`xcrun devicectl list devices` 本次返回 CoreDevice XPC connection invalidated，按 UI 验证规则不反复尝试，也不把编译成功宣称为布局通过。此前已验证的单阻断及来源无差异弹窗仍仅覆盖那些旧文案；待设备工具恢复时应在 `MtestiPhone15` 的隔离宿主查看新双阻断英文、中文弹窗的正文和按钮。

稍后 CoreDevice 清单恢复，`MtestiPhone15` 显示为已连接。已在 `/tmp/SiteZoneCandidateValidation` 的隔离宿主加双阻断文案布局探针，用当前源码签名构建并安装到该测试机；启动时系统明确返回 `RequestDenied: Locked`，因此没有取得新版弹窗截图或布局结果。此轮没有解锁设备，也没有触碰真实 Site 的 Mesh 配置。下次真机可启动时继续使用该隔离宿主，不需要在真实 Site 上重做 UI 验证。

传输/转发 Key 分离的只读候选及空 Key 身份阻断加入后，`bash scripts/check_site_trigger_zones.sh`、`git diff --check` 与 `SunSmart`、`SLG Sync Plus` 两个受影响入口的直接 generic iPhoneOS Debug 构建通过。该候选仍不证明 Vendor Model Bind、实际 `currentApplicationKey` 或跨 Space 会话；3A 未通过前不调用发送 API。

会话诊断进一步核对 SDK getter 时发现，直接读取 `currentNetworkKey` / `currentApplicationKey` 在空 Key 清单下可能生成并保存随机 Key。为保持只读页面安全，`SiteTriggerZoneMeshConnection.SDKTransport.context` 现在在读取当前 NetKey 前检查 Mesh NetKey 清单非空；被动日志没有新增实际 AppKey getter 调用。传输候选与实际会话的差异须在 3A/3C 以无副作用的方式核验，不能从目前的 Debug Log 推定相同。

上述空清单保护之后，Site Trigger Zone 纯逻辑脚本、`git diff --check`，以及 `SunSmart` 和 `SLG Sync Plus` 的直接 generic iPhoneOS Debug 构建通过。当前验证没有构造真实空 Key Mesh，也不把编译和纯逻辑通过当作该 SDK 边界的运行时验收。

增加 `[SiteZoneSync][mesh-session]` 连接阶段日志后，同一纯逻辑脚本、`git diff --check` 和两个入口的直接 generic iPhoneOS Debug 构建通过。该日志的真实断线顺序尚未在 Mesh 现场验证；手机离线期间没有可用的消息证据。

## 明确未完成的约束

- 指纹现在覆盖 Key 材料身份，但仍没有实物确认的 TTL、Vendor 邻居/转发 Key 读回或设备 ACK 账本。`[SiteZoneSync][plan]` 仍标明 `scope=site`、`deviceEvidence=unverified` 和 `sender=disabled`；`targetFingerprint=unavailable` 是当前预期结果。即使以后有可计算的目标指纹，它也不代表 `Plan.isComplete` 或设备已应用。3C 在复用账本或接受回执前仍必须重新核对云版本、显式会话和实际设备状态。
- Zone 和 Site 级入口目前只显示**暂定差异**及阻断/未验证状态，不能开启发送。隔离宿主已覆盖单一 Mesh 清单阻断弹窗的真实布局，但使用假 Site，未覆盖多阻断长文案、删除 Zone 后的 Site 级导航按钮及真实 Site 数据。项目规则禁止 Computer Use；这些仍需后续可用的自动化或人工目视核对，不能把单一弹窗截图当作完整 UI 验收。
- 当前用户不希望被要求配合现场操作。后续仅在用户自行测试并提供日志时分析实物行为；在 3A 关卡可验证之前，不开放真实设备写入。
