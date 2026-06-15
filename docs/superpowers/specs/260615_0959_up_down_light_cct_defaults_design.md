# Up Down Light CCT 默认值设计

## 背景

目标设备为 `CID 0x0A78 / PID 0x2491`，型号在 `SunSmart/devices_config.json` 中记录为 `SR-BL2421_SSV_2CH`。用户期望该设备进入 `Site - Space - More - Device Parameter Settings` 后：

| 参数 | 期望 |
|---|---|
| Change Control Page | `Single White`、`Tunable White (Default)` |
| Absolute CCT Range | 默认值 `2700K...5000K` |

现有 Device Parameter Settings 不在 cell 内写死默认值，而是读取 SDK `Node` 的派生属性：

| App 入口 | 默认值来源 |
|---|---|
| Change Control Page | `Node.defaultChangeControlPage` |
| Absolute CCT Range | `Node.defaultAbsoluteCctRange` |

## 现状结论

当前实现不完全符合预期。

| 参数 | 当前结果 | 结论 |
|---|---|---|
| Change Control Page | `Tunable White` 为默认项 | 符合预期 |
| Absolute CCT Range | `2700K...6500K` | 不符合预期 |

根因在 SDK 层：`NodeAbsoluteCctRange.singleWhiteDefaultRange` 已经是 `2700...5000`，但 `Node.defaultAbsoluteCctRange` 只有在 `isSingleWhiteDefaultCctProduct == true` 时才使用它。当前 `isSingleWhiteDefaultCctProduct` 只覆盖 `0x0A78 / 0x2013` 和 `0x0A78 / 0x24B1`，不包含 `0x0A78 / 0x2491`。

不能直接把 `0x2491` 加进 `isSingleWhiteDefaultCctProduct`，因为这会同时把 `defaultChangeControlPage` 改成 `Single White`，与本次预期的 `Tunable White (Default)` 冲突。

## 方案选择

采用方案 A：在 SDK 默认值层拆分 Change Control Page 默认规则和 Absolute CCT Range 默认规则。

| 方案 | 做法 | 结论 |
|---|---|---|
| A | 新增独立的窄 CCT range 默认判断，`0x2491` 只影响 `defaultAbsoluteCctRange` | 推荐 |
| B | 只在 App 的 Device Parameter Settings 覆盖 `0x2491` range | 不推荐，其他依赖 `effectiveCctRange` 的入口仍可能不一致 |
| C | 把 `0x2491` 加入 `isSingleWhiteDefaultCctProduct` | 不推荐，会破坏 Change Control Page 默认值 |

## 设计

SDK 层保留现有 `isSingleWhiteDefaultCctProduct` 语义，只让它继续控制：

| 属性 | 行为 |
|---|---|
| `defaultChangeControlPage` | 特殊单白产品默认 `singleWhite`，其他 CCT 产品默认 `tunableWhite` |
| `changeControlPageMessageForSelection` | 单白默认产品使用特殊说明文案 |

新增或调整一个只服务 CCT range 的产品判断，用于 `defaultAbsoluteCctRange`：

| 产品 | 默认 Change Control Page | 默认 Absolute CCT Range |
|---|---|---|
| `0x0A78 / 0x2013` | `Single White` | `2700K...5000K` |
| `0x0A78 / 0x24B1` | `Single White` | `2700K...5000K` |
| `0x0A78 / 0x2491` | `Tunable White` | `2700K...5000K` |
| 其他 CCT 产品 | `Tunable White` | `2700K...6500K` |

`effectiveCctRange` 继续保持“已配置值优先，未配置时使用默认值”的现有合同。这样 Device Parameter Settings、单灯控制页、组控、场景和 Profile 等依赖有效 CCT range 的入口都会获得一致默认范围。

## 非目标

- 不改变 `0x2491` 的 `Change Control Page` 默认值。
- 不改变已保存的 `changeControlPage` 或 `absoluteCctRange` 优先级。
- 不新增云同步字段、导入导出字段或 enabled 状态字段。
- 不调整 Device Parameter Settings 的 UI 布局、文案样式或交互。
- 不修改 Up/Down Ratio 控件、顶部 Up Down Light 视觉或现有图片资源。

## 影响范围

| 模块 | 影响 |
|---|---|
| NordicSigMeshSDK `Node` 默认属性 | 增加 `0x2491` 的窄默认 CCT range 规则 |
| Device Parameter Settings | 未配置的 `0x2491` 展示 `2700K...5000K` |
| CCT 控制相关入口 | 未配置的 `0x2491` clamp 范围随 `effectiveCctRange` 变为 `2700K...5000K` |
| 已配置设备 | 保持已有配置值，不被默认值覆盖 |

## 验证计划

1. 静态检查 `0x2491` 不在 `isSingleWhiteDefaultCctProduct` 中，避免 Change Control Page 默认变成 Single White。
2. 静态检查 `0x2491` 被新的 CCT range 默认规则覆盖，默认范围为 `2700...5000`。
3. 运行 `git diff --check`。
4. 运行 iPhoneOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 验收标准

| 场景 | 期望 |
|---|---|
| `0x0A78 / 0x2491` 未配置 Change Control Page | Device Parameter Settings 显示 `Tunable White (Default)` |
| `0x0A78 / 0x2491` 未配置 Absolute CCT Range | Device Parameter Settings 显示 `2700K...5000K` |
| `0x0A78 / 0x2491` 已配置 Absolute CCT Range | 继续显示已配置值 |
| `0x0A78 / 0x2013`、`0x0A78 / 0x24B1` | 继续保持 Single White 默认和 `2700K...5000K` |
| 其他 CCT 产品 | 继续保持 Tunable White 默认和 `2700K...6500K` |
