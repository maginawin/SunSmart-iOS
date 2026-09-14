# Site Trigger Zone 功能与验收状态总结

日期：2026-09-14。范围：当前 `site-tz-plus` 工作树及此前阶段记录。下列“已实现”指客户端源码已有相应能力，不等于真实设备联动或发布验收通过；近期修复仍为未提交的工作树改动。

## 已实现的客户端能力

1. **Zone 页面与云数据闭环**：Site 入口、最多 100 个 Zone 的批量创建、空 Zone 删除、跨 Space 成员卡片、权限与受限数据展示、选中行的 Save/Reset、草稿丢弃与过期保护均已有实现。成员使用稳定的 Site/Space/Node 身份和 v2 `extensionData`；未知字段保留，损坏或未知格式保持只读。按行 Save 只替换选中 Zone，同时向 `/sitespace/update/siteprops` 提交完整 `props.extensionData`，再用 GET 回读确认；本地 pending、服务器冲突、重启恢复和远端接管有保守处理。服务端缺少 CAS，因此并发客户端在 GET 与 POST 之间仍可能互相覆盖，不能把客户端基线比较当成原子保护。
2. **成员候选与添加交互**：按 Space、Group/Profile 和权限筛选合格 Proximity 设备；支持 Manual、Trigger 和 Quick Adding，触发消息可作为候选或加入草稿。点击候选后的 Attention Identify 是辨认设备的既有动作，**不是 Site Trigger Zone 配置同步**。切换 Zone/Space、断连、后台及过期回调有隔离；成员移除和 Reset 只更新当前草稿，Save 后才进入云端。
3. **P0 状态纠偏**：云保存、已知设备变更和设备状态未验证已分开呈现。非空 Zone 不再一律标为待同步；有保留成员差异时保留待办，历史/远端 Zone 无可信设备证据时显示未验证，空 Zone 无旧清理时不制造设备任务。严格证明新增 Zone 的关系已被未变动 Zone 完整覆盖时，仅增加来源、不制造设备目标差异。已删除 Zone 的旧清理依据留在 Site 级只读入口；Save 提示及中英文说明不再暗示设备已完成配置。P0 代码基本落地，但最新所有页面文案尚未完整真机目视验收。
4. **3B 只读目标与诊断**：合并 Group Path、Group/Space Trigger Zone 和 Site Trigger Zone 的旧/新全 Site 拓扑，按 Space 确定 Primary 转发策略，给每台设备形成唯一暂定目标；只读预览区分选中 Zone 的直接影响、共享设备或 Space 的影响、已删除 Zone 的 Site 级清理，并列出 Remove/Configuration 暂定任务及具体阻断。云内容、目标和 Key 材料使用不泄露 Key 值的身份摘要；传输 AppKey 候选与设备转发 Key 分离。本机缓存或云差异均不能充当设备回执，也不会开启发送。
5. **Debug 证据**：`[SiteZoneSync]` 日志覆盖云 GET/POST/GET 版本与指纹、草稿/Save 来源、只读计划与任务归属、缓存观察、页面前台收到的触发/RET 及 Space 连接阶段；日志明确标出 `deviceEvidence=unverified`、`sender=disabled`。手机或蓝牙断开时没有持续观测能力，缺少手机日志不能推断灯具是否联动。

## 尚未开发或未放行

| 顺序 | 待完成内容 | 当前结论 |
| --- | --- | --- |
| 3A 实物协议关卡 | 用独立、可回退的 Space 1/2 测试 Zone 核实完整云回读、原 Group Path 基线、Key/Bind/容量、Vendor 转发 Key 与 TTL、双向跨 Space 触发、App 断开和断电保持、部分失败与回退。现有跨 Space 3 Zone 覆盖部分拟测设备，单次响应无法证明来源。 | **未通过**；用户暂不配合现场操作，等待其日后自行测试并提供日志。 |
| 3B 可执行目标补全 | 实测确认 TTL、实际会话和 Vendor Model Bind，取得足以核对当前设备状态的可信证据；目前 Vendor 邻居/转发 Key 缺少独立 Get，节点观察只来自本机缓存，当前测试 Site 的可执行目标指纹预期不可用。 | 只读规划可用，发送仍被阻断。 |
| 3C 持久任务与发送 | 任务账本、逐 Space 显式会话、Key/Bind 前置、Remove/Configuration、ACK 与必要读回、版本隔离、失败重试/STOP/重启恢复。需在 3A 后决定单遍还是两轮部署。 | 未开发；没有 Site 设备同步器。 |
| 3D 同步页面与 Save 接线 | 操作栏 Save 云确认后自动进入并运行 `Sync devices`，按 Space 展示进度、阻断与重试；切换/退出弹窗 Save 保留后续入口。 | 未开发；现有同步图标仅打开**只读预览**，没有手动触发设备同步的按钮。 |
| 3E 防覆盖与发布 | 普通 Group Path、Group/Space Zone、Profile、Restore 等写入口共用合并目标，核对旧版客户端覆盖风险；非空 Delete/Test 设备语义、完整故障与 UI/硬件回归。 | 未开发，正式可发送入口未放行。 |

## 已验证与尚未验证

- `scripts/check_site_trigger_zones.sh` 的数据、候选、卡片和拓扑纯逻辑测试已通过；英文与简体中文 strings lint、`git diff --check` 已通过。五个品牌 target 在只读版本曾通过 generic iPhoneOS Debug 构建；最后一轮日志与只读保护改动又验证了 `SunSmart` 和 `SLG Sync Plus`。构建通过只证明代码可编译。
- `MtestiPhone15` 的隔离宿主曾验证候选/卡片布局、单一阻断及“仅来源增加”的中英文预览。最新双阻断长文案的宿主已安装，但启动被设备锁屏拒绝，因此该弹窗、Site 级删除清理入口和真实 Site 页面仍未完成目视验收。XCUITest 候选用例曾受 IDE 连接失败阻断，不算通过。
- 原始 Save 日志可证明 POST 返回业务成功；其后的 GET body 被省略，不能独立证明那次完整目标回读。真实 Mesh 设备的邻居配置、双向跨 Space 联动、脱离 App 运行与断电恢复均没有可接受的验收证据。`Sep 11 site trigger zone` 保持现状，当前不向用户要求立即进行现场测试。

**当前产品结论**：Zone 的编辑与云保存、状态纠偏及只读任务诊断已具备；“Save 后设备自动同步”及实际跨 Space 触发仍未交付。下一道放行关卡是 3A，后续按已确认的 P0 → 3A → 3B → 3C → 3D → 3E 顺序推进；在实物证据和端到端验收前，设备发送维持关闭。

依据：[阶段关卡核对](260914_2335_site_trigger_zone_stage_gate_audit.md)、[执行计划](260914_1748_site_trigger_zone_device_sync_repair_execution_plan.md)、[阶段 2 状态](260914_1208_site_trigger_zone_stage2_development_status.md)。
