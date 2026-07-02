# WiFi Gateway Remove APN Plan

## 背景

WiFi Gateway 的设备身份为 `CID 0x0A78 / PID 0x2721`。当前 Site 入口通过 `node.isWiFiGateway` 将该设备路由到 `WiFiGatewayViewController`，但该 controller 继承 `GatewayViewController`，因此仍复用了 4G Gateway 的 APN section 和 APN 同步任务生成逻辑。

需求是 WiFi Gateway 不支持配置 APN 属性，需要从 WiFi Gateway 页面删除 APN 属性；如果 Save 任务中存在 APN 相关任务，也需要删除。

## 当前代码事实

- `SunSmart/Main/Site/Controller/SiteViewController.swift` 中，`gateway.node.isWiFiGateway` 时进入 `WiFiGatewayViewController`，否则进入 `GatewayViewController`。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` 已将 WiFi Gateway 定义为 `companyIdentifier == 0x0A78 && productIdentifier == 0x2721`。
- `WiFiGatewayViewController` 目前没有覆盖 section 配置，继承了 `GatewayViewController` 的 `sections`，其中包含 `.apn`。
- `GatewayViewController` 的 APN UI 包括 `.apn` section、APN cell、APN header、APN menu selection。
- `saveBtnAction()` 保存后通过 `node.getNodeSyncGatewayData(gateway: setGatewayModel)` 判断是否进入 `SyncDevicesViewController`。
- `Node+SyncData.swift` 的 `getNodeSyncGatewayData(gateway:)` 会在 `gateway.apn` 与 `gatewayInfo?.simInfo?.apn` 不一致时追加 `.syncGatewaySIMAPN(apn:)`。
- `SyncDevicesViewController` 只是把传入的 `.syncGatewaySIMAPN` 转成名为 `apn` 的同步任务；任务源头在 `getNodeSyncGatewayData(gateway:)`。

## 推荐方案

采用 WiFi Gateway 专属能力开关，保留 legacy 4G Gateway 的 APN 行为。

1. 在 `GatewayViewController` 增加可覆盖的 APN 能力属性，例如 `supportsAPNConfiguration: Bool`，默认返回 `true`。
2. 在 `WiFiGatewayViewController` 覆盖该属性返回 `false`。
3. 将 `GatewayViewController` 的 section 初始化改成通过能力属性生成：
   - 默认 Gateway 保留 `.apn`。
   - WiFi Gateway 过滤 `.apn`。
4. 在 `Node+SyncData.swift` 的 `getNodeSyncGatewayData(gateway:)` 中，APN 同步追加前增加 WiFi Gateway 排除：
   - `node.isWiFiGateway == true` 时不追加 `.syncGatewaySIMAPN`。
   - 其他 Gateway 保持现有 APN 同步逻辑。
5. 保留 `GatewayModel.apn`、数据库字段、导入导出字段、APN menu 组件和 Sync 页面对 `.gatewaySIMAPN` 的处理，避免影响 4G Gateway、历史数据和共享同步框架。

## 不推荐方案

- 直接从 `GatewayViewController.sections` 删除 `.apn`：会影响所有 Gateway，包括 legacy 4G Gateway。
- 删除 `.syncGatewaySIMAPN` enum 或 Sync 页面任务处理：会影响其他仍支持 APN 的 Gateway 和已有同步机制。
- 清空 WiFi Gateway 本地 `gateway.apn`：这不是本次需求，且可能造成历史数据迁移副作用；只需要 WiFi 页面不展示、不产生 APN Save 同步任务。

## 验证计划

1. 增加轻量静态回归脚本，检查：
   - `WiFiGatewayViewController` 覆盖 APN 能力为 false。
   - `GatewayViewController` section 构造会根据能力过滤 `.apn`。
   - `Node+SyncData.getNodeSyncGatewayData(gateway:)` 对 WiFi Gateway 不追加 `.syncGatewaySIMAPN`。
2. 运行静态脚本，先验证它能守住本次改动点。
3. 运行 `git diff --check`。
4. 运行 iPhoneOS 构建：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 预期结果

- `CID 0x0A78 / PID 0x2721` 的 WiFi Gateway 页面不再显示 APN section。
- WiFi Gateway 点击 Save 时，即使本地历史 `GatewayModel.apn` 有值，也不会生成 APN 同步任务。
- 其他 Gateway 页面仍显示 APN section，Save 任务仍可包含 APN 同步。
- 不新增用户可见文案，不新增 Auth 信息，不改变 WiFi Gateway 的 Activate、Associated Spaces、Server Information 等现有行为。
