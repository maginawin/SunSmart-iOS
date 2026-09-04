# Lumineux Profile 与 Safe Mode 资源补充 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不修改共享业务代码和其他品牌 target 的前提下，为 Lumineux 接入 `profile_chart_occupancy_daylight`、`schedule_target_select`、`sensor_move`、`device_select` 四组 Figma 同名资源。

**Architecture:** 原始 Figma 矢量存入 `Lumineux/DesignAssets/Figma`，manifest 记录节点和逻辑画布，打包脚本机械生成 1x／2x／3x PNG。现有构建期合并器继续以完整 `.imageset` 覆盖公共同名资源；运行时仍使用原有 `UIImage(named:)` 调用。

**Tech Stack:** Figma MCP、Swift 脚本、CoreGraphics／ImageIO、Asset Catalog、XCTest、Ruby 配置与合并测试、Xcode `xcodebuild`。

## Global Constraints

- 只修改 Lumineux 资源、资源打包工具、品牌测试和 Lumineux 资源清单；不修改共享 UIKit 业务代码。
- 不修改 `SunSmart/Assets.xcassets`、`SLGSync/Assets-SLGSync.xcassets` 或其他 target。
- 品牌色严格使用 Figma 的 `#4D738A`，不运行时染色、不手绘图标路径。
- `device_select` 保持 30 × 30pt 透明画布，18 × 18pt Figma 图形居中，不放大内部图形。
- `profile_chart_occupancy_daylight` 只接入本次提供的 iPhone 212 × 234pt 图；没有提供的 `_ipad` 资源继续沿用公共版本。
- 保留当前脏工作区中的既有用户改动；本计划执行期间不自动提交或推送。

---

### Task 1: 为四组资源建立失败基线

**Files:**
- Modify: `Tests/Branding/LumineuxAssetTests.swift`
- Read: `Lumineux/DesignAssets/icon-manifest.json`

**Interfaces:**
- Consumes: 当前 manifest 的 `assets` 数组和 `Lumineux/Assets-Lumineux.xcassets`。
- Produces: 四组资源的节点、画布、倍率和 `device_select` 内容边界断言。

- [ ] **Step 1: 增加四组资源的 manifest 与画布断言**

在 `LumineuxAssetTests.swift` 的页面素材断言之后增加：

```swift
let supplementalAssets: [(name: String, node: String, width: Int, height: Int, contentSize: Int?)] = [
    ("profile_chart_occupancy_daylight", "16001:174597", 212, 234, nil),
    ("schedule_target_select", "16001:174651", 30, 30, nil),
    ("sensor_move", "16001:174616", 20, 20, nil),
    ("device_select", "0:17954", 30, 30, 18)
]

for expected in supplementalAssets {
    let asset = iconAssets.first { $0["asset"] as? String == expected.name }
    check(asset != nil, "Missing supplemental Lumineux asset: \(expected.name)")
    check(asset?["node"] as? String == expected.node,
          "Incorrect Figma source node for \(expected.name)")
    let width = (asset?["width"] as? Int) ?? (asset?["size"] as? Int)
    let height = (asset?["height"] as? Int) ?? (asset?["size"] as? Int)
    check(width == expected.width && height == expected.height,
          "Incorrect logical canvas for \(expected.name)")
    check(asset?["contentSize"] as? Int == expected.contentSize,
          "Incorrect content canvas for \(expected.name)")
}
```

把通用 `for asset in iconAssets` 的 `size` 强制读取改为宽高兼容读取，并对 `device_select` 的透明边距增加像素范围检查：30pt 输出中可见内容宽高不得超过 18pt 加抗锯齿容差 1px，且四边留白差不得超过 1px。

- [ ] **Step 2: 运行素材测试并确认按预期失败**

Run:

```bash
swift Tests/Branding/LumineuxAssetTests.swift
```

Expected: FAIL，首个失败明确为 `Missing supplemental Lumineux asset: profile_chart_occupancy_daylight`，而不是编译错误或现有素材回归。

- [ ] **Step 3: 记录失败输出并确认没有生产资源变化**

Run:

```bash
git diff --check -- Tests/Branding/LumineuxAssetTests.swift
git status --short
```

Expected: 只有测试文件新增本任务断言；四个新 `.imageset` 尚不存在。

---

### Task 2: 下载 Figma 原稿并扩展机械打包器

