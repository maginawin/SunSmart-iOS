# iPad Information 返回崩溃分析与修复方案

## 结论与当前状态

已按用户确认的范围完成 App 修复，定向回归及 SunSmart generic iOS 构建通过，真实 iPad 返回转场尚待人工验收。修复前的直接原因是 Information 页对第 0 个分区执行局部刷新时，第 2 个 Scene 分区的有效行数也从 2 变成 0，但刷新操作没有包含这个变化，导致 `UITableView` 抛出 `NSInternalInconsistencyException`。

修复同时覆盖页面离开后的 RSSI/固件 UI 回调，以及 Scene 行数和单元格实时读取可变共享数据的问题。以下分析证据保留修复前基线；实际改动与结果见文末。

用户随后明确“按上述范围实施修复”。本次只修改 App 共享 Information 页面、增加定向测试并更新本文档；没有 SDK、数据库、export JSON、协议或外部服务结构变更，未 commit/push。

## 检查基线

- 时间：2026-11-07，Asia/Singapore。
- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-device-scene-261028`。
- 分支：`feat/device-scene-261028`。
- App HEAD：`0b8a588a7fa6fbd5dc94d4539ce9d437e09f4d75`。
- 开始检查时工作树干净。
- 本地入口：`SunSmartLocal.xcworkspace`；其 `.local-sdk/nordic-sig-mesh-sdk` 指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK HEAD：`8f62e8aafeda0c5d9ac678f085c589da99e17e26`，检查时无未提交改动；仅作只读追踪。
- 原始证据：`/Users/maginawin/Desktop/ipad crash bugly logs.txt`。
- 日志未给出 App version/build、iPadOS 版本或构建 revision，因此“当前未修复”指上述工作树代码，不能据此确定设备上已安装包或商店包的状态。

## 崩溃证据

Bugly 报告的表格 dataSource 是 `SunSmart.DeviceInformationViewController`，不是 Lights 列表。栈的关键顺序：

`CoreBluetooth didDiscover` → SDK `refreshNodesRSSI` → `emitNodeRSSIRefreshSample` → Information `refreshRSSI` 回调 → `reloadDeviceInfoSection` → `UITableView.reloadSections` → 异常。

| 分区 | 当前页面含义 | 更新前行数 | 更新后行数 | 本次更新是否覆盖 |
| --- | --- | ---: | ---: | --- |
| 0 | Device | 12 | 12 | 是，Reload 在异常中表现为 Delete 0 + Insert 0 |
| 1 | Group，内容位于 header | 0 | 0 | 否，无行数变化 |
| 2 | Scene | 2 | 0 | 否，遗漏了 2 行的变化 |

因此，这不是第 0 分区的 12 行算错，而是其余分区在局部刷新时已与 UITableView 上次记录的状态不一致。`.none` 只决定动画，不免除一致性检查。Apple 文档也明确 `reloadSections` 针对指定分区重新取数据，而 `reloadData` 重新加载整张表的数据。

- [Apple reloadSections(_:with:)](https://developer.apple.com/documentation/uikit/uitableview/reloadsections(_:with:))
- [Apple reloadData()](https://developer.apple.com/documentation/uikit/uitableview/reloaddata())

## 修复前代码对应关系

以下位置均以本次 HEAD 为准。

| 位置 | 代码事实 | 影响 |
| --- | --- | --- |
| `DeviceInformationViewController.swift` 369–389 | 开始最长 5 秒 RSSI 刷新；两个回调只校验弱引用及节点地址，没有页面可见轮次校验 | 控制器尚未释放时，返回过程中的回调仍可刷新 UI |
| 同文件 392–398 | `reloadDeviceInfoSection` 只调用 Device 分区的 `reloadSections` | 与 Bugly 栈直接对应，缺陷仍存在 |
| 同文件 552–565、585–603、653–673 | Scene 行数、header、cell 分别实时访问 `node.scenes`；cell 直接按下标访问 | 计数和内容缺少同一份稳定的展示数据，另有越界风险 |
| 同文件 351–365 | 固件回调另行执行 `setupDeviceInfoDataSource` 和第 0 分区刷新 | 单改 RSSI 入口会留下相同刷新缺口；退出后还可能接着请求初次 TTL |
| 同文件 119–137、156–157、289–341 | `viewDidAppear`、TTL、网关/灯具时间回调复用局部刷新；退出仅清理时间协调器和 TTL | 已有局部生命周期保护，但不覆盖全部 UI 入口，也未解决分区一致性 |
| 同文件 599–604 | header 展开/收起直接改变 `sectionShowMap` 并局部刷新 | 也须纳入统一数据与刷新规则 |

相关文件目录：`SunSmart/Main/Device/Controller/`。

核心 RSSI/刷新实现的 blame 仍指向 `b941d347`（2026-05-15）。当前的 `didRefreshCurrentNodeRSSI` 只避免收到目标设备后，在完成回调中再次处理；它不保证其他分区行数稳定，也不判断页面是否已经退出。后续时间、TTL 和导航样式改动没有消除本次缺陷。

## 返回路径与 Scene 变化边界

已核对页面路径：

1. `DeviceLightsViewController.collectionLongPressAction` 创建 `DeviceLightViewController`，放入模态 `NavigationViewController`；iPad 设置首选尺寸。
2. 设备页 `information()` 使用 `pushDeviceInformationController` 打开共享 Information 页面。普通灯具包含 Device、Group、Scene 三个分区，并注入时间与 TTL 上下文；常见形态为 9 个基础字段 + TTL + 日期时间 + 时区，即日志中的 12 行。
3. Information 返回设备页后，设备页 `backAction()` 关闭模态导航栈，回到 Lights。
4. Information 当前没有在开始离开时使 RSSI 回调失效。`[weak self]` 只防止访问已释放对象，不代表“已经离开就不再刷新”。转场期间对象仍可能存活。

SDK 的 `Node.scenes` 并非稳定数组，它按 `meshNetwork.scenes` 中包含该节点 Element 地址的成员关系实时计算；`Node.meshNetwork` 还是弱引用。`SceneClientHandler` 收到有效 Scene Register 状态时，会依据返回列表更新已有 Scene 的地址成员关系。因此，其他业务的状态回读就可能改变这个 getter 的结果。

**证据限制：**日志只证明 Scene 分区的有效行数由 2 变为 0，没有记录对应的 Scene Register 回包、网络对象生命周期或展开/收起动作。不能断言本次一定是某个回包、某次网络重载，或用户的两个业务 Scene 被删除；也不能仅凭该日志确认异常精确落在第一次返回还是第二次返回的哪一个生命周期回调中。正常 Lights 返回代码本身没有直接清空这两行的证据。

这些缺失不影响崩溃修复方向：合法的数据变化和退出后的回调都不应使 UITableView 崩溃。iPad 是本次已报告的触发环境；共享代码没有 iPad 专属保护，不能认定 iPhone 不受影响。

## 已确认的最小完整方案

### 1. 统一 Information 的展示数据与刷新入口

- 为页面建立轻量的内存展示快照：Device 行、Group 显示内容、Scene 行及当前展开状态。Scene 行使用复制后的展示值，避免仅缓存可继续被修改的 `Scene` 引用。
- `numberOfRows`、header 和 `cellForRow` 读取同一份快照；不在 UIKit 多次取数过程中各自重新查询 `node.scenes`。对索引访问保留边界保护。
- RSSI、固件、TTL、时间、页面重新出现和展开/收起统一进入主线程刷新入口；一次生成并提交完整快照，再使用无动画 `reloadData()` 更新表格，去掉这些路径的局部分区批量更新。
- 保留已有分区显示开关、文字覆盖、展开/收起状态和可保持的滚动位置。展开/收起功能保留，原有分区插删动画改为无动画刷新；人工验证其视觉表现和滚动位置。
- 现有机制不足之处是只缓存了 Device 行，Scene 仍是动态查询。新增快照仅属于当前页面内存，不引入全局缓存、持久化、恢复流程或新的数据源框架，维护成本集中在一个展示构建入口。

### 2. 约束页面生命周期与迟到回调

- 页面开始离开时停止接受 UI 更新，并使本轮 RSSI 等页面专属回调失效；回调中的节点更新、扫描停止、UI 刷新和后续请求必须先通过当前轮次校验。
- 页面正常出现、取消返回手势后恢复出现、以及退出重进时，重新建立有效展示状态；需要的读取按现有串行规则恢复，避免旧轮次启动新 TTL 请求或覆盖新页面结果。
- 保留现有时间协调器和 TTL 的收尾语义。TTL 已确认的写入、保存和同步不能因为关闭页面而被丢弃；最终退出时解除 UI 关联，暂时消失不能错误地永久 detach 后又无法恢复。
- 不在页面退出时无条件调用全局 `stopRefreshNodesRSSI()`：SDK 扫描器由多个页面共享，且停止会同步触发旧完成回调。优先让旧页面的回调失效，允许原有有界扫描自行结束或被新请求替换，避免停止 Lights 或新 Information 页的扫描。
- 如需诊断，只添加 `#if DEBUG` 下的页面轮次、刷新来源、有效性及分区行数摘要，不输出密钥，不逐个广播打印。

