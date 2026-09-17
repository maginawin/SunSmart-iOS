# Site Trigger Zone 云端接管与页面恢复实施记录

日期：2026-09-14。依据：同日的故障分析与已确认修复方案。

## 已实施

- `get/siteprops` 返回完整、合法的 Zone 数组时，若本地待上传目标无法与服务器对应，事务内归档原 `base/target/operationId`，停止旧目标上传，采用服务器版本。归档待查看标记跨重启保存，点击状态提示可核对本地与服务器 Zone 数；确认查看不会删除归档。旧响应时间戳不会覆盖较新版本；同一时间戳却有不同内容时暂停编辑和同步，等待更明确的版本。无效/不完整响应不覆盖已确认数据。没有编辑权限也可先接收服务器对象用于只读展示。
- 旧 `triggerElementAddress` 成员可按 `(spaceId,nodeUUID)` 展示。仅在当前 Node 的 Space、Group、主地址、元素范围及 Vendor Model 均核实时，才推导规范化 `deviceAddress` 供该 Zone 编辑与保存；未核实者保持只读。未编辑 Zone 的原始字段仍随完整 `extensionData` 保留。
- 页面按服务器 Zone 逐项显示，选中后保留 Test、Reset、Delete、Save 操作区，按权限与数据完整性逐按钮禁用。正式版 Test 目前无实现，继续禁用。页面草稿基线变化时标记为过期，不能用旧草稿覆盖云端。旧成员也计入设备所属关系，避免候选列表重复添加。
- 只读恢复规划器汇总所有 Space 的现有 Group Path/Trigger Zone 目标与服务器 Site Zones，逐 Node 对比本机缓存，生成移除、新增或更新任务预览。移除只包含终态不再需要的邻居；共享 Path 邻居保留。缓存、缺失 Node、未知转发 Key/TTL、地址不符及不完整拓扑均显式阻断真实执行。同步标记可查看各 Space 的预览计数，不发送设备命令。
- 将首帧表格重载推迟到容器有实际尺寸后，并且仅在已选中可编辑 Zone 时显示添加面板，以减少零尺寸布局阶段的约束冲突。

本次示例服务器对象含 **2 个 Site Zone**（一个含成员、一个为空）。若本地曾显示 3 个，云端接管后应显示服务器的 2 个；归档中的本地版本不会自动重新上传。

## 验证

- `scripts/check_site_trigger_zones.sh`：数据兼容、云端失配接管、同版本歧义、旧成员展示、任务分类与共享邻居等聚焦用例通过。
- 中英文本地化文件 `plutil -lint` 通过；`git diff --check` 通过。
- `SunSmart` 已进行签名 iPhoneOS 构建，安装至允许的 `MtestiPhone15` 并成功启动。`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`、`Lumineux` 的 generic iPhoneOS 构建通过。

## 尚未验收与后续

- Xcode 的 Computer Use 界面读取被自动审批拒绝，因此本轮无法目视核对真实 Site Zone 页面、操作栏、中英文长文案及约束日志。需在 `MtestiPhone15` 进入本示例 Site，确认服务器 2 张卡片、8 个旧成员、选中操作栏、空 Zone 与同步预览，并留意 `UIViewAlertForUnsatisfiableConstraints`。最终体验仍由人工确认。
- Node 字段仅是缓存；真实设备读回、协议 3A 实物过渡验证、逐任务持久回执、发送器及重试尚未交付。只读预览不得解释为设备已经同步，真实设备命令保持关闭。对于旧 Zone 被删除且 Node 不在当前拓扑的情况，预览会标为待核实，不会推断安全的清空命令。
