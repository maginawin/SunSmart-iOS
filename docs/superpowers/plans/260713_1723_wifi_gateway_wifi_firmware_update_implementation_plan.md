# WiFi Gateway WiFi Firmware Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Steps use checkbox (`- [ ]`) syntax for tracking. Do not use subagents unless the user explicitly changes the execution preference.

**Goal:** 为 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 增加只读 WiFi 固件查询页面、Beta/历史版本查询和 `UPGRADE` 占位入口，同时保持现有 BLE/Mesh Firmware Version 行为不变。

**Architecture:** 将 `FirmwareVersionViewController` 调整为带窄扩展点的模板控制器，由新增 `WiFiFirmwareUpdateViewController` 覆盖页面标题、字符串 `customerId`、固定版本、导入/删除显隐和主按钮动作。历史页面接收字符串 `customerId`，WiFi 页面只查询和展示，不进入 `FirmwareData`、`ZipHandler` 或 Mesh 固件缓存链。

**Tech Stack:** Swift、UIKit、SnapKit、SwiftyJSON、现有 `NetworkRequest`/`FirmwareUpdateTypeData`、Bash 静态契约、Xcode workspace 多 scheme iPhoneOS 构建。

## Global Constraints

- 设备范围固定为 CID `0x0A78`、PID `0x2721`，不得改变其他 Gateway 或 Firmware update via BLE 行为。
- 正式与 Beta 最新/历史请求都使用 `customerId=wifi`；Beta 额外使用 `profile=dev`。
- `Current target version` 固定为 `1.0.0`，不读取或修改 Mesh 固件缓存。
- WiFi Beta 弹窗隐藏 `Import from local`；普通 Firmware Version 继续保留。
- `UPGRADE` 仅在服务器版本高于 `1.0.0` 时启用，点击只显示现有 `under_development`。
- 不实现 WiFi 固件下载、解析、缓存、传输、进度、恢复或完成校验；不修改数据库 schema。
- 所有新增或修改的用户可见文案覆盖 English 和简体中文，不硬编码新文案。
- 保持改动聚焦，不格式化或重构无关代码，不新增 Auth 信息。
- 新控制器和共享改动必须覆盖 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 构建直接使用 `xcodebuild`、generic iPhoneOS destination、`CODE_SIGNING_ALLOWED=NO`，不得使用 shell 包装、重定向或 Simulator。

---

## 文件结构

- Create: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift` — WiFi 页面差异和 `UPGRADE` 占位动作。
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift` — 共享页面扩展点和默认 BLE/Mesh 行为。
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionHistoryController.swift` — 字符串 `customerId` 历史查询。
- Modify: `SunSmart/Main/Firmware/View/BetaTestingAlertView.swift` — 可配置本地导入显隐。
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift` — WiFi DFU 菜单导航。
- Modify: `SunSmart/en.lproj/Localizable.strings`、`SunSmart/zh-Hans.lproj/Localizable.strings` — 两种语言文案。
- Modify: `SunSmart.xcodeproj/project.pbxproj` — 新文件加入四个品牌 target。
- Create: `scripts/check_wifi_gateway_firmware_update.sh` — 新功能静态契约。
- Modify: `scripts/check_wifi_gateway_menu_icons.sh` — WiFi DFU 从 placeholder 改为页面导航后的契约。

---

### Task 1: 为共享 Firmware Version 页面增加扩展点

**Files:**
- Create: `scripts/check_wifi_gateway_firmware_update.sh`
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift:12-425`
- Modify: `SunSmart/Main/Firmware/View/BetaTestingAlertView.swift:10-266`

**Interfaces:**
- Consumes: 现有 `FirmwareVersionViewController(type:)`、`FirmwareUpdateTypeData`、`BetaTestingAlertView`。
- Produces: `firmwarePageTitle`、`firmwareRequestCustomId`、`displayedCurrentTargetVersion`、`showsFirmwareDeleteButton`、`showsBetaImportAction`、`firmwarePrimaryActionTitle`、`firmwarePrimaryAction()`，以及 `BetaTestingAlertView.init(inputTextCallback:importCallback:showsImportAction:)`。

- [ ] **Step 1: 创建会失败的共享扩展点契约**

创建 `scripts/check_wifi_gateway_firmware_update.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