### 3. 范围和兼容性

- 预计改动共享 `DeviceInformationViewController.swift`，按验证需要增加小型可离线测试的展示/生命周期逻辑及行为测试；不更改设备实际 Scene 数据或同步规则。
- 普通灯具、Base、Gateway、EFC 和八键开关入口共用此页面，须保留各自隐藏 Scene/Group、覆盖文本、TTL 与时间能力的差异。DALI/Gateway 同名空壳控制器不是本次实际崩溃入口。
- 工程中该文件归属 SunSmart、Archipelago、SylSmart、SLG Sync Plus、Lumineux、HSmart 六个 target；共享修复影响其对应入口。
- 不需要 SDK API、依赖 revision 或远端发布配套，不修改固件、服务器及运行配置。
- **数据库/export JSON：无新增、删除、字段语义、层级、默认值或关联关系变化；无需迁移、回填或新旧格式兼容处理。**

## 实施后的验证与验收

| 验证 | 必须覆盖的行为 | 证据边界 |
| --- | --- | --- |
| 新增定向行为回归 | Scene 2→0、0→2、数量不变但内容替换；展开/收起期间 RSSI/固件刷新；空 Scene、隐藏 Scene 和文本覆盖入口 | 使用真实生产展示/生命周期逻辑，不能只断言源码字符串；离线测试不等同 UIKit 运行 |
| 异步回归 | 离开后目标 RSSI/无结果完成回调、固件成功/失败回调；旧完成回调被新扫描同步触发；快速重进、手势取消；旧轮次不刷新、不停止新扫描、不追加读取 | 要验证调用次数和顺序，覆盖 SDK 停止会同步调用完成回调的边界 |
| 现有回归 | `check_information_ttl.sh`、`check_light_information_time.sh`（含网关时间）、`check_device_information_menu_transition.sh`、必要的 Information 分区检查 | 部分既有脚本只是源码契约检查，不能代替表格/生命周期行为验证 |
| 编译 | 复核本地 SDK 映射后，SunSmart Debug、generic iOS、关闭签名构建一次；核对新增文件在六 target 的归属 | 纯共享逻辑且无品牌差异时不机械重复六次构建；若实际实施引入跨 target 编译风险，再覆盖相应 target |
| 用户真机验收 | iPad 在有两个 Scene 的灯具上执行 Main → Lights → 设备 → Information → 返回 → 返回；分别在进入后立即、1–5 秒内及超时后返回；重复进入；覆盖无 Scene/离线设备及展开/收起；取消返回手势后仍能刷新 | 验证无 crash、无旧页面提示/刷新、Lights 扫描不受影响；iPhone 同路径做共享逻辑冒烟；本轮不自动操作真机 |

