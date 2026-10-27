# Group 调光后 ON 无法开灯：分析与实施记录

日期：2026-10-27。状态：用户已确认方案，App 修复与相关自动验证完成，真实设备验收待用户执行。SDK 未修改，未安装或运行真机。下文根因部分记录修复前行为，末节记录实际实施及结果。

## 结论与证据边界

已定位 App 缺陷：滑条结束后的迟到 `valueChanged` 可以重启限流定时器；OFF 刷新滑条时，0 被当前 1...100 范围夹成 1，残留定时器把它作为用户调光发送。Group 的发送回调同时覆盖本地亮度和开关状态，导致下一次预期 ON 的点击实际发送 OFF。

日志后面确实也有真正的 ON（TID 127），其操作码、目标和 ON 参数与最初正常 ON 相同，只是 TID 不同。因此不能把全部现象解释成“后面的 ON 都变成 OFF”。1% 命令可能同时改变设备最后非零亮度，导致真正 ON 后仍非常暗；这部分需要设备状态读回，不能仅靠发送日志认定固件内部行为。

## 日志中的实际命令顺序

来源：[group control logs.txt](</Users/maginawin/Desktop/group control logs.txt>)。下面行号指原始日志；所有命令目标均为组地址 `0xC000`，发送者为 App Provisioner `0x0001`。

| 日志行 | 操作/现象 | 实际发送 | 含义 |
| --- | --- | --- | --- |
| 19–21 | 初次 OFF | `0x8203 / 00 77` | OFF，TID 119 |
| 37–39 | 初次 ON，用户确认正常 | `0x8203 / 01 78` | ON，TID 120 |
| 86–158 | 调光 | `0x824D`，37354、43253、43253 | 约 57%、66%、66%，TID 121–123 |
| 167–173 | 松手后 | `reason=ended` 后仍有同一滑条的 `sliderValueChanged` | 结束后仍收到值变事件 |
| 179–181 | 调光后 OFF | `0x8203 / 00 7C` | OFF，TID 124 |
| 195–197 | 没有新的滑条操作记录 | `0x824D / 8F 02 7D` | **额外发送 655，即 App 的 1%，TID 125** |
| 235–237 | 下一次按钮点击，预期重新开灯 | `0x8203 / 00 7E` | **仍为 OFF，TID 126** |
| 253–255 | 再次点击 | `0x8203 / 01 7F` | 真正 ON，TID 127 |
| 271–273 | 再次点击 | `0x8203 / 00 80` | OFF，TID 128 |
| 290–384 | 再次调光 | 1966、34733、34733 | 约 3%、53%、53% |
| 402–420 | OFF 后再次出现同类异常 | OFF，随后 655 | TID 132、133 |
| 436–438 | 下一次点击 | OFF | TID 134 |

两轮均出现“调光 → OFF → 无新拖动却发 1% → 下一次按钮仍发 OFF”。TID 逐次变化，没有日志证据支持把本次问题归为重复 TID。`received from: 0001` 是本 App 源地址的消息记录，并非设备执行成功的状态回复；`Discarding packet` 对应已经处理过的同序号转发包，不能据此认定新 ON 被设备拒绝。日志没有灯具返回的 Generic OnOff / Light Lightness Status。

## 已证实的 App 调用链

1. [CustomDeviceSlider.swift](../SunSmart/Common/View/CustomDeviceSlider.swift) 的 `sliderEndValueChange()` 将 `isSliding` 设为 false 并停止定时器，但 `sliderValueChanged()` 不检查当前是否仍属于有效手势，直接把 `isSliding` 改回 true 并 `startTimer()`。
2. 定时器每 0.3 秒直接读当前 `self.value`，只检查与 `lastSendValue` 是否不同，不区分用户输入与程序刷新。日志中结束后又出现值变事件，正好符合重启条件。
3. [GroupViewController.swift](../SunSmart/Main/Group/Controller/GroupViewController.swift) 的 `onoffBtnClick` 发出 OFF 后调用 `controlPanelView.setBrightnessValue(0)`。
4. [DeviceLightControlPanelView.swift](../SunSmart/Main/Device/View/DeviceLightControlPanelView.swift) 允许配置中的 OFF 显示值为 0，但底层 [BuoySliderView.swift](../SunSmart/Main/Group/View/BuoySliderView.swift) 最终写入 `CustomDeviceSlider.value`。后者按 `limitRange` 夹值；现场范围为 1...100，因此定时器读到 1。
5. 面板的 `suppressCallbacks` 仅覆盖同步 `configure` 过程，不能阻止之后的定时器回调。
6. Group 的 `sendGroupBrightnessValue(1, ended: false)` 先执行 `applyGroupBrightnessValue`，将 `group.lightness`、成员亮度设为 655，将 Group、成员和 `onoffBtn.isSelected` 设为 ON，再发送 655。
7. 下一次按钮按 `sender.isSelected` 取反，于是再次发送 OFF。亮度记忆也从 66%/53% 被覆盖为 1%。

