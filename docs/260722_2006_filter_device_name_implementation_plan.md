# Space Main 设备名称过滤实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. 本仓库默认采用 Inline Execution；除非用户明确要求，不使用 subagents。所有步骤使用 checkbox 跟踪。

**Goal:** 在 `Site → Space → Main` 的 Lights、Switches、Sensors、Others 中实现共享的按名称过滤、Reset、selected 图片和 Figma 搜索交互，同时保持所有非 Main 列表及原有全量业务逻辑不受影响。

**Architecture:** `DevicesViewController` 持有一个页面实例级 `DeviceNameFilterSession` 并注入四个分类。各分类保留完整数据源，只向 collection view 暴露可见数据；菜单与搜索遮罩由 Main 父控制器统一呈现，Footer 默认仍不可交互。

**Tech Stack:** Swift、UIKit、SnapKit、WMPageController、NordicSigMeshSDK、Asset Catalog、`.strings`、独立 `swiftc` 聚焦测试、`xcodebuild` generic iPhoneOS。

## Global Constraints

- 仅作用于 `Site → Space → Main → Lights/Switches/Sensors/Others`。
- Group、Scene、Timed、More 及所有深层设备列表始终使用完整数据源。
- 关键词仅在键盘 `Search` 提交时更新；首尾 Trim、保留中间空格、忽略大小写、子串匹配。
- Cancel 或点击搜索遮罩只丢弃草稿，不更新已提交条件。
- 非空条件在四分类共享；任一分类 Reset 后四分类同时清空。
- Pop 回 Site 后清空；进入更深页面再返回时保留。
- Footer 数量、Lights `ALL` 控制、修复、同步和设备状态读取继续基于完整数据源。
- Lights `ALL` 参与显示过滤；可见时点击仍控制全部 Lights。
- 编辑和删除仅作用于过滤后可见设备；Select All 只选择可见真实设备。
- 不实现 Address、MAC，不扩展 Sensors 真实列表业务。
- 所有新增用户文案同步 English 与简体中文，禁止硬编码。
- 保留现有 worktree 改动；不覆盖 selected 图片，不格式化无关文件。
- 四个品牌 target 均需通过 generic iPhoneOS、关闭签名的直接 `xcodebuild`。

---

## 文件结构

### 新建

- `SunSmart/Main/Device/Filter/Model/DeviceNameFilterSession.swift`：纯过滤状态、观察与匹配规则。
- `SunSmart/Main/Device/Filter/View/DeviceNameFilterMenuView.swift`：左下角 Search/Reset 菜单。
- `SunSmart/Main/Device/Filter/View/DeviceNameFilterSearchView.swift`：Figma 搜索遮罩和草稿输入。
- `Tests/Device/DeviceNameFilterSessionTests.swift`：不依赖 UIKit/SDK 的聚焦测试。

### 修改

- `SunSmart/Main/Space/View/SpaceFunctionFooterView.swift`：可配置过滤入口与 selected 图片。
- `SunSmart/Main/Device/Controller/DevicesViewController.swift`：持有共享会话、注入子页面、统一展示菜单/搜索框。
- `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`：完整/可见 Lights 分离及编辑映射。
- `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`：完整/可见 Switches 分离。
- `SunSmart/Main/Device/Sensors/Controller/DeviceSensorsViewController.swift`：共享状态、按钮和过滤空状态。
- `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`：完整/可见 Others 分离。
- `SunSmart/en.lproj/Localizable.strings`：英文文案。
- `SunSmart/zh-Hans.lproj/Localizable.strings`：简体中文文案。
- `SunSmart.xcodeproj/project.pbxproj`：三个新业务源文件加入四个 app target；测试文件不加入 app target。

### 使用但不改写内容

- `SunSmart/Assets.xcassets/Space/space_device_count_selected.imageset/*`
- `SunSmart/Assets.xcassets/Common/search_icon.imageset/*`
- `SunSmart/Assets.xcassets/Common/menu_bubble.imageset/*`（仅作为当前菜单风格参考）。

---

### Task 1: 过滤会话与纯逻辑测试

