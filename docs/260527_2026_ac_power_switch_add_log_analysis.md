# AC Power Switch 添加日志命令分析

## 结论

这段日志添加的是 `2422K8NACS`，Manufacturer Data 为 `78 0A 11 2A ...`，Composition Data 中 `companyIdentifier = 0x0A78`、`productIdentifier = 0x2A11`，后续 `compositionHash = 6d3613bc`，与 AC Power Switch 4SC 型号一致。

日志中 AC Switch 自身的 9 条 `batteryPowerSwitchKeyConfig` 都已发出并收到成功 ACK。它们配置的是按键 4/5 调光、按键 6 开/Auto、按键 7 关，目标地址为 `0xC00C`。

但从 AC 协议和当前 SDK 能力判断，日志中缺少关键的按键 Client Model AppKey Bind：只绑定了主元素 `0x02CA` 上的部分 Client Models，没有绑定 `0x02CB`~`0x02D1` 上各按键 element 的 Client Models。AC 节点没有 Generic Battery Server，而 SDK 的 `batteryPowerSwitchProfileClientModels` 当前依赖 `batteryModel != nil`，导致 AC 不会进入 Battery Power Switch 的完整必绑模型集合。这是最明显的漏发。

## 已发送的业务命令

以下只统计业务层 Mesh Access 命令，不把分段传输 ACK、Secure Network Beacon、广播扫描和 HTTP 同步计入。

### 1. Provisioning 后基础配置

1. `ConfigCompositionDataGet`
   - opcode: `0x8008`
   - 参数: `00`
   - 目标: `0x02CA`
   - 返回: `ConfigCompositionDataStatus`
   - 结果: 成功，元素为 `0x02CA`~`0x02D1` 共 8 个。

2. `ConfigAppKeyAdd`
   - opcode: `0x00`
   - 参数: `011000FA90F7A77C49AECFA0A330208D0B4D96`
   - 目标: `0x02CA`
   - 返回: `ConfigAppKeyStatus`
   - 结果: Success。

3. `ConfigModelAppBind`
   - `0x02CA / 0x1200` Time Server: Success
   - `0x02CA / 0x1201` Time Setup Server: Success
   - `0x02CA / 0x0A78:0001` Sunricher Vendor Model: Success
   - `0x02CA / 0x0002` Health Server: Success
   - `0x02CB / 0x1400` Firmware Update Server: Success
   - `0x02CB / 0x1402` BLOB Transfer Server: Success
   - `0x02CA / 0x1001` Generic OnOff Client: Success
   - `0x02CA / 0x1003` Generic Level Client: Success
   - `0x02CA / 0x1311` Light LC Client: Success
   - `0x02CA / 0x1305` Light CTL Client: Success
   - `0x02CA / 0x1205` Scene Client: Success

### 2. 信息查询

1. `FirmwareUpdateInformationGet`
   - opcode: `0x8308`
   - 参数: `0001`
   - 目标: `0x02CB`
   - 返回: `FirmwareUpdateInformationStatus`
   - 结果: 成功。

2. `SunricherVendorGet(.compositionHash)`
   - opcode: `0xF1780A`
   - 参数: `38`
   - 目标: `0x02CA`
   - 返回: `SunricherVendorStatus`
   - 结果: 成功，hash 为 `6d3613bc`。

### 3. AC Power Switch 自身按键配置

以下 9 条都是 `SunricherVendorSet(.batteryPowerSwitchKeyConfig)`，opcode 均为 `0xF0780A`，回包均为 `0xF3780A 4C0000`，即成功。

| 按键 | 触发 | 动作 | 关键参数 |
|---|---|---|---|
| 4 | click | `levelDelta` | level `+13107`，address `0xC00C`，appKey `1` |
| 4 | press | `levelMove` | level `+6553`，address `0xC00C`，appKey `1` |
| 4 | pressRelease | `levelMove` | level `0`，address `0xC00C`，appKey `1` |
| 5 | click | `levelDelta` | level `-13107`，address `0xC00C`，appKey `1` |
| 5 | press | `levelMove` | level `-6553`，address `0xC00C`，appKey `1` |
| 5 | pressRelease | `levelMove` | level `0`，address `0xC00C`，appKey `1` |
| 6 | click | `onOffSet` | value `1`，address `0xC00C`，appKey `1` |
| 6 | press | `lightCtrlOnOff` | value `1`，address `0xC00C`，appKey `1` |
| 7 | click | `onOffSet` | value `0`，address `0xC00C`，appKey `1` |