这条因果链不需要假设网关或固件修改了 App 按钮状态。只把按钮改为从 `group.isOn` 取反也无效，因为两者已同时被覆盖。

已运行隔离复现：从当前生产文件抽取 `value`、开始/值变/结束和定时器方法，使用 Foundation Timer 与最小 UISlider/Delegate 替身，主动触发计时回调。结果：

- 正常结束后程序设置 0：定时器已关闭，没有发送回调。
- 结束后补一次 `valueChanged` 再程序设置 0：`isSliding=true`、定时器仍存在，收到 1% 的限流回调。

该复现验证生产方法的事件顺序漏洞，不是 UIKit 真机测试；UIKit 为何产生末尾事件尚未单独验证，不能据此宣称仅 iOS 27 才受影响。

## 真正 ON 仍不亮的解释及未确认部分

TID 120 与 TID 127 都是 `GenericOnOffSetUnacknowledged(true)`，同一个组地址，均未携带过渡时间或延迟。区别在于后者执行前已经下发过 1% 亮度。

Bluetooth Mesh Model 1.1 的 §6.1.2.2.3 与 §6.1.2.3 规定：Default 为 0 时 ON 使用 Last；非零亮度事务完成后更新 Last；Default 非零时 ON 使用 Default。因此，如果该灯具按此规则使用 Last，655 可以成为后续 ON 的恢复值。来源：[Bluetooth SIG Mesh Model](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)。

这能解释持续“看起来没有亮”的一种机制，但日志未提供设备 Actual、Last、Default、Range，也没有实测低亮阈值。不能断言该型号在 1% 必然完全不发光，或固件已进入异常锁定。若修复 App 后真正 ON 仍失败，再对目标灯具单播读取 Generic OnOff、Light Lightness Actual/Last/Default/Range，并记录固件版本、Element/Model 和实际光输出，交由固件团队核对；本任务不修改固件。

## 设备页为何表现不同

两页复用同一控制面板和滑条，设备页不是天然免疫。

- Group 的限流回调既发命令又重写 `group.isOn`、按钮与成员状态；设备详情的 `brightnessThrottleValueChanged` 只负责发送，状态更新在独立 `brightnessValueChanged` 回调。因此程序刷新后的定时采样不会通过同一函数直接将设备页按钮改回 ON。
- 设备详情点击开关使用 `node.isOn`，本地还维护 `trunOffLightness`；Group 详情直接切换按钮状态，没有对应的亮度保存/恢复过程。这里只是本地状态差异，设备详情的 ON 命令也不是直接指定恢复亮度。
- 设备详情使用单播 Model 地址，开关与调光结束请求 ACK；Group 使用组播无 ACK。此差异影响反馈，但无法解释 App 自己在 OFF 后生成 655，故不作为首要修复点。
- 两页亮度范围来源也不同：Group 使用 Profile 的 low/high trim，设备页使用节点 lightnessRange。缺少设备页同操作日志，无法断定那里是否没有迟到事件，或是否有额外亮度包但没有造成同样症状。

## 已确认的修复方案

推荐修复共享滑条的交互与限流生命周期，保持现有 Mesh 开关协议和合法调光范围。

