# BackgroundTimer 崩溃根因记录

## 背景

在 `Site - Space - More - Device Parameter Settings - 2.Parameter selection` 中滑动 `Absolute CCT Range` 的 max slider 时，App 崩溃在本地 `NordicSigMeshSDK` 的：

`BackgroundTimer.init(withTimeInterval:repeats:queue:block:)`

崩溃点为一次性 timer 的 event handler 执行完业务 block 后调用 `self.invalidate()`。

## 现象

Xcode 日志中同时出现 Mesh acknowledged message timeout 和 cancel：

- `Response to Access PDU ... not received (timeout)`
- `Cancelling messages with op code ...`

这说明崩溃不是 slider 布局本身导致。slider 滑动只更新本地 `DeviceParameterCctRangeData`；后台 Mesh 层此时已有 acknowledged request timeout，timeout timer 触发后进入取消链路。

## 根因

`BackgroundTimer` 的一次性 timer 在 event handler 中会自动执行：

1. `block(self)`
2. `self.invalidate()`

而 `AccessLayer.AcknowledgmentContext` 的 timeout block 内部也会调用 `invalidate()`，取消同一个 `BackgroundTimer`。

因此 timeout 触发路径存在同一个 dispatch source 在回调执行期间被取消，回调返回后又被二次取消的情况。崩溃栈落在第二次 `self.invalidate()`。

## 修复

在 `BackgroundTimer` 内增加锁和 `valid` 状态：

- `invalidate()` 改为幂等，只有第一次调用会真正清空 handler 并 cancel dispatch source。
- `deinit` 复用 `invalidate()`，避免重复取消逻辑分叉。
- `fireDate(delay:)` 对已失效 timer 直接返回，避免重排已取消的 dispatch source。

这个修复不改变 `BackgroundTimer` 的公开 API，也保留现有行为：未保存返回值的一次性 timer 仍可依赖 handler 对 `self` 的强捕获直到触发。

## 验证

已执行 SunSmart iOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

结果：`BUILD SUCCEEDED`

补充：尝试执行 `swift test --filter BackgroundTimerTests/testNonRepeatingTimerCanBeInvalidatedFromItsOwnHandler` 时，当前 SDK Package 在 macOS 测试环境下因已有源码 `import UIKit` 报 `no such module 'UIKit'`，无法作为本仓库的有效测试入口。
