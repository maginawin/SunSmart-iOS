# WiFi Firmware Update 请求顺序优化实施总结

## 实施结果

已按方案 A 将 WiFi Firmware Update 页面调整为两阶段加载：

1. 第一阶段并行请求 WiFi 当前固件版本 `43 14` 与互联网最新固件版本；
2. 两个请求无论成功、失败或超时，只要都结束，才进入第二阶段；
3. 第二阶段注册 OTA 状态 observer 并发送 `43 11`；
4. Reload、页面重新进入和异步旧回调通过 generation 隔离，每轮最多启动一次首个 OTA 状态查询。

因此，恢复到未消费 OTA session 时不再因为优先执行 `43 11` 而跳过 `43 14`。`Current version` 在 `43 14` 完成后会进入版本号或 `Failed`，不会因 OTA 终态一直保留 `Loading...`。

## 主要改动

### 页面基类

- 增加统一的 `loadFirmwareData()` 加载周期扩展点；
- 首次加载和 Reload 统一走该入口；
- 云端最新固件请求增加 completion；
- completion 通过 `defer` 覆盖成功、字段校验失败、Resource Not Found 和其它失败路径；
- 默认实现仍保持其它固件页面原有的 cloud + additional 行为。

### WiFi Firmware Update 页面

- 增加 `WiFiFirmwareInitialLoadGate` 与 generation；
- current/cloud 两个 completion 任意顺序到达都必须经过屏障；
- 重复 completion、旧 generation 和页面退出后的 completion 不会启动 OTA 查询；
- 页面重新出现时重新执行完整的两阶段加载；
- OTA success 的 confirmed version 仍可覆盖第一阶段读取的 current version。

### WiFi DFU Coordinator

- `beginInitialLoad()` 只负责使旧 Mesh callback 失效并查询 `43 14`；
- `refreshOTAStatus()` 才注册 OTA observer 并查询 `43 11`；
- 恢复 session 的 authoritative 查询仍优先于缓存终态回放；
- authoritative 查询清理 stale terminal 后只发出 idle，不再重复查询 `43 14`；
- 无本地 session 时仍会实际发送一次 `43 11`，IDLE 响应映射为页面 idle。

### Auto Layout

- 将 `WiFiFirmwareUpdatingView` 内部 detail label 的 bottom constraint 降为 `.defaultHigh`；
- 父视图隐藏时可以安全折叠到 0，不再与内部 `top = 65` 形成 required constraint 冲突；
- 未修改共享父控制器的折叠规则。

## TDD 证据

RED 阶段：

- 新测试首先因缺少 `WiFiFirmwareInitialLoadGate` 编译失败；
- 静态契约首先因缺少 coordinator 分离入口失败。

GREEN 阶段覆盖：

- current 先完成、cloud 后完成；
- cloud 先完成、current 后完成；
- 两个前置请求完成后只启动一次 OTA；
- 重复 completion 不重复启动；
- 新 generation 拒绝旧 completion；
- cancel 后迟到 completion 不启动 OTA；
- 原有 authoritative session 恢复、状态 reducer、metadata builder 与 SDK V1.9 contract 保持通过。

## 验证结果

- `bash scripts/check_wifi_gateway_firmware_update.sh`：通过；
- `SunSmart` generic iPhoneOS Debug build：`BUILD SUCCEEDED`；
- `Archipelago` generic iPhoneOS Debug build：`BUILD SUCCEEDED`；
- `SLG Sync Plus` generic iPhoneOS Debug build：`BUILD SUCCEEDED`；
- `SylSmart` generic iPhoneOS Debug build：`BUILD SUCCEEDED`；
- `git diff --check`：通过。

四个构建均使用 `CODE_SIGNING_ALLOWED=NO`，未使用 Simulator。

## 尚需真机 Log 验收

编译与本地契约不能替代真实网关通信。真机进入页面或点击 Reload 后应确认：

1. HTTP latest 与 `43 14` 可以任意先后开始；
2. 两者都结束前不发送 `43 11`；
3. 两者都结束后只发送一次首个 `43 11`；
4. HTTP 返回 `4004 Resource Not Found` 时仍继续发送 `43 11`；
5. `Current version` 最终显示版本号或 `Failed`；
6. 控制台不再出现 `WiFiFirmwareUpdatingView.height == 0` 对应的约束冲突。

## 范围说明

- 本次未修改 NordicSigMeshSDK、协议 payload、本地化资源、target 配置或依赖；
- 保留工作区内既有的 OTA 页面恢复修复；
- 保留 `WiFiFirmwareUpdateViewController` 中用户已有的“相同版本允许升级”实验改动，未对其进行回退或扩展；
- 未执行 commit、merge 或 push。
