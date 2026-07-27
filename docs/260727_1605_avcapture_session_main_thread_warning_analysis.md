# AVCaptureSession 主线程警告分析

## 结论

该问题建议修复。

它不是 Swift 编译器产生的静态警告，而是 Xcode Thread Performance Checker 在真机运行期间发现的线程性能问题。当前代码在主线程同步调用 `AVCaptureSession.startRunning()`，可能阻塞主线程并造成扫码页面进入动画卡顿、按钮短暂无响应或 watchdog 风险。

它通常不会直接导致崩溃，也不代表扫码功能一定失败，因此优先级可定为中等；但根因明确、修复范围可控，不建议长期忽略。

## 证据链

1. `LBXScanViewController.viewDidAppear(_:)` 使用 `perform(...afterDelay:)` 在当前主 RunLoop 延迟调用 `startScan()`。
2. `startScan()` 完成界面更新后调用 `scanObj?.start()`。
3. `LBXScanWrapper.start()` 在调用线程直接执行 `session.startRunning()`，对应诊断中的第 153 行。
4. Apple 文档明确说明 `startRunning()` 是同步阻塞调用，可能耗时，应在串行调度队列执行以避免阻塞主队列。
5. 同类问题也存在于 `stopRunning()`：Apple 文档明确说明它会同步阻塞直到会话完全停止。当前第 160 行同样直接在调用线程执行。

相关位置：

- `SunSmart/Thirdparty/ScanQRCode/LBXScanViewController.swift` 第 166–170、176–217 行
- `SunSmart/Thirdparty/ScanQRCode/LBXScanViewController.swift` 第 254–257 行
- `SunSmart/Thirdparty/ScanQRCode/LBXScanWrapper.swift` 第 150–160 行

Apple 参考：

- [AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession)
- [startRunning()](https://developer.apple.com/documentation/avfoundation/avcapturesession/startrunning())
- [stopRunning()](https://developer.apple.com/documentation/avfoundation/avcapturesession/stoprunning())
- [AVCam: Building a camera app](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app)

## 为什么显示两条相同警告

两条文本都指向同一文件同一行，因此不是两个不同根因。

现有代码允许多次启动扫描：

- 页面首次出现时启动一次；
- 扫码失败、业务校验失败或用户取消某些提示后，多个调用方会再次调用 `startScan()`；
- 每次会话已经停止后重新执行 `startRunning()`，Thread Performance Checker 都可能再次记录同一诊断。

仅凭这两行文本无法确定是同一次调用被控制台重复展示，还是实际执行了两次。若需要精确区分，应保留诊断发生时的完整调用栈和时间戳。不过这不影响根因和修复方向。

## 推荐修复

### 最小且正确的修复

在 `LBXScanWrapper` 内新增一个实例级专用串行队列，用它统一管理捕获会话的启动和停止：

1. `start()` 仍可由主线程调用，但把 `isRunning` 判断和 `startRunning()` 一起提交到专用串行队列。
2. `stop()` 把 `isRunning` 判断和 `stopRunning()` 一起提交到同一个队列。
3. 扫描结果开关应在主线程及时更新，避免页面已经退出或已取得结果后继续处理元数据。
4. 预览层的创建、frame 更新、插入视图层级，以及所有界面动画和结果回调继续留在主线程。

关键点是“同一个专用串行队列”。不能只把 `startRunning()` 随手扔到全局并发队列，也不能仅异步启动而仍在主线程停止；否则快速进入、退出或重启扫码页时，启动和停止可能乱序。

### 更完整但改动较大的优化

当前 `LBXScanWrapper` 初始化时还会在主线程创建输入、添加输入输出并设置 session preset。Apple 的当前 AVCam 架构也把捕获会话配置放在非主线程隔离上下文中。

若后续真机性能分析显示进入扫码页仍有明显卡顿，可进一步：

1. 将会话创建、配置、启动和停止全部封装到专用串行队列或独立 capture service；
2. 使用明确的配置完成状态，配置成功后再启动；
3. 主线程只负责 `AVCaptureVideoPreviewLayer` 和界面；
4. 另行评估把已废弃的 `AVCaptureStillImageOutput` 迁移到 `AVCapturePhotoOutput`。

这属于扫码模块现代化，不应与本次线程警告的最小修复捆绑实施。

## 影响范围

`LBXScanWrapper.swift` 同时加入以下四个 App target 的 Sources：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

因此修改共享文件即可覆盖四个品牌，但验证时应至少编译四个 target，并在有扫码入口的品牌真机验证。

本次问题不涉及用户可见文案、本地化、资源或依赖。

## 验证建议

编译只能证明代码兼容，不能证明 Thread Performance Checker 诊断已经消失。建议分两层验证：

1. 对四个品牌 target 执行 generic iPhoneOS Debug build。
2. 在真机启用 Thread Performance Checker，覆盖以下场景：
   - 首次进入扫码页并等待预览出现；
   - 退出后重新进入；
   - 扫到无效二维码后恢复扫描；
   - 快速进入后立即退出；
   - 连续多次启动、停止；
   - 验证退出页面后摄像头确实停止、没有延迟重启。

验收标准：

- 不再出现主线程调用 `startRunning()` 的诊断；
- 主线程无可感知卡顿；
- 快速启停不会出现黑屏、退出后摄像头仍运行或会话状态错乱；
- 扫码结果及现有重试流程不变。

## 建议实施边界

本次只修改 `LBXScanWrapper` 的会话调度模型，不调整扫码业务流程，不替换第三方扫码 UI，不迁移拍照 API，不新增本地化或 target 配置。