**Files:**
- Create: `SunSmart/Main/Device/Filter/Model/DeviceNameFilterSession.swift`
- Create: `Tests/Device/DeviceNameFilterSessionTests.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `DeviceNameFilterSession.query: String`
- Produces: `DeviceNameFilterSession.isActive: Bool`
- Produces: `submit(_:)`, `reset()`, `matches(_:)`, `matches(anyOf:)`, `filtered(_:names:)`
- Produces: `observe(_:) -> UUID` 与 `removeObserver(_:)`

- [ ] **Step 1: 先编写会失败的聚焦测试**

创建完整测试入口：

```swift
import Foundation

@main
struct DeviceNameFilterSessionTests {
    struct Item: Equatable {
        let id: Int
        let names: [String]
    }

    static func main() {
        testTrimAndEmptyReset()
        testCaseInsensitiveSubstring()
        testMiddleSpacesArePreserved()
        testAnyCandidateMatches()
        testAllUsesDisplayedName()
        testCompleteAndVisibleCollectionsStaySeparate()
        testObserversReceiveCommittedChangesOnly()
        testDraftDoesNotMutateCommittedQuery()
        print("DeviceNameFilterSessionTests passed")
    }

    static func testTrimAndEmptyReset() {
        let session = DeviceNameFilterSession()
        session.submit("  Room  ")
        precondition(session.query == "Room")
        precondition(session.isActive)
        session.submit("   \n  ")
        precondition(session.query.isEmpty)
        precondition(!session.isActive)
    }

    static func testCaseInsensitiveSubstring() {
        let session = DeviceNameFilterSession()
        session.submit("LIGHT")
        precondition(session.matches("Meeting Light 01"))
        precondition(!session.matches("Switch 01"))
    }

    static func testMiddleSpacesArePreserved() {
        let session = DeviceNameFilterSession()
        session.submit("room  light")
        precondition(session.matches("Room  Light 01"))
        precondition(!session.matches("Room Light 01"))
    }

    static func testAnyCandidateMatches() {
        let session = DeviceNameFilterSession()
        session.submit("floor")
        precondition(session.matches(anyOf: ["Light 01", "First Floor"]))
        precondition(!session.matches(anyOf: ["Light 01", "Meeting Room"]))
    }

    static func testAllUsesDisplayedName() {
        let session = DeviceNameFilterSession()
        session.submit("all")
        precondition(session.matches("ALL"))
        session.submit("全部")
        precondition(session.matches("全部"))
    }

    static func testCompleteAndVisibleCollectionsStaySeparate() {
        let all = [
            Item(id: 1, names: ["Light 01", "First Floor"]),
            Item(id: 2, names: ["Light 02", "Second Floor"]),
            Item(id: 3, names: ["Switch 01"])
        ]
        let session = DeviceNameFilterSession()
        session.submit("first")
        let visible = session.filtered(all, names: { $0.names })
        precondition(all.map(\.id) == [1, 2, 3])
        precondition(visible.map(\.id) == [1])
    }

    static func testObserversReceiveCommittedChangesOnly() {
        let session = DeviceNameFilterSession()
        var received: [String] = []
        let id = session.observe { received.append($0) }
        session.submit(" room ")
        session.submit("room")
        session.reset()
        session.removeObserver(id)
        session.submit("ignored")
        precondition(received == ["", "room", ""])
    }

    static func testDraftDoesNotMutateCommittedQuery() {
        let session = DeviceNameFilterSession()
        session.submit("old")
        var draft = session.query
        draft = "new"
        precondition(draft == "new")
        precondition(session.query == "old")
    }
}
```

- [ ] **Step 2: 编译测试并确认失败**

Run:

```bash
swiftc -parse-as-library Tests/Device/DeviceNameFilterSessionTests.swift -o /tmp/DeviceNameFilterSessionTests
```

Expected: FAIL，错误包含 `cannot find 'DeviceNameFilterSession' in scope`。

- [ ] **Step 3: 实现最小过滤会话**

创建完整实现：

```swift
import Foundation

final class DeviceNameFilterSession {
    typealias Observer = (String) -> Void

