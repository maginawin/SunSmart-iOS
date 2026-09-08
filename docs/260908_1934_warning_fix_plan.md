# SunSmart / SunSmartLocal warning 修复方案（已确认）

用户已于 2026-09-08 确认按本方案实施。以下保留规划时的基线与范围；实际修复、构建结果及待验收项见 [实施结果](260908_1959_warning_fix_results.md)。

## 1. 工作范围与当前基线

- App 修改位置：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix-warning`。
- 用户日志来自相邻 `fix` 工作树；核对时两者 HEAD 均为 `a4ee57d3`，所列 App 警告位置在当前源码中存在。本次不会修改 `fix`。
- 本地 SDK：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，目录存在。
- App 核对前工作树干净；SDK 的 `Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift` 已有未提交修改，完整保留。
- 当前工作树没有 `SunSmartLocal.xcworkspace`；仓库已有 `scripts/setup_local_nordic_sdk_workspace.sh`。实施时使用它和明确的 SDK 路径建立被 Git 忽略的本地 workspace，避免误用 `fix` 的 workspace。
- 共享工程仍引用远程 SDK 的 `release` 分支。本地 SDK 修复不会自动进入远程版本；本方案不包含提交、推送、合并、SDK 发布或远程依赖升级。
- 五个引用 SDK 的品牌 target：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。
- App 公共 target 配置为 iOS 15.0 / Swift 5.0；SDK 为 Swift tools 5.8 / Swift language 5、最低 iOS 15。工程级另有 iOS 16.4 设置，最终构建需核对 target 的有效值。所提 UIKit 替代方案均可覆盖 iOS 15，无需提高最低版本。

## 2. 推荐实施顺序

1. 等价语法清理、无用绑定清理、SDK 类型名称与访问控制语法修正。
2. SDK Operation Sendable 声明审查、蓝牙状态日志隔离、云同步任务回调边界修正。
3. 文件选择器与扫码拍照 API 迁移。
4. 按钮布局迁移、图片资源符号冲突修复。
5. 聚焦回归、五品牌构建、实际设备交互和布局验收。

不关闭编译器诊断，不编辑 DerivedData 中的生成文件，不把整个工程切到 Swift 6，也不顺带升级 CryptoSwift 或扫码库。

## 3. SDK 警告逐项方案

以下路径相对于 SDK 根目录。

| 文件 / 原行号 | 原因 | 拟修复方式与边界 |
| --- | --- | --- |
| `Sources/NordicSigMeshSDK/nRFMeshProvision/Utils/AsyncOperation.swift:29` | Operation 已继承声明 unchecked Sendable，子类需显式重述 | 审查现有并发约束后，在当前类上重述 `@unchecked Sendable`；保留现有 Operation/KVO 语义。已有并发队列与 barrier 仅保护执行/结束标志，不能据此宣称所有子类线程安全。 |
| `Sources/NordicSigMeshSDK/nRFMeshProvision/Utils/AsyncResultOperation.swift:29` | 同上 | 同样重述；重点审查 result、onResult、finish、cancel 的调用与回调队列。若存在无保护的并发写入，先在该 Operation 层建立必要的同步，不能仅增加声明。 |
| `Sources/NordicSigMeshSDK/nRFMeshProvision/Bearer/Remote/PBRemoteBearer.swift:33` | Send 子类需重述继承声明 | 审查 shouldRetry、发送失败、超时、取消与成功回调路径后重述。`maxConcurrentOperationCount = 1` 只限制排队操作，不足以证明异步回调与取消互斥；新增同步如有必要只限这三个 Operation 类型，且避免持锁执行外部回调。 |
| `Sources/NordicSigMeshSDK/nRFMeshProvision/Bearer/GATT/BaseGattProxyBearer.swift:681` | 为外部类型 CBManagerState 添加外部协议一致性，存在未来冲突 | 推荐改为 SDK 自有的状态日志格式化方法/属性，日志显式调用，保留现有六种状态文本和 unknown 兜底，移除外部协议一致性。检查整个 SDK 与 App 的相关日志，不只是当前文件的插值。 |
| `Sources/CryptoSwift/Sources/CryptoSwift/CS_BigInt/BigUInt.swift:32–33` | `fileprivate (set)` 中的空格不符合新语法要求 | 仅移除两处多余空格，保留访问级别、存储与算法。 |
| `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift:39` | SDK 自身仍引用旧拼写别名 | 属性改用 `FunctionParameters`；保留已有的 deprecated `FunctionParamters` typealias 供旧调用方兼容，不变更协议字节或解析逻辑。 |

Sendable 的 unchecked 声明表示由实现者保证同步，并不会自动提供线程安全；上述三个类型的审查是实施前置步骤。[Swift 并发迁移指南](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/commonproblems/)

CBManagerState 的推荐方案会移除 SDK 额外提供的公开协议一致性；当前工程可同步调整调用，但未知外部消费者若依赖该一致性，需要发布前迁移说明。单独添加 `@retroactive` 只能承认风险，不能解决未来重复一致性问题，因此不作为首选。[Swift SE-0364](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0364-retroactive-conformance-warning.md)

## 4. App 并发与生命周期

### CloudSynchronizationManager.swift:939、1202

已核对：

- `CloudSynchronizationHandle` 拥有可变 state、timer、请求与 Task 句柄，类本身没有完整的单一隔离域。
- 延时触发来自自建 concurrent 队列。
- 网关授权 Task 未指定 MainActor，结束时再次 DispatchQueue.main.async 捕获 self。
- 配置上传 Task 已标记 MainActor，末尾也已经在 MainActor.run 内，却再次嵌套 DispatchQueue.main.async。

推荐局部收敛这两个警告涉及的执行边界：

1. 网关授权 Task 明确在 MainActor 上处理状态、句柄与模型写回；网络调用继续异步 await，保留取消检查及 generation 确认/重试语义。
2. 配置上传保留已有 MainActor 隔离，在该上下文完成回调，移除不必要的再次跨队列捕获。
3. 不给整个 CloudSynchronizationHandle 添加 `@unchecked Sendable`，也不使用 nonisolated(unsafe) 或匿名包装逃避检查。
4. 回调从“排入下一轮主队列”变为当前主执行上下文调用，必须验证 manager 回调重入、句柄移除、取消后晚到结果，以及新任务不能被旧任务清理的行为。若必须保留异步顺序，采用明确的 MainActor 回调调度，并验证编译器隔离检查。
5. 保持当前 manager API 与同步任务合并规则；本轮不宣称完成整个云同步系统的并发迁移。若局部修改引出其他实际跨隔离错误，先补充证据和最小方案，不能用 unchecked 标注掩盖。

### GatewayTimeInformationCoordinator.swift:159

在嵌套闭包调用中显式使用 self。保留外层 `[self]` 的强捕获，让读取在页面离开后仍可完成恢复/收尾；不能为了消警告改为 weak 导致清理丢失。

## 5. App 等价清理清单

以下均相对于 `SunSmart/`；行号以用户日志及本轮核对版本为准。

| 文件 / 原行号 | 拟处理方式 |
| --- | --- |
| `Common/Tools/LCWeakTimer.swift:29` | 显式丢弃 perform 返回值，保留 selector 调用；不改变 Unmanaged 所有权。 |
| `Common/Data/MeshNetwork+SunSmart.swift:3185` | 将未使用的 model 解包改为非空判断，保留 scheduler 删除确认条件。 |
| `Common/Data/ImportData.swift:2536` | 显式丢弃 devices(in:) 返回值，保留调用。已确认其执行 repository 加载、真实消防控制器合并和 mergeCache，直接删除会丢副作用。 |
| `Thirdparty/ScanQRCode/LBXScanViewController.swift:14` | class 协议约束改为 AnyObject，保留弱代理语义。 |
| `Main/Site/Controller/SitesViewController.swift:417、1491` | 移除未使用的 owner/gateway 关联值绑定，保留对应枚举分支。 |
| `Main/Site/Controller/SitesViewController.swift:708` | 改为 contains(where:) 存在判断，保留删除场所的设备检查。 |
| `Main/Site/Controller/SiteViewController.swift:1629` | 同上。 |
| `Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift:115、173` | 未使用的 space 解包改为非空判断，保留 SAVE/同步入口的 Space 存在门槛。 |
| `Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift:152` | 保留 space 非空与 currentDevice 解包检查。 |
| `Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift:367、369` | powerLossTrigger、fireTrigger 改为 let；另外两个会变化的状态仍为 var。 |
| `Main/Device/Dongle/Controller/DeviceDongleViewController.swift:600` | bindNode 解包改为非空判断，保留 UI 显隐分支。 |
| `Main/Device/Controller/DeviceInformationViewController.swift:439` | 删除未使用的 sectionType 读取，保留固定行高。 |
| `Main/Device/Controller/DevicesReplySetViewController.swift:79` | 移除没有使用的 weak self 捕获，保留关闭弹窗与停止发送。 |
| `Main/Device/View/UpDownLightView.swift:62` | imageAlpha 改为 let。 |
| `Main/Group/Model/GroupServer.swift:454` | 删除未消费的 removeSceneDatas 过滤计算；不启用后面已注释的场景删除逻辑，不改变实际退组消息。 |
| `Main/Timed/Controller/ScheduleAddViewController.swift:623` | 去掉被下一行同名变量遮蔽的关联值绑定，保持当前候选与默认选中行为。默认全选是否合理属于独立产品问题。 |
| `Main/Firmware/Controller/MeshSelectUpgradeDevicesViewController.swift:18、20、22` | 移除不用的 failureNodes/max 绑定，不改错误枚举关联数据或现有错误文案。 |
| 同上 `:158` | 将未使用的 self 解包改为 self 存活检查，保留页面释放后不显示结果的行为。 |
| 同上 `:296` | 保留 await 调用，返回值改为非空判断，保留升级排队条件。 |
| `Main/Energy/View/EnergyHarvestSelectView.swift:333` | 空回调去除 weak self 与无用 guard；继续明确覆盖复用 cell 的回调，不引入新的 Identify 行为。 |
| `Main/Energy/View/ImportEnergyDeviceSelectView.swift:229` | 同上。 |

### GroupPowerSwitchesViewModel.swift:86

这是用户可见 MAC 文案，不应改成 String(describing:) 保留 Optional(...) 外观。先解包 `getMacAddressSegmentString()`，格式化成功后显示 MAC；失败进入与现有无 MAC 分支一致的 N/A 兜底。新增或调整的格式串/兜底通过本地化 key 输出，先查复用 key，必要时同时补充 en 和 zh-Hans。覆盖合法、空值、格式错误三类输入。

## 6. 旧 API 迁移

### 文件导入：SiteViewController.swift:2316

改用 UTType 的 data/content 与 `init(forOpeningContentTypes:asCopy:)`，明确 asCopy 为 true，保持原 `.import` 的复制导入语义，不改为原位置打开。保持 delegate、单文件选择、取消和后续解析流程。[Apple 文件选择器文档](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init%28foropeningcontenttypes%3Aascopy%3A%29)

### 扫码：LBXScanWrapper.swift:48 及关联调用

不能只替换属性类型：同文件初始化、session output、JPEG 设置、captureImage 都引用旧 API。

- 使用 AVCapturePhotoOutput、AVCapturePhotoSettings 和 AVCapturePhotoCaptureDelegate，照片数据通过 fileDataRepresentation 获取。
- 保留普通扫码、连续扫码和 isNeedCaptureImage 可选照片返回路径；即使默认不拍照，也不删掉现有能力。
- 沿用现有 sessionQueue 执行 session 启停，拍照结果及 UI 回调明确回到主线程；避免重新引入主线程 startRunning 警告。
- 处理照片失败/无数据、页面退出、重复扫码与晚到回调；每次有效扫码至多完成一次，空结果不使用会越界的数组闭区间。
- 保留预览、扫码识别区、相册识别和手电筒入口；不新增权限或额外用户文案。
- 验证普通扫码成功、连续扫码、带照片成功、失败回收、取消后再次进入及权限拒绝。

迁移依据：[Apple AVCapturePhotoOutput](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput?changes=_9)、[照片数据转换](https://developer.apple.com/documentation/avfoundation/avcapturephoto/filedatarepresentation%28%29)。

## 7. 按钮布局迁移

不全局改动 UIButton 便利构造器或现有 setImagePosition，避免影响其他页面。只给所列按钮接入小范围复用的布局实现，复用当前字体、颜色、圆角与资源。

| 布局种类 | 涉及位置 | 方案 |
| --- | --- | --- |
| 左图右文 Scan | SiteDeviceAddViewController:884–885；DeviceAddClassicModeController:1970–1971；DeviceAddProfessionalModeController:2175–2176、2296–2297；DeviceRestoreViewController:3152–3153；DeviceAddCandidateDeviceListView:614–615 | 使用 UIButton.Configuration.plain 的 leading 图片位置、imagePadding 和 contentInsets；逐处保留 72/80/126 等实际宽度、字体、边框和左对齐效果。 |
| 左侧文字、右侧固定箭头 | DeviceAddClassicModeController:2002–2003；DeviceAddCandidateDeviceListView:206–207；EnergyStaticDataViewController:474–475 | 原有 frame 偏移把箭头固定在右边，仅设 imagePlacement.trailing 不保证等价。优先使用当前项目风格的专用 UIButton 子类/内部 label 与 imageView 约束，约束文字左边距、箭头右边距和最小间隔，标题截断，不依赖一次性 frame。保留整个按钮点击区及无障碍语义。 |
| Identify 文字内边距 | DeviceForceResetViewCell:244；DeviceAddViewCell:339 | 使用 Configuration.contentInsets 保留水平 SCRXFrom(14)，确认 intrinsicContentSize、相邻按钮间距及 disabled 颜色不变。 |

Configuration 迁移同时核查后续 setTitle/setImage、selected/disabled/highlighted 状态和 configurationUpdateHandler，不能让系统默认字体、tint 或内边距覆盖原样式。[Apple contentInsets 文档](https://developer.apple.com/documentation/uikit/uibuttonconfiguration/contentinsets)

实际布局验收：英文/简体中文、短标题/长标题、普通/禁用/加载状态；iPhone/iPad 可用尺寸、页面重新进入、cell 复用，以及应用允许的尺寸变化。检查完整约束链、无重叠/裁切、箭头位置和点击路径。原工程未开放的旋转/分屏能力不在本次开启。

## 8. 资源符号冲突

同一警告在日志中重复出现，先作为一个资源命名问题处理：

- `SunSmart/Assets.xcassets/Device/device_dongle.imageset`
- `SunSmart/Assets.xcassets/Device/Icon/Dongle/device_Dongle.imageset`

两者归一化后均生成 deviceDongle。已确认小写资源由 DeviceOthersCollectionViewCell 显式引用；大写资源由 MeshDeviceConfigInfo 的 device_ + iconCategory 动态引用，devices_config.json 中存在 Dongle 分类。

推荐保留动态使用的大写资源，将小写资源改为唯一语义名称，例如 `device_dongle_legacy`，同步更新其显式引用。保留图片内容，不合并两张资源，不修改 device_dongle_offline 与 device_menu_dongle。

实施时全仓检查 Swift、JSON、Storyboard/XIB、资源处理脚本和五品牌资源合并路径；重新生成 asset symbols 确认不存在冲突。不能修改 GeneratedAssetSymbols.swift，也不关闭整个工程的资源符号生成。

## 9. 验证与完成标准

### 自动验证

1. 使用当前 fix-warning 的本地 workspace 对 SunSmart 建立基线，记录实际解析的 SDK 路径，按警告文件/诊断归一化对比；重复编译输出不算多个独立问题。
2. 使用现有相关检查：SDK 依赖配置、network response queue、configuration database safety、space recovery receipts、gateway information time、timed scheduler persistence、EFC controller flows、device menu icons 等。按实际改动选择，不对全部无关脚本做重复测试。
3. 并发/状态有改动时增加有行为价值的回归：Operation 完成/取消交错与回调次数，云同步取消/替换后的晚到响应、回调队列与顺序。语法清理不逐行新增形式化测试。
4. SDK 使用可运行的现有协议/Standalone 测试；包含 UIKit 的 package 测试不能默认视作可在 macOS 直接 swift test，需区分可运行逻辑测试、iOS 编译与真机执行。
5. 通过直接 xcodebuild、Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO，构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。使用 SunSmartLocal.xcworkspace 验证本地 SDK，不使用 Simulator，不用 shell 包装或日志重定向。
6. 保持共享远程 SDK 配置原样，补充共享 SunSmart.xcworkspace 的 App 兼容构建；它仍可能包含尚未发布的 SDK 原始警告，必须与本地 SDK 验证结果分开报告。
7. 检查本地化两种语言、资源引用、git diff --check，并确认没有改动 SDK 既有 MeshDatabase.swift 内容。

### 实际设备验收

- 五品牌启动与受影响入口的冒烟验证；完整按钮布局在实际 UIKit 运行环境检查，至少覆盖 iPhone/iPad 和英中布局。
- 扫码与可选照片返回、手电筒、离开后重进；文件导入和取消。
- 云同步成功/失败/取消/替换、网关授权重试、TimeGet 收尾，确认状态与回调无回退。
- Remote Provisioning 发送/超时/取消的真实 BLE/Mesh 验证与自动化结果分开记录。

目前尚未确认可用的实际测试设备。若执行时无法取得设备或现场操作，报告应明确标记这些验收未完成；编译通过与源码检查不能算 UI/相机/Mesh 验收完成。

## 10. 待用户确认的实施范围

推荐确认以上全部类别，在 fix-warning 和本地 one-dev SDK 实施，保持远程依赖与未提交工作不变。范围包括扫码照片 API 迁移、按钮实际布局验证，以及 SDK 蓝牙状态外部协议一致性的移除；这些是相较纯语法清理需要重点回归的部分。

此方案已获得确认，执行情况以实施结果文档为准。
