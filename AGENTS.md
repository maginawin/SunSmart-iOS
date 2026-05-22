## 项目简介

- 这是一个 iOS 智能照明/蓝牙 Mesh 控制应用工程，主 workspace 为 `SunSmart.xcworkspace`，主工程为 `SunSmart.xcodeproj`。
- 工程包含多个品牌 target：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`，共享 Common 抽象 target 与部分通用业务代码。
- 主要代码位于 `SunSmart/`，以 Swift 为主，包含少量 Objective-C 第三方或历史组件；品牌资源和启动页分别位于 `Archipelago/`、`SLGSync/`、`SylSmart/` 等目录。
- 依赖管理同时使用 CocoaPods 和 Swift Package。CocoaPods 依赖见 `Podfile`，Swift Package 中包含 `NordicSigMeshSDK`。
- 业务重点包含设备添加、Mesh 网络、网关、开关、应急/消防设备等智能设备控制功能。

## SDK Notes

- `NordicSigMeshSDK` 的本地开发路径是 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- 当前工程中 `NordicSigMeshSDK` 作为 Swift Package 被多个 target 引用，默认远程地址为 `https://gitee.com/sunricher-i-os/nordic-sig-mesh-sdk.git`。
- 需要修改 SDK 开发功能时，应先将工程中的 SDK 依赖切换为上述本地路径引用，再在本地 SDK 仓库中修改和验证。
- 修改 SDK 相关功能后，需要检查所有引用 `NordicSigMeshSDK` 的 target 是否仍能正常编译与运行。

## Code Notes

- 所有回复和 Markdown 文件、计划文档应使用**简体中文**，但文档中的 UI 原型、流程图中的内容使用**英文**。
- 重要分析和计划需要保存到 `docs/`，使用 Markdown 文件，命名格式为 `yyMMdd_HHmm_[description].md`。
  - 注意当前年份是 2026 年。
- 不处理 `user-temp/` 文件夹。
- 除非明确要求，不要在回复中包含代码。
- Git commit 中不要添加 `codex` 相关行。
- 写代码时不需要增加 Auth 信息。
- 保持改动聚焦，不要顺手重构无关模块或格式化大量无关文件。
- 修改本地化、资源、target 配置或 Pod 依赖时，同步检查相关 target 是否受影响。

## Figma Notes

- 当用户提供 `figma.com` 链接时，优先使用 Figma plugin / Figma connector 读取该链接对应的结构化 design context，包括 frame/layer 层级、组件、文本、颜色、字体、尺寸、间距、圆角、Auto Layout、变量等信息。
- 不要把 Figma 链接当作普通网页或截图来分析；不要通过截图、OCR 或视觉猜测来还原 UI。
- 只有在用户明确提供截图、图片，或 Figma plugin 无法读取设计内容时，才使用图片分析作为辅助方案。
- 根据 Figma 结构化信息实现 UI 时，优先复用当前项目已有的组件、主题、颜色、字体、尺寸、资源和代码风格。
- 如果 Figma 设计与现有项目组件存在差异，先说明差异，再选择最小改动方案实现。

## iOS build command policy

When verifying SunSmart iOS builds, run xcodebuild directly without wrapping it in `/bin/zsh -lc` and without shell redirection.

Preferred command:

xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

Do not use:
- /bin/zsh -lc "xcodebuild ..."
- bash -lc "xcodebuild ..."
- output redirection such as `> /tmp/*.log 2>&1`

If logs are needed, rely on Codex command output first.
