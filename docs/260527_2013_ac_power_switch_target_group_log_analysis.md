# AC Power Switch Target Group SAVE 日志分析

## 结论

这段日志中真正发出的 Mesh 配置命令是给 target group 内灯具节点添加订阅：

- 订阅地址：`0xC00C`
- 目标节点：`0x02BA`、`0x02BF`
- 配置命令：`ConfigModelSubscriptionAdd`
- 回包：所有已展示的 `ConfigModelSubscriptionStatus` 都是 `Success`

因此，从 target 灯具侧看，订阅命令是成功的。手机上模拟的 Switch 可以控制该 Group，也进一步说明 target 灯具订阅到 `0xC00C` 这条链路大概率是通的。

当前现象更像是 AC Power Switch 自身侧没有正确发出与 App 期望一致的控制消息，而不是 target group 订阅失败。

## 日志解读

实际下发到 `0x02BA` 的订阅：

- `0x02BA / 0x1000`：Generic OnOff Server
- `0x02BA / 0x1002`：Generic Level Server
- `0x02BA / 0x1300`：Light Lightness Server
- `0x02BC / 0x130F`：Light LC Server

实际下发到 `0x02BF` 的订阅：

- `0x02BF / 0x1000`：Generic OnOff Server
- `0x02BF / 0x1002`：Generic Level Server
- `0x02BF / 0x1300`：Light Lightness Server
- `0x02C1 / 0x130F`：Light LC Server

这些模型集合由日志中的 action types 推导：

`8,8,8,8,3,4,4,3,4,4,2,6,2`

按当前 SDK 枚举含义：

- `8` = `lightnessSet`
- `3` = `levelDelta`
- `4` = `levelMove`
- `2` = `onOffSet`
- `6` = `lightCtrlOnOff`

所以这是一套 Brightness Profile 订阅目标，不是 Scene Profile 订阅目标。若当前 AC Switch 是 PID `0x2A12`，这与默认 brightness profile 一致；若它是 PID `0x2A11` 且预期仍是 scene profile，则这段日志反而暴露了 profile 不匹配问题。

## 这段日志没有证明的部分

日志没有看到以下 AC Switch 自身侧配置：

- `SunricherVendorSet(.batteryPowerSwitchKeyConfig(...))`
- `SunricherVendorSet(.batteryPowerSwitchTxEnabled(...))`
- AC Switch 各 key element 上 Client Model 的 `ConfigModelAppBind`

也就是说，这段 SAVE 只证明 target 灯具订阅了 `0xC00C`，没有证明物理 AC Switch 会向 `0xC00C` 发正确 action。

## 最可能方向

1. AC Switch 自身 key config 没有真正下发或没有重发。
   - 当前 SAVE 只做了 target subscription，没有 own configuration step。
   - 如果 AC 之前的 key config 失败、目标地址还是旧 group，或 profile 与 App 不一致，则物理开关不会控制当前 `0xC00C`。

2. AC Switch 的 Client Models 可能没有完整 AppKey Bind。
   - AC 协议没有 Generic Battery Server。
   - 当前本地 SDK 中 `batteryPowerSwitchProfileClientModels` 入口仍依赖 `isBatteryPowerSwitchRequiredConfigurationSupported`，而这个判断要求 `batteryModel != nil`。
   - 因此 AC 节点可能没有像 Battery Power Switch 一样把 8 个 element 上的按键 Client Models 全部纳入必绑模型。
   - 目标灯具已订阅、手机模拟可控，但物理开关不可控，符合这一类 switch source 侧问题。

3. Profile 可能不匹配。
   - 日志是 Brightness Profile。
   - 如果真实 AC 设备是 `0x2A11` 默认 Scene Profile，且本次没有重发 key config，则物理按键可能仍在发 Scene Recall，而 target 灯具没有订阅 Scene Server。

## 建议下一步验证

1. 确认物理 AC Switch 的 PID：
   - `0x2A11` 应默认 Scene Profile。
   - `0x2A12` 应默认 Brightness Profile。

2. 抓一次按下物理 AC Switch 的日志：
   - 看源地址是否来自 AC Switch 的 key element。
   - 看目标地址是否为 `0xC00C`。
   - 看 opcode/action 是 Lightness/Level/OnOff/LC，还是 Scene Recall。

3. 抓 AC Switch 添加或 Repair/Key Bind 日志：
   - 检查是否对 8 个 key elements 上的 Client Models 发送了 `ConfigModelAppBind`。
   - 如果只绑定了 primary element 上的一组 Client Models，则需要修 SDK 的 AC Power Switch 必绑模型识别。

4. 强制触发一次 own configuration 同步：
   - 预期日志应出现 `batteryPowerSwitchKeyConfig` 和必要的 `batteryPowerSwitchTxEnabled`。
   - 如果重发 own configuration 后物理开关可控，说明 target subscription 本身不是根因。
