# AC Power Switch 与 Battery Power Switch AppKey Bind 对比

## 结论

当前添加流程下，AC Power Switch 与 Battery Power Switch 在添加成功后绑定的 model 集合不一致。

两类设备已绑定的 AppKey 命令都使用 `MeshNetworkManager.instance.currentApplicationKey`，也就是当前子网 AppKey；但问题不在 AppKey 来源，而在 AC 没有进入 Battery Power Switch 的完整按键 Client Model 收集路径，导致 AC 只绑定了部分 model。

除 Battery 相关 model 外，预期应保持一致的按键 Client Models，目前没有达到。

## 添加流程依据

添加时 SDK 先通过 `getInitializeMessageHandles()` 下发 `ConfigCompositionDataGet` 和 `ConfigAppKeyAdd(currentApplicationKey)`，随后通过 `getConfigMessageHandles()` 遍历 `supportModels`，对未绑定当前 AppKey 的 model 下发 `ConfigModelAppBind(currentApplicationKey, to: model)`。

关键点：

- AppKey 来源：`Node+Messages.swift:667`、`Node+Messages.swift:709` 都使用当前 AppKey。
- Model 绑定集合来源：`Node+Messages.swift:711` 遍历 `supportModels`。
- 添加结束前会反复补齐 `getConfigMessageHandles()` 返回的配置消息：`MeshFastAddDeviceManager.swift:641` 到 `MeshFastAddDeviceManager.swift:648`。
- 非强制 keybind 场景下，普通 `ConfigModelAppStatus` 失败不会一定导致添加失败；Battery Power Switch 的关键 model 失败会触发失败处理。

## Battery Power Switch 当前行为

Battery Power Switch 的 PID 是 `0x2A01` / `0x2A02`，代码已识别为 `PJEightKeyPowerSwitchKind.battery`。

SDK 的 Battery Power Switch 必绑判断要求：

- Health Server 存在。
- Generic Battery Server 存在。
- Sunricher Vendor Model 存在。
- 每键 Profile Client Model 集合存在。

这个判断在 `Node+SupportModels.swift:310` 到 `Node+SupportModels.swift:315`。Battery 设备有 `Generic Battery Server (0x100C)`，因此会进入 `batteryPowerSwitchProfileClientModels`，遍历所有 element 收集基础 Profile Client Models。

当前基础 Profile Client Model ID 列表是：

| Model ID | 含义 |
|---|---|
| `0x1001` | Generic OnOff Client |
| `0x1003` | Generic Level Client |
| `0x1205` | Scene Client |
| `0x1302` | Light Lightness Client |
| `0x1311` | Light LC Client |

所以 Battery 添加成功时，基础 5 个按键 Client Model 会按 8 个 element 收集并绑定当前 AppKey；此外还会绑定 Health、Battery、Vendor 等关键 model。

## AC Power Switch 当前行为

AC Power Switch 的 PID 是 `0x2A11` / `0x2A12`，代码已识别为 `PJEightKeyPowerSwitchKind.ac`，但 SDK 的完整按键 Client Model 收集仍挂在 `isBatteryPowerSwitchRequiredConfigurationSupported` 后面。

AC 协议明确没有 `Generic Battery Server (0x100C)`，因此：

- `batteryModel == nil`
- `isBatteryPowerSwitchRequiredConfigurationSupported == false`
- `batteryPowerSwitchProfileClientModels` 返回空数组
- `supportModels` 不会遍历所有 element 收集按键 Client Models

AC 最终只会走 `supportModels` 里的通用 getter，通常只取第一个匹配的 Client Model，例如主元素上的 `0x1001`、`0x1003`、`0x1311`、`0x1305`、`0x1205` 等。它不会补齐 `primary + 1` 到 `primary + 7` 上的同类按键 Client Models。

另外，当前 `supportModels` 没有单独的 Light Lightness Client getter；`0x1302` 只在 `batteryPowerSwitchProfileClientModelIDs` 中出现。所以 AC 因为缺少 Battery Server，连主元素上的 `0x1302` 也可能不会被当前添加流程绑定。

## JSON 快照对比

当前 `protocols/0x2A01.json` / `0x2A02.json` 显示 Battery 已绑定 AppKey index `0` 的集合为：

- `0x0002` Health Server：1 个
- `0x100C` Generic Battery Server：1 个
- `0x0A780001` Sunricher Vendor Model：1 个
- `0x1001` / `0x1003` / `0x1205` / `0x1302` / `0x1311`：各 8 个
- `0x1400` / `0x1402`：各 1 个

当前 `protocols/0x2A11.json` / `0x2A12.json` 显示 AC 已绑定 AppKey index `0` 的集合为：

- `0x0002` Health Server：1 个
- `0x0A780001` Sunricher Vendor Model：1 个
- `0x1200` / `0x1201` Time 相关 model：各 1 个
- `0x1001` / `0x1003` / `0x1205` / `0x1302` / `0x1311`：各 8 个
- `0x1305` / `0x1309` / `0x100B` / `0x1008` / `0x1005`：各 8 个
- `0x1400` / `0x1402`：各 1 个

这些 JSON 快照里的 common models 绑定 AppKey 是一致的，都是 index `0`。但这不能证明当前添加流程已经做到一致，因为当前代码路径不会为 AC 收集所有 element 上的 Profile Client Models，已有 AC 添加日志也显示只绑定了主元素上的部分 Client Models。

## 与预期的差异

预期是：除 Battery 相关 model 外，AC/Battery Power Switch 的按键 Client Models 应绑定同一把 AppKey，并覆盖相同的 element 范围。

当前差异是：

| 范围 | Battery 添加流程 | AC 添加流程 |
|---|---|---|
| AppKey 来源 | 当前 AppKey | 当前 AppKey |
| Health / Vendor | 会绑定 | 会绑定 |
| Battery Server `0x100C` | 会绑定 | 不存在，可忽略 |
| 基础按键 Client 5 个 model | 遍历所有 element 绑定 | 只绑定通用 getter 找到的首个或少量 model |
| Light Lightness Client `0x1302` | 会被 BPS profile 路径收集 | 可能不会绑定 |
| 扩展按键 Client 5 个 model | 当前 SDK 的 BPS profile 列表还未覆盖 | AC JSON 中存在，但当前 SDK 也不会按所有 element 收集 |

## 判断

当前代码不满足“除 Battery 相关 models 外，AC/Battery Power Switch 其他 models 绑定 AppKey 保持一致”的预期。

根因是 SDK 把“Power Switch 按键 Profile Client Models 遍历所有 element 收集”的逻辑绑定在 `batteryModel != nil` 条件上。AC 是 Power Switch，但没有 Battery Server，因此被排除在完整收集路径之外。

后续修复方向应是把这段逻辑从 Battery-only 判断拆成 Power Switch profile 判断：通过 PID 或 Power Switch kind 识别 `0x2A01` / `0x2A02` / `0x2A11` / `0x2A12`，对共同的按键 Client Models 使用同一套 all-elements bind 逻辑；Battery Server 只作为 Battery 设备额外处理。

