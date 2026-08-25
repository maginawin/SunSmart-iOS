# Calibration 审查问题修复规划

## 1. 结论

本轮三条审查意见均成立，建议按 P2 等待取消、P1 Lightness Range、P1 publish-delta 终态收敛的顺序实施，并在每一步先建立可复现回归测试。

本轮只修复审查指出的三个行为问题，不调整校准产品规则、不重构整套校准状态机、不修改 UI 文案，也不改 Swift Package 引用方式。

当前 App 与 SDK 工作树都已有未提交改动。实施时必须在现有增量上做最小修改，不得重置或覆盖；SDK 中 Mesh 接收元数据、Replay Protection 诊断等改动与校准改动交织，最终需要按文件和 diff hunk 复核，避免把无关诊断代码纳入校准修复。

## 2. 问题一：按每台灯具的 Lightness Range 校验到位值

### 2.1 根因

当前 Group 控制发送的是统一的原始 Lightness，但 `verifyLightNode` 对每台灯具都继续用该原始值校验 `LightLightnessStatus`。

灯具对非零 Lightness 会按自己的 `lightnessRange` 做截断。因此：

- 请求值高于 High End Trim 时，正确的 Present/Target Lightness 应等于该灯具的 range 上限；
- 非零请求值低于 Low End Trim 时，正确值应等于该灯具的 range 下限；
- 请求 0 表示 Off，必须保持 0，不能被 Low End Trim 抬高；
- 不同灯具可以拥有不同 range，所以不能计算一个 Group 级统一期望值。

### 2.2 修复设计

在 `MeshSensorCalibrateManager` 增加一个可单测的“有效期望 Lightness”纯函数：

1. 请求值为 0 时返回 0；
2. 请求值非零时，限制到当前节点 `lightnessRange` 的闭区间内；
3. `verifyLightNode` 在每个节点开始校验时计算一次节点级期望值；
4. Present Lightness 与可选 Target Lightness 都和该期望值比较，继续沿用现有 transition-complete 与 tolerance 规则；
5. Group Unack 下发及单灯 acknowledged 补偿仍发送原始请求值，让设备按自身 range 执行；不在 App 侧改写下发语义；
6. 日志同时记录 requested、expected、range、present、target、attempt，便于区分设备正确截断与真正未到位。

`LightnessLuxData.lightness`、拐点搜索百分比和 `lastConfirmedLightness` 继续保留 Group 原始请求值。原因是一组灯具可能有不同 range，校准曲线横轴表达的是 Group 控制输入，不存在可替代它的单一“实际 Lightness”。本轮只修正逐灯到位判断，不改变 `0x38` 曲线的数据域。

### 2.3 回归测试

扩展 `SensorCalibrateMathTests`，至少覆盖：

- 默认 range 下原始值不变；
- High End Trim 小于 100% 时，100% 请求以 range 上限为期望并通过；
- Low End Trim 大于 0 时，低亮度非零请求以 range 下限为期望并通过；
- Low End Trim 大于 0 时，0 请求仍以 0 为期望；
- Present 到位但 Target 未到位、transition 未结束、超过 tolerance 时仍失败；
- 两台 range 不同的节点分别使用自己的期望值，不共享计算结果。

同时扩展 App 侧 Sensor calibration 源码契约，防止后续又直接用 requested Lightness 校验所有节点。

## 3. 问题二：publish-delta 恢复由单一路径管理终态

### 3.1 根因

当前恢复流程同时存在两套结束机制：

- `setSensorPublishDelta` 最多执行 3 次，每次 ACK 默认最多等待 10 秒，两次间隔各 0.5 秒，名义预算约 31 秒；
- `restoreSensorPublishDelta` 另启 30 秒 `BackgroundTimer`。

30 秒 timer 会在第三次 ACK 尚未结束时先将错误写成 `noResponse` 并启动回滚。随后原 Task 仍可能写入 `publishDeltaRestoreFailed`、再次触发失败或继续成功回调，形成错误覆盖、并发回滚和等待取消竞态。

