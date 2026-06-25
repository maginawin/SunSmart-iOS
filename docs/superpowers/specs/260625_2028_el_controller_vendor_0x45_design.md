# EL Controller Vendor 0x45 协议实现设计

## 背景

`CID 0x0A78 / PID 0x24C1` 的 EL Controller 已在设备详情页展示 `Function Test` 与 `RX/TX Cable` 卡片。当前卡片只做本地状态循环，本次需要接入 SIG Mesh Sunricher Vendor 协议 `0x45`，让页面能发送真实命令并处理设备主动上报。

本协议当前用于 `0x0A78 / 0x24C1`，但 SDK 层不做 PID 限制。App UI 层决定是否调用接口和处理上报。

## 协议修正

Transport opcode 使用现有 NordicSigMeshSDK 常量：

| 方向 | SDK opCode | 实际 wire |
| --- | --- | --- |
| SET | `0xF0780A` | `F0 78 0A` |
| GET | `0xF1780A` | `F1 78 0A` |
| RET | `0xF3780A` | `F3 78 0A` |

说明：协议表中 `F0/F1/F3 0A 78` 是笔误。Company ID `0x0A78` 在 3-octet vendor opcode 中按小端 wire 表示为 `78 0A`，与现有 SDK 编码一致。

Access Payload 结构：

- SET：`F0 78 0A | 45 | <sub> | <data>`
- GET：`F1 78 0A | 45 | <sub> | <data>`
- RET：`F3 78 0A | 45 | <sub> | <ret> | <data>`

## 功能范围

本轮实现：

- SDK 层完整建模 `0x45` 协议：
  - SET `0x07`：开始 Function Test。
  - SET `0x08`：退出 Function Test。
  - GET `0x00`：Check RX/TX Cable Connection。
  - GET `0x01`：Get Device Status。
  - GET `0x03`：Get Function Test Result。
  - RET `0x00 / 0x01 / 0x03`：解析应答和主动上报。
- App 层在 EL Controller 详情页接入：
  - Function Test 按钮发送 SET `0x07`。
  - SET 成功后进入 testing 状态，等待设备主动上报 RET `0x03`。
  - 不设置 App 侧超时，不自动轮询 GET `0x01 / 0x03`。
  - 不在 UI 展示 Exit，也不在离开页面时自动发送 SET `0x08`。
  - RX/TX Cable 按钮发送 GET `0x00`，按 ret 显示结果。
- 修正 `ELControllerFunctionTestView` 中现有硬编码按钮文案，新增或复用本地化 key。

本轮不实现：

- Function Test 轮询。
- Function Test 超时失败。
- 自动退出 Function Test。
- PID 以外的页面入口改造。
- 其他 Emergency Fire / EFC 协议语义调整。

## SDK 设计

在本地 `NordicSigMeshSDK` 的 Sunricher Vendor 消息体系中扩展 `VendorOpCode` / `ResponseCode` / `VendorFunctionSet` / `VendorFunctionGet` / `FunctionParameters`：

- 新增 vendor 主码 `0x45`，命名应与 EL Controller 或 legacy emergency function test 语义绑定，避免与现有 `0x4D` Emergency Fire v2 混淆。
- 新增子码枚举：
  - `0x00`：RX/TX Cable Connection。
  - `0x01`：Device Status。
  - `0x03`：Function Test Result。
  - `0x07`：Start Function Test。
  - `0x08`：Exit Function Test。
- SET 编码只输出 `[0x45, sub]`。
- GET 编码只输出 `[0x45, sub]`。
- RET 解析保留通用 `ret`：
  - `ret == 0` 表示成功。
  - `ret != 0` 表示失败，保留 error code。

RET 数据解析：

- `0x00`：只解析 `ret`。`ret == 0` 表示 RX/TX Connection Normal，其他 ret 表示 Connection Fault。
- `0x01`：解析 `ret + status`。`status == 0x0E` 表示 Function testing；`status == 0x03` 或其他值都按 Normal status 暴露。
- `0x03`：解析 `ret + faultBits + validity`。
  - `faultBits.bit0 == 1`：lamp fault。
  - `faultBits.bit1 == 1`：battery fault。
  - `faultBits.bit2 == 1`：circuit fault。
  - `validity == 0x00`：valid result。
  - `validity == 0x07`：invalid result。

解析长度不足时将 `SunricherVendorStatus.status.isSuccessful` 置为 false，避免 App 把不完整 payload 当成功结果。

## App 设计

入口仍在 `DeviceLightViewController` 的 EL Controller 分支内，不改变 `node.isEmergencySignController` 的既有语义。

`ELControllerFunctionTestView` 从本地循环控件改为外部驱动控件：

