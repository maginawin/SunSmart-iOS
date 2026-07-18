# WiFi Gateway DFU Start V1.9 实现总结

## 1. 实现结论

已按确认的方案 A 将 WiFi Gateway `0x43/0x10` start OTA 链路切换为 V1.9，并保持 URL 由当前 App 区域 host、固定下载路径和 HTTPS body 的 `filename` 组成。

本次实现同时修改 App worktree 与本地 `NordicSigMeshSDK`，未增加旧格式兼容、`0x43/0x15` cancel、App 下载/解压 OTA 文件或其它固件更新流程改动。

## 2. 最终行为

### 2.1 URL 与 firmware ID

- 当前区域 HTTPS base URL 只把 scheme 改为 `http`，保留 host 与 `/srv2`。
- 固定追加 `/sitespace/ota/download`。
- query `key` 使用 HTTPS response body 的 `filename`。
- `firmware_id` 使用 body 的 `version`，最多移除一个前导 `v` 或 `V`。
- 需求给出的 China Mainland 示例以及 AP、US、EU 区域 host 已加入精确 contract。

### 2.2 Start 请求与 RET

- 每次用户明确点击 `UPGRADE` 或 `UPGRADE AGAIN` 时生成非零随机 `UInt64 ota_id`。
- SDK 只编码 V1.9 请求：`ota_id + url_len + url + firmware_id_len + firmware_id`。
- SDK 校验 V1.9 的 URL/firmware ID 字符范围、长度关系和 256 字节上限。
- 不发送 `size` 或 `sha256`。
- 只接受精确 11 字节的 V1.9 RET；旧 3 字节 RET 和 trailing bytes 都不能形成 typed response。
- Mesh transaction 只允许回显 `ota_id` 与请求相同的 RET 完成，避免旧轮次或同 opcode 响应串包。

### 2.3 无有效 RET 的恢复

- SET 事务等待期间，只暂存 `ota_id` 和 `firmware_id` 都匹配的合法非 `IDLE` EVENT。
- 未收到有效 RET 时，先使用已暂存的匹配 EVENT 确认本轮状态。
- EVENT 仍不能确认时，只发送一次 `0x43/0x11`。
- 一次查询返回匹配非 `IDLE` 状态时建立本轮 session；返回 `IDLE`、身份不匹配、非法应答或超时时结束本次请求。
- 无法确认时显示既有 `Connection failed / Communication timeout`，并提供 `UPGRADE AGAIN`。
- 不继续查询，不自动重发 `0x43/0x10`。
- 有效 `ret=0x01...0x04` 是本轮明确失败结果，不进入上述恢复；reserved ret 按无有效 RET 处理。

## 3. SDK 实现边界

V1.9 start request/response、wire parser 和 matcher 放在独立的 Foundation-only 文件中，vendor set/status routing 与 Mesh response matching 复用该协议真值。

SDK 当前直接执行 `swift test` 会在 macOS host 构建阶段被仓库既有 UIKit 依赖阻断。因此本次新增独立 `swiftc` contract 验证 wire contract，并使用 SDK Demo 与 App 的 generic iPhoneOS 构建验证真实集成；没有把该基线问题扩展为本次无关重构。

## 4. 验证范围

- App 静态 regression script，包括 reducer、URL builder、既有 `0x43/0x11` contract 和新增 `0x43/0x10` contract。
- SDK V1.9 start Foundation-only contract。
- SDK Demo generic iPhoneOS build。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个共享源码 target 的 generic iPhoneOS build。
- App worktree 与 SDK repository 分别执行 `git diff --check` 和改动范围检查。

最终验证结果以本次交付回复中列出的最新命令输出为准。
