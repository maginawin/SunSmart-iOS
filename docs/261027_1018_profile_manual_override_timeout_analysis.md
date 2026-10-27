# Manual override timeout 回退显示分析与修复方案

日期：2026-10-27。范围：App 端分析与修复。用户确认后已完成 Timeout 共享控件修复、针对性回归与 SunSmart generic iOS Debug 构建；真实 UI 与设备计时待人工验收。

已确认 SAVE 下发 60000ms，设备返回成功，上传后的云端 Profile 为 60 秒；没有发现本次保存把它写回 5 秒的证据。App 共享控件存在可复现的浮点截断显示缺陷，与现场现象高度吻合；但日志缺少重新进入页面时的模型值和滑条原始值，现场直接成因还需该采样闭环，不能宣布已证实 iOS 27 回归。

## 1. 日志中的发送和接收

输入：桌面的 `add to occupancy sensing.txt`、`change to 1min.txt`。以下只引用业务参数，不复制网络密钥、设备密钥或 HTTP 认证信息。

设备 L1：用户提供 CID `0A78`、PID `2134`、型号 `SR-BL2421-Mini`，三个 Elements。日志中主地址为 `0002`，其余地址为 `0003`、`0004`；Vendor 设置发往 `0002`，Light LC / Profile Scene 操作发往 `0004`，与当前 App 按相应 Model 所属 Element 寻址一致。

| 阶段 | 日志证据 | 判断 |
| --- | --- | --- |
| 加入 Group | 8 次 Subscription Add 均收到成功 Status；Sensor Publication 设置成功 | 日志所示订阅和发布操作有对应成功应答 |
| 首次调用 General Scene | 第 157–168 行：Recall `FF00`，返回 `5E 02 00 00`，SDK 解码为 `Scene Not Found` | 不能说整份日志“所有应答都成功”；符合新设备尚未存储该场景的情形 |
| 初始 Timeout | 第 203 行：`F0 78 0A 32 01 00 88 13 00 00`；第 212 行：`F3 78 0A 32 00 00` | 下发 enabled=1、standby=0、5000ms；ret=0 |
| 初始 Profile 其余参数 | LC Mode/Occupancy Mode 开启；Lightness On/Prolong/Standby 为 65535/32767/0；T1–T5 为 2000/1200000/2000/600000/2000ms | 日志中 Property Status 与下发值一致 |
| 初始场景保存 | 第 469–480 行：Store `FF00` 后成功，场景列表含 `FF00` | 后续 SAVE 再 Recall `FF00` 已成功；初次 Scene Not Found 不能解释本次 UI 回到 5s |
| 初始其他设置 | Power-up Restore；Sensitivity=62258，返回相同值 | 对应当前 App 参数；物理行为未计时验证 |
| SAVE 1min | `change to 1min.txt` 第 49–63 行：interval=60000，PDU `F0 78 0A 32 01 00 60 EA 00 00`，返回 `F3 78 0A 32 00 00` | `60 EA 00 00` 为小端 60000，毫秒换算正确 |
| SAVE 保护与保存顺序 | 暂停 Sensor Action Publication → Recall `FF00` → 写 Timeout → Store `FF00` → 恢复 Action Publication | 对应当前 Profile 保存路径；这些应答均成功 |
| SAVE 前云端基线 | 第 121 行：Profile type=3，manualOverrideTimeout=5；随后 `noPendingReceipt` | 是上传前的旧配置基线，不能据此判定发生回滚 |
| SAVE 后云端回读 | 第 185 行：同一 Profile type=3，manualOverrideTimeout=60；第 187–188 行 `confirmed`、CloudSync Success | 不是仅有 HTTP 200；返回配置本身确实已经是 60 秒 |

上述 Vendor RET 是合法的短回包。现用私有协议的 SET 0x32 RET 定义为子码 0、ret=0/1，不要求回显间隔。SDK `SunricherVendorStatus` 对三字节参数解析为成功且 `parameters=nil`；`VendorServerDelegate.model(_:didReceiveResponse:toAcknowledgedMessage:from:)` 随后按匹配的原 SET 请求，将 Node 的 enabled、state、interval 缓存更新。因此这里不能把 `parameters=nil` 判为丢失 60 秒的原因。

边界：ACK 与按请求更新的 Node 缓存不是设备内部定时器的独立读回。当前私有 GET 0x32 返回的是 `is_manual`，不是配置间隔；不能用它证明设备已按 60 秒计时。物理计时与掉电保持仍需实机验收，本次 UI 分析不要求修改固件。