parent="SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift"
history="SunSmart/Main/Firmware/Controller/FirmwareVersionHistoryController.swift"
beta="SunSmart/Main/Firmware/View/BetaTestingAlertView.swift"
wifi="SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift"
gateway="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
project="SunSmart.xcodeproj/project.pbxproj"
localizable_en="SunSmart/en.lproj/Localizable.strings"
localizable_zh="SunSmart/zh-Hans.lproj/Localizable.strings"

rg -n 'var firmwarePageTitle: String' "$parent" >/dev/null || fail "missing firmware page title hook"
rg -n 'var firmwareRequestCustomId: String' "$parent" >/dev/null || fail "missing firmware customer id hook"
rg -n 'var displayedCurrentTargetVersion: String\?' "$parent" >/dev/null || fail "missing displayed current version hook"
rg -n 'var showsFirmwareDeleteButton: Bool' "$parent" >/dev/null || fail "missing delete visibility hook"
rg -n 'var showsBetaImportAction: Bool' "$parent" >/dev/null || fail "missing beta import visibility hook"
rg -n 'var firmwarePrimaryActionTitle: String' "$parent" >/dev/null || fail "missing primary action title hook"
rg -n '@objc func firmwarePrimaryAction\(\)' "$parent" >/dev/null || fail "missing primary action hook"
rg -n 'customId: firmwareRequestCustomId' "$parent" >/dev/null || fail "latest request ignores customer id hook"
rg -n 'showsImportAction: showsBetaImportAction' "$parent" >/dev/null || fail "beta alert ignores import visibility hook"
rg -n 'title: firmwarePrimaryActionTitle' "$parent" >/dev/null || fail "button ignores title hook"
rg -n '#selector\(firmwarePrimaryAction\)' "$parent" >/dev/null || fail "button ignores action hook"
rg -n 'showsImportAction: Bool = true' "$beta" >/dev/null || fail "beta alert missing default import visibility"
rg -n 'importBtn\.isHidden = !showsImportAction' "$beta" >/dev/null || fail "beta alert does not apply import visibility"

echo "PASS: WiFi Gateway firmware update static checks"
```

Run: `bash scripts/check_wifi_gateway_firmware_update.sh`

Expected: FAIL with `missing firmware page title hook`。

- [ ] **Step 2: 增加默认扩展点并接入标题和最新请求**

在 `FirmwareVersionViewController` 的 `isTesting` 后加入：

```swift
var firmwarePageTitle: String { "firmware_version".localizedString }
var firmwareRequestCustomId: String { "00" }
var displayedCurrentTargetVersion: String? { localFirmwareData?.version }
var showsFirmwareDeleteButton: Bool { localFirmwareData != nil }
var showsBetaImportAction: Bool { true }
var firmwarePrimaryActionTitle: String { "Download".localizedString }
```

将标题和最新请求改为：

```swift
title = firmwarePageTitle

NetworkRequest.shared.request(
    .firmwareLatestVersion(
        deviceType: type.productId.hex,
        customId: firmwareRequestCustomId,
        isTesting: self.isTesting
    )
) { [weak self] result in
```

- [ ] **Step 3: 给 Beta 弹窗增加默认显示的导入配置**

将 `BetaTestingAlertView` initializer 改为：

```swift
private let showsImportAction: Bool

init(
    inputTextCallback: InputTextChangedBack?,
    importCallback: ImportActionCallBack?,
    showsImportAction: Bool = true
) {
    self.showsImportAction = showsImportAction
    super.init(frame: UIScreen.main.bounds)
    self.textValueChangedBack = inputTextCallback
    self.importCallback = importCallback
    setupUI()
}
```

在 import button 配置完成后加入：

```swift
importBtn.isHidden = !showsImportAction
```

父页面创建 Beta 弹窗时增加第三个参数：

```swift
}, importCallback: { [weak self] in
    self?.importFirmwareData()
}, showsImportAction: showsBetaImportAction).show()
```

- [ ] **Step 4: 让固定版本、删除显隐和版本比较走 hook**

将 `updateUI()` 开头的版本展示替换为：

```swift
if let version = displayedCurrentTargetVersion {
    currentVersionLabel.text = version
    versionDeleteBtn.isHidden = !showsFirmwareDeleteButton
    currentVersionLabel.snp.updateConstraints { make in
        make.right.equalTo(SCRXFrom(showsFirmwareDeleteButton ? -64 : -20))
    }
} else {
    currentVersionLabel.text = "none".localizedString
    versionDeleteBtn.isHidden = true
    currentVersionLabel.snp.updateConstraints { make in
        make.right.equalTo(SCRXFrom(-20))
    }
}
```

将新版本判断替换为：

```swift
let hasNewerVersion = displayedCurrentTargetVersion.map {
    newFirmwareData.version.compare($0, options: .numeric) == .orderedDescending
} ?? true

