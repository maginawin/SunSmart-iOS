# Timed Scheduler 重载后重复同步修复实施计划

> **执行要求：** 按 `superpowers:executing-plans` 在当前会话 Inline Execution；每个行为改动严格执行 `superpowers:test-driven-development` 的 RED → GREEN → REFACTOR，并在完成前执行 `superpowers:verification-before-completion`。

## 目标

落实已确认的方案 A，解决 Scheduler 同步成功后退出 Space、重新进入 Timed 又显示“需要同步”的问题，同时修复已经被旧版本写成空状态的节点：

1. SDK 能兼容读取历史数字地址与新字符串地址格式；
2. 后续统一以四位十六进制字符串保存 Scheduler Model 的 Element Address；
3. 解码损坏时保留原始数据，避免 TimeStatus 等无关保存把原数据覆盖成空数组；
4. 对 per-Model Scheduler 状态未知的节点执行一次权威读取；
5. 只有全部 Scheduler Model 的 Register 与有效 Action 都读取完成后，才把节点视为迁移成功；
6. `needsSync` 继续使用严格的 per-Model 真值，不回退到可能掩盖跨 Model 残留的扁平缓存；
7. DEBUG Log 输出各 Model 的缓存与明确的同步差异原因。

## 实施约束

- App 与本地 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` SDK 同步修改。
- 不改变 Target、Action 与 Profile 的 Owner 规则。
- 不修改用户可见文案，不新增本地化 Key。
- 不修改 Dongle collection Scheduler。
- 不执行 Git commit、merge 或 push。
- 不使用 Simulator；iOS 构建只使用 generic iPhoneOS 与 `CODE_SIGNING_ALLOWED=NO`。
- 构建和自动化测试不能替代真实设备、真实 Mesh 与退出/重进 Space 的生命周期验收。

## Task 1：建立 Scheduler Model 持久化 RED 测试

### 文件

- 新增：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/Standalone/SchedulerModelCachePersistenceTests.swift`
- 新增：`scripts/check_timed_scheduler_persistence.sh`
- 修改：`Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`

### 步骤

1. 新增独立可执行测试，要求同一个 codec 同时支持：
   - 历史 JSON 数字地址；
   - 新 JSON 四位十六进制字符串地址；
   - 小写十六进制字符串；
   - 双 Scheduler Model 容器，其中 Owner 有 entry、非 Owner 是已知空字典；
   - encode → decode 往返后两个 Model 容器和空状态均保留；
   - 非法字符串、非单播地址和错误 JSON 类型明确失败；
   - 新编码结果必须是四位大写十六进制字符串。
2. 扩展源码契约测试，要求数据库加载不再使用静默 `try?`，并保留损坏的原始 blob。
3. 扩展读取契约，要求 `getSchedule(index:nil)` 的完成结果覆盖 Register 及其动态追加的 Action Get。
4. 扩展 App 契约，要求 Timed 页面只对缺少任一 Scheduler Model 状态的节点发起修复读取。
5. 运行新脚本，确认测试因 codec/保护/迁移尚未实现而失败，即 RED。

## Task 2：最小修复 SDK 持久化 codec 与损坏保护

### 文件

- 新增：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/SchedulerModelCachePersistence.swift`
- 修改：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- 修改：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift`

### 步骤

1. 把 `ScheduleModelDataContainer` 移到可独立测试的纯 Foundation 文件。
2. 解码 `elementAddress` 时先接受 `UInt16` 数字，再接受十六进制字符串；两种格式都校验单播地址范围。
3. 编码 `elementAddress` 时统一输出四位大写十六进制字符串。
4. Node 加载 `allSchedulerModelActions` 时改用显式 `do/catch`：
   - 成功时恢复所有 Model 容器，包括已知空 Model；
   - 失败时记录可诊断错误，并暂存原始 blob；
   - 不把损坏状态伪装为已知空状态。
5. `savePropertys()` 在 per-Model 字典仍为空且存在损坏原始 blob 时原样保存该 blob；只有 Scheduler Register/Action 真正建立了 Model 维度后才用新数据替换。
6. 运行持久化测试，确认兼容解码、规范编码、双 Model 往返和损坏保护变为 GREEN。

## Task 3：让权威读取的完成语义覆盖全部 Scheduler Model

### 文件

- 修改：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshScheduleServer.swift`
- 修改：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift`

