# Power Switch Select Scene Numbered Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 AC/Battery Power Switch Edit -> Select Scene 页顶部标题显示 `Scene 1`、`Scene 2`、`Scene 3`、`Scene 4`。

**Architecture:** 在 `SwitchSelectScenePageController` 增加局部标题显示风格，默认继续使用 `Scene A/B/C/D`，AC/Battery Edit 入口显式传入 numbered 风格。保留 `SwitchSceneData.SceneType` 的 `.sceneA/.sceneB/.sceneC/.sceneD` 数据语义，不改变选择回调、保存字段或同步逻辑。

**Tech Stack:** Swift, UIKit, WMPageController, SunSmart iOS workspace.

---

## File Structure

- Modify: `SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift`
  - 增加 Select Scene 顶部标题显示风格。
  - 默认标题保持 `switch_key_sceneA/B/C/D`。
  - numbered 标题使用现有 `neightkeyswitches_scene_1/2/3/4`。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - AC/Battery Power Switch Edit 入口创建 Select Scene 页面时传入 numbered 标题风格。
- Do not modify: `SunSmart/en.lproj/Localizable.strings`
  - 已存在 `neightkeyswitches_scene_1/2/3/4`。
- Do not modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 已存在 `neightkeyswitches_scene_1/2/3/4`。
- Reference only: `docs/260624_1106_power_switch_select_scene_numbered_tabs_design.md`
  - 已确认设计和验收标准。

## Task 1: Confirm Baseline

**Files:**
- Inspect: `SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift`
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Inspect: `SunSmart/en.lproj/Localizable.strings`
- Inspect: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Re-read current tab title source**

Run:

```bash
nl -ba SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift | sed -n '11,25p'
```

Expected: `SwitchSceneData.SceneType.title` returns `switch_key_sceneA`, `switch_key_sceneB`, `switch_key_sceneC`, and `switch_key_sceneD`.

- [ ] **Step 2: Re-read AC/Battery Edit entry**

Run:

```bash
nl -ba SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift | sed -n '266,282p'
```

Expected: `SwitchSelectScenePageController` is created with `scenes` and `sceneDatas`, with no title style parameter yet.

- [ ] **Step 3: Confirm numbered localization keys exist in both supported languages**

Run:

```bash
rg -n '"neightkeyswitches_scene_[1-4]"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 8 matches total, 4 in English and 4 in zh-Hans.

- [ ] **Step 4: Confirm clean workspace**

Run:

```bash
git status --short
```

Expected: empty output.

## Task 2: Add Select Scene Title Style

**Files:**
- Modify: `SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift`

- [ ] **Step 1: Add title style enum and helper**

In `SwitchSelectScenePageController.swift`, update `SwitchSceneData.SceneType` so it contains this helper while keeping the existing `title` behavior:

```swift
        var title: String {
            title(style: .lettered)
        }

        func title(style: SwitchSelectScenePageController.TitleStyle) -> String {
            switch style {
            case .lettered:
                switch self {
                case .sceneA:
                    return "switch_key_sceneA".localizedString
                case .sceneB:
                    return "switch_key_sceneB".localizedString
                case .sceneC:
                    return "switch_key_sceneC".localizedString
                case .sceneD:
                    return "switch_key_sceneD".localizedString
                }
            case .numbered:
                switch self {
                case .sceneA:
                    return "neightkeyswitches_scene_1".localizedString
                case .sceneB:
                    return "neightkeyswitches_scene_2".localizedString
                case .sceneC:
                    return "neightkeyswitches_scene_3".localizedString
                case .sceneD:
                    return "neightkeyswitches_scene_4".localizedString
                }
            }
        }
```

Inside `SwitchSelectScenePageController`, add:

```swift
    enum TitleStyle {
        case lettered
        case numbered
    }
```

- [ ] **Step 2: Add stored style and initializer parameter**

Update the class properties and initializer so the class contains:

```swift
    let titleStyle: TitleStyle
