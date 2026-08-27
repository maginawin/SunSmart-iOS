# SunSmart iOS

SunSmart 是一款面向智能照明和 Bluetooth Mesh 设备的 iOS 应用。项目支持设备添加与控制、Mesh 网络管理、场景与定时任务、网关以及开关、应急照明等设备功能。

工程包含以下品牌 Target，并复用 `Common` 中的通用业务代码：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

项目主要使用 Swift 开发，最低支持 iOS 15.0。第三方依赖同时通过 CocoaPods 和 Swift Package Manager 管理，其中 Mesh 能力由 `NordicSigMeshSDK` 提供。

## 工程结构

- `SunSmart.xcworkspace`：共享 Workspace，供常规开发和构建使用。
- `SunSmart.xcodeproj`：主 Xcode 工程。
- `SunSmart/`：主要业务代码和 SunSmart 品牌资源。
- `Archipelago/`、`SLGSync/`、`SylSmart/`：各品牌资源与配置。
- `Config/`：通用及品牌构建配置。
- `Tests/`：项目测试与协议契约检查。
- `protocols/`：设备协议资料。
- `scripts/`：开发和验证脚本。

## 开始开发

安装 CocoaPods 依赖：

```bash
pod install
```

随后使用 Xcode 打开共享 Workspace：

```bash
open SunSmart.xcworkspace
```

在 Xcode 中选择需要开发的品牌 Scheme 和目标设备后运行。

## 使用本地 NordicSigMeshSDK

需要同时开发 App 和 `NordicSigMeshSDK` 时，运行：

```bash
scripts/setup_local_nordic_sdk_workspace.sh
```

脚本默认使用以下 SDK Git worktree：

```text
../../nordic-sig-mesh-sdk-worktrees/one-dev
```

也可以通过第一个参数指定 SDK 路径：

```bash
scripts/setup_local_nordic_sdk_workspace.sh /path/to/nordic-sig-mesh-sdk
```

或通过环境变量指定：

```bash
NORDIC_SIG_MESH_SDK_ROOT=/path/to/nordic-sig-mesh-sdk \
  scripts/setup_local_nordic_sdk_workspace.sh
```

路径优先级为：命令行参数、`NORDIC_SIG_MESH_SDK_ROOT`、默认路径。指定目录必须包含 `Package.swift`，并且必须是 Git worktree。

脚本执行时会：

1. 校验共享工程仍使用远程 `NordicSigMeshSDK` 的 `release` 分支，避免本地路径进入共享配置。
2. 在 `.local-sdk/nordic-sig-mesh-sdk` 创建指向本地 SDK 的符号链接。
3. 生成 `SunSmartLocal.xcworkspace`，组合 App 工程、Pods 工程和本地 SDK Package。
4. 输出本地 SDK 的实际路径、当前分支和 HEAD commit。

完成后使用以下命令打开本地开发 Workspace：

```bash
open SunSmartLocal.xcworkspace
```

`.local-sdk/` 和 `SunSmartLocal.xcworkspace/` 已被 Git 忽略，不会影响其他开发者使用共享的远程 SDK 配置。脚本不会执行 `pod install`；如果本地尚未生成 `Pods/Pods.xcodeproj`，请先安装 CocoaPods 依赖。

如果已有 SDK 符号链接指向其他目录，脚本会停止并提示错误。确认旧链接不再需要后，可手动移除 `.local-sdk/nordic-sig-mesh-sdk`，再重新运行脚本。
