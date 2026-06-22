# WiFi Gateway Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `0x0A78 / 0x2721` Gateway 从 Site 入口进入 WiFi Gateway 页面，并让其他 Gateway 保持旧 4G 页面行为。

**Architecture:** 在 App 侧 `Node` 扩展新增单一事实源 `isWiFiGateway`，Site Gateway 入口按该 predicate 分流。WiFi Gateway 使用现有 `PJNGatewayViewController`，并将暂不实现的菜单项收口为空操作；4G Gateway 继续使用旧 `GatewayViewController`。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, SnapKit, Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - Responsibility: 保存 App 侧基于 CID/PID 的 WiFi Gateway 判断，避免入口和页面散落硬编码。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - Responsibility: Site Gateway 状态入口按 `gateway.node.isWiFiGateway` 分流到 WiFi 或 4G 页面。
- Modify: `SunSmart/Main/Device/Device1.5/NGateWay/Controller/PJNGatewayViewController.swift`
  - Responsibility: WiFi Gateway 页面右上角菜单展示五个选项，并只让 Delete/Identify 执行真实功能。
- Verify only: `SunSmart/devices_config.json`
  - Responsibility: 已有未提交修改包含 `0x0A78 / 0x2721` Gateway 配置。本计划不修改该文件，但执行前后都要确认不覆盖它。

## Task 1: Add WiFi Gateway Predicate

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1817-1858`

- [ ] **Step 1: Add constants near existing device capability constants**

Insert the WiFi Gateway constants after `externalLightSensorCapableLuminaireProductIdentifiers` and before `unsupportedMotionSensitivityCompanyIdentifier`:

```swift
    private static let wifiGatewayCompanyIdentifier: UInt16 = 0x0A78
    private static let wifiGatewayProductIdentifiers: Set<UInt16> = [0x2721]
```

- [ ] **Step 2: Add static predicate after `isExternalLightSensorCapableLuminaire`**

Add this method immediately after `static func isExternalLightSensorCapableLuminaire(...)`:

```swift
    static func isWiFiGateway(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
        guard companyIdentifier == wifiGatewayCompanyIdentifier,
              let productIdentifier else {
            return false
        }
        return wifiGatewayProductIdentifiers.contains(productIdentifier)
    }
```

- [ ] **Step 3: Add instance property near other Node capability properties**

Add this property after `var isExternalLightSensorCapableLuminaire: Bool` and before `var isSupportVendorIdentify: Bool`:

```swift
    var isWiFiGateway: Bool {
        return Node.isWiFiGateway(
            companyIdentifier: companyIdentifier,
            productIdentifier: productIdentifier
        )
    }
```

- [ ] **Step 4: Run focused static search**

Run:

```bash
rg -n "wifiGateway|isWiFiGateway" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

```text
SunSmart/Common/Data/MeshNetwork+SunSmart.swift:<line>:    private static let wifiGatewayCompanyIdentifier: UInt16 = 0x0A78
SunSmart/Common/Data/MeshNetwork+SunSmart.swift:<line>:    private static let wifiGatewayProductIdentifiers: Set<UInt16> = [0x2721]
SunSmart/Common/Data/MeshNetwork+SunSmart.swift:<line>:    static func isWiFiGateway(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
SunSmart/Common/Data/MeshNetwork+SunSmart.swift:<line>:    var isWiFiGateway: Bool {
```

## Task 2: Route Site Gateway Entry

**Files:**
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:2230-2239`

- [ ] **Step 1: Replace fixed old Gateway controller creation**

Replace the current block:

```swift
        guard let gatewayVc = GatewayViewController(site: site, gateway: gateway) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
            return
        }
        if isIPad {
            gatewayVc.preferredContentSize = iPadStandardSize
        }
        //测试v1.5网桥
       // let gatewayVc = PJNGatewayViewController(site: site, gateway: gateway)
        present(NavigationViewController(rootViewController: gatewayVc), animated: true)
```

with:

```swift
        let gatewayVc: UIViewController
        if gateway.node.isWiFiGateway {
            gatewayVc = PJNGatewayViewController(site: site, gateway: gateway)
        } else {
            guard let controller = GatewayViewController(site: site, gateway: gateway) else {
                XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
                return
            }
            gatewayVc = controller
        }
        if isIPad {
            gatewayVc.preferredContentSize = iPadStandardSize
        }
        present(NavigationViewController(rootViewController: gatewayVc), animated: true)
```

- [ ] **Step 2: Confirm the old test comment is gone**

Run:

```bash
rg -n "测试v1.5网桥|PJNGatewayViewController\\(site" SunSmart/Main/Site/Controller/SiteViewController.swift
```

Expected:

```text
SunSmart/Main/Site/Controller/SiteViewController.swift:<line>:            gatewayVc = PJNGatewayViewController(site: site, gateway: gateway)
```

The command must not print `测试v1.5网桥`.

## Task 3: Restrict WiFi Gateway Menu Actions

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NGateWay/Controller/PJNGatewayViewController.swift:283-320`