```

and the initializer signature becomes:

```swift
    init(
        scenes: [Scene],
        sceneDatas: [SwitchSceneData] = [.init(type: .sceneA), .init(type: .sceneB)],
        titleStyle: TitleStyle = .lettered
    ) {
        self.scenes = scenes
        super.init(nibName: nil, bundle: nil)
        self.sceneDatas = sceneDatas
        self.titleStyle = titleStyle
```

Keep the existing menu styling assignments after these stored values are set.

- [ ] **Step 3: Use style in tab titles**

Update `menuView(_:titleAt:)` to:

```swift
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return self.sceneDatas[index].type.title(style: titleStyle)
    }
```

- [ ] **Step 4: Review local diff**

Run:

```bash
git diff -- SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift
```

Expected: diff only adds title style support and keeps the default behavior as `.lettered`.

## Task 3: Enable Numbered Titles for AC/Battery Edit

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Pass numbered title style from AC/Battery Edit entry**

Update `selectScenesAction()` so the Select Scene controller creation becomes:

```swift
        let vc = SwitchSelectScenePageController(
            scenes: MeshNetworkManager.instance.scenes,
            sceneDatas: viewModel.sceneDatas,
            titleStyle: .numbered
        )
```

Keep the callback body unchanged:

```swift
        vc.scenesSelectCallback = { [weak self] sceneDatas in
            guard let self else { return }
            self.viewModel.sceneDatas = sceneDatas
            self.editorView.sceneRowView.setValue(self.viewModel.sceneTitle)
            self.updateSaveBarButtonState()
        }
```

- [ ] **Step 2: Review entry diff**

Run:

```bash
git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: only the `SwitchSelectScenePageController` initializer call gains `titleStyle: .numbered`.

## Task 4: Static Verification

**Files:**
- Verify: `SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Verify: `SunSmart/en.lproj/Localizable.strings`
- Verify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Confirm numbered style is scoped to AC/Battery Edit**

Run:

```bash
rg -n "titleStyle: \\.numbered|TitleStyle|neightkeyswitches_scene_[1-4]|switch_key_scene[A-D]" SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift SunSmart/Main/Device/Switches/Controller/DeviceSwitchViewController.swift
```

Expected: `.numbered` appears only in `PJPreAddEightKeySwitchesVC.swift`; other `SwitchSelectScenePageController` callers do not pass numbered.

- [ ] **Step 2: Confirm localization files were not modified**

Run:

```bash
git diff -- SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: empty output.

- [ ] **Step 3: Confirm old keys were not changed**

Run:

```bash
rg -n '"switch_key_sceneA"|"switch_key_sceneB"|"switch_key_sceneC"|"switch_key_sceneD"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: English still maps to `Scene A/B/C/D`, and zh-Hans still maps to the existing lettered scene labels.

- [ ] **Step 4: Check whitespace**

Run:

```bash
git diff --check
```

Expected: empty output.

## Task 5: iPhoneOS Build Verification

**Files:**
- Build: `SunSmart.xcworkspace`

- [ ] **Step 1: Run project-preferred iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build completes with `** BUILD SUCCEEDED **`.

- [ ] **Step 2: If build fails, inspect only relevant compile errors**

Read the direct `xcodebuild` output. Only change source if the failure points to `SwitchSelectScenePageController.swift` or `PJPreAddEightKeySwitchesVC.swift`.

Expected: unrelated existing failures are reported separately and not fixed in this task.

## Task 6: Commit Source Fix

**Files:**
- Commit: `SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift`
- Commit: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Review final diff**

Run:

```bash
git diff --stat
git diff -- SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: only the title style support and AC/Battery Edit numbered call are changed.

- [ ] **Step 2: Commit**

Run:

```bash
git add SunSmart/Main/Group/Switch/Controller/SwitchSelectScenePageController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "fix: show numbered switch scene tabs"
```

Expected: commit succeeds with only the source fix.

## Self-Review

- Spec coverage: Task 2 adds default lettered and explicit numbered styles. Task 3 applies numbered only to AC/Battery Edit. Task 4 checks old keys and other callers remain unchanged. Task 5 covers required iPhoneOS build verification.
- Placeholder scan: no unresolved placeholder instructions remain.
- Type consistency: `SwitchSelectScenePageController.TitleStyle`, `titleStyle`, and `title(style:)` are defined before use.
- Scope check: no localization files, resources, target settings, dependencies, data storage fields, callbacks, or sync flows are changed.
