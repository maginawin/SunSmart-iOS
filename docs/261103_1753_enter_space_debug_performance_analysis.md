# 进入 Space 后 Debug 卡顿与高 CPU：原因及待确认修复方案

日期：2026-11-03。状态：只读分析完成，待用户确认实施。

## 结论

主因是 **Space 同步状态刷新在主线程反复解析完整 Scene 目标**。每台设备检查 Scene 时，解析器为每个目标再次扫描全部设备，并重新生成包含 Device Key 指纹的身份。设备、Scene 目标和多次同步判定的循环相乘，造成大量重复计算。

刷新器已有 4 ms 分片预算，但预算检查发生在整台设备检查结束后，无法打断内部的完整 Scene 解析。这次记录中，Scene 同步判定累计占用主线程 **100.488 CPU 秒，占主线程运行采样的 96.9%**。

另有 `libRPAC.dylib` 的后台回溯、符号查找开销 **92.516 CPU 秒**，放大 Debug 时的总 CPU。应先修 App 重复计算与分片粒度，再通过相同 Debug 条件及诊断开关 A/B 区分两部分收益。

建议本次只修改 App 的 Scene 解析、同步只读上下文及必要分片；复用现有机制，不增加持久化格式，不修改 SDK、固件或服务端。

## 1. 本次证据

输入文件：

- `/Users/maginawin/Desktop/enter space logs.txt`：1,045 行。
- `/Users/maginawin/Desktop/enter space.trace`：Time Profiler，Attached，130.811220 秒。

| 项目 | 结果 |
| --- | --- |
| 设备 / 进程 | iPhone 15，iOS 26.5.2，SunSmart PID 20159 |
| 录制时间 | 17:45:58.902～17:48:09.713，UTC+8 |
| 采样 | 198,128 条，全部 Running，每条 1 ms；未录制等待线程 |
| 全进程累计采样权重 | 198.128 CPU 秒 |
| 主线程累计采样权重 | 103.697 CPU 秒 |
| 15～100 秒区间估算 CPU | 全进程 187.75%，主线程 99.64% |
| Hangs | 58 条：54 Hang、3 Severe Hang、1 Microhang |
| Hangs 累计 / 最长单条 | 101.658 秒 / 2.011 秒 |

Hangs 是多条相邻或接近连续的记录，不能表述成一条 101 秒的 Hang。CPU 百分比用区间内运行采样权重除以墙钟时间估算；CPU 秒可以跨线程累加，不等于单个操作耗时。

完整解析了 XML 的 id/ref 引用。同一函数在一条栈中只计一次；下文包含子调用的权重相互重叠，不能相加。采样数不等于调用次数。

### 与当前源码的对应可靠性

Trace 的 `SunSmart.debug.dylib` UUID 为 `6FEB7E60-5077-3D49-988F-55C9B26FE4C8`，与以下本机产物完全一致：

`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmartLocal-cwtgvqjfdilojfcjnqfddkugnteg/Build/Products/Debug-iphoneos/SunSmart.app/SunSmart.debug.dylib`

产物修改时间为 17:42:40；DerivedData 的 WorkspacePath 指向当前工作树 `SunSmartLocal.xcworkspace`。使用该二进制和 `atos` 核实了刷新器、Scene 同步判定、目标扫描及身份生成的位置。当前 HEAD 为 `f63d8dff4353cae66b31777ca96c06f9ed3a6f11`；匹配 UUID 不代表工作区全部未提交内容与录制二进制完全相同。

当前已有 Space 完整性、恢复、Scene 数据、文案和测试的未提交改动；本轮未修改这些文件。分析期间 `SceneConfigurationRoundTripTests.swift` 也出现外部改动，未触碰。

## 2. 日志与采样的时间对应

日志第 40～42 行：本地和服务端均为 **53 台设备、2 个 Scene、3 个 Group、0 个 Schedule**。

| 日志或采样 | 时间 / 耗时 | 判断 |
| --- | --- | --- |
| spaceInfo JSON 解码，日志 23 | 86.7 ms，main=false | 解码已在后台 |
| Space 导入判断，日志 24～57 | 总计 440.3 ms | 服务端时间戳不更新，跳过应用完整配置 |
| 网络加载，日志 58、104 | 17:46:05.541～05.735，约 194 ms | 已完成 |
| 扩展数据完成，日志 106 | 17:46:05.743 | 随后启动会话和全设备同步状态预热 |
| 首个 Scene 同步判定采样 | 17:46:05.781，相对 6.879 秒 | 紧接进入 Space |
| 最后一个 Scene 同步判定采样 | 17:47:47.532，相对 108.630 秒 | 重负载持续约 102 秒的窗口 |
| 两次日志内 export，日志 109～123 | 59.5 ms、60.6 ms | 不能解释后续约百秒的主要工作量 |

