# Profile Lack Sensitivity Notice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Profile 编辑页的 `Relative sensitivity` 标题行右侧显示 lack sensitivity 设备提示。

**Architecture:** `ProfileSettingsViewController` 只负责根据当前 group 的 nodes 计算是否存在 lack sensitivity 设备；`ProfileSensitivityView` 只负责展示和布局右侧提示。文案通过现有 `Localizable.strings` 管理，不新增资源或业务数据模型。

**Tech Stack:** Swift、UIKit、SnapKit、iOS 本地化字符串、Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 新增英文文案 key，放在 `relative_sensitivity` 附近。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 新增中文文案 key，放在 `relative_sensitivity` 附近。
- Modify: `SunSmart/Main/Profile/View/ProfileSensitivityView.swift`
  - 增加右侧提示 label 和公开布尔属性。
  - 调整标题行约束，保证左侧标题和 help 按钮不被压缩，右侧提示可换行并与标题垂直居中。
- Modify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
  - 在 `showSensitivity` 计算后，将 group 中是否存在 `isExternalLightSensorCapableLuminaire` 的结果传给 `ProfileSensitivityView`。

## Task 1: Add Localized Strings

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings:1380`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings:1381`

- [ ] **Step 1: Add English string near `relative_sensitivity`**

Add:

```text
"profile_some_devices_lack_sensitivity" = "Some devices lack sensitivity";
```

Expected position:

```text
"relative_sensitivity" = "Relative sensitivity";
"profile_some_devices_lack_sensitivity" = "Some devices lack sensitivity";
"absolute_sensitivity" = "Absolute Sensitivity";
```

- [ ] **Step 2: Add Simplified Chinese string near `relative_sensitivity`**

Add:

```text
"profile_some_devices_lack_sensitivity" = "部分设备缺少灵敏度";
```

Expected position:

```text
"relative_sensitivity" = "相对灵敏度";
"profile_some_devices_lack_sensitivity" = "部分设备缺少灵敏度";
"absolute_sensitivity" = "绝对灵敏度";
```

- [ ] **Step 3: Verify the key exists in both localizations**

Run:

```bash
rg -n '"profile_some_devices_lack_sensitivity"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: one match in each file.

## Task 2: Extend ProfileSensitivityView UI

**Files:**
- Modify: `SunSmart/Main/Profile/View/ProfileSensitivityView.swift:28-101`

- [ ] **Step 1: Add a private warning label property**

Add the property with the existing UI properties:

```swift
private var lackSensitivityLabel: UILabel!
```

- [ ] **Step 2: Add a public state property**

Add this property near `editable`:

```swift
/// 是否显示部分设备缺少灵敏度提示
var showLackSensitivityNotice: Bool = false {
    didSet {
        lackSensitivityLabel.isHidden = !showLackSensitivityNotice
    }
}
```

- [ ] **Step 3: Configure title/help compression resistance**

After creating `titleLabel`, set:

```swift
titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
titleLabel.setContentHuggingPriority(.required, for: .horizontal)
```

After creating `helpBtn`, set:

```swift
helpBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
helpBtn.setContentHuggingPriority(.required, for: .horizontal)
```

- [ ] **Step 4: Add the warning label**

Add this after `helpBtn` constraints and before `sensitivitySlider` creation:

```swift
lackSensitivityLabel = UILabel(
    text: "profile_some_devices_lack_sensitivity".localizedString,
    textColor: RGB(255, 167, 44),
    fontSize: 12,
    fontWeight: .regular,
    fit: false
)
lackSensitivityLabel.textAlignment = .right
lackSensitivityLabel.numberOfLines = 0
lackSensitivityLabel.isHidden = true
lackSensitivityLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
lackSensitivityLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
addSubview(lackSensitivityLabel)
lackSensitivityLabel.snp.makeConstraints { make in
    make.left.greaterThanOrEqualTo(helpBtn.snp.right).offset(SCRXFrom(8))
    make.right.equalTo(SCRXFrom(-16))
    make.centerY.equalTo(titleLabel)
}
```

- [ ] **Step 5: Run a targeted compile check through Xcode build later**

No standalone unit test exists for this UIKit view. Defer compile verification to Task 4.

## Task 3: Pass Group State from ProfileSettingsViewController

**Files:**
- Modify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift:663-669`

- [ ] **Step 1: Set the notice state beside `sensitivityView.isHidden`**

Change the block around `sensitivityView.isHidden = !showSensitivity` to:

```swift
sensitivityView.isHidden = !showSensitivity
sensitivityView.showLackSensitivityNotice = showSensitivity && (group?.nodes.contains { $0.isExternalLightSensorCapableLuminaire } == true)
if !showSensitivity {
    sensitivityView.snp.removeConstraints()
}
```

Expected behavior:

- `showSensitivity == false`: notice is hidden because the whole view is hidden.
- `showSensitivity == true` and group has a lack sensitivity node: notice is visible.
- `showSensitivity == true` and group is nil, empty, or has no lack sensitivity node: notice is hidden.

## Task 4: Verify and Commit

**Files:**
- Verify all modified files.

- [ ] **Step 1: Check changed files**

Run:

```bash
git diff -- SunSmart/Main/Profile/View/ProfileSensitivityView.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

- Only the four intended files changed.
- No unrelated formatting churn.
- No Auth information added.

- [ ] **Step 2: Run iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 3: Inspect git status**

Run:

```bash
git status --short
```

Expected: only intended implementation files and this plan document are modified or added.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add docs/260602_1817_profile_lack_sensitivity_notice_plan.md SunSmart/Main/Profile/View/ProfileSensitivityView.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: show lack sensitivity notice in profiles"
```

Expected: one implementation commit.

## Self-Review

- Spec coverage: profile type visibility, lack sensitivity detection, Figma styling, localization, non-goals, and build validation are covered.
- Placeholder scan: no placeholders or deferred implementation details remain.
- Type consistency: `showLackSensitivityNotice` is defined on `ProfileSensitivityView` and used by `ProfileSettingsViewController`; `isExternalLightSensorCapableLuminaire` already exists on `Node`.
