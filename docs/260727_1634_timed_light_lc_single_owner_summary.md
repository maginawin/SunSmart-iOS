# Timed 双 Scheduler 按动作单 Owner 实施总结

## 1. 完成结果

已按最终确认方案实现：

| Action | 双 Scheduler Owner |
|---|---|
| Auto/On | Light LC Scheduler |
| Off | 普通 Scheduler |
| Scene Recall | 普通 Scheduler |

单 Scheduler 设备对全部 Action 使用唯一 Model。Target 为 Devices、Groups 或 Scenes 时采用相同规则。

## 2. 核心改动

### 2.1 Action Owner

本地 `NordicSigMeshSDK` 新增：

- 全部 Scheduler Setup Models；
- 普通 Scheduler 解析；
- 按 Action 选择 Owner；
- 按 Action 取得非 Owner Models。

App 和 SDK 公开 Set API 共用相同路由规则。

### 2.2 Set / Edit / Enable / Disable

每次写入固定执行：

1. 清理全部非 Owner 的同 index；
2. 向 Action Owner 写入目标 entry。

因此编辑 Action 会同步迁移物理 entry，不会在普通 Scheduler 与 Light LC Scheduler 同时保留有效的同 index。

### 2.3 Delete

删除不读取 Action，直接清理节点全部 Scheduler Setup Models。

App 只有在全部 Model 状态已知且同 index 均无效时，才完成本地待删除目标清理。Direct Devices 删除目标被提前清空的问题也已修复。

### 2.4 Model-aware 缓存

Scheduler 消息按来源 Model 更新 `allSchedulerModelEntrys`。兼容 `schedulerActions` 根据逻辑 Action 重建：

- 正常状态优先使用 App Schedule 的目标 Action；
- 删除态 `noAction` 使用设备 entry 的 Action，防止物理清理完成前过早隐藏残留。

`needsSync` 同时检查 Owner entry 与全部非 Owner；`needsDelete` 检查全部 Scheduler Models。

### 2.5 多 Model 读取与历史入口

SDK 读取遍历全部 Scheduler Models，并保持 Status/Action Get 的来源 Model。Timed、Group、Space、Restore 等普通照明日程入口已复用统一消息生成规则；Dongle collection Scheduler 保持独立。

## 3. TDD 证据

动作路由契约先改为新策略，旧实现出现预期 RED：

`Node must identify the ordinary Scheduler Setup model`

完成最小实现后：

`TimedSchedulerSingleOwnerContractTests passed`

## 4. 验证状态

- 聚焦契约测试：通过。
- App `git diff --check`：通过。
- 本地 SDK `git diff --check`：通过。
- generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 构建：

| Scheme | 结果 |
|---|---|
| SunSmart | BUILD SUCCEEDED |
| Archipelago | BUILD SUCCEEDED |
| SLG Sync Plus | BUILD SUCCEEDED |
| SylSmart | BUILD SUCCEEDED |

构建解析的 SDK 为本地 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。

## 5. 已存在日程的影响

- 不做一次性全网迁移。
- 正确位于目标 Owner 的既有日程不受影响。
- 错误 Model 或跨 Model 重复的 entry，会在编辑、启停、相关同步或恢复时清理并重写。
- 删除既有日程会清理全部 Scheduler Models。

## 6. 真机验收边界

当前没有固件真机执行证据，后续至少验证：

1. Group 与 Device 的 Auto/On 到点进入 AUTO；
2. Off 到点正确关灯；
3. Scene Recall 正确；
4. Auto/On 与 Off/Scene Recall 互相编辑后只保留一个物理 entry；
5. 删除后全部 Scheduler Model 同 index 均无效；
6. 16 条逻辑日程的物理有效 entry 总数为 16；
7. 单 Scheduler 旧设备行为不变；
8. 非 Owner 清理失败时保留同步失败并可重试。

## 7. 工作区说明

本次未执行 Git commit、merge 或 push。工作区原有 QR 扫码线程修复及其测试、文档未被覆盖或回退。