全 trace 中 `SpaceData.update` 包含权重约 0.382 秒、`SpaceData.export` 约 0.598 秒，`print` 约 0.025 秒。日志阶段计时与采样权重的含义不同，但两者都支持把首要修复放在 Scene 同步判定。

日志同时有两次 30 秒代理连接超时，之后更换代理成功。主线程长任务可能拖延连接、定时器和 UI 回调，但当前资料不能证明这两次 BLE 超时完全由卡顿造成；不据此修改连接策略、SDK 或固件。

## 3. 主要计算链及重复来源

进入路径：

`SpaceViewController.setNetworkConnected → loadExtensionData → beginSession / warmUp`

设备页也经 `DeviceLightsViewController.updateUI → NodeSyncStatusRefresh.request(nodes:)` 请求同步状态。共享刷新器合并请求，但目前没有复用内部 Scene 解析结果。

主要采样链：

`NodeSyncStatusRefresh.step → Node.getNeedSyncGroup / getNeedSync → getNodeSyncSceneDatas → SceneTargetResolver.resolve → append → nodes.filter → timedSchedulerIdentity → keyFingerprint / Data.hex / String(format:)`

| 函数 / 路径 | 包含权重 | 意义 |
| --- | ---: | --- |
| `NodeSyncStatusRefresh.step` | 100.728 秒 | 主线程共享刷新器 |
| `Node.getNodeSyncSceneDatas` | 100.488 秒 | 本次首要业务热点 |
| `SceneTargetResolver.resolve(scene:)` | 98.474 秒 | 每个设备的检查都重建 Scene 全量目标 |
| 解析器 `append` | 94.050 秒 | 每个目标再次查找实际 Node |
| `Node.timedSchedulerIdentity` | 88.653 秒 | 在上述扫描中重复生成身份 |
| `SchedulerModelSnapshot.keyFingerprint` | 59.278 秒 | 验证、SHA256 及摘要字符串转换 |
| `Data.hex` | 26.956 秒 | Device Key 等数据的十六进制转换 |

### 3.1 每个目标重新扫描所有设备

[SceneTargetResolver.swift](../SunSmart/Main/Scene/Model/SceneTargetResolver.swift) 的私有 `resolve` 先取得本 Space 的 nodes，随后 `append` 对每个目标执行 `nodes.filter`，逐台生成身份进行比较。

假设空间有 N 台设备、单个 Scene 有 T 个目标，一次解析包含约 N×T 次身份比较。上层再对每台设备、每个 Scene 调用解析器，形成约 N×S×T×N 的重复工作；T 随 N 增长时存在立方级增长因素。短路返回、实际目标数及设备能力会影响现场次数。

传统 Group Scene 同样经过这条解析路径，问题不限于直接选择设备的新 Scene。

### 3.2 同一设备还会多次进入 Scene 判定

[Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift) 中：

- `computeNeedSyncGroup` 开头检查一次 Scene，Profile 检查后又检查一次带 Group 上下文的 Scene。
- `getStandardNeedSync` 开头检查 Scene，随后可能调用显式 Group 的 `getNeedSyncGroup`。
- 刷新器先算 Group 状态，未发现差异时继续算设备状态。

因此，在组内设备无同步差异的路径，一台设备可进入五轮 Scene 检查。现有 `groupNeedsSync` 缓存区分 nil 与显式 Group，符合恢复/待加入组的语义；不能为了提速把二者直接合并。

Trace 中 Scene 判定的互斥上游分区为：刷新器直接算 Group 40.265 秒、设备判定内再算 Group 39.981 秒、设备判定直接查 Scene 20.242 秒。

### 3.3 身份 getter 含有实际计算

[TimedSchedulerBindings.swift](../SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift) 的 `timedSchedulerIdentity` 每次读取都会转 Device Key hex、调用指纹计算，并格式化地址。

[SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift) 的 `keyFingerprint` 对规范化后的字符串做 SHA256，摘要逐字节使用 `String(format:)`。采样显示大量 Foundation 格式化和分配开销。

这里的修复方向是减少重复读取，保留 UUID、地址、Device Key 指纹三者构成的身份校验。不能改成只按地址匹配，也不应改变指纹算法、大小写契约或持久化身份。

### 3.4 现有 4 ms 预算检查位置太外层

[NodeSyncStatusRefresh.swift](../SunSmart/Common/Data/NodeSyncStatusRefresh.swift) 在完整执行 `getNeedSyncGroup` 和 `getNeedSync` 后才检查耗时。内部解析未提供可暂停的处理单元，单节点长计算期间不会让出主线程。

