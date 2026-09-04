# Proximity Lighting Relay 按 Group Profile 归属实施记录

## 1. 实施结果

已按确认方案完成：

> Group Sequence、Group Trigger Zone、Space Trigger Zone 继续统一合并直接邻居关系；每台设备的 Relay 独立取自其唯一所属 Group 的当前 Profile，不要求跨 Group Space Trigger Zone 内的 Relay 相同。

本次没有为 Space Trigger Zone、Group Sequence 或 Group Trigger Zone 新增 Relay 字段，也没有修改云端 Schema。

## 2. 主要改动

### 2.1 统一拓扑策略

- 移除 `RelayConflict`、冲突列表及冲突查询接口。
- Planner 为每个有效 Group 成员直接使用该 Group Snapshot 的 Relay。
- 保留 Group Sequence、Group Trigger Zone、Space Trigger Zone 邻居关系的并集、去重和排序。
- 保留有效 Proximity Lighting Group 成员即使没有邻居也保持 Enabled 的语义。
- 保留未知或非有效 Group 目标的禁用差量语义。

### 2.2 Group Path 页面

- 移除查看未同步状态、重新同步和保存时的 Relay 冲突阻断。
- 页面继续通过统一 Planner 生成 Group 设备任务。
- 保存 Group Sequence/Group Trigger Zone 不会要求其他 Group Profile 使用相同 Relay。

### 2.3 Space Trigger Zone 页面

- 移除保存和添加设备时的 Relay 冲突阻断。
- 添加设备时直接使用 `node.group` 作为唯一 owner Group，并验证其属于当前 Space 的有效 Proximity Lighting Group。
- `SpaceTriggerZone.Item.groupAddress` 继续保留，用于归属校验与数据恢复，不保存 Relay 副本。
- 保存时继续只同步 old/new Space Zone 受影响设备，并使用包含全部 Group/Space 关系的统一计划。

### 2.4 节点差量与文案

- 节点差量计算不再跳过所谓 Relay 冲突设备。
- 删除不再使用的中英文 `proximity_lighting_relay_conflict` 文案。
- 本地化文件为共享资源，已检查所有品牌 Target 编译。

## 3. 自动化覆盖

已覆盖以下行为：

1. Group A Relay=1、Group B Relay=3 的设备可以加入同一个 Space Trigger Zone。
2. 跨 Group Space Zone 建立双向直接邻居，同时两端保留不同 Relay。
3. Group Profile Relay 变化只改变该 Group 设备的 Relay，不改变已合并邻居关系，也不修改其他 Group Relay。
4. Space Zone Item 的 Group 地址与设备真实归属不一致时，该成员不参与建边，也不能改变设备 owner Group Relay。
5. 32 个空 Space Zone 不改变 Group 拓扑、不产生受影响设备，也不禁用有效设备。
6. 相同边由多类拓扑产生时继续去重。
7. Relay 单独变化时继续只生成 Relay Set，不重写相同邻居表。

## 4. 验证结果

### 4.1 聚焦检查

- Path topology persistence contracts：PASS
- Proximity Lighting topology policy tests：PASS
- `git diff --check`：PASS
- English Localizable plist syntax：PASS
- Simplified Chinese Localizable plist syntax：PASS

测试脚本声明使用 Bash，并依赖 `BASH_SOURCE`；直接用 zsh 启动会在脚本入口失败，因此实际按脚本解释器使用 Bash 执行并通过。

### 4.2 Generic iPhoneOS 构建

以下命令均使用 Debug、generic iOS device、关闭签名构建，结果全部为 `BUILD SUCCEEDED`：

- SunSmart：PASS
- Archipelago：PASS
- Lumineux：PASS
- SylSmart：PASS
- SLG Sync Plus：PASS

Workspace 当前解析的 NordicSigMeshSDK 为远程 `release @ 86f5ec9`。本次未修改 SDK 源码或依赖版本。

构建仍会报告项目既有 warning，例如重复 Asset Symbol、旧扫描 API 和未使用局部变量；本次改动没有新增编译错误。

## 5. 尚待真实环境验收

自动化和构建不能证明真实设备传播行为。仍需至少验证：

1. 两个 Group 配置不同 Relay，建立跨 Group Space Trigger Zone。
2. 分别从两个 Group 的设备触发，确认传播范围按各自 Profile 生效。
3. 依次保存 Group Sequence、Group Trigger Zone、Space Trigger Zone，确认保存顺序不会改变 owner Group Relay 或擦除其他拓扑关系。
4. 修改一个 Group Profile 并同步，确认另一 Group Relay 不受影响。
5. 验证 Mesh ACK、设备实际灯光行为、设备重启后配置、App 缓存和服务器 Round Trip。
6. 验证旧版 App 参与编辑时的兼容边界。

邻居表容量保护及 Device Restore 对 Space Trigger Zone 地址迁移属于已有独立 P1，不包含在本次聚焦修改中。

## 6. 工作树说明

本次修改聚焦于统一 Planner、Group/Space 保存入口、双语未使用文案和相关测试。未提交 Git commit。

工作树中原有未跟踪文档 `docs/260902_1700_space_trigger_zone_compatibility_review.md` 未被修改；其 Relay 冲突描述对应本次优化前的 HEAD，应以本实施记录和 `docs/260902_1704_proximity_relay_group_profile_optimization_plan.md` 的新规则为准。
