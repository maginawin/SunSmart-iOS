# EFC LINK 同步闭环修复设计

## 背景

用户反馈的流程：

1. 添加一个 EFC 虚拟设备。
2. 在 `Associate with group(s)` 中添加一个空组，或添加一个已有真实设备的组。
3. 进入 EFC 设备页，右上角选择 `Edit`。
4. 在 Edit 页面选择 `LINK`，把一个真实 EFC 设备绑定到该虚拟 EFC。
5. LINK 完成后，设备页立即展示需要同步。
6. 再进入 Edit 页面选择 `Sync`，会发现真实 EFC 需要重新下发 EFC 自身配置，真实组场景下组配置也未随 LINK 下发。

预期行为：

- 空组场景：组内没有设备，没有可下发的组订阅任务。只要 EFC controller 自身配置下发成功，LINK 后就应标记为已同步。
- 真实组场景：LINK 时既要下发 EFC controller 自身配置，也要下发关联组内设备对 EFC 内部 publish group 的订阅。两者成功后，LINK 后不应展示需要同步。

## 代码事实

- `LinkedEmerFireEditVC.linkRealDeviceAction()` 保存虚拟 EFC 后，通过 `DeviceAddViewController.bindTarget = .emergencyFire(device)` 进入 Add Device LINK 流程。LINK 完成回调目前会调用 `openSyncAfterLinkedDeviceIfNeeded()`。
- Classic / Professional Add Device 在 EFC 分支中都会调用 `DeviceEmerFireStore.bind(...)`，然后通过 `appendEmergencyFireControllerDefaultConfigurationMessages(...)` 静默追加 EFC controller 默认配置。
- `finishEmergencyFireDefaultConfiguration(for:)` 目前只在 `!controller.configuration.hasSyncIntent` 时把 `isSynced` 按下发结果更新。因此只要虚拟 EFC 先关联过 group，即使是空组，LINK 成功后也会保留 unsynced。
- 现有 `appendEmergencyFireControllerGroupMutationMessages(node:group:appendMessages:)` 只服务“把新灯加入某个 group”时的 EFC group mutation，不服务“把真实 EFC LINK 到已有虚拟 EFC”时的全量关联组订阅。
- Battery power switch 的 LINK 路径在相同 Add Device append 阶段会构造 linked switch data，并追加 linked configuration message handles。EFC 应采用同类思路，把 LINK 阶段当成配置闭环入口，而不是 LINK 后再依赖同步页补救。

## 方案选择

采用方案 A：在 Add Device LINK append 阶段完成 EFC 配置闭环。

不采用的方案：

- LINK 后继续跳转 Sync 页面：仍会打断 LINK 体验，也不满足“LINK 后不要展示需要同步状态”。
- 只改 `isSynced` 判断：会掩盖真实组订阅未下发的问题。

## 目标设计

### 1. LINK append 阶段追加 controller 配置

保持现有行为：当新增节点是 `.emergencyController` 且当前 `bindTarget` 是 EFC 时，先通过 `DeviceEmerFireStore.bind(...)` 把虚拟 EFC 绑定到真实节点，再追加 EFC controller 默认配置。

这部分继续使用 `DeviceEmerFireData.getControllerDefaultConfigurationMessageHandles(...)`，确保包括 Scene publication、Enable、Resend、Action Config、Restore Delay 等 controller-side 配置。

### 2. LINK append 阶段追加关联组订阅

新增 EFC LINK 专用 append 逻辑：

- 从绑定后的 `DeviceEmerFireData.configuration.activeLightLCGroupAddresses` 获取当前关联组。
- 对每个 group：
  - 如果 group 不存在，跳过 mesh 下发任务，不把它当作本次 LINK 下发失败。
  - 如果 group 存在但 `group.nodes` 为空，视为没有可下发任务。
  - 如果 group 内有设备，复用 `EmergencyFireControllerSyncPlanner.makeAssociateTasks(node:group:publishGroup:)` 为每个节点生成订阅任务。
- 生成的 group subscription message handles 跟随 Add Device append 队列下发，并登记到本次 LINK 的 EFC group subscription 追踪表。

### 3. LINK 收尾同步态判定

Classic / Professional 两个 Add Device 控制器需要使用相同判定规则：

- controller 默认配置有下发任务且全部成功；
- 本次 LINK 生成的关联组订阅任务全部成功，或者没有任何可下发的关联组订阅任务；
- 满足以上条件时，保存 `controller.isSynced = true`；
- 任一登记过的下发任务失败时，保存 `controller.isSynced = false`；
- 如果 controller 默认配置无法生成 handles，应保留未同步状态，后续由手动 Sync/Repair 处理。

空组的确认规则：空组不生成 group subscription handles，因此不会制造 pending sync。只要 controller 默认配置成功，即可标记为已同步。

### 4. LINK 后页面行为

`LinkedEmerFireEditVC` 的 LINK 成功回调只刷新本地状态、列表和通知，不再依赖 `openSyncAfterLinkedDeviceIfNeeded()` 作为正常 LINK 后续流程。

如果实现时仍保留该方法，只能作为非正常兜底入口；正常 LINK 成功后不应自动进入 EFC Sync 页面。

### 5. 失败处理

- controller 默认配置失败：真实 EFC 保留 `isSynced = false`，设备页可继续提示需要同步。
- 真实组订阅失败：真实 EFC 保留 `isSynced = false`，后续手动 Sync 负责补发 EFC controller 与关联组配置。
- 空组无下发任务：不算失败。
- group 已不存在：不作为本次 LINK mesh 下发失败；当前配置仍可由后续 Edit/Sync 或数据一致性流程处理。

## 影响范围

改动范围应限制在：

- `DeviceAddClassicModeController`
- `DeviceAddProfessionalModeController`
- `LinkedEmerFireEditVC`
- 必要的 EFC contract 脚本

不应修改：

- EFC SAVE 的正常同步页语义。
- EFC Delete cleanup。
- Restore Device Data。
- Battery / AC power switch。
- SDK AppKey bind 或 `0x4D/0x07 app_idx` 取值。
- 普通 group add 的 profile sync 或 fast add 逻辑。

## 验证计划

静态/contract 验证：

- `scripts/check_efc_controller_flows.sh` 增加检查，确保 Classic 和 Professional EFC LINK 都会追加 linked associated group subscription 逻辑。
- 检查 LINK 成功回调不再把正常流程导向 `openSyncAfterLinkedDeviceIfNeeded()`。
- 检查空组语义不创建失败状态。
- 检查 EFC associated group subscription 仍复用 `EmergencyFireControllerSyncPlanner` 的固定 model 集合和节点实际模型过滤。

构建验证：

- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

手工 BLE 验证：

- 虚拟 EFC 关联空组后 LINK 真实 EFC：LINK 成功后不展示需要同步；Edit 页面不要求再次下发 EFC 自身配置。
- 虚拟 EFC 关联真实组后 LINK 真实 EFC：LINK 阶段下发 EFC controller 配置和组内设备订阅；LINK 成功后不展示需要同步。
- 断开或制造 group subscription 失败：LINK 后保留需要同步状态，手动 Sync 可补发。
- 无 associated group 的虚拟 EFC LINK 真实 EFC：保持已有静默 controller 默认配置行为，不进入 Sync 页面。

## 用户确认

用户已确认采用方案 A，并明确空组规则：如果关联的是空组，按“没有可下发组订阅任务”处理，只要 EFC controller 自身配置下发成功，就直接标记为已同步。
