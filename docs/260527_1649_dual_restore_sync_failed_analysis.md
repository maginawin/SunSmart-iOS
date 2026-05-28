# 双设备同时恢复同步失败日志分析

## 结论

本次同步失败提示来自本地恢复流程，不是云端同步接口失败。

失败节点是 `02A0`。它在 deferred restore 阶段的第一个 `ConfigModelPublicationSet` 被判定为未响应：

`[DeviceRestore] Deferred restore task failed node=02A0, result=false, operation=false, response=false, reliableOperation=false, keys=, failed=ConfigModelPublicationSet@02A0[responded=,missing=02A0]`

随后流程虽然继续执行，且 `02A0` 的后续 LightLC、Vendor、Scene、CTL 等任务都有成功回包，但 `finishDeferredRestore` 已经记录 `hadFailedTask`，最终将该设备标记为 `syncFailed`：

`[DeviceRestore] Mark sync failed for node=02A0, deferred task failed`

后面再次出现：

`[DeviceRestore] Mark sync failed for node=02A0, sync=profile(1)`

这是第一个 publication 任务失败留下的 profile sync 未清干净导致的后续判定。

## 关键证据

两台设备几乎同时完成配网：

- `02A0`：原始恢复快照 `0261`，新地址 `02A0`
- `02A3`：原始恢复快照 `0295`，新地址 `02A3`

两台设备都进入 deferred restore：

- `02A0`：`tasks=19, sync=profile(19),syncScenes(1)`
- `02A3`：`tasks=19, sync=profile(19),syncScenes(1)`

在 deferred restore 前发生了连接切换和代理重连：

- `XPC connection invalid`
- `Central Manager state changed to .poweredOn`
- `Connected to SR Dongle`
- `GATT Bearer open and ready`
- `New Proxy connected`
- `SetFilterType(Accept List)`
- `AddAddressesToFilter`
- `白名单配置成功`

紧接着 `02A0` 的 deferred task 被判失败，失败 handle 显示 `missing=02A0`，说明命令层没有把 `02A0` 计入响应。

而 `02A3` 的同类 Publication 任务稍后实际发送并收到成功回包：

`ConfigModelPublicationStatus(... status: Success) source:675`

因此只有 `02A0` 被标记同步失败。

## 根因判断

两个设备同时恢复时，配置/恢复命令在同一个 Mesh 命令通道上交错执行。`02A0` 先进入 deferred restore，刚好撞上 Proxy/GATT 重连和白名单重配窗口，`ConfigModelPublicationSet` 没有拿到命令层认可的响应，于是 `MeshProxyMessageCommand` 将该 handle 标成 `notRespond`。

当前代码的判定链路是：

- `MeshMessageHandle.isSuccessful` 只看 `respondAddresss.count == allAddresss.count`
- 失败时 `notRespondAddresss = allAddresss.filter { !respondAddresss.contains($0) }`
- 本次 `02A0` 的 failed handle 是 `responded=,missing=02A0`
- `operation=false`
- `response=false`
- `reliableOperation=false`

所以 deferred task 无法被兜底判成功，只能进入失败分支。

日志中还出现了两次：

`SWIFT TASK CONTINUATION MISUSE: send(_:from:to:withTtl:) leaked its continuation without resuming it.`

这说明 SDK 的 async send 在取消、断连或回调清理路径上仍有 continuation 没有 resume。它会让等待发送结果的任务悬挂，也会放大双设备并发恢复时的命令超时和响应归属问题。

## 排除项

这不是设备整体离线。

`02A0` 后续能正常返回：

- `LightLightnessRangeStatus(status: Success)`
- `LightLCModeStatus(controllerStatus: true)`
- `SunricherVendorStatus(... isSuccessful: true)`
- `LightCTLDefaultStatus`
- `GenericOnPowerUpStatus`
- `LightCTLStatus`
- `SceneRegisterStatus(status: Success)`

这不是云同步接口失败。

云端同步最终返回：

`[CloudSync][Success] operation=syncSite`

这也不是 BPS 订阅匹配失败。

后续订阅匹配日志显示：

- `02A0`：`matched=02A0/1000,02A0/1002,02A0/1300,02A2/130F`
- `02A3`：`matched=02A3/1000,02A3/1002,02A3/1300,02A5/130F`

## 与单设备隐藏问题的区别

之前单设备问题中，失败 handle 后面仍能被可靠状态或成功 response 兜底：

- handle 可能 false
- 但 operation 或 reliable state 能证明最终成功

这次 `02A0` 是：

- `operation=false`
- `response=false`
- `reliableOperation=false`

也就是说命令层没有拿到 `ConfigModelPublicationSet` 的有效完成证据，现有兜底逻辑不会把它判成功。

## 建议方向

1. 先确认 SDK 的 continuation cancel 修复已经进入当前 App 实际使用的 `NordicSigMeshSDK` 依赖，并用双设备同时恢复复测。
2. deferred restore 开始前，等待 Proxy ready 和白名单配置完成，避免在重连窗口立即发送第一条配置命令。
3. 双设备恢复时避免多个设备的恢复任务在同一个 `MeshProxyMessageCommand.shared` 上并发插队，至少把 deferred restore 串行化到命令层完全 idle 后再开始下一台。
4. 对 `ConfigModelPublicationSet` 增加一次 retry 或 publication 状态复查，避免一次连接窗口里的 missed response 直接把设备永久标为 `syncFailed`。
5. 继续检查 `MeshProxyMessageCommand.shared` 的回调覆盖和队列插入行为。它在已有发送队列时会追加新 handles，并替换 `progressBack/sendSuccessfulBack/sendFailedBack/finishedBack`，双设备并发恢复时存在响应归属和完成回调被覆盖的风险。
