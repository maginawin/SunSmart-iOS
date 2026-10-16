# Calibration 外接光感设备提示分析与开发方案

日期：2026-10-16。状态：用户已确认方案，App 实施与自动化验证完成；真实设备及界面体验待人工验收。未提交 Git。

最终实现：三种模式手动选择外接光感设备均先提示；确认后继续原模式流程，取消无状态提交；分类已整理为 Company/PID 名单，当前 11 个成员不变。详细验证结果见文末。

## 结论

1. 现有 App 已有集中分类 `isExternalLightSensorCapableLuminaire`，并已有与需求完全相同的英文弹窗。`0x0A78 / 0x2134` 已在分类中，不需要再次添加设备资料或新增平行分类。
2. 实施前缺口在选择入口：Plane Cal 会检查分类并提示；Night Cal、Sensor Cal 在检查前提前返回，因此不提示。未校准页面默认 Night Cal，更容易遇到此问题。
3. 建议将提示检查移到三种模式共用的选择入口，确认后再执行各自原有选择流程。复用现有能力 getter、弹窗组件和本地化 Key。
4. 为满足后续仅维护 `companyId + productId` 的要求，可将这一个分类内部的“固定 Company ID + PID 集合”整理为“Company ID → PID 集合”的名单；现有 11 个成员等价迁移，不增加通用能力框架。

## 取证基线