if hasNewerVersion {
```

- [ ] **Step 5: 把下载行为包在可覆写主动作后面**

将现有 `downloadBtnAction()` 替换为以下两个方法：

```swift
@objc func firmwarePrimaryAction() {
    downloadFirmware()
}

private func downloadFirmware() {
    guard let serverData = type.serverData,
          let downloadURL = URL(string: serverData.url) else {
        return
    }

    XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
    ZipHandler.downloadAndHandleZip(from: downloadURL) { [weak self] result in
        XWHUDManager.hide()
        guard let self else { return }
        switch result {
        case .success(let zipData):
            let imageSize = UInt32(zipData.firmwareData.count)
            var incomingFirmwareMetadata = Data(
                bytes: zipData.firmwareId.byteArray,
                count: zipData.firmwareId.count + 3 + 1 + 4 + 2 + 1
            )
            incomingFirmwareMetadata.writeBits(value: imageSize, numBits: 24, atOffset: 64)
            incomingFirmwareMetadata.writeBits(value: UInt8(zipData.coreType), numBits: 8, atOffset: 88)
            incomingFirmwareMetadata.writeBits(value: UInt32(data: zipData.compositionHash), numBits: 32, atOffset: 96)
            incomingFirmwareMetadata.writeBits(value: UInt16(zipData.elementCount), numBits: 16, atOffset: 128)
            incomingFirmwareMetadata.writeBits(value: UInt8(zipData.test ? 1 : 0), numBits: 1, atOffset: 144)
            incomingFirmwareMetadata.writeBits(value: UInt8(zipData.versionCheck ? 1 : 0), numBits: 1, atOffset: 145)

            self.localFirmwareData = .init(
                name: serverData.filename,
                version: serverData.version,
                firmwareID: zipData.firmwareId,
                data: zipData.firmwareData,
                updateFirmwareImageIndex: zipData.imageIndex,
                incomingFirmwareMetadata: incomingFirmwareMetadata,
                productId: serverData.productId,
                vendorId: serverData.companyId,
                customId: serverData.customId,
                releaseDate: serverData.releaseDate,
                content: serverData.content,
                compositionHash: zipData.compositionHash.reversed().toHexString(),
                versionIdentifier: zipData.versionIdentifier
            )
            self.localFirmwareData?.save()
            self.updateLocalFirmwareDataCallback?(self.localFirmwareData)
            self.updateUI()

        case .failure:
            XWHUDManager.showErrorTipHUD("download_failure".localizedString)
        }
    }
}
```

将底部按钮创建替换为：

```swift
downloadBtn = UIButton(
    title: firmwarePrimaryActionTitle,
    titleSize: 16,
    titleWeight: .light,
    titleColor: Bar_Color,
    target: self,
    action: #selector(firmwarePrimaryAction)
)
```

Run: `bash scripts/check_wifi_gateway_firmware_update.sh`

Expected: PASS。

- [ ] **Step 6: 编译验证共享扩展点**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 检查并提交**

```bash
git diff --check
git add scripts/check_wifi_gateway_firmware_update.sh SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift SunSmart/Main/Firmware/View/BetaTestingAlertView.swift
git commit -m "refactor: add firmware version customization hooks"
```

Expected: diff check 无输出；commit 只包含上述三个路径。

---

### Task 2: 让历史版本查询继承字符串 customerId

**Files:**
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift:160-165`
- Modify: `SunSmart/Main/Firmware/Controller/FirmwareVersionHistoryController.swift:45-142`

**Interfaces:**
- Consumes: Task 1 的 `firmwareRequestCustomId: String`。
- Produces: `FirmwareVersionHistoryController.init(productId:customId:)`，`customId` 默认值为 `"00"`。

- [ ] **Step 1: 在 PASS 前加入失败契约**

```bash
rg -n 'let customId: String' "$history" >/dev/null || fail "history missing string customer id"
rg -n 'init\(productId: UInt16, customId: String = "00"\)' "$history" >/dev/null || fail "history initializer missing default customer id"
rg -n 'customId: self\.customId' "$history" >/dev/null || fail "history request ignores customer id"
customer_id_hook_count=$(grep -Fc 'customId: firmwareRequestCustomId' "$parent")
[ "$customer_id_hook_count" -eq 2 ] || fail "latest and history requests must both use the customer id hook"
```

Run: `bash scripts/check_wifi_gateway_firmware_update.sh`

Expected: FAIL with `history missing string customer id`。

- [ ] **Step 2: 修改历史控制器属性、initializer 和请求**

```swift
let productId: UInt16
let customId: String

private var versionDatas: [FirmwareServerData] = []
var isTesting: Bool = false

init(productId: UInt16, customId: String = "00") {
    self.productId = productId
    self.customId = customId
    super.init(nibName: nil, bundle: nil)
}
```

```swift
NetworkRequest.shared.request(
    .firmwareVersionList(
        deviceType: self.productId.hex,
        customId: self.customId,
        isTesting: self.isTesting
    )
) { [weak self] result in
```

- [ ] **Step 3: 父页面传递当前 request identity**

```swift
let vc = FirmwareVersionHistoryController(
    productId: self.type.productId,
    customId: firmwareRequestCustomId
)
vc.isTesting = self.isTesting
navigationController?.pushViewController(vc, animated: true)
```

- [ ] **Step 4: 运行契约和 diff 检查**

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
git diff --check
```

Expected: script PASS；diff check 无输出。

- [ ] **Step 5: 编译验证历史查询改动**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 提交历史查询改动**

```bash
git add scripts/check_wifi_gateway_firmware_update.sh SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift SunSmart/Main/Firmware/Controller/FirmwareVersionHistoryController.swift
git commit -m "feat: support firmware history customer id"
```

Expected: commit 成功。

---

### Task 3: 新增 WiFi 子类、本地化和四 target 引用

**Files:**
- Create: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings:813-908`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings:832-930`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Consumes: Tasks 1-2 的父类 hook 和 history identity。
- Produces: `final class WiFiFirmwareUpdateViewController` 及无参数 `init()`。

- [ ] **Step 1: 在 PASS 前加入 WiFi 子类、localization 和 target 契约**

```bash
[ -f "$wifi" ] || fail "missing WiFiFirmwareUpdateViewController"
rg -n 'final class WiFiFirmwareUpdateViewController: FirmwareVersionViewController' "$wifi" >/dev/null || fail "wrong WiFi firmware superclass"
rg -n 'override var firmwareRequestCustomId: String' "$wifi" >/dev/null || fail "missing wifi customer id override"
rg -n 'return "wifi"' "$wifi" >/dev/null || fail "customer id must be wifi"
rg -n 'override var displayedCurrentTargetVersion: String\?' "$wifi" >/dev/null || fail "missing fixed version override"
rg -n 'return "1\.0\.0"' "$wifi" >/dev/null || fail "fixed version must be 1.0.0"
rg -n 'override var showsFirmwareDeleteButton: Bool' "$wifi" >/dev/null || fail "missing delete visibility override"
rg -n 'override var showsBetaImportAction: Bool' "$wifi" >/dev/null || fail "missing import visibility override"
rg -n '@objc override func firmwarePrimaryAction\(\)' "$wifi" >/dev/null || fail "missing WiFi primary action"
rg -n 'XWHUDManager\.showTipHUD\("under_development"\.localizedString' "$wifi" >/dev/null || fail "WiFi primary action must show under development"

if rg -n 'FirmwareData\.(load|save|delete)|ZipHandler|UIDocumentPickerViewController' "$wifi"; then
  fail "WiFi page must not use Mesh cache, ZIP, or document picker"
fi

rg -n -F '"wifi_dfu" = "WiFi DFU";' "$localizable_en" >/dev/null || fail "missing English WiFi DFU"
rg -n -F '"wifi_firmware_update" = "WiFi Firmware Update";' "$localizable_en" >/dev/null || fail "missing English title"
rg -n -F '"wifi_firmware_upgrade" = "UPGRADE";' "$localizable_en" >/dev/null || fail "missing English button"
rg -n -F '"wifi_dfu" = "WiFi DFU";' "$localizable_zh" >/dev/null || fail "missing Chinese WiFi DFU"
rg -n -F '"wifi_firmware_update" = "WiFi 固件更新";' "$localizable_zh" >/dev/null || fail "missing Chinese title"
rg -n -F '"wifi_firmware_upgrade" = "升级";' "$localizable_zh" >/dev/null || fail "missing Chinese button"

build_ref_count=$(grep -c 'WiFiFirmwareUpdateViewController.swift in Sources \*/ = {isa = PBXBuildFile' "$project" || true)
source_phase_count=$(grep -c 'WiFiFirmwareUpdateViewController.swift in Sources \*/,' "$project" || true)
[ "$build_ref_count" -eq 4 ] || fail "new controller must have four PBXBuildFile entries"
[ "$source_phase_count" -eq 4 ] || fail "new controller must belong to four Sources phases"
```

Run: `bash scripts/check_wifi_gateway_firmware_update.sh`

Expected: FAIL with `missing WiFiFirmwareUpdateViewController`。

- [ ] **Step 2: 创建 WiFi 专用子类**

```swift
import UIKit

final class WiFiFirmwareUpdateViewController: FirmwareVersionViewController {

    convenience init() {
        self.init(
            type: FirmwareUpdateTypeData(
                productId: 0x2721,
                targetVersion: "1.0.0",
                nodes: []
            )
        )
    }

    override var firmwarePageTitle: String {
        return "wifi_firmware_update".localizedString
    }

    override var firmwareRequestCustomId: String { return "wifi" }
    override var displayedCurrentTargetVersion: String? { return "1.0.0" }
    override var showsFirmwareDeleteButton: Bool { return false }
    override var showsBetaImportAction: Bool { return false }

    override var firmwarePrimaryActionTitle: String {
        return "wifi_firmware_upgrade".localizedString
    }

    @objc override func firmwarePrimaryAction() {
        XWHUDManager.showTipHUD(
            "under_development".localizedString,
            isLineFeed: true
        )
    }
}
```

- [ ] **Step 3: 增加两种语言文案**

```text
// SunSmart/en.lproj/Localizable.strings
"wifi_dfu" = "WiFi DFU";
"wifi_firmware_update" = "WiFi Firmware Update";
"wifi_firmware_upgrade" = "UPGRADE";

// SunSmart/zh-Hans.lproj/Localizable.strings
"wifi_dfu" = "WiFi DFU";
"wifi_firmware_update" = "WiFi 固件更新";
"wifi_firmware_upgrade" = "升级";
```

- [ ] **Step 4: 加入 Xcode project 和四个 Sources phases**

使用以下未占用 ID：

```text
C8F6A1052FA3000000000001 /* build file 1 */
C8F6A1062FA3000000000001 /* build file 2 */
C8F6A1072FA3000000000001 /* build file 3 */
C8F6A1082FA3000000000001 /* build file 4 */
C8F6A1092FA3000000000001 /* file reference */
```

PBXBuildFile section 加入：

```text
C8F6A1052FA3000000000001 /* WiFiFirmwareUpdateViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A1092FA3000000000001 /* WiFiFirmwareUpdateViewController.swift */; };
C8F6A1062FA3000000000001 /* WiFiFirmwareUpdateViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A1092FA3000000000001 /* WiFiFirmwareUpdateViewController.swift */; };
C8F6A1072FA3000000000001 /* WiFiFirmwareUpdateViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A1092FA3000000000001 /* WiFiFirmwareUpdateViewController.swift */; };
C8F6A1082FA3000000000001 /* WiFiFirmwareUpdateViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A1092FA3000000000001 /* WiFiFirmwareUpdateViewController.swift */; };
```

PBXFileReference section 和 Firmware Controller group 分别加入：

```text
C8F6A1092FA3000000000001 /* WiFiFirmwareUpdateViewController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WiFiFirmwareUpdateViewController.swift; sourceTree = "<group>"; };

C8F6A1092FA3000000000001 /* WiFiFirmwareUpdateViewController.swift */,
```

四个包含 `FirmwareVersionViewController.swift in Sources` 的 Sources phase 各加入以下条目中的一条，不能把四条放入同一 phase：

```text
C8F6A1052FA3000000000001 /* WiFiFirmwareUpdateViewController.swift in Sources */,
C8F6A1062FA3000000000001 /* WiFiFirmwareUpdateViewController.swift in Sources */,
C8F6A1072FA3000000000001 /* WiFiFirmwareUpdateViewController.swift in Sources */,
C8F6A1082FA3000000000001 /* WiFiFirmwareUpdateViewController.swift in Sources */,
```

- [ ] **Step 5: 运行契约和工程语法检查**

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
plutil -lint SunSmart.xcodeproj/project.pbxproj
git diff --check
```

