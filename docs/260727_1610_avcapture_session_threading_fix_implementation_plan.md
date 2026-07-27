# AVCaptureSession 线程警告修复实施计划

> **执行方式：** 使用 `superpowers:executing-plans` 在当前会话内逐项执行与检查，不使用 subagents。

**目标：** 消除 `LBXScanWrapper` 在主线程同步启动和停止 `AVCaptureSession` 的问题，同时保持现有扫码 UI、扫码结果和重试流程不变。

**架构：** `LBXScanWrapper` 拥有一个实例级专用串行队列。调用方仍在主线程管理 UI 和扫描结果开关，但捕获会话的运行状态判断、启动和停止全部由该串行队列顺序执行。

**技术栈：** Swift、UIKit、AVFoundation、Dispatch、standalone Swift contract test、Xcode generic iPhoneOS build。

## 全局约束

- 只修改扫码会话调度，不调整扫码业务流程。
- 不迁移 `AVCaptureStillImageOutput`。
- 不修改用户可见文案、本地化、资源或依赖。
- 不新增 Auth 信息。
- 不格式化或重构无关代码。
- 保留当前脏 worktree 中的所有既有修改。
- 不执行 Git commit、push、merge 或 PR 操作。

---

### Task 1：建立线程调度回归契约

**文件：**

- 新增：`Tests/Thirdparty/LBXScanWrapperThreadingContractTests.swift`

**契约：**

- `LBXScanWrapper` 必须拥有专用串行 session queue。
- `start()` 中的 `isRunning` 判断和 `startRunning()` 必须位于该队列提交的工作块内。
- `stop()` 中的 `isRunning` 判断和 `stopRunning()` 必须位于同一个队列提交的工作块内。
- 禁止用全局并发队列替代专用串行队列。

- [ ] 新增 standalone Swift contract test，读取 `LBXScanWrapper.swift` 并验证上述结构约束。
- [ ] 编译并运行测试，确认它因当前缺少 session queue 而按预期失败。

### Task 2：实施最小线程调度修复

**文件：**

- 修改：`SunSmart/Thirdparty/ScanQRCode/LBXScanWrapper.swift`

**行为：**

- `start()` 被调用时及时恢复扫描结果处理，然后异步提交捕获会话启动。
- `stop()` 被调用时及时禁止扫描结果处理，然后异步提交捕获会话停止。
- 启动、停止及各自的 `isRunning` 判断在同一个串行队列内执行，保证快速启停顺序。
- 现有 metadata delegate 继续使用主队列，预览层和 UI 不改变。

- [ ] 新增一个带 `.userInitiated` QoS 的实例级专用串行队列。
- [ ] 将启动状态判断和 `startRunning()` 一起移动到串行队列。
- [ ] 将停止状态判断和 `stopRunning()` 一起移动到同一串行队列。
- [ ] 不改变 `successBlock`、连续扫码、拍照或手电筒路径。
- [ ] 重新运行 focused contract test，确认转为通过。

### Task 3：静态与多 target 编译验证

**文件：**

- 验证：`SunSmart/Thirdparty/ScanQRCode/LBXScanWrapper.swift`
- 验证：`Tests/Thirdparty/LBXScanWrapperThreadingContractTests.swift`

- [ ] 运行 `git diff --check`，确认本次文件没有空白错误。
- [ ] 检查 scoped diff，确认没有覆盖 worktree 既有修改。
- [ ] 运行 SunSmart generic iPhoneOS Debug build。
- [ ] 运行 Archipelago generic iPhoneOS Debug build。
- [ ] 运行 `SLG Sync Plus` generic iPhoneOS Debug build。
- [ ] 运行 SylSmart generic iPhoneOS Debug build。

### Task 4：记录结果与真机验收边界

**文件：**

- 新增：`docs/260727_1610_avcapture_session_threading_fix_summary.md`

- [ ] 记录 RED、GREEN、diff check 和四个 target 的实际结果。
- [ ] 明确编译成功不能证明 Thread Performance Checker 诊断消失。
- [ ] 保留真机验收清单：首次进入、退出重进、无效二维码恢复、快速进入退出、连续启停以及退出后摄像头停止。