最后发送了 `AttentionSet(attentionTimer: 6)` 到 `0x02CA`，返回 `AttentionStatus(6)`，随后 App 打印添加成功。

## 没看到或疑似漏发的命令

### 1. 非主元素按键 Client Models 的 AppKey Bind

AC `0x2A11` 是 8 element 节点，按键源地址应覆盖 `0x02CA`~`0x02D1`。日志只看到主元素 `0x02CA` 上的 5 个 Client Model 被绑定：

- `0x1001` Generic OnOff Client
- `0x1003` Generic Level Client
- `0x1311` Light LC Client
- `0x1305` Light CTL Client
- `0x1205` Scene Client

同时，主元素上的 `0x1302` Light Lightness Client 也没有出现在 AC 日志中；这是因为当前 SDK 只会通过 `batteryPowerSwitchProfileClientModels` 扩展 Light Lightness Client，而 AC 因为缺少 Battery Server 没有进入该扩展分支。

没有看到 `0x02CB`~`0x02D1` 上对应 Client Models 的 `ConfigModelAppBind`。按当前仓库的 AC JSON，这些 element 还包含 CTL、HSL、Generic Power Level、Generic Power OnOff、Default Transition Time 等 Client Models；这些也没有在日志里出现。

这个漏发风险最高。物理开关如果从各按键 element 发消息，而这些 model 未绑定 AppKey，可能导致按键发不出或目标设备无法解密。

### 2. Model Publication Set

日志没有看到针对 AC Switch 自身 Client Models 或 Health Server 的 `ConfigModelPublicationSet`。AC 差异文档引用的 4DIM_AC 主文档列出了 Publication Set 要求，但当前仓库缺少完整 4DIM_AC 主协议文档，无法仅凭本仓库判断具体哪些 model 必须设置 publication。

如果固件完全使用 `0x4C` key config 中的 `address/appKeyIndex` 发控制消息，缺少 publication 未必影响控制；如果固件依赖 SIG model publication，则这里也是漏发。

### 3. TX Enable / LED Enabled

日志没有看到：

- `SunricherVendorSet(.batteryPowerSwitchTxEnabled(...))`
- `SunricherVendorSet(.batteryPowerSwitchLEDEnabled(...))`

按当前 App 代码，直接添加新 Power Switch 时默认只发送 Key Config；TX/LED 仅在绑定已有虚拟 switch 或后续同步状态不一致时发送。因此这两条从当前实现看不是必然漏发，但如果 AC 固件出厂默认 TX disabled，则需要补发 TX Enable。

### 4. Target Group 订阅命令

日志尾部的：

```text
[BPS Target] subscribe node=02BA, group=C00B, ...
[BPS Target] subscribe node=02BF, group=C00B, ...
```

只是 DEBUG 计算输出，后面没有对应 `Sending Access PDU`，所以这段日志没有实际发送 target 灯具的 `ConfigModelSubscriptionAdd`。它也不是新 AC Switch 自身的 key config，且 group 是 `0xC00B`，而本次 key config 指向的是 `0xC00C`。

直接添加一个未绑定目标设备的 AC Switch 时，不发送 target group 订阅是合理的；如果本次期望同时绑定并控制已有灯组，则还缺少目标灯具订阅 `0xC00C` 的命令。

## 建议后续验证

1. 修正或验证 SDK 的 Power Switch 必绑模型判断，不要让 AC 因为没有 Generic Battery Server 而跳过完整按键 Client Model 集合。
2. 重新抓添加日志，确认 `0x02CA`~`0x02D1` 上的按键 Client Models 都出现 `ConfigModelAppBind` 成功回包。
3. 抓物理按键按下日志，确认源地址、目标地址、opcode 与 `0xC00C` key config 一致。
4. 回源确认 4DIM_AC 主协议中 Publication Set 的必配范围，再决定是否在添加或后续 Sync 中补 `ConfigModelPublicationSet`。
