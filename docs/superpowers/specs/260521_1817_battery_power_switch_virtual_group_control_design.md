# Battery Power Switch 虚拟组控制设计

## 背景

Battery Power Switch 已经在设备监控页中间展示 8 个按钮。页面当前只完成了展示和部分长按弹窗能力，真实单击控制还没有覆盖完整 8 个按钮：

- Scene Profile：4 个 Scene 按钮、Dim Up、Dim Down、ON、OFF。
- Brightness Profile：100%、75%、50%、25%、Dim Up、Dim Down、ON、OFF。
- Dim Up / Dim Down 长按已能弹出亮度控制条。
- ON 长按已能弹出 AUTO 控制弹窗。
- 亮度弹窗与 AUTO 弹窗当前偏 UI 展示，还需要接入真实 Mesh 命令发送。

本设计的目标是让 App 在 BPS 设备页模拟真实 Battery Power Switch 对 target groups 的控制行为：App 不直接遍历 target groups，而是向 BPS 自身的虚拟地址发送同类控制命令，让已经订阅该虚拟地址的目标设备或组响应。

## 已确认需求

- 单击 8 个中间按钮时，向 Battery Power Switch 的虚拟地址发送对应功能命令。
- 即使没有配置 target groups，也允许发送命令；无目标响应是正常结果。
- Scene Profile 的 4 个 scene 按钮也参与单击发送。
- scene key 未配置 scene number 时静默忽略，不提示、不发送。
- 亮度弹窗只在拖动结束时发送最终亮度，不在拖动过程中连续组播。
- ON 长按弹窗里的 AUTO 点击后发送一次 AUTO 命令。
- AUTO 命令与组页面 AUTO 按钮语义一致。
- 不做 App 层重发。一次用户操作对应一次 Mesh 发送。
- 同一个按钮 200ms 内只响应一次单击发送；不同按钮之间不互相限流。

## 非目标

- 不修改 Battery Power Switch 配置同步流程。
- 不修改 target group subscription / unsubscription 逻辑。
- 不修改 SDK。
- 不改普通 EnOcean Switch 页面。
- 不新增 ACK 成功态、失败弹窗或重试 UI。
- 不主动更新 target groups 的本地灯状态；若 SDK 的本地 loopback 或现有消息处理已经更新状态，则沿用现有行为。

## 方案选择

采用“单发 + 同按钮 200ms 限流”方案。

不采用 App 层重发的原因是，当前 SDK 每次重新发送都会重新进入 Access / Network layer，sequence number 会变化；多数 TransactionMessage 还会重新分配 TID。对于绝对亮度、ON、OFF、AUTO 这类目标状态命令，重复发送通常结果可接受，但语义上仍是第二次真实 Mesh 操作。对于 dim up/down 这类增量命令，重复发送会直接造成亮度变化异常。因此本期统一取消 App 层重发，让用户在未生效时自行再点一次。

不采用全局 200ms 限流的原因是，不同按钮之间快速操作不应互相过滤。例如用户先点 ON 再点 AUTO，或点亮度后立即点 OFF，这些都是有效意图。限流只作用于同一个按钮。

## 命令映射

所有命令发送目标均为 `switchData.linkGroupAddress`。若该虚拟地址不存在，发送层静默忽略，不弹提示；正常 BPS 数据应在创建和保存时确保虚拟地址存在。

- Scene 1-4：发送 `SceneRecallUnacknowledged(sceneNumber)`。
- Brightness 100 / 75 / 50 / 25：发送 `LightLightnessSetUnacknowledged`，亮度值由 `Node.getLightness(lightness100:)` 转换。
- Dim Up：发送 `GenericDeltaSetUnacknowledged`，delta 为 `+13107`。
- Dim Down：发送 `GenericDeltaSetUnacknowledged`，delta 为 `-13107`。
- ON：发送 `GenericOnOffSetUnacknowledged(true)`。
- OFF：发送 `GenericOnOffSetUnacknowledged(false)`。
- AUTO：发送 `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)`，与组页 AUTO 一致。
- 亮度弹窗：拖动结束时发送 `LightLightnessSetUnacknowledged`，亮度值来自最终 slider value。