**Files:**
- Create: `Lumineux/DesignAssets/Figma/node-16001-174597.pdf`
- Create: `Lumineux/DesignAssets/Figma/node-16001-174651.pdf`
- Create: `Lumineux/DesignAssets/Figma/node-16001-174616.pdf`
- Create: `Lumineux/DesignAssets/Figma/node-0-17954.pdf`
- Modify: `Lumineux/DesignAssets/icon-manifest.json`
- Modify: `scripts/prepare_lumineux_icons.swift`
- Create: `Lumineux/Assets-Lumineux.xcassets/profile_chart_occupancy_daylight.imageset/*`
- Create: `Lumineux/Assets-Lumineux.xcassets/schedule_target_select.imageset/*`
- Create: `Lumineux/Assets-Lumineux.xcassets/sensor_move.imageset/*`
- Create: `Lumineux/Assets-Lumineux.xcassets/device_select.imageset/*`

**Interfaces:**
- Consumes: Figma file `P4AaSxu8SJe2Tf2gpyTFT9` 的四个已确认节点。
- Produces: 四份不可改色的矢量原稿、四个完整 imageset，以及支持非正方形画布和居中内容画布的打包器。

- [ ] **Step 1: 从 Figma 重新读取并下载四个确切节点**

依次调用官方 Figma `get_design_context`，四次调用分别使用以下参数：

```json
[
  {"fileKey":"P4AaSxu8SJe2Tf2gpyTFT9","nodeId":"16001:174597","clientFrameworks":"UIKit","clientLanguages":"Swift","skillNames":"figma-design-to-code"},
  {"fileKey":"P4AaSxu8SJe2Tf2gpyTFT9","nodeId":"16001:174651","clientFrameworks":"UIKit","clientLanguages":"Swift","skillNames":"figma-design-to-code"},
  {"fileKey":"P4AaSxu8SJe2Tf2gpyTFT9","nodeId":"16001:174616","clientFrameworks":"UIKit","clientLanguages":"Swift","skillNames":"figma-design-to-code"},
  {"fileKey":"P4AaSxu8SJe2Tf2gpyTFT9","nodeId":"0:17954","clientFrameworks":"UIKit","clientLanguages":"Swift","skillNames":"figma-design-to-code"}
]
```

工具每次只接收数组中的一个对象。随后通过 Figma `download_assets` 对相同 `fileKey` 和 `nodeId` 请求 PDF 矢量导出，并保存到上方四个固定路径；不得从页面截图裁切，也不得使用 SunSmart／SLGSync 图片重新着色。

- [ ] **Step 2: 扩展 manifest 模型以支持宽高与内容画布**

将 `scripts/prepare_lumineux_icons.swift` 的 `Asset` 改为：

```swift
struct Asset: Decodable {
    let asset: String
    let node: String
    let size: Int?
    let width: Int?
    let height: Int?
    let contentSize: Int?
    let source: String

    var canvasWidth: Int { width ?? size! }
    var canvasHeight: Int { height ?? size! }
    var contentWidth: Int { contentSize ?? canvasWidth }
    var contentHeight: Int { contentSize ?? canvasHeight }
}
```

保留已有 `size` 字段兼容性。渲染时按 `canvasWidth × canvasHeight` 创建输出，使用 `min(contentWidth/sourceWidth, contentHeight/sourceHeight)` 等比缩放原 PDF，并将结果居中；默认资源的内容画布等于输出画布，现有图标生成结果不得变化。

- [ ] **Step 3: 在 manifest 添加四个确定条目**

```json
{
  "asset": "profile_chart_occupancy_daylight",
  "node": "16001:174597",
  "width": 212,
  "height": 234,
  "category": "Profile",
  "source": "Figma/node-16001-174597.pdf"
},
{
  "asset": "schedule_target_select",
  "node": "16001:174651",
  "size": 30,
  "category": "Timed",
  "source": "Figma/node-16001-174651.pdf"
},
{
  "asset": "sensor_move",
  "node": "16001:174616",
  "size": 20,
  "category": "Group",
  "source": "Figma/node-16001-174616.pdf"
},
{
  "asset": "device_select",
  "node": "0:17954",
  "size": 30,
  "contentSize": 18,
  "category": "Device",
  "source": "Figma/node-0-17954.pdf"
}
```

- [ ] **Step 4: 运行打包脚本生成四个 imageset**

Run:

```bash
swift scripts/prepare_lumineux_icons.swift
```

Expected: 输出的打包数量比执行前增加 4；四组均含 `Contents.json` 和 1x／2x／3x PNG。现有 manifest 图标重新生成后保持既有逻辑尺寸。

- [ ] **Step 5: 运行素材测试并确认转绿**

Run:

```bash
swift Tests/Branding/LumineuxAssetTests.swift
```

Expected: PASS；四个节点和尺寸正确，`device_select` 内容在 30pt 画布内居中，非正方形图表未被裁成正方形。

- [ ] **Step 6: 验证合并器没有改变公共输入**

Run:

```bash
ruby Tests/Branding/LumineuxMergeTests.rb
ruby Tests/Branding/LumineuxConfigurationTests.rb
```

Expected: 两个脚本均 exit 0；Lumineux 派生 catalog 使用四组新覆盖，公共 catalog 与其他 target 配置不变。

