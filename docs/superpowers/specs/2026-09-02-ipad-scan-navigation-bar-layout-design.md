# 独立全屏扫码页修复设计

## 目标

项目列表页和动能开关页不再把 `LBXScanViewController` push 到当前业务导航控制器，而是直接以 `.fullScreen` modal 展示。扫码页可以继续隐藏状态栏，但状态栏和顶部 safe area 的变化只属于独立 modal，不再改变底层业务导航栏的布局。

## 最小设计

- 两个现有扫码入口直接 `present` 同一个 `LBXScanViewController`，并设置 `modalPresentationStyle = .fullScreen`；扫码页已有自定义返回按钮，不额外包装导航控制器。
- 扫码页恢复 `prefersStatusBarHidden = true` 和原有返回按钮位置，撤回“状态栏始终显示”的试验样式。
- 扫码控制器提供统一退出方法：modal 场景执行 `dismiss`，保留 push 场景的 `pop` 兜底。
- 自定义返回按钮和 `scanFineshedExit` 都使用统一退出方法。
- 业务页扫码失败时继续调用 `startScan()`；需要离开扫码页并继续跳转或绑定时，先关闭 modal，再执行原有后续操作。
- 不修改相机权限、扫码识别、相册选择、数据请求或业务判断。

## 风险与验收

- modal 关闭和后续 push/present 必须串行执行，避免两个转场同时发生。
- 本轮不执行 Xcode、模拟器或真机验证；源码级检查不代表 UI 已验收。
- 用户重点验证 iPad 立即返回、相机启动后返回、扫码成功后的业务跳转，以及 iPhone 回归效果。