Scene 未配置 scene number 时不构造命令。

## 交互设计

设备页 enabled 状态下：

1. 用户单击某个 key。
2. 页面判断该 key 是否命中同按钮 200ms 限流。
3. 若被限流，静默忽略。
4. 若未限流，按当前 panel type 和 key index 解析控制动作。
5. sender 生成对应 Mesh message，并调用 `MeshAPI.sendMessage(message:address:)`。

设备页 disabled 状态下：

- 沿用现有 disabled 提示。
- 不发送控制命令。

Dim Up / Dim Down 长按：

- 保留当前长按弹出亮度控制条。
- 弹窗打开本身不发送命令。
- slider 拖动过程中不发送命令。
- slider 结束时发送一次最终亮度命令。

ON 长按：

- 保留当前长按弹出 AUTO 弹窗。
- 点击 AUTO 时发送一次 AUTO 命令。
- AUTO 弹窗可沿用现有 loading UI，短暂展示发送中状态后恢复，不等待 ACK。

## 实现结构

新增一个小的控制发送单元，例如 `PJEightKeySwitchVirtualGroupControlSender`。它负责：

- 读取 BPS 虚拟地址。
- 根据 panel type、key index、scene 数据和 slider value 构造控制命令。
- 调用 `MeshAPI.sendMessage(message:address:)`。

UI 侧调整：

- `PJEightKeySwitchMonitorKeyView` 保留当前长按识别，补齐所有 enabled key 的 tap 能力。
- `PJEightKeySwitchMonitorPanelView` 增加 key tap 回调，并继续保留 dimming 和 ON 的长按回调。
- `PJEightKeySwitchMonitorVC` 统一处理 key tap，维护同按钮 200ms 限流状态。
- `PJEightKeySwitchDimmingPopupController` 增加亮度结束回调，只在 `ended == true` 时通知外层。
- `PJEightKeySwitchForcedAutoPopupController` 增加 AUTO 点击回调，由外层发送 AUTO 命令。

实现时不把控制发送塞进同步任务队列。该功能是用户即时控制，不需要 `MeshProxyMessageCommand` 的配置任务语义。

## 错误处理

- 缺少 BPS 虚拟地址：静默忽略。
- Scene key 未配置 scene number：静默忽略。
- 页面 disabled：沿用现有 disabled 提示。
- Mesh 当前无 proxy 或发送失败：沿用 `MeshAPI.sendMessage` 和底层队列现有行为，本期不新增错误提示。

## 测试计划

静态检查：

- 8 个 key 都具备 enabled tap 回调路径。
- Scene 未配置时不调用 `MeshAPI.sendMessage`。
- Dim Up / Dim Down 没有任何 App 层重发逻辑。
- 亮度弹窗只在 `ended == true` 时触发发送。
- AUTO 命令使用与组页一致的 Light LC OnOff unack message。
- 同按钮 200ms 限流只按 key index 生效，不影响不同按钮。

构建验证：

- 执行项目指定的直接 `xcodebuild` 命令验证 SunSmart Debug iphoneos 编译。

手动 QA：

- Brightness Profile：100%、75%、50%、25%、Dim Up、Dim Down、ON、OFF 单击均能向虚拟地址发送一次命令。
- Scene Profile：已配置 scene 的 4 个 scene key 能发送 scene recall；未配置 scene 的 key 静默无动作。
- 快速连续点击同一个按钮，200ms 内只发送一次。
- 快速点击不同按钮，均能按顺序发送。
- 长按 Dim Up / Dim Down 打开亮度弹窗，拖动中不发送，松手后只发送一次最终亮度。
- 长按 ON 打开 AUTO 弹窗，点击 AUTO 发送一次 AUTO。
- 未配置 target groups 时发送不报错、不提示。

## 设计自检

- 无未决项，文档完整。
- 命令映射与 Battery Power Switch key configuration 和组页 AUTO 语义一致。
- 范围聚焦在 BPS 设备页即时控制，不触碰配置同步和 SDK。
- 已明确取消 App 层重发，并说明 sequence number / TID 影响。
- 已明确 scene 未配置、虚拟地址缺失、disabled 状态的处理方式。