- App 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-SR-BL2421-Mini-261016`。
- 分支：`feat/SR-BL2421-Mini-261016`；HEAD：`83f087dc`。调查开始时工作树干净。
- 历史提交 `6d0b1bbd` 已将 `0x2134` 加入外接光感能力及不支持移动灵敏度的名单。本次以当前源码为准，不沿用旧设计文档的八设备名单。
- `SunSmartLocal.xcworkspace` 存在，`.local-sdk/nordic-sig-mesh-sdk` 实际解析到 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；SDK HEAD 为 `2598bd1`，本次检查时无未提交差异。SDK 只读核对，不计划修改。
- [Figma 节点 31301:74557](https://www.figma.com/design/6oNpzrtKUau4OLQnpXallR/SunSmart_v1.3.0-v1.5.0?node-id=31301-74557) 已通过 Figma connector 取得结构化内容及截图。

## 现有分类及设备清单

名单位于 [Node+Capability.swift](../SunSmart/Common/Data/Node+Capability.swift) 的 `SunricherProductCapabilityPolicy.externalLightSensorCapableLuminaireProducts`（实施前为 `externalLightSensorCapableLuminaireProductIdentifiers`），由 [MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift) 的 Node 静态方法和实例 getter 转接。

以下设备的 Company ID 均为 `0x0A78`。型号来自当前 [devices_config.json](../SunSmart/devices_config.json)；未配置型号的条目仍在能力名单中，不根据相邻 PID 推断型号。

| Product ID | 当前配置的型号 | 与本次需求的关系 |
| --- | --- | --- |
| `0x2121` | SR-BL2421-5A-AUX | 既有同类设备 |
| `0x2122` | 当前配置无对应记录 | 既有同类设备 |
| `0x2132` | SR-BL2421-SVVT-AUXRJ45 | 既有同类设备 |
| `0x2133` | 当前配置无对应记录 | 既有同类设备 |
| `0x2134` | SR-BL2421-Mini | 本次目标，已在名单中 |
| `0x2321` | SRPL-BL9105N-XXCCXXE | 既有同类设备 |
| `0x2322` | SRPL-BL9105N-XXCCTXXE | 既有同类设备 |
| `0x2491` | SR-nRF54L15-M1 | 既有同类设备 |
| `0x2492` | SR-nRF54L15-M3 | 既有同类设备 |
| `0x2493` | 当前配置无对应记录 | 既有同类设备 |
| `0x2494` | 当前配置无对应记录 | 既有同类设备 |

这份名单证明 App 当前将这些产品归为外接光感设备，不代表本次已验证每款硬件的物理连接能力。其他厂商的相同 PID、缺失 Company/PID、`0x0A78 / 0x2131` 等未入名单产品均不命中。

实际业务使用方有两处：

- Calibration 选择设备时显示外接光感提示。
- [ProfileSettingsViewController.swift](../SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift) 在显示 Sensitivity 且 Group 存在此类设备时显示 `Some devices lack sensitivity`。

因此保留该分类的现有成员与语义；本次不会改变 Profile 的提示结果，也不调整独立的 `unsupportedMotionSensitivityProductIdentifiers`。后续扩充该能力名单时，应同时核对这两个使用方；如果未来产品的光感与灵敏度能力组合不同，需要重新评估二者的关联，不能凭 PID 相似推断。

## 实施前行为链与原因

### 页面入口与候选设备

- [GroupViewController.swift](../SunSmart/Main/Group/Controller/GroupViewController.swift) 的菜单 Calibrate 和页面 CALIBRATE 按钮均进入同一个 `LightSensorCalibrationViewController`。入口受 Group 编辑权限、Profile 类型等既有条件约束。
- 列表来自 SDK 的 `group.ambientLightSensorNodes`，筛选条件是组内 Node 具有 `ambientLightSensorModel`。SDK 进一步根据 Sensor Model 的 `presentAmbientLightLevel` 属性或缓存模型识别光感。
- 用户提供的 JSON 在当前设备配置中已完整存在，但 `elementCount = 3`、`Lighting` 或图标类别本身不能保证设备一定进入该列表。仍依赖实际发现的 Mesh 模型；本次不伪造传感器模型或放宽候选规则。

### 手动选择

[LightSensorCalibrationSelectView.swift](../SunSmart/Main/Group/View/LightSensorCalibrationSelectView.swift) 的开关覆盖按钮只上报启用意图，不提前改变选中状态。控制器的 `didSelectDaylightSensor` 当前按以下顺序处理：

1. 结束输入，检查是否有设备正在 loading。
2. Night/Sensor：直接关闭旧选择、更新新选择和页面草稿，然后 return。
3. Plane：检查 `isExternalLightSensorCapableLuminaire`，命中后显示确认弹窗。
4. Plane 确认后调用 `enableDaylightSensor`，按需取消旧 Publication、启用已校准设备、保存和刷新；失败由原有逻辑处理。

因此即使 `0x2134` 已被分类，也只有 Plane 能触发提示。这是可直接从当前分支控制流确认的缺口。

### 下游与恢复

- Night/Sensor 的选择是草稿，正式 Apply 后才执行校准和 Publication 提交。不能为了共用弹窗，把这两个模式也直接接到 Plane 的 `enableDaylightSensor`。
- 校准启动仍检查设备在线条件、光感及 Vendor Model、固件最低版本；`0x2134` 当前落入默认最低版本 `1.3.0`。本次不修改这些判断。
- 页面进入时会恢复已保存的 Group 光感选择；此恢复不走手动选择 delegate。
- 正式校准后还存在配置成员、失败回滚、STOP/RETRY 及 Group Auto 恢复流程。本次只在选择前增加确认，不移动其持久化或成功判定边界。
- 没有发现可证明外接传感器物理连接状态的现有判断。本次提示由用户确认连接，不以读数为零判定未连接，也不承诺自动检测。

## 已确认的交互规则

| 场景 | 预期行为 |
| --- | --- |
| 三种模式中，手动将名单内设备从关闭切为选中 | 在新选择状态提交前弹出提示 |
| 弹窗等待期间 | 保持原选择、草稿、Publication 和持久化数据；不为候选设备启动新的选中读数轮询 |
| CANCEL | 候选设备保持未选中，原设备保持选中；不触发新的配置或校准 |
| CONFIRM，Night/Sensor | 只提交原有页面选择草稿，正式配置仍等待 Apply |
| CONFIRM，Plane | 继续原有启用流程，保留失败处理与 loading 反馈 |
| 取消选中设备 | 不弹外接光感提示 |
| 取消后重选、关闭后重选 | 再次提示，不设置永久免提醒标记 |
| 普通光感设备 | 沿用原有选择流程 |
| 页面恢复上次选择、只切换校准模式、点击 Apply 或 Re-calibrate | 不额外重复该提示；Apply 原有确认继续保留 |
| 有设备处于 loading 或校准配置正占用页面 | 不新增弹窗或选择操作 |
| 弹窗确认时页面已退出、候选已失效或状态已繁忙 | 丢弃该次确认，不执行过期选择 |

提示是“选择前确认”。原已选设备的既有 Lux 轮询可能继续，不应将“取消不触发配置”描述成网络上完全没有 Mesh 消息。现有双按钮 `SRAlertView` 不通过点击遮罩关闭，建议保持此交互。

## 最小完整实施方案

### 1. 继续复用产品能力分类

- 保留 `SunricherProductCapabilityPolicy.isExternalLightSensorCapableLuminaire(companyIdentifier:productIdentifier:)` 和 Node getter 接口。
- 仅将此分类的内部名单调整为 Company ID 对应 PID 集合，现有 `0x0A78` 的 11 个成员完整迁移。未知厂商及空标识保持 false。
- 同厂商扩充时只加 PID；新厂商扩充时只增加 Company/PID 表项。页面不再需要新增判断。
- 其他能力表继续使用原有 `supports` 机制，不更改设备类别、设备信息 JSON、扫描、路由、Group 加入规则或 SDK。
- 不选 `devices_config.json` 新字段方案：现有能力名单包含四个 JSON 中缺记录的 PID，改为依赖 JSON 会引入双来源或丢失兼容成员。

### 2. 统一选择前置检查，保持模式差异

- 在 `didSelectDaylightSensor` 的前置有效性/忙碌检查后、所有选择状态变化前判断外接光感能力。
- 将“确认后继续选择”收敛为控制器私有方法，内部保留 Night/Sensor 草稿分支与 Plane 启用分支；普通设备直接进入，名单内设备仅在 CONFIRM 后进入。
- 继续使用现有 `showExternalLightSensorConnectionAlert`；确认回调弱引用控制器与视图，并在继续入口复核可见性、候选仍属于列表且具有光感模型、loading/校准状态。避免已失效选择在回调中落地。
- CONFIRM 复用 `SRAlertAction.performsActionAfterDismiss`，在弹窗关闭后继续流程；复用组件已有的重复点击拦截。
- 取消保持无提交。无需新增持久化字段、记录“已提醒”标记或修改导入导出/云同步格式。

### 3. 复用弹窗并局部对齐设计

Figma 的内容为：

- 标题：`Notification`。
- 正文：`This device has the ability to connect to an external light sensor. Before calibration, please ensure that the sensor is connected.`
- 左按钮 `CANCEL`，右按钮 `CONFIRM`。
- 居中标题 18 pt Regular；正文 15 pt Light、22 pt 行高；标题与正文间距 16 pt；圆角 20；按钮区高 60。

现有 `SRAlertView` 已具备居中多行正文、双按钮、分隔线和圆角。当前调用默认标题为 15 pt、标题正文间距 26，正文未指定设计行高；这些差异在本弹窗实例内调整，复用项目色值和自适应布局，不改全局默认值。

设计背景包含半透明/模糊与阴影，现有通用弹窗使用纯白内容背景。建议本次沿用 App 标准背景，仅局部对齐文本、间距和按钮；这属于明确保留的视觉差异，不表述为逐像素一致。不同品牌继续使用各自主题色及现有按钮配色规则。

复用现有四个 `external_light_sensor_capable_luminaire_calibration_*` Key。English 保留需求原文；当前 `zh-Hans` 四项仍是英文，实施时建议同步为“通知 / 此设备支持连接外部光照传感器。校准前，请确保已连接传感器。 / 取消 / 确认”，符合项目国际化要求。

### 4. 文件与品牌范围

预计修改：

- `SunSmart/Common/Data/Node+Capability.swift`：名单表达方式及必要注释。
- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`：共用确认入口及本弹窗样式。
- `SunSmart/zh-Hans.lproj/Localizable.strings`：复用 Key 的中文翻译；English 原文无需变化。
- 现有相关测试文件：补分类成员和选择确认行为用例，尽量复用当前测试脚本。

