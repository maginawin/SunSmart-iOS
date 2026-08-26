# App 设备默认 TTL 哨兵值更新实施记录

## 1. 实施结果

本次按确认范围完成后续下发修复，不迁移存量设备：

| 配置项 | 实施结果 |
|---|---|
| Kinetic Proxy Model Publication | 从 App Network Parameters Default TTL 改为固定 `0xFF` |
| EFC Scene Publication | 从 App Network Parameters Default TTL 改为固定 `0xFF` |
| Group Add 路径的 Neighbor Config | 从非零 App Default TTL 改为固定 `0xFF` |
| Battery/AC Power Switch Key Config | 保持 `0xFF`，未修改生产逻辑 |
| EFC Action Config | 保持 `0xFF`，未修改生产逻辑 |
| 通用 Node、Space、EFC 三条 Neighbor 同步路径 | 保持 TTL `0`，未修改 |
| SDK Neighbor 默认参数 | 保持 TTL `0`，未修改 |

没有新增后台扫描、强制同步、迁移标记或 TTL 差异检测。已经写入设备的 TTL `5` 不会因 App 升级自动变化。

## 2. 生产代码改动

### 2.1 本地 NordicSigMeshSDK

- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshEnOceanProxyServer.swift`
  - Kinetic Proxy Model Publication 的 TTL 固定为 `0xFF`。

### 2.2 App

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
  - EFC Scene Publication 的 TTL 固定为 `0xFF`。
  - EFC Action Config 原有 `0xFF` 保持不变。
- `SunSmart/Main/Group/Model/GroupServer.swift`
  - Group Add 路径中原本使用非零 App Default TTL 的 Neighbor Config 改为 `0xFF`。

## 3. 回归保护

### 3.1 App 契约脚本

新增 `scripts/check_device_default_ttl_payloads.sh`，保护以下约束：

- 三个目标构造点固定使用 `0xFF`，不再读取 App Network Parameters Default TTL。
- Battery/AC Key Config 和 EFC Action Config 保持 `0xFF`。
- 三条现有 Neighbor TTL `0` 路径继续为 `0`。
- SDK Neighbor API 默认参数继续为 `0`。

### 3.2 SDK 编码用例

新增 `Tests/NordicSigMeshSDKTests/ProximityLightingVendorMessageTests.swift`，覆盖 Neighbor Config：

- TTL `0` 的 payload 编码。
- TTL `0xFF` 的 payload 编码。

## 4. 自动验证结果

| 验证项 | 结果 |
|---|---|
| Device Default TTL payload 契约 | 通过 |
| EFC controller flow 契约 | 通过 |
| App `git diff --check` | 通过 |
| SDK `git diff --check` | 通过 |
| `SunSmart` Debug iphoneos 通用目标构建 | 通过 |
| `Archipelago` Debug iphoneos 通用目标构建 | 通过 |
| `SLG Sync Plus` Debug iphoneos 通用目标构建 | 通过 |
| `SylSmart` Debug iphoneos 通用目标构建 | 通过 |
| SDK `swift test` | 未执行到用例；SwiftPM 在 macOS 平台编译 SDK 时因依赖 `UIKit` 失败 |

`swift test` 的失败发生在 SDK module 编译阶段，错误为 macOS 环境不存在 `UIKit`，不是本次新增测试或 TTL 生产代码的编译错误。四个 iphoneos 构建均已成功编译本地 SDK 和 App 生产代码。

构建日志中存在项目原有警告，例如重复 Asset Symbol、废弃 API 和未使用局部变量；本次没有处理这些无关警告。

## 5. 验收边界

当前已证明：

- 源码中的后续下发值符合约定。
- TTL `0` 业务路径受到契约保护。
- 本地 SDK 和四品牌 App 生产代码可通过 iphoneos 编译与链接。

当前尚未证明：

- 真机实际收到的三类配置 payload 均为预期值。
- 设备使用其他工具设置 Default TTL 后，Kinetic/EFC/Neighbor 实际发包跳数随之变化。
- TTL `0` 的 Neighbor 业务在真机上仍保持仅直达行为。

以上需要通过抓包、设备日志和真实 Mesh 网络验收。

## 6. 工作区说明

App 工作区在本任务开始前已有以下用户改动，本次未修改或清理：

- `scripts/check_lab_light_group_ttl.sh`
- 既有 TTL 分析与实施文档

本次没有提交、推送或调整 Git 分支。
