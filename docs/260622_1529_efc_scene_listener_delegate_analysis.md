# EFC Scene 监听中断问题分析与修复方案

## 结论

问题真实存在。

当前 App 进入 Space 后会创建 `EmergencyFireControllerSceneEventManager`，并维护 EFC 内部 publish group 的 proxy filter。但 EFC scene 业务解析并不是由 Space 级 manager 直接接收所有 mesh message，而是依赖当前 `MeshLibManager.manager.messageDelegate` 页面在 `didReceiveMessage` 中调用 `EmergencyFireControllerSceneEventManager.dispatch(...)`。

因此，当当前页面把自己设为 `messageDelegate` 但没有转发 `didReceiveMessage` 时，SDK 仍能打印 `[Scene Recall RX]`，但 App 业务层不会进入 EFC scene 匹配，也就不会打印 `[EFC Scene] matched`。

## 复现链路解释

1. 进入 Space 后，`SpaceViewController` 在网络扩展数据加载完成后创建并激活 `EmergencyFireControllerSceneEventManager`。
2. `EmergencyFireControllerSceneEventManager` 会根据 `DeviceEmerFireStore.shared.devices(in: space)` 维护 EFC publish group 的 proxy filter。
3. 从 Main - Others 进入 EFC 设备页时，`EmerFireAlarmMonitorVC.viewWillAppear` 保存旧的 `messageDelegate`，然后把 `messageDelegate` 改成自己。
4. EFC 设备页内收到 recall scene 时，`EmerFireAlarmMonitorVC` 会在 `didReceiveMessage` 中调用 `EmergencyFireControllerSceneEventManager.dispatch(...)`，因此能打印 `[EFC Scene] matched`。
5. 退出 EFC 设备页时，`EmerFireAlarmMonitorVC.viewDidDisappear` 把 `messageDelegate` 还原成进入前的页面，也就是 `DeviceOthersViewController`。
6. `DeviceOthersViewController` 当前只实现了 `deviceDataUpdate`，没有实现 `didReceiveMessage`，因此后续 recall scene 不会进入 EFC scene manager。
7. SDK 的 `[Scene Recall RX]` 在 `NetworkManager` 通知 App delegate 前打印，所以它仍然存在；这证明设备端 recall 和 mesh 接收没有断。
8. 切换到 Lights 分类并下拉刷新后，`DeviceLightsViewController.viewDidAppear` 把 `messageDelegate` 改成自己，而 Lights 页面实现了 `didReceiveMessage` 并调用 `EmergencyFireControllerSceneEventManager.dispatch(...)`，所以 `[EFC Scene] matched` 又恢复。

## 影响范围

- 已确认受影响：`DeviceOthersViewController`。
- 同类风险：`DeviceSwitchesViewController` 也会把自己设为 `messageDelegate`，但只实现 `deviceDataUpdate`，未转发 `didReceiveMessage`。
- Lights、普通设备详情、EFC 设备页等已实现 `didReceiveMessage` 转发，因此在这些页面可正常匹配。
- Sensors 当前没有接管 `messageDelegate`，不是本次复现的直接断点。

## 根因

根因不是 EFC group subscription、proxy filter、AppKey、Scene ID 或 EFC controller 数据丢失。

根因是 EFC scene 监听职责被拆成了两段：

- Space 级 `EmergencyFireControllerSceneEventManager` 负责匹配、状态更新和 proxy filter。
- 当前页面的 `messageDelegate` 负责把 mesh message 转交给 manager。

这导致“进入 Space 后持续监听 EFC 状态”的需求没有真正落在 Space 级全局链路上，而是受当前页面是否正确转发 `didReceiveMessage` 影响。

## 修复方案选项

### 方案 A：只补 DeviceOthersViewController 的 didReceiveMessage

在 `DeviceOthersViewController` 的 `MeshLibManagerMessageDelegate` extension 中增加 `didReceiveMessage`，只做 EFC scene dispatch。

优点：
- 改动最小。
- 能直接修复当前用户复现路径。

缺点：
- 只修 Others，Switches 等同类页面仍可能断。
- 与“进入 Space 后就持续监听”的产品预期不完全一致。

### 方案 B：补齐当前设备分类页的 EFC dispatch 转发

在所有会接管 `MeshLibManager.manager.messageDelegate` 的设备分类页中补齐 EFC scene dispatch，至少包括：

- `DeviceOthersViewController`
- `DeviceSwitchesViewController`

并保持 Lights 现有逻辑不变。

