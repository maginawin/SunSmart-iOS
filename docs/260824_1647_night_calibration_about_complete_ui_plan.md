# Night Calibration About 与完成态 UI 优化计划

## 1. 结论

需求整体完整、合理，可以在 App 当前工作树内以聚焦改动完成，不需要修改 `NordicSigMeshSDK`、数据库结构、校准协议或 Mesh 配置流程。

本次需求包含两类互相独立的调整：

1. `About` 的首次展开状态：只根据进入页面时的有效校准状态初始化一次；页面内后续切换模式、选择传感器、开始重新校准或完成校准，均不再自动改变该状态。
2. Night Cal. 完成态样式：按 Figma `Card / Calibration Complete` 的三个指定子组件重建布局，同时保留既有目标值来源、重新校准动作和 pending-device 异常提示能力。

开始开发前仍需确认一项文案业务语义，见第 5 节。

## 2. 当前实现与状态语义

### 2.1 About 当前行为

`LightSensorCalibrationAboutView` 当前内部默认 `isExpanded = true`：

- 初始化时展开；
- 用户点击 Header 时手动切换；
- `updateMode` 只更新标题和说明内容，不改变展开状态。

控制器进入页面时会先解析 Group 当前有效校准模式，再选择对应 Segment，并通过回调更新 About 内容。当前缺少的只是“首次进入时按 Active 初始化展开状态”的单次调用。

因此无需把 About 展开状态与 Profile、sensor 或 Segment 做持续绑定。持续绑定反而会违反“页面内更改配置和状态后不自动改变 About”的要求。

### 2.2 当前有效校准模式

页面的 `Active` 使用 `effectiveActiveCalibrationMode`：

- Profile 不是 daylight 类型时为 `none`；
- 当前 Group 无法解析出有效的 daylight sensor，或 sensor 未完成校准时为 `none`；
- sensor 有效且已校准时，使用持久化的 Night / Sensor / Plane 模式；
- 旧数据缺少模式字段但 sensor 有效时，兼容为 Plane。

建议 About 首次状态复用这一事实源，避免“Active 显示 None，但 About 却按另一套 publication 条件收起”的双重标准：

| 进入页面时的 Active | 首次 About 状态 |
| --- | --- |
| `None` | 展开 |
| `Night Cal.` / `Sensor Cal.` / `Plane Cal.` | 收起 |

这里把“Group 已完成校准并启用了对应 daylight sensor”解释为页面当前已存在非 None 的有效 Active。不会额外读取实时 Mesh 状态，也不会仅为了 About 再检查 publication address。

### 2.3 Night 完成态当前行为

Night 完成态在 Profile 模式为 `nightCal` 且页面不处于 Re-calibrate 草稿时显示。现有功能包括：

- 显示目标照度；
- 显示取样亮度；
- 有未同步设备时显示 pending 数量；
- 点击 Re-calibrate 只进入页面内草稿，不提前清除已保存的 Active。

以上业务行为均应保留。本次只调整视图结构、样式和明确要求修改的文案。

## 3. Figma 结构化差异

参考节点：`519:15390`，组件名为 `Card / Calibration Complete`。

### 3.1 外层 Card

- 白色背景，圆角 16；
- 左右内边距 16，上 16，下 20；
- 标题为 14 pt Regular、行高 20，颜色 `#1B1425`；
- 标题与内容区间距 16；
- 内容区三个正常态组件之间间距 12。

当前标题为 15 pt，内容没有统一的纵向 Card 容器和设计间距。

### 3.2 Value Card / Target Level

Figma：

- 背景 `#F6F8FF`，圆角 14；
- 内边距：水平 16、垂直 12；
- 第一行是完整文本 `Target level: 842 lx`，12 pt Regular、行高 20、颜色 `#1E2329`；
- 第二行是 `(Set at 50% brightness)`，12 pt Regular、行高 16、颜色 `#94A3B8`，与第一行间隔 2。

当前：

- `Target level`、大号 `842 lx`、brightness 分成三行；
- 数值使用 22 pt Light；
- 无浅蓝 Value Card 背景和 14 圆角；
- brightness 缺少括号，字号为 11。

