# iPad 启动主线程 Mesh 解码卡顿：现场定位与修复方向

后续实施与验证见 [启动加载修复记录](260908_1650_ipad_startup_loading_fix.md)。本文保留修复前的现场分析。

日期：2026-09-08。依据：用户提供的卡顿现场 LLDB 全线程栈、当前 fix 源码及 SDK 对照。本文更新此前仅有 HTTP 日志时的判断。未修改业务代码，未执行构建或真机复测。

## 已定位的卡顿路径

现场 Task 1 明确运行于 com.apple.main-thread，其调用顺序为：

1. CloudSynchronizationManager.resumePendingSynchronizations 的 MainActor Task，第 332 行。
2. SiteDeviceOwnershipReconciler.reconcile，第 56 行。
3. ProximityLightingTopologyContext.network，第 224 行。
4. MeshNetwork.load(allData: true)，现场 SDK 第 254 行。
5. Node.load，现场 SDK 第 829 行。
6. JSONDecoder 解码 Element 数组、Model，最后采样在 Model.init 的解码及 swift_allocObject。

这份栈直接证明：采样时主线程正在做本地 Mesh 数据解码，没有在等待 HTTP，也没有停在锁或信号量等待点。结合持续卡顿症状，启动恢复任务的同步加载是当前已定位的主要调查与修复入口。

单个采样不能证明该函数永久不返回，不能证明 JSON 数据损坏、内存泄漏或死循环；具体耗时由节点数量、元素/模型规模、重复加载、存储读取及调试开销中的哪些因素造成，仍需计时或连续采样。

## 为什么日志也停止

Moya 没有自定义 callbackQueue；Alamofire DataRequest.response 默认在主队列执行。NetworkLoggerPlugin.didReceive 在该完成回调中打印 Response/Failure，随后才执行业务完成回调和隐藏 HUD。

主线程被同步数据处理占用时，即使底层网络已经结束，完成日志与 HUD 清理仍会排队。这解释了“配置了请求超时却无失败日志”的现象，但线程栈本身不能证明服务器实际已经返回。HUD 的 CABasicAnimation 仍然转动也不能证明主线程可响应。

UIScene、全屏方向要求及空 App Group 标识不在本次已捕获的卡顿调用链上。修改这些配置不是针对本次现场证据的修复。

## 放大因素与实现边界

- resumePendingSynchronizations 对每个正常 Site 先 reconcile，之后才筛选待上传 Space；因此没有待上传任务也可能先经历完整归属扫描。
- 该 Task 显式标记 MainActor。使用 Task 并不会把其中同步函数自动移到后台；当前捕获的 reconcile 阶段没有异步让出点。
- reconcile 遍历 Site 的正常 Space。除非命中当前已加载网络，否则 network(for:) 默认完整加载节点、组、场景，并读取 GroupInfo。
- SDK 的 Node.load 按 Site/子网过滤数据库行后逐节点解码属性，其中包含完整 Element/Model 数组。不能把这描述为无过滤扫描全部数据库。
- 网络恢复和 App 激活均能触发恢复任务；入口没有整个恢复任务的合并状态。runningSites 仅保护单次 reconcile 期间的重入，不能合并先后启动的完整扫描。此项为源码可见风险，本次尚无日志证明实际重复触发。
- reconcile 还负责设备替代关系、删除恢复和持久化验证，并要求主线程执行；不能直接用 Task.detached 包裹整个函数。SDK 加载也可能修补已用地址并保存，不应未经线程安全审查就作为纯读取并发运行。
- 工程 Package.resolved 固定远程 SDK release 的 86f5ec9e40148b9cd93e0512702337fcec41dd40；本地 one-dev 存在但 HEAD 不同。已对照固定 revision，确认节点 Element 解码路径一致；未把 one-dev 当作 iPad 当前二进制版本的证明。

## 建议修复方案

1. 为启动恢复建立单一任务入口，合并重复触发，并校验账户、服务器地区和任务有效性，防止旧任务写入新上下文。
2. 把设备归属扫描拆为安全的数据读取/计算阶段与串行校验/修改阶段；优先读取判定归属所需的轻量字段，避免仅为判定身份就完整解码每个节点的模型和全部组、场景。删除及拓扑清理仍按现有安全契约加载所需数据并执行。
3. 若需要后台读取，先确认数据库连接、共享编解码器、SDK 隐式写入和模型生命周期约束；提交修改前重新验证获胜节点、账户/地区及当前状态。不能只搬移同步函数或取消归属修复功能。
4. 给读取、归属计算、持久化阶段补充耗时和数量日志，验证单空间及整体耗时，识别重复扫描。页面请求的总时限和 HUD 结束保护可作为补充，但主线程计时器无法补救主线程长期被占用。
5. 验证大规模本地数据、无需上传、重复激活/网络恢复、跨空间同 MAC 替代及待删除恢复；真机确认启动可交互且 HTTP 完成日志及时出现。涉及 SDK 时检查全部引用 target 的构建，保留真实数据恢复和设备验收边界。

当前交付为原因分析与修复方向。具体数据规模和阶段耗时未测量，尚未实施修复。
