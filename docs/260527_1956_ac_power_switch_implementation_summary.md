# AC Power Switch 实现总结

## 范围

- 新增 AC Power Switch 设备族识别，支持 `0x2A11` 场景面板与 `0x2A12` 亮度面板。
- 在 8-key Power Switch 共享模型中持久化 `powerSwitchKind`，旧数据默认 Battery。
- 添加 Switches 弹窗中的 AC Power Switch 入口，并保存未绑定虚拟 AC 开关。
- 绑定与恢复流程按 Battery / AC kind 精确匹配，AC 只允许绑定 AC PID。
- AC 与 Battery 共用现有 switch 数量上限。
- AC 添加成功后跳过初始电量读取与主动断开 Proxy。
- AC 保存、同步重试、启用/禁用不等待设备激活。
- AC 监控页顶部显示 `Unlinked`、`Online` 或 `Offline`，不显示电池控件。

## 验证

- `jq empty SunSmart/devices_config.json`
- `plutil -lint SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings`
- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 备注

- 首次构建失败原因是当前 worktree 缺少 CocoaPods 生成的 `Pods-Common-SunSmart` 支持文件。执行 `pod install` 后补齐 ignored 文件，重新构建通过。
- `protocols/` 下的 AC 协议文件保持未跟踪，未纳入实现提交。