优点：
- 改动仍然小，风险低。
- 修复当前问题和已确认的 sibling 风险。
- 不碰 SDK、AppKey、proxy filter、EFC sync planner 或协议逻辑。

缺点：
- 仍然依赖页面转发约定，未来新增页面如果接管 `messageDelegate` 仍可能漏转发。

### 方案 C：把 EFC scene dispatch 移到全局消息入口

在 `MeshLibManager` 收到普通 mesh message 后，直接或通过一个全局 observer/callback 调用 EFC scene dispatch，让 EFC 状态监听不再依赖页面级 `messageDelegate`。

优点：
- 最符合“进入 Space 后只要有 EFC 就持续监听”的架构目标。
- 从根上消除页面转发遗漏。

缺点：
- 需要改 SDK 或新增全局消息分发机制。
- 需要处理当前 `messageReceiveCallback` 已被 OTA distribution 使用的问题，避免覆盖已有回调。
- 验证面更大，涉及 SDK 与 App 双侧构建。

## 推荐方案

推荐先采用方案 B。

理由：
- 当前故障点已经明确，不需要改协议、订阅或 proxy filter。
- 方案 B 能修复当前 Others 路径，同时覆盖已发现的 Switches 同类断点。
- 改动范围比方案 C 小，适合当前问题的修复节奏。
- 后续如果继续发现页面级 `messageDelegate` 漏转发，再单独规划全局消息分发机制，避免本轮把 SDK 架构和 EFC 状态修复绑在一起。

## 后续确认

用户确认采用方案 C，并明确要求：

- 全局入口接管 EFC scene dispatch。
- 移除页面里的 EFC dispatch，避免重复触发。

对应实现计划已保存到：

- `docs/superpowers/plans/2026-06-22-efc-global-scene-dispatch.md`

## 重复 observer 问题补充

方案 C 初版只在 `SpaceViewController.deinit` 中移除全局 message observer。实际退出 Space 后，旧 `SpaceViewController` 实例可能仍被导航栈、回调或残留清理链路短暂持有，并不会立刻 deinit。

因此每次重新进入 Space 都会注册新的 SDK 全局 observer，而旧 observer 仍留在 `MeshLibManager` 的 singleton observer 列表中。同一条 recall scene 会被多个 observer 转发到 `EmergencyFireControllerSceneEventManager.dispatch(...)`，表现为第二次进入 Space 打印两份 `[EFC Scene]` 日志，第三次进入打印三份。

修复方式：

- 保留方案 C 的全局入口接管，不恢复页面级 EFC dispatch。
- 将 EFC scene monitoring 的停止逻辑收敛为 `stopEmergencyFireSceneMonitoring()`。
- 在 `stopSpacePresenceTracking(reason:)` 中调用该停止逻辑，确保离开 Space、Sites 残留清理、权限失效和 deinit 都走同一个清理路径。
- 在异步 `loadExtensionData` 回调和 observer 注册入口增加已停止判断，避免 Space 已退出后回调晚到又重新注册全局 observer。
- contract 检查 `stopSpacePresenceTracking(reason:)` 必须停止 EFC scene monitoring，防止以后退回只依赖 deinit 的实现。

## 验证建议

1. 静态检查 SDK 暴露 `addGlobalMessageObserver` / `removeGlobalMessageObserver`，且不覆盖原有 `messageDelegate` 和 `messageReceiveCallback`。
2. 静态检查 `SpaceViewController` 注册全局 observer，并且 App 内只有 `SpaceViewController` 调用 `EmergencyFireControllerSceneEventManager.dispatch(...)`。
3. 静态检查 `stopSpacePresenceTracking(reason:)` 会停止 EFC scene monitoring，避免 Space 反复进入后 observer 累加。
4. 运行 `scripts/check_efc_controller_flows.sh`，确认页面级 EFC dispatch 不再残留，且离开 Space 会清理全局 observer。
5. 手工验证 Others 复现链路：
   - Space 内存在已绑定且有 publish group 的 EFC。
   - 从 Main - Others 进入 EFC 设备页。
   - 触发 emergency，再触发 restore，确认设备页内有 `[EFC Scene] matched`。
   - 退出 EFC 设备页，仍停留在 Others。
   - 再触发 emergency/restore，确认仍有 `[Scene Recall RX]` 和 `[EFC Scene] matched`。
6. 手工验证进入 Space、退出 Space、再次进入 Space 后，同一条 recall scene 只打印一份 `[EFC Scene]` matched 日志。
7. 手工验证 Switches 分类停留时也能打印 `[EFC Scene] matched`。
8. 运行 `git diff --check`。
9. 按项目规则运行 iPhoneOS 构建：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
