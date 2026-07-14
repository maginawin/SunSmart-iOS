# WiFi Gateway Current Target Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Do not use subagents unless the user explicitly requests them. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 在 `WiFi Firmware Update` 页面展示本次正式或 dev 查询实际获得的新固件版本，并在无有效结果时展示 `None`。

**Architecture:** 保留 `FirmwareVersionViewController` 作为共享查询和 UI 实现，只增加“请求前重置服务器结果”和“有效服务器固件是否可升级”两个默认兼容的覆盖点。WiFi 子类把标签绑定到本次 `FirmwareServerData.version`，同时避免服务器版本与自身比较；BLE/Mesh 页面继续使用原有缓存版本比较。

**Tech Stack:** Swift、UIKit、SwiftyJSON、SnapKit、现有 `NetworkRequest` 固件 API、Bash 静态契约、Xcode iPhoneOS 构建。

## Global Constraints

- 设备范围固定为 CID `0x0A78`、PID `0x2721`，不得改变其他 Gateway。
- 正式和 dev 固件均展示本次有效响应中的版本；dev 继续使用 `customerId=wifi` 和 `profile=dev`。
- 服务器无固件、请求失败、响应字段缺失、PID 无效或不匹配时展示 `None`。
- 每次正式查询、Refresh 或 dev 查询前清除上一次 WiFi 服务器结果，失败后不得残留旧版本。
- `UPGRADE` 继续显示现有 `under_development` 提示，不实现真实升级。
- BLE、Mesh Firmware Update 的默认缓存版本比较和展示行为保持不变。
- 不新增用户可见文案，不修改本地化资源、依赖或 target 配置。
- 使用 Debug iPhoneOS generic destination 和 `CODE_SIGNING_ALLOWED=NO` 验证，不使用 Simulator。

---

## File Structure

- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift` — 提供默认兼容的结果重置和新固件判断覆盖点。
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift` — 移除固定版本并展示本次服务器版本。
- Modify: `scripts/check_wifi_gateway_firmware_update.sh` — 守住动态版本、失败清理和默认比较契约。
- Create: `docs/260714_1104_wifi_gateway_target_version_implementation_summary.md` — 记录实际改动与验证。

### Task 1: 以契约测试驱动动态 Target Version 行为

**Files:**
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`

**Interfaces:**
- Consumes: `type.serverData`、`FirmwareServerData.version`、`loadCloudFirmwareRequest()`、`displayedCurrentTargetVersion`。
- Produces: `resetsServerFirmwareBeforeCloudRequest: Bool`；`isNewServerFirmwareAvailable(_:) -> Bool`。

- [ ] **Step 1: 将旧固定版本契约替换为动态版本契约**

从 `scripts/check_wifi_gateway_firmware_update.sh` 删除：

```bash
rg -n 'override var displayedCurrentTargetVersion: String\?' "$wifi" >/dev/null || fail "WiFi firmware controller missing fixed current version"
rg -n 'return "1\.0\.0"' "$wifi" >/dev/null || fail "WiFi firmware current version must be 1.0.0"
```

在共享页面 hook 检查区域加入：

```bash
rg -n 'var resetsServerFirmwareBeforeCloudRequest: Bool' "$parent" >/dev/null || fail "missing server firmware reset hook"
rg -n 'func isNewServerFirmwareAvailable\(_ serverData: FirmwareServerData\) -> Bool' "$parent" >/dev/null || fail "missing server firmware availability hook"
rg -n 'if resetsServerFirmwareBeforeCloudRequest' "$parent" >/dev/null || fail "firmware request ignores reset hook"
rg -n 'type\.serverData = nil' "$parent" >/dev/null || fail "firmware request does not clear stale server data"
rg -n 'noServerFirmware = false' "$parent" >/dev/null || fail "firmware request does not reset stale not-found state"
rg -n 'if isNewServerFirmwareAvailable\(newFirmwareData\)' "$parent" >/dev/null || fail "firmware UI ignores availability hook"
rg -n 'serverData\.version\.compare\(currentVersion, options: \.numeric\) == \.orderedDescending' "$parent" >/dev/null || fail "default availability must preserve numeric comparison"
```

在 WiFi 页面检查区域加入：

```bash
if rg -n '0\.0\.1' "$wifi" >/dev/null; then
  fail "WiFi firmware controller must not contain a fixed target version"
