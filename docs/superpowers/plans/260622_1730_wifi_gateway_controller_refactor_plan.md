# WiFi Gateway Controller Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 `WiFiGatewayViewController` 继承 `GatewayViewController` 实现 WiFi Gateway 差异行为，并删除全部 `PJNGateway` 相关源码、资源和工程引用。

**Architecture:** App 侧继续用 `Node.isWiFiGateway` 作为 WiFi Gateway 单一判断点。`GatewayViewController` 保持 4G 默认行为，仅开放导航、底部按钮和删除流程的最小 hook；`WiFiGatewayViewController` 只覆盖菜单与 Save-only 底部布局。旧 `PJNGateway` 模块不再参与入口或编译。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、Xcode project.pbxproj、iPhoneOS `xcodebuild`

---

## 执行说明

按本项目 AGENTS 约定，确认计划后默认使用 Inline Execution，不再询问 subagent 执行方式。实现过程中每个任务完成后做局部检查，最后统一构建验证。

当前工作区有既有未提交改动：

- `SunSmart/devices_config.json`

执行本计划时不要修改、暂存或提交该文件。

## 文件结构

- Modify: `SunSmart/Main/Device/View/DeviceBottomBtnView.swift`
  - 增加 `showSaveOnlyUI()`，让共享底部按钮支持单行 Save。
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - 增加子类 hook，开放关闭与删除入口，保留 4G 默认行为。
- Create: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - WiFi Gateway 专用子类，负责菜单、Identify 和 Save-only 底部。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - WiFi Gateway 入口改为 `WiFiGatewayViewController`。
- Modify: `SunSmart.xcodeproj/project.pbxproj`
  - 添加 `WiFiGatewayViewController.swift` 到四个品牌 target。
  - 删除所有 `PJNGateway` / `NGateWay` 源码引用。
- Delete: `SunSmart/Main/Device/Device1.5/NGateWay/`
  - 删除旧 PJNGateway 模块源码、ViewModel、View、Model、Add/Restore 容器和说明文档。
- Delete: `SunSmart/Assets.xcassets/Gateway1.5/`
  - 删除旧 Gateway1.5 资源。
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 删除确认未使用的 `ngateway_*` 文案块。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 删除确认未使用的 `ngateway_*` 文案块。
- Modify: `SunSmart/Main/Device/Device1.5/devices1.5.md`
  - 删除 NGateWay 模块介绍与接手说明残留。

## Task 1: 父类 Hook 与底部 Save-only 模式

**Files:**
- Modify: `SunSmart/Main/Device/View/DeviceBottomBtnView.swift`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`

- [ ] **Step 1: 增加底部 Save-only 展示方法**

在 `DeviceBottomBtnView` 中新增 `showSaveOnlyUI()`，并让 `showEditUI()` 每次恢复双按钮约束，避免从 WiFi 页面回到 4G 双按钮时残留 full-width 约束。

```swift
func showEditUI() {
    saveBtn.isHidden = false
    btnLineView.isHidden = false
    deleteBtn.isHidden = false
    createBtn.isHidden = true

    saveBtn.snp.remakeConstraints { make in
        make.right.top.equalToSuperview()
        make.left.equalTo(self.snp.centerX)
        make.height.equalTo(deleteBtn)
    }
}

func showSaveOnlyUI() {
    saveBtn.isHidden = false
    btnLineView.isHidden = true
    deleteBtn.isHidden = true
    createBtn.isHidden = true

    saveBtn.snp.remakeConstraints { make in
        make.left.right.top.equalToSuperview()
        make.height.equalTo(SCRYFrom(56))
    }
}
```

- [ ] **Step 2: 在父类开放必要 UI 成员**

把 `GatewayViewController` 中 `bottomView` 从 `private` 改成对子类可读：

```swift
private(set) var bottomView: DeviceBottomBtnView!
```

保留 `tableView`、`headerView`、`setGatewayModel` 等未被子类直接使用的成员为 `private`。

- [ ] **Step 3: 抽出导航栏 hook**

把 `viewDidLoad()` 中直接设置右侧关闭按钮的代码改为调用 hook：

```swift
configureNavigationItems()
```

在类内新增默认实现：

```swift
func configureNavigationItems() {
    navigationItem.rightBarButtonItem = UIBarButtonItem(
        image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal),
        style: .done,
        target: self,
        action: #selector(closeAction)
    )
}
```

- [ ] **Step 4: 开放关闭入口**

把 `closeAction` 从 `private` 改成可被子类 selector 使用：

```swift
@objc func closeAction() {
    if setGatewayModel == gatewayModel {
        closeGatewayPage()
    } else {
        SRAlertView(
            title: "notification".localizedString,
            message: "profile_exiting_message".localizedString,
            actions: [
                SRAlertAction(title: "keep_edit".localizedString, style: .cancel),
                SRAlertAction(title: "EXIT".localizedString, actionHandler: { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.closeGatewayPage()
                    }
                })
            ]
        ).show()
    }
}
```

把原 `close()` 改名为：

```swift
func closeGatewayPage() {
    if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1 {
        dismiss(animated: true)
    } else {
        navigationController?.popViewController(animated: true)
    }
}
```

- [ ] **Step 5: 抽出底部布局 hook**

在 `GatewayViewController` 新增两个 hook：

```swift
func showConfiguredBottomActions() {
    bottomView.showEditUI()
}

