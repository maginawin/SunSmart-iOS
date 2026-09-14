# Site Trigger Zone 3A 测试 Site 范围与旧 Zone 重叠处置

日期：2026-09-14。状态：已确认现场 Site 和观察人员；只读盘点完成，尚未改动云端 Zone、Group Path 或设备配置。对应 [执行计划](260914_1748_site_trigger_zone_device_sync_repair_execution_plan.md) 的 3A；3B 只读规划可并行，3C 设备发送和正式入口仍待实物关卡通过。

后续现场反馈：用户已尝试触发，但在 iPhone 上没有可判断的变化，明确要求**暂不安排本人继续配合真实设备测试**；先补 Debug Log，之后由用户自行测试并在有问题时提供日志。因此下述物理步骤和旧 Zone 临时调整方案均暂缓，不能将这次观察判作跨 Space 成功或失败。当前应用没有 Site 设备发送器，iPhone 没有反应也不能据此判断设备端状态。

## 已确认范围

- 用户确认 `Sep 11 site trigger zone` 是真实可测试 Site，且本人可以观察。Site ID 为 `A9E138AC-E52E-4ABA-A01E-21EECDB0B725`。
- 当前云端 `get/siteprops` 业务码 200，`extensionData` 为 schema 2、5 个 Zone，时间戳 `1789378325`；与本机保存的云基线一致。本次只是 GET，没有 POST 或设备写入。
- Space 1（`78241517-4E06-4643-9B2C-CA20A72DA4A9`）有 L1/L2/L3，Mesh 地址 2/5/11，均为 PID 2502、VID 0003。Space 2（`14E57708-AAB5-48E1-8B73-D76ECC2BC386`）有 L1/L2/L3，地址 14/17/20，前两台 PID 2502、第三台 PID 1502，均为 VID 0003。这些型号、地址来自本机缓存，不等于现场设备读回。
- 既有第 1 个 Zone（`987F85AC-F078-450D-986A-88D25EB7AF49`）包含 Space 1 的 2/5/11、Space 2 的 14/17/20、Space 3 的 32/38。其余四个 Zone 只包含 Space 1 设备。Space 1/2 的 Group Path 持久化记录均为空。

## 新发现的测试前置阻断

仅向此 Site 增加一个成员来自 Space 1/2 的新 Zone，不能单独验证设备目标变化：两边全部六台设备已共同属于跨 Space 3 的旧 Zone，旧 Zone 的完整邻居图已经包含两边任意两台之间的关系。重叠 Zone 只增加来源，不增加新邻居；只读规划测试已覆盖这种“来源新增而设备写入数为零”的情形。若看到跨 Space 联动，也不能归因于新 Zone；若没有联动，仅靠新 Zone 的成员差异同样不能推导出具体设备任务。

当前实现另对这种完整子集做保守的快速证明：覆盖 Zone 未被改动且成员地址完全一致时，Save 提示与卡片从“成员变更待同步”改为“设备状态未验证”，但保留原变更记录。这个证明不读取设备，不能据此判断旧跨 Space 关系是否已安装。

因此 3A 先做**不改配置的物理基线观察**：分别触发 Space 1 的 L1（地址 2）和 Space 2 的 L1（地址 14），记录 Space 1/2、若可见也包括 Space 3 的响应；断开 App/蓝牙后再重复。若旧 Zone 已经在设备上生效、Space 3 会受影响，先停下并重新圈定可写设备，不能宣称只在 Space 1/2 测试。

## 待基线观察确认后的受控方案

1. 在任何云写入前，再次 GET 并保存可精确恢复的完整 `extensionData` 和版本；保存两 Space 的 Group/Profile/Path 目标、节点身份、型号及当前现场行为。备份仅用于本次回退，不将 Mesh Key 值或 Auth 信息写入文档。
2. 如果旧跨 Space 3 联动尚未在设备上生效，且现场允许临时调整此测试 Site：先将旧第 1 个 Zone 的 Space 1/2 六名成员移出，保留 Space 3 两名；GET 确认。随后新建一个只含 Space 1/2 选定设备的测试 Zone，再 GET 确认。四个 Space 1 旧 Zone 原样保留。这个云端暂态操作**需要用户对调整旧 Zone 范围作明确确认**，当前尚未执行。
3. 为两 Space 各建立一条可恢复的 Group Path 行为基线；先验证原 Space Key 下的触发、App 断开及恢复，再以显式 Primary Key/Bind、转发 Key、TTL 和完整邻居目标逐节点试验。旧 Group Path 在每轮操作后都重测；故障或中断时记录已成功、失败和未知节点。
4. 双向触发、App 断开、断电恢复都通过后，按保存的旧 Path/Space 目标恢复设备行为，并恢复云端旧第 1 个 Zone；再次 GET 验证云对象精确一致。已安装的 Primary Key 按既定策略保留，不能把保留 Key 误写成完整设备回滚。若设备缺少邻居/转发 Key/TTL 的 Get，需由命令回执加现场行为共同验收，回退后设备状态仍需标出不能读回的部分。

若基线观察表明旧跨 Space 3 关系已经生效，或无法证明 Group Path 可恢复，则不要执行第 2～4 步；需扩大现场可写/可观察范围或换一个真正隔离的 Site，再确定方案。

## 只读实现进展

3B 已把 Space/Primary Key 索引和目标 TTL 从隐式常量改成显式目标字段。目标 TTL 在实物验证前为未知，阻断正式执行，但允许显示带原因的暂定只读差异。旧成员若是没有 `deviceAddress` 的兼容格式，先按当前 Node 清单规范化，再用于前后目标及 Space 排序；不会误判为“旧成员无效”。`bash scripts/check_site_trigger_zones.sh` 通过；`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`、`Lumineux` 的 generic iPhoneOS Debug 直接构建通过。设备发送器未接线，也未因此宣称真机布局或现场联动验收通过。

## 用户自行测试时的 Debug 证据

Debug 构建在 Zone Save 路径输出 `[SiteZoneSync][save]`、`[draft]`、`[cloud]`：记录入口来源、旧/新成员数、操作 ID、首次 GET 版本、POST 接受、二次 GET 的完整目标匹配、最终成功/失败。保存成功后或点击某 Zone 状态入口，输出 `[preview]`、`[plan]`、`[plan-attribution]`、`[plan-space]`、`[plan-task]`、`[cache-observation]`：记录该 Zone 已知成员差异、完整 Site 只读目标的暂定任务、按 Space 的 Remove/Configuration、目标转发 Key 索引、TTL、邻居、来源、缓存状态及阻断原因。添加模式的 `[trigger-observer]` 记录其监听启停和收到的触发源；页面可见且 App 在前台时，新增的 `[passive-trigger]` 被动记录当前 Mesh 实际收到的 Presence/Vendor Trigger 及上下文，不发送命令。App/蓝牙断开或 Mesh 没收到消息时不会有手机事件日志；缺失日志不能证明设备未联动。日志明确标记 `deviceEvidence=unverified sender=disabled`；它不表示已向设备发送配置或收到配置 ACK。

日志不输出 Mesh Key 值、Auth 信息或完整云响应。用户以后若手动复现，可提供同一次操作的 `[SiteZoneSync]` 行及相邻 HTTP 响应状态，并用文字说明现场设备行为；当前无需再做触发、断开 App 或断电操作。正式设备发送器和 ACK/读回日志只有在 3A 协议关卡通过后才会接入。
