# Content Display 有效编辑权限展示设计

## 背景

`Site - Space - More` 中当前存在 `Content Display` 功能入口。需求更新为：

- 当前有 Edit 权限的用户展示 `Content Display`。
- Owner 和 Editor 只有在没有降级到 Visitor 时才展示 `Content Display`。
- Visitor，或者因 Space 被其他 Owner/Editor 占用而降级为 Visitor 的 Owner/Editor，不展示 `Content Display`。

本次只调整 `Content Display` 功能入口和页面内权限判断，不修改 Content Display 数据字段、云同步合同、国际化文案、资源、target 配置或其他 More 功能。

## 当前问题

代码中问题真实存在：

- `SpaceMoreViewController` 的 `options` 当前固定包含 `.contentDisplay`，因此 Visitor 也会看到 `Content Display` 功能选项。
- `.contentDisplay` 点击分支没有权限 guard，会直接进入 `ContentDisplayViewController`。
- `ContentDisplayViewController.isEditable` 当前只判断 `space.permission == .owner || space.permission == .editor`，没有覆盖当前会话被降级的情况。

项目已有更接近真实权限的 capability 层：

- `SpaceData.deviceOperates` 在 `permission == .visitor`、`disableEditorPermission == true` 或 `meshOTADistribution == true` 时不包含 `.edit`。
- `SpaceViewController` 在发现已有其他 Owner/Editor 占用 Space 后，会把当前会话 `space.disableEditorPermission` 置为 `true`，并发送 `spacePermissionChangedNotificaitonName`。

因此本次展示条件应统一使用当前有效编辑能力，而不是只看字面角色。

## 方案对比

### 方案 A：使用当前有效编辑能力

以 `space.deviceOperates.contains(.edit)` 作为 `Content Display` 入口展示和页面可编辑性的统一判断。

优点：

- 覆盖 Visitor。
- 覆盖 Owner/Editor 被占用后降级为 Visitor 的当前会话。
- 复用项目已有 capability 真值层，和设备、组、场景等页面更一致。
- 自动覆盖 Mesh OTA 分发期间临时禁编辑的现有语义。

缺点：

- 展示条件比文字需求稍宽，包含 Mesh OTA 分发期间隐藏入口；但这和现有 `deviceOperates` 语义一致。

### 方案 B：只判断角色和降级标记

以 `permission == .owner || permission == .editor` 且 `!disableEditorPermission` 作为判断。

优点：

- 精确贴合本次文字描述。

缺点：

- 绕开 `SpaceData.deviceOperates`，容易和其他页面的权限真值层分叉。
- 不能覆盖已有的其他临时禁编辑状态。

### 方案 C：入口仍展示，点击后提示无权限

保留入口，点击时提示 `no_permission`，页面只读。

优点：

- 改动最少。

缺点：

- 不符合“不要展示 Content Display 功能选项”的需求。

## 推荐方案

采用方案 A：把 `Content Display` 的入口展示条件和页面可编辑条件统一定义为当前有效编辑能力：

`space.deviceOperates.contains(.edit)`

这能同时覆盖字面 Visitor 和当前会话降级 Visitor，且复用已有权限模型。

## 设计

### Space More 入口

在 `SpaceMoreViewController` 中将 `options` 从固定数组改为按当前权限构建：

- 基础入口保持现状：`.ble`、`.deviceParameters`、`.energyData`。
- 仅当 `space.deviceOperates.contains(.edit)` 为 `true` 时追加 `.contentDisplay`。
- `.mesh` 长按测试入口继续保留原有动态插入行为。

为避免权限变化后 More 页面仍显示旧状态，`SpaceMoreViewController` 需要监听 `spacePermissionChangedNotificaitonName`：

- 权限变化后重新构建 options。
- 如果 `.contentDisplay` 从可见变为不可见，从列表中移除。
- 如果 `.contentDisplay` 从不可见变为可见，重新加入列表。
- 如果 `.mesh` 已通过长按测试入口插入，刷新 options 时保留 `.mesh`。
- 刷新 collection view，避免 indexPath 和 options 状态不一致。

`.contentDisplay` 点击分支可以保留轻量 guard：

- 如果当前已无 `.edit`，提示 `no_permission` 并返回。
- 正常情况下不可见入口不会被点击；guard 作为异步权限变化后的防线。

### Content Display 页面

在 `ContentDisplayViewController` 中把 `isEditable` 改为：

`space.deviceOperates.contains(.edit)`

这会让 3 个已有设置项都沿用有效编辑能力：

- `displayDeviceNamePrefix`
- `showCCTQuickButtons`
- `controlType`

页面需要监听 `spacePermissionChangedNotificaitonName`：

- 当前会话被降级时，reload table。
- cell 的 switch 或选择卡刷新为不可编辑。
- closure 内继续保留 `guard self.isEditable else { return }`，防止权限变化后旧 cell 回调仍修改 Space。

不新增提示文案。用户已经在 Space 占用冲突处看到降级确认；本页只负责按当前权限收口展示和编辑能力。

### 数据与同步

本次不修改 Content Display 数据层和同步链路。

现有设置变更仍通过：

- `ContentDisplayViewController.notifyContentDisplayChanged()`
- `spaceDataChangedNotificaitonName`
- `SpaceChangeDataType.common`
- `SpaceViewController` 监听后更新 `lastUpdate`、保存并进入 `.slow` sync

由于无编辑能力时入口不可见，且页面内也不可编辑，不会新增无权限写入路径。

### 错误处理

- More 入口因权限变化隐藏，不额外弹窗。
- 如果权限在点击瞬间变化，点击 guard 复用 `no_permission` 提示。
- 如果用户已停留在 Content Display 页面后权限变化，页面控件刷新为不可编辑，不弹额外提示。

### 影响范围

计划修改文件：

- `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`
- `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`

不修改文件：

- `SpaceData.swift`
- `Database.swift`
- `ExportData.swift`
- `ImportData.swift`
- 本地化文件
- 图片资源
- `project.pbxproj`
- 其他 target 配置

## 验收标准

- Owner / Editor 且 `space.deviceOperates.contains(.edit)` 为 true 时，`Site - Space - More` 显示 `Content Display`。
- Visitor 不显示 `Content Display`。
- Owner / Editor 因 Space 被其他编辑用户占用并确认降级后，不显示 `Content Display`。
- Owner / Editor 已打开 More 页面后发生权限降级，More 列表刷新并移除 `Content Display`。
- 用户已打开 Content Display 页面后发生权限降级，3 个设置项变为不可编辑。
- 已降级用户不能通过旧 cell callback 修改 `displayDeviceNamePrefix`、`showCCTQuickButtons` 或 `controlType`。
- BLE、Device Parameter Settings、Energy Data、Mesh 长按测试入口行为不被改动。
- Content Display 的数据保存和 `.common` / `.slow` 同步链路保持现状。
- `SunSmart` iPhoneOS Debug 构建通过。

## 验证计划

1. 静态检查：
   - `SpaceMoreViewController` 中 `.contentDisplay` 不再无条件出现在初始 `options`。
   - `ContentDisplayViewController.isEditable` 使用 `space.deviceOperates.contains(.edit)`。
   - 两个页面都处理 `spacePermissionChangedNotificaitonName`。

2. 手工行为检查：
   - Owner / Editor 正常进入 Space，More 页面能看到 `Content Display`。
   - Visitor 进入 Space，More 页面看不到 `Content Display`。
   - Owner / Editor 被其他编辑用户占用后确认以 Visitor 进入，More 页面看不到 `Content Display`。
   - 已打开 Content Display 页面后触发降级，页面控件不可编辑。

3. 构建验证：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