相关页面的 [SpacePageSyncRead.swift](../SunSmart/Common/Data/SpacePageSyncRead.swift) 也在完整单节点检查后判断 deadline，部分初始化直接解析完整 Scene。因此仅修设备列表入口，仍可能在 Scene、Timed 页面重现相同成本。

本次 signpost 导出只有系统 ConditionInducer 事件，没有 App 的 `SyncMainStep` 等事件，不能把每条 Hangs 记录直接当作一个刷新分片，也不能给出现场精确调用次数或分片 P95。

## 4. 只读计数复现与既有测试边界

复用了 `scripts/check_scene_configuration.py` 的生产 resolver 夹具，仅在 `/tmp` 生成副本，对夹具的身份 getter 加计数，不改仓库生产代码或测试。

构造一个 Group，两个 Scene 均包含该 Group，全部节点支持 Scene：

| 节点数 | 解析一个 Scene 的身份读取次数 |
| --- | ---: |
| 10 | 110 |
| 53 | 2,862 |
| 106 | 11,342 |

结果符合 N²+N。53 台、2 个 Scene、每台只检查一轮，即为 **303,372 次**；尚未加入上述一台设备多轮检查。

这是特定夹具的实际计数，用于复现算法增长方式，不是现场调用次数。夹具的身份 getter 使用预置指纹，没有真实 Device Key 编码和 SHA256 成本，因此不把它的执行时间当作手机性能结果。

这也说明现有功能测试通过不能覆盖该性能风险：`SceneTargetTestSupport.swift` 的身份读取很便宜，现有普通断言未约束这类重复工作。

## 5. Debug 的额外 CPU

后台实际采样链为：

`libRPAC.__generateCulledBacktrace_block_invoke_2 → dyld.dladdr → findClosestSymbol`

包含权重 92.516 秒，占全进程累计采样 46.7%，几乎都在符号查找。该成本与主线程 Scene 业务热点分别统计。

当前资料不足以指定是哪一个 Xcode 诊断选项触发了所有回溯；共享 scheme 没有给出完整的实际启动诊断状态，os-log 导出也没有对应文本记录。修复后先保持现有 Debug 条件比较，再单独改变对应运行性能诊断设置做 A/B，记录启动方式与选项。

CPU 改善和真实交互验收必须分别观察。关闭诊断后，即使后台 CPU 下降，主线程重复 Scene 计算仍需消除。

## 6. 建议实施方案（待确认）

### A. Scene 解析建立一次身份索引

调整 `SceneTargetResolver`：每次解析先为当前有效节点建立规范化身份索引，目标匹配改为查索引；组场景展开时复用已经计算的身份。

- 单次 `resolve(scene:)` 与 `resolve(draft:)` 共用同一优化，降低保存、控制、容量检查等直接使用方的相同成本。
- 索引必须保留重复身份的歧义状态；两个节点命中同一完整身份时仍拒绝选取，不能字典覆盖后随便选一台。
- 保留缺失身份、换 Device Key、跨 Space、能力不足、离线新增设备等现有判定。

### B. 接入现有 Space 会话只读缓存

扩展 [NodeSyncReadContext.swift](../SunSmart/Common/Data/NodeSyncReadContext.swift)，复用其现有生命周期和 `memoized` 机制：

- 同一有效上下文内，每个节点身份计算一次，每个 Scene 解析一次；缓存解析失败的明确状态，避免每台设备重试，不能当成成功空场景。
- 提供按节点查询的 Scene 写入目标，并复用同一版本的差异判断，减少多轮 `getNodeSyncSceneDatas` 重算。
- 设备、Group、Scene 列表/详情及引用 Scene 的 Timed 读取共用此上下文。Group 参数、待删除关系和额外灯光字段继续采用现有完整语义。
- 使用现有 network 对象、networkID、account/region、数据库 revision、节点状态 generation、保护 generation 失效；不是只按 Scene number 或云时间戳缓存。
- 配置编辑/导入、Group 成员变化、设备替换、ACK 更新、失败回滚、退出重进和跨 Space 时，旧结果不得发布。实施时定向核对这些写入是否触发已有失效入口，缺失的仅补必要入口。

`SceneCommandBuilder`、保存预检、发送及 ACK 的 `SceneMessageContext.matches` 继续获取当前有效配置并校验身份/权限；UI 会话缓存不替代操作时授权和旧回执拦截。操作路径可受益于 A 的索引优化，但不延长快照有效期。

### C. 让 Scene 准备真正服从主线程预算

