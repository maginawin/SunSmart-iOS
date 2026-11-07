# 组场景色温控件显示问题：原因与实施记录

时间：2026-11-07（Asia/Singapore）  
状态：用户已确认原方案，业务修改、相关离线回归和 SunSmart generic iOS 构建完成；真机界面与设备体验待验收。

## 结论

建议采用“组场景始终展示亮度和色温”的方案，覆盖创建和已有场景编辑。组场景保存的是该组的预设参数，组成员会变化，不适合用当前成员是否有色温能力决定能否配置色温。

测试反馈的两个现象由同一显示判断解释：

- 参数设置里的“控制页面类型 → 单白光”只影响单设备 UI，不改变设备的 Mesh 色温能力；仍有色温 Model 的设备加入组后，组仍被判定为支持色温。
- 空组没有任何成员，`Group.effectiveSupportCct` 返回 false，场景编辑入口据此隐藏色温条。

需要澄清：当前实现即使隐藏色温条，也会保留并保存色温值；新建通常为 4500K。后加入设备的场景同步链路也已经存在。因此并非以后加入色温设备就无法处理，而是用户不能提前明确设置色温，且同一个组的编辑界面会随成员变化。

## 当前核对基线与证据边界

- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-device-scene-261028`。
- 分支：`feat/device-scene-261028`；App HEAD：`46dfdd83ff67d36da3de6bed9b9cde5d3c1d308c`。
- 开始分析时 App 工作树干净。
- 本地入口：`SunSmartLocal.xcworkspace`，其中 `.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK HEAD：`8f62e8aafeda0c5d9ac678f085c589da99e17e26`；检查时无未提交差异，仅只读核对。
- 测试反馈没有附具体型号、操作录像或 Mesh 日志。本结论依据当前源码和离线边界复现；“修改类型”对应当前参数页的“控制页面类型 → 单白光”。如果现场实际修改的是设备另一种输出模式，需要补充对应入口再核对。

## 原因与完整行为链

### 1. 参数修改没有把 CTL 设备变成硬件单调光设备

`DeviceParameterSettingsController.setupAction()` 的 `.changeControlPage` 分支，只写入 `node.changeControlPage`、保存属性并通知刷新；该分支没有发出更改设备输出模式的 Mesh 命令。

SDK `Node+Propertys.swift` 明确区分：

| 判断 | 当前含义 | 改成单白光后的结果（原有色温 Model） |
| --- | --- | --- |
| `rawSupportCct` | 是否存在 `temperatureModel` | true |
| `effectiveSupportCct` | 跨设备控制与自动化的色温能力，返回 `rawSupportCct` | true |
| `singleDeviceDisplaySupportCct` | 原始色温能力，且控制页类型不是 `.singleWhite` | false |

因此单设备页面隐藏色温，而组场景仍允许色温，符合当前两类属性的既定语义。不能为了修复空组展示而把共享能力属性改为始终 true，也不应让单设备显示偏好关闭全部自动化色温能力。

源码入口：

- `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift:236`。
- SDK `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift:148`、`:207`。
- `SunSmart/zh-Hans.lproj/Localizable.strings:1998`，UI 名称为“控制页面类型”。

### 2. 组场景错误地用当前成员能力限制预设编辑界面

自定义创建经 `SceneAddViewController.openDraftEditor` 进入 `SceneSettingsViewController`；已有场景的 Group 参数也使用 `editGroup(_:)`。

分析时 `editGroup(_:)` 传入：`showCct: group.effectiveSupportCct`。后者在 `MeshNetwork+SunSmart.swift` 中使用 `nodes.contains(where: { $0.effectiveSupportCct })`。因此原结果为：

| 组成员 | 当前组场景色温条 | 推荐结果 |
| --- | --- | --- |
| 没有成员 | 隐藏 | 显示，可预设 |
| 全部是真正无色温能力的调光设备 | 隐藏 | 显示，可预设 |
| 含 CTL 设备，但单设备界面改成单白光 | 显示 | 显示 |
| 含可调色温设备或混合成员 | 显示 | 显示 |

模板参数 Picker 本来就默认显示色温，当前限制集中在共享的 Group 编辑入口。修复后仍应核对模板 → 参数分配 → Settings → 保存这一条路径。

源码入口：`SceneSettingsViewController.swift:350`、`:367`；`MeshNetwork+SunSmart.swift:1176`；`SceneAddViewController.swift:427`、`:1052`、`:1074`。

### 3. 隐藏控件不等于没有保存色温

`SceneExecuteDataPickerView.selectedCct` 在隐藏时仍返回传入色温，并按当前范围裁剪。Group 编辑初值使用已有参数，缺省才使用 4500K；完成回调仍写入草稿的 `cct`。

`SceneConfigurationStore` 保存组场景时，把这些参数写入既有 `group.info.sceneExecuteDatas`，不要求组内已经有设备。空组是合法的场景组配置，不等于没有选择任何组。