func showRepairBottomActions() {
    bottomView.showCreateUI()
}
```

把 `updateData()` 中的直接调用替换为：

```swift
showConfiguredBottomActions()
```

和：

```swift
showRepairBottomActions()
```

4G Gateway 默认行为不变。

- [ ] **Step 6: 开放删除动作给子类复用**

把删除按钮 action 从：

```swift
@objc private func deleteBtnAction()
```

改为：

```swift
@objc func deleteBtnAction()
```

不改方法体，确保 WiFi 子类调用的是当前 4G Gateway 删除流程。

- [ ] **Step 7: 局部检查**

运行：

```bash
rg -n "private func close\\(|private func closeAction|private func deleteBtnAction|showSaveOnlyUI|showConfiguredBottomActions|showRepairBottomActions" SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift SunSmart/Main/Device/View/DeviceBottomBtnView.swift
```

Expected:

- 不再出现 `private func close(`。
- 不再出现 `private func closeAction`。
- 不再出现 `private func deleteBtnAction`。
- 出现 `showSaveOnlyUI`、`showConfiguredBottomActions`、`showRepairBottomActions`。

## Task 2: 新增 WiFiGatewayViewController

**Files:**
- Create: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: 创建 WiFiGatewayViewController 文件**

新增文件内容：

```swift
//
//  WiFiGatewayViewController.swift
//  SunSmart
//

import UIKit
import NordicSigMeshSDK

final class WiFiGatewayViewController: GatewayViewController {

    override func configureNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(closeAction)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(moreClick)
        )
    }

    override func showConfiguredBottomActions() {
        bottomView.showSaveOnlyUI()
    }

    override func showRepairBottomActions() {
        bottomView.showSaveOnlyUI()
    }

    @objc private func moreClick() {
        var items: [MenuPopView.MenuItem] = []
        items.append(.init(icon: UIImage(named: "menu_information"), title: "WiFi DFU", tapItemBack: { _ in
        }))
        if site.deviceOperates.contains(.edit) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
                self?.deleteBtnAction()
            }))
        }
        items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { _ in
        }))
        items.append(.init(icon: UIImage(named: "device_identify"), title: "Identify", tapItemBack: { [weak self] _ in
            guard let self else { return }
            MeshAPI.identify(address: self.node.primaryUnicastAddress)
        }))
        items.append(.init(icon: UIImage(named: "menu_information"), title: "Diagnosis", tapItemBack: { _ in
        }))

        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(120))
    }
}
```

- [ ] **Step 2: 添加 Xcode project 引用**

在 `SunSmart.xcodeproj/project.pbxproj` 添加 `WiFiGatewayViewController.swift` 文件引用和四个 Sources build file。使用新的 24 位 PBX ID，先确认不重复：

```bash
rg -n "C8F6A1002FA3000000000001|C8F6A1012FA3000000000001|C8F6A1022FA3000000000001|C8F6A1032FA3000000000001|C8F6A1042FA3000000000001" SunSmart.xcodeproj/project.pbxproj
```

Expected: no output.

新增条目示例：

```pbxproj
C8F6A1002FA3000000000001 /* WiFiGatewayViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A1042FA3000000000001 /* WiFiGatewayViewController.swift */; };
C8F6A1012FA3000000000001 /* WiFiGatewayViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A1042FA3000000000001 /* WiFiGatewayViewController.swift */; };
C8F6A1022FA3000000000001 /* WiFiGatewayViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A1042FA3000000000001 /* WiFiGatewayViewController.swift */; };
C8F6A1032FA3000000000001 /* WiFiGatewayViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A1042FA3000000000001 /* WiFiGatewayViewController.swift */; };
C8F6A1042FA3000000000001 /* WiFiGatewayViewController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WiFiGatewayViewController.swift; sourceTree = "<group>"; };
```

把 file reference 插入 Gateway Controller group，紧挨 `GatewayViewController.swift`：

```pbxproj
C8D22DFF2E010A47001A2BDA /* GatewayViewController.swift */,
C8F6A1042FA3000000000001 /* WiFiGatewayViewController.swift */,
```

把四个 Sources build file 分别插入四个 Sources build phase，紧挨现有 `GatewayViewController.swift in Sources`。

- [ ] **Step 3: 局部检查**

运行：

```bash
rg -n "WiFiGatewayViewController.swift" SunSmart.xcodeproj/project.pbxproj SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
```

Expected:

- Swift 文件存在。
- project 文件中有 1 个 `PBXFileReference`。
- project 文件中有 4 个 `PBXBuildFile`。
- project 文件中有 4 个 Sources build phase 引用。

## Task 3: Site Gateway 入口分流

**Files:**
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`

