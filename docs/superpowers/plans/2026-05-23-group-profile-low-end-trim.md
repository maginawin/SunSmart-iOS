# Group Profile Low-End Trim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将未来新建 group profile 模板的默认 low-end trim 改为 1%，同时不改动任何已保存 group profile、导入 fallback 或数据库数据。

**Architecture:** 在 `Profile` 模型层新增一个仅用于 group 默认模板的创建入口，避免修改 `LightControlData` 的全局默认值。`GroupAddViewController` 与 `ProfileSettingsViewController` 的 profile 类型选择列表统一使用该入口，已有 group 仍通过传入 profile 替换同类型模板，保证当前保存值不被覆盖。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Xcode workspace、现有 SQLite 持久化层。

---

## 文件结构

- Modify: `SunSmart/Main/Profile/Model/Profile.swift`
  - 负责新增 group 默认 profile 模板入口。
  - 保留 `LightControlData` 通用默认 `lowEndTrim = 0`。
  - 确保 `proximityLightingWithPhotocell` 的 general、night、day 默认 scene low-end trim 都是 1。
- Modify: `SunSmart/Main/Group/Controller/GroupAddViewController.swift`
  - 新建 group 的 profile 列表改为使用模型层模板入口。
  - 编辑已有 group 时继续使用 `group.info.profile`，不覆盖当前值。
- Modify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
  - Profile 设置页的类型切换列表改为使用模型层模板入口。
  - 初始化时继续用传入 profile 替换同类型模板，保护当前 group profile。
- No change: `SunSmart/Common/Data/Database.swift`
  - 不迁移、不改读取、不改保存。
- No change: `SunSmart/Common/Data/ImportData.swift`
  - 导入缺少 `lowEndTrim` 时仍 fallback 到 0。

## 约束

- 不新增 Auth 信息。
- 不格式化无关文件。
- 不处理 `user-temp/`。
- 不修改 `AGENTS.md` 当前未提交改动。
- 构建验证优先直接运行 `xcodebuild`，不使用 shell 包装或重定向日志。

### Task 1: 新增 group 默认 profile 模板入口

**Files:**
- Modify: `SunSmart/Main/Profile/Model/Profile.swift`

- [ ] **Step 1: 确认当前默认值仍是 0**

Run:

```bash
rg -n "lowEndTrim = 0|lowEndTrim: Int = 0|let lowEndTrim = 0|generalScene\\(profileType" SunSmart/Main/Profile/Model/Profile.swift
```

Expected: 能看到 `LightData`、`LightControlData` 和 `generalScene(profileType:)` 仍以 0 为通用默认值。

- [ ] **Step 2: 添加只服务 group 默认模板的常量和工厂方法**

在 `Profile` class 内、`LightControlScene` 定义之前，添加：

```swift
static let defaultGroupProfileLowEndTrim = 1

static func defaultGroupProfiles() -> [Profile] {
    return ProfileType.defaultGroupProfileTypes.map { Profile.defaultGroupProfile(type: $0) }
}

static func defaultGroupProfile(type: ProfileType) -> Profile {
    let profile = Profile(type: type)
    profile.applyDefaultGroupProfileLowEndTrim()
    return profile
}

private func applyDefaultGroupProfileLowEndTrim() {
    scenes.forEach { scene in
        scene.lightControlData.lowEndTrim = Profile.defaultGroupProfileLowEndTrim
    }
}
```

在 `ProfileType` enum 内添加：

```swift
static let defaultGroupProfileTypes: [ProfileType] = [
    .occupancy_daylight,
    .vacancy_daylight,
    .occupancy,
    .vacancy,
    .daylight,
    .manualControl,
    .proximityLighting,
    .proximityLightingWithPhotocell
]
```

放置建议：

- `defaultGroupProfileLowEndTrim` 和相关方法放在 `Profile` 的属性/嵌套类型区域，靠近 `LightControlScene` 或 `ProfileType` 之前均可。
- `defaultGroupProfileTypes` 放在 `ProfileType` enum 的 `rawValue` 之前，保持类型自己的默认顺序由 enum 管理。

- [ ] **Step 3: 做源码级检查**

Run:

```bash
rg -n "defaultGroupProfileLowEndTrim|defaultGroupProfiles|defaultGroupProfile\\(|defaultGroupProfileTypes|applyDefaultGroupProfileLowEndTrim" SunSmart/Main/Profile/Model/Profile.swift
```

Expected: 能看到 5 个新增符号；没有改动 `LightControlData.init` 的默认参数。

- [ ] **Step 4: Commit**

Run:

```bash
git add SunSmart/Main/Profile/Model/Profile.swift
git commit -m "feat: add default group profile factory"
```

