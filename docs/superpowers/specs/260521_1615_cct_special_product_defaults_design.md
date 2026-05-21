# 特殊 CCT 产品默认值更新设计

## 背景

Device Parameter Settings 已支持对 CCT 设备配置 `Change Control Page` 和 `Absolute CCT Range`。当前特殊默认值规则只覆盖 `companyIdentifier == 0x0A78 && productIdentifier == 0x2013`：

| 参数 | 特殊默认值 |
| --- | --- |
| Change Control Page | `Single White` |
| Absolute CCT Range | `2700K...5000K` |
| PWM frequency | 不展示、不读取、不设置、不筛选 |

本次需要把 `productIdentifier == 0x24B1` 纳入同一类特殊 CCT 产品。

## 目标

对以下两个 PID 统一应用特殊 CCT 默认值规则：

| Company ID | Product ID |
| --- | --- |
| `0x0A78` | `0x2013` |
| `0x0A78` | `0x24B1` |

统一后的行为：

| 项目 | 默认值或行为 |
| --- | --- |
| Change Control Page | `Single White (Default)` |
| Absolute CCT Range | `2700K...5000K` |
| PWM frequency | 不展示、不读取、不设置、不筛选 |
| Details 文案 | 使用特殊单白光默认设备文案 |

## 非目标

- 不改变已配置值的优先级。只要设备本地或云同步数据中已有 `changeControlPage` 或 `absoluteCctRange`，继续使用已配置值。
- 不新增后端接口或云同步字段。
- 不新增 enabled/disabled 持久化字段。
- 不改变其他 CCT 设备的默认值：仍为 `Tunable White` 和 `2700K...6500K`。
- 不改变 Rated Power、Motion Sensitivity、Default Transition Time 等其他参数逻辑。

## 规则设计

推荐继续把特殊产品判断集中在 SDK 的 `Node` 属性层，避免 Device Parameter Settings、设备列表、场景、组控等入口重复判断 PID。

| 规则 | 说明 |
| --- | --- |
| 特殊产品判断 | `companyIdentifier == 0x0A78 && productIdentifier` 属于 `[0x2013, 0x24B1]` |
| `defaultChangeControlPage` | 特殊产品返回 `.singleWhite`，其他产品返回 `.tunableWhite` |
| `defaultAbsoluteCctRange` | 特殊产品返回 `2700...5000`，其他产品返回 `2700...6500` |
| `effectiveChangeControlPage` | 已配置值优先；未配置时使用 `defaultChangeControlPage` |
| `effectiveCctRange` | 已配置值优先；未配置时使用 `defaultAbsoluteCctRange` |
| `effectiveSupportCct` | 继续使用 `rawSupportCct && effectiveChangeControlPage != .singleWhite` |

## Device Parameter Settings 行为

当入口设备为 `0x0A78/0x2013` 或 `0x0A78/0x24B1`：

| UI 项 | 展示 |
| --- | --- |
| Change Control Page | 默认选中 `Single White`，选项文案显示 `Single White (Default)` |
| Absolute CCT Range | 默认预填 `2700K...5000K` |
| Change Control Page Details | 使用特殊单白光默认设备文案 |
| PWM frequency | 不展示 |

当入口设备为其他 CCT 设备：

| UI 项 | 展示 |
| --- | --- |
| Change Control Page | 默认选中 `Tunable White`，选项文案显示 `Tunable White (Default)` |
| Absolute CCT Range | 默认预填 `2700K...6500K` |
| Change Control Page Details | 使用普通 CCT 设备文案 |
| PWM frequency | 沿用现有支持判断 |

多设备选择继续沿用现有规则：若有效值一致，展示共同值；若存在冲突，回退到当前 PID 类型默认值。Device Parameter Settings 当前按同类设备集合进入，因此本设计不处理特殊 PID 与普通 PID 混合展示。

## PWM frequency

App 侧 `supportPwmFrequency` 需要同步把 `0x0A78/0x24B1` 纳入排除条件，使其与 `0x0A78/0x2013` 行为一致：

| 入口 | 影响 |
| --- | --- |
| Device Parameter Settings | 不展示 PWM frequency cell |
| 参数读取 | 不发起 PWM frequency 读取 |
| 参数设置 | 不发起 PWM frequency 设置 |
| 设备参数列表 | 不展示 PWM 行 |
| 筛选弹窗 | 不出现 PWM 筛选项 |

## 数据与同步

数据保存和云同步语义保持不变：

| 参数 | 行为 |
| --- | --- |
| Change Control Page | 开关打开后更新本地并进入现有云同步 JSON |
| Absolute CCT Range | 开关打开后下发 `LightCTLTemperatureRangeSet`，成功后保存本地并进入现有云同步 JSON |
| 未配置值 | 不落库、不导出字段，读取时走设备类型默认值 |
| 删除设备后重新添加 | 因配置被删除，重新按设备类型默认值处理 |

## 测试关注点

| 场景 | 期望 |
| --- | --- |
| `0x0A78/0x2013` 未配置 Change Control Page | 展示 `Single White (Default)` |
| `0x0A78/0x24B1` 未配置 Change Control Page | 展示 `Single White (Default)` |
| `0x0A78/0x2013` 未配置 CCT Range | 有效范围为 `2700K...5000K` |
| `0x0A78/0x24B1` 未配置 CCT Range | 有效范围为 `2700K...5000K` |
| 两个特殊 PID 已配置 `Tunable White` | 配置值优先，设备有效支持 CCT |
| 其他 CCT 设备未配置 Change Control Page | 展示 `Tunable White (Default)` |
| 其他 CCT 设备未配置 CCT Range | 有效范围为 `2700K...6500K` |
| 两个特殊 PID 进入 Device Parameter Settings | 不展示 PWM frequency |
| 其他原本支持 PWM 的设备进入 Device Parameter Settings | PWM frequency 保持可见 |

## 自检

- 无占位项或未定需求。
- SDK 默认值规则、Device Parameter Settings 展示、PWM 排除条件三者一致。
- 范围仅覆盖两个 PID 的默认值和 PWM 支持判断，不包含无关 UI 样式或数据结构调整。
