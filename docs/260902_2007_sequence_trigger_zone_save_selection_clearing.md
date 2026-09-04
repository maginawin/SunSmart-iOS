# Sequence / Trigger Zone SAVE 立即清除选中行

## 问题结论

以下页面点击 `SAVE` 后，原选中行的状态对象虽然会被立即置空，但原 section 没有同步刷新：

- `Group > Path > Sequence`
- `Group > Path > Trigger Zone`
- `Space > More > Trigger Zone`

保存流程随后进入容量校验或设备同步页面。如果校验或同步失败并返回，旧行仍保留选中样式；此时内部选中状态已经是空，再选择其他行时无法找到并刷新旧行，最终表现为允许多行同时处于选中样式。

## 修复方案

保留三个页面现有的 `SAVE` 调用时机，让 `stopSetPath()` / `stopSetZone()` 复用各自完整的取消选中逻辑：

1. 获取当前选中对象及其 section。
2. 清空选中状态。
3. 立即刷新原选中 section，移除行和 header 的选中样式。
4. 更新底部设备添加区域，使其恢复未选中状态。
5. 之后才继续容量校验、数据持久化和设备同步。

Space Trigger Zone 的页面消失清理也复用同一入口，避免存在两套不同的取消选中实现。

## 保持不变的行为

- 不改变 Sequence、Trigger Zone 的编辑数据和保存内容。
- 不改变容量校验、Cloud Dirty、持久化、设备同步与失败重试流程。
- 不改变 Group Path 的返回行为。
- 保留工作区原有的 Space Trigger Zone 保存成功后关闭模态导航容器改动。
- 不修改本地化、资源、Target 配置、依赖或 NordicSigMeshSDK。

## 回归覆盖

新增 `PathSaveSelectionClearingContractTests`，覆盖：

- Group `SAVE` 在容量校验和设备同步之前触发 Sequence 与 Trigger Zone 清理。
- Space Trigger Zone `SAVE` 在数据清洗、容量校验和设备同步之前触发清理。
- 三个页面都通过完整取消选中路径清空状态、刷新原 section 并更新设备添加区域。

该契约先在旧实现上得到预期失败，再在修复后通过。既有 Path topology persistence、Space Trigger Zone follow-up 和 Device Add View 合同测试也继续通过。

已完成验证：

- `PathSaveSelectionClearingContractTests`：通过。
- `PathTopologyPersistenceContractTests`：通过。
- `SpaceTriggerZoneFollowupContractTests`：通过。
- `GroupPathSequenceDeviceAddViewContractTests`：通过。
- `git diff --check`：通过。
- SunSmart、Archipelago、Lumineux、SylSmart、SLG Sync Plus：Debug、通用 iPhoneOS、关闭签名构建均通过。

## 验收边界

源码契约与通用 iPhoneOS 构建可以证明清理时序、刷新接线和编译兼容，不能替代真实页面交互验收。真机应分别验证三个入口：选中一行后点击 `SAVE`，确认行立即取消选中；制造容量校验失败或设备同步失败并返回，再选择另一行，确认始终只有一行显示为选中。