### Task 2: 新建 group 使用默认模板入口

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupAddViewController.swift`

- [ ] **Step 1: 替换内联 profile 列表**

将：

```swift
private var profiles: [Profile] = [
    .init(type: .occupancy_daylight),
    .init(type: .vacancy_daylight),
    .init(type: .occupancy),
    .init(type: .vacancy),
    .init(type: .daylight),
    .init(type: .manualControl),
    .init(type: .proximityLighting),
    .init(type: .proximityLightingWithPhotocell)
]
```

替换为：

```swift
private var profiles: [Profile] = Profile.defaultGroupProfiles()
```

- [ ] **Step 2: 确认编辑已有 group 路径仍使用已保存 profile**

检查 `viewDidLoad()` 中已有逻辑保持不变：

```swift
if let group = self.group {
    name = group.name
    title = "edit_group".localizedString
    selectProfile = group.info.profile
    doneBtn.setTitle("done".localizedString, for: .normal)
    selectImageIndex = max(0, group.info.imageId - 1)
}else {
    name = MeshNetworkManager.instance.getNextGroupName()
    title = "create_group".localizedString
    selectProfile = profiles.first!
}
```

Expected: `group != nil` 时没有把 `selectProfile` 改成 `Profile.defaultGroupProfile(...)`。

- [ ] **Step 3: 做源码级检查**

Run:

```bash
rg -n "private var profiles|Profile.defaultGroupProfiles|selectProfile = group.info.profile|selectProfile = profiles.first" SunSmart/Main/Group/Controller/GroupAddViewController.swift
```

Expected: `profiles` 使用 `Profile.defaultGroupProfiles()`；已有 group 仍 `selectProfile = group.info.profile`。

- [ ] **Step 4: Commit**

Run:

```bash
git add SunSmart/Main/Group/Controller/GroupAddViewController.swift
git commit -m "feat: use group profile defaults for group creation"
```

### Task 3: Profile 设置页类型切换使用默认模板入口

**Files:**
- Modify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`

- [ ] **Step 1: 替换内联 profile 列表**

将：

```swift
private var profiles: [Profile] = [
    .init(type: .occupancy_daylight),
    .init(type: .vacancy_daylight),
    .init(type: .occupancy),
    .init(type: .vacancy),
    .init(type: .daylight),
    .init(type: .manualControl),
    .init(type: .proximityLighting),
    .init(type: .proximityLightingWithPhotocell)
]
```

替换为：

```swift
private var profiles: [Profile] = Profile.defaultGroupProfiles()
```

- [ ] **Step 2: 确认传入 profile 会替换同类型模板**

检查 `init(group:profile:)` 中已有逻辑保持不变：

```swift
self.selectProfile = profile.copy()
self.initProfile = profile
if let index = profiles.firstIndex(where: { $0.type == selectProfile.type }) {
    self.profiles.replaceSubrange(index...index, with: [selectProfile])
}
```

Expected: 打开已有 group 的 Profile 设置页时，同类型模板会被当前保存 profile 替换，当前值不会被 1% 默认值覆盖。

- [ ] **Step 3: 做源码级检查**

Run:

```bash
rg -n "private var profiles|Profile.defaultGroupProfiles|replaceSubrange\\(index\\.\\.\\.index, with: \\[selectProfile\\]\\)|self.selectProfile = profile.copy" SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift
```

Expected: `profiles` 使用 `Profile.defaultGroupProfiles()`；初始化仍用传入 profile 替换模板。

- [ ] **Step 4: Commit**

Run:

```bash
git add SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift
git commit -m "feat: use group profile defaults in profile settings"
```

### Task 4: 兼容性与构建验证

**Files:**
- Verify: `SunSmart/Main/Profile/Model/Profile.swift`
- Verify: `SunSmart/Main/Group/Controller/GroupAddViewController.swift`
- Verify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
- Verify unchanged: `SunSmart/Common/Data/Database.swift`
- Verify unchanged: `SunSmart/Common/Data/ImportData.swift`

- [ ] **Step 1: 确认未修改数据库和导入 fallback**

Run:

```bash
git diff -- SunSmart/Common/Data/Database.swift SunSmart/Common/Data/ImportData.swift
```

Expected: 无输出。

- [ ] **Step 2: 确认通用默认值仍保留 0**

Run:

```bash
rg -n "var lowEndTrim: Int = 0|init\\(highEndTrim: Int = 100, lowEndTrim: Int = 0|let lowEndTrim = 0|profileJson\\[\"lowEndTrim\"\\]\\.int \\?\\? 0" SunSmart/Main/Profile/Model/Profile.swift SunSmart/Common/Data/ImportData.swift
```

Expected: 仍能看到通用默认值和导入 fallback 为 0。

- [ ] **Step 3: 确认 group 默认模板入口被两个 UI 流程使用**

Run:

```bash
rg -n "Profile.defaultGroupProfiles\\(\\)" SunSmart/Main/Group/Controller/GroupAddViewController.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift
```

Expected: 两个文件各出现 1 次。

- [ ] **Step 4: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 查看最终改动范围**

Run:

```bash
git status --short
git diff --stat HEAD~3..HEAD
```

Expected:

- 除用户已有的 `AGENTS.md` 未提交改动外，工作区干净。
- 最近 3 个实现提交只涉及 `Profile.swift`、`GroupAddViewController.swift`、`ProfileSettingsViewController.swift`。

## 自审结果

- Spec coverage: 新建 group 默认 1%、切换 profile 类型默认 1%、已有 group 不被覆盖、不迁移数据库、不改导入 fallback、`proximityLightingWithPhotocell` 多 scene 一致性均有对应任务。
- Placeholder scan: 无 `TBD`、`TODO`、`implement later` 或未定义步骤。
- Type consistency: 计划中使用的 `Profile.defaultGroupProfiles()`、`Profile.defaultGroupProfile(type:)`、`Profile.defaultGroupProfileLowEndTrim`、`ProfileType.defaultGroupProfileTypes` 命名一致。
