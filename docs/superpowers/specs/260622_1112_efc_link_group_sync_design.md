# EFC LINK Group Sync 修复设计

## 背景

虚拟 EFC 关联一个包含真实设备的 Group 后，再 LINK 一个真实 EFC 设备，当前实现会在 Add Device 的 append 阶段同时追加两类任务：

- EFC controller 自身默认配置。
- 已关联 Group 内真实设备订阅 EFC publish group 的配置。

EFC controller 自身配置的目标是刚入网的 EFC 节点，适合放在 Add Device append 阶段。Group 订阅配置的目标是 Group 内已有灯具节点，不是刚入网的 EFC 节点，不适合放进 fast-add append 队列。

## 根因

`DeviceAddClassicModeController` / `DeviceAddProfessionalModeController` 在 LINK EFC 时调用 `appendLinkedEmergencyFireControllerGroupSubscriptionMessages(...)`，把 Group 订阅任务追加到 fast-add append 队列。

这些任务由 `EmergencyFireControllerSyncPlanner.makeAssociationSubscriptionTasks(...)` 生成，消息是 `ConfigModelSubscriptionAdd`，目标地址是 Group 内真实设备的 `primaryUnicastAddress`。

SDK 的 fast-add append 发送分支在处理 `AcknowledgedConfigMessage` 时，即使 `MeshMessageHandle.address` 是 Group 内设备地址，也会按当前新增设备 `node` 发送。结果是：

- Group 内设备没有真正收到订阅配置。
- 回包 source 与 `MeshMessageHandle` 期望 source 不匹配，append 阶段等待到 45 秒超时或失败分支。
- LINK 成功 callback 当前只刷新 UI 并 dismiss，不再进入正常 EFC Sync 页面。
- 用户需要修改 EFC 配置并再次 SAVE，才会通过正常 sync 通道把 Group 订阅配置下发出去。

## 修复目标

1. LINK 后不再因为真实 Group 订阅任务卡在 Add Device 页面等待很久。
2. 有真实设备的 Group 在 LINK 后必须实际下发订阅配置，配置立即生效。
3. 空组按“没有可下发组订阅任务”处理，只要 EFC controller 自身配置成功，就标记为已同步。
4. EFC controller 自身默认配置仍在 Add Device append 阶段静默下发，不额外弹出 sync 页。
5. Group 订阅配置必须使用能按真实目标节点发送的同步通道，不能继续塞进 fast-add append 队列。

## 方案对比

### 方案 A：Add Device 只处理 EFC 自身配置，LINK 成功后触发 EFC 正常 Sync

在 Add Device append 阶段保留 `appendEmergencyFireControllerDefaultConfigurationMessages(...)`，移除 Group 订阅 append。LINK 成功 callback 刷新绑定状态后，判断当前 EFC 是否存在关联 Group 订阅任务：

- 没有任务：若 controller 自身配置成功，保持 synced。
- 有任务：进入 EFC Sync 流程，由现有 `SyncDevicesViewController(type: .emergencyFire(...))` 通过真实目标地址下发。

优点：

- 复用现有 EFC Sync planner、失败记录、重试和状态回写。
- 发送路径与用户再次 SAVE 后能成功的路径一致。
- 风险低，不需要修改 SDK fast-add 发送语义。

缺点：

- LINK 后可能出现一次同步页面或同步过程，不再是完全留在 Add Device append 阶段内完成。

### 方案 B：实现 EFC 专用 LINK 后静默同步 runner

在 LINK 成功后创建专用后台 runner，直接执行 `EmergencyFireControllerSyncPlanner` 生成的 Group 订阅任务，并按任务真实地址发送。

优点：

- 用户体验可做成静默完成，不一定展示 Sync 页面。

缺点：

- 需要新建一套发送、回包、失败、状态回写与中断处理逻辑。
- 容易和现有 EFC Sync 行为分叉，后续维护成本更高。

### 方案 C：修改 SDK fast-add append 支持跨节点 acknowledged config

让 fast-add append 在 `AcknowledgedConfigMessage + address` 场景下按 address 查找目标 node 再发送。

优点：

- 表面上改动点集中在 SDK。

缺点：

- fast-add append 原本是新增设备配置流程，改成跨节点配置会扩大行为范围。
- 会影响其它 add-device append 使用方，回归风险高。
- 仍需处理跨节点 append 失败、连续任务和 UI 等待语义。

## 推荐方案

采用方案 A。

具体设计：

1. Add Device append 阶段只保留 EFC controller 自身默认配置。
2. 删除或停用 `appendLinkedEmergencyFireControllerGroupSubscriptionMessages(...)` 在 Add Device append 队列中的调用。
3. LINK 成功 callback 刷新绑定状态后，重新读取绑定后的 EFC 数据。
4. 如果没有任何可下发 Group 订阅任务，保持当前成功路径：controller 自身配置成功后标记 synced。
5. 如果存在 Group 订阅任务，进入 EFC Sync 流程，使用 `.saveConfiguration(persistsSyncResult: true, changedFromConfiguration: nil)` 语义，让现有 planner 和发送队列处理真实目标地址。
6. Sync 成功后把 EFC 标记为 synced；Sync 失败则保留 need-sync 状态，供用户 Retry / SAVE 后继续同步。

## Battery Power Switch 对标

虚拟 Battery Power Switch LINK 时，add-device append 只下发新绑定 switch 自身的 vendor 配置，目标 model 就在新增节点上，因此适合放在 append 阶段。

EFC 的差异在于 associated Group 订阅任务目标是 Group 内已有设备。它不是新增 EFC 节点的自身配置，所以不能照搬到 add-device append；应照搬 Battery Power Switch 的状态语义：LINK 时先准备 desired config，真正需要跨节点同步时走 Sync 流程并按成功/失败回写状态。

## 验证计划

1. 运行 `bash scripts/check_efc_controller_flows.sh`，补充或更新 contract，确保 EFC LINK 不再把 Group 订阅任务塞进 Add Device append。
2. 运行 iPhoneOS build：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
3. 手工验证：
   - 虚拟 EFC + 空组 + LINK 真实 EFC：Add Device 不长时间等待，controller 自身配置成功后已同步。
   - 虚拟 EFC + 有真实设备 Group + LINK 真实 EFC：LINK 后进入正确同步流程，Group 内设备收到订阅配置，完成后不再显示需要同步。
   - 故意让 Group 内设备离线：Sync 失败后保留 need-sync，后续 Retry / SAVE 可继续下发。

