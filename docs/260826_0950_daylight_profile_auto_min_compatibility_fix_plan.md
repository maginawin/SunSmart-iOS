# Daylight Group Profile Auto Min 兼容性修复计划

> 规划日期：2026-08-26  
> 工程范围：`ttl-test` worktree  
> 当前阶段：仅规划，未修改业务代码  
> 目标 Profile：`Occupancy sensing with daylight harvesting`、`Vacancy sensing with daylight harvesting`、`Daylight harvesting`

## 1. 目标

修复以下两个数据一致性问题：

1. 三种 daylight harvesting Profile 的旧云数据缺少 `autoMinLevel` 时，应按当前新建 Profile 语义恢复为关闭，即 `255`，不能继续 fallback 为已启用的 `0%`。
2. 三种 daylight harvesting Profile 调整 High-end/Low-end trim 时，仅夹取有效且已启用的 Auto min 值；关闭哨兵值 `255` 必须保持不变，不能被改成 High-end。

同时处理由第二个问题产生的历史污染值：对于 daylight Profile 中超出有效范围且不等于 `255` 的 Auto min，例如旧版本可能保存的 `50...100`，在云导入和本地数据库读取时按关闭规范化为 `255`，使 UI、模型和同步层恢复一致。

## 2. 统一数据语义

在模型层建立唯一语义，避免 UI、导入和同步分别使用 `!= 255`、`<= 30` 等不同判断：

| 输入值 | 统一解释 | 规范值 |
| ---: | --- | ---: |
| 缺字段或类型错误 | 旧数据没有配置 Auto min | `255` |
| `0...30` | Auto min 已启用，值为对应百分比 | 原值 |
| `255` | Auto min 已关闭 | `255` |
| 小于 0、`31...254`、大于 255 | 非法值或历史范围夹取污染 | `255` |

特别保留 `0` 与 `255` 的差异：

- `0` 是显式启用的 `0%`；
- `255` 才是关闭。

该语义只在三种 `ProfileType.daylightType == true` 的 Group Profile 中生效；其余五种 Profile 的业务字段和导入行为不在本次范围内。

## 3. 推荐设计

### 3.1 模型层作为语义所有者

修改 `SunSmart/Main/Profile/Model/Profile.swift`，在 `Profile.LightControlData` 中集中定义：

- Auto min 有效范围 `0...30`；
- disabled 哨兵值 `255`；
- 输入值规范化方法；
- “是否启用”判断；
- 调整亮度范围时的 Auto min 规范化/夹取方法。

所有现有 `255`、`<= 30`、`!= 255` 判断逐步改为复用这一模型语义。重点包括：

- `LightControlData.autoMinLevelEnabled`；
- `LightData` 将 `LightControlData` 转换成图表/同步 levels 时的 enabled 判定；
- Profile 设置页打开 Auto min 编辑器时的 enabled 判定；
- 用户关闭 Auto min 后保存的哨兵值。

这样可以保证：UI 显示、Profile equality、Need Sync 期望值和 `Node+SyncData` 最终得到同一个 enabled 结果。

### 3.2 云导入按 Profile 类型应用兼容默认

修改 `SunSmart/Common/Data/ImportData.swift`：

- 先解析 `ProfileType`，再解析 Auto min；
- 对三种 daylight Profile：缺字段、类型错误或非法范围统一规范为 `255`；
- 显式 `0...30` 和 `255` 原样保留；
- 顶层 `lightControlData` 和 `scenes[]` 中的 `autoMinLevel` 使用同一规则；
- 非-daylight Profile 保持现有导入语义，避免扩大行为变化。

必须覆盖两种旧 payload 形态：

- 没有 `scenes`，由顶层 Profile 数据创建 General Scene；
- 有 `scenes`，但 General Scene 也缺少 `autoMinLevel`。

### 3.3 本地数据库读取时修复历史污染值

修改 `SunSmart/Common/Data/Database.swift` 的 Profile 读取路径：

- 已有 `profileType` 后，对三种 daylight Profile 的数据库 `autoMinLevel` 做同样规范化；
- `0...30` 与 `255` 保持不变；
- 旧版本已经保存成 High-end 的 `50...100` 等非法值，在内存中恢复为 `255`；
- 不新增字段、不修改表结构、不执行批量 SQL migration；
- 仅在用户后续正常保存 Profile 时，规范值才通过现有保存链路落库。

这一项用于修复已经被旧 UI 范围逻辑污染的本地 Profile。若只修改未来的范围调整逻辑，历史用户仍会看到“UI 启用、同步关闭”的不一致，因此不建议省略。

### 3.4 High/Low-end trim 只处理有效启用值

修改 `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`：