上述代码和本地化由 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五品牌共享；已核对工程中对应 Sources/Resources 归属。当前方案不新增资源、不改变 target 配置，不修改 `project.pbxproj`、SDK 或正式依赖，无固件/服务器配套发布依赖。

## 验证计划与边界

### 自动化

- 分类行为：完整验证 11 个现有 Company/PID 组合，重点补齐 `0x2134`；验证相同 PID 的其他 Company、未知 PID、nil，以及 `0x2131` 不误入。确认其他能力 getter 结果未变。
- 选择行为：优先扩展 `Tests/Group/CalibrationModeControlBehaviorTests.py` 的生产方法提取与命令记录夹具，加入可延迟确认/取消的弹窗 stub，实际执行共同选择入口；不只断言源文件含某个字符串。
- 重点覆盖三模式提示等待和 CANCEL 均保留旧选择；Night/Sensor CONFIRM 无 Publication 提交；Plane CONFIRM 才进入启用；普通设备直通；关闭不提示；重选再提示；busy/退出/候选失效时不提交。
- 复用现有生命周期、Publication 回滚行为回归，确认草稿与持久化边界保留。静态 Night/Sensor workflow 脚本仅作为结构性补充，不能代替上述行为执行。
- 现有 `UpDownLightProductSupportContractTests.swift` 的外接光感用例尚未包含 `0x2134`。另静态发现它要求 `0x2321.categoryName == CCT Up&Down Lighting`，而当前 JSON 为 `Driver Lighting`；实施时先确认这个既有测试基线，单独报告或在明确现行契约后校正测试预期，不为通过测试改动该产品分类。当前未运行该脚本，不把静态不一致表述为已执行失败。
- 完成一轮生产代码修改后使用已确认映射的 `SunSmartLocal.xcworkspace`，运行一次 SunSmart Debug、generic iOS、禁用签名构建，使用该工作树稳定的 DerivedData 目录。无 Simulator、无自动真机安装。
- 因本方案不改变品牌条件或资源归属，代表品牌构建即可作为本次编译检查；若实际实施新增资源或产生品牌专属编译路径，再覆盖受影响品牌。

