# 单灯恢复新日志隐藏问题分析

## 结论

本次恢复主流程未再展示失败，且 deferred restore 后继续执行后续 profile、scene store，并最终触发 `CloudSync Success`。这说明恢复页面状态已经被修正，没有再把设备标成同步失败。

但日志仍显示两个隐藏问题：

1. `ConfigModelPublicationSet` 已收到 `ConfigModelPublicationStatus(status: Success)`，但 deferred runner 仍打印 `response=false, keys=`。
2. 多次出现 `SWIFT TASK CONTINUATION MISUSE: send(_:from:to:withTtl:) leaked its continuation without resuming it`。

## 关键证据

- 成功回包已到达：
  - `message:ConfigModelPublicationStatus(... status: Success) source:658 destination:0x0001`
- deferred runner 没有记录到成功响应：
  - `[DeviceRestore] Ignore deferred handle false node=0292, operation=true, response=false, reliableOperation=true, keys=, failed=ConfigModelPublicationSet@0292[responded=,missing=0292]`
- 页面未失败是因为可靠后置状态兜底生效：
  - `operation=true`
  - `reliableOperation=true`
- 最终云同步成功：
  - `[CloudSync][Success] operation=syncSite ...`

## 根因判断

`MeshProxyMessageCommand` 的命令级超时仍可能早于分包回包完成。超时后它会把当前 handle 标为 `notRespond`，后续 `matchesResponse` 又要求 `!isFinished`，因此迟到的成功分包回包虽然被 SDK 网络层解析并打印，但不会再进入 command 的 `successfulBack`。

这就是为什么日志中同时存在：

- SDK 层：`ConfigModelPublicationStatus Success`
- deferred runner：`response=false, keys=`

当前 UI 没失败，是因为新增的 `operationType.isSuccessful` 后置状态兜底正确识别设备实际状态。但这仍然是一个隐藏一致性问题：本地 command 结果和实际 Mesh 回包状态不一致。

## 影响

- 当前这条恢复链路没有用户可见失败。
- `ConfigModelPublicationSet` 这类分包 status 仍容易被 command 超时误判。
- 如果某些任务没有可靠后置状态兜底，仍可能再次出现“设备已执行但本地判失败”。
- continuation 泄漏属于 SDK 层取消路径问题，可能导致 async 等待任务挂起，需要单独修复。

## 后续修复建议

1. 在 deferred restore 中，对已被后置状态确认成功的 failed handle，也按成功更新本地缓存，避免本地 sync state 被旧的 handle 失败污染。
2. 调整 deferred restore 的 acknowledged timeout，至少覆盖分包 status 的 SAR 完成时间。
3. 修复 `MeshProxyMessageCommand` 或 SDK response callback：允许迟到但匹配的成功回包恢复 handle，或不要在分包响应未完整前过早标记失败。
4. 修复 `NetworkManager` async send 的取消路径：取消时必须移除并 resume 对应 continuation，避免 `SWIFT TASK CONTINUATION MISUSE`。
