# Battery 与 AC Power Switch Key Bind 漏发对比

## 结论

Battery Power Switch 没有发生 AC 日志里同一种漏发。

AC 日志的问题是：只绑定了主元素上的少量 Client Models，没有绑定 `0x02CB`~`0x02D1` 各按键 element 上的 Profile Client Models。Battery Power Switch 在当前 SDK 逻辑下会进入完整的 Battery Power Switch 必绑模型路径，因此会把 8 个 element 上的基础 Profile Client Models 纳入 `ConfigModelAppBind`。

所以不能用“Battery 也没发”来证明 AC 不需要发。恰好相反：Battery 能发完整按键 Client Bind，是因为 Battery 有 Generic Battery Server；AC 没有 Battery Server，导致 SDK 条件判断失败。

## 代码依据

SDK 中 `Node.isBatteryPowerSwitchRequiredConfigurationSupported` 的条件是：

- `healthModel != nil`
- `batteryModel != nil`
- `sunricherVendorModel != nil`
- `hasBatteryPowerSwitchProfileClientModelSet == true`

Battery `0x2A01` / `0x2A02` 的 Composition 里有 `0x100C` Generic Battery Server，因此 `batteryModel != nil` 成立。

AC `0x2A11` / `0x2A12` 的协议明确不挂 Generic Battery Server，因此 `batteryModel == nil`，不会进入 Battery Power Switch 的完整必绑模型集合。

`supportModels` 里有两层来源：

1. 通用 Client Model getter，只取节点中第一个匹配 model，通常是主元素上的一个。
2. `batteryPowerSwitchProfileClientModels`，只有在 `isBatteryPowerSwitchRequiredConfigurationSupported == true` 时，才遍历所有 elements，把基础 Profile Client Models 全部加入。

因此：

- Battery 会走第 2 层，补齐 8 个 element。
- AC 只走第 1 层，所以日志只看到主元素上的部分 Client Models。

## JSON 对比

当前仓库 JSON 中，Battery 与 AC 都是 8 element。

Battery `0x2A01` / `0x2A02`：

- `0x100C` Generic Battery Server：1 个
- `0x1001` Generic OnOff Client：8 个
- `0x1003` Generic Level Client：8 个
- `0x1205` Scene Client：8 个
- `0x1302` Light Lightness Client：8 个
- `0x1311` Light LC Client：8 个

AC `0x2A11` / `0x2A12`：

- 没有 `0x100C` Generic Battery Server
- `0x1001` Generic OnOff Client：8 个
- `0x1003` Generic Level Client：8 个
- `0x1205` Scene Client：8 个
- `0x1302` Light Lightness Client：8 个
- `0x1311` Light LC Client：8 个
- 额外还有 `0x1305` Light CTL Client、`0x1309` Light HSL Client、`0x100B` Generic Power Level Client、`0x1008` Generic Power OnOff Client、`0x1005` Generic Default Transition Time Client 等各 8 个。

## Battery 是否也有其它范围的漏发

如果只看 AC 日志中暴露的“非主元素基础 Profile Client Models 未绑定”问题，Battery 不漏。

但还有一个单独问题：当前 SDK 的 `batteryPowerSwitchProfileClientModelIDs` 只包含 5 个基础 Client Model：

- Generic OnOff Client
- Generic Level Client
- Scene Client
- Light Lightness Client
- Light LC Client

它没有包含 CTL / HSL / Power Level / Power OnOff / Default Transition Time 等扩展 Client。Battery 协议文档中提到新版本每键 SIG Client 已扩展到 10 个，但当前 Battery JSON 仍只列出基础 5 个。这个属于“协议版本与 JSON/SDK 是否同步”的问题，不是这次 AC 日志中的同一种漏发。

## 判断

当前证据支持：

1. Battery 的基础 8-element Profile Client Bind 是完整的。
2. AC 的基础 8-element Profile Client Bind 不完整。
3. AC 不应因为 Battery 行为而跳过绑定；相反，SDK 应把 AC 从 `batteryModel` 条件中拆出来，按 Power Switch 类型识别后补齐至少基础 5 个 Profile Client Models。
4. 是否同时补齐 AC 扩展的 10 Client，需要依据 4DIM_AC 主协议确认。但至少不能继续只绑定主元素。
