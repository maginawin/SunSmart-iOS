# iPad 启动持续加载分析

更新：后续已取得主线程 Mesh 解码现场栈，最新定位见 [主线程 Mesh 解码分析](260908_1633_ipad_startup_main_thread_mesh_decode.md)。以下保留初始日志阶段的分析过程，最终判断以新文档为准。

日期：2026-09-08。范围：用户提供的启动日志及 fix 工作区源码，只分析，未修改业务代码，未进行真机复现或服务器接口调用。

## 结论

若用户看到的是页面中央加载框，其直接控制链路为 SitesViewController.loadSitesRequest()：显示 HUD → 请求 sites → 成功后导入场所并刷新列表，或失败 → 隐藏 HUD。devicesConfig 是独立后台请求，不控制这个 HUD。

提供的日志只有两个 Request，没有 Response、Failure 或“导入数据”记录。因此优先调查 sites 请求完成回调之前的等待；尚不能区分设备网络、DNS/TLS、服务器响应、回调队列阻塞或日志截取不完整。Request 日志不能证明服务器已收到请求。

已确认的健壮性缺口：该入口的 HUD 使用 HUGE_VALF，没有有限的自动关闭时间；入口没有使用已有 maximumDuration 总时限请求封装。异常情况下，加载状态只能等待完成路径或断网观察回调清理，缺少独立的页面等待上限。但这不等于已经证明本次请求永远不返回。

## 源码证据

- SunSmart/Main/Site/Controller/SitesViewController.swift：loadSitesRequest 约第 293 行，先显示 HUD，失败分支会隐藏；成功且包含 sites 数组时等待整个导入任务组完成，再刷新并隐藏。
- 同文件 loadMeshDeviceConfigRequest 约第 477 行：只更新设备配置，没有显示 HUD。
- 同文件 menuClick 约第 515 行：HUD 可见时直接返回，可解释加载时菜单无法打开。
- 同文件 updateSyncState 约第 967 行：导航栏另有云同步转圈。如果实际转圈位于导航栏，应改查 CloudSynchronizationManager 状态，不能直接套用中央 HUD 结论。
- SunSmart/Thirdparty/WYHUDManager/Classes/XWHUDManager.m 第 88–92 行：默认加载时长为 HUGE_VALF。
- SunSmart/Common/Network/NetowrkReqeustApi.swift 第 206 行：sites 和 devicesConfig 的 requestTimeoutInterval 均为 10 秒。
- SunSmart/Common/Network/NetworkRequest.swift：已有带 maximumDuration 的异步请求封装；当前场所列表调用的是普通回调版本。
- SunSmart/Common/Network/NetworkLoggerPlugin.swift：Request 在 willSend 打印；Response/Failure 在 didReceive 打印，先于业务回调。
- Pods/Moya/Sources/Moya/MoyaProvider+Internal.swift 与 Moya+Alamofire.swift：响应回调中先执行插件；当前未指定 callbackQueue，使用 Alamofire 默认回调队列。因此缺少响应日志也不能排除回调队列阻塞。

10 秒请求超时不能理解为整个“网络 + 数据导入 + 页面刷新”必定在 10 秒完成。Apple 文档区分等待数据超时与资源总时限；新数据到达会重置请求等待计时。参考：[timeoutIntervalForRequest](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/timeoutintervalforrequest)、[timeoutIntervalForResource](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/timeoutintervalforresource)。

## 日志解读

- UIScene、UIRequiresFullScreen、方向支持：日志表述为未来兼容性要求；后续已进入 SitesViewController，没有证据表明这些警告导致此次等待。
- 空 App Group identifier：存在无效容器参数调用；当前搜索未在 App 自有业务源码找到直接调用位置，不能据此归因启动卡住，也不能擅自编造 identifier 修复。
- nw_connection 的 unconnected 提示：在未连接连接上读取元数据或端点；未包含具体 URL、错误码和任务映射，无法把 C3 直接对应到 sites，也无法单凭它认定 DNS、TLS 或服务端故障。

## 下一步定位与修复方向

1. 确认转圈位置、持续时长，以及等待超过 60 秒后的完整 HTTP Response/Failure 日志。
2. 若 sites 出现 Failure 但 HUD 仍存在，检查回调执行、HUD 归属、重复请求与主线程状态；若出现 Response 和“导入数据”却无“导入数据完成”，检查导入任务组。
3. 若持续没有两个请求的完成日志，真机暂停调试查看主线程和网络任务状态，并用另一网络复测；区分设备链路问题和 App 回调阻塞。Mac 能访问服务器不代表该 iPad 能访问。
4. 修复应在场所加载入口明确请求归属和有限等待上限，超时恢复本地列表操作并提示可重试，避免旧请求晚到覆盖新请求状态；为请求、导入、HUD 结束分别记录耗时。不能仅延长网络超时或定时隐藏 HUD 后宣称根因已解决。
5. 若涉及实现，再验证成功、失败、超时、重复刷新及导入异常路径，并在实际 iPad 验收。此次未实施修复或执行构建。

## 补充：持续等待仍无后续日志

用户确认后续没有更多日志，一直停留在这段输出。这使回调队列不能执行成为重点调查方向，但仍不能直接确诊死锁。

- Pods/Alamofire/Source/Core/DataRequest.swift 第 219 行明确响应默认 queue 为 .main。当前 Moya 未覆盖此队列，HTTP 完成日志和业务回调都会依赖主队列。
- HUD 使用 CABasicAnimation 驱动旋转；视觉上仍在旋转不能单独证明 App 主线程仍可处理任务。
- CloudSynchronizationManager 在网络变化或 App 激活后调用 resumePendingSynchronizations；其中包含本地恢复，以及 MainActor 上的 SiteData.loadAll、设备归属核对、空间恢复状态读取。这些是需要线程栈核实的同步工作候选，不是已确认根因。
- SitesViewController.viewDidAppear 后续同步状态读取和滚动指示器调用中，静态检查未发现明确的等待循环。PJUIDebug 的 enter 日志发生于 super.viewDidAppear 调用链内，不能把它当作整个子类 viewDidAppear 已返回的证明。

最小现场取证：保持 iPad 卡住且连接 Xcode 调试，点击 Pause，在 LLDB 控制台执行 `thread backtrace all`，保留全部输出。若主线程在锁、信号量、数据库或文件调用中，继续追踪对应持有者及调用链；若主线程在正常 RunLoop 等待，则转查 URLSession/Alamofire 请求状态。暂停取栈无需重启 App 或修改业务代码。

当前没有真机线程栈，因此不把网络问题、主线程阻塞或某个恢复模块写成确诊结论。仍未修改业务代码。
