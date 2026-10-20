# HDB Sensor Server preparation 开发方案与实施记录

日期：2026-10-21。状态：已按用户调整实施，相关回归与 App 构建通过，真机待用户重置重加后验收。

## 已确认范围

用户确认实施，并作出两项调整：类型未识别完整时不因 HDB Publication 保持待同步，不猜测 element，不生成 Publication 配置任务；不兼容旧设备，由用户重置后重新添加。

因此取消原方案中的主动补发现/等待流程、旧 Ambient 发布清理和旧初始化签名迁移。本次仅调整 HDB preparation 的目标选择与接收订阅条件，沿用标准入网完成后进入 HDB preparation 的时序，不修改普通 Site/Profile、SDK、固件或服务器。

## 当前实现

| 条件 | sensorGroupId | LC 接收订阅 | Publication |
| --- | --- | --- | --- |
| 无 SIG Sensor Server（0x1100） | 不新增 | 不新增自身 Sensor 订阅 | 不新增 |
| 有 0x1100，属性映射完整且唯一匹配 0x004D | 分配或复用 | 订阅本设备 sensorGroupId | 仅匹配实例发布到该地址 |
| 有 0x1100，属性映射完整但没有 0x004D | 分配或复用 | 同样保留 | 不生成任务 |
| 有 0x1100，但任一 Sensor 属性缺失或为 0 | 分配或复用 | 同样保留 | 不生成任务；不额外产生 HDB Publication 待同步 |
| 完整映射中有多个 0x004D | 保留地址 | 保留已有配置 | 拒绝歧义，不任意选择 |

`HDBDeviceSyncContext` 从当前 composition 的 SIG 0x1100 实例检查 `sensorModelTypes`，忽略旧的 Presence/Ambient convenience getter 缓存。目标 element 来自当前 composition，未硬编码 element 0 或 LC element。

`hasSensor` 改为基于 composition；既有 `prepareIntent` 因而会为只有光照、能耗或尚未识别类型的 Sensor Server 分配 sensorGroupId。`HDBDevicePreparationPolicy` 在有 Sensor Server 时要求分配地址，并独立生成 LC subscriptionTargets，不再由 Publication 目标是否为空决定接收订阅。

已有 `zoneSensorTargets` 通过同一 hasSensor 条件保留 LC 及同 element 共享订阅模型的 sensorGroupId；FEFD 与 Zone 的既有重写顺序保持。地址唯一性、保存失败恢复、删除回收、ACK 和 Node 持久化继续复用原机制。

Publication 的 AppKey、TTL=0xFF、period/retransmit disabled 未改变；消息发往节点主地址，payload 指定被选中的 Sensor element。Ambient 0x004E 和能耗 0x0072 不生成发布任务。

## 明确的边界

- “未知属性不保持待同步”落实在 HDB preparation/Publication 判定。SDK 标准入网仍有其原有 `isKeybindComplete` 检查（包含属性条目数量）；本次没有放宽标准入网条件，也没有新增属性发现或等待任务。因此未完成标准入网的设备仍可能由标准流程报未完成，不能把 HDB 的跳过策略等同于放行全部入网失败。
- 当前 SDK 的 Descriptor 只保留首个属性，重复 Property 映射也有限制；本次不新增对单 Server 多 Property 的通用支持。只有当前属性映射完整且唯一匹配时才发布。
- 由用户重置后重新添加验收。不新增旧设备清理、签名升级或旧 Force 状态迁移；现有签名机制保持原行为。
- 如果之后获得新的属性映射，后续任务会按届时证据重新计算；执行期间目标变化仍受既有任务身份检查保护，不接受旧目标回执。
- 原现场样本为 element 0/0008=004D、element 1/0009=004E、element 2/000A=0072，LC 在 element 2；按本实现只配置 0008/1100 Publication。这不能单独证明之前自身感应不触发的问题已经解决。

## 代码与基线

App 分支 `feat/HDB-261020`，HEAD `355632ee`。本轮仅修改两个生产文件：

- `SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift`
- `SunSmart/Common/Data/HDBDevicePreparationPolicy.swift`

同步扩展现有 HDB tests 与边界夹具，使 Sensor 类型能真实表达缺失、0、004D、004E、0072；Publication 夹具包含 element 地址，支持错误 element 回执验证。没有新增测试工程、用户文案、资源或依赖。

两个生产文件属于五品牌共享代码，无品牌独立编译路径。本次代表构建使用 SunSmart。

实际 workspace：`SunSmartLocal.xcworkspace`；SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `8c5af55`，本轮未修改 SDK。固定 DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020`。

## 验证记录

已通过：

- `python3 scripts/check_hdb_device_preparation.py`：策略测试及 device-sync、device-tasks、add-completion、add-execution、subelement 五项集成模式。
- `python3 scripts/check_hdb_integration.py`：Store/Service/Executor、共享订阅、空 Zone、失败持久化及迟到回执。
- `python3 scripts/check_hdb_lighting_configuration_service.py`：控制入口准备状态、绑定、取消/重入和发送失败。
- `git diff --check`。

新增行为覆盖：Presence 位于主/非主 element；三个 Sensor 分属 004D/004E/0072；Ambient-only/Energy-only；缺映射/0/部分映射；过期 convenience getter；多个 004D；Vendor 0x1100 不视作 SIG Sensor；错误 element 回执拒绝后重试；添加完成只有一个 Publication；无 Presence 仍分配地址和保留 LC 接收订阅。

这些测试使用生产 HDB 代码、部分真实 SDK readiness getter及数据库/无线边界替身。未知属性用例分别断言 HDB 不增加待同步和 SDK 标准检查仍保留，未把两者混为同一验收结论。

App 构建：SunSmartLocal / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO，退出码 0。出现既有页面中的 weak/implicit-strong-capture 警告，本轮未扩展修复。未自动安装或运行真机，未做服务器联调。

## 最短人工验收

1. 重置设备后，用新 App 在 HDB Site 重新添加。
2. 检查 sensorGroupId 已分配；回读唯一 004D 所在 element 的 Sensor Server Publication，目标应为该 sensorGroupId；004E/0072 不应由此次 preparation 新配置 Publication。
3. 检查 LC 接收订阅保留 sensorGroupId，以及需要的 FEFD；编辑为空或非空 Zones 后仍保留。
4. 执行 Auto 并观察人体感应从 Dim 返回 Bright；此项需要真实设备，不能由编译或隔离回归代替。