1. 在 `CustomDeviceSlider` 中明确有效交互的开始与结束；结束后的迟到值变不得重新开启会话或定时器。最终回调使用本轮最后有效用户值，结束处理幂等，正常松手保留一次最终提交。
2. 定时发送只消费本轮用户产生的待发送值，不能轮询程序刷新后的 `value` 生成新命令；新一轮拖动重置去重/待发送状态。程序刷新本身不发 Mesh 命令，合法的 1% 调光仍可发送。
3. 正常结束、取消、退出视图均清理定时器和待发送状态。取消是否提交最终值继续遵循现有 `sendsFinalValueOnTouchCancel`，为 true 的上下光比例和 Manual Override Timeout 保留原语义；false 也必须清理，不能遗留定时器。
4. Group/设备详情的显式开关操作若遇到尚未结束的调光会话，应先丢弃旧调光待发送值，再发开关并刷新面板，保证旧调光不能晚于 OFF 执行。必要时由共享控制面板提供轻量取消入口，不在各页面各写一套计时逻辑。
5. 补行为回归，验证两页命令序列与本地状态。保留 `sendGroupBrightnessValue` 对真实用户调光的状态更新，不靠取消该更新掩盖问题，也不把 ON 改成强制 100% 或额外亮度命令。

本次必须覆盖的关联风险：共享滑条的取消清理、退出后残留回调、程序刷新触发命令。分析已核对控制面板的三个使用方（Group、设备详情、HDB Zone），以及滑条在 CCT、上下光比例、校准、Profile 和设备参数中的使用。共享生命周期修复可能改变这些入口的回调次数，尤其“取消时提交”与“仅最终回调”必须保持兼容。

不需要新增持久化字段、迁移云数据或修改 SDK/服务器。修复后对已经落入低亮度状态的现场设备，先由用户主动设置一次明确亮度（例如 50%）再验证 OFF/ON；退出重进或重启 App 不应被视为一定能恢复设备端 Last。若仍失败，再按上述状态读回收窄外部原因。

## 验证与验收

- 自动行为回归：正常拖动、结束后迟到值变、OFF 后等待多个限流周期、连续 OFF/ON、取消两种策略、退出/重进、新手势重复相同值、程序设置/刷新范围、1% 合法输入、上下限非默认值、无用户拖动的面板初始化。
- Group 序列验收：调光最终值只由用户输入决定；OFF 后没有新操作就不得出现 `0x824D`；下一次 ON 必须是 `0x8203` 且参数首字节 `01`；本地开关与最后有效亮度不被刷新回调改写。
- 相关现有检查：CustomDeviceSlider 几何与 Manual Override Timeout 行为测试、上下光比例发送检查；按修改范围选择 HDB 控制回归，不机械执行全仓测试。几何测试不能替代触摸生命周期验证。
- 实施后构建一次实际本地 workspace 的 SunSmart Debug generic iOS；这些共享 Swift 文件被多品牌使用，但不涉及新增资源、target 或依赖时无需机械重复五品牌构建。
- 人工真机：Group 简单/详细模式与设备详情各重复原始序列，调光松手后立即 OFF 及等待后 OFF 各测一次，OFF 后等待至少 1 秒，重复三轮；补取消拖动和退出重进。记录 Mesh 命令及可见灯光，不自动安装/运行设备。
- 分析阶段只完成日志、源码、协议核对与隔离复现；实施阶段结果见末节。设备状态读回与真实运行仍未验证。

## 工作区与交接

- App 分支 `fix/SR-BL2421-MINI-261027`；分析时 HEAD `3d9bcf70`，实施期间工作区已有布局修复被外部提交为 `fbf2667e`。本任务未执行提交操作。
- 本地 workspace 指向 `.local-sdk/nordic-sig-mesh-sdk`，realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；只读核对时 SDK HEAD `e7c1a7f`，工作区无未提交差异。
- 任务开始时已有 `Tests/UI/CustomDeviceSliderGeometryTests.py` 修改；分析过程中还观察到 `CustomDeviceSlider.swift` 新增灰段布局及 DEBUG 日志修改。它们并非本轮写入，已核对不涉及本次复现的事件/定时器方法；后续实施前需重新检查并保留。
- 分析阶段只新增本文档；用户随后确认实施，改动与验证记录如下。

