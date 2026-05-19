# PJEightKeySwitchMonitorVC Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 8 键开关详情页进入 Edit 的导航方式、未保存退出提示，以及保存名称后详情标题不刷新的问题。

**Architecture:** 保持 `PJEightKeySwitchMonitorVC` 作为详情页，`PJPreAddEightKeySwitchesVC` 继续作为编辑页。Edit 从详情页通过同一个导航栈 push 进入，保存成功后通过回调把最新 `PJEightKeySwitchData` 回传给详情页并 pop 返回。

**Tech Stack:** UIKit, Swift, SQLite.swift, 现有 `MeshNetworkManager` 与 `PJEightKeySwitchRepository`。

---

### Task 1: Edit 导航改为 Push

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [x] **Step 1: 写失败检查**

Run: `rg -n 'present\\(NavigationViewController\\(rootViewController: vc\\), animated: true\\)' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

Expected before fix: 命中 `pushEditor()` 中的 present。

- [x] **Step 2: 实现最小修复**

将 `pushEditor()` 中的 present 改成 `navigationController?.pushViewController(vc, animated: true)`。

- [x] **Step 3: 验证检查通过**

Run: `rg -n 'present\\(NavigationViewController\\(rootViewController: vc\\), animated: true\\)' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

Expected after fix: 无命中。

### Task 2: 保存后刷新 Monitor 标题和 UI

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [x] **Step 1: 写失败检查**

Run: `rg -n 'switchSavedAction|updateSwitchData' SunSmart/Main/Device/Device1.5/NEightKeySwitches`

Expected before fix: 无命中。

- [x] **Step 2: 实现最小修复**

给 `PJPreAddEightKeySwitchesVC` 增加保存成功回调；给 Monitor view model 增加更新数据方法；Monitor push Edit 时设置回调，收到新数据后更新标题和 UI。

- [x] **Step 3: 验证检查通过**

Run: `rg -n 'switchSavedAction|updateSwitchData' SunSmart/Main/Device/Device1.5/NEightKeySwitches`

Expected after fix: 命中编辑页回调、Monitor 回调和 view model 更新方法。

### Task 3: 未保存内容侧滑退出提示

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [x] **Step 1: 写失败检查**

Run: `rg -n 'interactivePopGestureRecognizer|UIGestureRecognizerDelegate|popViewController\\(animated: true\\)' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

Expected before fix: 没有完整的侧滑返回拦截实现。

- [x] **Step 2: 实现最小修复**

编辑模式下接管 `interactivePopGestureRecognizer`，在手势开始时如果有未保存内容则展示确认弹窗并返回 `false`；用户确认后执行 `navigationController?.popViewController(animated: true)`。

- [x] **Step 3: 验证检查通过**

Run: `rg -n 'interactivePopGestureRecognizer|UIGestureRecognizerDelegate|popViewController\\(animated: true\\)' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

Expected after fix: 命中侧滑拦截和确认后 pop。

### Task 4: 构建验证

**Files:**
- No code changes.

- [x] **Step 1: 检查 diff**

Run: `git diff --check`

Expected: 无输出且 exit 0。

- [x] **Step 2: 编译 SunSmart**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `** BUILD SUCCEEDED **`。
