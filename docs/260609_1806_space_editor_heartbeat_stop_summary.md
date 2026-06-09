# Space Editor 心跳停止实施总结

## 改动范围

本次采用 `docs/260609_1755_space_editor_heartbeat_stop_plan.md` 中的方案 A，并补轻量方案 B 兜底。

修改文件：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`
- `SunSmart/Main/Site/Controller/SitesViewController.swift`

## 实现内容

### SpaceViewController

- 新增 `SpacePresenceStopReason`，统一标识停止 Space presence 的原因。
- 新增 `hasStoppedPresenceTracking`，保证停止逻辑幂等，避免离开页面、权限失效、deinit 多路径重复处理。
- 新增 `isHandlingExternalVendorMessages`，只在当前 Space 页面接管过 Mesh vendor delegate 时尝试清理。
- 新增统一停止方法：
  - 停止 `/sitespace/user/hb` 对应的 `heartbeatTimer`。
  - 停止 Mesh 权限探测 `userAskTimer`。
  - 如果 `MeshLibManager.manager.externalVendorMessageDelegate` 仍指向当前 Space 页面，则清空 delegate。
- 在 `viewDidDisappear` 判断当前 Space VC 已被移出导航栈时停止 presence。
- `deinit`、`noSitePermission`、`noSpacePermission/userUnauthorized` 权限失效路径改为复用统一停止方法。
- `startHeartbeatTimer()` 增加 `hasStoppedPresenceTracking` guard，避免已离开 Space 后因网络恢复观察回调重新启动心跳。
- 增加 DEBUG 日志，记录 heartbeat 启动、active editor 冲突、当前会话降级 Visitor、presence 停止原因。

### SitesViewController

- 在 `viewDidAppear` 增加窄兜底：
  - 扫描当前导航栈中异常残留的 `SpaceViewController`。
  - 只调用其 `stopSpacePresenceTrackingForSitesCleanup()`。
  - 不停止设备扫描、RSSI、Gateway、Firmware 等无关 timer。

## 验证

已运行：

`git diff --check`

结果：通过，无空白错误。

已运行：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO -quiet build`

结果：构建通过，命令退出码为 0。

构建输出仍有工程既有 warning，例如 asset symbol 重名、废弃 API、未使用变量、重复 Compile Sources 文件；这些 warning 与本次改动无关。

## 剩余验证建议

建议补一轮双手机手动验证：

1. 手机 A 作为 Owner 进入 Site - Space，确认开始 `/sitespace/user/hb`。
2. 手机 A 从 Space 返回 Site，再返回 Sites。
3. 确认 A 不再继续发送该 Space 的 `/sitespace/user/hb`。
4. 手机 B 以 Editor 权限进入同一 Space。
5. 如果 B 仍被提示 Visitor，抓 `/sitespace/get/activeuser` 确认是否是服务端 active user 过期窗口尚未结束。
