# Device Parameter Settings CCT 默认值优化设计

## 背景

现有 Device Parameter Settings 已为真实支持 CCT 的 PID 设备增加两个参数：

| 参数 | 当前语义 |
| --- | --- |
| Change Control Page | 未配置时按默认值处理，决定设备在 App 中按 `Single White` 还是 `Tunable White` 展示和控制 |
| Absolute CCT Range | 未配置时按默认值处理，决定 App 侧 CCT 控制范围和下发前 clamp 范围 |

本次优化只调整一个特定设备类型的默认值和参数可见性，其他属性和保存/同步逻辑保持不变。

## 目标

对 `companyIdentifier == 0x0178 && productIdentifier == 0x2013` 的设备做特殊处理：

| 项目 | 默认值或行为 |
| --- | --- |
| Change Control Page | `Single White` |
| Absolute CCT Range | `2700K...5000K` |
| PWM frequency | 不展示、不读取、不设置、不筛选 |

对其他支持 CCT 的设备保持当前默认：

| 项目 | 默认值或行为 |
| --- | --- |
| Change Control Page | `Tunable White` |
| Absolute CCT Range | `2700K...6500K` |
| PWM frequency | 沿用现有 `supportPwmFrequency` 判断 |

## 非目标

- 不改变已配置值的优先级。只要设备本地或云同步数据中已有 `changeControlPage` 或 `absoluteCctRange`，继续使用已配置值。
- 不新增后端接口。
- 不新增 enabled/disabled 持久化字段。
- 不改变 Rated Power、Motion Sensitivity、Default Transition Time 等其他参数逻辑。
- 不迁移已有 Scene/Profile/Power Up 数据。

## 规则设计

在 SDK 的 `Node` 属性层增加一个设备类型判断，让默认值只有一个来源：

| 规则 | 说明 |
| --- | --- |
| 特殊设备判断 | `companyIdentifier == 0x0178 && productIdentifier == 0x2013` |
| `effectiveChangeControlPage` | 已配置值优先；未配置时特殊设备返回 `singleWhite`，其他设备返回 `tunableWhite` |
| `effectiveSupportCct` | 继续使用 `rawSupportCct && effectiveChangeControlPage != .singleWhite` |
| `effectiveCctRange` | 已配置值优先；未配置时特殊设备返回 `2700...5000`，其他设备返回 `2700...6500` |

这样单设备控制、组控、场景、配置页、筛选列表都能沿用已有 `effective*` 封装，不需要在各业务入口重复判断 PID。

## Device Parameter Settings 行为

Change Control Page：

| 设备类型 | 选项文案 |
| --- | --- |
| `0x0178/0x2013` | `Single White (Default)`、`Tunable White` |
| 其他支持 CCT 设备 | `Single White`、`Tunable White (Default)` |

Absolute CCT Range：

| 设备类型 | 开关打开后的默认预填 |
| --- | --- |
| `0x0178/0x2013` | `2700K...5000K` |
| 其他支持 CCT 设备 | `2700K...6500K` |

多设备选择时，页面沿用当前与 Rated Power 对齐的规则：

| 场景 | 展示 |
| --- | --- |
| 所有选中设备有效值一致 | 展示共同值 |
| 有属性冲突 | 展示当前 PID 类型的默认值 |

Device Parameter Settings 只能从同一 PID 设备集合进入，因此不会出现特殊 PID 与其他 PID 混合展示的情况。

## PWM frequency

`0x0178/0x2013` 设备应在 `supportPwmFrequency` 层返回不支持。这样以下入口自然不会出现 PWM frequency：

| 入口 | 影响 |
| --- | --- |
| 参数设置页 | 不展示 PWM frequency cell |
| 读取参数 | 不发起 PWM frequency 读取 |
| 同步参数 | 不发起 PWM frequency 设置 |
| 设备参数列表 | 不展示 PWM 行 |
| 筛选弹窗 | 不出现 PWM 筛选项 |

其他设备继续沿用当前 `supportPwmFrequency` 逻辑。

## 数据与同步

数据保存和云同步语义保持上一版 CCT 设计：

| 参数 | 行为 |
| --- | --- |
| Change Control Page | 开关打开后直接更新本地并进入现有云同步 JSON |
| Absolute CCT Range | 开关打开后下发 `LightCTLTemperatureRangeSet`，成功后保存本地并进入现有云同步 JSON |
| 未配置值 | 不落库、不导出字段，读取时走设备类型默认值 |
| 删除设备后重新添加 | 因配置被删除，重新按设备类型默认值处理 |

## 测试关注点

| 场景 | 期望 |
| --- | --- |
| `0x0178/0x2013` 未配置 Change Control Page | 展示 `Single White`，有效 CCT 能力为不支持 |
| `0x0178/0x2013` 未配置 CCT Range | 有效范围为 `2700K...5000K` |
| `0x0178/0x2013` 已配置 `Tunable White` | 配置值优先，设备有效支持 CCT |
| 其他 CCT 设备未配置 Change Control Page | 展示 `Tunable White`，有效 CCT 能力为支持 |
| 其他 CCT 设备未配置 CCT Range | 有效范围为 `2700K...6500K` |
| `0x0178/0x2013` 进入 Device Parameter Settings | 不展示 PWM frequency |
| 其他原本支持 PWM 的设备进入 Device Parameter Settings | PWM frequency 保持可见 |
| 多设备同值 | 展示共同值 |
| 多设备冲突 | 展示该 PID 类型默认值 |