源码入口：`SceneExecuteDataPickerView.swift:155`；`SceneSettingsViewController.swift:362`—`:374`；`SceneConfigurationStore.swift:628`—`:643`。

### 4. 后加入设备已经能够继承组场景参数

既有链路为：

1. 组场景保存 Group 参数。
2. 设备加入组后，`SceneTargetResolver` 按当前成员解析目标；待加入设备的同步规划也能通过已有 `restoreData.addGroupAddress` 找到目标组。
3. `Node.getNodeSyncSceneDatas(group:)` 读取该组保存的场景参数，比较设备缓存及待同步状态。
4. `SceneExecuteData.deviceTarget(for:)` 按具体设备的有效色温范围裁剪目标。
5. 同步消息按实际能力选择 CTL、Lightness 或 OnOff，并走既有 Scene Store、回执和保存流程。

真正无色温能力的设备不会因此被要求执行 CTL；它的同步成功比较也跳过色温。仅改为单白光显示的 CTL 设备仍按现有自动化规则处理色温。

新成员必须完成既有组/场景同步后，才能认为设备已经存储并能调用该场景；显示控件或保存 App 配置都不代表这一步完成。

源码入口：`SceneTargetResolver.swift:249`、`:324`；`Node+SyncData.swift:1522`；`MeshNetwork+SunSmart.swift:1582`、`:1599`；`SceneCommandBuilder.swift:139`；`Node+MessageHandles.swift:18`。

## 已确认实施范围

1. **统一组场景编辑展示。** 在共享 `editGroup(_:)` 入口明确始终显示色温条，沿用现有 Picker、亮度条、OFF 行为和交互生命周期。覆盖创建、已有场景和模板创建后的组编辑。
2. **保留现有范围与默认值。** 亮度继续受 Group 的 `highEndTrim` 限制；色温继续取组内有色温能力成员的范围并集，没有这类成员时使用项目已有 2700～6500K。新参数仍默认 ON、100%（受上限约束）、4500K；已有参数照常读取。此次不扩大为全设备最大范围，也不修改色温步长。
3. **配置与即时控制分别判断。** 空组、无色温能力组允许改草稿和保存色温；即时色温控制继续检查 `group.effectiveSupportCct`，无可接收成员时不发送色温命令。正式预览/同步继续逐设备按能力选消息、裁剪范围。保留权限、紧急限制、断线、取消、退出和迟到回调保护。
4. **沿用既有持久化与入组同步。** 不新增成员变化恢复机制、隐藏值备份或同步状态；不批量重写历史场景。既有值再次编辑时仍遵守现有范围裁剪规则。
5. **单设备路径维持原规则。** Devices 场景的单设备及批量参数控件继续按当前设备显示能力处理，普通 Group 控制页也不因本次修改变成固定显示色温。

不建议增加“启用色温”开关：本次需求是让组预设稳定可编辑，新增开关会增加交互和字段语义，现有参数机制已经足够。

## 数据与兼容性

本方案**无数据库或 export JSON 结构变更**：不新增、删除或改名字段，不修改类型、层级、关联、必填/可空规则、默认值或字段语义。

- `cct` 原本就存在，含义仍是场景期望色温，单位 K；只让原来被隐藏的现有参数可见、可编辑。
- 无迁移、回填、索引或约束变化；旧记录及旧格式继续走原有读写路径，不新增缺字段规则。
- 导入导出、分享和云同步继续传递既有字段，旧版本可按现有方式读取；旧版界面仍可能按成员能力隐藏控件。
- 不修改 SDK、固件或服务器，不需要外部接口/部署配套。
- 共享场景代码影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；预计无新增资源或文案。

## 分析阶段验证与实施验收计划

本轮已完成：

- `python3 scripts/check_scene_configuration.py --suite selection`：selection 74 项、device parameter editing 51 项及 DeviceNameFilterSessionTests 通过。
- `python3 scripts/check_scene_configuration.py --suite targets`：28 项通过。
- 临时 Swift 边界复现：直接抽取当前 SDK 的能力属性、App 的 Group 能力/范围计算及 Picker 的隐藏色温取值；验证单白光 CTL 设备仍使组支持色温、空组返回不支持但隐藏值为 4500K、真正无色温能力的设备返回不支持、成员范围仍参与裁剪，4 个场景通过。

这些结果证明当前判定与数据解析行为；UIKit、设备成员来源和 Mesh 传输在夹具中为边界替身。没有把完整 SQLite 保存、重启、真实入组、ACK/Scene Store 和云端往返当作已验证。本轮只分析和新增此文档，按项目规则未构建、未操作真机。

确认实施后的最小自动化范围：

- 给现有 Scene 测试补共享 `editGroup` 行为用例，检查四种组的 Picker 都含亮度和色温；编辑 4000K 后关闭、再打开，草稿保留用户输入。
- 覆盖空组保存后重载，再加入色温设备的目标解析和任务生成；复用现有持久化夹具，验证组预设不丢失、已有成功目标不重发、待加入/失败目标仍保留同步任务。无色温设备不产生 CTL 参数命令；不同范围设备按自身范围裁剪。
- 复用 Group 即时控制及 Picker 交互回归，确认无色温组只改草稿；OFF、断线、关闭/取消和旧回调不引入发送回归。单设备及批量 Devices 编辑保持原行为。
- 一轮修改结束后构建一次 SunSmart Debug、generic iOS、关闭签名，使用已核对的本地 SDK workspace；无品牌分支或资源变更时不机械重复五品牌构建。