## 2. 显示、保存、恢复的完整链路

实际入口是 `GroupViewController.groupProfile()`，不是占位的 `GroupProfilesViewController`：

1. 从 `group.info.profile` 创建 `ProfileSettingsViewController`，编辑对象为 Profile 的副本。
2. `updateUI()` 把副本的整数秒数赋给 `ProfileManualOverrideTimeoutView.second`。
3. 控件在选项表中查找秒数，找到后给 `slider.value` 赋整数档位；选项依次为 5s、1–60min、infinite，下标为 0–61。
4. `updateValue()` 又从滑条读回 Float，以 `Int(slider.value)` 截断取下标，再设置文案。加减按钮、开关和滑动回调也走这一取值方式，未配置已有的 `step=1`。
5. 用户编辑回调才修改副本的 `manualOverrideTimeout`；仅渲染不会发出该回调。
6. SAVE 通过生命周期事务更新 `group.info.profile` 并存入 SQLite，再生成设备同步任务和云端上传。SQLite、Profile copy/update、导入导出均以整数秒保存该字段；Mesh 下发时才转换为毫秒。
7. 再次进入页面重复步骤 1–4。没有从设备 Timeout 缓存反向覆盖 Profile 秒数的路径。

**已证实的代码缺陷**：用连续 Float 作为离散选项的持久显示依据，并直接截断。若预期档位 1 读回 `0.99999994`，则下标变为 0，显示 5s，而 Profile 仍可保持 60 秒。它无需依赖错误的 Mesh 命令或云端回滚就能产生本次表象。

