# WiFi Firmware Current Version 失败时展示 latest 固件设计

## 1. 背景

WiFi Gateway 的 WiFi Firmware Update 页面同时加载两个独立数据源：

- 云端 latest firmware：通过 `/sitespace/ota/latest` 获取；
- 网关 Current version：通过 SIG Mesh `43 14` 实时查询。

用户通过 Beta Testing 输入 `1314` 后，dev latest 请求已成功返回 `v0.4.0`，但页面没有展示固件详情。代码核查确认，服务端响应和解析均成功，问题位于页面状态派生逻辑。

当前父页面使用 `isNewServerFirmwareAvailable(_:)` 同时决定：

1. 是否展示云端固件详情；
2. 是否启用 `UPGRADE`。

WiFi 页面在 Current version 查询失败时无法比较版本，因此该方法返回 false。父页面随即把它当成“已是最新版本”，隐藏云端固件详情。失败态的后置处理只显示 Refresh 并禁用按钮，没有恢复固件详情。

## 2. 目标

- 云端 latest firmware 请求成功时，即使 Current version 为 `Failed`，仍展示云端固件详情。
- Current version 为 `Failed` 时，`UPGRADE` 必须保持禁用。
- Current version 有效时，继续仅在 New version 严格高于 Current version 时启用 `UPGRADE`。
- 保留 Refresh 同时重试云端 latest firmware 和 Current version 的现有行为。
- 保持 BLE/Mesh 固件页面行为不变。

## 3. 非目标

本次不包含：

- 修改 NordicSigMeshSDK 或 `43 14` 协议；
- 修改 latest firmware 接口、请求参数或响应模型；
- 改变 Beta Testing `1314` 入口；
- 实现真实 WiFi DFU；
- 修改 `43 10` start WiFi DFU 或 `43 11` status 的 App 功能；
- 改变 Current version 为 `Loading...` 时的固件详情展示策略；
- 修改 UI 布局、页面文案或本地化文件；
- 重构其它 Gateway 或 Firmware 页面。

## 4. 设计原则

页面需要分别回答两个问题：

- 云端 latest firmware 的信息是否应该展示；
- 当前是否具备安全的升级资格。

第一个问题属于信息展示，第二个问题属于操作权限。Current version 查询失败只会使升级资格未知，不应使已经成功取得的云端数据消失。

## 5. 方案

### 5.1 父页面增加窄扩展点

在 `FirmwareVersionViewController` 中增加两个方法：

- `shouldShowServerFirmwareDetails(_:)`
  - 输入：当前 `FirmwareServerData`；
  - 输出：是否展示云端固件详情区域；
  - 默认实现：调用现有 `isNewServerFirmwareAvailable(_:)`。
- `isFirmwarePrimaryActionEnabled(_:)`
  - 输入：当前 `FirmwareServerData`；
  - 输出：是否启用主按钮；
  - 默认实现：调用现有 `isNewServerFirmwareAvailable(_:)`。

默认实现使 BLE/Mesh 固件页面继续保持现有行为：只有发现更高版本时展示固件详情并启用 `Download`。

现有 `isNewServerFirmwareAvailable(_:)` 保留为纯粹的版本比较能力，不再隐含“是否展示”的唯一含义。

### 5.2 父页面渲染逻辑

当 `type.serverData` 有效时：

1. 使用 `shouldShowServerFirmwareDetails(_:)` 决定固件详情区域是否可见及 Current version 卡片约束。
2. 使用 `isFirmwarePrimaryActionEnabled(_:)` 独立决定主按钮状态。
3. 详情可见时继续复用现有版本、大小、发布日期和描述渲染，不改变格式。
4. 详情不可见时继续复用现有“已是最新版本”状态。

当 `requiresAdditionalFirmwareReload == true` 时，现有失败态后置规则继续生效：

- 隐藏顶部状态文字；
- 显示 Refresh；
- 强制禁用主按钮。

该后置规则不再覆盖固件详情区域的可见性。

### 5.3 WiFi 页面覆盖规则

`WiFiFirmwareUpdateViewController` 覆盖 `shouldShowServerFirmwareDetails(_:)`：

- Current version 为 `.failed`：返回 true；
- 其它状态：返回 `isNewServerFirmwareAvailable(_:)` 的结果。

WiFi 页面不放宽主按钮规则。`isFirmwarePrimaryActionEnabled(_:)` 继续使用父页面默认实现，而 WiFi 已有的 `isNewServerFirmwareAvailable(_:)` 仍要求：

1. Current version 必须为 loaded；
2. New version 与 Current version 均能完成现有规范化；
3. 去掉最多一个前导 `v/V` 后，New version 按 `.numeric` 比较严格高于 Current version。

