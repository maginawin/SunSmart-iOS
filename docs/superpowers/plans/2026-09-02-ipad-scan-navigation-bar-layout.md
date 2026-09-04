# 独立 Full-Screen 扫码页实施计划

**目标：** 用独立 `.fullScreen` modal 隔离扫码页的状态栏变化，并保持原有扫码业务行为。

**架构：** `LBXScanViewController` 直接作为 full-screen modal 展示，通过统一退出方法兼容 modal dismiss 和旧 push/pop；调用页在退出完成后继续原有跳转。

**技术栈：** Swift、UIKit、AVFoundation、现有轻量源码契约。

## 全局约束

- 只修改共享扫码控制器、两个现有入口及对应退出点。
- 不增加设备或系统版本分支，不改业务文案和扫码逻辑。
- 不执行 Xcode、模拟器或真机验证，不提交、不暂存、不推送。

## 实施步骤

- [x] 先将契约改为要求两个入口使用 `.fullScreen` modal、扫码页保持隐藏状态栏并通过统一方法退出。
- [x] 运行契约确认旧 push 实现不满足新要求。
- [x] 恢复扫码页隐藏状态栏和原有返回按钮位置，增加 modal dismiss / push pop 兼容退出方法。
- [x] 将项目导入和动能开关扫码入口改为直接 full-screen present。
- [x] 将扫码成功后的退出点改为先 dismiss，再执行原有 push、present 或绑定回调。
- [x] 仅运行轻量源码契约并检查目标 diff；真实 UI 由用户真机验收。
