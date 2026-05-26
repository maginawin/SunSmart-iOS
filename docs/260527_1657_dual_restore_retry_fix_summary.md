# 双设备恢复同步失败修复说明

## 背景

双设备同时恢复时，日志显示 `02A0` 在 deferred restore 阶段的 `ConfigModelPublicationSet` 被命令层判定为未响应：

`failed=ConfigModelPublicationSet@02A0[responded=,missing=02A0]`

该失败发生在 Proxy/GATT 重连和白名单配置窗口附近。后续 `02A0` 仍能正常完成 LightLC、Vendor、Scene、CTL 等配置，因此这不是设备离线或云同步失败，而是恢复阶段单个配置命令的一次 missed response。

## 本次改动

文件：

- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

改动内容：

- 为普通 deferred restore task 增加一次性失败重试。
- 仅对未被 `DeferredRestoreResponseTracker` 证明成功的失败 handles 重试，且这些 handles 必须全部满足以下条件：
  - 消息是 acknowledged message
  - 不是 `SceneRecall`
  - 不是 battery power switch 专项恢复配置 message
  - handle 有 missing/notRespond address
- 重试前只清空失败 handles 的 `respondAddresss` 和 `notRespondAddresss`，避免旧失败状态导致重试回包无法匹配。
- 延迟 1.5 秒后只重发失败 handles，不重复发送已经成功的 handles。
- 重试仍失败时，保持原逻辑：更新本地数据为失败，并最终标记 `syncFailed`。

## 预期效果

当两个设备同时恢复且普通 deferred restore 命令撞上连接重建窗口时，恢复流程不会立即把设备标记同步失败，而是给失败命令一次重试机会。

如果重试成功：

- 不再触发 `Mark sync failed ... deferred task failed`
- 对应 node sync 状态会被清除
- 后续任务继续执行

如果重试仍失败：

- 仍会走原有失败路径
- 不隐藏真实配置失败

## 验证

已执行：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

`xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

`xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

`xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

结果：

- 四个品牌 target 均 `BUILD SUCCEEDED`
- 构建中仅出现项目已有 warning，未出现本次改动相关错误

补充：

- 当前 App workspace 没有独立 XCTest target，因此没有新增 App 单元测试。
- SDK SwiftPM 测试入口存在，但该包在本地 macOS `swift test` 环境会因 iOS-only UIKit 依赖受限，历史验证同样使用 iOS build 覆盖编译链路。
