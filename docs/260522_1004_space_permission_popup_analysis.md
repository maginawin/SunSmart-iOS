# Space Permission Popup Analysis

## 现象

删除某个 Site/Space 后，切换到另一个 Site 时仍可能弹出：

`You have been cleared of visitor permissions and can no longer use the space.`

## 定位结论

该完整文案由 `the_space_cleared_visitor_message` 提供，只在 `SpaceViewController.heartbeatRequest()` 的心跳失败分支中弹出。

触发条件是当前 `SpaceViewController` 对其持有的 `space.siteId`、`space.id`、`space.permission` 发送 `heartbeat` 后，服务端返回以下错误之一：

- `4009`：`noSpacePermission`
- `4010`：`userUnauthorized`

这通常表示当前账号已经不再拥有该 Space 的权限，例如：

- Owner/Editor 清除了当前账号的 Visitor 权限
- Space 被删除或解绑，服务端侧成员关系失效
- 本地仍保留旧 Space 数据，但服务端已经没有对应授权

## 和“切换另一个 Site”相关的原因

`SpaceViewController` 的心跳在进入云端 Space 后启动，启动后会立即执行一次，之后每 30 秒执行一次。心跳只在 `deinit` 中停止，`viewWillDisappear` 不停止心跳。

因此如果旧的 `SpaceViewController` 仍在导航栈或尚未释放，它仍会用旧 Space 的 ID 继续发送心跳。旧 Space 刚被删除或权限被清掉后，服务端返回 `4009/4010`，弹窗就会出现在当前界面上，看起来像是“切换到另一个 Site 后弹出”。

## 代码位置

- 文案：`SunSmart/en.lproj/Localizable.strings`
- 心跳启动：`SunSmart/Main/Space/Controller/SpaceViewController.swift`
- 弹窗分支：`SpaceViewController.heartbeatRequest()`
- 错误码映射：`SunSmart/Common/Network/NetworkRequest.swift`
