# 邻近照明超限目标共享下发防护

## 问题结论

邻近照明拓扑计划能够识别超过 184 个邻居的设备，但此前仍会把完整目标交给统一差异决策。只有 Group 与 Space 两个编辑页面主动检查容量；设备恢复、设备加组和延迟同步等共享调用路径仍可能生成超限 Neighbor Set。

当前 App 锁定的 NordicSigMeshSDK 版本没有发送层容量兜底，因此 185 至 255 个邻居可能生成不可发送的分段消息，更多数据还存在整数转换崩溃风险。

## 修复方案

在 `ProximityLightingTopologyPolicy.mutation` 共享差异决策入口增加容量守卫。只要目标邻居数超过 184，就不生成任何同步 Mutation。

拓扑计划继续保留完整目标与 `CapacityViolation`，供编辑页面定位具体设备和显示国际化提示。超限目标不会被删除或替换成禁用目标，避免错误下发禁用、启用或 Relay 更新。

该入口由 `Node.getNodeSyncProximityLighting` 统一调用，因此覆盖页面保存、Device Restore、设备加组和延迟同步等现有任务构造路径。本次不修改 SDK 依赖版本，也不改变 Mesh 消息格式。

## 回归覆盖

- 最终合并结果为 185 个邻居时，仍记录容量违规，但不得生成同步 Mutation；
- 最终合并结果为 255 个邻居时，仍记录容量违规，也不得生成同步 Mutation；
- 184 个及以下邻居继续按原逻辑生成差异任务；
- 未知设备的禁用目标与正常 Relay、启用、邻居变更行为保持不变。

## 验收边界

自动化测试与通用真机构建只能确认 App 任务构造被阻断以及各 target 编译兼容。真实设备不再收到超限 Mesh 报文，仍需结合设备恢复、加组和延迟同步场景检查运行日志；SDK 发送层自身是否具备独立防护不属于本次改动范围。

## 自动化验证结果

- Path topology persistence contracts：通过；
- Proximity Lighting topology policy tests：通过；
- Space Trigger Zone follow-up contracts：通过；
- `git diff --check`：通过；
- SunSmart、Archipelago、Lumineux、SylSmart、SLG Sync Plus 的 Debug iphoneos 通用真机构建：通过。

构建只出现工程既有的资源符号重复、旧 API 和 AppIntents 元数据跳过等警告。本次尚未执行真实设备 Mesh 下发验收。
