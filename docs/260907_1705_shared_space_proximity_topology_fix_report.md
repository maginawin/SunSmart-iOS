# 分享 Space 的 Path / Trigger Zone 丢失修复报告

日期：2026-09-07。工作树：`trigger-zone-sep`。基于用户确认的 P0/P1 范围实施；不提交 Git，不修改 SDK、依赖、品牌资源或本地化，不操作服务器数据。

## 1. 补充场景与修复结果

用户确认手机 B 的其他 Site/Space 中也存在 L1、L2。设备身份、设备地址、Group 地址都不能代替 Space/网络作用域；同一设备出现在其他项目，不应成为当前导入的成员依据。

原导入虽然传入目标 Nodes，却由 `group.nodes` 读取 SDK 当前全局网络。修复后，导入、生命周期、拓扑任务和导出校验都使用目标 Space 的完整 Groups/Nodes；同时验证网络 UUID、子网 ID 和快照完整性。SDK `Group.nodes` 的全局行为保持原样，当前修复在 App 层隔离这一依赖。

配置数量、顺序、空 Point 和跨 Path/Zone 的重复设备都保留。邻居相同的逻辑编辑仍保存并标记云同步，设备无需执行重复 Neighbor Set。

## 2. 实施内容

### 明确网络与成员来源

- 在 `GroupProximityLightingData.swift` 增加 `ProximityLightingTopologyContext`，按目标 Space 的网络 UUID + 子网 ID 获取当前或磁盘快照；离线加载时读取相同作用域的 GroupInfo。
- 成员从传入 Nodes 的 Model 订阅解析，并验证 Node/Group 网络身份；不通过当前全局 `group.nodes` 查询。
- 协调器保留目标 Network 强引用，避免 SDK 的 Group/Node 弱引用在离线上下文中失效。
- 检查输入是否覆盖该快照全部 Groups/真实 Nodes；读取失败、混入其他网络、Profile/拓扑加载异常时，禁止提交。
- Planner 增加不可用状态；Node 同步遇到不可用上下文时不生成任务。移除遗漏 Space Zone 的 Group-only 后备计算，防止不完整输入生成清空邻居或 Disable。
- `GroupInfo.load` 增加可选子网筛选；此次导出、拓扑加载和回滚调用明确传入，其他调用接口兼容。

### 导入保真与云同步副作用

- schema 1 预检交叉检查 Node.groupAddress、groupState 与 Model 订阅；legacy 导入也解析实际成员。
- 删除 Point/Zone 成员等破坏性 repair 计入导入异常；无害的 Zone 内重复成员去重可继续应用。
- 修正 Relay 缺省值为实际 Profile 默认值 2，避免普通非 Proximity Group 在新一致性检查中误报。
- 应用阶段将预检拓扑与实际 Groups/Nodes 生成的拓扑比较；提交后重新从数据库加载 Space、GroupInfo、Nodes，比较完整拓扑快照，包含参与拓扑的 Profile 资格、Relay、成员、Path/Zone 顺序与空位。
- 仅在上述验证通过后解除导入保护。正常服务器导入或无害规范化不推进本地云编辑时间戳；用户编辑、成员删除等明确操作仍标记待上传。
- 首次导入中无法验证的扩展数据保存为本机恢复目录内的 `unvalidated-import.json`，保持保护状态，不将其标记为已验证升级基线，也不在每次启动自动重放该异常扩展。
- 数值超界的 Path/Zone 地址在转换 UInt16 前拒绝，避免异常输入触发转换崩溃。

### 同源路径

- 非当前 Space 导出校验改用目标数据库中的 Nodes，不依赖页面当前打开的网络。
- 云脏标记与摘要刷新分离；摘要从目标 Space 的网络、日程和开关存储计算，避免覆盖为其他 Space 的数量。
- Space 进入时不自动执行破坏性历史拓扑清理；存在未验证数据时使用已有配置保护流程。
- 导入通知只保留 Space/网络身份，不保留导入时生成的旧 Node 任务。目标网络激活后，以最新 Space 配置重新生成任务，再使用现有同步页面。
- 没有修改 Path sequence 的任务名称或页面布局；原有 SAVE/显式设备同步交互保留。

