# 恢复命令失败重试范围分析与开发规划

## 结论

需求合理，但不建议做成 Mesh 命令层的全局重试。更合适的范围是在 `DeviceRestoreViewController` 的 deferred restore 普通恢复任务层增加一次失败重试，并继续排除 battery power switch 的专项恢复链路。

理由：

- 这次问题的根因是恢复阶段单个 acknowledged message 在连接重建或代理过滤窗口内漏响应，设备本身后续仍可通信。
- deferred restore 本来就是恢复完成后的补配置阶段，命令大多是幂等或可被状态回包确认的配置类操作。
- battery power switch 已有独立恢复配置、link group、target subscription、初始电量读取与失败标记路径，不应被普通 retry 策略混入。
- 如果在 SDK 的 `MeshProxyMessageCommand` 全局重试，会影响添加、控制、参数、网关、固件等所有调用方，风险过大。

## 适用范围

适合增加一次失败重试的范围：

- deferred restore 中的普通设备恢复任务。
- 当前由 `deferredRestoreTasks(syncDatas:node:)` 生成的非空 task。
- 已过滤 `SceneRecall` 后剩余的恢复命令。
- 非 battery power switch 的 switch restore、profile restore、scene/schedule/collection schedule restore、EnOcean switch/proxy restore。

不纳入本次通用重试的范围：

- battery power switch 专项配置命令。
- `SceneRecall`，当前已经被过滤，不参与恢复重放。
- 首次配网、AppKey bind、model bind、基础添加流程中的非 deferred 命令。
- SDK 全局 `MeshProxyMessageCommand`。

## 当前代码状态

当前已有一次 narrow retry：

- 只针对 `ConfigModelPublicationSet`。
- 只在没有成功 response、handle 有 missing address 时重试。
- 重试前清空 `respondAddresss` 与 `notRespondAddresss`。
- 重试仍失败时保留原失败路径，最终标记同步失败。

这个实现能覆盖日志里的 `ConfigModelPublicationSet@02A0[responded=,missing=02A0]`，但还不能覆盖其他 deferred restore 命令的同类漏响应。

## 推荐方案

将 narrow retry 扩展为 deferred restore task 通用一次重试，并保留必要保护条件：

- 每个 task 最多重试一次。
- 仅在当前 task 被判定失败时触发。
- 仅当未被 response tracker 记录成功的 failed handles 全部是 acknowledged message 且存在 missing address 时触发。
- 对已经成功或已由 response tracker 证明成功的 handles 不重发；仅对仍 missing response 的 failed handles 重试。
- 若 operation type 已经能通过可靠本地状态校验恢复成功，则不重试。
- 重试前只清空 failed handles 的 response 状态。
- 重试仍失败时，维持原逻辑：更新本地 node sync 状态并最终标记 sync failed。

这个方案比“所有 Mesh 消息全局重试”更安全，比“只重试 publication”覆盖面更完整。

## 风险分析

主要风险是重复发送带副作用的命令。当前 deferred restore 中风险较低，但仍要控制边界：

- 配置类 set 命令通常是幂等的，重复发送同值影响可接受；实现上只重发 failed handles，避免重复发送已经成功的配置命令。
- scene store 可能重复存储同一 scene，但 restore 场景下目标值相同，且只在该 handle 未收到响应时重试一次，风险可接受。
- schedule、collection schedule、profile 配置重复发送同一配置，风险可接受。
- delete 类恢复命令可能重复 delete；如果设备返回成功或 already absent 类状态，需要依赖现有 status 判断。当前计划只重试一次，避免放大副作用。
- 不对 SceneRecall 重试，因为 recall 是执行动作，不是配置状态同步。
- 不对 BPS 专项链路重试，因为它有独立状态与后续电量读取流程。

## 开发规划

### 1. 抽象重试判定

修改 `DeviceRestoreViewController.swift` 中现有 `shouldRetryDeferredRestoreTask`，从仅判断 `ConfigModelPublicationSet` 扩展为普通 deferred restore command 判定。

判定输入保留：

- failed handles
- response tracker
- retry count
- task operation type

判定输出：

- true：该 task 可重试一次。
- false：进入现有失败或 recovery 路径。

### 2. 明确排除类型

在 retry 判定中显式排除：

- `SceneRecall`
- battery power switch 相关恢复配置 message

虽然 deferred task 当前已经过滤了这些类型，仍建议保留防御式排除，避免后续扩展把高风险命令带入通用 retry。

### 3. 保留恢复优先级

处理顺序保持为：

1. 先根据 result、operation、response tracker、可靠 operation state 判断 task 是否已经成功。
2. 只有 task 仍失败时才考虑 retry。
3. retry 只重发 failed handles，retry 仍失败后再更新 node sync 数据。

这样不会把已经通过本地状态确认成功的命令重复发送。

### 4. 增强调试日志

保留并扩展当前 retry 日志：

- node address
- retry count
- operation description
- failed handle description

这样下次日志可以直接判断是“重试后成功”还是“重试后仍失败”。

### 5. 文档同步

更新现有修复说明文档，说明 retry 范围从 publication 扩展到普通 deferred restore command，并记录排除 BPS 与 SceneRecall 的原因。

## 验证计划

必须执行：

- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

建议同步执行：

- `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

手工回归重点：

- 两个普通设备同时恢复，确认不会因单次 missing response 直接 sync failed。
- 一个普通设备恢复时断开/重连代理，确认最多重试一次，不无限等待。
- battery power switch 恢复，确认仍走原专项恢复路径。
- Scene recall-only restore task 仍被跳过。

## 建议执行

建议按上述方案执行。实现范围小，风险主要由“一次重试”和 deferred restore 层边界控制住；同时能覆盖这次日志暴露出的同类漏响应问题，而不会把所有 Mesh 命令全局改成自动重发。