    private var observers: [UUID: Observer] = [:]
    private(set) var query: String = ""

    var isActive: Bool {
        !query.isEmpty
    }

    @discardableResult
    func observe(_ observer: @escaping Observer) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(query)
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    func submit(_ rawQuery: String) {
        let normalized = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != query else { return }
        query = normalized
        observers.values.forEach { $0(query) }
    }

    func reset() {
        submit("")
    }

    func matches(_ candidate: String) -> Bool {
        !isActive || candidate.localizedCaseInsensitiveContains(query)
    }

    func matches(anyOf candidates: [String]) -> Bool {
        !isActive || candidates.contains(where: matches(_:))
    }

    func filtered<Value>(_ values: [Value], names: (Value) -> [String]) -> [Value] {
        guard isActive else { return values }
        return values.filter { matches(anyOf: names($0)) }
    }
}
```

- [ ] **Step 4: 编译并运行聚焦测试**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Filter/Model/DeviceNameFilterSession.swift Tests/Device/DeviceNameFilterSessionTests.swift -o /tmp/DeviceNameFilterSessionTests
```

Run:

```bash
/tmp/DeviceNameFilterSessionTests
```

Expected: 输出 `DeviceNameFilterSessionTests passed`。

- [ ] **Step 5: 将模型文件加入四个 target**

在 `project.pbxproj` 的 Device 分组下新增 Filter/Model 文件引用，并分别加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 Sources。验证每个 target 恰好有一条 build file 引用，测试文件不加入任何 app target。

Run:

```bash
rg -n "DeviceNameFilterSession.swift in Sources" SunSmart.xcodeproj/project.pbxproj
```

Expected: 4 条 Sources 引用。

- [ ] **Step 6: 提交 Task 1**

```bash
git add SunSmart/Main/Device/Filter/Model/DeviceNameFilterSession.swift Tests/Device/DeviceNameFilterSessionTests.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add device name filter session" -- SunSmart/Main/Device/Filter/Model/DeviceNameFilterSession.swift Tests/Device/DeviceNameFilterSessionTests.swift SunSmart.xcodeproj/project.pbxproj
```

---

### Task 2: Footer 入口、过滤菜单与搜索遮罩

