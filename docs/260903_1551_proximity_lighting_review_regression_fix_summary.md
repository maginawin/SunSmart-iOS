# 邻近照明 Review 回归修复实施报告

## 1. 实施结论

Review 提出的 6 个 P1 运行时回归已按确认方案完成修复，并新增独立聚焦门禁。测试按 RED→GREEN 执行：新门禁在修复前首先因 Space 导入没有保留服务器存在性而失败，完成运行时修改后全部通过。

本轮没有修改 NordicSigMeshSDK、依赖、target 配置、本地化或资源，没有新增 Auth 信息，也没有改动 `SyncDevicesViewController` 的全局 callback 语义。

## 2. 修复内容

### 2.1 Space 刷新不再把导入拒绝当成服务端删除

- 新增 `SpaceImportResult`，分别携带服务器 Space ID、可应用的本地 Space 和 applied/skipped/rejected 结果。
- `SiteData.update` 使用全部可识别的服务器 Space ID 判断本地 Space 是否已从服务器移除，不再使用“成功导入的 Space 集合”代替服务器存在集合。
- 已知 ID 但拓扑预检失败的 Space 保留本地最后正确数据，也不会进入 `waitDeleted`。
- 任一服务器条目无法识别 ID 时，本次刷新保守跳过缺失 Space 删除判定，避免损坏快照导致误删。
- 文件导入入口已适配新结果，rejected 仍显示原有国际化失败提示。

### 2.2 Group 删除重试保留真实退组状态

- 删除了 `GroupServer.deleteGroup` 对整组原始 `groupState` 的恢复。
- 成功退出的 Node 保持 `none`，失败 Node 保持 `exitFailure`。
- `GroupViewController.deleteFailedCheck` 只把 `exitFailure` Node 传给 `outNodes`，避免已成功退出的设备重新生成订阅任务。
- Group 的最终本地移除仍保持在成员和邻近对端任务成功之后。

### 2.3 普通 Profile 与 Group 编辑恢复通用同步

- `GroupViewController` 保存 Profile 后，在回调返回前显式失效 Group 成员的通用同步缓存。
- `GroupAddViewController` 保存 GroupInfo/Profile 后同样失效通用同步缓存。
- 通用 Group 编辑现在同时检查 `group.needSync` 和邻近照明补充任务，不再用 `lifecycleResult.syncDatas` 代表整个 Group 是否已同步。
- 同步页仍使用 `.group` 生成完整 Group 任务，跨 Group 邻近任务继续作为 supplementary 数据追加。

### 2.4 删除后的邻居同步页恢复正确导航

- `DeviceProtocol.syncPermanentDeletionPeers` 与 `DeviceLightsViewController.syncDeletionPeersIfNeeded` 都增加了一次性结束闭包。
- 同步成功和用户返回均先确认并关闭当前 Sync Device(s) 页面，再执行原 completion。
- Device Others 保持列表刷新语义；DeviceBase/Gateway 保持各自原有的详情页关闭语义；批量删除即使传入空 completion 也能返回设备列表。
- 没有改变其他 Profile、Group Members、Restore、EFC 等同步入口的 callback 所有权。

## 3. 测试与构建证据

新增：

- `Tests/Group/ProximityLightingReviewRegressionContractTests.swift`
- 将新门禁接入 `scripts/check_path_topology_persistence.sh`

聚焦门禁最终结果：

- Path topology persistence contracts：PASS
- Proximity Lighting topology policy tests：PASS
- Proximity Lighting lifecycle policy tests：PASS
- Space Trigger Zone follow-up contracts：PASS
- Proximity Lighting lifecycle integration contracts：PASS
- Proximity Lighting review regression contracts：PASS
- `git diff --check`：PASS

Debug generic iPhoneOS、关闭签名构建结果：

- SunSmart：BUILD SUCCEEDED
- Archipelago：BUILD SUCCEEDED
- Lumineux：BUILD SUCCEEDED
- SylSmart：BUILD SUCCEEDED
- SLG Sync Plus：BUILD SUCCEEDED

构建继续解析远程 NordicSigMeshSDK `release` revision `86f5ec9`。日志中仅看到工程既有的 Info.plist、重复 Compile Sources 和 AppIntents metadata 类警告，本轮没有新增编译错误。

## 4. 尚未完成的真实验收

自动化和构建不能证明以下结果，发布前仍需人工或真机验证：

- 真实服务器返回无效或较新版本邻近拓扑时，editor/visitor Space 保留且真实缺失 Space 仍进入 `waitDeleted`。
- Group 多设备部分退组失败后，重试页只发送失败设备的 Unsubscribe，不向成功设备重新 Subscribe。
- 普通 Profile 字段修改在已有 `needSync == false` 缓存时仍立即进入同步，并由设备 ACK/回读确认新值。
- Device Others、DeviceBase、Gateway 和批量灯具删除在邻居任务成功、失败返回两种情况下的真实页面栈。
- 真实 BLE/Mesh 的邻近 Enabled、Relay Number、Neighbors 最终收敛与断连重试。

## 5. 工作树状态

所有修改保留在当前工作树，未 commit、未 push。计划文档与本实施报告均位于 `docs/`。

