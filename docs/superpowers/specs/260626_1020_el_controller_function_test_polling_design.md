# EL Controller Function Test 轮询适配设计

## 背景

`CID 0x0A78 / PID 0x24C1` 的 EL Controller 页面已经接入 Sunricher Vendor `0x45` 协议。当前点击 Function Test 的 `Start` 按钮后，App 会发送：

- SET opcode：`0xF0780A`
- payload：`45 07`

实测设备会回复成功 ACK：

- RET opcode：`0xF3780A`
- payload：`45 07 00 0E`

其中 `0x07` 是 Start Function Test 子码回显，`0x00` 表示 Start 成功。尾部 `0x0E` 不能按 Function Test Result 解析；它更接近 Device Status 的 Function testing 状态。当前 App 收到 Start 成功后只保持 `Awaiting device response...`，等待设备主动上报 `RET 0x03`，但实测设备不会继续主动更新结果，因此需要 App 主动轮询 `GET 0x03`。

## 目标

- 进入 EL Controller 设备页面后，先读取 Device Status。
- 如果设备处于 Function testing，Function Test 卡片展示 `Awaiting device response...`，并每 2 秒获取 Function Test Result。
- 点击 Start 成功后，不再依赖设备主动上报，改为每 2 秒获取 Function Test Result。
- 页面不可见时停止轮询，包括退出页面栈和 push 新页面。
- 下次回到 EL Controller 页面时，Function Test 和 RX/TX Cable 先恢复默认 UI，再重新读取 Device Status。
- 将流程封装成 helper，避免继续扩大 `DeviceLightViewController`。

## 非目标

- 不修改 SDK 的 vendor opcode、payload 编码和基础解析。
- 不在 UI 展示 Exit Function Test。
- 不在离开页面时自动发送 SET `0x08`。
- 不改变 SDK 层不限制 PID 的既有设计。
- 不改变其他 Emergency Sign、EFC、普通 Light 页面流程。

## 当前代码事实

- `DeviceLightViewController` 已通过 `supportsELControllerLocalFunctionViews` 将 EL Controller UI 限制在 `CID 0x0A78 / PID 0x24C1`。
- `ELControllerFunctionTestView` 已支持外部驱动的 Function Test 与 RX/TX Cable 状态。
- `startELControllerFunctionTest()` 当前在 Start ACK 成功后只保持 `.awaiting`，没有启动 `GET 0x03` 轮询。
- `handleELControllerVendorStatus(_:sentFrom:)` 当前能处理设备主动 `RET 0x03`，但没有主动查询结果。
- 当前页面只在 `deinit` 恢复 message delegate；`viewDidDisappear` 是注释状态。仅依赖 `deinit` 无法覆盖 push 新页面时停止轮询的要求。

## 推荐架构

新增 App 层 helper，例如 `ELControllerFunctionTestHelper`。

Helper 负责：

- 读取 `GET 0x01 Device Status`。
- 发送 `SET 0x07 Start Function Test`。
- 执行每 2 秒一次的 `GET 0x03 Function Test Result` 轮询。
- 发送 `GET 0x00 RX/TX Cable Connection`。
- 接收 `SunricherVendorStatus` 并转换为页面状态。
- 在页面离开时停止轮询并恢复默认 UI。

`DeviceLightViewController` 负责：

- 在 EL Controller 分支创建 helper。
- 将 Function Test / RX/TX Cable 卡片的按钮 action 绑定到 helper。
- 在 `viewWillAppear` 启动 helper 的页面进入流程。
- 在 `viewWillDisappear` 停止 helper 并恢复默认状态。
- 在 `meshNetworkManager(_:didReceiveMessage:sentFrom:to:)` 中继续将 `SunricherVendorStatus` 转交给 helper。

这样 controller 只保留页面生命周期和 UI 连接点，具体协议状态机收口在 helper。

## 页面进入流程

1. `viewWillAppear` 后，如果当前页面支持 EL Controller 本地功能，并且设备 key bind 完成、在线，则 helper 启动。
2. helper 先将 Function Test 恢复默认状态。
3. helper 先将 RX/TX Cable 恢复默认状态。
4. helper 发送 `SunricherVendorGet(function: .elControllerDeviceStatus)`。
5. 收到 `ret=0` 且 `status=0x0E`：
   - Function Test 展示 `Awaiting device response...`。
   - 启动每 2 秒 `GET 0x03 Function Test Result` 轮询。
   - RX/TX Cable 保持默认状态。
6. 收到 `ret=0` 且 `status=0x03` 或其他值：
   - Function Test 保持默认状态。
   - 不启动轮询。
   - RX/TX Cable 保持默认状态。
7. `GET 0x01` 超时、失败或解析不到 status：
   - Function Test 保持默认状态。
   - RX/TX Cable 保持默认状态。
   - 不启动轮询。

## Start 按钮流程

1. 用户点击 Function Test 的 `Start`。
2. helper 检查 EL Controller 支持、key bind、在线状态和 vendor model。
3. helper 将 Function Test 设置为 `Awaiting device response...`。
4. helper 发送 `SunricherVendorSet(function: .elControllerStartFunctionTest)`。
5. 收到 Start ACK 且 `ret=0`：
   - 保持 `Awaiting device response...`。
   - 启动每 2 秒 `GET 0x03 Function Test Result` 轮询。
6. Start ACK 超时、`ret != 0` 或解析不到 Start ACK：
   - Function Test 展示 `Failed`。
   - 不启动轮询。

