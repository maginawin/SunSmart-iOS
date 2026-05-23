# Group Profile Low-End Trim 默认值设计

## 背景

当前 group profile 的 low-end trim 默认值为 0%。代码中主要默认来源如下：

- `Profile.LightData.init(profileType:)` 使用 `lowEndTrim = 0`。
- `Profile.LightControlData.lowEndTrim` 属性默认值为 `0`。
- `Profile.LightControlData.init(...)` 默认参数为 `lowEndTrim: Int = 0`。
- `GroupAddViewController` 新建 group 时预置 8 个 `Profile(type:)` 模板，并将选中的模板保存到 `group.info.profile`。
- `ImportData` 在导入数据缺少 `lowEndTrim` 时 fallback 到 `0`。

业务目标是将未来新建 group profile 的默认 low-end trim 改为 1%，同时不改变任何已经创建的 group profile 值，避免现有设备出现大范围同步需求。

## 目标

- 新建 group 使用的默认 profile 模板 low-end trim 为 1%。
- 新建 group 流程中切换到任意 profile 类型时，该类型默认 low-end trim 为 1%。
- 已存在 group 当前保存的 profile 不被自动修改，原来是 0% 就继续保持 0%。
- 已存在 group 进入编辑页时，继续显示并保存原 profile，除非用户主动修改 profile 内容。
- 不做数据库迁移，不批量更新 `profiles` 表。
- 不改变导入旧数据缺少 `lowEndTrim` 时的 fallback 行为。

## 非目标

- 不重算或修正现有 group 的 profile 数据。
- 不主动触发已有设备的 high/low end trim 同步。
- 不调整 low-end trim 的 UI 可选范围，仍保持现有 0...30。
- 不改变用户手动保存 profile 后的既有同步流程。

## 推荐方案

新增或集中一个用于“默认 group profile 模板”的创建入口，将模板 low-end trim 设为 1%。`GroupAddViewController` 和 `ProfileSettingsViewController` 中用于类型选择的默认 profile 列表都使用该入口。

保留 `Profile.LightControlData` 的通用默认值 0，避免影响导入、历史 fallback、以及其它未明确属于 group profile 默认模板的调用点。这样可以把行为变化限制在“新模板创建”场景内。

对于 `proximityLightingWithPhotocell`，默认包含 general、night、day 三个 scene。模板入口应确保这些默认 scene 的 `LightControlData.lowEndTrim` 一致为 1%，避免同一个默认 profile 内部出现 general scene 为 1%、day/night scene 仍为 0 的不一致。

## 数据流

新建 group：

1. `GroupAddViewController` 构造默认 profile 模板列表。
2. 用户选择 profile 类型，或保持默认第一项。
3. 创建 group 后，`finnished()` 将选中的 profile copy/update 到 `group.info.profile`。
4. 保存 `group.info` 和 `group.info.profile`。
5. 后续同步逻辑按已保存 profile 的实际 low/high end trim 判断。

编辑已有 group：

1. `GroupAddViewController` 接收已有 `group` 时，`selectProfile = group.info.profile`。
2. 不使用默认模板覆盖该 group 当前 profile。
3. 保存时仍保存原 profile 数据，除非用户主动切换或编辑。

Profile 设置页：

1. 初始化时用传入 profile 的 copy 作为 `selectProfile`。
2. 默认模板列表中同类型项被传入 profile 替换。
3. 因此当前 group 已保存 profile 不会被模板默认值覆盖。
4. 如果用户主动切换到其它 profile 类型，该类型来自默认模板，low-end trim 为 1%；只有用户保存后才会影响 group。

## 错误处理与兼容性

- 数据库读取继续以已保存字段为准，不对 0% 做隐式升级。
- 导入数据缺少 `lowEndTrim` 时继续 fallback 到 0，保持旧导入语义。
- 如果某些设备当前 high/low trim 与 group profile 不一致，仍由现有 `needSync` 和同步流程处理，不新增自动同步入口。

## 测试计划

- 验证新建 group 默认 `Occupancy daylight` profile 的 low-end trim 为 1%。
- 验证新建 group 中切换每一种 profile 类型后，low-end trim 为 1%。
- 验证 `proximityLightingWithPhotocell` 的 general、night、day scene 默认 low-end trim 均为 1%。
- 验证编辑已有 low-end trim 为 0% 的 group 时，进入页面和保存后仍保持 0%。
- 验证导入缺少 `lowEndTrim` 的历史数据时仍保持 0% fallback。
- 编译验证 `SunSmart` scheme。

## 自审结果

- 无占位符、TODO 或未决需求。
- 范围聚焦在默认模板创建，不包含数据库迁移或设备同步改造。
- 已明确区分新建 group、编辑已有 group、Profile 设置页切换类型三类场景。
- 已明确 `proximityLightingWithPhotocell` 的多 scene 一致性要求。