---

### Task 3: 验证真实 UIKit 使用位置与独立来源

**Files:**
- Modify: `Tests/Branding/LumineuxRuntimeTests.swift`
- Modify: `Tests/Branding/README.md`
- Read: `SunSmart/Main/Profile/View/ProfileTriggerConditionPhasesView.swift`
- Read: `SunSmart/Main/Profile/View/ProfilePowerUpBehaviorView.swift`
- Read: `SunSmart/Main/Group/View/GroupSensorView.swift`
- Read: `SunSmart/Main/Device/Reset/View/DeviceForceResetViewCell.swift`

**Interfaces:**
- Consumes: 主 App 合并后的四个同名资源与测试 bundle 独立编译的 Lumineux reference catalog。
- Produces: iPhone 16 中英文运行时来源、尺寸、控件边界和截图证据。

- [ ] **Step 1: 增加四组运行时来源测试**

在 `LumineuxRuntimeTests` 增加 `testProfileAndSafeModeSupplementalAssets()`：

```swift
func testProfileAndSafeModeSupplementalAssets() throws {
    try assertNamedImage("profile_chart_occupancy_daylight", size: CGSize(width: 212, height: 234))
    try assertNamedImage("schedule_target_select", size: 30)
    try assertNamedImage("sensor_move", size: 20)
    try assertNamedImage("device_select", size: 30)

    for name in ["profile_chart_occupancy_daylight", "schedule_target_select", "sensor_move", "device_select"] {
        try assertResolvedImageMatchesLumineuxSource(UIImage(named: name), name: name)
    }

    let phases = ProfileTriggerConditionPhasesView(frame: CGRect(x: 0, y: 0, width: 343, height: 640))
    let chart = try XCTUnwrap(descendants(phases).compactMap { $0 as? UIImageView }
        .first { $0.image?.size == CGSize(width: 212, height: 234) })
    try assertResolvedImageMatchesLumineuxSource(chart.image, name: "profile_chart_occupancy_daylight")

    let powerUp = ProfilePowerUpBehaviorView(frame: CGRect(x: 0, y: 0, width: 343, height: 320))
    let selectedButton = try XCTUnwrap(descendants(powerUp).compactMap { $0 as? UIButton }
        .first { $0.image(for: .selected)?.size == CGSize(width: 30, height: 30) })
    try assertResolvedImageMatchesLumineuxSource(selectedButton.image(for: .selected), name: "schedule_target_select")

    let sensor = GroupSensorView(frame: CGRect(x: 0, y: 0, width: 343, height: 320))
    let expectedMovement = try oraclePixels(try XCTUnwrap(UIImage(named: "sensor_move")))
    let movement = try XCTUnwrap(descendants(sensor).compactMap { $0 as? UIImageView }.first { imageView in
        guard let image = imageView.image, let pixels = try? oraclePixels(image) else { return false }
        return pixels.width == expectedMovement.width &&
               pixels.height == expectedMovement.height &&
               pixels.rgba == expectedMovement.rgba
    })
    try assertResolvedImageMatchesLumineuxSource(movement.image, name: "sensor_move")

    let selectedControl = UIButton(normalImageName: "device_select_un", selectedImageName: "device_select")
    selectedControl.isSelected = true
    try assertResolvedImageMatchesLumineuxSource(selectedControl.currentImage, name: "device_select")
}
```

将四个视图放入测试 window 后执行布局，断言相关图片 frame 位于宿主 bounds 内且 `hasAmbiguousLayout == false`，并生成 Profile、Group Sensor、Safe Mode 选择态截图附件。

- [ ] **Step 2: 生成独立测试 workspace**

Run:

```bash
branding_tmp="$(mktemp -d /private/tmp/lumineux-profile-safe-mode.XXXXXX)"
export LUMINEUX_SOURCE_PACKAGES_DIR=/Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages
ruby scripts/make_lumineux_test_workspace.rb "$branding_tmp/runtime"
```

Expected: 生成 `LumineuxBranding.xcworkspace`，reference bundle 独立编译更新后的 Lumineux catalog。

- [ ] **Step 3: 在 iPhone 16 英文环境运行测试**

Run:

```bash
xcodebuild -workspace "$branding_tmp/runtime/LumineuxBranding.xcworkspace" -scheme LumineuxBranding -configuration Debug -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' -derivedDataPath "$branding_tmp/DerivedData" -clonedSourcePackagesDirPath "$LUMINEUX_SOURCE_PACKAGES_DIR" -disableAutomaticPackageResolution -skipPackageUpdates -resultBundlePath "$branding_tmp/iphone16-en.xcresult" -testLanguage en -testRegion US -parallel-testing-enabled NO -jobs 4 test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: 新增测试通过，无实际失败或跳过。

- [ ] **Step 4: 复用构建产物运行简体中文测试**

Run:

```bash
xcodebuild -workspace "$branding_tmp/runtime/LumineuxBranding.xcworkspace" -scheme LumineuxBranding -configuration Debug -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' -derivedDataPath "$branding_tmp/DerivedData" -clonedSourcePackagesDirPath "$LUMINEUX_SOURCE_PACKAGES_DIR" -disableAutomaticPackageResolution -skipPackageUpdates -resultBundlePath "$branding_tmp/iphone16-zh.xcresult" -testLanguage zh-Hans -testRegion CN -parallel-testing-enabled NO -jobs 4 test-without-building CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: 新增测试通过，中文布局没有裁切或约束歧义。

- [ ] **Step 5: 导出并人工检查截图**

Run:

```bash
xcrun xcresulttool export attachments --path "$branding_tmp/iphone16-en.xcresult" --output-path "$branding_tmp/screenshots-en"
xcrun xcresulttool export attachments --path "$branding_tmp/iphone16-zh.xcresult" --output-path "$branding_tmp/screenshots-zh"
```

Expected: Profile 图表、选中按钮、传感器移动图标和设备选择态均清晰，未显示 SunSmart 紫色或 SLGSync 绿色资源，无模糊、裁切和重叠。

---

### Task 4: 更新清单并完成构建回归

**Files:**
- Modify: `docs/lumineux-missing-assets.md`
- Modify: `Tests/Branding/README.md`
- Verify: `SunSmart.xcworkspace`

**Interfaces:**
- Consumes: 四组已验证资源、静态测试结果和 iPhone 16 截图。
- Produces: 57 组剩余清单、可复现验证记录、Lumineux 与 SunSmart 构建证据。

- [ ] **Step 1: 更新资源数量和待补清单**

在 `docs/lumineux-missing-assets.md` 中：

- 新增本轮四组资源表格及节点、逻辑尺寸。
- 已提供资源总数增加 4。
- 从原 60 组清单删除 `profile_chart_occupancy_daylight`、`schedule_target_select`、`device_select`，合计改为 57。
- 把 `sensor_move` 记录为 SLGSync 差异统计之外新增的 Lumineux 品牌覆盖，不虚减原清单。
- 明确 `_ipad` 图表仍未提供。

- [ ] **Step 2: 运行全部静态回归**

Run:

```bash
ruby Tests/Branding/LumineuxConfigurationTests.rb
ruby Tests/Branding/LumineuxMergeTests.rb
swift Tests/Branding/LumineuxAssetTests.swift
bash scripts/check_nordic_sdk_dependency.sh
git diff --check
```

Expected: 所有命令 exit 0；NordicSigMeshSDK 仍使用既有依赖，不涉及 SDK 源码修改。

- [ ] **Step 3: 构建 Lumineux 真机 Debug**

在正常 `Library/Developer/Xcode/DerivedData3` 下创建独立目录，并执行：

```bash
derived_data="$(mktemp -d /Users/sr/Library/Developer/Xcode/DerivedData3/LumineuxProfileAssets.XXXXXX)"
xcodebuild -workspace SunSmart.xcworkspace -scheme Lumineux -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath "$derived_data/AppBuild" -clonedSourcePackagesDirPath "$LUMINEUX_SOURCE_PACKAGES_DIR" -disableAutomaticPackageResolution -skipPackageUpdates build
```

Expected: `** BUILD SUCCEEDED **`；日志中 actool 只编译生成的 merged catalog，无重复资源或 Ruby sandbox 拒绝。

- [ ] **Step 4: 校验签名与合并后资源来源**

Run:

```bash
codesign --verify --deep --strict "$derived_data/AppBuild/Build/Products/Debug-iphoneos/Lumineux.app"
codesign -dvv "$derived_data/AppBuild/Build/Products/Debug-iphoneos/Lumineux.app"
```

Expected: 签名完整，Team 为 `JTD3WYUC58`；四组同名资源来自 Lumineux catalog。

- [ ] **Step 5: 构建 SunSmart Debug 回归**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' -derivedDataPath "$derived_data/SunSmartBuild" -clonedSourcePackagesDirPath "$LUMINEUX_SOURCE_PACKAGES_DIR" -disableAutomaticPackageResolution -skipPackageUpdates build CODE_SIGNING_ALLOWED=NO ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: `** BUILD SUCCEEDED **`；SunSmart 继续只使用公共资源，未加载 Lumineux 四组覆盖。

- [ ] **Step 6: 最终差异审阅**

Run:

```bash
git status --short
git diff --stat
git diff --check
```

Expected: 没有共享业务 Swift、SunSmart／SLGSync 资源、其他 target 或服务器配置变化；不提交、不推送，等待用户下一步指令。