- 暴露 action 回调，由 Controller 决定发送哪个 Mesh 命令。
- 暴露状态更新方法，由 Controller 根据 ACK / 上报设置 UI。
- Function Test 状态：
  - idle：提示用户 Start。
  - sending/testing：SET `0x07` 成功前后均显示等待状态；按钮禁用。
  - passed：valid result 且 faultBits 为 0。
  - faults：valid result 且 faultBits 有故障位，按现有三类文案组合展示。
  - invalid：validity 为 `0x07`，展示无效结果提示。
  - failed：SET ACK 失败或 ret 非 0。
- RX/TX 状态：
  - idle：提示用户 Check。
  - checking：GET `0x00` 等待 ACK。
  - normal：ret 为 0。
  - fault：ret 非 0 或 ACK 失败。

Function Test 数据流：

1. 用户点击 Function Test Start。
2. Controller 通过 `node.sunricherVendorModel` 发送 `SunricherVendorSet(function: .startELControllerFunctionTest)`。
3. ACK 成功后保持 testing 状态并禁用按钮。
4. Controller 通过现有 `MeshLibManagerMessageDelegate.didReceiveMessage` 接收 `SunricherVendorStatus`。
5. 仅处理来源为当前 node、response code 为 Function Test Result 的 RET `0x03`。
6. 收到 valid result 后展示 passed 或 fault rows，并恢复按钮。
7. 收到 invalid result 后展示 invalid，并恢复按钮。

RX/TX 数据流：

1. 用户点击 RX/TX Check。
2. Controller 发送 `SunricherVendorGet(function: .elControllerRxTxCableConnection)`。
3. ACK 返回 `ret == 0` 展示 Connection Normal。
4. ACK 返回 `ret != 0`、解析失败或超时，展示 Connection Fault。

## 主动上报监听策略

不使用 `MeshNetworkManager.messages(withOpCode:)` 或长时间 `waitFor` 监听 Function Test 上报。

原因：现有 `MeshAPI.sendMessage` 会为 `SunricherVendorStatus.opCode` 注册一次性 ACK 等待，并会取消同源同 opcode 的 notify callback。长挂同 opcode 监听容易与 SET ACK 互相影响，造成 ACK 或主动上报丢给错误回调。

本轮使用 `DeviceLightViewController` 已经持有的 `MeshLibManagerMessageDelegate` 路径监听全局收到的 Mesh 消息。该路径不参与 ACK callback 注册，不会和 `SET 0x07` 的 ACK 等待冲突。

## 错误处理

- 当前 node 没有 `sunricherVendorModel`：按钮可显示失败状态，不发送消息。
- SET `0x07` ACK 超时或 ret 非 0：Function Test 展示 failed，按钮恢复可点。
- Function Test testing 无设备上报：UI 一直保持 testing，符合已确认方案。
- 离开页面：只恢复 `MeshLibManager.manager.messageDelegate`，不发送 SET `0x08`。
- 收到非当前 node 的 `RET 0x03`：忽略。
- 收到当前 node 但 response code 不匹配：继续走现有 updateData 逻辑，不影响 Function Test UI。
- RX/TX GET 超时、ret 非 0 或解析失败：显示 Connection Fault。

## 测试与验证

SDK 测试：

- SET `0x07` 编码为 payload `[45, 07]`。
- SET `0x08` 编码为 payload `[45, 08]`。
- GET `0x00 / 0x01 / 0x03` 编码为 payload `[45, sub]`。
- RET `0x00`：`45 00 00` 为成功，`45 00 xx` 为失败。
- RET `0x01`：`45 01 00 0E` 解析为 Function testing；`45 01 00 03` 和其他 status 解析为 Normal status。
- RET `0x03`：覆盖 pass、lamp fault、battery fault、circuit fault、组合故障、invalid result、长度不足。

App 验证：

- `0x0A78 / 0x24C1` 页面仍只展示 EL Controller 专用 UI、Relay、Function Test、RX/TX Cable。
- Function Test Start 成功后进入 testing，按钮禁用，且不自动轮询。
- 模拟或真机收到 RET `0x03` 后，Function Test 卡片展示对应 passed / fault / invalid。
- RX/TX Check 根据 ret 显示 Connection Normal 或 Connection Fault。
- 普通 Light、其他 Emergency Sign、EFC 页面不受影响。

构建验证：

使用项目推荐 iPhoneOS 构建命令：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如 SDK 改动影响多个引用 target，应同步检查所有引用 `NordicSigMeshSDK` 的 target。

## 已确认决策

- 使用方案 A：SDK 完整协议建模，App UI 通过现有设备页调用与监听。
- Function Test 使用设备主动上报，不做 App 侧轮询。
- Function Test 不设超时。
- 本轮 UI 不展示 Exit，不自动发送 SET `0x08`。
- GET `0x00` 按 `ret == 0` 判断 Connection Normal，其他 ret 为失败。
