# HDB Smart Lighting — Sample Payload

## 来源与转换说明

- 来源文件：`【平台方按我们需求提供例子】Sample_payload.xlsx`。
- 工作表：`Smart Lighting Config & Control`；数据范围：`A1:C35`。
- 原始列名：`Category`、`Event Type`、`Sample Payload`。
- 转换日期：2026-10-20（Asia/Singapore）。
- 完整收录 11 个分类、34 个事件示例，保持工作表中的分类和排列顺序。
- 26 个原始 payload 可直接解析为 JSON；另外 8 个仅修正引号或逗号，修正明细及对应单元格原文见附录 A。
- 正文 JSON 统一缩进，保留字段名大小写、键顺序、数值类型、数组顺序、null 和字符串内部空白。未补入缺失字段，也未推导默认值。
- 字段表中的类型、取值和出现位置均来自这些示例，不代表必填性、完整枚举、取值范围或正式协议约束。
- 示例未提供应答报文、错误码、字段单位或重试规则；这些内容未在转换时补写。
- 原文件 SHA-256：`5636c3df4a0c876eee88a43470e99852eb5606ed5f35878c54c436f37e3a226d`。

## 事件索引

“未提供”表示该字段在当前示例中缺失，不等同于 `null`、空字符串或默认值。

| Category | Event Type | CommandType | Transmission | 原始 JSON | 源单元格 |
| --- | --- | --- | --- | --- | --- |
| Lighting Zones | [SmartLighting/setLightingZone](#event-2) | `Set` | `Unicast` | 有效 | `C2` |
| Lighting Zones | [SmartLighting/getLightingZone](#event-3) | `Get` | `Unicast` | 已修正语法，原文见附录 A | `C3` |
| Trigger Zones | [SmartLighting/getTriggerZone](#event-4) | `Get` | `Unicast` | 已修正语法，原文见附录 A | `C4` |
| Trigger Zones | [SmartLighting/setTriggerZone](#event-5) | `Set` | `Unicast` | 有效 | `C5` |
| Lighting Configuration | [SmartLighting/getLightOverride](#event-6) | `Get` | 未提供 | 有效 | `C6` |
| Lighting Configuration | [SmartLighting/setLightOverride](#event-7) | `Set` | `Broadcast` | 有效 | `C7` |
| Lighting Configuration | [SmartLighting/getLightIntensity](#event-8) | `Get` | 未提供 | 有效 | `C8` |
| Lighting Configuration | [SmartLighting/setLightIntensity](#event-9) | `Set` | `Unicast` | 有效 | `C9` |
| Lighting Configuration | [SmartLighting/getSoftDimming](#event-10) | `Get` | 未提供 | 有效 | `C10` |
| Lighting Configuration | [SmartLighting/setSoftDimming](#event-11) | `Set` | `Broadcast` | 有效 | `C11` |
| Lighting Configuration | [SmartLighting/getTimeDelay](#event-12) | `Get` | 未提供 | 有效 | `C12` |
| Lighting Configuration | [SmartLighting/setTimeDelay](#event-13) | `Set` | `Broadcast` | 有效 | `C13` |
| Lighting Configuration | [SmartLighting/getLightInstallDate](#event-14) | `Get` | `Unicast` | 有效 | `C14` |
| Lighting Configuration | [SmartLighting/setLightInstallDate](#event-15) | `Set` | `Unicast` | 有效 | `C15` |
| Sensor Configuration | [SmartLighting/getMotionSensitivity](#event-16) | `Get` | 未提供 | 有效 | `C16` |
| Sensor Configuration | [SmartLighting/setMotionSensitivity](#event-17) | `Set` | `Unicast` | 有效 | `C17` |
| Sensor Configuration | [SmartLighting/getPhotoSensing](#event-18) | `Get` | 未提供 | 有效 | `C18` |
| Sensor Configuration | [SmartLighting/setPhotoSensing](#event-19) | `Set` | `Unicast` | 有效 | `C19` |
| Sensor Configuration | [SmartLighting/getRainSensing](#event-20) | `Get` | 未提供 | 有效 | `C20` |
| Sensor Configuration | [SmartLighting/setRainSensing](#event-21) | `Set` | `Unicast` | 有效 | `C21` |
| Proximity Lighting | [SmartLighting/getProximityLighting](#event-22) | `Get` | `Unicast` | 有效 | `C22` |
| Proximity Lighting | [SmartLighting/setProximityLighting](#event-23) | `Set` | `Unicast` | 有效 | `C23` |
| Predictive Lighting | [SmartLighting/getPredictiveLighting](#event-24) | `Get` | `Unicast` | 有效 | `C24` |
| Predictive Lighting | [SmartLighting/setPredictiveLighting](#event-25) | `Set` | `Unicast` | 有效 | `C25` |
| Timer Profiles | [SmartLighting/getTimerProfile](#event-26) | `Get` | 未提供 | 有效 | `C26` |
| Timer Profiles | [SmartLighting/setTimerProfile](#event-27) | `Set` | `Unicast` | 已修正语法，原文见附录 A | `C27` |
| Dimming Profiles | [SmartLighting/getDimmingProfile](#event-28) | `Get` | `Unicast` | 已修正语法，原文见附录 A | `C28` |
| Dimming Profiles | [SmartLighting/setDimmingProfile](#event-29) | `Set` | `Unicast` | 有效 | `C29` |
| Luminance Profiles | [SmartLighting/getLuminanceProfile](#event-30) | `Get` | `Unicast` | 已修正语法，原文见附录 A | `C30` |
| Luminance Profiles | [SmartLighting/setLuminanceProfile](#event-31) | `Set` | `Unicast` | 已修正语法，原文见附录 A | `C31` |
| Daylight Profile | [SmartLighting/getDaylightProfile](#event-32) | `Get` | 未提供 | 有效 | `C32` |
| Daylight Profile | [SmartLighting/setDaylightProfile](#event-33) | `Set` | `Unicast` | 有效 | `C33` |
| Daylight Harvesting Profile | [SmartLighting/getDaylightHarvestingProfile](#event-34) | `Get` | `Unicast` | 已修正语法，原文见附录 A | `C34` |
| Daylight Harvesting Profile | [SmartLighting/setDaylightHarvestingProfile](#event-35) | `Set` | `Unicast` | 已修正语法，原文见附录 A | `C35` |

## 公共顶层字段

下列六个键在全部 34 个示例中均出现。表中说明仅描述样例形态。

| 字段 | 样例类型 | 样例形态 |
| --- | --- | --- |
| `SenderId` | string | 原始示例包含 `Backend-...` 和 `SmartLighting-...` 字符串。 |
| `SensorId` | string | 原始示例均为 `SmartLighting-...` 字符串；未改写其 ID。 |
| `Resourcepath` | number（整数样例） | `207989`、`902355`、`207987`；原拼写为 `Resourcepath`。 |
| `EventId` | string | 保留原始 `EV-...` 字符串，包括跨示例重复出现的值。 |
| `EventType` | string | 与同一行的 `Event Type` 列一致，详见事件索引。 |
| `Parameters` | object | 各事件携带的参数对象，详见下文。 |

## Parameters 字段索引

`[]` 表示数组元素路径；取值按首次出现顺序去重。表中 `C行号` 均指来源工作表的 Sample Payload 单元格。数组内容以完整 JSON 示例为准。

| 字段路径 | 样例类型 | 已出现的样例值 | 来源 |
| --- | --- | --- | --- |
| `Parameters.NumberOfZone` | number（整数样例） | `1` | [C2](#event-2)、[C5](#event-5) |
| `Parameters.LightingZones` | array<object> | 见完整 JSON 示例中的数组 | [C2](#event-2) |
| `Parameters.LightingZones[].ZoneId` | number（整数样例） | `1` | [C2](#event-2) |
| `Parameters.CommandType` | string | `"Set"`、`"Get"` | [C2](#event-2)、[C3](#event-3)、[C4](#event-4)、[C5](#event-5)、[C6](#event-6)、[C7](#event-7)、[C8](#event-8)、[C9](#event-9)、[C10](#event-10)、[C11](#event-11)、[C12](#event-12)、[C13](#event-13)、[C14](#event-14)、[C15](#event-15)、[C16](#event-16)、[C17](#event-17)、[C18](#event-18)、[C19](#event-19)、[C20](#event-20)、[C21](#event-21)、[C22](#event-22)、[C23](#event-23)、[C24](#event-24)、[C25](#event-25)、[C26](#event-26)、[C27](#event-27)、[C28](#event-28)、[C29](#event-29)、[C30](#event-30)、[C31](#event-31)、[C32](#event-32)、[C33](#event-33)、[C34](#event-34)、[C35](#event-35) |
| `Parameters.ConfigurationZone` | number（整数样例） | `0` | [C2](#event-2)、[C5](#event-5)、[C7](#event-7)、[C9](#event-9)、[C11](#event-11)、[C13](#event-13)、[C15](#event-15)、[C17](#event-17)、[C19](#event-19)、[C21](#event-21)、[C25](#event-25)、[C27](#event-27)、[C29](#event-29)、[C31](#event-31)、[C33](#event-33)、[C35](#event-35) |
| `Parameters.Transmission` | string | `"Unicast"`、`"Broadcast"` | [C2](#event-2)、[C3](#event-3)、[C4](#event-4)、[C5](#event-5)、[C7](#event-7)、[C9](#event-9)、[C11](#event-11)、[C13](#event-13)、[C14](#event-14)、[C15](#event-15)、[C17](#event-17)、[C19](#event-19)、[C21](#event-21)、[C22](#event-22)、[C23](#event-23)、[C24](#event-24)、[C25](#event-25)、[C27](#event-27)、[C28](#event-28)、[C29](#event-29)、[C30](#event-30)、[C31](#event-31)、[C33](#event-33)、[C34](#event-34)、[C35](#event-35) |
| `Parameters.TriggerZones` | array<object> | 见完整 JSON 示例中的数组 | [C5](#event-5) |
| `Parameters.TriggerZones[].ZoneId` | number（整数样例） | `1` | [C5](#event-5) |
| `Parameters.LightingControl` | string | `"Auto"`、`"Enable"` | [C7](#event-7)、[C23](#event-23)、[C25](#event-25) |
| `Parameters.FailsafeDelay` | number（整数样例） | `10` | [C7](#event-7) |
| `Parameters.DimIntensity` | number（整数样例） | `40` | [C9](#event-9) |
| `Parameters.BrightIntensity` | number（整数样例） | `80` | [C9](#event-9) |
| `Parameters.RampUpTime` | number（整数样例） | `2` | [C11](#event-11) |
| `Parameters.RampDownTime` | number（整数样例） | `2` | [C11](#event-11) |
| `Parameters.HoldTime` | number（整数样例） | `60` | [C13](#event-13) |
| `Parameters.InstallDate` | string | `"19-03-2026"` | [C15](#event-15) |
| `Parameters.MotionSensitivity` | number（整数样例） | `1` | [C17](#event-17) |
| `Parameters.PhotoUpperThreshold` | number（整数样例） | `600` | [C19](#event-19) |
| `Parameters.PhotoLowerThreshold` | number（整数样例） | `500` | [C19](#event-19) |
| `Parameters.PhotoSensing` | string | `"Enable"` | [C19](#event-19) |
| `Parameters.RainUpperThreshold` | number（整数样例） | `30` | [C21](#event-21) |
| `Parameters.RainLowerThreshold` | number（整数样例） | `5` | [C21](#event-21) |
| `Parameters.RainSensing` | string | `"Enable"` | [C21](#event-21) |
| `Parameters.SaveNodeSetting` | string | `"Yes"` | [C23](#event-23) |
| `Parameters.NumberOfNeighbourNode` | number（整数样例） | `3` | [C23](#event-23) |
| `Parameters.ProfileControl` | string | `"Enable"` | [C27](#event-27)、[C29](#event-29)、[C31](#event-31)、[C33](#event-33)、[C35](#event-35) |
| `Parameters.RepeatAction` | number（整数样例） | `10`、`0`、`1` | [C27](#event-27)、[C29](#event-29)、[C31](#event-31)、[C33](#event-33)、[C35](#event-35) |
| `Parameters.NumberOfProfile` | number（整数样例） | `2` | [C27](#event-27)、[C29](#event-29)、[C31](#event-31) |
| `Parameters.TimerProfiles` | array<object> | 见完整 JSON 示例中的数组 | [C27](#event-27) |
| `Parameters.TimerProfiles[].ZoneId` | number（整数样例） | `1` | [C27](#event-27) |
| `Parameters.TimerProfiles[].StartTime` | string | `"07:00"`、`"19:00"` | [C27](#event-27) |
| `Parameters.TimerProfiles[].EndTime` | string | `"19:00"`、`"07:00"` | [C27](#event-27) |
| `Parameters.TimerProfiles[].DayOfWeek` | string | `"Everyday"` | [C27](#event-27) |
| `Parameters.TimerProfiles[].Action` | string | `"Force_Off"`、`"Auto"` | [C27](#event-27) |
| `Parameters.DimmingProfiles` | array<object> | 见完整 JSON 示例中的数组 | [C29](#event-29) |
| `Parameters.DimmingProfiles[].ZoneId` | number（整数样例） | `255` | [C29](#event-29) |
| `Parameters.DimmingProfiles[].StartTime` | string | `"11:50"`、`"11:55"` | [C29](#event-29) |
| `Parameters.DimmingProfiles[].EndTime` | string | `"23:50"`、`"23:55"` | [C29](#event-29) |
| `Parameters.DimmingProfiles[].DayOfWeek` | string | `"Everyday"`、`"Weekday"` | [C29](#event-29) |
| `Parameters.DimmingProfiles[].DimLevel` | number（整数样例） | `12`、`22` | [C29](#event-29) |
| `Parameters.DimmingProfiles[].BrightLevel` | number（整数样例） | `70`、`66` | [C29](#event-29) |
| `Parameters.LuminanceProfiles` | array<object> | 见完整 JSON 示例中的数组 | [C31](#event-31) |
| `Parameters.LuminanceProfiles[].ZoneId` | number（整数样例） | `1` | [C31](#event-31) |
| `Parameters.LuminanceProfiles[].StartDate` | string | `"01-01-2026"`、`"01-01-2027"` | [C31](#event-31) |
| `Parameters.LuminanceProfiles[].EndDate` | string | `"31-12-2026"`、`"31-12-2027"` | [C31](#event-31) |
| `Parameters.LuminanceProfiles[].LuminanceLevel` | number（整数样例） | `80`、`85` | [C31](#event-31) |
| `Parameters.ZoneId` | number（整数样例） | `255` | [C33](#event-33) |
| `Parameters.StartTime` | string | `"11:50"`、`"07:00"` | [C33](#event-33)、[C35](#event-35) |
| `Parameters.EndTime` | string | `"23:50"`、`"19:00"` | [C33](#event-33)、[C35](#event-35) |
| `Parameters.DimAction` | string | `"Auto"` | [C33](#event-33) |
| `Parameters.BrightAction` | string | `"Auto"` | [C33](#event-33) |
| `Parameters.PhotoSensor1` | null | `null` | [C33](#event-33) |
| `Parameters.PhotoSensor2` | null | `null` | [C33](#event-33) |
| `Parameters.PhotoSensor3` | null | `null` | [C33](#event-33) |
| `Parameters.DimThreshold` | number（整数样例） | `200` | [C33](#event-33) |
| `Parameters.BrightThreshold` | number（整数样例） | `400` | [C33](#event-33) |
| `Parameters.OverallZone` | number（整数样例） | `0` | [C35](#event-35) |
| `Parameters.DayOfWeek` | string | `"Weekday"` | [C35](#event-35) |
| `Parameters.DaylightThreshold` | number（整数样例） | `500` | [C35](#event-35) |
| `Parameters.MinLuminanceLevel` | number（整数样例） | `20` | [C35](#event-35) |
| `Parameters.MaxLuminanceLevel` | number（整数样例） | `90` | [C35](#event-35) |

## 保留的样例差异

- `C3` 的 `SenderId` 字符串以一个空格结尾，转换后仍保留该空格；正文仅修正其 JSON 语法。
- 部分示例省略 `Transmission`，`setProximityLighting` 示例省略 `ConfigurationZone`；未根据其他示例补齐。
- 同名 `LightingControl` 在 `setLightOverride` 中为 `"Auto"`，在 `setProximityLighting` 和 `setPredictiveLighting` 中为 `"Enable"`，未统一取值。
- `C33` 中 `PhotoSensor1`、`PhotoSensor2`、`PhotoSensor3` 均明确为 `null`。
- `Resourcepath`、`SenderId`、`SensorId` 和 `EventId` 中的数字不一定相同，部分 `EventId` 跨示例重复；未尝试对齐或重新生成。
- 日期、时间保留原始字符串，如 `"19-03-2026"`、`"07:00"`。TimerProfiles 示例保留 `"19:00"` 至 `"07:00"` 的时段，未推导跨日行为。

## 完整 Payload 示例

### Lighting Zones

<a id="event-2"></a>

#### SmartLighting/setLightingZone

- Category：`Lighting Zones`。
- 来源：`A2:C2`；payload 位于 `C2`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "SmartLighting-reza-207989-01010001",
  "SensorId": "SmartLighting-reza-207989-01010001",
  "Resourcepath": 207989,
  "EventId": "EV-207987-01010001-20260504075115504",
  "EventType": "SmartLighting/setLightingZone",
  "Parameters": {
    "NumberOfZone": 1,
    "LightingZones": [
      {
        "ZoneId": 1
      }
    ],
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Unicast"
  }
}
```

<a id="event-3"></a>

#### SmartLighting/getLightingZone

- Category：`Lighting Zones`。
- 来源：`A3:C3`；payload 位于 `C3`。
- JSON 状态：已修正原文语法；原文及修正明细见[附录 A / C3](#raw-3)。

```json
{
  "SenderId": "SmartLighting-reza-207989-01010001 ",
  "SensorId": "SmartLighting-reza-207989-01010001",
  "Resourcepath": 902355,
  "EventId": "EV-902355-S-20260319141443233",
  "EventType": "SmartLighting/getLightingZone",
  "Parameters": {
    "CommandType": "Get",
    "Transmission": "Unicast"
  }
}
```

### Trigger Zones

<a id="event-4"></a>

#### SmartLighting/getTriggerZone

- Category：`Trigger Zones`。
- 来源：`A4:C4`；payload 位于 `C4`。
- JSON 状态：已修正原文语法；原文及修正明细见[附录 A / C4](#raw-4)。

```json
{
  "SenderId": "SmartLighting-reza-207989-01010001",
  "SensorId": "SmartLighting-reza-207989-01010001",
  "Resourcepath": 902355,
  "EventId": "EV-902355-S-20260319141443233",
  "EventType": "SmartLighting/getTriggerZone",
  "Parameters": {
    "CommandType": "Get",
    "Transmission": "Unicast"
  }
}
```

<a id="event-5"></a>

#### SmartLighting/setTriggerZone

- Category：`Trigger Zones`。
- 来源：`A5:C5`；payload 位于 `C5`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "SmartLighting-reza-207989-01010001",
  "SensorId": "SmartLighting-reza-207989-01010001",
  "Resourcepath": 207989,
  "EventId": "EV-207987-01010001-20260504075115570",
  "EventType": "SmartLighting/setTriggerZone",
  "Parameters": {
    "NumberOfZone": 1,
    "TriggerZones": [
      {
        "ZoneId": 1
      }
    ],
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Unicast"
  }
}
```

### Lighting Configuration

> **App 项目约定（2026-10-20）：** `setLightInstallDate` 额外支持 Multicast 目标；它与 `FailsafeDelay` 仅保存到 `hdb` JSON。其他可下发字段选择 Multicast 时使用真实 Mesh 组播，全部消息发送成功即按全部目标成功记录。以下 JSON 仍保留原工作表样例，不增加或改写样例的 Transmission。~~Unoccupy_Off~~ 在原 ICD PDF 中已删除，不作为有效 LightingControl 值。具体发送及前置配置规则见[当前设计](../../docs/261020_1649_HDB_lighting_configuration_design.md)。

<a id="event-6"></a>

#### SmartLighting/getLightOverride

- Category：`Lighting Configuration`。
- 来源：`A6:C6`；payload 位于 `C6`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061315818",
  "EventType": "SmartLighting/getLightOverride",
  "Parameters": {
    "CommandType": "Get"
  }
}
```

<a id="event-7"></a>

#### SmartLighting/setLightOverride

- Category：`Lighting Configuration`。
- 来源：`A7:C7`；payload 位于 `C7`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504060924211",
  "EventType": "SmartLighting/setLightOverride",
  "Parameters": {
    "LightingControl": "Auto",
    "FailsafeDelay": 10,
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Broadcast"
  }
}
```

<a id="event-8"></a>

#### SmartLighting/getLightIntensity

- Category：`Lighting Configuration`。
- 来源：`A8:C8`；payload 位于 `C8`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-reza-207989-01010003",
  "Resourcepath": 207989,
  "EventId": "EV-207987-01010003-20260504074349701",
  "EventType": "SmartLighting/getLightIntensity",
  "Parameters": {
    "CommandType": "Get"
  }
}
```

<a id="event-9"></a>

#### SmartLighting/setLightIntensity

- Category：`Lighting Configuration`。
- 来源：`A9:C9`；payload 位于 `C9`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-reza-207989-01010003",
  "Resourcepath": 207989,
  "EventId": "EV-207987-01010003-20260504074220784",
  "EventType": "SmartLighting/setLightIntensity",
  "Parameters": {
    "DimIntensity": 40,
    "BrightIntensity": 80,
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Unicast"
  }
}
```

<a id="event-10"></a>

#### SmartLighting/getSoftDimming

- Category：`Lighting Configuration`。
- 来源：`A10:C10`；payload 位于 `C10`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061613326",
  "EventType": "SmartLighting/getSoftDimming",
  "Parameters": {
    "CommandType": "Get"
  }
}
```

<a id="event-11"></a>

#### SmartLighting/setSoftDimming

- Category：`Lighting Configuration`。
- 来源：`A11:C11`；payload 位于 `C11`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061503218",
  "EventType": "SmartLighting/setSoftDimming",
  "Parameters": {
    "RampUpTime": 2,
    "RampDownTime": 2,
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Broadcast"
  }
}
```

<a id="event-12"></a>

#### SmartLighting/getTimeDelay

- Category：`Lighting Configuration`。
- 来源：`A12:C12`；payload 位于 `C12`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061740456",
  "EventType": "SmartLighting/getTimeDelay",
  "Parameters": {
    "CommandType": "Get"
  }
}
```

<a id="event-13"></a>

#### SmartLighting/setTimeDelay

- Category：`Lighting Configuration`。
- 来源：`A13:C13`；payload 位于 `C13`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/setTimeDelay",
  "Parameters": {
    "HoldTime": 60,
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Broadcast"
  }
}
```

<a id="event-14"></a>

#### SmartLighting/getLightInstallDate

- Category：`Lighting Configuration`。
- 来源：`A14:C14`；payload 位于 `C14`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/getLightInstallDate",
  "Parameters": {
    "CommandType": "Get",
    "Transmission": "Unicast"
  }
}
```

<a id="event-15"></a>

#### SmartLighting/setLightInstallDate

- Category：`Lighting Configuration`。
- 来源：`A15:C15`；payload 位于 `C15`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/setLightInstallDate",
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "InstallDate": "19-03-2026"
  }
}
```

### Sensor Configuration

<a id="event-16"></a>

#### SmartLighting/getMotionSensitivity

- Category：`Sensor Configuration`。
- 来源：`A16:C16`；payload 位于 `C16`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-reza-207989-01010003",
  "Resourcepath": 207989,
  "EventId": "EV-207987-01010003-20260504074552967",
  "EventType": "SmartLighting/getMotionSensitivity",
  "Parameters": {
    "CommandType": "Get"
  }
}
```

<a id="event-17"></a>

#### SmartLighting/setMotionSensitivity

- Category：`Sensor Configuration`。
- 来源：`A17:C17`；payload 位于 `C17`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-reza-207989-01010003",
  "Resourcepath": 207989,
  "EventId": "EV-207987-01010003-20260504074510731",
  "EventType": "SmartLighting/setMotionSensitivity",
  "Parameters": {
    "MotionSensitivity": 1,
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Unicast"
  }
}
```

<a id="event-18"></a>

#### SmartLighting/getPhotoSensing

- Category：`Sensor Configuration`。
- 来源：`A18:C18`；payload 位于 `C18`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-reza-207989-01010003",
  "Resourcepath": 207989,
  "EventId": "EV-207987-01010003-20260504074738437",
  "EventType": "SmartLighting/getPhotoSensing",
  "Parameters": {
    "CommandType": "Get"
  }
}
```

<a id="event-19"></a>

#### SmartLighting/setPhotoSensing

- Category：`Sensor Configuration`。
- 来源：`A19:C19`；payload 位于 `C19`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-reza-207989-01010003",
  "Resourcepath": 207989,
  "EventId": "EV-207987-01010003-20260504074649966",
  "EventType": "SmartLighting/setPhotoSensing",
  "Parameters": {
    "PhotoUpperThreshold": 600,
    "PhotoLowerThreshold": 500,
    "PhotoSensing": "Enable",
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Unicast"
  }
}
```

<a id="event-20"></a>

#### SmartLighting/getRainSensing

- Category：`Sensor Configuration`。
- 来源：`A20:C20`；payload 位于 `C20`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-reza-207989-01010003",
  "Resourcepath": 207989,
  "EventId": "EV-207987-01010003-20260504074738437",
  "EventType": "SmartLighting/getRainSensing",
  "Parameters": {
    "CommandType": "Get"
  }
}
```

<a id="event-21"></a>

#### SmartLighting/setRainSensing

- Category：`Sensor Configuration`。
- 来源：`A21:C21`；payload 位于 `C21`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-reza-207989-01010003",
  "Resourcepath": 207989,
  "EventId": "EV-207987-01010003-20260504074649966",
  "EventType": "SmartLighting/setRainSensing",
  "Parameters": {
    "RainUpperThreshold": 30,
    "RainLowerThreshold": 5,
    "RainSensing": "Enable",
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Unicast"
  }
}
```

### Proximity Lighting

<a id="event-22"></a>

#### SmartLighting/getProximityLighting

- Category：`Proximity Lighting`。
- 来源：`A22:C22`；payload 位于 `C22`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/getProximityLighting",
  "Parameters": {
    "CommandType": "Get",
    "Transmission": "Unicast"
  }
}
```

<a id="event-23"></a>

#### SmartLighting/setProximityLighting

- Category：`Proximity Lighting`。
- 来源：`A23:C23`；payload 位于 `C23`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/setProximityLighting",
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "LightingControl": "Enable",
    "SaveNodeSetting": "Yes",
    "NumberOfNeighbourNode": 3
  }
}
```

### Predictive Lighting

<a id="event-24"></a>

#### SmartLighting/getPredictiveLighting

- Category：`Predictive Lighting`。
- 来源：`A24:C24`；payload 位于 `C24`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/getPredictiveLighting",
  "Parameters": {
    "CommandType": "Get",
    "Transmission": "Unicast"
  }
}
```

<a id="event-25"></a>

#### SmartLighting/setPredictiveLighting

- Category：`Predictive Lighting`。
- 来源：`A25:C25`；payload 位于 `C25`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/setPredictiveLighting",
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "LightingControl": "Enable"
  }
}
```

### Timer Profiles

<a id="event-26"></a>

#### SmartLighting/getTimerProfile

- Category：`Timer Profiles`。
- 来源：`A26:C26`；payload 位于 `C26`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504062537335",
  "EventType": "SmartLighting/getTimerProfile",
  "Parameters": {
    "CommandType": "Get"
  }
}
```

<a id="event-27"></a>

#### SmartLighting/setTimerProfile

- Category：`Timer Profiles`。
- 来源：`A27:C27`；payload 位于 `C27`。
- JSON 状态：已修正原文语法；原文及修正明细见[附录 A / C27](#raw-27)。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/setTimerProfile",
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "ProfileControl": "Enable",
    "RepeatAction": 10,
    "NumberOfProfile": 2,
    "TimerProfiles": [
      {
        "ZoneId": 1,
        "StartTime": "07:00",
        "EndTime": "19:00",
        "DayOfWeek": "Everyday",
        "Action": "Force_Off"
      },
      {
        "ZoneId": 1,
        "StartTime": "19:00",
        "EndTime": "07:00",
        "DayOfWeek": "Everyday",
        "Action": "Auto"
      }
    ]
  }
}
```

### Dimming Profiles

<a id="event-28"></a>

#### SmartLighting/getDimmingProfile

- Category：`Dimming Profiles`。
- 来源：`A28:C28`；payload 位于 `C28`。
- JSON 状态：已修正原文语法；原文及修正明细见[附录 A / C28](#raw-28)。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/getDimmingProfile",
  "Parameters": {
    "CommandType": "Get",
    "Transmission": "Unicast"
  }
}
```

<a id="event-29"></a>

#### SmartLighting/setDimmingProfile

- Category：`Dimming Profiles`。
- 来源：`A29:C29`；payload 位于 `C29`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504062106560",
  "EventType": "SmartLighting/setDimmingProfile",
  "Parameters": {
    "ProfileControl": "Enable",
    "RepeatAction": 0,
    "NumberOfProfile": 2,
    "DimmingProfiles": [
      {
        "ZoneId": 255,
        "StartTime": "11:50",
        "EndTime": "23:50",
        "DayOfWeek": "Everyday",
        "DimLevel": 12,
        "BrightLevel": 70
      },
      {
        "ZoneId": 255,
        "StartTime": "11:55",
        "EndTime": "23:55",
        "DayOfWeek": "Weekday",
        "DimLevel": 22,
        "BrightLevel": 66
      }
    ],
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Unicast"
  }
}
```

### Luminance Profiles

<a id="event-30"></a>

#### SmartLighting/getLuminanceProfile

- Category：`Luminance Profiles`。
- 来源：`A30:C30`；payload 位于 `C30`。
- JSON 状态：已修正原文语法；原文及修正明细见[附录 A / C30](#raw-30)。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/getLuminanceProfile",
  "Parameters": {
    "CommandType": "Get",
    "Transmission": "Unicast"
  }
}
```

<a id="event-31"></a>

#### SmartLighting/setLuminanceProfile

- Category：`Luminance Profiles`。
- 来源：`A31:C31`；payload 位于 `C31`。
- JSON 状态：已修正原文语法；原文及修正明细见[附录 A / C31](#raw-31)。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/setLuminanceProfile",
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "ProfileControl": "Enable",
    "RepeatAction": 1,
    "NumberOfProfile": 2,
    "LuminanceProfiles": [
      {
        "ZoneId": 1,
        "StartDate": "01-01-2026",
        "EndDate": "31-12-2026",
        "LuminanceLevel": 80
      },
      {
        "ZoneId": 1,
        "StartDate": "01-01-2027",
        "EndDate": "31-12-2027",
        "LuminanceLevel": 85
      }
    ]
  }
}
```

### Daylight Profile

<a id="event-32"></a>

#### SmartLighting/getDaylightProfile

- Category：`Daylight Profile`。
- 来源：`A32:C32`；payload 位于 `C32`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504062426441",
  "EventType": "SmartLighting/getDaylightProfile",
  "Parameters": {
    "CommandType": "Get"
  }
}
```

<a id="event-33"></a>

#### SmartLighting/setDaylightProfile

- Category：`Daylight Profile`。
- 来源：`A33:C33`；payload 位于 `C33`。
- JSON 状态：原文语法有效，仅统一缩进。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504062105402",
  "EventType": "SmartLighting/setDaylightProfile",
  "Parameters": {
    "ProfileControl": "Enable",
    "RepeatAction": 0,
    "ZoneId": 255,
    "StartTime": "11:50",
    "EndTime": "23:50",
    "DimAction": "Auto",
    "BrightAction": "Auto",
    "PhotoSensor1": null,
    "PhotoSensor2": null,
    "PhotoSensor3": null,
    "DimThreshold": 200,
    "BrightThreshold": 400,
    "CommandType": "Set",
    "ConfigurationZone": 0,
    "Transmission": "Unicast"
  }
}
```

### Daylight Harvesting Profile

<a id="event-34"></a>

#### SmartLighting/getDaylightHarvestingProfile

- Category：`Daylight Harvesting Profile`。
- 来源：`A34:C34`；payload 位于 `C34`。
- JSON 状态：已修正原文语法；原文及修正明细见[附录 A / C34](#raw-34)。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/getDaylightHarvestingProfile",
  "Parameters": {
    "CommandType": "Get",
    "Transmission": "Unicast"
  }
}
```

<a id="event-35"></a>

#### SmartLighting/setDaylightHarvestingProfile

- Category：`Daylight Harvesting Profile`。
- 来源：`A35:C35`；payload 位于 `C35`。
- JSON 状态：已修正原文语法；原文及修正明细见[附录 A / C35](#raw-35)。

```json
{
  "SenderId": "Backend-600123-00",
  "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
  "Resourcepath": 207987,
  "EventId": "EV-207987-G-20260504061706597",
  "EventType": "SmartLighting/setDaylightHarvestingProfile",
  "Parameters": {
    "CommandType": "Set",
    "Transmission": "Unicast",
    "ConfigurationZone": 0,
    "ProfileControl": "Enable",
    "RepeatAction": 10,
    "OverallZone": 0,
    "StartTime": "07:00",
    "EndTime": "19:00",
    "DayOfWeek": "Weekday",
    "DaylightThreshold": 500,
    "MinLuminanceLevel": 20,
    "MaxLuminanceLevel": 90
  }
}
```

## 附录 A：语法修正与原始文本

以下 `text` 代码块逐字保留原单元格内容（不含代码块边界换行），其中的语法问题未在原文块中修改。正文 JSON 为语法修正版，不代表平台方重新确认过的报文。

<a id="raw-3"></a>

### C3 — SmartLighting/getLightingZone

- 移除包围整个对象的多余双引号及对象外空白；字符串内部保持原样。
- 移除 EventType 值开头和 Transmission 键末尾各一个多余双引号。
- `SenderId` 内末尾空格保留。

```text
 "{
    "SenderId": "SmartLighting-reza-207989-01010001 ",
    "SensorId": "SmartLighting-reza-207989-01010001",
    "Resourcepath": 902355,
    "EventId": "EV-902355-S-20260319141443233",
    "EventType": ""SmartLighting/getLightingZone",
    "Parameters": {
        "CommandType": "Get",
        "Transmission"": "Unicast"
    }
}"
```

<a id="raw-4"></a>

### C4 — SmartLighting/getTriggerZone

- 移除包围整个对象的多余双引号及对象外空白；字符串内部保持原样。

```text
"{
    "SenderId": "SmartLighting-reza-207989-01010001",
    "SensorId": "SmartLighting-reza-207989-01010001",
    "Resourcepath": 902355,
    "EventId": "EV-902355-S-20260319141443233",
    "EventType": "SmartLighting/getTriggerZone",
    "Parameters": {
        "CommandType": "Get",
        "Transmission": "Unicast"
    }
}"
```

<a id="raw-27"></a>

### C27 — SmartLighting/setTimerProfile

- 在 EventId 字符串值后补上缺少的逗号。

```text
{
    "SenderId": "Backend-600123-00",
    "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
    "Resourcepath": 207987,
    "EventId": "EV-207987-G-20260504061706597"
    "EventType": "SmartLighting/setTimerProfile",
    "Parameters": {
        "CommandType": "Set",
        "Transmission": "Unicast",
        "ConfigurationZone": 0,
        "ProfileControl": "Enable",
        "RepeatAction": 10,
        "NumberOfProfile": 2,
        "TimerProfiles": [
            {
                "ZoneId": 1,
                "StartTime": "07:00",
                "EndTime": "19:00",
                "DayOfWeek": "Everyday",
                "Action": "Force_Off"
            },
            {
                "ZoneId": 1,
                "StartTime": "19:00",
                "EndTime": "07:00",
                "DayOfWeek": "Everyday",
                "Action": "Auto"
            }
        ]
    }
}
```

<a id="raw-28"></a>

### C28 — SmartLighting/getDimmingProfile

- 在 EventId 字符串值后补上缺少的逗号。

```text
{
    "SenderId": "Backend-600123-00",
    "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
    "Resourcepath": 207987,
    "EventId": "EV-207987-G-20260504061706597"
    "EventType": "SmartLighting/getDimmingProfile",
    "Parameters": {
        "CommandType": "Get",
        "Transmission": "Unicast"
    }
}
```

<a id="raw-30"></a>

### C30 — SmartLighting/getLuminanceProfile

- 在 EventId 字符串值后补上缺少的逗号。

```text
{
    "SenderId": "Backend-600123-00",
    "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
    "Resourcepath": 207987,
    "EventId": "EV-207987-G-20260504061706597"
    "EventType": "SmartLighting/getLuminanceProfile",
    "Parameters": {
        "CommandType": "Get",
        "Transmission": "Unicast"
    }
}
```

<a id="raw-31"></a>

### C31 — SmartLighting/setLuminanceProfile

- 在 EventId 字符串值后补上缺少的逗号。

```text
{
    "SenderId": "Backend-600123-00",
    "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
    "Resourcepath": 207987,
    "EventId": "EV-207987-G-20260504061706597"
    "EventType": "SmartLighting/setLuminanceProfile",
    "Parameters": {
        "CommandType": "Set",
        "Transmission": "Unicast",
        "ConfigurationZone": 0,
        "ProfileControl": "Enable",
        "RepeatAction": 1,
        "NumberOfProfile": 2,
        "LuminanceProfiles": [
            {
                "ZoneId": 1,
                "StartDate": "01-01-2026",
                "EndDate": "31-12-2026",
                "LuminanceLevel": 80
            },
            {
                "ZoneId": 1,
                "StartDate": "01-01-2027",
                "EndDate": "31-12-2027",
                "LuminanceLevel": 85
            }
        ]
    }
}
```

<a id="raw-34"></a>

### C34 — SmartLighting/getDaylightHarvestingProfile

- 在 EventId 字符串值后补上缺少的逗号。

```text
{
    "SenderId": "Backend-600123-00",
    "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
    "Resourcepath": 207987,
    "EventId": "EV-207987-G-20260504061706597"
    "EventType": "SmartLighting/getDaylightHarvestingProfile",
    "Parameters": {
        "CommandType": "Get",
        "Transmission": "Unicast"
    }
}
```

<a id="raw-35"></a>

### C35 — SmartLighting/setDaylightHarvestingProfile

- 在 EventId 字符串值后补上缺少的逗号。

```text
{
    "SenderId": "Backend-600123-00",
    "SensorId": "SmartLighting-A4XX785242242HGFGFJH124554X-G",
    "Resourcepath": 207987,
    "EventId": "EV-207987-G-20260504061706597"
    "EventType": "SmartLighting/setDaylightHarvestingProfile",
    "Parameters": {
        "CommandType": "Set",
        "Transmission": "Unicast",
        "ConfigurationZone": 0,
        "ProfileControl": "Enable",
        "RepeatAction": 10,
        "OverallZone": 0,
        "StartTime": "07:00",
        "EndTime": "19:00",
        "DayOfWeek": "Weekday",
        "DaylightThreshold": 500,
        "MinLuminanceLevel": 20,
        "MaxLuminanceLevel": 90
    }
}
```

## 附录 B：工作簿定义名称

原工作簿还包含以下外部定义名称。此工作表没有公式或数据验证引用它们；转换未访问外部文件，也未将这些引用推导为字段约束。

| 定义名称 | 原始引用 |
| --- | --- |
| `Boolean` | `[1]MasterList!$E$2:$E$3` |
| `DeploymentType` | `[1]MasterList!$C$2` |
| `DisplayLevel` | `[1]MasterList!$A$2:$A$53` |
| `DisplayLocation` | `[1]MasterList!$B$2:$B$73` |
| `SensorPlanType` | `[1]MasterList!$D$2:$D$4` |