如果设备返回 `45 07 00 0E`，只用 `45 07 00` 判定 Start 成功，尾部 `0x0E` 不作为 Function Test Result。

## Function Test Result 轮询流程

1. helper 启动轮询时先停止旧轮询，避免重复 timer。
2. 每 2 秒发送一次 `SunricherVendorGet(function: .elControllerFunctionTestResult)`。
3. 收到 `ret=0` 且成功解析结果后：
   - `validity=0x07`：Function Test 展示 Invalid result，停止轮询。
   - `validity=0x00` 且无故障位：Function Test 展示 Passed，停止轮询。
   - `validity=0x00` 且有故障位：Function Test 展示对应 lamp / battery / circuit faults，停止轮询。
4. 单次请求超时、无响应、`ret != 0`、payload 长度不足或解析不到结果：
   - Function Test 保持 `Awaiting device response...`。
   - 不展示 Failed。
   - 继续下一轮 2 秒轮询。

该策略使用已确认的方案 A，避免 Mesh 单次丢包或设备暂未产出结果时误判失败。

## RX/TX Cable 流程

RX/TX Cable 逻辑保持原语义，但从 controller 移入 helper：

1. 用户点击 RX/TX Cable 的 Check。
2. helper 发送 `SunricherVendorGet(function: .elControllerRxTxCableConnection)`。
3. 收到 `ret=0`：展示 Connection Normal。
4. 收到 `ret != 0`、超时或解析失败：展示 Connection Fault。
5. 页面离开或重新进入时恢复默认状态。

## 页面离开流程

1. `viewWillDisappear` 覆盖退出页面栈和 push 新页面。
2. helper 停止 Function Test Result 轮询。
3. helper 将 Function Test 恢复默认 UI。
4. helper 将 RX/TX Cable 恢复默认 UI。
5. 不发送 SET `0x08`。
6. `deinit` 继续恢复原 message delegate，作为页面最终释放兜底。

下次 `viewWillAppear` 时，不复用旧结果；重新按页面进入流程读取 Device Status。

## 主动上报处理

即使设备当前不会主动上报，App 仍应保留 `RET 0x03` 处理能力：

- 如果 helper 正在运行且收到当前 node 的 `RET 0x03`，直接解析结果并停止轮询。
- 如果收到当前 node 的 `RET 0x01` 且 status 为 Function testing，进入 Awaiting 并启动轮询。
- 如果收到当前 node 的 `RET 0x00`，更新 RX/TX Cable 状态。
- 非当前 node 或非 EL Controller 页面忽略。

这保证后续固件如果恢复主动上报，App 不需要再改流程。

## Timer 与并发约束

- Timer 使用主线程 timer 或项目现有弱引用 timer 模式均可，但 helper 必须在 stop 时 invalidate。
- 每次启动轮询前必须先停止旧 timer。
- 页面不可见后，timer 回调和 Mesh 回调都不能再更新 UI。
- 建议 helper 内维护 `isActive` 标记；`viewWillAppear` 置为 active，`viewWillDisappear` 置为 inactive。
- 若上一轮 `GET 0x03` 尚未返回，下一轮 timer 仍可继续按 2 秒触发；回调回来时根据 `isActive` 和 source/code 校验决定是否更新 UI。

## 错误处理

- 设备离线或 key bind 未完成：不发送命令，保持现有离线/修复页面行为。
- 缺少 `sunricherVendorModel`：
  - Start：展示 Failed，不启动轮询。
  - RX/TX Check：展示 Fault。
  - 页面进入读取 Device Status：保持默认 UI，不启动轮询。
- Device Status 读取失败：保持默认 UI，不启动轮询。
- Start ACK 失败：展示 Failed，不启动轮询。
- Function Test Result 单次失败：保持 Awaiting，继续轮询。
- Function Test Result 成功但 invalid：展示 Invalid result，停止轮询。
- 页面离开：停止轮询并恢复默认 UI。

## 测试与验证

代码验证：

- Helper 启动后先恢复 Function Test 和 RX/TX 默认状态。
- `GET 0x01` 返回 `45 01 00 0E` 时进入 Awaiting 并启动轮询。
- `GET 0x01` 返回 `45 01 00 03` 或其他 status 时保持默认且不轮询。
- Start ACK 返回 `45 07 00` 或 `45 07 00 0E` 时启动轮询。
- Start ACK 失败时展示 Failed 且不轮询。
- `GET 0x03` 单次失败时继续轮询，不展示 Failed。
- `GET 0x03` 返回 pass / faults / invalid 时更新 UI 并停止轮询。
- `viewWillDisappear` 后 timer 停止，UI 恢复默认。
- 再次 `viewWillAppear` 后重新读取 Device Status。

构建验证：

使用项目推荐 iPhoneOS 构建命令：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如 helper 需要加入 target，需要确认 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 等共享 target source phase 均包含新文件。

## 已确认决策

- 使用推荐方案：新增 App 层 helper，controller 只做生命周期和 UI 连接。
- 使用方案 A：Function Test Result 单次轮询失败不终止，继续保持 Awaiting 并轮询。
- Start ACK `45 07 00 0E` 只表示 Start 成功，不直接解析为 Function Test Result。
- 页面离开包括退出页面栈和 push 新页面，都停止轮询并恢复默认 UI。
- 下次进入页面重新读取 Device Status，不复用旧 UI 状态。
