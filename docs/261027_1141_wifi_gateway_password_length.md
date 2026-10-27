# WiFi 网关密码长度协议更新

2026-10-27，按本次提供的新协议实施。

## 执行契约

| 字段 | 长度 | 取值 |
| --- | --- | --- |
| `password_len` | 1 字节 | `0~63`，表示 password 的 UTF-8 字节数 |

- 设置凭据 `43 0D <ssid_len> <ssid> <password_len> <password>` 与成功回读 `43 12 00 <ssid_len> <ssid> <password_len> <password>` 均接受 1～7 字节密码。
- 长度为 0 时不携带 password，继续表示开放网络；64 字节及以上拒绝。
- SSID 仍为 1～32 UTF-8 字节；保留控制字符、无效 UTF-8 与报文长度一致性校验。
- App 连接按钮、提交、回读与不确定结果恢复共用 SDK 凭据校验；无须迁移已有密码缓存。英文和简体中文长度提示已同步。

## SDK 交付依赖

- App 分支：`fix/SR-BL2421-MINI-261027`。
- 本地 workspace：`SunSmartLocal.xcworkspace`，映射到 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK 基线：`e7c1a7f327191a67adb8143e9b588f757892fde7`；本次未提交差异为 `SunricherVendorStatus.swift` 的两处长度校验，以及 `WiFiGatewayVendorMessageTests.swift` 的边界测试。
- 发布前须将 SDK 变更纳入远端 `release` 并更新 App 解析到的 SDK revision；仅交付 App 文案不能获得短密码支持。正式依赖声明未改动。
- 五个品牌共用上述 SDK 逻辑与本地化资源；无新增资源归属、API 或品牌条件分支，以 SunSmart 作代表构建。

## 验证与待验收

- 通过：抽取实际 SDK 凭据模型、文本校验器及 `0x12` 解析函数的隔离 Swift 行为验证，覆盖全部 0～63 字节和 3 个中文密码案例，以及 nil、超长多字节密码、控制字符、无效 UTF-8、截短和多余字节。
- 已扩展 SDK XCTest 的实际 `0x0D` 编码与 `0x12` 回读测试，并通过 Swift 语法解析；未运行完整 iOS SDK XCTest。上述隔离验证不覆盖外层消息分发和真实传输。
- 通过：`check_wifi_gateway_network_connectivity.sh`、`check_wifi_gateway_disconnect_clear_credentials.sh`，含连接轮询与凭据恢复 reducer；中英 strings 格式检查、两个工作树的 `git diff --check`。
- 通过：SunSmart / Debug / generic iOS / 禁用签名构建，使用本地 SDK；现有无关编译警告保留。未运行其他品牌构建或真机。
- 人工验收：在支持新协议的网关上输入 1～7 字节有效密码，确认 Connect 可用且配置下发成功；退出重进确认回读保留原密码。再核对空密码和 63 字节有效、64 字节不可提交。连接结果以目标网络实际认证规则为准。
