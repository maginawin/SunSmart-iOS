# Site Trigger Zone 修复阶段关卡核对

日期：2026-09-14。依据 [已确认执行计划](260914_1748_site_trigger_zone_device_sync_repair_execution_plan.md)、[3A 实物关卡](260914_1813_site_trigger_zone_3a_hardware_gate_checklist.md) 和 [3B 只读进度](260914_1937_site_trigger_zone_3b_fingerprint_progress.md)。此文记录当前代码与验证边界，不改变计划顺序，也不授权设备写入。

| 阶段 | 当前可核实的成果 | 仍缺的完成证据 | 结论 |
| --- | --- | --- | --- |
| P0 状态与文案 | 非空 Zone 不再统一当作待同步；有保留成员变更时标明待办，旧/远端无可信回执时为未验证；来源仅增加的严格覆盖情形不制造设备任务；Site 级旧清理入口、云 Save 提示和中英文只读预览已实现。纯逻辑测试与五个品牌 Debug 构建通过，隔离真机曾验证单阻断及来源无差异弹窗。 | 最新双阻断长文案与所有 P0 页面情形尚未完整目视验收；隔离宿主已安装，最近启动被测试机锁屏拒绝。 | 代码纠偏基本落地，UI 验收未完成；不能声称 P0 全部验收。 |
| 3A 云与实物协议 | 测试 Site `Sep 11 site trigger zone` 已确认；云 GET/POST/GET 的版本、内容指纹与相等性有 Debug 诊断；标准 Config 可核对 Key 索引/Bind，Vendor Set/RET 与缓存证据边界已离线核对；被动触发、RET 和 Space 连接阶段日志已加入。 | 原始 Save 日志省略完整 GET body，不能独立证明那一次回读的全量内容；没有独立且可回退的两 Space 写入范围、旧 Group Path 现场基线、设备 Key/Bind/容量核验、目标 TTL、双向与断线/断电保持、故障回退。既有跨 Space 3 Zone 覆盖拟测成员，单次响应有来源歧义。用户要求暂缓本人配合的现场测试。 | **未通过**；保持真实设备发送关闭。 |
| 3B 完整目标与归属 | Site 全拓扑旧/新目标、共享来源、已删除 Zone 清理、Space 级 Primary 策略、目标/云指纹、传输候选与转发 Key 分离、具体阻断分类均已有只读实现。缓存观察及旧/新云差异均不能让暂定任务变为可执行；无差异来源用例、容量、权限、地址及 Key 身份等纯逻辑测试通过。 | TTL 仍未知；Vendor 邻居/转发 Key 没有独立 Get；当前节点观察仅是本机缓存。传输候选未经过实际会话与 Vendor Model Bind 核验。目标指纹在当前测试 Site 预期不可用，真实设备恢复计划尚无可信输入。 | **只读准备继续有效，不能放行发送**。 |
| 3C 账本与设备执行 | 尚无可发送的 Site 同步器；页面和 Debug Log 明确 `sender=disabled`。 | 3A 通过后才可决定单遍或两轮部署，再实现持久任务账本、显式会话、Key/Bind、Remove/Configuration、RET/必要读回、失败/STOP/恢复。 | 未开始。 |
| 3D 同步页面与 Save 接线 | 目前仅有按 Zone 及 Site 级的只读影响预览。 | 操作栏 Save 后自动进入可恢复的 Sync devices 页面、按 Space 执行、STOP/重试及全部 UI 真机验收。 | 未开始。 |
| 3E 防覆盖与发布 | 五个品牌 target 对当前只读改动曾通过 generic iPhoneOS Debug 构建。 | 普通 Group Path/Zone/Profile/Restore 写入口共同使用合并目标；防旧版覆盖、硬件故障回归、完整真机体验与人工验收。 | 未开始。 |

下一次可安全推进的分界：用户日后**自行**提供带时间点、Space/设备地址、连接阶段及现场灯具观察的日志后，先按 [协议证据矩阵](260914_2029_site_trigger_zone_3a_protocol_evidence_and_passive_logs.md) 判断 3A；若证据不足，保持“设备状态未验证”，不得以缓存、RET 或没有手机日志推断联动成功/失败。3A 的单遍部署与回退证据不足时，不能选择 3C 发送策略。当前无需用户立即操作设备，真实 Site 配置保持原样。
