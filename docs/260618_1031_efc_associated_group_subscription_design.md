# EFC Associated Group Subscription 设计

## 背景

EFC Edit 页面配置 `Associate with group(s)` 时，App 需要让 associated groups 中的设备订阅 EFC 内部 Group。这个订阅关系用于让 EFC 固件后续向 EFC Group 下发动作时，组内设备能接收到对应控制命令。

当前实现仍把部分订阅行为和 EFC 功能配置耦合：

- `Set brightness` 场景始终补 Light Lightness Server 订阅。
- `Restore AUTO` 时才补 Light LC Server 订阅。
- 从 `Restore AUTO` 切换到 `Set Brightness` 或 `None` 时，会清理 Light LC / Scene 历史订阅。

新的业务规则要求：associated groups 的设备订阅 EFC Group 只由“是否关联该 group”决定，不再根据 EFC 设备配置的功能增加或删除某些 Model 订阅。

## 目标

- Associated groups 中所有可同步设备，都按固定 Model 集合订阅 EFC Group。
- EFC 功能配置变化不触发 associated group 设备的 Model 订阅增删。
- 固定 Model 集合只是候选集合；具体到每个设备时，只对该设备实际拥有的 Model 分配订阅任务。
- 设备本身没有的 Model 不生成同步任务，避免对不支持的 Model 产生无效配置消息。
- 只在取消关联 group、group member 退出、删除 EFC 时清理 EFC Group 订阅。
- 保留 Scene Server 历史订阅清理，但 Scene Server 不再作为 desired subscription。

## 固定订阅模型

采用方案 B：EFC associated group 的 desired subscription 对齐普通 group control models，并补充 AUTO 所需 Light LC Server。

| Model ID | Model | 用途 |
| --- | --- | --- |
| `0x1000` | Generic OnOff Server | 保持与普通 group on/off control 一致 |
| `0x1300` | Light Lightness Server | Set brightness |
| `0x1303` | Light CTL Server | 保持与普通 group CTL control 一致 |
| `0x1306` | Light CTL Temperature Server | 保持与普通 group CCT control 一致 |
| `0x1307` | Light HSL Server | 保持与普通 group HSL control 一致 |
| `0x130F` | Light LC Server | AUTO / Restore AUTO |

订阅规则：

- 对 associated group 内每个在线、keybind complete 的设备，遍历上述固定集合。
- 如果设备 composition 中存在对应 Model，并且该 Model 尚未订阅 EFC Group，则生成 `ConfigModelSubscriptionAdd`。
- 如果设备 composition 中不存在对应 Model，则直接跳过，不为该 Model 创建 task 或 sync row。
- 不根据 Power Loss / Fire Alarm / Event Ends 的 action type 过滤这个集合。

## 不作为 desired subscription 的模型

- `0x1203` Scene Server：只做历史清理，不再主动订阅。
- Setup models，例如 `0x1301`、`0x1310`：属于配置模型，不是运行态 EFC group action 目标。
- Client models，例如 `0x1302`、`0x1309`、`0x1311`：client 是发起控制的一侧，不是 associated group 灯端订阅目标。
- Sensor / Scheduler / Vendor models：当前 EFC action config 没有证据需要它们订阅 EFC Group。

## 数据流

1. 用户在 EFC Edit 页面保存 associated groups。
2. `EmergencyFireControllerSyncPlanner` 确保 EFC Group 存在。
3. Planner 针对当前 active associated groups 展开组内节点。
4. 每个节点按固定 desired Model 集合生成缺失的 subscription add 任务。
5. 如果只是修改 EFC 功能配置，例如 brightness、AUTO、restore delay、send count，不改变 associated group，则不生成与功能类型相关的 subscription delete。
6. 用户取消关联 group、group member 退出、删除 EFC 时，才对对应节点生成 EFC Group subscription delete。

## 清理策略

正常清理：

- 取消关联 group：清理该 group 内设备对 EFC Group 的固定 desired Model 订阅。
- Group member 退出：清理退出节点对 EFC Group 的固定 desired Model 订阅。
- 删除 EFC：清理所有已关联或 pending cleanup group 内设备对 EFC Group 的固定 desired Model 订阅。

历史兼容：

- 如果发现 Scene Server 仍订阅 EFC Group，可继续生成 delete 任务。
- Scene Server delete 只用于清理旧版本残留，不参与新增订阅，也不因 action type 变化单独触发。

## 错误处理

- 设备离线、未 keybind complete、缺失目标 Model 时，不生成对应订阅任务。
- 固定 desired Model 集合不能被理解为每台设备必须全量订阅；实际任务以设备拥有的 Model 为准。
- 找不到 group 或 group 内没有可下发节点时，保留 local-only cleanup task，用于清理 pending 标记。
- 单个节点某个 Model 已订阅 EFC Group 时跳过 add，避免重复消息。
- 单个节点某个 Model 未订阅 EFC Group 时跳过 delete，避免无意义清理。

## 实现边界

本轮做：

- 重构 EFC associated group subscription planner。
- 将 Light LC subscription 从 `Restore AUTO` 条件中移出，变成固定 desired Model。
- 新增 Generic OnOff / CTL / CTL Temperature / HSL 的 EFC Group subscription。
- 删除因 action type 切换触发的 Light LC cleanup。
- 保留并收口 Scene Server 历史清理。
- 更新 contract script，防止后续又把订阅逻辑绑回 action type。

本轮不做：

- 不修改 EFC UI 文案和布局。
- 不修改 `0x4D/0x07` action config payload。
- 不修改普通 group subscription 的 SDK 全局集合。
- 不新增云端 schema。
- 不把 client / setup / sensor / scheduler / vendor models 加入 EFC desired subscription。

## 验收标准

- Associated group 新增时，设备实际拥有的 `0x1000/0x1300/0x1303/0x1306/0x1307/0x130F` 会订阅 EFC Group。
- 设备没有的候选 Model 不会生成任务，也不会在同步页面显示对应 sync row。
- `Set brightness`、`Restore AUTO`、`None` 之间切换时，不因为 action type 变化删除 Light LC 或其他 desired subscription。
- 删除 associated group 或 group member 退出时，会清理固定 desired Model 订阅。
- 旧 Scene Server 订阅如存在仍可被清理，但新增关联不会再订阅 Scene Server。
- `git diff --check` 通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 通过。
