# Sync Gateways 时区同步成功后的蓝牙断开分析

## 结论

当前实现满足“Gateway timezone 同步成功后，App 主动断开与该 Gateway 的蓝牙 Proxy 连接”的预期。

准确时序是：收到并校验 `TimeStatus` 成功 → 更新并保存本地 Node 时间数据 → 入队 Gateway 云同步 → 主动断开目标 Proxy → 更新页面成功状态、显示成功 Toast → 恢复页面 RSSI 扫描。

这里的“成功”是 Device sync 成功，即有效 `TimeStatus` 且本地 `Node.savePropertys()` 成功；不等待后续 Gateway 云上传成功。

## 当前成功路径证据

1. `GatewayTimeSyncCoordinator.settle(...)` 校验返回的时间不为零且 timezone offset 与目标值一致。
2. 校验成功后，将响应中的 `timestamp` 和 `timezone` 写入 Node，并要求 `savePropertys()` 成功。
3. 本地保存成功后先调用 `onPersistedSuccess`，触发 GatewayModel dirty generation 与异步 `.syncGateway`。
4. 随后调用 `finishRuntimeAttempt(..., result: .success)`。
5. `finishRuntimeAttempt` 无论成功或失败，都会对本次 Runtime Target 的 Node 调用 `MeshLibManager.manager.disconnectProxy(node:)`。
6. 发起断开请求后，才触发页面的 `onUISettlement` 与 `onAttemptEnded`；后者恢复 RSSI 扫描。实际 GATT 断开完成是 CoreBluetooth 的异步结果。

相关位置：

- `SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift:252-297`
- `SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift:312-329`
- `SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift:187-196`
- `SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift:301-338`

## SDK 断开是否真正落到 CoreBluetooth

当前 Xcode 工程的四个 App target 都引用本地 `NordicSigMeshSDK`：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。

SDK 调用链为：

1. `MeshLibManager.disconnectProxy(node:)` 转发到 `NetworkConnection.disconnect(node:)`。
2. `NetworkConnection.disconnect(node:)` 按 Node 的 primary unicast address 找到对应 GATT bearer，并调用 bearer 的 `close()`。
3. `BaseGattProxyBearer.close()` 在 Peripheral 为 connected 或 connecting 时调用 `CBCentralManager.cancelPeripheralConnection(...)`。

因此，这不是只清理 App 状态，而是会向 CoreBluetooth 发起实际的连接取消请求。

相关位置：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:481-484`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshNetwork/NetworkConnection.swift:179-190`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Bearer/GATT/BaseGattProxyBearer.swift:149-156`

## 其他终态

当前断开并非只覆盖成功：

- 连接失败、缺少 Time Setup Model、无效或缺失 `TimeStatus`、超时、本地保存失败：均通过 `finishRuntimeAttempt` 主动断开。
- 页面在 Time Set 发送前退出：`finishPage()` 主动断开。
- 页面在 Time Set 发送后退出：保留已发送事务等待响应或超时；事务最终收敛时仍会主动断开，但不再更新已关闭页面的 UI。
- App 在连接阶段进入后台：主动断开；Time Set 已发送后进入后台则等待事务收敛后断开。

## 需要区分的运行时边界

`disconnectProxy(node:)` 可以确认 App 主动发起了断开，但静态源码不能证明真机在任意观察时刻都保持 disconnected。

SDK 的 `NetworkConnection` 在已经启动且自动连接模式开启时，目标 Proxy 断开后会恢复 Mesh Proxy 扫描。它可能随后自动连接到某个 Proxy，极端情况下也可能再次连接到同一 Gateway。因此，如果真机现象是“成功后仍看到 Gateway connected”，需要用连接日志或 CoreBluetooth 状态区分：

- 根本没有执行断开；
- 已执行断开，但 CoreBluetooth 的异步断开尚未完成；
- 已断开，随后被 SDK 自动 Proxy 机制重新连接。

## 测试与结论边界

已运行 `./scripts/check_site_sync_gateways.sh`，所有 Sync Gateways 聚焦检查通过，包括 `GatewayTimeSyncCoordinatorTests` 与 `SyncGatewaysUIContractTests`。

现有测试覆盖 attempt 状态机与源码集成，但没有通过可注入的 transport spy 直接断言“成功终态恰好调用一次 disconnect”。所以当前结论是源码调用链确认，不是真机 BLE 验收结果。

## 建议

当前业务代码无需为“成功后主动断开”再补一处断开调用，否则可能造成重复断开。若真机仍表现为持续连接，下一步应先采集同步成功前后的 Proxy/GATT 连接日志，重点确认断开调用、CoreBluetooth didDisconnect 回调以及自动重连三者的时间顺序，再决定是否需要限制本页面完成后的自动重连。