### 3.3 Notice / Profile Update

Figma：

- 背景 `#FFF9EF`，圆角 14；
- 内边距：水平 16、垂直 12；
- 左侧 16×16 橙色提示图标，顶部偏移 2；
- 图标与正文间距 8；
- 正文 11 pt、行高 17.875、颜色 `#BB4D00`；
- `Vacant` 使用 Semibold，其余为 Regular；
- 英文文案为：`The Occupancy level values in Profile have been updated. Please review the Vacant level to ensure it is set correctly.`

当前：

- 无提示图标；
- 使用浅蓝背景和蓝灰正文；
- 圆角仅 8；
- 文案内容不同且没有 `Vacant` 强调。

共享资源 `site_entry_sync_warning` 的路径、尺寸、描边和颜色与 Figma 提示图标一致，可直接复用，不需要新增重复资源。

### 3.4 Action Row / Recalibrate

Figma：

- 1 pt `#ECECEC` 边框，圆角 14；
- 内容内边距：水平 16、垂直 14；
- 左侧 `Re-calibrate` 为 14 pt Regular、行高 20、颜色 `#1B1425`；
- 右侧为 16×16、颜色 `#8B96A8` 的带横线 disclosure arrow；
- 整行可点击。

当前：

- 是无边框、无图标的整宽文字按钮；
- 文案颜色使用品牌 Bar 色；
- 底部贴住外层 Card，没有 Figma 的左右边距和独立圆角行。

现有 `arrow_right` 是 30 pt 画布上的 chevron，外形不等同于 Figma 的 16 pt 带横线箭头。实施时应导入 Figma 原始 disclosure SVG 为共享 asset；共享 `Assets.xcassets` 已由四个品牌 target 引用。

### 3.5 Pending 异常状态

Figma 正常态节点没有 pending-device 文案，但现有流程在 Night 校准参数已保存、Group member 尚未全部同步时会进入完成态，因此 pending 信息具有功能价值，并且已有契约保护。

建议：

- pending 数量为 0 时，页面严格呈现 Figma 的三个组件；
- pending 数量大于 0 时，保留现有异常提示，作为额外状态行显示；
- 不删除 pending 计算，不改变 Configuring、STOP、RETRY、CANCEL 或 Auto 恢复语义。

## 4. 开发方案

### 4.1 About 单次初始化

涉及：

- `LightSensorCalibrationAboutView.swift`
- `LightSensorCalibrationViewController.swift`

方案：

1. 给 About View 增加受控的展开状态设置入口，并继续由 View 自己维护后续用户交互状态。
2. 页面完成初始 sensor、Active 和 Segment 解析后，只调用一次：Active 为 None 时展开，否则收起。
3. 现有模式切换回调只更新 About 内容和对应配置 UI，不调用展开状态入口。
4. 传感器选择、Re-calibrate、Apply 成功、失败/回滚、Active 更新均不自动改变 About。
5. 保留现有箭头、divider、body 和 accessibility value 的同步更新。

### 4.2 重建 Night 完成态内部布局

涉及：

- `LightSensorCalibrationModeView.swift`

方案：

1. 外层使用纵向 Stack 表达标题、内容区和统一间距，避免依赖多个互相串联的绝对约束。
2. Target level 改为 Figma 的两行 Value Card，目标值仍来自现有 `taskLevel` / `occupancyLevel` 分支，取样亮度仍来自持久化 `targetNightBrightness`。
3. Notice 改为“图标 + 可换行富文本”，复用现有精确匹配的 warning asset，并对本地化中的重点词单独使用 Semibold。
4. Re-calibrate 改为整行 Button 容器，增加边框、圆角、左右布局和 Figma disclosure asset；点击区域覆盖整行，继续调用既有 `recalibrateHandler`。
5. 继续支持 Dynamic Type 之外的项目现有 `SCRXFrom` / `SCRYFrom` 缩放和多行文本自适应，不写固定整体高度。
6. pending 异常提示保留为条件显示的额外 arranged subview，避免正常态出现多余间距。

### 4.3 本地化与共享资源

涉及：

- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart/Assets.xcassets/Common/`

方案：

1. 更新/新增完整 Target level 格式、带括号 brightness 和 Notice 富文本所需 Key；英文与简体中文同步。
2. Notice 的强调词不靠硬编码 Range 猜测，使用可本地化片段或格式化数据构建 attributed string，保证中英文都能正确加粗。
3. 复用 `site_entry_sync_warning`；仅新增 Figma disclosure SVG，避免修改品牌专属资源目录。
4. 检查新资源在 SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 shared Assets 引用和编译结果。

## 5. 待确认业务语义

Figma Notice 固定写“Occupancy level 已更新，请检查 Vacant level”，但当前 Night 校准保存逻辑是：

- `.occupancy_daylight` / `.vacancy_daylight`：更新 `occupancyLevel`；
- `.daylight`：更新 `taskLevel`。

因此把 Figma 英文原文用于所有 daylight Profile，会导致纯 `.daylight` Profile 的提示与实际保存字段不一致。

推荐方案：按 Profile 类型提供真实文案，同时完全复用 Figma 样式：

- occupancy/vacancy daylight 使用 Figma 原文，并强调 `Vacant`；
- daylight 使用对应的 Task level 更新提示，不提示用户检查 Vacant。

如果产品要求所有类型无条件显示 Figma 原文，也可以照做，但需要明确接受纯 daylight 场景的语义偏差。

## 6. 测试与验证计划

### 6.1 自动契约

扩展 `NightCalibrationWorkflowContractTests`，验证：

- About 存在显式初始化入口；
- 控制器只在页面初始装载路径按 Active 设置一次；
- modeChanged、Re-calibrate 和完成态刷新路径不改变 About 展开状态；
- Night 完成态继续包含目标照度、取样亮度、pending 状态和 Re-calibrate 行；
- 新增 Notice/Target/Re-calibrate 文案 Key 在英文和简体中文中同时存在；
- shared warning asset 被复用，disclosure asset 存在。

静态契约适合保护状态边界，但不能代替 UI 视觉验收。

### 6.2 代码与构建验证

1. 运行 Night workflow 与 persistence 既有契约，防止影响此前校准成功门槛和 Active 有效性修复。
2. 运行新增/调整后的完成态 UI 契约。
3. 执行 `git diff --check`。
4. 使用 `xcodebuild`、iphoneos、generic iOS destination、关闭签名，串行构建四个品牌 scheme：SunSmart、Archipelago、SLG Sync Plus、SylSmart。
5. 不使用 Simulator 作为构建校验。

### 6.3 真机/UI 验收矩阵

| 场景 | 预期 |
| --- | --- |
| 首次进入，Active = None | About 展开 |
| 首次进入，Active = Night/Sensor/Plane | About 收起 |
| 页面内切换 Segment | About 只换内容，展开状态不变 |
| 页面内切换 sensor 或 Active 更新 | About 展开状态不变 |
| 点击 Re-calibrate | About 展开状态不变，进入 Night 草稿 |
| Night 校准成功 | About 展开状态不变，显示完成态 Card |
| 用户手动展开/收起后再改配置 | 保持用户选择 |
| pending = 0 | 完成态与 Figma 三组件一致 |
| pending > 0 | 额外显示 pending 异常提示，既有重试语义不变 |
| English / 简体中文 | 无截断、无硬编码、重点词样式正确 |
| 四品牌 | 字体、颜色、资源和点击区域一致 |

还需在真机上检查窄屏、长中文换行、VoiceOver Header 状态、整行 Re-calibrate 点击，以及真实 Night 校准后的值与 Notice 文案是否对应。自动契约和编译不能证明像素级视觉、手势、BLE Mesh ACK 或固件行为。

## 7. 明确不在本次范围

- 不修改 Night 采样、目标照度计算、校准参数或 rollback；
- 不改变 daylight sensor publication、Group member Configuring 和 Auto 恢复；
- 不修改 Profile 持久化字段、数据库迁移、导入导出格式；
- 不调整 Sensor Cal. / Plane Cal. 的配置内容和完成流程；
- 不删除 pending-device 状态；
- 不顺手重构其他 Group UI 或公共按钮体系。