- [ ] **Step 1: 替换 WiFi Gateway 入口 controller**

把 `gatewayOperationClickAction(_:)` 中 WiFi Gateway 分支从：

```swift
gatewayVc = PJNGatewayViewController(site: site, gateway: gateway)
```

改为：

```swift
guard let controller = WiFiGatewayViewController(site: site, gateway: gateway) else {
    XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
    return
}
gatewayVc = controller
```

4G Gateway 分支继续保留：

```swift
guard let controller = GatewayViewController(site: site, gateway: gateway) else {
    XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
    return
}
gatewayVc = controller
```

- [ ] **Step 2: 局部检查**

运行：

```bash
rg -n "PJNGatewayViewController|WiFiGatewayViewController|GatewayViewController\\(site: site, gateway: gateway\\)" SunSmart/Main/Site/Controller/SiteViewController.swift
```

Expected:

- 不再出现 `PJNGatewayViewController`。
- 出现 `WiFiGatewayViewController(site: site, gateway: gateway)`。
- 仍出现 `GatewayViewController(site: site, gateway: gateway)`。

## Task 4: 删除 PJNGateway 源码、资源和本地化残留

**Files:**
- Delete: `SunSmart/Main/Device/Device1.5/NGateWay/`
- Delete: `SunSmart/Assets.xcassets/Gateway1.5/`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `SunSmart/Main/Device/Device1.5/devices1.5.md`

- [ ] **Step 1: 删除源码和资源目录**

使用 Git 删除目录：

```bash
git rm -r SunSmart/Main/Device/Device1.5/NGateWay
git rm -r SunSmart/Assets.xcassets/Gateway1.5
```

Expected:

- `git status --short` 显示上述目录下文件为 deleted。
- 不包含 `SunSmart/devices_config.json` 暂存。

- [ ] **Step 2: 清理 project.pbxproj 中旧引用**

从 `SunSmart.xcodeproj/project.pbxproj` 删除所有匹配以下关键词的条目和 group 引用：

- `PJNGateway`
- `NGateWay`
- `Gateway1.5`
- `PJDevicesGatewayAddContainerController`
- `PJDevicesGatewayRestoreContainerController`

清理后运行：

```bash
rg -n "PJNGateway|NGateWay|Gateway1\\.5|PJDevicesGatewayAddContainerController|PJDevicesGatewayRestoreContainerController" SunSmart.xcodeproj/project.pbxproj
```

Expected: no output.

- [ ] **Step 3: 删除本地化残留**

在以下文件删除所有 `ngateway_*` 文案和 `//v1.5-- NGateWay` 注释块：

```bash
SunSmart/en.lproj/Localizable.strings
SunSmart/zh-Hans.lproj/Localizable.strings
```

保留其他 v1.5 模块文案，例如 `FireAlarm` 和 `NEightKeySwitches`。

清理后运行：

```bash
rg -n "ngateway_|v1\\.5-- NGateWay" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: no output.

- [ ] **Step 4: 更新 Device1.5 说明**

在 `SunSmart/Main/Device/Device1.5/devices1.5.md` 中：

- 从总览移除 `NGateWay` bullet。
- 从接手优先级移除 `NGateWay`。
- 删除 `## NGateWay 网桥` 整节。
- 删除 “`NGateWay/ngateWay.md` 当前处于删除状态” 这类残留。

清理后运行：

```bash
rg -n "NGateWay|WiFi DFU|Gateway1\\.5" SunSmart/Main/Device/Device1.5/devices1.5.md
```