若实际 Scene 变化无法稳定重现，可在实施后的受控调试验证中使同一节点的 Scene 展示来源由 2 行变成 0 行，再触发 RSSI/固件回调；须与正常硬件回读验收分别记录。不能将简化夹具的通过写成真实 UIKit 异常已复现或真机已修复。

## 实施结果（2026-11-07）

### 实际改动

- `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`：新增文件内的展示快照与页面有效性状态。Foundation 部分可单独编译供测试使用，UIKit 控制器仍在原文件内，保持六个 target 的现有 Sources 归属，没有修改工程或依赖声明。
- Scene 的名称和状态文本在刷新入口复制为值；Device 行、Group 文字、Scene 行及展开状态一次提交。行数、header、cell 与点击索引都读取快照，并校验索引范围。缺少 Scene 执行数据时清空内容，避免复用上一行文字。
- 全页仅保留一个 `reloadData()` 刷新入口，主线程执行，无分区插删动画；在可用范围内恢复原滚动位置，内容缩短时限制到有效范围。
- 请求从首次 `viewDidAppear` 启动；`viewWillAppear` 建立展示状态，`viewWillDisappear` 立即使当前 RSSI/旧 header/旧弹窗操作失效并关闭本页提示，不停止共享扫描器。真正退出时完成已有时间/TTL detach；导航父级已清空也能识别为退出。
- RSSI 还校验 `Node` 对象身份；收到目标样本后先标记已接受，再调用 SDK stop，防止其同步完成回调清空刚收到的 RSSI。
- 固件/时间区分“暂时不可见”与“页面已结束”：暂时不可见时允许同一页面的未完成请求更新内部读取状态，但不刷新表格、不启动初次 TTL。取消返回或重新显示同一控制器后，复用正在执行的请求，避免重复固件/时间读取；永久退出后不再接受页面回调。TTL 已确认写入的持久化/同步逻辑保持原样。
- 没有增加生产 DEBUG 日志，没有改文案、本地化、设备 Scene 成员关系、存储或同步协议。

