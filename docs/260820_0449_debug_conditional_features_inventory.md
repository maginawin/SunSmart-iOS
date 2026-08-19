# App `#if DEBUG` 条件编译功能盘点

## 范围与结论

- 工作树：`sun-smart-worktrees/time-zone-test`
- 盘点范围：`SunSmart/` 下实际生效的 Swift/Objective-C/C 系列条件编译；排除 `Pods/`、`Tests/`、`docs/`，也排除已被注释的 `//#if DEBUG`。
- 共找到 **55 个实际生效的 `DEBUG` 条件入口，分布在 17 个 App 源文件中**。
- 当前源码中，**没有通过实际生效的 `#if DEBUG` 增加用户可见菜单、按钮或页面**。
- 真正会让 Debug 与 Release 产生业务/运行行为差异的主要有 3 类：
  1. App 启动后安装全局 UI 操作跟踪器；
  2. 进入 Space 并完成 Mesh 连接后，额外向一个有日程的节点单播 `TimeSet`；
  3. Mesh OTA 下载固件后，额外清理同 PID、同版本的分发缓存并向分发者发送删除消息。
- 其余命中主要是控制台日志、诊断会话，或当前无实际效果的空调用。

## 会改变运行行为的 Debug-only 功能

### 1. 全局 UI 操作跟踪

- 入口：`SunSmart/AppDelegate/AppDelegate.swift:19`
- Debug 启动时调用 `PJUIDebugConsoleTracer.start()`。
- 跟踪器会：
  - Swizzle `UIViewController.viewDidAppear`，记录进入的页面；
  - Swizzle `UIControl.sendAction`，记录控件事件、目标和 Action；
  - 给 Key Window 安装不拦截触摸的 Tap Gesture，记录点击 View 和 View 层级路径。
- Release 不启动该跟踪器。
- 这是不可见的调试能力，但会改变运行时方法实现和手势识别器集合，并产生大量 `[PJUIDebug]` 控制台日志。

### 2. 有日程设备的额外单播时间同步

- 入口：`SunSmart/Main/Device/Controller/DevicesViewController.swift:261`
- Debug-only 实现：`DevicesViewController.swift:456`
- 触发前提：
  - 进入 Space 后 Mesh 网络连接完成；
  - 当前用户不是 Visitor；
  - 至少一个真实节点存在 `scheduleIds`；
  - App 至少存在一个已启用日程。
- 行为：连接完成约 5 秒后，选取第一个有日程的节点，调用 `MeshAPI.syncNodeTime`，向该节点单播标准 `TimeSet`，并打印结果。
- 与之不同，约 3 秒后的 `.allNodes` 广播 `TimeSet` 已移到 `#if DEBUG` 外，Debug 和 Release 都会执行。
- 因此 Debug 相比 Release 会多一次 Mesh 单播，并可能再次修改一个节点的时间状态。

### 3. Mesh OTA 重复版本分发缓存清理

- 入口：`SunSmart/Main/Firmware/Controller/MeshFirmwareListViewController.swift:413`
- 触发时机：固件详情页下载或导入固件成功，回调更新本地固件数据时。
- 行为：对 PID 与新固件一致、且 `distributionVersion` 也相同的节点：
  - 清空 `distributionFirmwareID`、`distributionFirmwareSize`、`distributionIncomingFirmwareMetadata`；
  - 保存节点属性；
  - 如果节点有 Firmware Distribution Server Model，则发送 `FirmwareDistributionFirmwareDelete`。
- Release 不执行这一清理。它最初用于重复升级同版本测试包，但会真实修改本地缓存并发送 Mesh 删除命令。

## Debug-only 运行配置与诊断

### Mesh 日志与心跳测试配置

- `SpaceViewController.swift:318`
  - Debug 打开 `.network`、`.model`、`.access`、`.lowerTransport`、`.upperTransport`、`.proxy`、`.bearer` 日志；
  - 如果全局常量 `routeTest` 为 `true`，关闭自动 Heartbeat Loop 并切换为 `.publish`；否则使用 `.general`。
  - 当前 `routeTest` 固定为 `false`，所以当前 Debug 与 Release 的心跳行为一致，实际差别只有日志级别。
- `SiteViewController.swift:184`
  - Debug 打开 Site 页面所需的 Mesh 网络、访问层、传输层、Proxy、Bearer 日志。

### Timed 页面日程诊断

- `TimedViewController.swift:85、268、279、289、299、307`
- 页面显示和未知 Scheduler Model 缓存修复期间，打印：
  - App 本地 Schedule 定义；
  - 节点 `schedulerActions`；
  - 每个 Scheduler Setup Model 的条目、未知状态和解码错误；
  - 缓存修复开始、单条失败和最终成功/失败地址。
- 真正的未知缓存修复读取不在 `#if DEBUG` 内，Release 仍会执行；仅诊断输出被过滤。

### Gateway 固件扫描诊断