### 步骤

1. 保留现有“每个 Scheduler Setup Model 发送 Scheduler Get”的逻辑。
2. 收到 Scheduler Status 后，只给来源 Model 追加 Register 中有效 index 的 Scheduler Action Get。
3. 利用同一 `MeshProxyMessageCommand` 队列动态追加消息的现有行为，让最终完成回调包含 Register 与 Action Get。
4. 按 Node 汇总全部相关 Handle：
   - 每个 Scheduler Model 的 Register 成功；
   - Register 声明存在的每个 Action Get 成功；
   - 两项都满足才进入成功列表，否则进入失败列表。
5. Scheduler Status 即使 Register 为空，也在 `allSchedulerModelEntrys[model]` 建立已知空字典并持久化。
6. 保证任一 Model 超时后该 Node 仍保持未知/待修复，而不是误判已同步。
7. 运行读取契约测试，确认完成语义与来源 Model 约束变为 GREEN。

## Task 4：在 Timed 页面执行一次性未知状态修复

### 文件

- 修改：`SunSmart/Main/Timed/Controller/TimedViewController.swift`
- 修改：`SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- 修改：`Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`

### 步骤

1. 定义“需要权威修复”的唯一条件：节点支持 Scheduler Setup Model，且任一 Model 在 `allSchedulerModelEntrys` 中没有字典。
2. Timed 页面出现后：
   - 仅在 Mesh 已连接时处理；
   - 仅选择上述未知节点；
   - 当前页面实例避免并发重复启动；
   - 调用 `MeshAPI.getSchedule(index:nil)`；
   - 完成后重新计算并刷新所有 Schedule 单元格。
3. 成功节点因所有 Model 都已有字典而不再触发读取；失败节点保持未知，下次进入页面可重试。
4. 不写 UserDefaults 式的独立迁移标记，避免“标记完成但设备读取实际失败”；per-Model 数据完整性本身就是迁移真值。
5. 将 `needsSync` 的判断拆成可诊断差异：
   - 非 Target；
   - 不支持 Scheduler；
   - Owner Model 未知；
   - Owner index 缺失；
   - Owner entry 不一致；
   - cleanup Model 未知；
   - cleanup Model 存在残留；
   - 已同步。
6. DEBUG 日志逐 Node、逐 Model 输出 element address、已知/未知状态、已有 index，并输出每条 Schedule 的最终差异原因。
7. 运行 Timed 契约与策略测试，确认迁移触发条件、严格判定及诊断覆盖为 GREEN。

## Task 5：回归与构建验证

### 自动化与静态验证

1. 运行 `scripts/check_timed_scheduler_persistence.sh`。
2. 运行 `scripts/check_timed_scheduler_single_owner.sh`。
3. App 仓库运行 `git diff --check`。
4. SDK 仓库运行 `git diff --check`。
5. 检查两个仓库 `git status --short`，确认没有无关文件被修改。

### iPhoneOS 构建

依次直接运行：

1. `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
2. `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
3. `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
4. `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

### 真机验收矩阵

自动化完成后仍需真实设备验证：

1. 当前 Timed 页面同步标记消失；
2. 退出 Timed 再进入；
3. 退出 Space 再进入；
4. 强制结束 App 再启动；
5. 同一 Scheduler 再次 SAVE 不出现重复的 cleanup/owner 写入；
6. Target 覆盖 Device、Group、Scene；
7. Action 覆盖 Auto/On、Off、Scene Recall；
8. Profile 至少覆盖：
   - proximity/predictive lighting with photocell；
   - daylight harvesting (closed loop)；
   - Manual control；
   - 无 Profile 或其他普通照明 Profile；
9. 16 个 Scene、16 个 Scheduler 容量边界保持正常。

## 完成标准

- 历史数字格式能恢复，不再因类型不匹配丢失 per-Model 缓存；
- 新写入格式稳定、可再次读取；
- 损坏 blob 不被 TimeStatus 等无关保存静默覆盖；
- 未知节点只在需要时执行权威读取，成功后退出/重进不重复读取；
- 任一 Model 读取失败时仍保守显示待同步；
- DEBUG Log 能直接指出具体 Model 与具体差异；
- 两组聚焦测试、两仓静态检查与四品牌 generic iPhoneOS 构建通过；
- 最终报告明确区分自动化/构建通过与真机生命周期是否已验收。
