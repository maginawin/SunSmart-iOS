# App 日志仅在 Debug 构建中输出

## 原因与范围

普通 Swift `print` 不会因为 Release 优化而自动停止输出，`debugPrint` 的名称也不代表它只在 Debug 构建中执行。需要通过编译条件排除日志。参考 [Swift 条件编译说明](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/statements/)。

本次对 `trigger-zone-sep` 的 `SunSmart/` 全部 Swift 源码进行语法扫描，包含项目内维护的 Thirdparty 源码，排除注释中的打印。共发现 215 处有效打印调用：原有 56 处直接受 `#if DEBUG` 保护，本次补齐其余 159 处，共修改 51 个 Swift 文件。未发现该目录 Objective-C 源码中的 `NSLog`、`printf` 等输出调用。

## 实现

- 复用项目已有 `#if DEBUG` 方式；Release 不编译打印调用，也不计算其字符串插值、格式化、排序或遍历参数。
- 将日志专用的 Import 错误统计、最大邻居数计算、EFC 删除任务明细、Scene 目标值计算和滑动速度读取一并放入 Debug 条件。
- EFC Scene 与两份 UI tracer 的日志方法使用 `@autoclosure`，仅在 Debug 分支求值，防止调用方先计算日志字符串。
- 固件扫描日志默认输出闭包补齐 Debug 条件；原有 Debug 去重和计数行为保留。
- 保留错误处理、持久化、网络/Mesh 操作、失败返回、同步状态及恢复逻辑。未修改 UI 布局、用户文案、资源、依赖或 target 配置。
- 保留任务开始前已有的 `SunSmart.xcscheme` 修改；未提交或推送 Git。

## 验证

1. `python3 scripts/check_debug_logging.py` 通过。脚本使用 Xcode 工具链自带的 SwiftParser/SwiftSyntax 检查全部 App 打印的编译条件，并提取实际 EFC 日志方法验证：Debug 正常输出且参数求值一次；Release 无输出且参数不求值；关闭优化但不定义 DEBUG 时也无输出、不求值。
2. 现有 `GatewayFirmwareScanDebugLoggerTests` 分别在 Debug 与 Release 编译运行通过，验证 Debug 去重/汇总及 Release 无日志回调。
3. SunSmart 最终源码的通用 iPhoneOS Debug 与 Release 完整构建均通过。存在项目原有的资源重名、废弃 API、Swift 6 捕获语义等警告，没有构建错误。
4. 对五个品牌分别执行 Debug/Release 的 `xcodebuild -showBuildSettings`，核对有效编译条件如下；本次不需要修改配置。
5. Release 产物抽查 `[SpaceConfigurationSafety] blocked space=`、`[DaylightCalibrationDebug] event=app_start`、`[EFC Scene]`、`[HTTP][Request]`、`[EFC Delete Cleanup] task=` 均不存在。
6. `git diff --check` 通过。

| 品牌 | Debug 编译条件 | Release 编译条件 |
| --- | --- | --- |
| SunSmart | DEBUG | 无 |
| Archipelago | Archipelago DEBUG | Archipelago |
| SLG Sync Plus | DEBUG SLGSync | SLGSync |
| SylSmart | DEBUG SylSmart | SylSmart |
| Lumineux | DEBUG Lumineux | Lumineux |

构建直接使用 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart`，分别指定 `-configuration Debug` / `Release`，其余参数为 `-sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。未使用 Simulator，未进行真机控制台验收或性能基准测试；其他四个品牌核对了实际构建条件，未执行完整编译。

## SDK 边界

当前 workspace 实际引用远程 NordicSigMeshSDK 的 `release` 分支，构建解析到 `86f5ec9`。该依赖内部另有未受 Debug 条件保护的打印，例如 `MeshDatabase.swift` 和 `NetworkConnection.swift`；App 源码条件无法控制另一个 Swift 模块内的打印。

本次尚未修改 SDK、Pods 或系统日志设置，也未切换依赖。因此本次保证范围为 App 自身源码的打印，不能据此宣称整个 Release 进程绝对无日志。已向用户提出是否扩展到本地 SDK 的范围选择；本地 SDK 改动还需通过依赖切换或后续 SDK 发布进入 App。