- 涉及：
  - `SiteViewController.swift:1924、2052`
  - `BleFirmwareUpdateViewController.swift:437、598`
  - `GatewayFirmwareScanDebugLogger.swift:52、111`
- Debug 会建立扫描 Session，记录 Site 候选筛选、Network Key Scope、RSSI 页面匹配和升级资格原因，并输出汇总。
- Release 中 Logger 为 `nil`，但 Gateway 选择、Network Key Scope 解析、RSSI 扫描和升级资格判断本身仍会执行。

## 仅过滤日志、不改变业务流程的区域

| 区域 | 文件 | Debug-only 内容 |
| --- | --- | --- |
| HTTP 请求 | `Common/Network/NetworkLoggerPlugin.swift` | 请求、响应、错误、脱敏 Body 及设备参数诊断 |
| 云同步 | `Common/Cloud/CloudSynchronizationManager.swift` | Operation/Level 描述，以及请求、成功、失败日志 |
| Site/Space 导入 | `Common/Data/ImportData.swift` | Space 数量探针、孤立 Gateway 关联清理结果日志 |
| 日程下发 | `Common/Data/Node+MessageHandles.swift` | Scheduler Set/Delete 原始 Payload 日志 |
| TimeSet 时区 | `Common/Data/SiteTimeSetMessageFactory.swift` | 使用手机时区回退的原因日志 |
| 电池开关订阅 | `Common/Data/MeshNetwork+SunSmart.swift` | 订阅快照、恢复、跳过陈旧目标日志 |
| Space 在线状态 | `Main/Space/Controller/SpaceViewController.swift` | 编辑权限冲突、Heartbeat 启停、Presence 停止日志 |
| 设备恢复 | `Main/Device/Controller/DeviceRestoreViewController.swift` | 延迟任务、过滤 Scene Recall、重试与失败判定日志 |
| Gateway 关联 | `Main/Device/Gateway/Controller/GatewayViewController.swift` | 缺失 AppKey 的 Space ID 日志 |
| Group 延迟同步 | `Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift` | 重试结果和 Sensor Publication 对照日志 |
| Devices 广播 TimeSet | `Main/Device/Controller/DevicesViewController.swift:445` | 无法编码 Mesh 时区时的跳过日志；广播逻辑本身不受 Debug 过滤 |

## 当前没有实际效果的 Debug 条件

- `SiteViewController.swift:255、609、1311、2412` 会在 Debug 调用 `updateAddressData()`。
- `updateAddressData()` 的实现体目前全部被注释，因此这些调用当前没有任何可见或数据效果。

## 容易误认为 Debug-only、但实际不是的功能

### Space 的 `Debug` 菜单

- `SpaceViewController.moreClick()` 会在 `space.canDebug` 为真时显示 `Debug` 菜单并进入 `SpaceDebugViewController`。
- 这段入口没有放在 `#if DEBUG` 中。
- `SpaceData.canDebug` 当前只检查 Space 状态正常且不需要重新验证密码，因此 **Release 也会编译并显示该菜单**。

### 灯具详情页的 Set Proxy、Identify、Reboot 等菜单

- 周围能看到已注释的 `// #if DEBUG` / `// #endif`，但它们不是条件编译指令。
- 这些菜单当前也会进入 Release 构建。

### Check Timed 页面

- 当前 `time-zone-test` 工作树中没有 `CheckTimed` 源目录，也没有实际生效的 `#if DEBUG` 菜单入口。
- 不能把其他工作树的 Debug-only `Check Timed` 功能算入当前 App。

## 完整文件分布

实际生效的 55 个条件入口位于以下 17 个文件：

1. `SunSmart/AppDelegate/AppDelegate.swift`
2. `SunSmart/Common/Cloud/CloudSynchronizationManager.swift`
3. `SunSmart/Common/Data/ImportData.swift`
4. `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
5. `SunSmart/Common/Data/Node+MessageHandles.swift`
6. `SunSmart/Common/Data/SiteTimeSetMessageFactory.swift`
7. `SunSmart/Common/Network/NetworkLoggerPlugin.swift`
8. `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
9. `SunSmart/Main/Device/Controller/DevicesViewController.swift`
10. `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
11. `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
12. `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`
13. `SunSmart/Main/Firmware/Controller/MeshFirmwareListViewController.swift`
14. `SunSmart/Main/Firmware/Model/GatewayFirmwareScanDebugLogger.swift`
15. `SunSmart/Main/Site/Controller/SiteViewController.swift`
16. `SunSmart/Main/Space/Controller/SpaceViewController.swift`
17. `SunSmart/Main/Timed/Controller/TimedViewController.swift`

## 配置说明

- 工程级 Debug 配置定义 `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`。
- Archipelago、SLG Sync Plus、SylSmart 的 Debug xcconfig 也显式包含 `DEBUG`，Release xcconfig 不包含。
- 上述共享源文件被四个品牌 target 引用，因此相关差异原则上影响四个 target 的 Debug/Release 构建，不只 SunSmart。
