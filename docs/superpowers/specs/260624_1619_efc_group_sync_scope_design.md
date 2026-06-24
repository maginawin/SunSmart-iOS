# EFC Group Sync Scope Design

## 背景

真实 EFC 设备在 Edit 页面添加或移除关联 Group 后，SAVE 会进入 `Sync device(s)` 页面执行与 Group 相关的同步任务。用户主动点击 STOP 后，EFC Edit 页面会展示 `Devices not synced`，这是预期行为：它表示 EFC 这份配置还有未完成的同步工作。

当前问题是状态粒度过粗。STOP 后 EFC 会被标记为未同步；再次从 `Devices not synced` 进入时，系统按完整 EFC 修复同步生成任务，导致只剩 Light 侧 `Group Subscription` 或 `Group Cleanup` 时，也展示 EFC 自身的 `Others` 任务。

## 已确认需求

- 如果 EFC 的 group 同步未完成，EFC 设备本身仍应展示 `Devices not synced`。
- `Devices not synced` 的含义是“EFC 配置未完全同步”，不等同于“EFC controller 自身参数一定需要重新下发”。
- 添加 Group 后 STOP，只应继续补 Light 侧 `Group Subscription`。
- 移除 Group 后 STOP，只应继续补 Light 侧 `Group Cleanup`。
- association-only 未完成时，不应要求用户执行 EFC 自身的完整 `Others` 修复任务。
- Lights 页底部同步按钮若展示，应能处理 Light 侧 EFC subscription / cleanup 任务，并在完成后清除对应 EFC 未同步状态。

## 推荐方案

采用方案 A：拆分 EFC controller self sync 与 associated group sync。

EFC 继续保留一个对用户可见的 `Devices not synced` 状态，但内部判断同步范围时区分两类未完成工作：

1. Controller self sync：EFC 自身 publication、enable、resend、action config、restore delay 等参数。
2. Associated group sync：Light 节点对 EFC 内部 publish group 的订阅和退订。

只有第一类未完成时，才生成 EFC 自身 `Others` 任务。只有第二类未完成时，Edit 页和 Lights 页都只进入 group association 任务。

## 数据流

EFC Edit 保存时，比较旧配置与新配置：

- 如果 controller self 参数有变化，标记 controller self dirty。
- 如果关联 Group 增加，保留 association subscription intent。
- 如果关联 Group 移除，保留 pending cleanup intent。
- 清除受影响 Light 节点的 sync cache，让 Lights 页底部按钮能重新计算。

同步成功时：

- Controller self sync 成功后清除 controller self dirty。
- Association subscription / cleanup 成功后清除对应 group pending intent。
- 当 controller self dirty 和 association pending 都为空时，EFC `Devices not synced` 状态消失。

同步 STOP 或失败时：

- 已成功的 task 仍保留成功结果。
- 未完成的 controller self task 保留 controller self dirty。
- 未完成的 association task 保留 association pending。
- EFC 仍展示 `Devices not synced`，但后续入口只生成剩余任务。

## 入口行为

EFC Edit 页面点击 `Devices not synced`：

- 如果只有 association pending，打开 EFC sync 页面，但只显示相关 Group 的 Light subscription / cleanup。
- 如果只有 controller self dirty，打开 EFC sync 页面，只显示 EFC 自身 `Others` 任务。
- 如果两者都有，按 controller self 和 association 任务组合展示。

Lights 页底部同步按钮：

- 继续以 Light 节点 `needSync` 为入口。
- Light 节点的 EFC association pending 会生成 `Group Subscription` 或 `Group Cleanup`。
- 完成后需要通知 EFC store 更新，避免 EFC 继续残留未同步状态。

Scene / Schedule 中删除 Group：

- 继续保持现有 Scene / Schedule 自身同步语义。
- 如果删除动作同时影响 EFC association cleanup，Light 节点应能通过统一的 association pending 逻辑暴露同步按钮。

## 错误处理

- Mesh 未连接时，仍按现有同步页规则提示无法执行。
- 找不到 Group 或 Group 内没有可执行节点时，保留 local cleanup task，用于清除 pending 标记。
- 离线或未 key bind 的 Light 节点不应误清 pending；需要保留未同步状态，等待后续重试。
- EFC 绑定节点不可用时，只影响 controller self sync，不应阻塞已能判断的 Light association cleanup。

## 测试计划

1. 添加真实 EFC，SAVE 当前配置。
2. 添加 Group A，并在 Group A 中添加 Light A。
3. 在 EFC Edit 页面选择 Group A，SAVE 后进入同步页。
4. Group Subscription 未完成时点击 STOP。
5. 回到 EFC Edit 页面，确认展示 `Devices not synced`。
6. 点击 `Devices not synced`，确认只展示 Light A 的 Group Subscription，不展示冗余 EFC Others 全量任务。
7. 不点击 `Devices not synced`，回到 Main - Lights，确认底部同步按钮能展示并完成 Light A 的 EFC association subscription。
8. 同步完成后，确认 EFC 不再残留 `Devices not synced`。
9. 从 EFC 移除 Group A，SAVE 后在 cleanup 未完成时 STOP。
10. 确认 EFC 展示 `Devices not synced`。
11. 确认 Lights 底部按钮能展示并完成 Light A 的 EFC association cleanup。
12. 完成后确认 EFC pending cleanup 被清除，且 EFC 不再展示 `Devices not synced`。

## 验证范围

- 运行 EFC contract 脚本，覆盖 EFC sync planner、Edit 入口、Lights 页 footer 和 association cleanup 行为。
- 运行 `git diff --check`。
- 运行 SunSmart iPhoneOS build。
