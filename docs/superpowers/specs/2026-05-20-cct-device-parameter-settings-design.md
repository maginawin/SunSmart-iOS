# CCT Device Parameter Settings 设计

## 背景

当前 App 判断设备是否支持 CCT 的核心依据是 `node.temperatureModel != nil`，也就是设备 Composition Data 中存在 `Light CTL Temperature Server`。色温范围优先使用设备读取到的 `node.lightCTLTemperatureRange`，没有读取到时使用 SDK 默认范围 `2700K...6500K`。

本设计在 `Site - Space - More - Device Parameter Settings` 中为支持 CCT 的 PID 设备增加两个设备参数：

| 参数 | 目的 |
|---|---|
| Change Control Page | 允许 App 将真实支持 CCT 的设备按 Tunable White 或 Single White 展示和控制 |
| Absolute CCT Range | 配置设备允许的绝对 CCT 色温范围，并影响所有 App 侧 CCT 输入、展示和下发 |

## 已确认需求

| 需求点 | 结论 |
|---|---|
| 适用设备 | 仅真实支持 CCT 的设备展示这两个参数，即原始能力 `temperatureModel != nil` |
| 云同步 | 后端没有新接口，扩展现有 node JSON 字段 |
| 保存模型 | 与 Rated Power 一致：外层开关默认关闭，只有打开时才更新该参数；关闭表示不修改已有值 |
| 持久化内容 | 不保存 enabled/disabled 状态，仅保存参数值 |
| Change Control Page 默认值 | 未配置时按 `Tunable White` 处理，也就是支持 CCT |
| Absolute CCT Range 默认值 | 未配置时按 `2700K...6500K` 处理 |
| Change Control Page 下发 | 不下发给设备，本地直接保存成功 |
| Absolute CCT Range 下发 | 需要下发设备成功后才保存本地 |
| 批量冲突展示 | 打开参数开关时，单设备展示设备值；多设备值一致展示共同值；多设备值冲突展示默认值 |
| 旧值越界 | 不主动改写旧 Scene/Profile/PowerUp 配置；显示、保存、执行和下发前按当前有效范围 clamp |
| 删除设备 | 删除设备后清理本地配置；同一设备重新添加后恢复默认值 |

## 数据模型

新增 App 侧设备级 CCT 参数模型。模型挂在 `Node` 设备属性层，不改变底层 Mesh Composition Data 的真实能力。

| 字段 | 类型 | 默认解释 |
|---|---|---|
| `changeControlPage` | 枚举：`singleWhite`、`tunableWhite` | 未配置时为 `tunableWhite` |
| `absoluteCctRange` | `ClosedRange<UInt16>` | 未配置时为 `2700...6500` |

不新增 `changeControlPageEnabled` 或 `absoluteCctRangeEnabled` 之类的持久化字段。Device Parameter Settings 的开关只表示“本次是否设置该参数”，不属于设备配置数据。

### 云字段

node JSON 扩展以下字段：

| 字段 | 说明 |
|---|---|
| `changeControlPage` | `singleWhite` 或 `tunableWhite` |
| `absoluteCctRangeMin` | 绝对色温范围下限 |
| `absoluteCctRangeMax` | 绝对色温范围上限 |

导出时只有本地有显式配置的值才需要写入；导入时如果字段不存在，则按默认值解释。

### 本地存储

本地存储跟随现有 Node property 保存方式，和 `phaseEnergyConsumptions`、`lightCTLTemperatureRange` 这类设备属性保持同一层级。设备删除时在 `Node.deleteExtension()` 中清理 CCT 配置缓存，避免重新添加同一设备时继承旧配置。

## 有效能力与有效范围

新增统一能力封装层，所有 UI、展示、保存和下发入口都使用“有效能力”，不再直接散落判断 `temperatureModel != nil`。

| 能力 | 规则 |
|---|---|
| 原始 CCT 能力 | `node.temperatureModel != nil`，表示设备真实 Mesh 能力 |
| `node.effectiveSupportCct` | 原始支持 CCT 且 `changeControlPage != singleWhite` |
| `node.effectiveCctRange` | `absoluteCctRange` 显式配置值优先；否则按默认范围 `2700...6500` |
| `group.effectiveSupportCct` | 组内存在任一 `effectiveSupportCct == true` 的设备 |
| `group.effectiveCctRange` | 组内有效 CCT 设备的范围并集，下限取最小值，上限取最大值 |

`Single White` 不修改设备真实模型，只让 App 侧把该设备视为不支持 CCT。这样保留 Mesh 调试和设备恢复时的真实能力信息。

## Device Parameter Settings 交互

### 展示入口

在 `Site - Space - More - Device Parameter Settings` 进入 PID 列表后，仅当当前 PID 的设备真实支持 CCT 时，在参数设置页展示：

| 参数 | 默认开关 | 默认编辑值 |
|---|---|---|
| Change Control Page | 关闭 | `Tunable White` |
| Absolute CCT Range | 关闭 | `2700K...6500K` |

### 打开参数开关后的预填