- [ ] **Step 1: Replace `moreClick()` menu item actions**

Replace the full `moreClick()` method with:

```swift
    @objc private func moreClick() {
        var items: [MenuPopView.MenuItem] = []
        items.append(.init(icon: UIImage(named: "menu_information"), title: "WiFi DFU", tapItemBack: { _ in
        }))
        if pageViewModel.site.deviceOperates.contains(.delete) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
                self?.deleteGateway()
            }))
        }
        items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { _ in
        }))
        items.append(.init(icon: UIImage(named: "Identify_gateway"), title: "Identify", tapItemBack: { [weak self] _ in
            guard let self else { return }
            MeshAPI.identify(address: self.pageViewModel.node.primaryUnicastAddress)
        }))
        items.append(.init(icon: UIImage(named: "menu_information"), title: "Diagnosis", tapItemBack: { _ in
        }))

        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(120))
    }
```

- [ ] **Step 2: Remove unused private navigation helpers**

Delete these methods because the placeholder menu items no longer call them:

```swift
    private func showInformation() {
        navigationController?.pushViewController(DeviceInformationViewController(node: pageViewModel.node), animated: true)
    }

    private func showWiFiDFU() {
        let controller = PJNGatewayWiFiDFUViewController(node: pageViewModel.node)
        if isIPad {
            controller.preferredContentSize = iPadPreferredContentSize
        }
        navigationController?.pushViewController(controller, animated: true)
    }
```

- [ ] **Step 3: Confirm placeholder actions do not call feature pages or HUD**

Run:

```bash
rg -n "showWiFiDFU|showInformation|PJNGatewayWiFiDFUViewController|DeviceInformationViewController\\(node: pageViewModel.node\\)|Diagnosis\"" SunSmart/Main/Device/Device1.5/NGateWay/Controller/PJNGatewayViewController.swift
```

Expected:

```text
SunSmart/Main/Device/Device1.5/NGateWay/Controller/PJNGatewayViewController.swift:<line>:        items.append(.init(icon: UIImage(named: "menu_information"), title: "Diagnosis", tapItemBack: { _ in
```

The command must not print `showWiFiDFU`, `showInformation`, `PJNGatewayWiFiDFUViewController`, or `DeviceInformationViewController(node: pageViewModel.node)`.

## Task 4: Verify and Commit

**Files:**
- Verify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Verify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NGateWay/Controller/PJNGatewayViewController.swift`
- Do not stage: `SunSmart/devices_config.json`

- [ ] **Step 1: Format touched Swift files**

Run:

```bash
swiftformat SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Device/Device1.5/NGateWay/Controller/PJNGatewayViewController.swift
```

Expected: command exits successfully. If `swiftformat` is not installed, skip this step and do not use another formatter.

- [ ] **Step 2: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 3: Verify only expected files changed**

Run:

```bash
git status --short
```

Expected changed files:

```text
 M SunSmart/Common/Data/MeshNetwork+SunSmart.swift
 M SunSmart/Main/Device/Device1.5/NGateWay/Controller/PJNGatewayViewController.swift
 M SunSmart/Main/Site/Controller/SiteViewController.swift
 M SunSmart/devices_config.json
```

`SunSmart/devices_config.json` is pre-existing user work and must remain unstaged.

- [ ] **Step 4: Build iPhoneOS SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build completes with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Stage only implementation files**

Run:

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Device/Device1.5/NGateWay/Controller/PJNGatewayViewController.swift
```

Expected:

```bash
git diff --cached --name-only
```

prints:

```text
SunSmart/Common/Data/MeshNetwork+SunSmart.swift
SunSmart/Main/Device/Device1.5/NGateWay/Controller/PJNGatewayViewController.swift
SunSmart/Main/Site/Controller/SiteViewController.swift
```

- [ ] **Step 6: Commit implementation**

Run:

```bash
git commit -m "feat: route wifi gateway entry"
```

Expected: commit succeeds. `SunSmart/devices_config.json` remains modified but unstaged after the commit.

## Plan Self-Review

- Spec coverage: Task 1 implements the App-side WiFi Gateway predicate; Task 2 implements Site entry routing; Task 3 implements menu behavior and placeholder boundaries; Task 4 covers static checks, iPhoneOS build, staging discipline, and commit.
- Placeholder scan: No unresolved marker words or unspecified validation steps remain.
- Type consistency: The plan defines `Node.isWiFiGateway(companyIdentifier:productIdentifier:)` and `node.isWiFiGateway`, then uses `gateway.node.isWiFiGateway` in the Site route.
