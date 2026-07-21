# WiFi Firmware Update 请求顺序问题分析与优化方案

## 1. 结论

`Current version` 一直显示 `Loading...` 的直接原因是：本次进入页面后没有发送 WiFi 固件版本查询 `43 14`。

当前页面恢复到一个未消费的 OTA session 后，`WiFiFirmwareDFUCoordinator.refresh()` 会优先发送 OTA 状态查询 `43 11` 并提前返回。日志中的 `43 11` 返回了合法的 OTA 终态失败：

- `stage = timeout`
- `code = versionQueryTimeout`
- `firmwareID = 0.9.1`
- `moduleVersion = nil`

coordinator 接受该终态后只更新 OTA UI 为 `Upgrade failed`，不会继续查询 `43 14`，也不会产生 current-version 成功或失败事件，因此页面状态一直停留在初始化的 `Loading...`。

`firmwareID = 0.9.1` 是该 OTA session 的目标固件标识，不等于网关当前运行版本；且本次响应的 `moduleVersion` 为空，因此不能用这条 `43 11` 响应替代 `43 14` 填充 `Current version`。

HTTP `500 / 4004 Resource Not Found` 是互联网最新固件请求失败，与 Mesh `43 11`、`43 14` 属于不同请求链。它会导致页面没有可用的新固件数据，但不是 `Current version` 一直 Loading 的直接原因。

## 2. 当前请求链的问题

当前基类在页面加载和 Reload 时按以下方式触发请求：

1. 启动互联网最新固件请求；
2. 调用 WiFi 页的 `loadAdditionalFirmwareData()`；
3. WiFi 页激活 coordinator；
4. coordinator 自行决定优先查询 OTA 状态还是当前版本。

当存在恢复 session 时，实际链路变成：

`HTTP latest` 与 `43 11 OTA status` 同时开始 → `43 11` 返回终态 → 查询结束。

这里有三个结构性问题：

1. 页面没有掌握两个前置版本请求是否已经完成，无法保证 OTA 查询顺序；
2. coordinator 把“当前版本查询”和“OTA 状态恢复”合并在同一个 `refresh()` 分支中，恢复 session 可以跳过当前版本；
3. 旧终态 session 被 authoritative `43 11` 判定为过期时，当前逻辑还会再次调用 `43 14`，调整顺序后可能造成重复版本请求。

## 3. 方案比较

### 方案 A：页面两阶段加载屏障（推荐）

第一阶段并行启动：

- Mesh `43 14`：WiFi 网关当前固件版本；
- HTTP latest：互联网最新固件版本。

当两个请求都进入结束态后，再进入第二阶段：

- 开放 OTA 状态监听；
- 发送 authoritative/normal `43 11`；
- 按现有 session 恢复策略显示进行中、成功、失败或空闲状态。

“结束态”包含成功、业务失败、网络失败、解析失败和超时。这样当前日志中的 HTTP `4004` 不会阻塞后续 OTA 查询。

优点：严格满足目标顺序；职责清楚；能统一处理首次进入、Reload、失败和旧回调；保留现有 OTA session 恢复策略。

代价：需要在页面基类增加一个很窄的加载编排扩展点，并拆分 coordinator 的 current-version 与 OTA-status 入口。

### 方案 B：只在 `43 11` 终态后补发 `43 14`

优点：改动最少。

缺点：请求顺序仍然是 OTA 在前，不符合要求；进行中 OTA、查询超时、无 session 等分支仍可能出现不同顺序；只能修当前现象，不能建立稳定契约。

### 方案 C：coordinator 内先查 `43 14` 再查 `43 11`

优点：Mesh 命令之间可以保证串行。

缺点：coordinator 不知道 HTTP latest 何时完成，无法保证“互联网新固件版本结束后再查 OTA”；若把 HTTP 也移入 coordinator，会扩大其职责并耦合网络层与 Mesh OTA 状态机。

## 4. 推荐设计

### 4.1 页面加载周期

在 `FirmwareVersionViewController` 增加一个可覆写的“固件数据加载周期”入口，页面首次加载和 Reload 都通过该入口触发。默认实现保持其它固件页面现状：继续启动云端请求与附加数据加载，不改变 BLE/Mesh 固件页面行为。

云端请求增加可选 completion，确保以下所有路径都回调完成：

- 正常成功并解析出固件；
- 成功响应但字段缺失或 Product ID 不匹配；
- `Resource Not Found`；
- 其它网络或业务失败。

Beta Testing 中单独刷新云端固件仍走原有云端请求，不触发新的 WiFi OTA 加载周期。

### 4.2 WiFi 两阶段屏障

WiFi 页面每次开始完整加载周期时创建新的 generation，并重置三个状态：

- current version 是否结束；
- cloud latest 是否结束；
- 本 generation 是否已经启动 OTA 查询。

随后并行启动 `43 14` 和 HTTP latest。任一完成事件到达时检查屏障；只有两者都完成且 OTA 尚未启动时，才调用一次 OTA status refresh。