fi
rg -n 'targetVersion: nil' "$wifi" >/dev/null || fail "WiFi firmware target version must start empty"
rg -n 'return type\.serverData\?\.version' "$wifi" >/dev/null || fail "WiFi target version must come from current server result"
rg -n 'override var resetsServerFirmwareBeforeCloudRequest: Bool' "$wifi" >/dev/null || fail "WiFi firmware controller missing reset override"
rg -n 'override func isNewServerFirmwareAvailable\(_ serverData: FirmwareServerData\) -> Bool' "$wifi" >/dev/null || fail "WiFi firmware controller missing availability override"
wifi_true_override_count=$(grep -Fc 'return true' "$wifi")
[ "$wifi_true_override_count" -eq 2 ] || fail "WiFi reset and availability overrides must both return true"
```

- [ ] **Step 2: 运行聚焦契约并确认红灯**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: FAIL，首个新契约错误为 `missing server firmware reset hook`；不得因脚本语法、路径或旧 `1.0.0` 断言失败。

- [ ] **Step 3: 在共享页面实现两个默认兼容覆盖点**

在现有可覆盖属性之后加入：

```swift
var resetsServerFirmwareBeforeCloudRequest: Bool { false }

func isNewServerFirmwareAvailable(_ serverData: FirmwareServerData) -> Bool {
    guard let currentVersion = displayedCurrentTargetVersion else {
        return true
    }
    return serverData.version.compare(currentVersion, options: .numeric) == .orderedDescending
}
```

在 `loadCloudFirmwareRequest()` 最前面、显示 loading HUD 之前加入：

```swift
if resetsServerFirmwareBeforeCloudRequest {
    type.serverData = nil
    noServerFirmware = false
}
```

必须同时重置 `noServerFirmware`，避免上一次 `resourceNotFound` 污染后续格式无效响应的状态。

删除 `updateUI()` 中的内联比较：

```swift
let hasNewerVersion = displayedCurrentTargetVersion.map {
    newFirmwareData.version.compare($0, options: .numeric) == .orderedDescending
} ?? true
```

并把 `if hasNewerVersion {` 替换为：

```swift
if isNewServerFirmwareAvailable(newFirmwareData) {
```

- [ ] **Step 4: 再次运行契约并确认失败推进到 WiFi 子类**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: FAIL，错误为 `WiFi firmware controller must not contain a fixed target version`；共享 hook 断言均通过。

- [ ] **Step 5: 让 WiFi 页面展示本次有效服务器版本**

将初始化改为：

```swift
convenience init() {
    self.init(
        type: FirmwareUpdateTypeData(
            productId: 0x2721,
            targetVersion: nil,
            nodes: []
        )
    )
}
```

将固定展示属性改为，并加入两个 WiFi 覆盖：

```swift
override var displayedCurrentTargetVersion: String? {
    return type.serverData?.version
}

override var resetsServerFirmwareBeforeCloudRequest: Bool {
    return true
}

override func isNewServerFirmwareAvailable(_ serverData: FirmwareServerData) -> Bool {
    return true
}
```

WiFi 页面没有设备当前 WiFi 固件版本；本次有效服务器结果本身就是 target firmware，因此不与自身比较。

- [ ] **Step 6: 运行聚焦契约并确认绿灯**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: `PASS: WiFi Gateway firmware update static checks`。

- [ ] **Step 7: 验证主 target 编译**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 退出码 `0`，结尾包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 8: 检查差异并提交核心实现**

Run:

```bash
git diff --check
git diff -- SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift scripts/check_wifi_gateway_firmware_update.sh
git add SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift scripts/check_wifi_gateway_firmware_update.sh
git commit -m "fix: show wifi firmware target version"
```

Expected: `git diff --check` 无输出；生成一个仅包含上述三个文件的提交。

### Task 2: 完成回归、四 target 构建与实施总结

**Files:**
- Test: `scripts/check_gateway_activate_header_layout.sh`
- Test: `scripts/check_gateway_associated_spaces_deferred_save.sh`
- Test: `scripts/check_wifi_gateway_apn_removed.sh`
- Test: `scripts/check_wifi_gateway_disconnect_clear_credentials.sh`
- Test: `scripts/check_wifi_gateway_firmware_update.sh`
- Test: `scripts/check_wifi_gateway_info_rows_hidden.sh`
- Test: `scripts/check_wifi_gateway_menu_icons.sh`
- Test: `scripts/check_wifi_gateway_network_connectivity.sh`
- Test: `scripts/check_wifi_gateway_repair_recovery.sh`
- Test: `scripts/check_wifi_gateway_server_information_recovery.sh`
- Test: `scripts/check_wifi_gateway_sig_mesh_status_header.sh`
- Test: `scripts/check_wifi_gateway_wifi_status_header.sh`
- Create: `docs/260714_1104_wifi_gateway_target_version_implementation_summary.md`

**Interfaces:**
- Consumes: Task 1 的共享 hook、WiFi 覆盖和聚焦契约。
- Produces: 四品牌 iPhoneOS 构建证据和最终实施总结；不新增运行时接口。

- [ ] **Step 1: 逐个运行全部 Gateway/WiFi Gateway 静态回归**

Run:

```bash
bash scripts/check_gateway_activate_header_layout.sh
bash scripts/check_gateway_associated_spaces_deferred_save.sh
bash scripts/check_wifi_gateway_apn_removed.sh
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
bash scripts/check_wifi_gateway_firmware_update.sh
bash scripts/check_wifi_gateway_info_rows_hidden.sh
bash scripts/check_wifi_gateway_menu_icons.sh
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_repair_recovery.sh
bash scripts/check_wifi_gateway_server_information_recovery.sh
bash scripts/check_wifi_gateway_sig_mesh_status_header.sh
bash scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: 12 个脚本均退出码为 `0` 并输出各自的 `PASS`。

- [ ] **Step 2: 串行验证其余三个品牌 target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 三条命令均退出码为 `0` 且包含 `** BUILD SUCCEEDED **`。必须串行执行，避免共享 DerivedData 的 `build.db` lock。

- [ ] **Step 3: 创建实施总结**

创建 `docs/260714_1104_wifi_gateway_target_version_implementation_summary.md`：

```markdown
# WiFi Gateway Current Target Version 实施总结

## 实施结果

- 移除 WiFi Firmware Update 页面中的固定版本 `0.0.1`。
- `Current target version` 展示本次正式或 dev 查询返回的有效固件版本。
- 每次查询前清除上一次 WiFi 服务器结果；服务器无固件、网络失败或格式无效时展示 `None`。
- WiFi 有有效服务器固件时独立判定为可升级，不再将服务器版本与自身比较。
- `UPGRADE` 继续使用现有开发中提示。

## 共享层边界

- 共享页面新增默认关闭的请求前结果重置 hook。
- 共享页面新增默认沿用数值版本比较的新固件判断 hook。
- BLE、Mesh 固件页面未覆盖这些 hook，既有行为保持不变。

## 验证结果

- WiFi Firmware Update 聚焦契约通过。
- Gateway/WiFi Gateway 共 12 个专项脚本通过。
- `git diff --check` 通过。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 Debug iPhoneOS 构建成功。
```

- [ ] **Step 4: 执行最终一致性检查**

Run:

```bash
rg -n '0\.0\.1' SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift
git diff --check
git status --short
```

Expected: 第一条 `rg` 无匹配并以状态 `1` 结束；`git diff --check` 无输出；状态只显示新实施总结。

- [ ] **Step 5: 提交总结并确认最终状态**

Run:

```bash
git add docs/260714_1104_wifi_gateway_target_version_implementation_summary.md
git commit -m "docs: summarize wifi firmware target version"
git status --short
git log -3 --oneline
```

Expected: 工作区干净；最近三个提交依次为实施总结、核心实现、设计文档。
