# Site Trigger Zone 阶段 2 开发与验证记录

日期：2026-09-14。状态：**客户端实现已形成可评审增量；阶段 2 尚未达到发布验收门槛**。本记录依据已确认的 [阶段 2 方案](260914_1125_site_trigger_zone_stage2_plan.md)。

## 本次实现

- 2A：定义 v2 成员身份与 Group/主地址/规范化 `deviceAddress` 字段，保留未知 JSON 字段；损坏、重复或未知 schema 保持只读。`deviceAddress` 沿用 Space Trigger Zone：优先使用 Sunricher Vendor Model 所在元素地址，否则使用主地址；触发源地址仅用于解析 Node，Manual 加入也走同一规则。页面草稿只在当前控制器内保存，切 Space 保留；非空 Zone 按 Space 显示成员，可移除，Reset 只恢复已保存成员。非空 Zone 的 Delete、Test 和设备 Sync 仍禁用，空 Zone Delete 保持可用。
- 2B：从只读 App/Mesh 数据库建立当前 Space 的合格 Proximity 设备及元素地址映射。Quick Adding 接受 Presence=true 与 vendor proximity trigger 后自动加入草稿；Trigger 仅列候选；Trigger/Manual 首次点击选中、再次点击加入。加入后仅在目标 Space 仍连接时 Identify。切模式、Space、Zone、后台与断连均停止旧目标侦测；Quick Retry 后需要再次 Start。退出或切 Zone 的脏草稿弹出 Save / Discard / Cancel。
- 2C：Save 把页面草稿写入本地持久化 pending，重新读取服务器 Site、旧/新成员 Space 的有效编辑权限及当前设备 Group/Profile/地址；仅替换选中 Zone 的成员，并通过 GET 回读确认云端结果。确认后保留前后成员快照供阶段 3 设备清理使用。仅云保存成功时显示设备待同步；未保存草稿和空 Zone 保存不冒充设备同步完成。

接口补充：用户确认 `/sitespace/update/siteprops` 的 `props.extensionData` 必须是**完整对象**。当前请求使用 `pending.target.jsonObject()`；选中 Zone 的 Save 从最新服务端 `extensionData` 复制顶层未知字段和其他 Zone，仅替换目标 Zone，首次保存非空成员时将 `schemaVersion` 升至 2，再把完整对象放入 `props.extensionData`。按后续反馈，该接口似乎不需要客户端提供 `updateTimestamp`，服务器自行生成更新时间且调用均接受；现已从 Trigger Zone 更新请求移除该字段，并改为以完整对象 GET 回读确认。新增契约测试核对了全量字段保留、其他 Zone 保留、schema 升级、请求字段与服务器时间回读。回读确认路径直接记录设备待同步的前后成员快照，以覆盖其他页面先回读或进程中断后的恢复场景。

## 已完成验证

- `scripts/check_site_trigger_zones.sh` 通过，包括成员 schema/草稿/重启恢复、跨 Space 候选、权限变动、失效 Profile 与 Group 快照校验。中英文 strings lint、`git diff --check` 通过。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`、`Lumineux` 五个 Debug iPhoneOS generic 构建通过；`SunSmart` Release iPhoneOS generic 构建通过。Release 输出有工程其他模块原有弃用/未使用变量警告，无本次改动的构建错误。
- 在允许的 `MtestiPhone15` 上安装隔离 UIKit 验证应用；英文、简体中文的阶段 2 布局探针均为 `PASS`。覆盖 320/393/768pt、非空多 Space 成员、Quick 控件、Trigger/Manual 候选操作、连接状态遮挡和 Trigger 列表裁切。截图仅用于布局自查，最终体验仍需人工确认。

## 已接受风险与待验收项

1. **并发覆盖风险已接受。** 按用户当前反馈，`sitePropsUpdate` 似乎不要求客户端提供 `updateTimestamp`，由服务器自行更新时间，更新调用都会接受。客户端的提交前 GET、基线比较和提交后 GET 回读不能阻止另一端在 GET 与 POST 之间写入并被完整对象覆盖。用户决定本阶段暂不要求后端 CAS，改由实际使用中的工程规范降低风险。建议规范明确同一 Site 的 Trigger Zone 配置由一人串行编辑，编辑前刷新；保存及回读结束前其他客户端不修改同一 Site 的 `extensionData`。这属于建议的操作约束，不是技术上的并发保护；后端 CAS 不再是阶段 2 发布门槛。
2. **真实环境联调仍待完成。** 未对真实 Site 云数据执行全量写入与回读验收；未用合格 Proximity Mesh 设备验证两种消息、Identify、断连/Retry 和跨 Space 快速切换。隔离 UIKit 探针不能替代这些验证。

真实环境联调完成后，再按 [阶段 2 方案](260914_1125_site_trigger_zone_stage2_plan.md) 的 2A→2B→2C 验收口径宣布阶段 2 完成。工作区原有 `AGENTS.md` 修改未处理；本次未修改 SDK、未发送设备配置命令，也未改动认证数据。