## 3. 验证方法与结果

### 运行真实 App 适配层的回归

新增 `Tests/Group/ProximityLightingScopedImportTests.swift` 与 `scripts/check_proximity_scoped_import.py`，接入既有 `check_path_topology_persistence.sh`。

测试直接提取并编译仓库中的实际预检、Context、Planner、Coordinator 和 Node 任务生成方法，使用真实 SwiftyJSON 与拓扑算法；SDK 对象及数据库边界使用测试替身。它不是仅检查源码是否包含某个字符串，也没有复制业务算法。

覆盖：

- 当前网络为空、无设备主网、另一 Site、同 Site 的另一 Space、目标 Space。
- 不同 Site/Space 的 L1、L2 身份与地址相同，Group 地址同为 C000。
- 32 Path + 32 Group Zone + 32 Space Zone、空位和重复来源完整保留。
- 正常导入无云编辑、无多余设备任务，离线目标 Space 查询不访问 SDK 全局 Group.nodes。
- 混入其他网络节点、成员遗漏、声明与订阅冲突、悬空引用不得破坏性应用。
- legacy、普通 Profile、缺失或未知 schema、无害重复项规范化。
- 明确成员删除仍执行清理；邻居不变的 Path 逻辑编辑仍保存并标记云同步。
- 无完整 Space 上下文时不生成 Group-only 或 Disable 后备任务。

修复前的 HEAD 在同一测试适配框架中运行，首个跨上下文完整性断言失败；修复后通过。用户提供的 `owner_ok.json` 另行作为输入运行真实预检，通过；该私有快照未复制进仓库。

### 既有测试与数据库

- `bash scripts/check_path_topology_persistence.sh`：原 7 组 + 新增作用域执行测试通过。
- `bash scripts/check_configuration_database_safety.sh <当前锁定 SDK checkout>`：真实 SQLite WAL 快照、隔离、检查点失败、事务回滚、不可用连接、旧 NOT NULL Profile 表及完整 Profile 切换测试通过。输出的两条 NOT NULL 约束错误来自预期的失败注入。
- `git diff --check`：通过。

### iOS 构建

均直接使用 xcodebuild、Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO；没有使用 Simulator。使用 `-quiet` 控制重复编译日志，日志未通过 shell 重定向。

| Target | 结果 |
| --- | --- |
| SunSmart | 通过 |
| Archipelago | 通过 |
| Lumineux | 通过 |
| SylSmart | 通过 |
| SLG Sync Plus | 通过 |

构建存在工程既有的弃用 API、资源符号冲突及 Swift 并发等警告；本轮不扩大范围修复这些警告。

## 4. 仍需真实双手机验收

自动化验证执行了 App 的成员适配/预检/拓扑/任务逻辑，但 SDK 与存储边界测试替身不等同于完整 iOS 导入运行。SQLite 回归验证事务基础，也不替代真实 App 全字段导入与两端云同步。

建议验收流程：

1. A 使用修复版本配置并保存 32/32/32，服务器回读确认 Path 1、两个 Zone 2 的完整成员。
2. B 保留其他 Site/Space 的 L1、L2，先进入这些项目，再以 Editor 进入共享 Space 1；不执行 SAVE 或设备 Sync。
3. 确认三个页面保留全部条目与设备，Group 1 不出现额外 Path sequence，服务器逻辑配置与 A 保存结果一致。
4. B 退出并重启；A 再进入共享 Space；重复回读确认不发生隐式清空。
5. 再验证有意移除成员、清空 Zone、Profile 降级等合法编辑仍传播并产生正确设备任务。

本轮没有安装到手机、执行 BLE/Mesh、实时请求业务服务器或完成上述两端验收。

## 5. 已损坏数据的恢复边界

修复防止再次误清理，不会把现有空配置自动推测为损坏后恢复。schema 1 显式空列表可能来自合法用户编辑，设备邻居也无法反推所有 Path/Zone。

`owner_ok.json` 是本次明确的恢复依据。恢复仍需读取最新服务器数据、核对是否存在后续合法编辑，只恢复三类逻辑配置；不整体回滚 Mesh 数据库、密钥、地址资源或序列号。本轮尚未执行恢复。