- 用 `selectProfile.type.daylightType` 代替重复枚举三个类型；
- 更新 High/Low-end trim 后，对每个相关 `LightControlData` 调用模型层 Auto min 范围处理；
- Auto min 为 `255` 时保持 `255`；
- Auto min 为有效值时，才夹入新的 `low...high` 范围；
- Auto min 为历史非法值时规范为 `255`，不夹成 High-end；
- General、Day、Night 数据仍沿用现有统一遍历方式，不改变其它阶段参数处理。

预期行为示例：

| 调整前 Auto min | 新 Low/High | 调整后 |
| ---: | --- | ---: |
| `255` | `1...100` | `255` |
| `0` | `1...100` | `1` |
| `10` | `20...100` | `20` |
| `30` | `1...100` | `30` |
| `100`（历史污染） | `1...100` | `255` |

## 4. 文件改动范围

### 4.1 计划修改

- `SunSmart/Main/Profile/Model/Profile.swift`
  - 集中 Auto min 常量、有效性、规范化和范围调整语义。
- `SunSmart/Common/Data/ImportData.swift`
  - 修复三种 daylight Profile 的旧云缺字段 fallback，并规范化非法值。
- `SunSmart/Common/Data/Database.swift`
  - 读取时修复三种 daylight Profile 的历史污染值，不做 schema migration。
