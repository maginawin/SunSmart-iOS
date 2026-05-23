# Battery Power Switch Publication Retransmit 分析

## 结论

当前代码没有为 Battery Power Switch 自身的 Profile Client Models 配置 `publication`，因此也没有配置 `publication retransmit`。

需要补充一个 BPS 专属同步步骤：为 BPS 节点上的 Profile Client Models 设置 publication 到 BPS 内部虚拟组 `linkGroupAddress`，并把 retransmit 设置为 `count = 1`、`interval = 200 ms`。

## 当前代码路径

### BPS SAVE 同步

`SyncDevicesViewController.appendBatteryPowerSwitchItems(...)` 当前只生成三个方向的任务：

1. `batteryPowerSwitchReset`
2. `batteryPowerSwitchKeyConfig`
3. `batteryPowerSwitchTargetSubscription`

`SyncDevicesCellModel` 中对应的 message 生成逻辑也只覆盖：

- reset BPS vendor 配置
- 下发每个按钮的 vendor key config
- 给 target groups 内设备的 capability models 订阅 BPS `linkGroupAddress`

这条链路没有对 BPS 自身的 Client Models 下发 `ConfigModelPublicationSet`。

### 添加阶段通用配置

SDK 的 `Node.getConfigMessageHandles()` 会根据 `MeshLibManager.manager.publishModelIDs` 给普通设备配置 publication。

但当前 App 在 `SiteViewController` 中设置：

- `MeshLibManager.manager.publishModelIDs = []`
- `MeshLibManager.manager.publishTimeModelIDs = []`
- `MeshLibManager.manager.publishModeloOnly = true`

所以添加阶段也不会给 BPS 配置任何 model publication。

即使未来走到 SDK 这段通用 publication 逻辑，当前 SDK 使用的 retransmit 也是 `.disabled`，不符合 `count = 1`、`interval = 200 ms` 的需求。

## 协议与 SDK 细节

`protocols/2422K8N_US_4DIM.md` 中明确提到 BPS 配网后推荐配置 Health Server publication；示例 JSON `protocols/0x2A01.json` / `protocols/0x2A02.json` 里也只有 Health Server (`0x0002`) 带 publication，且样例 retransmit 是 `count = 3`、`interval = 50 ms`。

本次需求是“为 Battery Power Switch 配置 models 的 publication，并把这些 models 的 retransmit 设为 1 / 200ms”。结合 BPS Profile 的控制链路，推荐把这里的 models 理解为 BPS 按键动作会使用的 Profile Client Models：

- Generic OnOff Client
- Generic Level Client
- Scene Client
- Light Lightness Client
- Light LC Client

这些 models 来自 SDK 已有的 `batteryPowerSwitchProfileClientModels`，不要新增重复的 SDK 设备接口。

SDK 的 `Publish.Retransmit` 支持精确表达该需求：

- `publishRetransmitCount = 1`
- `intervalSteps = 3`
- 实际 interval = `(3 + 1) * 50 ms = 200 ms`

避免用浮点换算时，建议使用 `Publish.Retransmit(publishRetransmitCount: 1, intervalSteps: 3)`。

## 推荐方案 A

在 App 侧增加 BPS 专属 publication 同步能力：

1. 在 BPS SAVE 同步中新增一步 `Model Publication`。
2. 对 `switchData.proxyNode?.batteryPowerSwitchProfileClientModels` 逐个下发 `ConfigModelPublicationSet`。
3. publication 参数：
   - address: `switchData.linkGroupAddress`
   - app key: 当前 space app key
   - ttl: 当前网络默认 TTL
   - period: disabled / 0
   - retransmit: `count = 1`, `interval = 200 ms`
4. 顺序建议：
   - reset BPS 配置
   - 下发 8 个按钮的 click / press / press release 配置
   - 配置 BPS Profile Client Models publication
   - 配置 target groups capability models 订阅 BPS 虚拟组
5. target group subscription 依赖新增的 publication step，避免 target 已订阅但 BPS 自身还没 publish 到虚拟组。
6. 将 publication retransmit 配置版本纳入 BPS desired config hash，例如加入 `publication=profileClients@linkGroup,retransmit=1/200`，确保旧设备会显示需要同步并进入 SAVE 流程补齐。
7. 同步成功后沿用现有 `markBatteryPowerSwitchSyncSucceeded()`；失败后沿用现有 `syncState = failed`，UI 显示 sync issue，重试时重新 reset + 下发 desired config。

优点：

- 范围最小，仅影响 BPS。
- 不改通用 add/keybind 逻辑，避免影响普通灯具、传感器、网关。
- 可以复用 SDK 已有 `batteryPowerSwitchProfileClientModels`，不新增重复接口。
- 与现有 BPS desired config / sync issue 机制一致。

风险：

- BPS 每个元素可能存在多个 Client Model；如果全部配置 publication，会增加多条 ConfigModelPublicationSet，SAVE 时间变长。
- 如果固件实际只读取 vendor key config 中的 `addr/app_idx`，而不依赖 model publication，功能上可能看不出变化，但 publication retransmit 对使用 model publication 发送的报文才生效。

## 备选方案 B

只配置 Health Server publication，并把 Health Server retransmit 改为 `1 / 200ms`。

优点：

- 与协议文档 §10.2 明确提到的 Health Server publication 完全对应。
- 消息数量少。

缺点：

- 只能影响 Health Current Status 故障上报，不会影响按键控制命令的投递。
- 不符合“these models”如果指 Profile Client Models 的诉求。

## 备选方案 C

在 SDK 的通用 `getConfigMessageHandles()` 中为 BPS 特判 publication。

优点：

- 添加阶段即可补齐。

缺点：

- 侵入 SDK 通用配置路径。
- 容易影响普通设备 publication 策略。
- BPS SAVE 时仍需要补齐旧设备或失败设备的 publication sync，因此最终仍需要 App 侧 BPS 专属同步逻辑。

## 推荐

采用方案 A。

已确认本次只应用到 BPS Profile Client Models，不修改 Health Server publication。Health Server 继续保留协议样例中的 `3 / 50ms` 故障上报策略。