**Files:**
- Create: `SunSmart/Main/Device/Filter/View/DeviceNameFilterMenuView.swift`
- Create: `SunSmart/Main/Device/Filter/View/DeviceNameFilterSearchView.swift`
- Modify: `SunSmart/Main/Space/View/SpaceFunctionFooterView.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Use: `SunSmart/Assets.xcassets/Space/space_device_count_selected.imageset/*`

**Interfaces:**
- Produces: `SpaceFunctionFooterViewDelegate.functionDidClickDeviceFilter(view:)`
- Produces: `SpaceFunctionFooterView.deviceNameFilterEnabled: Bool`
- Produces: `SpaceFunctionFooterView.deviceNameFilterActive: Bool`
- Produces: `DeviceNameFilterMenuView.show(from:onSearch:onReset:)`
- Produces: `DeviceNameFilterSearchView.show(initialText:onSubmit:)`

- [ ] **Step 1: 为 Footer 增加默认关闭的过滤能力**

在协议及默认实现中加入：

```swift
func functionDidClickDeviceFilter(view: SpaceFunctionFooterView)

func functionDidClickDeviceFilter(view: SpaceFunctionFooterView) {}
```

在 Footer 中加入并绑定 count button：

```swift
var deviceNameFilterEnabled: Bool = false {
    didSet {
        countBtn.isUserInteractionEnabled = deviceNameFilterEnabled
        countBtn.accessibilityTraits = deviceNameFilterEnabled ? .button : .staticText
    }
}

var deviceNameFilterActive: Bool = false {
    didSet {
        let imageName = deviceNameFilterActive
            ? "space_device_count_selected"
            : "space_device_count"
        countBtn.setImage(UIImage(named: imageName), for: .normal)
    }
}

@objc private func countBtnClick() {
    guard deviceNameFilterEnabled else { return }
    delegate?.functionDidClickDeviceFilter(view: self)
}
```

`setupUI()` 创建 `countBtn` 后添加 target，默认保持不可点击，并将 accessibility label 设置为本地化后的 Search by Name。

- [ ] **Step 2: 实现左下角专用菜单**

`DeviceNameFilterMenuView` 使用 window 级透明 `UIControl` 作为外部点击区域，内容 View 采用以下固定规则：

```swift
final class DeviceNameFilterMenuView: UIControl {
    static func show(
        from sourceView: UIView,
        onSearch: @escaping () -> Void,
        onReset: @escaping () -> Void
    )

    private static let menuWidth = SCRXFrom(200)
    private static let rowHeight = SCRYFrom(44)
    private static let dividerAreaHeight = SCRYFrom(16)
}
```

实现细节必须全部满足：

- 背景 `RGB(74, 74, 74, 0.95)`、圆角 `SCRYFrom(10)`。
- 阴影颜色黑色、opacity `0.15`、radius `20`、offset `(0, -4)`。
- 两个 UIButton 分别使用 `device_filter_search_by_name` 与现有 `reset` 本地化。
- 每行高 44，左内边距 16，字体 14 regular，白色。
- 两行之间放置高 16 的 divider area；中间线为白色 20% alpha、高 `1 / UIScreen.main.scale`。
- 将 source button 的 bounds 转换到 key window；菜单左边限制在 safe area 左侧 16，底部位于按钮上方 8，且不得超出 window 右边 16。
- 点击 Search/Reset 时先移除菜单，再执行对应 closure。
- 点击内容外部仅移除菜单，不执行 closure。
- `show` 前移除 window 中已有的 `DeviceNameFilterMenuView`，防止叠加。

- [ ] **Step 3: 实现 Figma 搜索遮罩**

类接口：

```swift
final class DeviceNameFilterSearchView: UIControl, UITextFieldDelegate {
    static func show(initialText: String, onSubmit: @escaping (String) -> Void)
}
```

实现细节必须全部满足：

- 覆盖 key window；背景为黑色 20% alpha。
- 顶部 card 左右边距手机 26、iPad 最大宽度 520，顶部为 safe area 加 96，高 66，白色，圆角 14，阴影沿用 Figma。
- card 内搜索框左右 16、高 40；边框使用 `RGB(193, 207, 226)`、1pt、圆角 5。
- 搜索框左侧使用现有 `search_icon`，尺寸 20；placeholder 为 `device_filter_search_by_name`。
- `UITextField.clearButtonMode = .whileEditing`，不自绘 clear glyph。
- `returnKeyType = .search`，`autocorrectionType = .no`。
- Cancel 使用现有 `Cancel` 本地化，颜色 `Bar_Color`，位于搜索框右侧内容区。
- 初始文字使用已提交 query；show 后在下一主队列周期 `becomeFirstResponder()`。
- `textFieldShouldReturn` 读取原始文本，关闭键盘和遮罩，然后调用 `onSubmit`；Trim 由 session 统一完成。
- Cancel 和背景 touchUpInside 仅关闭，不调用 `onSubmit`。
- card 吞掉触摸，避免点击输入框或 Cancel 时触发背景关闭。
- `show` 前移除已有搜索 View 和设备过滤菜单，避免 window 残留遮罩。

- [ ] **Step 4: 将两个 View 文件加入四个 target**

在 `project.pbxproj` 的 Device/Filter/View 分组加入两个文件，并加入四个 app target 的 Sources。

Run:

```bash
rg -n "DeviceNameFilter(Menu|Search)View.swift in Sources" SunSmart.xcodeproj/project.pbxproj
```

Expected: 每个文件 4 条 Sources 引用，共 8 条。

- [ ] **Step 5: 检查资源和 Footer 默认隔离**

Run:

```bash
plutil -lint SunSmart/Assets.xcassets/Space/space_device_count_selected.imageset/Contents.json
```

Expected: `OK`。检查 Group、Scene、Timed、More 等现有 Footer 调用方未设置 `deviceNameFilterEnabled`，因此 count button 仍不可点击。

- [ ] **Step 6: 提交 Task 2**

```bash
git add SunSmart/Main/Device/Filter/View/DeviceNameFilterMenuView.swift SunSmart/Main/Device/Filter/View/DeviceNameFilterSearchView.swift SunSmart/Main/Space/View/SpaceFunctionFooterView.swift SunSmart/Assets.xcassets/Space/space_device_count_selected.imageset SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add device filter menu" -- SunSmart/Main/Device/Filter/View/DeviceNameFilterMenuView.swift SunSmart/Main/Device/Filter/View/DeviceNameFilterSearchView.swift SunSmart/Main/Space/View/SpaceFunctionFooterView.swift SunSmart/Assets.xcassets/Space/space_device_count_selected.imageset SunSmart.xcodeproj/project.pbxproj
```

---

### Task 3: Main 父控制器共享会话与本地化

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Produces: `DevicesViewController.deviceNameFilterSession`
- Produces: `DevicesViewController.showDeviceNameFilterMenu(from:)`
- Consumes: Task 1 session、Task 2 menu/search View。

- [ ] **Step 1: 新增本地化 Key**

English：

```text
"device_filter_search_by_name" = "Search by Name";
"device_filter_no_matching_devices" = "No matching devices";
```

简体中文：

```text
"device_filter_search_by_name" = "按名称搜索";
"device_filter_no_matching_devices" = "没有匹配的设备";
```

Reset 继续复用现有 `reset`，Cancel 继续复用现有 `Cancel`，ALL 继续复用现有 `ALL`。

- [ ] **Step 2: 在 Main 父控制器持有会话并统一呈现 UI**

加入：

```swift
let deviceNameFilterSession = DeviceNameFilterSession()

func showDeviceNameFilterMenu(from sourceView: UIView) {
    DeviceNameFilterMenuView.show(
        from: sourceView,
        onSearch: { [weak self] in
            guard let self else { return }
            DeviceNameFilterSearchView.show(
                initialText: self.deviceNameFilterSession.query,
                onSubmit: { [weak self] text in
                    self?.deviceNameFilterSession.submit(text)
                }
            )
        },
        onReset: { [weak self] in
            self?.deviceNameFilterSession.reset()
        }
    )
}
```

不把 session 放入 `SpaceData`、通知中心、单例或静态属性。

- [ ] **Step 3: 将同一 session 注入四个 Main 分类**

修改 `pageController(_:viewControllerAt:)`：

```swift
case 0:
    return DeviceLightsViewController(
        site: site,
        space: space,
        deviceNameFilterSession: deviceNameFilterSession
    )
case 1:
    return DeviceSwitchesViewController(
        space: space,
        deviceNameFilterSession: deviceNameFilterSession
    )
case 2:
    return DeviceSensorsViewController(
        space: space,
        deviceNameFilterSession: deviceNameFilterSession
    )
case 3:
    return DeviceOthersViewController(
        space: space,
        deviceNameFilterSession: deviceNameFilterSession
    )
```

- [ ] **Step 4: 运行本地化重复 Key 与格式检查**

Run:

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
```

Run:

```bash
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 两条命令均为 `OK`，新增 Key 各出现一次。

- [ ] **Step 5: 提交 Task 3**

```bash
git add SunSmart/Main/Device/Controller/DevicesViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: coordinate main device filter" -- SunSmart/Main/Device/Controller/DevicesViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

---

### Task 4: Lights 完整数据与可见数据分离

**Files:**
- Modify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`

**Interfaces:**
- Consumes: `DeviceNameFilterSession`
- Produces internally: `visibleDevices: [Node]`、`showsAllControl: Bool`、`device(at:)`

- [ ] **Step 1: 注入会话并建立观察**

新增属性：

```swift
private let deviceNameFilterSession: DeviceNameFilterSession
private var deviceNameFilterObservation: UUID?
private var visibleDevices: [Node] = []
private var showsAllControl = false
```

扩展初始化器接收 session；`viewDidLoad` 观察 query，closure 使用 `[weak self]` 调用 `applyDeviceNameFilter()`。`deinit` 移除 observation。

- [ ] **Step 2: 保留 `devices` 为完整集合并派生可见集合**

`loadDevices()` 继续把全部 light nodes 写入 `devices`，随后调用：

```swift
private func applyDeviceNameFilter() {
    visibleDevices = deviceNameFilterSession.filtered(devices) { [space] node in
        var names = [node.name ?? ""]
        if space.displayDeviceNamePrefix, let group = node.group {
            names.append(group.name)
        }
        return names
    }
    showsAllControl = !devices.isEmpty
        && deviceNameFilterSession.matches("ALL".localizedString)
    let visibleAddresses = Set(visibleDevices.map(\.primaryUnicastAddress))
    selectedAddresss.removeAll { !visibleAddresses.contains($0) }
    footerView?.deviceNameFilterActive = deviceNameFilterSession.isActive
    updateDevicesEmptyUI()
    collectionView?.reloadData()
    if isEdit { updateEditUI() }
}
```

过滤不得覆盖 `devices`；排序完成后对排序后的 `devices` 再调用该方法。

- [ ] **Step 3: 将 collection 索引统一映射到 visibleDevices**

新增唯一索引入口：

```swift
private func device(at indexPath: IndexPath) -> Node? {
    let deviceIndex = indexPath.item - (showsAllControl ? 1 : 0)
    guard visibleDevices.indices.contains(deviceIndex) else { return nil }
    return visibleDevices[deviceIndex]
}
```

修改以下路径全部使用 `visibleDevices`/`device(at:)`：

- `numberOfItemsInSection` 返回 `visibleDevices.count + (showsAllControl ? 1 : 0)`。
- `cellForItemAt` 仅在 `showsAllControl && indexPath.item == 0` 时创建 ALL cell。
- `didSelectItemAt`、长按、单项编辑回调。
- `reloadCollectionItem(node:)` 计算 visible index 后加 ALL offset；过滤掉的 node 不 reload item。

保留 `allOnAction`、`allOffAction`、light control、repair、sync、heartbeat、Footer count 使用完整 `devices`。

- [ ] **Step 4: 修改空状态和编辑选择**

空状态判断顺序：

```swift
let hasVisibleContent = showsAllControl || !visibleDevices.isEmpty
if !hasVisibleContent, deviceNameFilterSession.isActive {
    collectionView.showEmptyDataView(
        title: "device_filter_no_matching_devices".localizedString,
        position: .center,
        bottomMargin: SCRYFit(30)
    )
} else if devices.isEmpty {
    // 保留现有 no_devices/no_devices_message
} else {
    collectionView.hideEmptyDataView()
}
```

编辑规则：

- `canEditDeviceAddresss` 改为 `visibleDevices.map(\.primaryUnicastAddress)`。
- Select All 选中 `visibleDevices`，取消时清空。
- `showSelectDatas` 中每个 group 的 addresses 与 visible address set 取交集，并移除没有可见设备的 group option。
- 删除仍从完整 `devices` 中按 `selectedAddresss` 找 Node，确保对象身份稳定。
- Filter active 且无可见真实设备时禁用 Edit；sort/repair/sync 仍按完整集合原规则。

- [ ] **Step 5: 接通 Footer 点击**

`setupUI()` 后设置：

```swift
footerView.deviceNameFilterEnabled = true
footerView.deviceNameFilterActive = deviceNameFilterSession.isActive
```

delegate 增加：

```swift
func functionDidClickDeviceFilter(view: SpaceFunctionFooterView) {
    (parent as? DevicesViewController)?
        .showDeviceNameFilterMenu(from: view.countBtn)
}
```

- [ ] **Step 6: 运行聚焦测试并提交**

Run 编译命令与 Task 1 相同，随后执行 `/tmp/DeviceNameFilterSessionTests`，Expected: PASS。

```bash
git add SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift
git commit -m "feat: filter main light devices" -- SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift
```

---

### Task 5: Switches 可见集合与安全索引

**Files:**
- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`

**Interfaces:**
- Consumes: `DeviceNameFilterSession`
- Produces internally: `visibleSwitches: [DeviceSwitchData]`

- [ ] **Step 1: 注入并观察共享会话**

新增 session、observation、`visibleSwitches`；初始化器接收 session；`viewDidLoad` 注册 weak observer；`deinit` 移除 observer。

- [ ] **Step 2: 每次 updateUI 从完整 manager 数据派生可见集合**

在 normalize 后执行：

```swift
private func applyDeviceNameFilter() {
    visibleSwitches = deviceNameFilterSession.filtered(
        MeshNetworkManager.instance.switchs,
        names: { [$0.name] }
    )
    footerView?.deviceNameFilterActive = deviceNameFilterSession.isActive
}
```

Footer count、`acPowerSwitchNodes`、刷新、权限和同步仍读取 `MeshNetworkManager.instance.switchs`。

- [ ] **Step 3: 替换所有展示索引**

`numberOfItemsInSection`、`cellForItemAt`、`didSelectItemAt`、长按均使用 `visibleSwitches`。`reloadSwitchItem(node:)` 先在 `visibleSwitches` 中定位对应 AC power switch；过滤掉的 item 不做局部 reload。

不得修改详情页、删除确认和 repository 的全量数据读取；它们接收的是可见列表中已解析出的具体对象。

- [ ] **Step 4: 空状态与 Footer**

- active 且 `visibleSwitches.isEmpty`：显示 `device_filter_no_matching_devices`。
- inactive 且完整 switches 为空：保留 `no_switches`。
- 有可见结果：隐藏空状态。
- Filter active 且零结果时 Edit 禁用；原始 count 不变。
- 启用 Footer filter 并实现与 Lights 相同的 parent menu callback。

- [ ] **Step 5: 聚焦测试与提交**

运行 Task 1 聚焦测试，Expected: PASS。

```bash
git add SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
git commit -m "feat: filter main switch devices" -- SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

---

### Task 6: Sensors 与 Others 接入共享过滤

**Files:**
- Modify: `SunSmart/Main/Device/Sensors/Controller/DeviceSensorsViewController.swift`
- Modify: `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`

**Interfaces:**
- Consumes: `DeviceNameFilterSession`
- Produces internally: `DeviceOthersListItem.filterName`、完整 `allItems` 与可见 `showItems`

- [ ] **Step 1: Sensors 只接入状态，不扩展业务**

为 Sensors 注入/观察 session、启用 Footer 点击并同步 selected 图片。`updateDevicesEmptyUI()` 使用：

```swift
if deviceNameFilterSession.isActive {
    collectionView.showEmptyDataView(
        title: "device_filter_no_matching_devices".localizedString,
        position: .center,
        bottomMargin: SCRYFit(30)
    )
} else {
    collectionView.showEmptyDataView(
        title: "no_sensors".localizedString,
        tipText: "no_sensors_message".localizedString,
        position: .center,
        bottomMargin: SCRYFit(30)
    )
}
```

不得新增 Sensor data source、SDK 查询或设备模型。

- [ ] **Step 2: 为 Others 建立稳定的完整/可见映射**

在私有 enum 中加入：

```swift
var filterName: String {
    switch self {
    case .dongle(let dongle): return dongle.name
    case .emergencyFireController(let device): return device.name
    }
}
```

控制器新增 `allItems`，`showItems` 保持为唯一可见 data source：

```swift
private func reloadShowItems() {
    let dongles = MeshNetworkManager.instance.dongles.map(DeviceOthersListItem.dongle)
    let emergency = DeviceEmerFireStore.shared.devices(in: space)
        .map(DeviceOthersListItem.emergencyFireController)
    allItems = dongles + emergency
    showItems = deviceNameFilterSession.filtered(allItems) { [$0.filterName] }
}
```

所有 collection、长按、删除、监控和详情继续只从 `showItems[indexPath.item]` 取对象。删除完成后重建完整集合并重新过滤。

- [ ] **Step 3: Others 空状态、局部刷新与 Footer**

- active 且 `showItems.isEmpty`：显示过滤空状态。
- inactive 且 `allItems.isEmpty`：显示现有 `no_others`。
- `reloadEmergencyFireItem(for:)` 只在可见 showItems 中定位；过滤掉的设备无需局部刷新。
- Footer count 继续使用当前完整计数逻辑。
- 启用 Footer filter、同步 active 图片并实现 parent callback。
- session observer 调用 `updateUI()`；使用 weak self，deinit 移除 observation。

- [ ] **Step 4: 聚焦测试与提交**

运行 Task 1 聚焦测试，Expected: PASS。

```bash
git add SunSmart/Main/Device/Sensors/Controller/DeviceSensorsViewController.swift SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift
git commit -m "feat: filter main sensor and other devices" -- SunSmart/Main/Device/Sensors/Controller/DeviceSensorsViewController.swift SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift
```

---

### Task 7: 全量回归、四品牌构建与交互验收

**Files:**
- Verify all files from Tasks 1–6
- Update only if verification exposes a scoped defect

- [ ] **Step 1: 运行聚焦测试**

```bash
swiftc -parse-as-library SunSmart/Main/Device/Filter/Model/DeviceNameFilterSession.swift Tests/Device/DeviceNameFilterSessionTests.swift -o /tmp/DeviceNameFilterSessionTests
```

```bash
/tmp/DeviceNameFilterSessionTests
```

Expected: `DeviceNameFilterSessionTests passed`。

- [ ] **Step 2: 检查本地化、资源、target 引用与 diff**

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
plutil -lint SunSmart/Assets.xcassets/Space/space_device_count_selected.imageset/Contents.json
git diff --check
```

Expected: 三个 plist/strings 检查均为 `OK`，`git diff --check` 无输出。确认三个新业务文件各有 4 条 Sources 引用。

- [ ] **Step 3: 构建 SunSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 构建 Archipelago**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: 构建 SLG Sync Plus**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: 构建 SylSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 7: 执行手工交互矩阵**

逐项记录 PASS/BLOCKED：

1. 初次进入 Main 四分类均为默认图片、原始数量。
2. 菜单只含 Search by Name、分隔线、Reset，位置在左下角按钮上方。
3. 搜索框自动聚焦、Search 键、系统 clear、已有 Trim 条件回填。
4. Cancel 与两种遮罩外部点击均不更新条件。
5. 空/全空格 Search 等同 Reset。
6. `room`/`ROOM` 子串匹配一致，中间双空格不折叠。
7. 四分类共享条件、selected 图片和 Reset。
8. Lights 开启组名前缀后按组名可见；关闭后同一组名不匹配。
9. `ALL` 自身参与过滤；可见时点击仍控制完整 Lights。
10. Footer 数量、repair、sync 保持全量语义。
11. 编辑 Select All 和 group selection 只选择当前可见设备；删除不触及隐藏设备。
12. active 零结果显示英中 `No matching devices`；未过滤空分类显示原空状态。
13. 设备新增、删除、改名和通知刷新后仍应用当前条件。
14. 进入 Main 深层页面再返回保留条件；深层列表展示完整数据。
15. 切到 Group、Scene、Timed、More 及其深层设备列表时展示完整数据。
16. Pop 回 Site 后重新进入 Space，条件和图片恢复默认。
17. iPhone/iPad 菜单与搜索 card 不越界，键盘不遮挡输入框。

- [ ] **Step 8: 最终范围审计**

Run:

```bash
git status --short
git diff --stat 2edfc37a..HEAD
```

确认没有 SDK 修改、依赖修改、Auth 信息、无关格式化或非 Main 列表行为变更。区分以下结论：

- 聚焦测试结果；
- 四品牌编译结果；
- 手工交互已验证项；
- 需要真机或真实 Mesh 网络才能验证的 BLOCKED 项。

---

## 实施完成定义

- 设计文档 13 条验收标准均有对应实现与验证记录。
- 纯逻辑聚焦测试通过。
- `git diff --check` 通过。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 generic iPhoneOS 构建通过。
- 不把编译成功描述为真机、键盘或真实 Mesh 控制已经验证。
- 未修改 Group、Scene、Timed、More 或其他深层设备列表的过滤语义。
