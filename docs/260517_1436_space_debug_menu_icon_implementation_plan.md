# Space Debug 菜单图标优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Site / Space 右上角菜单中 `Debug` 入口的图标从信息图标换成更符合调试含义的 `menu_profile_test` 图标。

**Architecture:** 复用现有 asset `menu_profile_test`，只替换 `SpaceViewController.moreClick()` 中 Debug 菜单项的 `UIImage(named:)` 资源名。菜单结构、权限判断、文案、本地化、点击行为和 `MenuPopView` 组件都不变。

**Tech Stack:** Swift, UIKit, Xcode asset catalog, Xcode workspace `SunSmart.xcworkspace`

---

## 文件结构

- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`
  - 替换 Debug 菜单项图标资源名。

不需要修改以下文件：

- `SunSmart/Assets.xcassets/Common/menu_profile_test.imageset/Contents.json`
- `SunSmart/Assets.xcassets/Common/menu_information.imageset/Contents.json`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart.xcodeproj/project.pbxproj`

## Task 1：替换 Debug 菜单图标

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`

- [ ] **Step 1：确认当前 Debug 菜单项位置**

Run:

```bash
rg -n "menu_information|debug\".localizedString|openSpaceDebug" SunSmart/Main/Space/Controller/SpaceViewController.swift
```

Expected:

```text
SpaceViewController.swift:<line>:            items.append(.init(icon: UIImage(named: "menu_information"), title: "debug".localizedString, tapItemBack: {[weak self] _ in
SpaceViewController.swift:<line>:                self?.openSpaceDebug()
SpaceViewController.swift:<line>:    private func openSpaceDebug() {
```

- [ ] **Step 2：确认目标资源存在**

Run:

```bash
find SunSmart/Assets.xcassets/Common/menu_profile_test.imageset -maxdepth 1 -type f
```

Expected:

```text
SunSmart/Assets.xcassets/Common/menu_profile_test.imageset/Contents.json
SunSmart/Assets.xcassets/Common/menu_profile_test.imageset/menu_profile_test@2x.png
SunSmart/Assets.xcassets/Common/menu_profile_test.imageset/menu_profile_test@3x.png
```

- [ ] **Step 3：替换 Debug 菜单项图标资源名**

在 `SpaceViewController.moreClick()` 中，将 Debug 菜单项从：

```swift
items.append(.init(icon: UIImage(named: "menu_information"), title: "debug".localizedString, tapItemBack: {[weak self] _ in
    self?.openSpaceDebug()
}))
```

改为：

```swift
items.append(.init(icon: UIImage(named: "menu_profile_test"), title: "debug".localizedString, tapItemBack: {[weak self] _ in
    self?.openSpaceDebug()
}))
```

说明：

- 只替换资源名。
- 不修改 `title`。
- 不修改 `tapItemBack`。
- 不修改 `if space.canEditing` 权限判断。

- [ ] **Step 4：静态检查改动范围**

Run:

```bash
git diff -- SunSmart/Main/Space/Controller/SpaceViewController.swift
```

Expected:

- 只看到 `menu_information` 改为 `menu_profile_test`。
- 不应出现 `openSpaceDebug()`、`space.canEditing`、菜单顺序、菜单宽度、本地化或 asset 文件改动。

- [ ] **Step 5：静态搜索确认 Debug 菜单项使用新图标**

Run:

```bash
rg -n "menu_profile_test|menu_information|debug\".localizedString|openSpaceDebug" SunSmart/Main/Space/Controller/SpaceViewController.swift
```

Expected:

- Debug 菜单项使用 `UIImage(named: "menu_profile_test")`。
- `openSpaceDebug()` 仍存在。
- `debug`.localizedString 仍存在。
- `menu_information` 不再用于 Space 页面 Debug 菜单项。

- [ ] **Step 6：构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

允许出现项目已有 warning，例如重复 Compile Sources、GeneratedAssetSymbols 资源重名、历史 deprecated API warning。不能出现本次改动导致的 Swift 编译错误。

- [ ] **Step 7：提交代码改动**

Run:

```bash
git status --short
git add SunSmart/Main/Space/Controller/SpaceViewController.swift
git commit -m "style: update space debug menu icon"
```

Expected:

```text
[www/feat/debug_260516 <hash>] style: update space debug menu icon
```

## Task 2：人工验证菜单显示

**Files:**
- Verify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`

- [ ] **Step 1：打开 Space 页面右上角菜单**

在真机或模拟器中进入：

```text
Site / Space -> 右上角更多菜单
```

Expected:

- 菜单正常弹出。
- `Debug` 菜单项仍出现在原位置。
- `Debug` 菜单项图标显示为 `</>` 样式。

- [ ] **Step 2：验证点击行为**

点击 `Debug` 菜单项。

Expected:

- 菜单关闭。
- 仍进入现有 Debug 页面。
- Debug 页面扫描、连接入口不受影响。

- [ ] **Step 3：最终状态检查**

Run:

```bash
git status --short
git log --oneline -5
```

Expected:

- 工作区干净。
- 最近提交包含 `style: update space debug menu icon`。

