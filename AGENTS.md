## 项目简介

- 这是一个 iOS 智能照明/蓝牙 Mesh 控制应用工程，主 workspace 为 `SunSmart.xcworkspace`，主工程为 `SunSmart.xcodeproj`。
- 工程包含多个品牌 target：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`，共享 Common 抽象 target 与部分通用业务代码。
- 主要代码位于 `SunSmart/`，以 Swift 为主，包含少量 Objective-C 第三方或历史组件；品牌资源和启动页分别位于 `Archipelago/`、`SLGSync/`、`SylSmart/` 等目录。
- 依赖管理同时使用 CocoaPods 和 Swift Package。CocoaPods 依赖见 `Podfile`，Swift Package 中包含 `NordicSigMeshSDK`。
- 业务重点包含设备添加、Mesh 网络、网关、开关、应急/消防设备等智能设备控制功能。
- 项目的 Author 是 `One`。

## SDK Notes

- `NordicSigMeshSDK` 的本地开发路径是 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- 当前工程中 `NordicSigMeshSDK` 作为 Swift Package 被多个 target 引用，默认远程地址为 `https://gitee.com/sunricher-i-os/nordic-sig-mesh-sdk.git`。
- 需要修改 SDK 开发功能时，应先将工程中的 SDK 依赖切换为上述本地路径引用，再在本地 SDK 仓库中修改和验证。
- 修改 SDK 相关功能后，需要检查所有引用 `NordicSigMeshSDK` 的 target 是否仍能正常编译与运行。

## 国际化要求

* 所有新增或修改的用户可见文案均需支持国际化。
* 当前支持语言：
    * English（默认）
    * 简体中文（zh-CN）
* 优先复用现有国际化 Key。
* 如不存在合适的 Key，则新增，并同步补充所有已支持语言的翻译。
* 禁止硬编码用户可见文案。