## 已实施与验证结果

实际改动：

- `CustomDeviceSlider` 在被允许的触摸跟踪开始时建立交互，拒绝结束后的迟到值变。定时器消费用户输入快照，不读取后来由程序刷新写入的值；旧计时器即使回调迟到，也不能消费新手势的数据。
- 正常结束先清理，再使用同一快照通知两个最终回调，防止第一个回调刷新 UI 后改变第二个回调的发送值。重复结束不重复提交。
- `touchesCancelled` 和系统 `cancelTracking` 均收尾，取消提交仍遵守原 opt-in 配置；移出 window、释放对象清理定时器。保留 VoiceOver 增减作为完整独立输入，避免有效的非触摸操作被迟到事件保护误拦截。
- 控制面板统一取消简单/详细模式的亮度、CCT 手势；Group/设备详情在显式开关和页面退出时调用。HDB Zone 也在 ON/OFF/Auto 接管及退出时取消，下一次真实调光仍可正常进行。
- 新增 [CustomDeviceSliderInteractionTests.py](../Tests/UI/CustomDeviceSliderInteractionTests.py)，直接抽取生产滑条方法、Group/设备详情控制函数和 HDB 控制函数执行。UIKit、时钟、界面组装和 Mesh 传输使用可观测替身，不等同于真机 UI 或无线执行验收。

验证结果：

| 检查 | 结果与范围 |
| --- | --- |
| 新增交互行为回归 | 92 项检查通过，覆盖迟到事件、快照隔离、取消双策略、系统取消、重入回调、新手势、退出/重进、VoiceOver、释放和三类页面控制接管 |
| 同用例修复前基线 | `--baseline` 在 HEAD `fbf2667e` 重现 `late valueChanged must not emit 1% after OFF`，说明几何修复本身未解决本次生命周期问题 |
| CustomDeviceSliderGeometryTests | 106 项通过；保留已有灰段与几何修复 |
| ProfileManualOverrideTimeoutTests | 2636 项通过；为隔离行为验证 |
| UpDownRatioCommandSchedulerTests | 行为测试通过；检查脚本前面的滑条/发送约束通过 |
| check_up_down_ratio_slider_commands.sh | **整体未通过**：末尾工程静态计数写死 4 个 target（8 处声明/引用），当前工程实际为 6 个 target（12 处）；HEAD 同为 12，属于已有检查过期。本任务未修改工程或该脚本，不能把整条脚本记为通过 |
| HDB control observation / zone control | 两项现有检查通过；没有新增协议或配置行为 |
| git diff --check | 通过 |
| SunSmart 编译 | `SunSmartLocal.xcworkspace` / SunSmart / Debug / iphoneos / generic iOS / `CODE_SIGNING_ALLOWED=NO`，xcodebuild 退出码 0，并确认生成 `SunSmart.app` 可执行文件（最终增量构建 2026-10-27 11:24:27） |

构建使用稳定隔离目录 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-SR-BL2421-MINI-261027-group-control`，避免与同工作树其他任务共用 build.db；没有 clean 或删除共享缓存。输出包含现有依赖/工程告警及一次 CryptoSwift “command failed with exit code 0”诊断，首次构建成功；补充 VoiceOver 回调内刷新快照保护后完成增量构建，退出码 0 且无诊断输出。未为消除此类输出修改依赖。

SDK 保持 `one-dev` / `e7c1a7f` 且无未提交改动。本次未更改 Mesh 命令格式、持久化、正式依赖或品牌配置；共享代码在 SunSmart 代表 target 编译，其他品牌未重复构建。

最短人工验收：先主动调到 50% 以恢复已受影响设备的亮度，再按“OFF → ON → 调光 → OFF → 等待至少 1 秒 → ON”重复三轮。Group 简单/详细模式和设备详情分别检查；预期 OFF 后无新调光包，下一次点击发 ON，灯光恢复正常。另检查取消拖动、退出重进和上下光比例/Timeout 的松手提交。实际灯光、UIKit 事件顺序及 VoiceOver 体验仍待真机确认；若真正 ON 仍失败，继续读取设备 Actual/Last/Default/Range，不能用本次编译替代设备结论。