### 3.2 修复设计

采用“单一异步所有者”方案，不通过简单把 30 秒改成更大的魔法数字规避竞态：

1. 进入 `restoreSensorPublishDelta` 时先停止上一阶段的 timer；
2. 此阶段不再启动独立 `BackgroundTimer`；
3. 显式集中定义单次响应 timeout、重试次数和重试间隔，并将响应 timeout 传给每次 `sendMessage`，使每次等待自身有界；
4. 唯一的恢复 Task 顺序执行 ACK 校验和重试；成功时才调用成功回调并 reset，耗尽重试时才写入 `publishDeltaRestoreFailed` 并进入失败回滚；
5. 首轮 3 次恢复全部结束后才能启动回滚中的再次恢复，因此两组发送不得重叠；
6. 所有终态回调都在主线程执行，并保持每轮最多一次成功或失败回调。

错误语义保持现有事务边界：

- 首轮 publish-delta 恢复失败、随后旧校准和 cleanup 均恢复成功时，最终报告 `publishDeltaRestoreFailed`；
- 回滚阶段仍无法完整恢复旧校准、Publication 或 publish delta 时，最终报告更严重的 `calibrationRollbackFailed`；
- 不再允许阶段 timer 把上述错误提前覆盖成 `noResponse`。

本轮不为整个 Manager 引入新的全局状态机。若保留任何外层 deadline，则必须能够取消并等待当前恢复 Task 结束后再进入回滚；默认方案是不在这一阶段保留第二个 deadline。

### 3.3 回归测试

建立可注入响应与等待的轻量测试缝，避免测试真实等待 31 秒，覆盖：

- 第一次 ACK 成功，只发送一次并只完成一次；
- 前两次超时、第三次成功，严格发送三次且不触发失败；
- 三次均超时，只有耗尽第三次后才产生 `publishDeltaRestoreFailed`；
- 响应 opcode 不匹配或 status 失败均按失败重试；
- 首轮失败后，回滚恢复发送只能在首轮 Task 返回后开始，不存在重叠在途等待；
- 成功、首轮恢复失败、回滚失败三种路径都只有一个终态回调。

App 侧源码契约同步检查：恢复函数先停止旧 timer、不再启动固定 30 秒 timer、每次 ACK 使用显式 timeout、重试次数仍为 3、错误分类保持上述边界。

## 4. 问题三：取消旧元数据等待时必须恢复 continuation

### 4.1 根因

`sendMessageWithReceiveMetadata` 注册新等待前会调用 `cancelNotifyCallback`。该方法当前从 `messageCallbacks` 移除匹配项，却不调用被移除的 callback。旧 `waitForMessageWithMetadata` 的 checked continuation 因此失去唯一恢复入口；其 timeout 之后也找不到 callback，调用方会永久挂起。

### 4.2 修复设计

保留 SDK 现有“同一来源和 response opcode 的新发送可替代旧等待”语义，但补齐取消契约：

1. `cancelNotifyCallback` 在 mutex 内原子查找并移除匹配 callback；
2. 将被移除的 callback 暂存，在 mutex 外以 `AccessError.cancelled` 完成；
3. 对该方法同时移除的 response callback 也遵循“凡移除必完成”原则，避免另一类 continuation 泄漏；
4. 保持现有 outgoing message 清理范围，不扩大到无关 source/opcode；
5. timeout、收到响应和主动取消继续通过同一个互斥保护的“取出一次”规则竞争，确保 callback 至多执行一次；
6. `sendMessageWithReceiveMetadata` 无需静默吞掉旧等待，新调用继续注册并发送，旧调用稳定收到取消结果。

选择显式取消而不是 busy 的原因是：现有普通 `sendMessage` 已采用“先取消旧等待再注册”的替代语义。本轮保持 API 行为一致，只修复被替代调用方无法结束的问题。若实施时发现某个调用方要求并存，则应单独设计 destination/request identity，不在本轮用静默覆盖解决。

### 4.3 回归测试