- `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
  - 调整 High/Low-end trim 时保留 disabled 哨兵，只夹取有效启用值。
- `Tests/Group/ProfileAutoMinCompatibilityContractTests.swift`
  - 新增聚焦源码契约测试。
- `scripts/check_profile_auto_min_compatibility.sh`
  - 编译并运行新增契约测试。

### 4.2 明确不修改

- `SunSmart/Common/Data/Node+SyncData.swift`
  - 保持已校准时将 enabled Auto min 映射到 On/Prolong/Standby，以及 disabled 映射为 0 的现有同步行为。
- `SunSmart/Common/Data/ExportData.swift`
  - 保持现有顶层和 scene `autoMinLevel` 导出字段。
- 本地化文件和 UI 布局
  - 不新增文案，不改变编辑器样式和约束。
- `NordicSigMeshSDK`
  - 本次是 App 数据兼容和 UI 状态修复，不修改协议消息。
- 数据库 schema
  - 不加列、不做批量数据迁移。
- 其余五种 Group Profile
  - 不改变其亮度范围、阶段亮度或导入业务语义。

## 5. 分步实施计划

### Task 1：先补 Auto min 兼容契约

新增 `ProfileAutoMinCompatibilityContractTests.swift`，先形成失败测试，约束以下契约：

- 模型只有一个 disabled 值和一个有效范围定义；
- enabled 判断必须以有效范围为准，不能继续只判断 `!= 255`；
- `LightData` 的 enabled 判定复用模型规则；
- 三种 daylight Profile 由 `ProfileType.daylightType` 统一识别；
- ImportData 不再对 daylight 顶层字段使用 `?? 0`；
- 顶层和 scene 导入均调用同一规范化规则；
- Database 读取对 daylight Profile 规范化历史值；
- High/Low-end trim 路径调用模型范围处理，不直接对 `255` 使用 `min/max`；
- `Node+SyncData` 的现有 Auto min → On/Prolong/Standby 映射仍然存在。

新增 `check_profile_auto_min_compatibility.sh`，沿用仓库现有 Swift 源码契约测试模式，通过参数传入上述源文件路径。

### Task 2：统一模型语义

在 `Profile.LightControlData` 中实现统一常量和方法，并替换当前分散判断。

验收点：

- 新建三种 daylight Profile 仍为 `255/N/A`；
- `0...30` 均判定为 enabled；
- `255` 和其它非法值均判定为 disabled；
- `copy()`、equality 和场景更新继续保留规范后的实际值；
- 不改变 Low-end trim 默认 `1%`。

### Task 3：修复云导入与本地历史数据

将模型规范化规则接入 ImportData 和 Database load。

验收矩阵对三种 daylight Profile 分别执行：

| 数据来源 | 输入 | 预期 |
| --- | ---: | ---: |
| 云顶层，无 scenes | 缺字段 | `255` |
| 云 scene | 缺字段 | `255` |
| 云顶层或 scene | `0` | `0` |
| 云顶层或 scene | `10` | `10` |
| 云顶层或 scene | `30` | `30` |
| 云顶层或 scene | `255` | `255` |
| 云顶层或 scene | `31/100/254/256/-1` | `255` |
| 本地数据库 | `0...30` | 原值 |
| 本地数据库 | `255` | `255` |
| 本地数据库 | `31...254` | `255` |

同时至少选取一个非-daylight Profile 验证现有导入行为未变化。

### Task 4：修复 High/Low-end trim 更新

将 Profile 设置页中的直接 `min/max` 替换为模型范围处理。

需验证三个 daylight Profile：

- disabled `255` 修改 High/Low 后仍显示 `N/A`；
- enabled `0` 在 Low 从 0 改为 1 时变为 1；
- enabled 10 在 Low 改为 20 时变为 20；
- enabled 30 修改 High/Low 后只在必要时变化；
- 历史污染 100 进入页面并修改范围后恢复为 `255/N/A`；
- 保存、退出、重新进入后值和开关状态一致。

### Task 5：回归同步与持久化边界

确认以下现有链路没有变化：

- Auto min enabled 时，已校准 daylight 仍生成 On/Prolong/Standby 三个 Lightness 同步项；
- Auto min disabled 时，已校准 daylight 仍以 0 作为同步目标；
- 未校准 occupancy/vacancy daylight 的 fallback 仍是 High-end/50/0；
- 未校准纯 daylight 的 fallback 仍是 High-end；
- Profile 保存失败、Need Sync 和 Re-Sync 的既有控制流不在本次改动范围内。

## 6. 验证计划

### 6.1 自动化验证

1. 运行 `zsh scripts/check_profile_auto_min_compatibility.sh`。
2. 运行现有 Night Calibration persistence/workflow 契约，确认 daylight Profile 持久化与校准流程未被破坏。
3. 运行 `git diff --check`。

### 6.2 四品牌构建

由于四个品牌 target 共享 Profile、ImportData、Database 和设置页代码，需要串行执行 generic iPhoneOS unsigned build：

1. `SunSmart`
2. `Archipelago`
3. `SLG Sync Plus`
4. `SylSmart`

均直接使用 `xcodebuild -workspace SunSmart.xcworkspace -scheme <scheme> -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`，不使用 shell 包装、日志重定向或 Simulator。

### 6.3 UI 与数据验收

构建通过不能替代实际 UI 验收。至少手动覆盖：

- 三种 daylight Profile 各自的新建默认值；
- 缺字段旧云数据导入后显示 `N/A`；
- 显式 `0%` 导入后仍显示 enabled 0%，不能误判为关闭；
- disabled 状态修改 High/Low 后仍保持关闭；
- enabled 值跨越新 Low-end 时正确夹取；
- 保存后重新进入 Space/Profile 页面状态不回退；
- 若条件允许，确认同步任务对 disabled 仍生成 0，而不是 High-end。

## 7. 风险与控制

### 7.1 显式 0 与缺字段混淆

不能使用 `intValue` 或其它把缺失转成 0 的 API。必须使用可选读取，先区分“没有字段”和“字段明确为 0”。

### 7.2 历史污染值修复触发同步

把历史 `50...100` 规范为 `255` 后，设备缓存若仍保留该错误值，Profile 可能出现 Need Sync。这是把不一致状态恢复为明确关闭的预期结果，但需要在验收说明中区分：

- App 数据修复成功；
- Mesh 配置任务成功；
- 真机闭环最终行为通过。

### 7.3 场景和顶层数据优先级

当前 Profile 有 General Scene 时，`lightControlData` 实际由该 scene 提供。只修顶层字段不足以覆盖所有旧 payload，因此顶层和 scene 必须使用同一规范化规则。

### 7.4 扩大到非-daylight Profile

不应借此次修复统一清洗全部 Profile 的 `autoMinLevel`。该字段在其余五类中不参与模型 levels 和同步，本次保持范围聚焦。

## 8. 非目标

- 不修改首次从 Off 打开 Auto min 时滑杆当前落到 30% 的行为；该问题需要单独的产品默认值决定。
- 不改变 Auto min `0...30%` 范围。
- 不改变 Auto min 与 Low-end trim 的产品关系。
- 不修改 daylight calibration、ratio、inflection point 或目标 Lux。
- 不修改固件和 SDK。
- 不新增或修改本地化、资源、target 配置或依赖。
- 不提交、推送或合并 Git 历史。

## 9. 完成标准

只有同时满足以下条件才可认为 App 修复完成：

- 三种 daylight Profile 缺失 Auto min 的旧云数据均恢复为 `255/N/A`；
- 显式 0 仍保持 enabled 0%；
- disabled 255 调整 High/Low 后不变；
- 历史非法值在读取时恢复为 255；
- UI、模型、导出数据和同步期望使用一致 enabled 语义；
- 新增及现有相关契约通过；
- 四品牌 generic iPhoneOS 构建通过；
- 实际页面完成保存、退出、重入验证。

真机 Mesh/闭环行为需要单独标记，不能仅凭源码契约和构建结果宣称通过。
