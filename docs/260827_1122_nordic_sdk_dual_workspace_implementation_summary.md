# NordicSigMeshSDK 双 Workspace 实施总结

## 结论

双 workspace 协作框架已完成实施与构建验证：团队共享配置始终使用远程 `release`，个人 App + SDK 联调使用被 Git 忽略的本地 workspace。开发者可以在当前 App worktree 正常提交 App 代码，不再长期保留 `project.pbxproj` 修改或 `Package.resolved` 删除。

## 共享模式

- 入口：`SunSmart.xcworkspace`
- SDK 来源：`git@gitee.com:sunricher-i-os/nordic-sig-mesh-sdk.git`
- Requirement：`release`
- 当前锁定 revision：`9504e5ba7286205f8d4749d8127bf2178b19d9a2`
- 使用者：团队成员与 CI

## 个人联调模式

- 初始化：运行 `scripts/setup_local_nordic_sdk_workspace.sh`
- 入口：`SunSmartLocal.xcworkspace`
- SDK 别名：`.local-sdk/nordic-sig-mesh-sdk`
- SDK 实际目录：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`
- 使用者：需要同时修改 App 和 SDK 的维护者

个人 workspace 和 SDK 别名均被 Git 忽略。初始化脚本不修改共享 project、标准 workspace、Package.resolved、Git 分支或 SDK 仓库。

## 验证结果

- 共享依赖静态检查通过。
- 个人 workspace Package 解析成功，来源为本地 SDK 别名。
- 个人 workspace 的 SunSmart generic iPhoneOS Debug 无签名构建成功。
- 标准 workspace Package 解析成功，来源为 Gitee `release @ 9504e5b`。
- 标准 workspace 四品牌 generic iPhoneOS Debug 无签名构建成功。
- 构建验证不等同于真实 BLE、Mesh、固件、服务器或 UI 验收。

## 方法依据

Apple 官方支持以同名本地 Package 覆盖已发布远程 dependency，用于 App 与 Package 联调。双 workspace 是基于该机制增加的本地状态隔离层，用来满足当前多 Target、CocoaPods workspace 和团队只读 SDK 的协作边界。

- [Developing a Swift package in tandem with an app](https://developer.apple.com/documentation/xcode/developing-a-swift-package-in-tandem-with-an-app)
- [Editing a package dependency as a local package](https://developer.apple.com/documentation/xcode/editing-a-package-dependency-as-a-local-package)
