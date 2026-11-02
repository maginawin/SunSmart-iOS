# Scene 设备弹窗遵循 Change Control Page：开发方案

日期：2026-11-02。状态：用户确认后已完成 App 实施、相关回归和 SunSmart generic iOS 构建；界面与实灯效果待人工验收。

## 结论

在现有 `SceneSettingsViewController.editDevices` 中复用 `node.singleDeviceDisplaySupportCct`，统一覆盖 Scene Settings → Devices 和 Select devices 的设备参数弹窗。关联处理同一入口的分类批量编辑与单设备实时控制，保证隐藏色温的设备不会被弹窗返回值覆盖原有场景色温。

本次设定作用于设备弹窗的色温展示、编辑和即时控制。场景正式 Preview、DONE 保存、Sync 及 Recall 继续使用现有场景参数与硬件能力规则；隐藏控件不删除历史场景色温，也不代表设备丧失色温能力。

## 已证实的行为链

| 环节 | 当前实现及影响 |
| --- | --- |
| 属性写入 | `DeviceParameterSettingsController` 将选择写入 `node.changeControlPage`，调用 `savePropertys()` 并发送设备数据变化通知。现有导入、导出、设备恢复已携带该属性。 |
| 显示规则 | SDK 的 `singleDeviceDisplaySupportCct` 为硬件支持色温且有效控制页不是 Single White；未设置时由 `defaultChangeControlPage` 决定。`effectiveSupportCct` 则直接使用硬件能力，不包含此偏好。 |
| 既有设备与组控制页 | 设备页使用 `singleDeviceDisplaySupportCct`；Group 控制页筛选硬件支持色温且控制页为 Tunable White 的成员。 |
| 两个需求入口 | Select devices 是 `SceneSettingsViewController` 的 `.deviceSelection` 模式，与 Settings 共享 `SceneDraftSelection`；两页通过 `SceneDevicesSelectionView.onSettings` 进入同一个 `editDevices`。 |
| 单台与分类 | 设备行传 `.device(identity)`；分类标题传 `.category(selectedIdentities)`。分类只包含当前筛选结果中已选设备，Group / Not in group 都适用；分类只剩一台也不启用实时控制。 |
| 当前缺口 | `editDevices` 的 `showCct`、色温范围成员筛选和 `handleDeviceLiveControl` 的温度事件保护使用 `effectiveSupportCct`，所以 Single White 设备仍出现色温控制。 |
| 回写风险 | Picker 隐藏色温后仍返回一个经过范围限制的色温；当前 `finishParameterEdit` 给目标成员统一应用该值。因此仅修改 `showCct` 会让全隐藏或混合批量编辑覆盖成员各自的旧色温。 |
| 复用布局 | Picker 已支持 `showCct: false`：不创建色温标签和滑条，弹窗高度从 244 缩为 146（经过现有缩放函数）。无需新建弹窗。 |
| 保存与执行 | 弹窗关闭提交内存草稿；Select devices 返回保留草稿；Settings DONE 使用现有保存和同步流程。`SceneParameters.resolved`、`SceneTargetResolver`、`SceneCommandBuilder` 按硬件能力限制范围及生成命令。 |

代码依据：

- [DeviceParameterSettingsController.swift](../SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift)
- [SceneSettingsViewController.swift](../SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift)
- [SceneDevicesSelectionView.swift](../SunSmart/Main/Scene/View/SceneDevicesSelectionView.swift)
- [SceneExecuteDataPickerView.swift](../SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift)
- [SceneDraftSelection.swift](../SunSmart/Main/Scene/Model/SceneDraftSelection.swift)
- [SceneTargetResolver.swift](../SunSmart/Main/Scene/Model/SceneTargetResolver.swift)、[SceneCommandBuilder.swift](../SunSmart/Main/Scene/Model/SceneCommandBuilder.swift)
- [SDK Node+Propertys.swift](/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift)

## 已确认的目标行为