Expected: script PASS；project 输出 OK；diff check 无输出。

- [ ] **Step 6: 编译验证 WiFi 子类与四 target 引用结构**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 提交 WiFi 页面基础能力**

```bash
git add SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj scripts/check_wifi_gateway_firmware_update.sh
git commit -m "feat: add wifi firmware update page"
```

Expected: commit 成功。

---

### Task 4: 接线菜单并完成回归验证

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:272-300`
- Modify: `scripts/check_wifi_gateway_menu_icons.sh`
- Modify: `scripts/check_wifi_gateway_firmware_update.sh`

**Interfaces:**
- Consumes: Task 3 的 `WiFiFirmwareUpdateViewController.init()` 和 `wifi_dfu` key。
- Produces: WiFi DFU 菜单 push 新页面；四品牌构建证据。

- [ ] **Step 1: 更新旧菜单契约并确认失败**

把图标契约改为：

```bash
check_menu_icon '"wifi_dfu".localizedString' "menu_wifi_dfu"
```

加入导航契约，并将 controller 内 `under_development` 次数由 `2` 改为 `1`（只剩隐藏的 Diagnosis）：

```bash
if ! grep -Fq 'let controller = WiFiFirmwareUpdateViewController()' "$file"; then
  printf 'FAIL: expected WiFi DFU to create WiFiFirmwareUpdateViewController\n'
  failures=$((failures + 1))
