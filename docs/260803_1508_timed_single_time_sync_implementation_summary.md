# Timed 单次时间同步方案 A 实现总结

## 结论

方案 A 已完成代码实现与静态验证。Timed 日程同步不再为同一设备的每个日程分别生成 `Time Set`，而是按“单设备、单次同步批次”最多生成一个独立时间同步任务。

时间消息在真正从 Mesh 发送队列取出、准备发送时重新生成，因此使用发送时刻的本地时间，避免任务提前创建和排队造成时间参数陈旧。

## 最终行为规则

| 场景 | 单设备生成的 Time Set 数量 |
| --- | ---: |
| 16 个启用日程 | 1 |
| 16 个停用日程 | 0 |
| 启用与停用日程混合 | 1 |
| 设备没有 Time Model | 0 |
| 删除日程或清理 Scheduler Entry | 0 |

启用日程依赖时间同步成功；时间同步失败时，这些启用日程不会继续写入。停用日程不依赖时间同步，即使时间同步失败仍可以执行清理。一个设备失败不会阻止后续设备批次，但最终结果会聚合为失败，供界面显示和重试。

## 实现范围

### App

- 新增统一的 Timed 时间同步策略，集中判断设备能力、日程启用状态和依赖关系。
- 将时间同步从单个日程消息列表中拆出，作为独立任务执行。
- Sync Devices、Deferred Sync、Fast Add、Restore、Node/Group 历史同步和 Schedule 保存入口统一采用每设备最多一次时间同步。
- Restore 重试按消息语义定位失败项，不依赖重新生成后可能变化的数组下标。
- 新增英文 `Sync Time` 和简体中文 `同步时间` 文案，并检查四个品牌 target 的资源引用。

### NordicSigMeshSDK

- `MeshMessageHandle` 支持发送前动态生成消息，同时保留原有固定消息初始化方式。
- 普通队列和 Fast Add 队列均在真正发送前刷新动态消息。
- Time Set 句柄改为动态消息工厂，排队和 busy 重入后会重新取得当前时间。

## 验证结果

以下聚焦验证全部通过：

- Timed 时间同步策略测试。
- Timed Scheduler 单一 Owner 与入口契约测试。
- Timed Scheduler 持久化与读取完成测试。
- Fast Add checkpoint、单一 Owner 与双 Scene 验证测试。
- Device Restore 候选设备与 EFC 恢复测试。
- SDK 动态值刷新独立测试。
- App 与 SDK `git diff --check`。
- Xcode 工程文件以及英文、简体中文本地化文件格式检查。

以下 target 均使用通用 iPhoneOS、关闭签名方式构建成功：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart
- NordicSigMeshSDK

## 验收边界

当前结论覆盖源码、聚焦契约和通用 iPhoneOS 构建，不等同于真实 Mesh 设备验收。仍需使用真实设备重点验证：

1. 两个组都关联 16 个日程，设备先加入组 1，再删除组 1并加入组 2后，只执行组 2 日程。
2. 16 个启用日程同步时，每台设备只出现一次 Time Set，且时间接近实际发送时刻。
3. Time Set 失败时，启用日程被阻断、停用日程清理继续执行、后续设备继续处理。
4. App 退出、Mesh busy、断连重连和失败重试后，时间消息仍使用重试发送时刻的时间。

本次未改造“删除组”的数据事务本身，也未增加 Time Get 回读校验。设备端可接受的时间误差范围仍需结合固件要求在真机验收时确认。

## 版本控制状态

本次没有执行 Git commit、push 或 merge。App 与本地 NordicSigMeshSDK 是两个独立仓库，改动分别保留在各自工作区中。