| 编辑对象 | 色温控件 | 提交草稿时的色温 |
| --- | --- | --- |
| 硬件支持 CCT，设置 Tunable White | 显示 | 允许修改，按该设备有效范围限制 |
| 硬件支持 CCT，设置 Single White | 隐藏 | 保留该成员原值 |
| 属性缺失的旧设备 | 遵循已有产品默认值 | 按有效显示规则决定是否允许修改 |
| 硬件不支持 CCT | 隐藏，即使设置为 Tunable White | 保持已有无 CCT 处理，不赋予新能力 |
| 分类内全部设备隐藏 CCT | 隐藏 | 每台保留各自原值，不能复制第一台的色温 |
| 分类内混合两种显示设置 | 只要有一台允许显示 CCT，就显示 | 新色温仅应用到允许编辑色温的成员；其余成员保留各自原值 |
| Relay | 保持已有 ON/OFF 弹窗 | 保持原处理 |

混合示例：同一分类已选 A（Tunable White，3000K）和 B（Single White，5000K）。批量设置 60% / 4000K 后，A 的目标为 60% / 4000K，B 的目标为 60% / 5000K。分类操作不实时发送控制命令；取消选择或筛选排除的成员不受影响。

## 最小完整实施方案

生产修改集中在 `SceneSettingsViewController.swift`，不新增配置字段或独立控制组件。以下方案已实施。

1. 在 `editDevices` 解析目标后，根据现有 `singleDeviceDisplaySupportCct` 确定可编辑色温的成员。单设备直接使用其判断；分类使用“任一符合即可显示”。仍按原有目标身份集合处理离线成员。
2. 色温初值使用第一台允许编辑色温的成员参数，避免混合分类以隐藏色温设备的值初始化。色温范围只让允许编辑色温的节点参与，沿用现有范围合并方式；单设备保留其有效范围。亮度上限和 ON/OFF 规则保持原机制。
3. 在现有 `finishParameterEdit` 的逐成员回写闭包中，保留亮度原始 Mesh 单位保护；隐藏色温或无法解析节点的成员，恢复各自旧 CCT，避免 Picker 默认值、范围限制或第一台参数覆盖。可编辑成员沿用设备范围规范化。保留已有 token、revision、lifecycle 检查。
4. 单设备实时温度事件使用同一个显示判断保护，阻止 Single White 的温度事件发送；亮度与 OFF 继续可用。控制时读取当前设备属性，避免已经隐藏后仍接受迟到的温度事件。
5. 每次打开弹窗重新读取节点属性。回写仅允许打开时可编辑、且提交时仍可编辑色温的成员接收新 CCT，确保异步属性变化不会让原本隐藏的字段被提交。继续复用现有退出、后台、断连和身份变化的取消机制。

### 复用影响及范围边界

- 两个需求页面的单设备、分类批量编辑一起修正，包括新建场景和已有场景的编辑路径。
- `SceneExecuteDataPickerView` 还被 Scene Settings → Groups、SceneAdd 模板及自定义参数使用。本次通过设备调用方传参实现，不改变 Picker 默认行为；这些使用方不会因本次规则改变。
- `SceneDevicesSelectionView.summary` 还用于已保存场景详情及预览结果。它展示场景参数，不是控制项；本次保留已有摘要展示，避免改变未提出的详情需求。
- 不修改 `effectiveSupportCct`、`SceneParameters.resolved` 或命令生成的硬件能力语义，不对旧场景做色温清零、迁移或自动重写。新增成员继续沿用既有场景默认参数。
- 不新增用户可见文案、资源或依赖；不需要 SDK、固件、服务器配套。
- 工程中此控制器由 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六个 target 共用；当前相关逻辑无品牌条件分支，所有使用相同入口的品牌行为一致。

## 验证与验收

以下为本次验证与验收范围，自动化执行结果见下一节；人工验收尚未完成。