优先扩展现有 `prepareSlice` 流程，按节点采集身份，按 Scene 目标增量准备，循环中检查 deadline；节点差异判断读取已准备结果。

- 防止把百秒重复计算变成一次仍很长的首轮缓存初始化。
- 保留现有取消、失败与 generation 校验；切页取消单个 owner，关闭 Space 结束会话。
- 如确需后台纯计算，只传不可变的已采集输入；不直接把现有访问可变 Node/Group/数据库的整条函数放进 global queue。
- 复用 `AppPerformance` 的 `SyncMainStep`、`SyncNodeCheck`、`SyncBatch`，必要时增加身份/Scene 解析的汇总计数，不输出密钥或逐节点高频日志。

### 范围与复用选择

| 选择 | 评估 |
| --- | --- |
| 只关闭日志/诊断 | 能区分诊断开销，不能解决已采到的主线程业务计算 |
| 仅优化 hex 或 SHA256 常数成本 | 仍保留嵌套扫描和重复解析，收益边界不足 |
| 只加一次 resolver 内索引 | 必须做，且惠及所有调用方；仍需消除逐设备重复解析 |
| 扩展现有只读上下文及分片 | 推荐；已有会话、共享请求、取消和失效机制 |
| 新增永久全局缓存或独立后台服务 | 本次没有必要，会增加失效和可变对象并发风险 |

预计生产改动集中在 `SceneTargetResolver.swift`、`NodeSyncReadContext.swift`、`Node+SyncData.swift`，以及为分片接入所需的 `NodeSyncStatusRefresh.swift` / `SpacePageSyncRead.swift`。具体接口以实施时最小完整方案为准。

这些是五品牌共享 App 逻辑。预计不涉及文案、资源、target 配置、数据库升级、协议或 SDK API。现有本地 workspace 映射到 `one-dev`，SDK HEAD 为 `dbcf6f1a7014320331f3cccdc0a46edc1a0baa88` 且有其他任务未提交改动，本方案不修改 SDK。

## 7. 验证与结束条件

自动化优先扩展现有夹具和回归：

1. **增长量**：53 台与 500 台，Group/Device Scene 均覆盖；断言单次 resolver 身份生成随节点数增长，同一有效上下文的 Scene 解析次数随 Scene 数增长，不随检查节点数重复增长。
2. **语义一致**：合法旧 Group Scene、空 Scene/空 Group、直接设备 Scene、重复/缺失身份、设备更换密钥、能力差异、exitFailure、pending write/remove、Scene 删除与 Timed 引用；保留完整 Group 附加参数。
3. **生命周期**：共享读者、取消/退出、跨 Space、配置/成员变化、ACK 成功和持久化失败回滚、保护或 revision 失效、过期结果禁止发布；nil Group 与显式恢复 Group 不能误用同一差异结果。
4. **构建**：改动完成后使用映射核实过的 `SunSmartLocal.xcworkspace` 构建一次 SunSmart Debug generic iOS，关闭签名。若实现引入新的跨品牌配置/编译差异，再扩大品牌覆盖；不使用 Simulator。

用户真机验收：保持同一 Space、53 台设备、同一 Debug 启动设置，重新录制进入后相同长度的 trace，比较进入到可交互时间、主线程/总 CPU 权重、Hangs 和刷新完成时间，再切换 Main/Groups/Scene/Timed 并检查同步提示。

验收目标是消除这次约百秒的 Scene 重复计算；新增 Scene 准备分片不得产生 >250 ms 的长阻塞，检查 `SyncMainStep` 的实际分布及预算超支，并确认首次/再次进入和配置更新后的同步状态正确。目标是否达成必须由新 trace 证明，当前不承诺具体倍数或时间。

`SUNSMART_PERFORMANCE` 可启用已有埋点；本次没有这些 App 事件，因此实施后应补齐。再单独进行 Debug 诊断 A/B，避免把回溯开销变化全部算成业务修复收益。

## 8. 本轮交付边界

已完成日志对齐、完整采样聚合、Hangs 分析、匹配二进制符号定位、关联调用方和缓存失效机制核对，以及临时计数复现。未修改业务代码/SDK，未运行 App 构建、未安装或操作真机。

分析中间产物位于 `/tmp/enter-space-*.xml`、`/tmp/enter-space-samples.pkl`、`/tmp/enter-space-summary.json`、`/tmp/analyze_enter_space.py`、`/tmp/probe_scene_resolution_counts.py`；原始 log/trace 为依据。Thermal 表导出返回 Missing features，未据此判断温度状态。

待确认：按 A+B+C 实施 App 修复，并执行上述自动化与构建；真实设备与最终体验由用户验收。