扩展 `NetworkManagerReceiveMetadataTests`，至少覆盖：

- 同 source/opcode 的旧 metadata waiter 被替代时收到 cancelled，且 callback 列表清空；
- 旧 callback 完成后可以立即注册新 callback，新 callback 能收到 message、source、destination 和 TTL；
- 不同 source 或不同 opcode 的等待不被取消；
- 取消 callback 在 mutex 外执行，可在 callback 内再次访问 Manager 而不死锁；
- 主动取消与 timeout/响应竞争时只完成一次；
- `cancelAllNotifyCallback` 的既有取消行为不回退。

同时审计 `cancelNotifyCallback` 的全部调用点，确认没有调用方依赖“移除后永不回调”的错误行为。

## 5. 实施顺序

1. 先为三类缺陷分别补充 RED 测试或源码契约，确认当前实现能够被稳定捕获。
2. 修复 `cancelNotifyCallback` 的完成语义，先消除可能影响后续 ACK 重试的 continuation 泄漏。
3. 增加节点级有效 Lightness 计算并接入逐灯校验，保持发送值和曲线横轴不变。
4. 将 publish-delta 恢复改为单一异步所有者，移除竞争 timer，并锁定错误优先级。
5. 运行聚焦测试、源码契约、语法检查和 diff 检查。
6. 使用当前本地 SDK 引用，串行验证 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 iphoneos Debug target，使用 generic iOS device 且关闭签名；不使用 Simulator 替代。
7. 最后逐 hunk 复核 App 与 SDK diff，确认未覆盖现有未提交改动，也未混入无关格式化、资源、target、依赖或本地化变化。

## 6. 自动化验收标准

- Lightness Range 的上下限和 Off 特例测试通过；默认 range 行为不回退。
- publish-delta 三次超时不再被 30 秒 timer 抢先终止，不存在并发 rollback，错误分类稳定。
- 被替代的 metadata waiter 必须在有限时间内以取消结束，不存在悬挂 continuation。
- 现有 TTL 元数据传递、source/destination/opcode 匹配测试继续通过。
- Sensor、Night 和持久化相关现有契约继续通过。
- 两个仓库的 `git diff --check` 通过。
- 四个共享 App target 均能链接当前本地 SDK 并完成 iphoneos 构建。

由于 SDK Package 在 macOS SwiftPM 环境会遇到 UIKit，不把普通 macOS `swift test` 作为唯一通过凭据；新增 XCTest 需要在可用的 iOS 测试环境补跑，当前开发验证至少执行测试源码语法检查，并由确定性源码契约与四 target 构建补强。

## 7. 真机验收边界

自动化和构建不能证明真实 Mesh 时序，修复后仍需真机覆盖：

- 同一 Group 内混合默认 range、High End Trim 和 Low End Trim 灯具，分别验证 0%、低亮度搜索点和 100% 采样；
- 灯具正确截断时继续校准，真正离线、无响应、transition 未结束或状态超容差时仍报告必要灯具不可用；
- publish-delta 第一次/第二次失败后成功、三次全超时、错误 opcode、失败 status，以及失败后的旧校准与 Publication 回滚；
- 并发触发同 source/opcode 元数据请求，确认旧请求收到取消、新请求正常返回，长时间观察无悬挂任务；
- 使用 Mesh 日志确认 publish-delta 首轮恢复与 rollback 恢复严格串行，没有互相取消 callback。

## 8. 明确不在本轮范围

- 不重新查询或重新配置灯具 Lightness Range，只使用当前 Node 已持久化/同步的 range；
- 不改变 Group Unack 加逐灯 acknowledged 校验的总体策略；
- 不改变 `0x38`/`0x39` 校准数学、目标 Lux 95% 规则、稳定窗口参数和 Auto 恢复策略；
- 不修改 UI、用户可见文案或本地化；
- 不调整 SDK 依赖地址、Package.resolved、target 配置或资源；
- 不顺带重构普通 `sendMessage` 的全部并发模型；仅保证本次实际移除的等待都有确定终态。