### 人工验收

1. 使用 `0x0A78 / 0x2134`，分别在 Night/Sensor/Plane 手动打开选择开关；确认提示文案、标题、按钮顺序和完整换行。
2. 已选另一个光感时尝试改选 Mini：CANCEL 保留原设备；CONFIRM 只按当前模式执行原有流程。普通传感器选择与关闭均不提示。
3. 取消或关闭后再次选中 Mini 应再次提示；单纯切换模式或退出重进恢复选择不重复提示。
4. Plane 模式下连接/取消旧 Publication 失败时确认既有错误反馈仍可恢复；Night/Sensor 确认后 Apply 仍执行原有固件能力检查及成功/失败处理。
5. 中英文、小屏幕与较长文本检查；其他品牌核对主题色。真实传感器接线、读数、BLE 回执及最终校准效果由人工验收，不由构建或 stub 测试替代。

## 实施结果与验证记录

用户已确认本文方案，按约定完成以下修改：

- `externalLightSensorCapableLuminaireProducts` 按 Company ID 保存 PID 集合；保留 11 个现有成员、既有 Node 接口及 Profile 联动结果。
- `didSelectDaylightSensor` 在模式分支前弹窗，`continueSelectingDaylightSensor` 保留 Night/Sensor 草稿选择与 Plane 启用逻辑。取消动作不改变设备状态；确认在弹窗关闭后执行。
- 确认前复核页面可见性、视图和候选实例、光感模型、当前模式和选择、loading 及实际校准/配置操作状态；不把 `daylightConfigurationPending` 单独当成禁止选择条件，保留失败后的恢复操作。
- 针对旧启用失败后“开关均关闭、控制器仍保留旧 Node 引用”的合法恢复状态，新增用例复现了初版保护会阻断重试的问题。最终分别核对弹窗开始时的控制器引用和列表当前实际打开的设备，不要求旧引用必须等于列表已选设备，相关重试已通过行为测试。
- 本弹窗局部设置 18 pt 标题、15 pt Light 正文/按钮、22 pt 正文行高、16 pt 标题正文间距；继续使用共享组件的白色背景、圆角、分隔线和品牌配色。英文原文不变，补齐四项中文翻译。
- 测试新增 Mini 配置与能力覆盖。经核对 `83f087dc` 的设备配置变更，旧 `0x2321` 类别断言改为当前正式值 `Driver Lighting`；未修改设备 JSON。

### 已执行验证

| 检查 | 结果与范围 |
| --- | --- |
| `python3 Tests/Group/CalibrationModeControlBehaviorTests.py` | 827 条断言通过。修改前新增用例复现 Night 不提示；最终覆盖三模式等待/取消/确认/重选、普通设备、失效回调、失败后重试，以及既有生命周期和 Publication 提交/回滚检查 |
| `bash scripts/check_up_down_light_product_support.sh` | 通过；实际执行生产能力表，包含全部 11 个外接光感产品与错误 Company/未知 PID/nil |
| `zsh scripts/check_night_calibration_workflow.sh` | 通过；静态结构契约 |
| `zsh scripts/check_sensor_calibration_workflow.sh` | 通过；静态结构契约 |
| English / zh-Hans `plutil -lint` | 通过 |
| `git diff --check` | 通过 |
| 五品牌 Sources / Resources 归属 | 已核对：修改的能力文件、控制器及共享 Localizable 均归属五品牌；未改变工程配置 |
| SunSmart Debug generic iOS 构建 | 最终代码 `BUILD SUCCEEDED`，使用 iPhoneOS 27.0 SDK、禁用签名；复核重试边界后对同一 DerivedData 执行增量重建 |

构建入口：`SunSmartLocal.xcworkspace`，scheme `SunSmart`；DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-SR-BL2421-Mini-261016`。SDK 仍为 `one-dev` / `2598bd1`，本任务未修改 SDK 或远端依赖。

选择行为夹具提取并执行生产控制器方法，弹窗呈现和 Plane 启用分派由 stub 替代；底层 activation/Publication 方法另外由既有夹具执行。它不覆盖 UIKit 实际布局、真实异步调度、BLE、设备接线和校准效果。其他四品牌未逐一构建，真实设备未安装或运行。

人工验收按上文五项步骤进行，重点确认 Mini 在三模式的提示、CANCEL 保留原选择、CONFIRM 后模式行为，以及中英文长文案显示。当前仅有本文及五个代码/测试/本地化文件的未提交差异。
