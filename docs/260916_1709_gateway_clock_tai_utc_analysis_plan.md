# 网关重启后 Off by +36s：分析与修复记录

日期：2026-09-16。状态：用户已确认实施，App 与本机 SDK 修复已落地，定向验证及跨品牌编译结果见文末。RTC/联网校时和真实日程执行仍待人工验收。

## 结论与证据边界

1. 高度怀疑是 TAI/UTC 时间语义不一致在网关重启后暴露，不能仅凭 UI 的 `+36s` 确定固件内部原因。
2. 已确认 SDK 发出的时间使用 `Unix seconds - 946684800`，同时设置 `taiDelta=0`。这个组合在按零差值解释时内部自洽，但不是当前真实的 TAI 时间。
3. 已确认 App 读回时丢弃 `TimeStatus.time.taiDelta`：网关详情 Off by、网关 Information、灯具 Information，以及恢复校时后的验证都直接把 seconds 加上 epoch 当作 UTC。这对真正按 TAI 回报的设备会产生错误。
4. 应同时修复公共时间发送和读回转换，不能只在网关 UI 减去 36，也不能只修固件。设备同步日期时间接口属于同一修复范围。
5. 用户补充：所有网关都有此问题，网关可以访问互联网校时。这支持公共链路问题，不宜按单一网关型号打补丁；但“能够联网校时”还不能证明本次偏差出现前已完成网络校时。
6. 还没有现场 TimeStatus 原始报文、固件实现或重启日志。RTC 恢复、启动默认 delta、联网自动校时哪一个改变了返回值，尚未证实。

## 环境基线