Apple 将 UISlider 定义为连续范围控件，`value` 类型为 Float；此接口本身不能替业务层定义离散档位规则。[UISlider 文档](https://developer.apple.com/documentation/uikit/uislider)、[value 文档](https://developer.apple.com/documentation/uikit/uislider/value)。本次没有取得 UIKit 内部归一化算法的证据。

**尚未证实的现场环节**：日志没有页面重开时的 `group.info.profile.manualOverrideTimeout`、副本秒数、预期下标和实际 `slider.value`。如果现场前三者为 60/60/1、后者略小于 1，即可闭环；如果模型本身已经为 5，应转查该次重开前的对象替换或持久化读取，不能套用浮点解释。

## 3. 隔离复现与数值范围

已在临时目录提取当前控件的 `second`、选项初始化、显示、加减、开关与滑动方法，保留原方法逻辑，用轻量替身提供 UILabel/UISwitch/Slider。运行 Swift 验证，未运行 UIKit、Simulator 或真机；临时文件已随验证结束删除。

| 输入条件 | 实际结果 |
| --- | --- |
| 滑条精确返回设置值 | 62 个选项全部匹配；渲染回调数为 0 |
| 每个正整数档位读回相邻的较小 Float（nextDown） | 1–60min 以及 infinite 均显示前一档；这是边界注入，不是实机发生率 |
| 示例归一化计算 `Float(index) / 61 * 61` | 下标 1、2、4、8、16、32 被截断成前一档 |
| 该示例下加载 60 秒 | 模型=60，slider=0.99999994，文案=5s，编辑回调=0 |
| 上述状态按一次加号 | 回调=60，显示=1min，未达到模型意义上的下一档 120 秒 |
| 加载非预设值 90 秒，滑条无误差 | 模型=90，文案却为 10min；这是现有查找失败后固定回退下标 10 的结果 |
| infinite 档位注入 nextDown | 文案=60min，开关变为启用；尚无证据表明实际 UIKit 在端点产生此漂移 |

所以它不是“从 5s 改为 1min”专属的转换问题。任何入口给该控件加载 60 秒都经过同一路径；其他分钟档也可能受影响。示例计算中的 1/2/4/8/16/32min 只能作为优先人工复现集合，不能当作 iOS 27 的确定受影响清单。全部 62 档都应进入离散映射回归。

5s 为最小端点下标 0，不会因非负微小值截断而再下降。infinite 的开关语义必须独立验证，不能只验证文字。用户未触碰控件时，显示错值本身不会改模型；一旦继续加减、拖动或切开关，错误档位可能进入编辑回调，不能只修文案。

合法数据范围也大于 UI 预设：当前导入完整性与 SQLite 允许 UInt32 秒数，所以 90 秒之类的非预设值不能静默变成 600 秒。另有独立的超大值风险：现有 `min(second * 1000, UInt32.max)` 在乘法后才限幅，有限值超过 4,294,967 秒会先溢出；UI 5s–60min 不触发，UInt32.max 已单独处理。本次现场为 60 秒，与溢出无关；该导入边界问题单独记录，不据此改变固件的时间语义。

## 4. Profile、入口与品牌影响

| Profile | Manual override timeout 的本次风险 |
| --- | --- |
| Occupancy sensing with daylight harvesting | 共用同一控件，可编辑，存在相同风险 |
| Vacancy sensing with daylight harvesting | 同上 |
| Occupancy sensing | 现场类型，同上 |
| Vacancy sensing | 同上 |
| Daylight harvesting | 控件可编辑，默认 infinite；启用有限时间后同样受影响；下发结束状态为 on，其他类型通常为 standby |
| Proximity lighting | 同上 |
| Proximity lighting with photocell | 同上；白天/夜间区块不另建 Timeout 控件 |
| Manual control | Timeout 控件隐藏，默认 infinite；正常页面没有此字段的可编辑回退现象 |

创建 Group 的 Profile 编辑与已有 Group 的编辑均使用这个控制器，空 Group、只读页面和切换 Profile 后的渲染也应保持一致。Timeout 控件没有 CID/PID 或 iOS 版本分支，不应对 `2134` 加专用补丁。已解析当前工程的 Sources 归属：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 均编译这个控件及控制器；该页面可达时使用相同实现。

该控件文件最近一次提交为 2025-06-07，相关截断逻辑并非新增加的 iOS 27 专用代码。系统变化可能暴露既有假设，但没有相同 App 构建、相同数据的跨系统运行证据，不能确认“iOS 27 才有”。

## 5. 建议修复范围

推荐在现有 `ProfileManualOverrideTimeoutView` 中完成局部、完整修复；不新增 PID 规则、独立控件或全局浮点补偿常量。

1. **现场闭环诊断。** 实施时在未修复逻辑上用 DEBUG 采样一次页面加载的模型秒数、副本秒数、预期档位、滑条读值和文案；编辑与 SAVE 只记录该字段。不输出凭据。如果模型已经变成 5，先调整原因判断。
2. **统一离散选项。** 复用 `CustomDeviceSlider` 现有 `step=1` 能力；在 Timeout 控件内统一计算和夹紧整数档位。拖动按最近档位取值，加减基于整数档位，避免在 Float 上连续累加后截断。标签、开关、编辑回调必须使用同一确定值。
3. **模型驱动渲染。** 外部设置 `second` 时，显示从模型秒数/已确定档位生成；不再为了显示重新读取 Slider。程序化绑定不发编辑事件，避免打开页面就变为 dirty。infinite 判断使用秒数或整数选项，不比较浮点相等。
4. **保留非预设值。** 对当前数据层接受的非预设秒数显示准确时长，保持原值；只有用户明确操作时间控件才切换到预设档位。加减可分别选择严格更大/更小的相邻预设，拖动选择预设；开关恢复既有默认 10min 行为。不能加载即改值、落库迁移或伪装成 10min。新增文案如有需要按现有英文、简体中文国际化规则处理。
5. **保持保存链路。** 不改变 Group 事务、SQLite 格式、秒/毫秒约定、云端协议、Vendor 短 ACK 兼容或失败重试机制；也不把模型值强制改成界面读回值来掩盖显示问题。

复用比较：仅加 `step=1` 能消除已复现的整数附近误差，但不能处理非预设值显示，也继续让显示依赖控件回读；只改标签又遗漏加减/开关/回调。以上组合仍局限于既有控件，覆盖同一问题的全部入口。

不建议全局把 `CustomDeviceSlider` 默认改成整数：它还用于亮度、色温、DALI、上下光比例、校准等，部分使用不同步长。已核对其中已有 step 用方；共享 setter 存在内部同名变量遮蔽，导致 setter 中计算的步进值未写回外层变量，但 getter 的步进取整有效。Timeout 当前 step=nil，遮蔽不是本次直接原因。本轮优先复用现有 getter 能力并保持局部整数状态；共享 setter 修理应另立有对应使用方回归的改动。

同类待跟进点：Profile Level、Power-up、Standby、Adjust speed 也有 Float → Int 截断；Sensitivity 加载文案直接来自模型，但其底层交互仍使用通用 Slider。它们是代码级风险线索，尚未取得本次对应的运行失败证据，不自动打包修改。超大导入秒数的溢出保护也单独规划，后续需同时统一任务比较、消息生成与成功判断，不能只改发送处。

## 6. 验证与实施边界

分析阶段完成：两份日志的业务命令/应答核对、页面到保存/导入导出/SDK 回调的静态追踪，以及上述生产方法的隔离数值复现。分析阶段未运行 App 构建或真机；用户确认后的实施结果见下一节。

实施后最小验证：

- 离散行为回归覆盖全部 62 档、整数附近的上下浮点邻值、拖动舍入边界、加减端点、infinite 开关及默认恢复；断言显示值与回调值一致，单纯加载无回调。
- 90 秒等非预设值保持原值、准确显示；无编辑 SAVE 不变；只编辑其他字段不改变 Timeout；退出不保存不落库。
- 覆盖创建/已有 Group、七个可编辑类型、Manual control 隐藏、只读状态、类型切换和返回重进。选择代表类型跑交互，全部类型跑控件策略，不要求七套重复 Mesh 测试。
- 复用 `scripts/check_profile_persistence.py` 的真实临时 SQLite 回归，补 5s/60s/3600s/infinite/非预设值的保存、重载、copy、导入导出保值断言；该回归不代表 UI 通过。
- 一轮生产代码修改稳定后，使用实际映射正确的 `SunSmartLocal.xcworkspace`，SunSmart Debug、generic iOS、禁止签名构建一次。若保持共享 Swift 逻辑且无品牌条件/资源变化，不机械重复全部品牌构建。
- 人工最短验收：L1 所在 Group 设置 5s→1min、SAVE、返回重进与重启 App；再测 2/4/8/16/32/60min、infinite→启用、加减及滑动结束。核对 UI、保存前整数秒数、下发毫秒数、云端回读一致。选另一种 Profile 验证同一修复。用户自行完成，默认不安装或运行真机。
- 如需判定 OS 回归，用同一 App 构建、相同 Profile 数据，在 iOS 27 与旧系统比较上述 DEBUG 采样；缺少对照不妨碍修复已证实的离散值处理缺陷。
- 如需验收固件实际超时，在没有人体/开关等重置计时因素的受控条件下单独验证；不把成功 ACK 当作计时通过。

## 7. 实施与验证结果

已实施：

- `ProfileManualOverrideTimeoutView.second` 为显示与编辑的整数数据来源；加载不再把 Slider Float 截断后当作显示值。加减按原始秒数查找严格相邻的预设，拖动使用整数步进、舍入和边界夹紧，文案、开关和回调值一致。
- Infinite 由整数 sentinel 判断；拖动经过 Infinite 时仍允许拖回，手势结束/取消才关闭滑条。无实际 valueChanged 的 touch-down 后松手/取消只刷新 UI，避免把 90 秒等历史值变成最近预设。
- 非预设值保留原值，复用已有 `sec` 本地化 Key 显示准确秒数；补数值标签与 Timeout 标签的间距和缩放限制。没有新增资源或本地化 Key。
- 只读保护覆盖滑动、加减及开关；仅真实改变值才发编辑回调。移除该控件没有消费者的 throttle 定时器配置，复用现有取消结束回调能力。
- `ProfileSettingsViewController` 增加 DEBUG 的 `[ProfileTimeout] event=bind/save`：记录 Profile 类型、Group/草稿/控件整数秒数、滑条标识和有效档位、文案。`sliderIndex` 是启用 step 后的有效值，不伪装为 UIKit 原始值。当前并行几何诊断的 `[SliderGeometry] id` 可与 `sliderID` 关联，查看其 `rawValue`；此日志来自另一项修改。本任务没有改共享 Slider、SDK、协议、数据库结构或云端同步代码。

由于没有运行真机，未取得原版现场的重开采样；修复依据是已确认的代码缺陷和隔离复现。iOS 27 独有性、实际 UIKit 手势与布局、固件 60 秒计时仍不宣称通过。

| 验证 | 结果与边界 |
| --- | --- |
| 新增 `Tests/UI/ProfileManualOverrideTimeoutTests.py --baseline` | 同一测试在 HEAD 原版控件上复现 `60-second reload must show 1 min despite Float normalization` 失败 |
| 新增 Timeout 回归 | 2636 项断言通过；提取生产控件行为与实际共享 Slider getter/setter，注入四种 Float 后端；覆盖全部 62 档、上下邻值、半档、端点、加减、Infinite 往返、重复回调、取消、只读及非预设值的英文/中文显示。未运行 UIKit |
| `scripts/check_profile_persistence.py` | 完整现有回归通过；新增 56 个组合，覆盖八种 Profile × 0/5/60/90/3600/3660/UInt32.max 秒，校验独立编辑副本、其他字段修改、SQLite 重新连接、云端导入导出保值 |
| SunSmart 构建 | `SunSmartLocal.xcworkspace`、SunSmart、Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO；退出码 0，生成 App；Xcode 构建记录为 0 errors、122 warnings。警告涉及现有依赖与弃用 API |
| 差异检查 | `git diff --check` 通过；没有提交、推送或改动 SDK |

构建使用稳定且独立的 DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-SR-BL2421-MINI-261027-timeout`，避开并行几何任务的目录。该构建包含工作区当时的共享 Slider 几何及 DEBUG 诊断修改，但本任务没有验证它们的真实布局表现。

人工最短验收：

1. L1 所在 Group：5s→1min，SAVE 后返回重进，再重启 App；均应显示 1min。DEBUG `save seconds=60`，重开 `groupSeconds/draftSeconds/viewSeconds` 应为 60。
2. 加减或拖动测试 2/4/8/16/32/60min；拖到 Infinite 后不松手再拖回，应可恢复有限值；松手停在 Infinite 后开关关闭，再启用恢复 10min。
3. 选另一种可编辑 Profile 重复 1min 保存重进；如有 90 秒历史数据，未修改 Timeout 时必须仍显示准确秒数，单独修改其他字段不改变它。

超大有限秒数的乘法溢出、共享 Slider setter 遮蔽、其他字段的 Float 截断仍是第 5 节记录的独立待办，未扩入本次实施。

## 8. 追溯入口

分析快照：App 分支 `fix/SR-BL2421-MINI-261027`，HEAD `f401123a`；初始工作树干净。本地 workspace 的 `.local-sdk/nordic-sig-mesh-sdk` 实际指向既定 `one-dev`，SDK HEAD `e7c1a7f`，工作树干净。未改动 SDK；日志未提供精确 App build/SDK revision，当前源码与现场版本仍存在版本核对边界。

分析收尾时检测到其他任务在同一工作树修改 `CustomDeviceSlider.swift` 并新增 `Tests/UI/CustomDeviceSliderGeometryTests.py`。实施期间再次只读核对：差异为 iOS 27 自定义滑块/轨道几何分支与 DEBUG 诊断，未修改 `value`、`step` 或 Timeout 控件；不改变本次离散数值隔离复现结论。本任务没有编辑、撤销这些文件。

- [Timeout 控件](../SunSmart/Main/Profile/View/ProfileManualOverrideTimeoutView.swift)：`second`、`updateValue`、加减/开关/滑动回调。
- [共享 Slider](../SunSmart/Common/View/CustomDeviceSlider.swift)：`value` getter/setter、`step`、结束与取消回调。
- [Profile 页面](../SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift)：副本初始化、`updateUI`、`saveAction`、Timeout delegate。
- [Group 入口及保存](../SunSmart/Main/Group/Controller/GroupViewController.swift)、[创建 Group 入口](../SunSmart/Main/Group/Controller/GroupAddViewController.swift)。
- [Profile 模型](../SunSmart/Main/Profile/Model/Profile.swift)、[数据库](../SunSmart/Common/Data/Database.swift)、[导入](../SunSmart/Common/Data/ImportData.swift)、[导出](../SunSmart/Common/Data/ExportData.swift)、[云端版本处理](../SunSmart/Common/Data/SpaceConfigurationSafety.swift)。
- [同步差量判断](../SunSmart/Common/Data/Node+SyncData.swift)、[消息生成](../SunSmart/Common/Data/Node+MessageHandles.swift)、[同步终值判断](../SunSmart/Main/Space/Model/SyncDevicesCellModel.swift)。
- SDK `Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift` 与 `Message/Vendor/SunricherVendorStatus.swift`：按已应答请求回填 Node。
- [本机私有协议](/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/_protocols/sunricher_protocol_vendor.md)：SET/RET/GET 0x32、SET/RET 0x46。协议文档说明与实际设备行为分开判断。