1. 扩展现有 Scene 行为夹具，执行实际生产参数选择/回写逻辑：覆盖 Single White、Tunable White、硬件无 CCT、属性缺失的产品默认值、单台离线、全隐藏、混合分类、第一台隐藏以及不同成员旧色温。覆盖仅改亮度、OFF、直接关闭弹窗、旧回调失效、移除后重选及页面返回后的参数保留。无需新增 Xcode 测试工程。
2. 扩展 `Tests/Scene/SceneDeviceLiveControlTests.py`：Single White 的温度事件不发送，Tunable White 按原规则发送；偏好改变后迟到温度事件被拒绝；亮度/OFF、断连恢复、取消和身份保护正常；分类无论成员数量均不实时控制。
3. 运行 `scripts/check_scene_configuration.py --suite selection` 和设备实时控制回归；按最终回写修改运行 `--suite save` 检查草稿至持久化。现有测试目前未覆盖本次弹窗显示与逐成员 CCT 保留，实施时补行为断言，不能仅以源码字符串匹配代替。
4. 一轮修改完成后，运行 SunSmart 的 Debug generic iOS 构建，使用 `SunSmartLocal.xcworkspace`、`CODE_SIGNING_ALLOWED=NO` 及该工作树稳定 DerivedData。无资源、依赖或品牌分支变化时不机械重复六品牌构建。静态/隔离回归与编译不代替实机验收。
5. 人工最短路径：准备 A/B 两台支持 CCT 的设备，分别设置 Tunable White / Single White；在 Settings → Devices 和 Select devices 分别打开单台与分类弹窗，确认显隐、紧凑布局、亮度/OFF；混合批量修改后检查 B 原色温保留。再切换 B 的设置并重开弹窗，确认即时生效；保存、重进，确认目标值连续。真实 BLE 控制效果由用户验收，默认不自动安装运行真机。

## 实施与验证结果

- 显隐、范围成员筛选和初值已使用既有显示规则；逐成员回写保留隐藏色温，实时温度事件按当前设定拦截，并清理失效的去重记录。其余业务入口保持原机制。
- `selection` 套件通过：既有 74 项选择/草稿回归、新增 37 项设备参数行为检查，以及 `DeviceNameFilterSessionTests`。新增夹具执行实际 `editDevices`、Picker 遮罩提交逻辑、SDK 显示规则和 `SceneDraftSelection`；UIKit 布局与 BLE 为测试边界，不能据此声称真实布局或无线送达通过。
- `SceneDeviceLiveControlTests.py` 通过 51 项检查，包含隐藏色温拒绝采样/结束事件、亮度与 OFF 可用、偏好切换后的迟到事件及恢复控制。
- `save` 套件通过，覆盖事务回滚、离线编辑、恢复、无改动保存、直接 Sync、权限、metadata、删除生命周期及 Coordinator 预览/取消等既有行为。
- SunSmart Debug generic iOS 构建于 2026-11-02 19:45 完成，结果 `BUILD SUCCEEDED`。入口 `SunSmartLocal.xcworkspace`，关闭代码签名，复用 `SunSmart-feat-device-scene-261028-cli` DerivedData；SDK 解析指向约定的本地工作树。
- 首次隔离测试受系统默认 clang 缓存目录写权限限制；指定允许写入的 `ModuleCache.noindex/scene-device-parameter-tests` 后通过。夹具编译补齐 CoreGraphics 导入后通过，未为环境问题修改业务逻辑或清理共享缓存。
- 差异空白检查、修改的 Python 脚本语法检查通过。本次未运行 Simulator、未安装或运行真机，未改 SDK、正式依赖、资源和国际化配置，未提交 Git。

## 当前工作区与下一步

- App：`feat/device-scene-261028`，HEAD `47140eb6`。已有未跟踪文档 `docs/261102_1930_space_scene_order_analysis.md`，本任务不修改。
- 本地 workspace 的 `.local-sdk/nordic-sig-mesh-sdk` 已核对 realpath，指向约定的 `one-dev`；读取时 SDK HEAD 为 `dbcf6f1`，工作树无未提交修改。本方案复用既有 API，不要求新 SDK revision。
- 本任务未提交差异：控制器实现、设备实时控制测试、新增设备参数行为夹具、selection 套件接入及本文档。
- 下一步：按上节人工路径检查两个页面的显隐、混合分类保留原值、设置切换后重新打开、保存重进及实灯效果。