| 选择设备 | Change Control Page 显示 | Absolute CCT Range 显示 |
|---|---|---|
| 单设备 | 设备配置值；未配置时默认 `Tunable White` | 设备配置值；未配置时默认 `2700K...6500K` |
| 多设备且值一致 | 共同值 | 共同范围 |
| 多设备且值冲突 | 默认 `Tunable White` | 默认 `2700K...6500K` |

这与 Rated Power 的保存语义一致：开关关闭不修改，开关打开后用当前 UI 值覆盖所有选中设备。但预填逻辑比现有 Rated Power 更明确，允许在没有冲突时展示已有值。

### 保存结果

| 参数 | 保存逻辑 |
|---|---|
| Change Control Page | 开关打开后直接写入所有选中设备本地配置，视为全部成功 |
| Absolute CCT Range | 开关打开后下发 `LightCTLTemperatureRangeSet`；每个设备下发成功后写本地，失败设备保留原值 |

如果两个参数同时打开，结果按参数和设备拆分：

| 情况 | 结果 |
|---|---|
| Change Control Page 成功，Absolute CCT Range 部分失败 | Change Control Page 对所有选中设备生效；Absolute CCT Range 仅成功设备生效，失败设备进入现有失败/重试展示 |
| Absolute CCT Range 全部失败 | Change Control Page 仍可成功；Absolute CCT Range 不写失败设备本地 |

成功写本地后，沿用现有 `spaceDataChanged(.device)` 触发后台云同步。云同步失败不回滚本地，保留 `syncCloudError` 与 `needUploadCloud`，后续由现有入口重试。

## 云同步与重试

云同步沿用当前空间同步模型：

| 场景 | 行为 |
|---|---|
| 本地成功更新 | 发送 `spaceDataChanged(.device)` |
| SpaceViewController 收到变更 | 更新 `space.lastUpdate` 并触发 `syncSpace(.promptly)` |
| 云同步成功 | 更新 `lastUploadCloudTimestamp`，清空 `syncCloudError` |
| 云同步失败 | 写入 `syncCloudError`，保持 `needUploadCloud == true` |

后续重试入口复用现有行为：点击 Space 或 Site 的同步失败图标、离开 Space 页面、进入 Site 详情、分享前强制同步、Site 详情批量同步失败 Spaces 等。`syncCloudError` 本身不触发重试，它只是错误缓存。

## 控制入口调整

所有可设置或展示 CCT 的入口都改用有效能力和有效范围。

| 入口 | 调整 |
|---|---|
| 单设备控制页 | 使用 `effectiveSupportCct` 控制 CCT UI 显隐；滑条范围使用 `effectiveCctRange`；下发前 clamp |
| 单设备基础控制页 | 行数、CCT cell、百分比换算使用有效能力和有效范围 |
| 多灯批量控制 | `supportOptions` 只统计有效 CCT 设备；范围取有效范围并集；逐设备下发前按各自范围 clamp |
| 组控 | CCT UI 使用 `group.effectiveSupportCct`；滑条范围使用 `group.effectiveCctRange` |
| Scene 设置与执行 | 设置时按目标组有效范围限制；旧值不改写，执行前 clamp |
| Power Up Behavior / Profile | CCT 输入和下发使用相关设备或组的有效范围；旧值不改写，保存或下发前 clamp |
| 设备列表与 Header | `Single White` 设备不展示 CCT 状态；颜色和百分比使用有效范围 |

## 错误处理

| 错误 | 行为 |
|---|---|
| Absolute CCT Range 下发失败 | 该设备该参数失败，不写本地，不影响 Change Control Page 成功 |
| 云同步失败 | 本地保持成功状态，显示同步失败，后续现有入口重试 |
| 范围输入非法 | 下限限制 `1000K...2700K`，上限限制 `5000K...10000K`，步进 `100K`，且下限必须小于上限 |
| 设备不支持 CCT | 不显示两个新参数，不参与有效 CCT 范围并集 |

## 测试与验证

| 类型 | 验证点 |
|---|---|
| 编译 | `SunSmart` Debug iphoneos 无签名构建 |
| 数据导入导出 | 新字段可导出到 node JSON；旧数据缺字段时按默认值解释 |
| Device Parameter Settings | 开关默认关闭；打开后单设备/多设备一致/多设备冲突的预填符合规则 |
| Change Control Page | 设为 `Single White` 后，设备页、组控、批量控制、Scene/Profile 入口不再将该设备作为 CCT 设备 |
| Absolute CCT Range | 下发成功后单设备范围、组并集、批量控制、Scene/Profile 输入限制生效 |
| 部分失败 | Absolute CCT Range 部分设备失败时，只成功设备写本地，失败设备保留旧值 |
| 云失败 | 本地成功后云失败保留 `syncCloudError` 与 `needUploadCloud`，后续现有重试入口可重新同步 |
| 删除恢复 | 删除设备后清理配置；重新添加同一设备后使用默认值 |

## 非目标

| 项目 | 说明 |
|---|---|
| 新后端 API | 不新增，继续使用现有 site/space props JSON |
| 改写设备真实能力 | 不修改 `temperatureModel` 或 Composition Data 解析逻辑 |
| 主动迁移历史场景 | 不在修改范围时批量改写旧 Scene/Profile/PowerUp CCT 值 |
| 访客权限写入 | 维持现有权限模型，不为新参数新增权限绕过 |
