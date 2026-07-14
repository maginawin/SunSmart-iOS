# WiFi Firmware Current Version 失败时未展示云端固件分析

## 1. 结论

问题真实存在，且服务端没有异常。

日志已经证明 Beta Testing `1314` 流程成功请求 dev profile，服务端返回 HTTP 200、业务码 200，并携带 WiFi Gateway 固件 `v0.4.0`。固件没有展示，是 App 将以下两个不同问题绑定到了同一个布尔值：

1. 云端 latest 固件是否应该展示；
2. 当前是否满足升级条件。

当 `Current version = Failed` 时，App 无法执行版本比较，因此升级条件为 false。父页面同时把该 false 当作“已是最新版本”，隐藏了云端固件详情。这与预期“仍展示 latest 固件，但禁用 UPGRADE”不一致。

## 2. 现有数据链

1. 用户通过云图标连续点击进入 Beta Testing，并输入 `1314`。
2. `FirmwareVersionViewController.showTestingAlert()` 将 `isTesting` 设为 true，重新请求 latest firmware。
3. 请求参数为 `manufacturerId=0A78`、`deviceType=2721`、`customerId=wifi`、`profile=dev`。
4. 服务端成功返回 `version=v0.4.0` 等完整数据。
5. App 将版本去除 `v` 后构造 `FirmwareServerData(version: "0.4.0", ...)`，写入 `type.serverData`。
6. `updateUI()` 调用 WiFi 子类的 `isNewServerFirmwareAvailable(_:)`。
7. Current version 查询失败时，`displayedCurrentTargetVersion` 为 nil，`isNewServerFirmwareAvailable(_:)` 返回 false。
8. 父页面进入“已是最新版本”分支，隐藏 `versionScrollView` 并禁用按钮。
9. `requiresAdditionalFirmwareReload` 随后只显示 Refresh、隐藏 header 状态、禁用按钮，没有恢复固件详情区域。

因此，无论云端请求和 Current version 查询谁先返回，只要 Current version 最终为 Failed，云端 latest 固件都会被隐藏。

## 3. 需求边界

本次修复后的状态应为：

| 云端 latest 固件 | Current version | latest 固件详情 | Refresh | UPGRADE |
| --- | --- | --- | --- | --- |
| 成功 | Failed | 展示 | 展示 | 禁用 |
| 成功 | Loading... | 保持现有行为，本次不扩展 | 保持现有行为 | 禁用 |
| 成功 | 成功，New > Current | 展示 | 隐藏 | 启用 |
| 成功 | 成功，New <= Current | 隐藏，显示已是最新版本 | 隐藏 | 禁用 |
| 失败 | 任意 | 沿用现有网络错误状态 | 展示 | 禁用 |
| 未找到 | 任意 | 沿用现有无固件状态 | 按现有规则 | 禁用 |

关键规则：

- `Current version = Failed` 只表示本次无法判断升级资格，不应抹掉已经成功获得的云端 latest 固件。
- `UPGRADE` 仍必须依赖有效的 Current version，并且仅在 New version 严格高于 Current version 时启用。
- Refresh 继续同时重试云端 latest 固件与 Mesh `43 14` Current version。
- 不改变 `43 14` 协议、SDK、云端接口、Beta Testing 入口和真实 WiFi DFU 行为。

## 4. 方案比较

### 方案 A：拆分展示判定与升级判定（推荐）

在共享父页面增加窄扩展点，分别回答：

- 是否展示云端固件详情；
- 是否启用主按钮。

父页面默认让两个判定都沿用当前 `isNewServerFirmwareAvailable(_:)`，因此 BLE/Mesh 页面行为不变。WiFi 子类仅在 `Current version = Failed` 且云端数据有效时覆盖展示判定为 true；升级判定仍使用严格版本比较。

优点：语义清晰，直接修复耦合根因；改动聚焦；后续接入真实 WiFi DFU 时仍可复用。缺点：父页面增加两个很小的 hook。

### 方案 B：在父页面失败态末尾强制恢复固件详情

当 `requiresAdditionalFirmwareReload == true` 且 `serverData != nil` 时，直接把 `versionScrollView` 改回可见并重做约束。

优点：改动行数较少。缺点：UI 状态继续散落在多个分支，同一状态可能被前后覆盖；没有解决“展示”和“升级”的概念耦合，后续更容易回归。

### 方案 C：WiFi 页面复制一套独立渲染逻辑

让 WiFi 子类自行维护完整云端详情、Current version、Refresh 和按钮状态。

优点：与 BLE/Mesh 页面彻底隔离。缺点：重复布局和渲染逻辑，改动大，不符合当前窄继承设计，也超出本次修复范围。

## 5. 推荐设计

采用方案 A。

共享页面仍负责布局和云端固件内容渲染，但把 UI 派生值拆成两个独立能力：

1. `showsServerFirmwareDetails`：控制云端固件卡片和相关布局；
2. `enablesFirmwarePrimaryAction`：控制 `Download` / `UPGRADE` 按钮。

默认实现保持原页面行为。WiFi 页面状态规则为：

- Current loaded 且 New > Current：展示详情，启用 UPGRADE；
- Current loaded 且 New <= Current：隐藏详情，禁用 UPGRADE；
- Current failed 且云端 latest 有效：展示详情，显示 Refresh，禁用 UPGRADE；
- Current loading：保持当前 loading 行为，禁用 UPGRADE。

为避免误导，Failed 场景继续隐藏顶部 `New version found` 状态，仅展示云端返回的 `New version` 详情卡片、`Current version: Failed` 和 Refresh。这样不会声称已经完成版本高低判断。

## 6. 计划修改范围

- `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
  - 将固件详情展示和主按钮 enablement 从单一版本比较结果中解耦。
  - 默认行为保持不变，避免影响 BLE/Mesh 固件页面。
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
  - Failed 状态下允许展示已成功取得的 latest 固件。
  - UPGRADE 继续严格依赖有效版本比较。
- `scripts/check_wifi_gateway_firmware_update.sh`
  - 先增加失败用例契约，确保 `Current version = Failed + serverData 有效` 时固件详情可见、Refresh 可见、UPGRADE 禁用。
  - 保留现有四 target 接线和 Current version 查询契约。

不计划修改 SDK、网络请求参数、接口模型、本地化文案、Xcode target 配置或其它 Gateway 页面。

## 7. 验证方案

1. 静态契约脚本先失败，再完成最小实现使其通过。
2. 人工状态矩阵检查：
   - dev latest 成功 + Current Failed；
   - dev latest 成功 + Current Loading；
   - New > Current；
   - New == Current；
   - New < Current；
   - latest 请求失败或未找到。
3. 运行现有 WiFi Gateway 相关回归脚本。
4. 使用 iPhoneOS generic destination 分别构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。
5. 执行 `git diff --check`，确认无无关格式化或越界改动。

## 8. 验收标准

- 输入 `1314` 后，只要云端 dev latest 请求成功，服务端返回的 `v0.4.0` 会按现有规则规范化为 `0.4.0`，并展示对应固件详情。
- Current version 为 `Failed` 时，页面仍展示 latest 固件详情和 Refresh。
- Current version 为 `Failed` 时，`UPGRADE` 始终不可用。
- Current version 成功后，仍只有 New version 严格高于 Current version 才启用 `UPGRADE`。
- BLE/Mesh 固件页面行为不变。
