# SR-BL2421-Mini 参数默认值分析与开发方案

日期：2026-10-16。状态：用户已确认并完成实施；22 个隔离行为用例、App 产品支持回归及 SunSmart generic iOS 编译通过。未运行真机、云端联调或完整 iOS SDK XCTest；SDK 改动尚未提交或发布。

## 结论

现有 `0x0A78 / 0x2013`、`0x0A78 / 0x24B1` 已实现“保留真实 CCT Models，默认使用 Single White 控制界面”，可以复用整条参数展示、保存、控制页刷新及导入导出链路。

必要调整位于 App 使用的本地 NordicSigMeshSDK：将 `0x2134` 纳入默认 Single White 产品，同时让窄色温范围判断只保留原有两个 PID。不能仅扩充 Single White 名单，因为当前窄范围判断直接复用了这个名单，会让 `2134` 错误采用 `2700K–5000K`。

推荐语义：本次改变未配置时的 App 展示默认值，保留用户已保存的选择与真实 CCT 能力。无需固件、服务端或数据库结构变更。

## 工作树与证据基线

- App：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-SR-BL2421-Mini-261016`；分支 `feat/SR-BL2421-Mini-261016`；HEAD `b404b12d`。调查开始时工作树干净。
- 本地入口：`SunSmartLocal.xcworkspace`，其中 `.local-sdk/nordic-sig-mesh-sdk` 的 realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK：分支 `one-dev`；HEAD `2598bd1`；本轮检查时无未提交改动。
- `SunSmart/devices_config.json` 已包含用户提供的完整设备资料，无需再次添加。`elementCount = 3` 和分类字符串用于设备资料，不单独证明 CCT 能力。
- 正式 `project.pbxproj` 当前实际记录的是 `git@github.com:maginawin/nordic-sig-mesh-sdk.git` 的 `release`，与 AGENTS 中的 gitee 地址不同。本轮只记录现状，不调整远端地址；实施及发布时需确认实际 SDK 发布目的地，不能把本地 SDK 生效等同于正式依赖已更新。

## 已证实的现有行为

### 1. 能力来源与同类设备

SDK `Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift` 从 Composition 的 Models 中查找 Light CTL Temperature Server；`Node+Propertys.swift` 的 `rawSupportCct` 判断为 `temperatureModel != nil`。

因此用户观察到的 CCT 界面与代码能力判断一致。但本轮没有该设备实际 Composition/报文，不能仅根据 JSON 枚举它的真实 Element/Model 分布，也不能确认固件实际支持的所有温度值。

| Company/PID | 本地产品名称 | 未配置时控制页 | 未配置时 Absolute CCT Range |
| --- | --- | --- | --- |
| `0A78/2013` | SR-BL9035B-PIR-V | Single White | 2700K–5000K |
| `0A78/24B1` | SR-BL9035B-V | Single White | 2700K–5000K |
| `0A78/2134` 当前 | SR-BL2421-Mini | Tunable White | 2700K–6500K |
| `0A78/2134` 目标 | SR-BL2421-Mini | Single White | 2700K–6500K |

默认控制页来源是 `isSingleWhiteDefaultCctProduct`；默认范围来源是 `isNarrowDefaultCctRangeProduct`。后者当前直接返回前者，是此次必须解除的耦合。Up/Down Light、Downlight 的 steps 规则独立存在，`2134` 不在其名单中。

### 2. 参数页入口、显示与编辑

入口链路：Space More Settings 的设备编辑权限检查 → `DeviceCategorysViewController` → `DeviceParameterDevicesViewController` → `DeviceParameterSettingsController`。

- 分类页要求设备已完成 keybind、具备参数设置能力；常规参数按 PID 分类。All Devices 目前只进入 behaviorOnly，不混合编辑本次两个参数。
- 参数页用 `rawSupportCct` 决定是否提供 Change Control Page 与 Absolute CCT Range。默认显示 Single White 后，两项仍可编辑，不会隐藏切回 Tunable White 的入口。
- `defaultChangeControlPage` 决定 `(Default)` 标记和初始默认值；打开参数开关时，读取各设备的有效配置。一组设备的已有配置不一致时，沿用现有默认值回退机制。
- Cell 已支持 `Single White (Default)`、`Tunable White` 两个选项，并已有中英文解释文案。采用已有 `tunable_white` 的正确英文 `Tunable White`，不新增用户输入中的 `Tunable Whtie` 拼写。
- Absolute CCT Range 直接复用现有 slider：下限可选 `1000K–2700K`，上限可选 `5000K–10000K`，步进 `100K`；Reset 使用产品默认范围，本设备为 `2700K–6500K`。
- 两项开关沿用“是否将该参数纳入本次设置”的含义；关闭或退出而未点击 Setup 不会保存草稿。

### 3. DIM 展示与真实 CCT 能力的边界

SDK 中现有区分：

- `effectiveChangeControlPage`：已保存的 `changeControlPage` 优先，否则采用产品默认值。
- `singleDeviceDisplaySupportCct`：真实 CCT 能力存在，且有效控制页不是 Single White。
- `effectiveSupportCct`：等同于真实 `rawSupportCct`，不受控制页选择影响。

单灯详情、基础控制、设备 Cell、灯头部和信息页等已经使用 `singleDeviceDisplaySupportCct`。扩充默认产品规则后，这些入口会一起采用 DIM 展示，不必逐页增加 PID 分支。

Group 控制页另有现成的 `rawSupportCct && effectiveChangeControlPage == .tunableWhite` 集合：组内只有默认 Single White 的 `2134` 时不显示 CCT；混入其他 Tunable White 设备后仍显示 CCT。

Scene、Profile、全局 Group 能力与批量控制继续使用真实 CCT 能力。Group 色温命令仍发往组地址；默认 Single White 并不保证设备不接收组播或自动化 CCT 命令。本次需求按“默认展示 DIM”实施，不能将其表述为禁用固件 CCT 或全局改成纯 DIM 设备。

### 4. 保存、同步与恢复

- Change Control Page 点击 Setup 后写入 `node.changeControlPage`，调用 `savePropertys()` 并发布 Space 数据变更通知；单独设置此项无需向设备下发切换工作模式的指令。
- Absolute CCT Range 使用现有 `.absoluteCctRange` 同步任务，经 `LightCTLTemperatureRangeSet` 下发；App 的成功应用路径才保存 `absoluteCctRange`、实际范围缓存及截断后的当前温度。
- 两项同时设置时，控制页选择先作为本地成功项保存，色温范围独立执行同步。范围失败/取消不回滚已保存的控制页，这是现有分项结果语义；重试继续使用已有机制。
- Classic/Professional 添加流程已有范围 Get；当前 SDK 的 Range Status 更新 `lightCTLTemperatureRange`，不会把 `changeControlPage` 或 `absoluteCctRange` 强写为默认值。
- SDK 数据库已有可空字段；App 的 ExportData/ImportData 已保存、恢复显式控制页和范围值。未配置字段保持缺省，由 getter 计算默认值，不需要数据迁移。
- Device Restore 对具备 CTL/Temperature Models 的节点复制旧的控制页和范围；删除设备时清除扩展配置，正常重新添加后重新采用默认值。
- 参数列表、筛选器从 effective 值派生；控制页在再次进入时重新读取显示能力，因此应一起纳入验收。

## 推荐实施方案

1. 修改 SDK `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`：在 Company ID 为 `0x0A78` 的前提下，将 `0x2134` 加入 `isSingleWhiteDefaultCctProduct`。
2. 同文件将 `isNarrowDefaultCctRangeProduct` 明确限制为原有 `0x2013`、`0x24B1`，保留 Company ID 检查。于是 `2134` 使用标准 `2700...6500`，不需要新增范围常量或另造策略层。
3. 扩展 SDK `Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`，验证目标产品、旧产品、其他 Company、显式配置优先及实际 CCT Models 的展示语义。现有默认值测试仅创建 Node 并设置 CID/PID，不能替代带 Models 的能力测试。
4. 复用 App 现有 Cell、默认标记、解释文本、保存/同步/刷新和导入导出。预计无需修改 App 生产代码、JSON、资源或本地化，也不新增 API/持久字段。
5. 实施后在本文补充 SDK revision/未提交差异、实际验证结果及正式 SDK 发布待办。仅在用户后续明确授权时提交或发布。

对备选方式的比较：仅在参数页写死默认值不能改变入网后单灯展示；在添加流程直接保存 Single White 会将默认值变成显式配置，漏掉存量缺省数据；修改设备 Models/全局 CCT 能力会影响同步、场景及切回 Tunable White。现有 getter 的最小扩展能同时覆盖新设备和存量缺省节点。

### 存量数据约定

| 已有状态 | 更新后的预期 |
| --- | --- |
| `changeControlPage == nil` | 自动采用 Single White；无需删除重加 |
| 已保存 Tunable White | 保留用户选择，不强制覆盖 |
| 已保存 Single White | 保持 Single White |
| `absoluteCctRange == nil` | 2700K–6500K |
| 已保存自定义范围 | 保留；点击 Reset 并成功设置后回到 2700K–6500K |
| 老格式导入缺少本次字段 | 按目标产品默认规则解释 |
| 显式设置后重新启动、导入或 Restore | 沿用现有显式字段持久化/恢复规则 |

旧版 App 未包含本次规则时，同一缺省节点仍可能默认显示 Tunable White。若需要跨新旧版本强制一致，属于额外迁移/版本兼容需求，本次不把默认值写成显式值来隐式改变该语义。

### 受影响范围与排除项

- 五品牌共同使用 SDK 和相关 App 逻辑，运行行为均受影响。本次无公共 API、资源归属或品牌条件编译变化，开发验证先选 SunSmart；只有实施发现品牌编译差异时扩大构建范围。
- 本机多个 App 工作树共用 `one-dev`，修改会让其他使用该 SDK 的本地构建同时采用新规则。实施前重新检查 SDK 状态及写入所有权。
- 不复制 `2013/24B1` 的其他产品特例，例如 PWM 隐藏规则；不改变 `2134` 已有外接光感、校准、移动灵敏度分类。
- 本次不修改固件、服务端、网络身份校验、权限、订阅和场景协议；无需新增外部接口。正式 App 交付依赖 SDK 改动进入实际使用的 release 来源。

## 验证计划与边界

### 自动验证

1. 默认值/回归：`0A78/2134` → Single White + 2700–6500；`2013/24B1` 保持 Single White + 2700–5000；普通 CCT 产品、steps 产品保持原规则；同 PID 的其他 Company、nil/未知身份不误入特例。
2. 能力/显式值：带 Temperature Model 的 `2134` 默认 raw/effective CCT 为 true、单设备显示 CCT 为 false；显式选择 Tunable White 后显示为 true；无 Temperature Model 时不得凭 PID制造 CCT 能力；显式范围优先且 clamp 使用有效范围。
3. 优先扩展现有 SDK XCTest。当前 Package 含 UIKit 依赖，macOS `swift test` 存在宿主限制；本轮未执行，不宣称这些用例能直接运行。实施时为核心规则提供轻量行为夹具执行生产逻辑，避免只匹配源码文本；完整 Node/UIKit 路径保留为 iOS 运行验收，不新建临时 Xcode 工程或使用 Simulator。
4. 一轮修改后使用已核对的 `SunSmartLocal.xcworkspace`、`SunSmart`、Debug、generic iOS、关闭签名完成一次构建，复用稳定 DerivedData 目录 `SunSmart-feat-SR-BL2421-Mini-261016`。编译不替代设备行为验证。

### 最短人工验收

1. 添加一个 `2134` 或打开未保存过控制页选项的存量节点：设备卡片和单灯页应为 DIM；进入参数页开启选项，显示 `Single White (Default)`、`Tunable White`；未配置范围为 `2700K–6500K`。
2. 切换 Tunable White 并 Setup：返回显示 CCT，重启仍保留；再切回 Single White：隐藏 CCT，但参数页仍能切回。
3. 检查范围 slider 的边界/步进，设置自定义范围并成功下发后重进保持；Reset 并成功设置后为 2700–6500；范围失败/取消能重试，未成功时不应当作已配置。
4. 仅含默认 `2134` 的 Group 隐藏 CCT；混合 Tunable White 设备时显示 CCT。Scene/Profile 保留原 CCT 能力和同步行为。
5. 使用显式控制页/范围数据做导入或恢复，确认配置保留；缺字段数据采用新默认。真机运行、固件范围接受情况、实际云端字段往返本轮均未验证，由用户最终验收。

## 确认与实施结果

用户已回复“确认方案，继续”，按“缺省值改为 DIM、显式 Tunable White/自定义范围继续保留、自动化 CCT 能力不变”的边界实施。

### 实际修改

SDK `one-dev` 基于 `2598bd1`，新增以下未提交差异：

- `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`：默认 Single White 名单加入 `0x2134`；窄范围名单仍限定为 `0x2013/0x24B1`，两者都校验 Company ID `0x0A78`。
- `Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`：新增 5 个测试方法，覆盖 Mini 默认值、显示切换与真实能力分离、无 Temperature Model、自定义范围及默认恢复、CID/PID 边界；加强旧 Single White 产品显式选择兼容检查。
- `scripts/check_node_cct_defaults.sh`：新增可执行脚本，复用 XCTest 文件中的行为断言，编译生产 CCT getter、范围常量、关联对象存储和 UpDownLightProductPolicy；仅替换 Node/Model 容器边界，使用本机 macOS XCTest 框架执行。

App 工作树只新增本文，无 App 生产代码、工程、资源、依赖声明或锁文件修改。现有 JSON、页面组件、中英文文案和保存/同步流程均直接复用。

### 已执行验证

| 验证 | 结果 | 证据边界 |
| --- | --- | --- |
| 修改前运行新增 CCT 夹具 | 22 个方法中 2 个失败，共 6 个断言失败 | 明确复现 Mini 默认为 Tunable White、默认显示 CCT 的差异 |
| 修改后 `bash scripts/check_node_cct_defaults.sh` | 22 个方法，0 failures | 执行生产 getter 和真实关联对象存储；Node/Model 容器为夹具，不覆盖 Composition 解码或数据库 |
| App `bash scripts/check_up_down_light_product_support.sh` | passed | 现有产品 JSON/能力契约回归，包含 `2134` |
| SDK `git diff --check`、脚本 `bash -n` | 通过 | 差异格式和脚本语法 |
| SunSmart Debug generic iOS 构建 | `BUILD SUCCEEDED`，exit 0 | 实际构建解析到 `.local-sdk/nordic-sig-mesh-sdk`，编译及链接成功；不是运行验收 |

构建使用 `SunSmartLocal.xcworkspace`、scheme `SunSmart`、`-sdk iphoneos`、`-destination 'generic/platform=iOS'`、`CODE_SIGNING_ALLOWED=NO`；DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-SR-BL2421-Mini-261016`。本次实际 SDK 为 iPhoneOS 27.0。

完整 SDK 测试中的 3 个既有 Vendor Status 用例需要完整 iOS SDK，隔离 runner 明确排除；没有将其计入 22 个通过用例。本次没有执行完整 `swift test`、iOS XCTest 或 Simulator。

### 未完成项与交付边界

1. 人工执行上文最短验收，重点确认默认 DIM、切回 Tunable White、重新进入/重启及范围 Reset；设备接受温度范围、BLE 失败/重试、导入恢复和实际云端字段往返尚无本次运行证据。
2. 正式交付需要将上述 SDK 差异发布到 App 实际使用的 SDK release 来源；当前仍为 `one-dev/2598bd1 + 本文列出的未提交差异`。本任务未新增 SDK API，也未修改正式远端配置。
3. App/SDK 均未提交或推送。其他工作树若映射同一 `one-dev`，会读取本次 SDK 默认规则。