Expected: no output.

## Task 5: 引用残留与构建验证

**Files:**
- Verify only

- [ ] **Step 1: 全仓残留搜索**

运行：

```bash
rg -n "PJNGateway|NGateWay|Gateway1\\.5|Identify_gateway|ngateway_" SunSmart SunSmart.xcodeproj/project.pbxproj -S
```

Expected:

- 不再出现业务代码、资源、project 或本地化残留。
- 如果只在已提交历史文档中出现，不影响当前工作树；本命令限定 `SunSmart` 和 project 文件，不扫描 `docs/` 历史设计。

- [ ] **Step 2: 检查本次变更未混入 devices_config**

运行：

```bash
git diff --name-only
git diff --cached --name-only
```

Expected:

- `SunSmart/devices_config.json` 可以出现在 unstaged diff。
- `SunSmart/devices_config.json` 不应出现在 staged diff。

- [ ] **Step 3: 静态 diff 检查**

运行：

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 4: iPhoneOS 构建验证**

运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds。
- 如果失败原因是 CocoaPods support files 缺失，先报告失败原因；只在需要时运行 `pod install`，并检查是否产生无关 project churn。

- [ ] **Step 5: 相关 target 引用检查**

因为本轮删除资源和 project 引用，至少运行 project 级残留检查：

```bash
rg -n "PJNGateway|NGateWay|Gateway1\\.5" SunSmart.xcodeproj/project.pbxproj
```

Expected: no output.

如果 `SunSmart` build 成功但 project 残留检查失败，继续清理 project。若 project 残留检查通过，一般表示 `Archipelago`、`SLG Sync Plus`、`SylSmart` 不再含已删除文件引用；如时间允许，再补充指定 scheme 的 iPhoneOS build。

## Task 6: 提交实现

**Files:**
- All implementation files except `SunSmart/devices_config.json`

- [ ] **Step 1: 审查变更文件**

运行：

```bash
git status --short
git diff --stat
```

Expected:

- 包含 Gateway 父类、WiFi 子类、Site 入口、project 文件、本地化、Device1.5 说明、删除的 PJNGateway 目录和 Gateway1.5 资源。
- `SunSmart/devices_config.json` 仍是 unstaged user change。

- [ ] **Step 2: 暂存本次实现文件**

暂存所有实现相关文件，排除 `SunSmart/devices_config.json`：

```bash
git add SunSmart/Main/Device/View/DeviceBottomBtnView.swift
git add SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
git add SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
git add SunSmart/Main/Site/Controller/SiteViewController.swift
git add SunSmart.xcodeproj/project.pbxproj
git add SunSmart/en.lproj/Localizable.strings
git add SunSmart/zh-Hans.lproj/Localizable.strings
git add SunSmart/Main/Device/Device1.5/devices1.5.md
git add -u SunSmart/Main/Device/Device1.5/NGateWay
git add -u SunSmart/Assets.xcassets/Gateway1.5
```

检查：

```bash
git diff --cached --name-only
```

Expected:

- 不包含 `SunSmart/devices_config.json`。
- 包含删除的 `NGateWay` 和 `Gateway1.5` 文件。

- [ ] **Step 3: 提交实现**

```bash
git commit -m "feat: add wifi gateway controller"
```

Expected: commit succeeds.

## Spec Coverage Checklist

- WiFi Gateway CID/PID 判断：已有 `Node.isWiFiGateway`，Task 3 使用它分流。
- 4G Gateway 保持现状：Task 1 hook 默认实现保留原行为，Task 3 4G 仍进入 `GatewayViewController`。
- WiFi Gateway 新 controller 继承父类：Task 2 创建 `WiFiGatewayViewController: GatewayViewController`。
- WiFi Gateway 底部 Save 独占一整行：Task 1 增加 `showSaveOnlyUI()`，Task 2 子类覆盖底部 hook。
- WiFi Gateway 菜单：Task 2 实现五个菜单项。
- WiFi DFU / Information / Diagnosis 暂不实现：Task 2 对应菜单闭包为空。
- Delete 复用 4G 删除：Task 1 开放 `deleteBtnAction()`，Task 2 调用父类方法。
- Identify 发送一次 SIG Mesh identify：Task 2 调用 `MeshAPI.identify(address:)` 一次。
- 不使用 PJNGateway：Task 3 替换入口，Task 4 删除源码、资源、project 和本地化残留。
- 多 target 影响检查：Task 5 project 残留检查和 iPhoneOS build。