fi

if ! grep -Fq 'self.navigationController?.pushViewController(controller, animated: true)' "$file"; then
  printf 'FAIL: expected WiFi DFU to push the firmware update controller\n'
  failures=$((failures + 1))
fi

under_development_count=$(grep -Fc 'XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)' "$file")
if [ "$under_development_count" -ne 1 ]; then
  printf 'FAIL: expected only Diagnosis to keep under development, found %s\n' "$under_development_count"
  failures=$((failures + 1))
fi
```

在新脚本 PASS 前加入：

```bash
rg -n 'title: "wifi_dfu"\.localizedString' "$gateway" >/dev/null || fail "WiFi DFU title is not localized"
rg -n 'let controller = WiFiFirmwareUpdateViewController\(\)' "$gateway" >/dev/null || fail "WiFi DFU does not create new page"
rg -n 'self\.navigationController\?\.pushViewController\(controller, animated: true\)' "$gateway" >/dev/null || fail "WiFi DFU does not push new page"
```

Run: `bash scripts/check_wifi_gateway_menu_icons.sh`

Expected: FAIL，报告菜单仍是旧 placeholder 行为。

- [ ] **Step 2: 将菜单回调替换为导航**

```swift
items.append(.init(
    icon: UIImage(named: "menu_wifi_dfu"),
    title: "wifi_dfu".localizedString,
    hideAnimation: false,
    performsActionAfterDismiss: true,
    tapItemBack: { [weak self] _ in
        guard let self else { return }
        let controller = WiFiFirmwareUpdateViewController()
        self.navigationController?.pushViewController(controller, animated: true)
    }
))
```

- [ ] **Step 3: 运行全部 WiFi Gateway 静态契约**

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
bash scripts/check_wifi_gateway_menu_icons.sh
bash scripts/check_wifi_gateway_apn_removed.sh
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
bash scripts/check_wifi_gateway_info_rows_hidden.sh
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_repair_recovery.sh
bash scripts/check_wifi_gateway_server_information_recovery.sh
bash scripts/check_wifi_gateway_sig_mesh_status_header.sh
bash scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: 所有脚本退出码为 `0` 并输出 PASS。

- [ ] **Step 4: 提交菜单接线**

```bash
git diff --check
git add SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift scripts/check_wifi_gateway_menu_icons.sh scripts/check_wifi_gateway_firmware_update.sh
git commit -m "feat: open wifi gateway firmware update"
```

Expected: diff check 无输出；commit 成功。

- [ ] **Step 5: 检查工程并构建 SunSmart**

```bash
plutil -lint SunSmart.xcodeproj/project.pbxproj
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: project 输出 OK；`** BUILD SUCCEEDED **`。

- [ ] **Step 6: 构建 Archipelago**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 构建 SLG Sync Plus**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 8: 构建 SylSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 9: 最终核对**

```bash
git diff --check
git status --short
git log -5 --oneline
```

Expected: diff check 无输出；没有未提交的本任务改动；最近提交包含本计划四个聚焦 commit。若存在用户原有文件，只报告并保持不动。

---

## 实施完成后的交付说明

最终回复需要报告：

- 最新和历史 API 实际使用 `customerId=wifi`；
- 固定版本、隐藏删除/导入、`UPGRADE` 启用和占位点击结果；
- 普通 Firmware Version 默认行为回归结果；
- 所有聚焦契约和四个 iPhoneOS scheme 的实际结果；
- 本次 commits；
- 未动的用户原有工作区文件。