旧 generation 的异步回调不得推进新 generation，页面离开后也不得补发迟到的 `43 11`。

### 4.3 Coordinator 职责拆分

把当前隐式的 `refresh()` 拆成两个明确入口：

- 当前版本查询：只发送 `43 14`，并产生 loading、success 或 failed 结束事件；
- OTA 状态刷新：只处理 session 恢复、缓存终态与 `43 11` 查询，不再回退调用 `43 14`。

页面生命周期激活与 OTA observer 激活需要分开。前置阶段允许 `43 14` 回调工作，但在屏障开放前不消费或展示 OTA EVENT，避免 EVENT 绕过顺序约束。屏障开放后再注册 OTA message/connection observer，并发送 `43 11`。

authoritative `43 11` 判定旧终态 session 已过期时，只清理 session 并发出 idle；不再重复查询 current version。若 `43 11` 返回 OTA success 且包含 `moduleVersion`，仍允许 confirmed version 覆盖第一阶段获取的 current version。

### 4.4 失败与 UI 规则

- `43 14` 成功：`Current version` 显示真实版本；
- `43 14` 失败或超时：显示 `Failed`，但仍在 HTTP latest 结束后查询 OTA；
- HTTP latest 失败：保持现有无新固件/错误 UI，但仍在 `43 14` 结束后查询 OTA；
- `43 11` 返回恢复 session 的合法终态：显示对应 OTA 结果，同时保留第一阶段取得的 current version；
- 两个前置请求无论谁先结束，都只能触发一次 `43 11`。

## 5. Auto Layout 警告

日志中的约束冲突与请求顺序无因果关系，但是真实存在的独立问题。

父控制器隐藏 `WiFiFirmwareUpdatingView` 时添加 `height == 0`；子视图内部同时要求 `detailLabel.top = 65` 且 `detailLabel.bottom <= bottom`。高度为 0 时这组 required constraints 不可能同时成立，因此 UIKit 打断 bottom constraint。

建议在同次修复中做局部处理：仅降低 `WiFiFirmwareUpdatingView` 内部 bottom 约束优先级，使隐藏状态允许父视图折叠；显示状态仍由现有内容高度约束决定。不修改共享父控制器的折叠机制，避免影响其它固件页面。

## 6. 实施范围

预计修改：

- `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
  - 增加可覆写的完整加载周期入口；
  - 云端请求支持可靠 completion；
  - 首次加载与 Reload 使用统一入口。
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
  - 增加 generation 化的两请求屏障；
  - 先启动 current/cloud，屏障完成后启动 OTA；
  - 页面离开时失效旧周期。
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`
  - 拆分 current-version 与 OTA-status API；
  - 延迟 OTA observer；
  - 删除 stale-terminal 分支中的重复 `43 14`。
- `SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift`
  - 局部消除折叠状态约束冲突。
- `Tests/Firmware/`
  - 增加加载屏障与顺序状态测试。
- `scripts/check_wifi_gateway_firmware_update.sh`
  - 更新静态契约检查。

不修改 NordicSigMeshSDK、不修改协议 payload、不改变 OTA status reducer、session 身份匹配和状态映射规则，也不调整其它 Gateway 固件页面行为。

## 7. TDD 与验收计划

### 自动测试

先增加失败测试，再实施代码：

1. current 先完成、cloud 后完成：只在 cloud 完成后启动一次 OTA；
2. cloud 先完成、current 后完成：只在 current 完成后启动一次 OTA；
3. current 失败、cloud 成功：仍启动 OTA；
4. cloud `Resource Not Found`、current 成功：仍启动 OTA；
5. 两个 completion 重复到达：OTA 只启动一次；
6. Reload 生成新 generation：旧回调不能推进新周期；
7. 页面离开：迟到回调不能发送 OTA 查询；
8. stale terminal 被清理：不重复发送 `43 14`。

### Log 验收

首次进入或点击 Reload 后应观察到：

1. HTTP latest 与 `43 14` 可以任意先后开始；
2. 在二者都结束之前，不出现 `43 11`；
3. 二者都结束后，只出现一次首个 `43 11`；
4. 即使 HTTP 返回 `4004 Resource Not Found`，仍继续发送 `43 11`；
5. `43 14` 回调结束后，`Current version` 必须变为版本号或 `Failed`，不能无限停在 `Loading...`；
6. 页面隐藏 OTA 区域时不再输出该 Auto Layout 冲突。

### 构建验证

运行聚焦测试和静态契约脚本，再使用 generic iPhoneOS、关闭签名方式分别验证共享代码涉及的 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` scheme，最后执行 `git diff --check` 并确认没有混入现有无关改动。

## 8. 待确认

建议确认采用方案 A，并将日志中的 Auto Layout 警告一并按局部低优先级约束方式修复。确认后按 Inline Execution 在当前会话中实施。
