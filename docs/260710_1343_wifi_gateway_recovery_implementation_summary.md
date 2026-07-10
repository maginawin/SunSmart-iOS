# WiFi Gateway 添加中断恢复实施总结

## 结论

CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 已增加专用的添加中断恢复路径。手动点击 `Devices not synced` 时，App 不再依赖本地 Key/Bind 完成缓存进行差异修复，而是对 Gateway 必要配置执行一次完整恢复。

权限判定、恢复任务图、失败依赖、离线终止、WiFi 请求串行和中英文反馈均已接入。

## 实施内容

### 1. 统一 Gateway 权限

- Site Owner 允许展示、进入和配置 Gateway。
- 非 Owner 必须至少拥有一个同时满足 `canEditing` 和 `deviceOperates.contains(.edit)` 的有效 Editor Space。
- 已关联 Gateway 还要求有效 Editor Space 与至少一个 Associated Space 匹配。
- 未关联 Gateway 允许拥有任一有效 Editor Space 的用户接管配置。
- Visitor、待删除 Space、待密码验证 Space 和无 `.edit` capability 的 Editor 均不能进入或配置。
- Site 列表、Gateway Card、动态同步状态、Add Gateway、详情页及 WiFi 操作共用同一权限真值。

### 2. 强制完整恢复

- 强制重发当前 AppKey，必要时重发 Main NetKey/Main AppKey。
- 对 Gateway 支持的 models 重做 AppKey Bind。
- 对每个 Associated Space 重发 NetKey、AppKey、subnet model bind，并在启用时下发 subnet appkey add。
- forced builder 不使用 `node.knows(...)` 或 `model.isBoundTo(...)` 进行本地缓存裁剪。
- 恢复路径不读写 WiFi SSID/Password，不新增 Auth 信息。

### 3. 专用任务图

固定顺序为：

1. Initialize
2. Associated Spaces（如有）
3. Association Project
4. Sync Spaces
5. Server Information（如有）

Initialize 是全部后续任务的关键前置。Associated Spaces、Association Project、Sync Spaces 和 Server Information 之间不互相依赖；因此 Associated Spaces 失败后，其他 Gateway Vendor 任务仍会继续。

Initialize 只有在 handles 非空且每个 Config 消息收到成功业务 Status 时才成功。Transport ACK 本身不作为业务成功依据。

### 4. 失败、离线与 Skipped

- Initialize 失败后，未执行的后续任务进入 `Skipped`。
- Gateway 在恢复中离线时，当前已发送任务沿用原失败语义，未开始任务进入 `Skipped`。
- `Skipped` 内部沿用失败聚合，但在进度详情中显示独立文案，不显示单任务重试按钮。
- Re-sync 时会清除 `Skipped` 标记并恢复 Waiting。

### 5. WiFi 请求串行与 Sync 前置

- WiFi credentials/status/RSSI GET、credentials SET 和 credentials CLEAR 共用单一 active request token。
- 每个请求明确标记为 automatic 或 user-initiated。Timer 在 gate 忙时跳过当次 tick。
- 自动请求进行中点击 `Devices not synced`：停止新 RSSI Timer，只保留一个 pending recovery，显示 `Preparing device sync…`，等当前请求完成或 timeout 后继续。
- Connect、Disconnect 或 Refresh 进行中点击：提示等待，不排队，不自动跳转。
- 等待期间自动请求失败不弹中间错误；Node 仍 Online 时进入 recovery，Offline 时关闭 HUD 并只提示离线。
- 页面关闭会清理 pending recovery，但不取消已发送的 acknowledged request。

## 源码与资源验证

- `git diff --check de4aeb8a..HEAD`：通过。
- 旧 Gateway 权限分支审计：目标文件中无遗留命中。
- forced builder 范围审计：无 `node.knows`、`isBoundTo`、WiFi 凭据或 password 命中。
- recovery task graph 和 Gateway 入口不包含 WiFi 凭据写入。
- WiFi GET/SET/CLEAR 调用点均显式传入 automatic 或 user-initiated origin。
- English 和简体中文的三个新 Key 各出现一次。
- `plutil -lint`：两个 `Localizable.strings` 均为 `OK`。
- `Localizable.strings` 变体组已进入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 Resources build phase。

## iPhoneOS 构建验证

| Scheme | 配置 | 结果 |
| --- | --- | --- |
| SunSmart | Debug / generic iPhoneOS / no code signing | 通过，exit 0 |
| Archipelago | Debug / generic iPhoneOS / no code signing | 通过，exit 0 |
| SLG Sync Plus | Debug / generic iPhoneOS / no code signing | 通过，exit 0 |
| SylSmart | Debug / generic iPhoneOS / no code signing | 通过，exit 0 |

Archipelago、SLG Sync Plus 和 SylSmart 在受限环境内启动 `xcodebuild` 时曾遇到 CoreSimulator/Xcode 日志权限错误，该错误发生在编译前。改为授权环境直接重跑后，三个 scheme 均 exit 0。

构建仍输出工程已有的 asset 命名冲突、deprecated API、actor isolation 和重复 build file 等 warning；本次验证无编译 error。

## 尚需实机验收

当前 App 没有可用的 XCTest target，且本轮无 CID `0x0A78` / PID `0x2721` 实机连接，因此以下项目仍需实机执行：

1. Owner、有效 Editor、无关 Editor、Visitor 及异常 Editor 的权限矩阵。
2. 页面自动 GET、RSSI GET、timeout、Offline、Connect/Disconnect/Refresh 与连续点击的串行矩阵。
3. Initialize 失败、Associated Spaces 失败、只有 Transport ACK、中途 Offline 和 Re-sync 的任务状态矩阵。
4. Adding 数秒后断电、重新上电、一次完整恢复、`Devices not synced` 消失且 WiFi 凭据不变的原始复现场景。

实机验收步骤和预期结果详见 `docs/260710_1223_wifi_gateway_interrupted_add_recovery_implementation_plan.md` 的 Task 7。