### 定向测试与边界

新增 `scripts/check_device_information_presentation.py` 和 `Tests/Device/DeviceInformationPresentationTests.swift`。脚本直接编译生产快照/页面状态，并提取当前控制器的真实生命周期、RSSI/固件回调、TTL 调度、整表刷新、行数与 header 方法执行；没有在测试里重写这些决策。

5 组行为检查覆盖：

1. Bugly 的 `[12, 0, 2]` → `[12, 0, 0]`，固件刷新时 `0→2`、同数量内容替换、共享对象改名后快照仍稳定、缺少执行数据的空内容。
2. 实际 header 点击展开/收起、刷新保持折叠状态、空 Scene header、开关文字覆盖、Gateway/EFC 分区组合及滚动位置限制。
3. 开始离开后迟到 RSSI/完成/固件回调不操作旧 UI、不触发 TTL、不停止新扫描；模拟 SDK 替换扫描时同步调用旧完成回调。
4. 取消返回后继续显示：旧 RSSI/header 回调不复活，固件/时间不重复读取，原请求完成后可继续初次 TTL，重复固件完成被忽略，其他 Node 对象不能匹配，当前超时正常清空 RSSI。
5. 暂时隐藏期间固件完成，恢复后不会卡住；永久退出并重新进入时，旧控制器回调不影响新页面。

测试中的 UITableView、导航、设备与 SDK 收发是可控制的替身，未执行 UIKit 内部批量更新校验、真实 BLE 广播/解码、持久化或实际转场。实际 Scene 上游为什么变为零仍无现场回包证据。已有 TTL 回归单独验证退出后确认写入继续保存/同步且不通知 UI；这些结果不替代真机和服务器验收。

### 验证记录

| 检查 | 结果 |
| --- | --- |
| `python3 scripts/check_device_information_presentation.py` | 5 组通过；测试夹具最初缺少 CoreGraphics import，补齐后通过 |
| `bash scripts/check_information_ttl.sh` | TTL 行为及中英文资源检查通过 |
| `bash scripts/check_light_information_time.sh` | 灯具时间、共享时钟恢复、网关时间及其附带回归/源码契约检查全部通过 |
| `bash scripts/check_device_information_menu_transition.sh` | 通过 |
| 六 target Sources 归属 | SunSmart、Archipelago、SylSmart、SLG Sync Plus、Lumineux、HSmart 均各引用原共享文件一次 |
| `git diff --check` | 通过 |
| SunSmart Debug generic iOS | 构建退出码 0；Xcode LogStoreManifest 的 primaryObservable 记录 0 errors、119 warnings；修改文件 arm64 对象、App 可执行文件和 debug dylib 均已生成 |

构建命令：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-information-return CODE_SIGNING_ALLOWED=NO build -quiet
```

构建使用本机 iphoneos27.1 SDK。输出包含 CryptoSwift 的 “command failed with exit code 0 but produced no further output” 诊断，以及现有 Swift 6 兼容/弃用 API 等告警；已通过最终退出码、Xcode 记录及实际产物交叉核对，没有清缓存或修改依赖来规避诊断。纯共享逻辑没有品牌差异、新文件归属或公共 API 变化，本轮仅构建代表 scheme SunSmart。

App HEAD 仍为 `0b8a588a7fa6fbd5dc94d4539ce9d437e09f4d75`，修复为未提交差异。SDK HEAD 仍为 `8f62e8aafeda0c5d9ac678f085c589da99e17e26`，工作树干净，本次未写 SDK。未使用 Simulator，未安装或运行真机。

### 剩余人工验收

在本分支构建的 iPad App 上，选有两个 Scene 的灯具，走 `Main → Lights → Device → Information → Back → Back`，分别立即返回、1–5 秒内返回和等待读取结束后返回，重复数次。补测展开/收起、无 Scene/离线设备、取消返回手势后继续使用，以及退出后重新进入。预期无 crash，Scene/Group/Device 内容一致，页面能继续刷新，返回 Lights 后扫描不受旧回调干扰。再用 iPhone 做同路径冒烟。最终体验和真实 BLE/设备行为仍待人工确认。