最短人工验收路径：

1. 新建空组 → 自定义创建场景 → 选择该组，确认同时显示亮度、色温；设置 40% / 4000K，DONE 后退出重进，值保持。
2. 向该组加入可调色温设备并完成同步 → 调用场景，检查亮度及色温；中断同步后重试、退出重进再确认。色温越界时以该设备允许范围为准。
3. 分别用真正单调光设备、CTL 设备切换单白光显示、混合组重复编辑；组场景均显示两条，单设备页面继续遵守原显示规则。
4. 从已有场景 Settings 和模板创建后编辑重复一次；检查 OFF、加减、关闭弹层与重新进入，确认预设和最终灯态符合既有交互。

## 实施结果（2026-11-07）

用户已确认：**组场景固定展示亮度和色温；沿用现有范围、默认值和保存/同步机制；实际发送仍由设备能力决定；单设备场景显示规则不变。**

生产代码仅修改 `SceneSettingsViewController.editGroup(_:)`，显式传入 `showCct: true`，并说明空组也需要为后续成员配置预设。模板参数原本默认显示两条，创建和已有场景复用该 Group 入口。范围、默认值、设备能力判断、持久化、同步、权限及取消机制均沿用现有实现。

新增行为测试在修改生产代码前，因空组未显示色温而断言失败；修改后通过。没有调整 SDK、依赖、数据库/export JSON、资源或品牌配置，没有提交或推送。

| 验证 | 结果与范围 |
| --- | --- |
| `python3 scripts/check_scene_configuration.py --suite selection` | selection 74 项、单设备编辑 51 项、新增 Group 编辑 32 项及名称筛选测试通过。覆盖空组、真正单调光组、单白光显示的 CTL 组、混合组，两条控件、默认值/范围、40%/4000K 写入重开、未改动值保持、亮度上限、退出后的迟到回调。执行生产编辑方法、Group 范围计算和 Picker 提交方法；UIKit 布局为夹具。 |
| `python3 scripts/check_scene_configuration.py --suite save` | 保存及协调器回归通过。新增空组 40%/4000K 保存后重新打开 SQLite、重建 Group/Scene，再接入待加入设备；单调光只生成 Lightness、色温设备按自身范围把 4000K 裁剪到 4500K；参数命令后跟 Scene Store。部分失败后重载，仅失败成员重试，组预设仍为 4000K。 |
| `python3 Tests/Scene/SceneGroupLiveControlTests.py` | 23 项通过。新增无色温能力组的采样与松手事件不发送色温；既有 OFF、取消、断线、权限、后台及提交后保护通过。 |
| `python3 Tests/UI/CustomDeviceSliderInteractionTests.py` | 127 项通过，覆盖滑条采样、OFF、多指/按钮接管和关闭最终值。 |
| `check_scene_configuration.run("roundtrip-group")` | 实际 SDK `SceneExecuteData` 编解码往返通过，检查原始参数、单位、HSL/LC 和清理状态。 |
| `git diff --check` | 通过。 |
| SunSmart Debug generic iOS | 通过，`xcodebuild` 最终退出码 0；Xcode 27.1（27A9275），关闭签名。 |

实际 SDK 编解码的定向命令：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -c 'import sys; sys.path.insert(0, "scripts"); from check_scene_configuration import run; run("roundtrip-group")'
```

持久化验证边界：执行真实 `SceneConfigurationStore`、App `SceneInfo` SQLite、任务参数生成、`applyMessageHandle` 及场景回执接受/写回逻辑。Group 参数通过已有夹具表持久化并重建，SDK Node 缓存仍为替身；实际 SDK Group 编解码单独验证。未覆盖完整 SDK 数据库重启和真实 Mesh ACK 解码/无线传输，不能将此结果作为真机 Scene Store/Recall 验收。

构建入口已核对 scheme 为 SunSmart、本地 SDK realpath 与上述 revision 一致。使用本任务独立且稳定的 DerivedData；没有使用 Simulator、安装真机、clean 或清理共享缓存：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-group-cct-cli CODE_SIGNING_ALLOWED=NO build -quiet
```

共享逻辑无品牌差异、资源或依赖变化，本轮选择 SunSmart 作为代表构建。待人工步骤沿用前文：空组设置 40%/4000K 保存重进，再加入色温设备完成同步并调用场景；补验真正单调光、单白光显示、混合组以及已有场景/模板入口。

构建过程包含未修改依赖/源文件的 Swift 并发、废弃 API 等告警，以及退出码为 0 但无额外输出的编译任务诊断；整个构建最终成功，未为这些输出改动依赖或重跑构建。