因此 Current version 为 loading 或 failed 时，`UPGRADE` 都不可用。

## 6. 页面状态矩阵

| 云端 latest | Current version | 固件详情 | 顶部状态 / Refresh | UPGRADE |
| --- | --- | --- | --- | --- |
| loading | 任意 | 沿用现有 loading 状态 | 沿用现有状态 | 禁用 |
| valid | loading | 沿用现有行为，本次不扩展 | 沿用现有状态 | 禁用 |
| valid | failed | 展示 | 隐藏顶部状态，显示 Refresh | 禁用 |
| valid | loaded，New > Current | 展示 | `New version found`，隐藏 Refresh | 启用 |
| valid | loaded，New == Current | 隐藏 | `The latest version`，隐藏 Refresh | 禁用 |
| valid | loaded，New < Current | 隐藏 | `The latest version`，隐藏 Refresh | 禁用 |
| failed | 任意 | 显示现有网络错误内容 | 显示 Refresh | 禁用 |
| not found | 任意 | 隐藏 | 沿用现有无固件状态 | 禁用 |

Failed 场景下，详情区域内继续使用现有 `New version` 标题，但顶部不显示 `New version found`，避免声称已经完成版本高低判断。服务端返回的 `v0.4.0` 会按现有解析规则展示为 `0.4.0`。

## 7. 请求时序

云端 latest firmware 和 Current version 查询保持并行，不增加互相等待：

1. 页面进入或点击 Refresh；
2. WiFi 页面清除旧 `serverData`，Current version 重置为 loading；
3. 同时发起云端请求和 Mesh `43 14`；
4. 任一请求返回后按当前两个数据源的最新状态刷新 UI；
5. Current version 最终失败但云端成功时，显示云端详情、Refresh 和禁用的 `UPGRADE`。

现有 `currentVersionRequestID` 继续过滤旧 Mesh 回调，不改变请求超时和错误映射。

## 8. 错误处理

- `43 14` 返回任何非 success、响应类型不匹配、节点离线、未完成 key bind、缺少 Vendor Model 或 App timeout：Current version 进入 failed。
- Current version failed 不清除 `type.serverData`。
- 云端请求失败：沿用现有网络错误和 Refresh 行为。
- 云端未找到固件：沿用现有 noServerFirmware 行为。
- 即使任何前置分支意外计算出可升级，`requiresAdditionalFirmwareReload` 在 failed 状态仍会最终强制禁用按钮，作为安全兜底。

## 9. 修改范围

### `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`

- 新增详情展示与主按钮 enablement 两个默认兼容 hook。
- 在 `updateUI()` 中分别消费两个 hook。
- 不改变现有布局、网络请求、固件下载、history 和 Beta Testing 行为。

### `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`

- Failed 状态覆盖详情展示规则。
- 保持严格版本比较和 Current version 状态机不变。

### `scripts/check_wifi_gateway_firmware_update.sh`

- 增加父页面存在两个独立 hook 的契约。
- 增加 WiFi Failed 状态允许展示详情的契约。
- 增加主按钮仍由严格版本比较控制的契约。
- 保留现有 target、入口、请求身份、Current version 和本地化检查。

## 10. 测试与验证

### 10.1 TDD 契约

先扩展 `scripts/check_wifi_gateway_firmware_update.sh`，使其因缺少独立判定而失败；再完成最小实现使脚本通过。

契约至少覆盖：

- 父页面默认详情和按钮判定均保持现有版本比较行为；
- WiFi 页面仅在 Current version failed 时放宽详情展示；
- WiFi 页面没有绕过严格升级资格；
- failed 后置状态仍强制禁用按钮并显示 Refresh。

### 10.2 回归验证

- 运行 `scripts/check_wifi_gateway_firmware_update.sh`。
- 运行现有 WiFi Gateway 相关静态回归脚本。
- 执行 `git diff --check`。
- 使用 iPhoneOS generic destination 构建：
  - `SunSmart`；
  - `Archipelago`；
  - `SLG Sync Plus`；
  - `SylSmart`。

不使用 Simulator。

## 11. 验收标准

- 输入 `1314` 后，dev latest 请求成功返回 `v0.4.0` 时，页面展示规范化后的 `0.4.0` 及其固件详情。
- Current version 显示 `Failed` 时，固件详情仍可见。
- Current version 显示 `Failed` 时，Refresh 可见且 `UPGRADE` 不可用。
- Current version 成功后，只有 New version 严格高于 Current version 时 `UPGRADE` 可用。
- New version 等于或低于 Current version 时，继续显示现有“已是最新版本”状态。
- BLE/Mesh 固件页面的展示、下载按钮和其它交互不变。
- 不产生 SDK、接口、本地化、target 配置或真实 DFU 行为改动。
