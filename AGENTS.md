## 项目简介

- 这是一个 iOS 智能照明/蓝牙 Mesh 控制应用工程，主 workspace 为 `SunSmart.xcworkspace`，主工程为 `SunSmart.xcodeproj`。
- 工程包含多个品牌 target：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 等，共享 Common 抽象 target 与部分通用业务代码。
- 主要代码位于 `SunSmart/`，以 Swift 为主，包含少量 Objective-C 第三方或历史组件；品牌资源和启动页分别位于 `Archipelago/`、`SLGSync/`、`SylSmart/` 等目录。
- 依赖管理同时使用 CocoaPods 和 Swift Package。CocoaPods 依赖见 `Podfile`，Swift Package 中包含 `NordicSigMeshSDK`。
- 业务重点包含设备添加、Mesh 网络、网关、开关、应急/消防设备等智能设备控制功能。

## SDK Notes

- `NordicSigMeshSDK` 的本地开发路径是 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
  
- 当前工程中 `NordicSigMeshSDK` 作为 Swift Package 被多个 target 引用，默认远程地址为 `git@gitee.com:sunricher-i-os/nordic-sig-mesh-sdk.git` 中的 `release` 分支。
- 需要修改 SDK 开发功能时，应先判断本地 SDK 开发路径是否存在，若存在就继续开发，若本地不存在此路径，则终止修改 SDK 的行为并提示用户。
- 修改 SDK 相关功能后，需要检查所有引用 `NordicSigMeshSDK` 的 target 是否仍能正常编译与运行。

## 国际化要求

* 所有新增或修改的用户可见文案均需支持国际化。
* 当前支持语言：
    * English（默认）
    * 简体中文（zh-CN）
* 优先复用现有国际化 Key。
* 如不存在合适的 Key，则新增，并同步补充所有已支持语言的翻译。
* 禁止硬编码用户可见文案。

## 开发要求

* 打印 Log 则必须包含在 `#if DEBUG` 和 `#endif` 内

### UI 验证规则

- UI 改动须检查受影响页面的布局约束及适配，并实际运行验证；编译和静态检查不能替代布局验证。
- 允许使用真机 `MtestiPhone15` 自查 UI，其他个人设备默认由人工操作；重复流程优先使用已有自动化测试。
- 验证范围与改动风险匹配；涉及硬件、系统交互或性能时须做相关真机验证，避免小改动触发全量回归。
- 最终体验由人工确认，不得仅凭构建成功或截图正常宣称 UI 验收通过。
- 验证受阻时避免反复尝试，明确已验证项、未验证项及人工检查步骤。
- 禁止使用 `Computer Use` 控制电脑