- App 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix-gateway`。
- App 分支/HEAD：`fix-gateway` / `6430f8ec9cf75f1a85b08e297f215bbd14356dd2`。
- 开始时已有未跟踪文档 `docs/260916_1704_site_empty_spaces_gateway_status_plan.md`，本任务未修改。
- 本机 workspace：`SunSmartLocal.xcworkspace`；其 `.local-sdk/nordic-sig-mesh-sdk` 正确链接到 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK 分支/HEAD：`one-dev` / `a6246b1b0409824a3227a9c7cad8140219feb182`，调查时无未提交差异。
- 正式工程仍引用远端 `release`；当前正式 `Package.resolved` 的 SDK revision 与上述本机 HEAD 相同。

## 协议与 +36s 的解释

Bluetooth Mesh 的 Time 消息包含 TAI seconds、subsecond、TAI-UTC delta 和时区。当前有效的 TAI−UTC 差值为 37 秒；36 秒是 2015-07-01 至 2017-01-01 之前的历史差值。依据：[Bluetooth Mesh Model 1.1 §5.1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)、[IERS 闰秒表（更新至 2026 年 7 月 Bulletin 72）](https://hpiers.obspm.fr/iers/bul/bulc/Leap_Second.dat)。

普通时刻（不在插入闰秒本身）应采用：

- 发送：`TAI seconds + subsecond / 256 = Unix seconds - 946684800 + delta`。
- 读取：`Unix seconds = TAI seconds + subsecond / 256 + 946684800 - 报文中的 delta`。
- 得到 UTC Date 后再应用时区；delta 和时区是两个独立量。
- Mesh delta 的 15-bit 编码带 255 的偏置：物理差值 37 编为 `0x0124`；SDK 的 `taiDelta` 属性是解码后的物理秒数，调用方应传 37，不应传 292。既有 marshal/unmarshal 已处理此偏置。

当前现象可以由下面的链条解释，但重启部分仍是假设：

1. App 发送 UTC 起算秒数和 `delta=0`。
2. 网关立即沿用或回报这组值，App 又按零差值读回，因此 Off by 约为 0；这不证明其 TAI 值符合真实时间标准。
3. 重启后，网关从 RTC 或其他来源重新生成时间，并恢复了非零 delta 对应的 TAI seconds。
4. App 忽略 delta，把 TAI 当 UTC 显示，出现约 +37 秒的偏差。

为什么可能显示 +36 而不是 +37：

| 可能情况 | 当前 App 表现 | 需要的证据 |
| --- | --- | --- |
| 回报正确 delta=37，样本到比较时约过去 1 秒 | +36s | 收发/接收时刻、subsecond、原始 TimeStatus |
| 固件使用历史 delta=36，seconds 也相应按 36 生成 | +36s | 重启后报文字段与固件常量 |
| seconds 和 delta 不成对，或 RTC/联网来源之间发生真实跳变 | 可为 +36s | 校时前、校时后、重启后同组样本及固件路径 |

代码是在主线程回调中用 `Date()` 与设备样本比较，再四舍五入到整数秒，故响应延迟和取整确实会影响 1 秒附近的显示。它不能单独证明上述任一固件假设。

如果修正为按报文 delta 转换后仍稳定差 36 秒，剩余问题就是报文字段不一致或设备实际时间有误，需继续修固件；不能通过固定补偿或扩大成功阈值掩盖。

## 源码定位

以下 SDK 路径相对于上述 `one-dev` 根目录。

| 位置 | 当前行为 / 影响 |
| --- | --- |
| SDK `MeshLib/Message/ExplicitTimeSetInput.swift`（位于 `Sources/NordicSigMeshSDK/` 下） | `make` 仅减 UTC 2000 epoch，未加入 delta |
| SDK `MeshLib/Node/Node+Messages.swift` | `Node.setLocalTimeMessage(input:)` 固定 `taiDelta: 0`；无参、有参和动态 handle 汇合于此 |
| SDK `MeshLib/MeshAPI.swift` | `syncNodeTime` 两个重载最终调用公共 Node factory，单播和组播/广播均受影响 |
| SDK `nRFMeshProvision/Mesh Messages/TimeMessage.swift` | 已有 `TaiTime.taiDelta` 和正确的 255 编码偏置，无需重写协议位布局 |
| [GatewayDetailClockCoordinator.swift](../SunSmart/Main/Device/Gateway/Model/GatewayDetailClockCoordinator.swift) | sample 没有 delta；`offBySeconds`、`isDisplayable` 未减 delta；sync 后已有独立 TimeGet 验证 |
| [InformationClockRecovery.swift](../SunSmart/Main/Device/InformationClockRecovery.swift) | sample 没有 delta；`matches` 的 30 秒验证未减 delta；恢复和回读共用这条路径 |
| [GatewayTimeInformationCoordinator.swift](../SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift) | formatter 直接 seconds + epoch |
| [LightTimeInformationCoordinator.swift](../SunSmart/Main/Device/Lights/Model/LightTimeInformationCoordinator.swift) | 复用上述 formatter，同样受影响 |
| [SiteTimeSetMessageFactory.swift](../SunSmart/Common/Data/SiteTimeSetMessageFactory.swift) | 负责 Site 时区，最终调用 SDK Node factory；应继续复用 |
| [GatewayTimeSyncCoordinator.swift](../SunSmart/Main/Site/Model/GatewayTimeSyncCoordinator.swift) | 同样用 Node factory；目前成功判断只有 seconds > 0 与目标 offset 相同，没有判断实际时间差 |

已确认的发送入口包括：网关详情 Sync clock、Site 网关同步、快速添加网关初始化、设备配置时间同步、日程同步前校时、采集日程校时、设备列表广播校时、网关/灯具 Information 缺时间后的恢复，以及 SDK `MeshAPI.syncNodeTime`。这些入口应通过同一 SDK 修复获得一致的编码，而非分别加 37。

## 已确认实施方案

### 1. 补最小现场诊断，并固定失败样例

- 在公共 TimeSet 生成/发送边界及相关 TimeStatus 接收处添加低频 DEBUG 日志：操作类型、节点地址、seconds、subsecond、已解码 delta、时区、手机时间、收发单调时钟以及转换后的误差。必要时只记录 Time 消息的 10 字节参数，不记录网络密钥或凭据。
- 采集三组状态：同步前、同步后的最终 TimeGet、断电重启后尚未再次 Sync clock 的 TimeGet。
- 用户已确认所有网关都有问题且可以访问互联网校时。验收应区分离线重启与联网恢复：在可控的现场网络下保留 BLE 读取，先读取 RTC 恢复结果，再恢复网络并读取联网校时后的 TimeGet；若难以隔离网络，至少按启动时序记录时间状态及已有联网校时日志。
- 在收到现场样本前，可以修复已证实的公共编码/转换问题并做自动化验证；不要把设备兼容性、RTC 或实际日程执行写成已通过。

### 2. SDK 统一处理 UTC ↔ TAI

- 在既有时间模块中增加小型共享转换能力，发送端和 App 读取端使用同一套规则，不在各页面散布常量。
- 发送端按 Date 解析当时的 TAI−UTC delta，成对生成 seconds 与 delta。当前日期采用 37；对 SDK 支持的 2000 年及之后日期，使用带生效时间和来源说明的小型表（32、33、34、35、36、37）。未来闰秒公告通过维护该表处理，本轮不引入联网时间服务。
- 扩展 `ExplicitTimeSetInput` 携带 delta；`Node.setLocalTimeMessage` 使用 input 的值，保持 `MeshAPI.syncNodeTime` 既有调用方式。
- 保留动态 messageProvider 在真正发送/重试时获取 Date 的机制，不能把时间重新冻结在任务创建时。
- 读取转换必须使用报文自己的 delta，不能一律减当前 37；保留 seconds=0 的 unknown 语义和合法短 TimeStatus。
- 明确 UInt64 秒数与有符号 delta 的运算边界、有效日期和 subsecond 精度。Foundation Date 不表示闰秒的 `23:59:60`，本轮不增加未来 Delta Set 调度或闰秒瞬间的日程机制。

### 3. App 完整传递样本并修正展示/验证

- 网关详情与 Information sample 显式携带 delta；从 TimeStatus 构建 sample 时不得遗漏。
- 网关 Off by、展示范围检查、网关/灯具 Information 日期与恢复后的时间校验均使用统一 UTC 转换结果。
- 继续保持已确认的 Off by 产品语义：Gateway 墙钟减去目标 Site 墙钟，时区差仍体现在 Off by，不能只比较绝对 UTC 而丢失此语义。
- 继续使用现有 TimeSet → TimeGet 的详情页/Information 恢复验证，不增加无关重试或扩大 30 秒阈值。
- Site 网关同步的 typed TimeStatus 成功判断补充基于 delta 的实际时间检查，避免只有时区一致就认定校时成功；复用现有响应，不为此另建同步流程。
- SDK 修复覆盖单设备/广播和其他设备时间同步接口；广播无逐设备确认的现有性质不变，不能据此声明所有设备实际校准成功。

### 4. 兼容旧设备和历史数据

- 新读取规则可以同时正确显示“旧 App 写入的 seconds/delta=0 配对”和“标准 TAI seconds/delta=37 配对”。不能把收到的 delta=0 自动替换成 37，也不能根据 UI 误差猜测协议版本。
- 若旧固件忽略 delta，只把收到的 seconds 当作 UTC，新标准写入可能令日程偏移约 37 秒。全设备发布前必须以代表固件验证。只有确有型号/版本证据时才考虑明确的兼容分支，不能由一个异常样本推导全部设备行为。
- 保持 `node.timestamp` 为原始 Mesh seconds，不暗改成 Unix seconds 或扣除 delta 后的值，以免破坏 SDK 回调、缓存保护、导入导出和现有字段含义。
- 当前数据库和云端 Node JSON 只保存 timestamp/offset，没有 delta；不批量加减旧 timestamp。此次运行中的页面使用新获取的完整样本，避免从不完整历史缓存推算日期。
- 本轮不默认扩展数据库或云端字段。如云端或其他客户端需要把持久化 timestamp 渲染成时间，应先确认消费者语义，再单独约定补充 delta/版本字段；仅有历史 timestamp 不能可靠推断其来源。
- 旧版 App 仍可能下发旧格式，也可能误显新版设备时间，发布验收需考虑不同 App 版本并存。

### 5. 验证与发布

自动化验证重点：

- 协议已知向量：UTC `2017-06-27 15:30:00` 对应 TAI `0x20E5369D`、delta=37；编解码成对正确。
- delta=0、36、37 的有效配对均能还原相同 UTC；seconds 错而 delta 未对应变化时保留真实误差，不得“自动归零”。
- SDK 支持范围内的历史 delta 生效边界、subsecond、unknown/无效状态、日期边界及正负/半小时/45 分钟时区。
- 动态 provider 在重试时更新 Date，并保持 Site 时区；修正现有测试中把 UTC-2000 当作 TAI 的预期值。
- 网关详情、网关 Information、灯具 Information、恢复后回读、Site 同步的正常和失败路径。
- 复用 `check_explicit_time_set_dynamic_provider.sh`、`check_site_timeset_message_factory.sh`、`check_site_timeset_call_sites.sh`、`check_light_information_time.sh`（已包含网关时间检查）、`check_timed_schedule_time_sync.sh` 及相关 Site 网关检查。源码 contract 只能验证接线，不能替代协议行为样例和设备验收。

编译：开发阶段使用正确映射的 `SunSmartLocal.xcworkspace`，SunSmart Debug generic iOS、关闭签名，稳定 DerivedData。本次涉及共享 SDK 公共时间能力，合入前覆盖五个受影响品牌的 Debug 编译；不使用 Simulator，不默认额外构建 Release。

人工设备验收最短流程：

1. 网关 Sync clock，确认最终读回接近手机时间，保存 DEBUG 时间样本。
2. 断电重启，重新进入详情，在再次手动校时前读取；应无固定 36/37 秒跳变，允许真实传输误差。
3. 检查网关和一台代表灯具的 Information 日期与公共同步接口结果。
4. 设置一个近期执行的日程，确认校时后以及网关重启后按正确墙钟触发。
5. 若支持联网校时，比较联网前后样本；覆盖实际支持的旧固件代表版本。

由用户完成真机/最终体验验收，除非另行明确授权。若固件启动后返回不自洽的 seconds/delta，则需要固件修复 RTC 还原、delta 持久化或联网转换；App 不通过猜测报文含义代偿。

SDK 发布：记录修复后的 SDK revision，发布到既有正式 `release` 依赖并更新解析结果后再做正式入口验证；本机 workspace 编译成功不能替代远端发布。

## 初始分析阶段记录

- 已完成工作树、实际入口、SDK realpath/revision、发送/读取链路、缓存/导出字段及现有测试预期的只读核对。
- 已用独立数值算例复核协议向量：当前公式得到 `0x20E53678`，标准值为 `0x20E5369D`，相差 37；标准样本延迟 1 秒可令旧公式显示 +36，按 delta 转换后为 −1。
- 该算例仅验证数学关系，不是 App 自动化测试或固件运行证据。
- 未执行 App/SDK 构建、真机测试或业务代码修改；符合本轮“分析并规划，与用户确认”的范围。
- 下一步：用户确认后，按“公共 SDK 发送 + App 读回/验证 + 定向诊断与兼容回归”实施，收到固件信息和现场样本后补齐重启的确切原因。
- 结束检查时工作树新增了 `SiteViewController.swift`、`SiteGatewayHeaderLayoutPolicy.swift` 及两个 Site Header/OnlineState 测试文件的未提交修改；这些不是本任务写入，本任务未改动或回退它们。后续实施前重新确认写入所有权和差异。


## 实施记录（2026-09-16）

实施开始时 App 已包含 Site 空 Space 页面修复，HEAD 更新为 `999be5fa13c968095431144ad9e1793aaf92edea`；SDK 仍为 `one-dev` / `a6246b1b0409824a3227a9c7cad8140219feb182`。本次只修改时间相关代码、定向回归脚本与本文档。

### 已落地的行为

- SDK 新增 `MeshTimeConversion`，按 IERS 生效边界处理 2000 年起的 UTC → TAI，读取时使用报文自身的 delta；拒绝 unknown、超出 40-bit seconds 和超出协议 delta 范围的输入。
- `ExplicitTimeSetInput` 同时携带 seconds/subsecond/delta；公共 `Node.setLocalTimeMessage` 通过 `TimeSet(input:)` 成对编码，覆盖所有既有公共同步接口。动态 provider 仍在每次发送/重试时刷新 Date 和 delta。
- 网关详情、网关/灯具 Information、恢复后的校时验证均保留并使用 delta。Site 网关同步在时区校验之外验证换算后的 UTC 与回调接收时刻相差不超过既有的 30 秒范围。
- 数据库、云端 JSON、`node.timestamp` 的原始 Mesh seconds 语义不变；未做历史数据迁移，也未根据 36/37 秒误差猜测固件版本。
- SDK DEBUG 收发回调增加 `[MeshClock]` 日志，输出 TimeSet/TimeGet/TimeStatus、地址、手机 Unix 时间、单调时钟、TAI/subsecond/delta/时区和换算后的 UTC 误差。`parameters` 为已解码时间样本重新编码的参数，unknown 短报文不应据此推断原始报文长度。不包含密钥，不在 UI tick 中打印。

### 已验证

- SDK `check_explicit_time_set_dynamic_provider.sh`：动态 provider、显式输入以及真实 TimeSet/TimeStatus/bit codec 编解码测试通过。覆盖官方向量、delta=0/36/37、历史生效边界、子秒、时区、unknown/非法输入和 signed delta 边界。
- App `check_light_information_time.sh`（含网关详情/Information/恢复相关检查）：通过。
- App `check_site_timeset_message_factory.sh`、`check_site_timeset_call_sites.sh`、`check_timed_schedule_time_sync.sh`：通过。
- Site `GatewayTimeSyncCoordinatorTests`：通过，含 delta 转换后的成功、真实时间错误、无效样本和既有生命周期路径。
- `check_site_sync_gateways.sh` 的时间协调器及此前其他测试通过；脚本最终在已有的 `SiteEntryTimeZoneSyncContractTests` 四品牌数量断言处停止。断言要求 `SiteEntryTimeZoneSyncOverlay.swift in Sources` 出现 8 次，而当前五品牌工程出现 10 次；HEAD 与工作区工程文件完全相同，失败不由本次修改引入。未顺手调整无关测试，整个 Site 脚本不能标记为通过。
- SDK/CoreBluetooth 真实 codec 测试首次被沙箱模块缓存权限阻止；授权后原命令成功。无需修改业务代码绕过环境。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 scheme 的 Debug / generic iOS 编译均通过（各命令退出码 0）。关闭签名，使用正确映射的 `SunSmartLocal.xcworkspace` 与固定 `DerivedData/SunSmart-fix-gateway`，串行执行；未构建 Simulator 或 Release。输出包含现有弃用 API、重复资源等警告，未修改这些无关项。
- App 与 SDK `git diff --check` 通过。没有以编译或隔离测试代替真机验收。
- 后续按用户要求删除四个 App 文件顶部新增的重复条件导入，保留各文件原有的 SDK 导入和测试隔离结构；时间逻辑及 SDK 未改变。清理后重新运行网关/灯具时间回归、`GatewayTimeSyncCoordinatorTests` 和 SunSmart Debug generic iOS 编译，均通过。

### 交付与待办

- App 和 SDK 修改均保留在工作区，未提交或发布。SDK 需要基于上述 revision 的本次未提交差异；正式远端 `release` 与 `Package.resolved` 尚未包含新 `MeshTimeConversion` / `TimeSet(input:)` API，使用本机 `SunSmartLocal.xcworkspace` 开发验证。
- 生产依赖发布时先发布 SDK 修复，再更新正式解析结果并核对正式 workspace；不要仅提交 App 而遗漏 SDK。
- 人工复测：Sync clock → 断电重启 → 再次进入读取（先不要重新 Sync clock），比较联网前后 `[MeshClock] rx TimeStatus` 的 delta/UTC 误差；再核对灯具 Information 和一次近期日程实际触发。测试构建对应本文件记录的 App/SDK 工作区差异。
- 没有安装或运行真机。当前证据可以证明转换/校验与编译结果，不能确认具体固件 RTC/网络转换实现，也不能替代旧固件与真实日程兼容验收。
