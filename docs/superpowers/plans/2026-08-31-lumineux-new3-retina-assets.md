# Lumineux new3 Retina Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `/Users/sr/Documents/SunSmart/assets/new3` 中已确认的 28 对原始 Retina PNG 以 29 个 Lumineux 同名资源接入工程，完整验证真实 UIKit 布局、构建期 catalog 合并、真机构建与签名，同时不覆盖用户在主工作目录中的并行修改。

**Architecture:** 在独立 Git worktree 和 `codex/lumineux-new3-assets` 临时分支中执行测试先行接入；每个资源在 `DesignAssets/Provided` 与 Lumineux asset catalog 各保留一份逐字节相同的 2x/3x PNG，1x 仅保留空槽。现有构建期合并器继续将 Common catalog 作为底图，再用 Lumineux 同名 imageset 覆盖；不修改生产 Swift、Xcode 工程或依赖。验证通过后仅把从设计基线提交起的实现补丁应用回主工作目录，并确保主目录原有暂存区整体哈希未变化。

**Tech Stack:** Swift/UIKit、XCTest、Xcode asset catalog、Ruby/xcodeproj、Swift 静态资源测试、Git worktree。

**Design baseline:** `aa5eb8c258ba44dec84e9d090886fcbd5350b8b5`（`docs: specify Lumineux new3 Retina assets`）及 `docs/superpowers/specs/2026-08-31-lumineux-new3-retina-assets-design.md`。

## 固定范围与映射

本计划只导入下表 29 个目标资源。`button/Group 160` 必须复制为两个目标 imageset；两份目标的 PNG 字节相同，但资源名不同。

| new3 相对路径（省略 `@2x.png` / `@3x.png`） | 分组 | 最终资源名 |
| --- | --- | --- |
| `Proximity/images/Controls/Edit Menus/Single Action` | Common | `value_buoy` |
| `button/Group 160` | Firmware | `distributor_nodes_highlight` |
| `button/Group 160` | Firmware | `updatating_nodes` |
| `images/version` | Firmware | `firmware_cloud_version` |
| `icon/images/download` | Firmware | `initiator` |
| `Group 194` | Firmware | `mesh_distributor_guide_4` |
| `Frame 161` | Firmware | `mesh_upgrade_guide_1` |
| `Group 192` | Firmware | `mesh_upgrade_guide_2` |
| `button/space_add_3` | Firmware | `mesh_upgrade_guide_3` |
| `icon/space_device` | Firmware | `single_device` |
| `图表2` | Profile | `adjust_speed_fast` |
| `图表1` | Profile | `adjust_speed_slow` |
| `Scheme 4` | Profile | `daylight_scheme4` |
| `Scheme 5` | Profile | `daylight_scheme5` |
| `Scheme 6` | Profile | `daylight_scheme6` |
| `Scheme 7` | Profile | `daylight_scheme7` |
| `images/lightsensor20` | Profile | `daylight_standalone_sensor` |
| `Defined` | Profile | `power_state_defined` |
| `Off` | Profile | `power_state_off` |
| `Restore` | Profile | `power_state_restore` |
| `button/数据表` | Profile | `profile_chart_daylight` |
| `数据表` | Profile | `profile_chart_manual_control` |
| `Proximity/数据表` | Profile | `profile_chart_occupancy` |
| `Proximity/images/sensor_move` | Profile | `profile_person` |
| `images/sensor_move` | Profile | `profile_person_big` |
| `Group 116` | Profile | `profile_proximity_lighting` |
| `Proximity/images/数据图表` | Profile | `sensor_manul_override_timeout` |
| `Proximity/images/Scene/images/编组` | Scene | `scene_data_add` |
| `Proximity/images/Property 1=code2` | Space | `locked` |

明确不导入 `.DS_Store`、任何 `FireAlarm1.5` 内容、根目录 `Group 160`、`icon/Nav`、`images/download` 和 `Proximity/images/数据表`。不得把 `icon/space_device` 缩放后复用为 `energy_light` 或 `distributor_single_device_highlight`，也不得从 iPhone 图表生成任何 `_ipad` 资源。

## Task 0: 隔离主工作目录并建立可回滚基线

**Files:**

- Inspect only: `/Users/sr/Documents/SunSmart/sun-smart/.git/index`
- Create worktree: `/private/tmp/sun-smart-lumineux-new3-worktree`
- Branch: `codex/lumineux-new3-assets`

- [ ] 在主目录输出并记录当前提交、全部 staged/unstaged/untracked 路径及暂存补丁整体哈希：

```sh
git -C /Users/sr/Documents/SunSmart/sun-smart rev-parse HEAD
git -C /Users/sr/Documents/SunSmart/sun-smart status --short
git -C /Users/sr/Documents/SunSmart/sun-smart diff --cached --binary | shasum -a 256
```

预期 `HEAD` 为 `aa5eb8c258ba44dec84e9d090886fcbd5350b8b5`。主目录现有暂存修改全部归用户所有；不得执行 `git add`、`git restore`、`git reset`、`git clean` 或覆盖式复制。

- [ ] 确认临时 worktree 路径和分支名都未被占用；若已存在，先检查来源并停止报告，不自动删除：

```sh
git -C /Users/sr/Documents/SunSmart/sun-smart worktree list
git -C /Users/sr/Documents/SunSmart/sun-smart branch --list codex/lumineux-new3-assets
test ! -e /private/tmp/sun-smart-lumineux-new3-worktree
```

- [ ] 从设计基线创建隔离 worktree：

```sh
git -C /Users/sr/Documents/SunSmart/sun-smart worktree add \
  -b codex/lumineux-new3-assets \
  /private/tmp/sun-smart-lumineux-new3-worktree \
  aa5eb8c258ba44dec84e9d090886fcbd5350b8b5
```

- [ ] 在隔离目录确认工作树为空，并运行最小基线：

```sh
git -C /private/tmp/sun-smart-lumineux-new3-worktree status --short
swift /private/tmp/sun-smart-lumineux-new3-worktree/Tests/Branding/LumineuxAssetTests.swift
ruby /private/tmp/sun-smart-lumineux-new3-worktree/Tests/Branding/LumineuxMergeTests.rb
```

预期隔离工作树无修改，现有 92 组素材测试与合并器测试通过。任何基线失败都先按 `superpowers:systematic-debugging` 查明原因，不能把失败归因于本轮尚未接入的资源。

## Task 1: 先建立 121 组静态资源合同并观察 RED

**Files:**

- Modify: `Tests/Branding/LumineuxAssetTests.swift`

- [ ] 在 `expectedAssetGroups` 中按字母顺序加入固定映射中的 29 个资源及业务分组，把错误文案从 `92-resource` 改为 `121-resource`，把 `discovered.count` 的合同从 92 改为 121。

- [ ] 保留现有 `ProvidedGroupedAsset`，新增 `providedNew3Assets: [ProvidedGroupedAsset]`。数组必须恰好 29 项，并使用本文末尾“素材 Oracle”中的精确像素和 SHA-256。

- [ ] 将现有 11 组与新增 29 组共用同一验证函数或同一循环。每一项必须断言：

```swift
check(expectedAssetGroups[asset.name] == asset.group, "Wrong business group")
check(entries.count == 3, "Expected empty 1x plus supplied 2x/3x")
check(entries.filter { $0["scale"] == "1x" }.count == 1, "Exactly one 1x slot")
check(entries.filter { $0["scale"] == "2x" }.count == 1, "Exactly one 2x slot")
check(entries.filter { $0["scale"] == "3x" }.count == 1, "Exactly one 3x slot")
check(entries.allSatisfy { $0["idiom"] == "universal" }, "Universal only")
check(entries.first { $0["scale"] == "1x" }?["filename"] == nil, "No 1x filename")
check(!FileManager.default.fileExists(atPath: unexpectedOneX.path), "No generated 1x PNG")
check(catalogData == sourceData, "Catalog/source bytes differ")
check(digest == asset.hashes[scale], "Supplied bytes changed")
check(rendered.width == expected.width && rendered.height == expected.height,
      "Incorrect pixel canvas")
```

- [ ] 将最终成功信息更新为明确包含 `29 new3 supplied Retina assets` 和 Lumineux `121` 组合同，避免继续输出过期的 92 组语义。

- [ ] 从隔离 worktree 根目录运行测试，确认因 manifest/资源尚未加入而失败：

```sh
cd /private/tmp/sun-smart-lumineux-new3-worktree
swift Tests/Branding/LumineuxAssetTests.swift
```

预期失败必须指向 `121-resource mapping`、缺少某个已确认 imageset，或缺少 `DesignAssets/Provided` 源文件。若测试意外通过，说明合同没有覆盖新增资源，先修正测试。

- [ ] 检查测试改动并在临时分支提交：

```sh
git diff --check
git diff -- Tests/Branding/LumineuxAssetTests.swift
git add Tests/Branding/LumineuxAssetTests.swift
git commit -m "test: define Lumineux new3 asset contracts"
```

## Task 2: 先建立真实 UIKit 来源与布局测试并观察 RED

**Files:**

- Modify: `Tests/Branding/LumineuxRuntimeTests.swift`

- [ ] 新增 `testProvidedNew3RetinaAssetsFitProductionControls()`。测试开头逐项调用 `assertResolvedImageMatchesLumineuxSource(UIImage(named:), name:)`，覆盖全部 29 个最终资源名。不要从 Common 或 SLGSync catalog 建立 oracle；独立 reference catalog 必须仍由 Lumineux 源 catalog 编译。

- [ ] 在同一测试中使用以下真实生产组件，按图片名查找其实际 `UIImageView`/`UIButton`，再调用 `assertResolvedImageMatchesLumineuxSource`、`assertContained`、`XCTAssertFalse(hasAmbiguousLayout)`：

  - `BuoySliderView(frame:functionType:)`：使用 `.level()`，发送 slider `.touchDown`，验证 `value_buoy` 真实浮标，宽度为 50pt；高度允许设计源 2x/3x 取整导致的约 36.33–36.5pt，不改图。
  - `MeshFirmwareUpgradeHeaderView(frame:)`：设置 `step = .upgrade`，验证 selected `distributor_nodes_highlight`。
  - `BLEUpgradeInstructionsController`：在 `show` 之前赋值三个 `InstructionsData`，分别使用 `initiator`、`single_device`、`updatating_nodes`；`name`/`message` 使用现有国际化字符串或测试文本，不新增用户文案。
  - `MeshFirmwareUpgradeGuideView(title:message:steps:contentHeight:)`：分别用 `[.selectDistributor, .selectDevices, .waiting]` 和 `[.distributor]`，验证 `mesh_upgrade_guide_1...3` 与 `mesh_distributor_guide_4` 的真实 cell。
  - 测试内 subclass `FirmwareVersionViewController`，覆盖 `createsUIBeforeCloudRequest` 为 `true`、`loadFirmwareData()` 为空，使用 `FirmwareUpdateTypeData(productId:targetVersion:nodes:)`，验证 `firmware_cloud_version` 而不发网络请求。
  - `PowerUpBehaviorInstructionController`：验证 `power_state_off`、`power_state_restore`、`power_state_defined`。
  - `AdjustSpeedInstructionController`：验证 `adjust_speed_slow`、`adjust_speed_fast`。
  - `ManualOverrideTimeoutInstructionController`：验证 `sensor_manul_override_timeout`。
  - `DaylightSensorInstructionsHeaderView(frame:)`：验证 `daylight_standalone_sensor`。
  - `ProfileProximityLightingNumberView(frame:)`：验证 `profile_person`。
  - Profile 指引/phase 的现有生产视图：验证 `daylight_scheme4...7`、`profile_chart_daylight`、`profile_chart_manual_control`、`profile_chart_occupancy`、`profile_person_big` 与 `profile_proximity_lighting`。iPhone 断言新 iPhone 图；iPad 明确保持现有 `_ipad` Common 图，不把本轮 iPhone PNG 当成 iPad oracle。
  - `SceneAddDataAddCell(frame:)`：验证 `scene_data_add`。
  - `SpacesViewCell(frame:)`：构造需要密码验证的非 owner `SpaceData`，验证可见 `locked`。

- [ ] 每个生产容器完成 layout 后保存可人工核对的附件，附件名固定为：

```text
New3-common-buoy
New3-firmware-header-and-flow
New3-firmware-guides
New3-profile-instructions
New3-profile-charts
New3-scene-and-space
```

- [ ] 先不修改 `scripts/make_lumineux_test_workspace.rb` 的 92 组基线；生成临时测试工程并只运行新测试：

```sh
cd /private/tmp/sun-smart-lumineux-new3-worktree
branding_tmp="$(mktemp -d /private/tmp/lumineux-new3-red.XXXXXX)"
ruby scripts/make_lumineux_test_workspace.rb "$branding_tmp/runtime"
xcodebuild \
  -workspace "$branding_tmp/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0,arch=x86_64' \
  -derivedDataPath "$branding_tmp/DerivedData" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedNew3RetinaAssetsFitProductionControls \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

预期编译成功但测试因独立 Lumineux reference catalog 缺少新增图片而失败。若当前模拟器 OS 名称不同，只能用 `xcrun simctl list devices available` 中同名设备的实际 ID 替换 destination，不创建或删除模拟器。

- [ ] 仅修正测试自身的编译问题，直到得到“缺少新增 Lumineux reference image”的正确 RED；不要提前复制资源，也不要修改生产 Swift。

- [ ] 在临时分支提交 RED 测试：

```sh
git diff --check
git add Tests/Branding/LumineuxRuntimeTests.swift
git commit -m "test: cover Lumineux new3 production layouts"
```

## Task 3: 最小接入 29 个 2x/3x imageset 并转为 GREEN

**Files:**

- Add: `Lumineux/DesignAssets/Provided/{Common,Firmware,Profile,Scene,Space}/*.png`
- Add: `Lumineux/Assets-Lumineux.xcassets/{Common,Firmware,Profile,Scene,Space}/*.imageset/Contents.json`
- Add: `Lumineux/Assets-Lumineux.xcassets/{Common,Firmware,Profile,Scene,Space}/*.imageset/*@2x.png`
- Add: `Lumineux/Assets-Lumineux.xcassets/{Common,Firmware,Profile,Scene,Space}/*.imageset/*@3x.png`
- Modify: `Lumineux/DesignAssets/asset-groups.json`
- Modify: `scripts/make_lumineux_test_workspace.rb`

- [ ] 按“固定范围与映射”将每对源 PNG 复制两次：一份规范化命名到 `DesignAssets/Provided/<group>/<name>@{2,3}x.png`，另一份逐字节复制到 `<name>.imageset`。只允许 `mkdir` 与二进制复制；不得调用 `sips`、ImageMagick、pngquant 或任何重新编码工具。

- [ ] 每个新增 `Contents.json` 使用完全相同的三槽结构，仅替换 `<name>`：

```json
{
  "images" : [
    {
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "<name>@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "<name>@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

不得创建 `<name>@1x.png`。

- [ ] 在 `asset-groups.json` 的 `assets` 对象中按现有字母顺序加入 29 个 `name: group`，不更改 `groups` 顺序。

- [ ] 将 `scripts/make_lumineux_test_workspace.rb` 中 reference catalog 的数量合同从 92 改为 121，错误文案同步改成 `Expected 121 complete Lumineux catalog sets`。

- [ ] 运行静态资源测试，预期 GREEN：

```sh
cd /private/tmp/sun-smart-lumineux-new3-worktree
swift Tests/Branding/LumineuxAssetTests.swift
```

- [ ] 重新生成临时测试工程，只运行新 UIKit 测试，预期 GREEN：

```sh
branding_tmp="$(mktemp -d /private/tmp/lumineux-new3-green.XXXXXX)"
ruby scripts/make_lumineux_test_workspace.rb "$branding_tmp/runtime"
xcodebuild \
  -workspace "$branding_tmp/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0,arch=x86_64' \
  -derivedDataPath "$branding_tmp/DerivedData" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedNew3RetinaAssetsFitProductionControls \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

- [ ] 检查没有生产代码、工程配置、FireAlarm 或排除资源进入 diff：

```sh
git diff --check
git diff --name-only
git diff --name-only | grep -E '(^SunSmart/.*\.swift$|FireAlarm1\.5|project\.pbxproj)' && exit 1 || true
find Lumineux/Assets-Lumineux.xcassets -name '*@1x.png' -path '*value_buoy*' -o -name '*@1x.png' -path '*Firmware*' -o -name '*@1x.png' -path '*Profile*'
```

最后一条只能用于人工确认本轮新增目录不存在 1x；不能删除既有资源。

- [ ] 在临时分支提交实现：

```sh
git add Lumineux/DesignAssets/Provided \
  Lumineux/Assets-Lumineux.xcassets \
  Lumineux/DesignAssets/asset-groups.json \
  scripts/make_lumineux_test_workspace.rb
git commit -m "feat: add Lumineux new3 Retina assets"
```

## Task 4: 更新缺失清单并完成全量静态回归

**Files:**

- Modify: `docs/lumineux-missing-assets.md`
- Modify: `Tests/Branding/README.md`

- [ ] 更新缺失清单：记录本轮 28 对源 PNG 对应 29 个资源、4 对排除素材、无 1x/无重编码、无生产 Swift 修改，以及以下准确数量：

```text
Lumineux source catalog: 121
SLGSync non-Fire covered: 83 / 94
SLGSync non-Fire missing: 11
additional packaged assets: 33
provided total: 116
merged catalog: 695 = 121 Lumineux + 574 Common
```

- [ ] 缺失清单只保留以下 11 组非 FireAlarm 待提供资源：

```text
Energy: energy_light
Firmware: distributor_single_device_highlight
Group: auto_big, member_add, switch_save_un
Profile: profile_chart_daylight_ipad, profile_chart_manual_control_ipad,
         profile_chart_occupancy_daylight_ipad, profile_chart_occupancy_ipad,
         profile_chart_occupancy_standby, profile_chart_occupancy_standby_ipad
```

- [ ] 在 `Tests/Branding/README.md` 追加本轮资源合同、新 focused test 名、六组合矩阵、截图数量和构建验证说明。测试尚未执行的结果不能预写成“已通过”；先写命令与验收项，Task 5/6 完成后再填真实结果。

- [ ] 运行全量静态/脚本回归：

```sh
cd /private/tmp/sun-smart-lumineux-new3-worktree
swift Tests/Branding/LumineuxAssetTests.swift
ruby Tests/Branding/LumineuxMergeTests.rb
ruby Tests/Branding/LumineuxGeneratorTests.rb
ruby Tests/Branding/LumineuxConfigurationTests.rb
ruby scripts/validate_lumineux_asset_groups.rb \
  Lumineux/Assets-Lumineux.xcassets \
  Lumineux/DesignAssets/asset-groups.json
git diff --check
```

若 validator 是 module-only 且没有 CLI 入口，以 `LumineuxConfigurationTests.rb` 中已有调用为准，不临时改生产脚本来迎合命令。

- [ ] 确认 NordicSigMeshSDK 仍引用既有锁定配置，未出现 package diff：

```sh
git diff -- SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved
git diff -- SunSmart.xcodeproj/project.pbxproj
```

两条预期无输出。

- [ ] 提交文档和静态验证更新：

```sh
git add docs/lumineux-missing-assets.md Tests/Branding/README.md
git commit -m "docs: record Lumineux new3 asset coverage"
```

## Task 5: 执行六组合 focused UIKit 矩阵并人工审图

**Files:**

- Verify: `Tests/Branding/LumineuxRuntimeTests.swift`
- Modify after evidence: `Tests/Branding/README.md`
- Modify after evidence: `docs/lumineux-missing-assets.md`

- [ ] 使用 `xcrun simctl list devices available` 确认现有 iPhone SE 3、iPhone 16、iPad Pro 11 M4 的 simulator ID；不创建、删除或抹除模拟器。

- [ ] 在 `/private/tmp` 创建临时测试 workspace。英文用 `test` 构建一次并串行跑三台设备，中文复用构建产物执行 `test-without-building`：

```sh
cd /private/tmp/sun-smart-lumineux-new3-worktree
branding_tmp="$(mktemp -d /private/tmp/lumineux-new3-matrix.XXXXXX)"
ruby scripts/make_lumineux_test_workspace.rb "$branding_tmp/runtime"

xcodebuild \
  -workspace "$branding_tmp/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=9FCF83EB-38F9-4B61-A35E-D88F8665A1B5,arch=x86_64' \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -destination 'platform=iOS Simulator,id=1B4321CD-F455-4252-8504-105435A02C9A,arch=x86_64' \
  -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath "$branding_tmp/DerivedData" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath "$branding_tmp/matrix-en.xcresult" \
  -testLanguage en -testRegion US \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedNew3RetinaAssetsFitProductionControls \
  -parallel-testing-enabled NO -jobs 4 \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES

xcodebuild \
  -workspace "$branding_tmp/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=9FCF83EB-38F9-4B61-A35E-D88F8665A1B5,arch=x86_64' \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -destination 'platform=iOS Simulator,id=1B4321CD-F455-4252-8504-105435A02C9A,arch=x86_64' \
  -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath "$branding_tmp/DerivedData" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath "$branding_tmp/matrix-zh.xcresult" \
  -testLanguage zh-Hans -testRegion CN \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedNew3RetinaAssetsFitProductionControls \
  -parallel-testing-enabled NO -jobs 4 \
  test-without-building CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

若设备 ID 漂移，替换为同名现有设备的实际 ID，并在 README 记录实际值。

- [ ] 导出两份结果摘要和附件：

```sh
xcrun xcresulttool get test-results summary --path "$branding_tmp/matrix-en.xcresult"
xcrun xcresulttool get test-results summary --path "$branding_tmp/matrix-zh.xcresult"
xcrun xcresulttool export attachments \
  --path "$branding_tmp/matrix-en.xcresult" \
  --output-path "$branding_tmp/screenshots-en"
xcrun xcresulttool export attachments \
  --path "$branding_tmp/matrix-zh.xcresult" \
  --output-path "$branding_tmp/screenshots-zh"
```

- [ ] 逐张人工检查六台/语言组合的附件：正确图片、无不合理拉伸/裁切、无重叠、无越界、无约束歧义。特别检查 `value_buoy` 的 cap inset 拉伸、Firmware 大图比例、Profile 图表在 iPhone 与 iPad 的分支、Scene 加号和 Space 锁图标。

- [ ] 如任一真实布局失败，使用 `superpowers:systematic-debugging` 只定位原因；本轮禁止修改生产 Swift 或重编码 PNG。停止并向用户报告需要 UI 方案选择。

- [ ] 用真实测试数、附件数和人工审图结论更新两份文档，然后提交临时分支证据：

```sh
git diff --check
git add Tests/Branding/README.md docs/lumineux-missing-assets.md
git commit -m "test: verify Lumineux new3 UIKit layouts"
```

## Task 6: 正常 DerivedData 真机构建、签名和合并 catalog 验证

**Files:**

- Verify only: `SunSmart.xcworkspace`
- Verify only: generated `Assets-Lumineux-Merged.xcassets`
- Modify after evidence: `Tests/Branding/README.md`
- Modify after evidence: `docs/lumineux-missing-assets.md`

- [ ] 在正常 Library 路径创建独立 DerivedData，不清理用户日常缓存：

```sh
derived_dir="$(mktemp -d /Users/sr/Library/Developer/Xcode/DerivedData3/LumineuxNew3.XXXXXX)"
```

- [ ] 不更新依赖地构建 Lumineux generic iOS Debug；如已有 `LUMINEUX_SOURCE_PACKAGES_DIR` 则继续复用，不改 Package.resolved：

```sh
cd /private/tmp/sun-smart-lumineux-new3-worktree
xcodebuild \
  -workspace SunSmart.xcworkspace \
  -scheme Lumineux -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_dir" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  build
```

- [ ] 找到生成的 `Lumineux.app` 并验证签名、Bundle ID、Team：

```sh
find "$derived_dir/Build/Products" -type d -name Lumineux.app -print
codesign --verify --deep --strict \
  "$derived_dir/Build/Products/Debug-iphoneos/Lumineux.app"
codesign -dvv \
  "$derived_dir/Build/Products/Debug-iphoneos/Lumineux.app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$derived_dir/Build/Products/Debug-iphoneos/Lumineux.app/Info.plist"
```

预期 Bundle ID 为 `com.azoula.sunsmart.Lumineux`，Team 仍为 `JTD3WYUC58`；若本机签名身份发生合法变化，只报告实际值，不擅自修改工程签名设置。

- [ ] 在 `Build/Intermediates.noindex` 中找到 `LumineuxAssets/Assets-Lumineux-Merged.xcassets`，用现有 validator/合并测试确认：总计 695 组，121 组与 Lumineux 源 catalog 同名同文件，其余 574 组与 Common 保持一致。确认构建日志没有 duplicate asset 或 actool 错误。

- [ ] 再次确认依赖锁和工程文件无 diff，且未安装或启动 App：

```sh
git diff --exit-code -- SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved
git diff --exit-code -- SunSmart.xcodeproj/project.pbxproj
```

- [ ] 把实际构建、签名和 695/121/574 结果写入文档，并提交临时分支：

```sh
git diff --check
git add Tests/Branding/README.md docs/lumineux-missing-assets.md
git commit -m "docs: record Lumineux new3 build verification"
```

## Task 7: 代码审查并安全回填用户主工作目录

**Files:**

- Review: all changes after `aa5eb8c258ba44dec84e9d090886fcbd5350b8b5`
- Apply to: `/Users/sr/Documents/SunSmart/sun-smart`

- [ ] 使用 `superpowers:requesting-code-review` 审查完整临时分支，重点检查：29 个映射是否唯一、PNG 是否逐字节保持、是否遗漏空 1x、是否误入 FireAlarm/排除素材、121/695 数量是否一致、UIKit 是否覆盖真实生产调用点、是否存在生产 Swift 或工程配置变化。

- [ ] 修复审查发现的问题，并重新运行受影响测试；修复在临时分支单独提交。随后按 `superpowers:verification-before-completion` 重跑 Task 4 静态套件、Task 5 focused matrix 的必要部分及 Task 6 构建验证，不能引用旧输出宣称当前 HEAD 通过。

- [ ] 输出临时分支相对设计基线的最终文件列表，确认没有用户并行修改的既有 imageset：

```sh
git -C /private/tmp/sun-smart-lumineux-new3-worktree \
  diff --name-status aa5eb8c258ba44dec84e9d090886fcbd5350b8b5..HEAD
```

- [ ] 回到主目录，重新输出 status 和暂存补丁整体哈希。它必须与 Task 0 记录值相同；若不同，说明用户又有新工作，重新做路径冲突检查，绝不覆盖：

```sh
git -C /Users/sr/Documents/SunSmart/sun-smart status --short
git -C /Users/sr/Documents/SunSmart/sun-smart diff --cached --binary | shasum -a 256
```

- [ ] 检查临时分支任务路径与主目录当前 staged、unstaged、untracked 路径是否相交。任何相交都停止并报告具体文件，由用户决定如何合并。

- [ ] 将临时分支相对基线的 binary patch 导出到精确临时文件，先 dry-run，再应用到主目录工作树；不要使用 cherry-pick，因为它会替用户提交，也不要使用 `git apply --index`，因为它会污染暂存区：

```sh
git -C /private/tmp/sun-smart-lumineux-new3-worktree \
  diff --binary aa5eb8c258ba44dec84e9d090886fcbd5350b8b5..HEAD \
  > /private/tmp/lumineux-new3-assets.patch
git -C /Users/sr/Documents/SunSmart/sun-smart \
  apply --check /private/tmp/lumineux-new3-assets.patch
git -C /Users/sr/Documents/SunSmart/sun-smart \
  apply /private/tmp/lumineux-new3-assets.patch
```

- [ ] 应用后第三次计算主目录暂存补丁整体哈希，必须仍与 Task 0 相同；同时确认 `git diff --cached --name-only` 不含本任务新文件，本任务改动保持 unstaged/untracked。

- [ ] 在“用户并行修改 + 本任务补丁”的主目录组合状态下运行最终静态套件和 `git diff --check`。若用户改动造成失败，只报告组合失败和证据，不修改用户文件来迁就测试。

- [ ] 只有补丁已安全回填、主目录组合验证完成、暂存哈希完全不变后，才移除精确的临时 worktree；临时分支可保留到用户确认结果后再删除，以便回滚：

```sh
git -C /Users/sr/Documents/SunSmart/sun-smart \
  worktree remove /private/tmp/sun-smart-lumineux-new3-worktree
```

最终交付明确说明：主目录原有 staged 修改未被改变；本任务资源/测试/文档为未暂存改动；没有提交、推送、更新依赖、安装 App 或启动 App。

## 素材 Oracle（实施时逐项原样录入测试）

| group/name | 2x 像素 | 3x 像素 | SHA-256 2x | SHA-256 3x |
| --- | --- | --- | --- | --- |
| Common/value_buoy | 100×73 | 150×109 | `314496171ff95b6fdba18fa7ce228f78f389638f59b06cca8242bc58b1d9eaf1` | `0670eec5decc5fb11a70bb13ccb984c9074af4338ef624b4cf113859ac43698c` |
| Firmware/distributor_nodes_highlight | 72×40 | 108×60 | `36f0a38152134589b81472876aba99e72a46fd4390ccacbafb05b5b78a01a788` | `c27ae96c5af3336c8a14664ae8b8f9eef4d4e3a58ff957a05de79d6edde0ecb2` |
| Firmware/updatating_nodes | 72×40 | 108×60 | `36f0a38152134589b81472876aba99e72a46fd4390ccacbafb05b5b78a01a788` | `c27ae96c5af3336c8a14664ae8b8f9eef4d4e3a58ff957a05de79d6edde0ecb2` |
| Firmware/firmware_cloud_version | 192×140 | 288×210 | `4bdce49e99f6fd5a74fc0776c1b2da3333e4dd343c8f48a3896c602ed467168e` | `c6f7940c1165e2cfed2c967f3c94c91622adcde1afe9f9d9ac11be743db9720f` |
| Firmware/initiator | 60×60 | 90×90 | `260a665e7765dab06ddafc1763b8485fa3e56dddc3c6cc5ffd73770985219bad` | `d894559ce0f5e24feb6672a4e729e4638f00604ff2bbf54e726bf93032a046df` |
| Firmware/mesh_distributor_guide_4 | 528×108 | 792×162 | `280c56032b5f062b975718cf4f57b12871fd50794c4c5014bfc9a5d706635d0a` | `363cabc1856db8c3f1192c9475e6c89f1d6699d0ef07e11141379cfb59a31622` |
| Firmware/mesh_upgrade_guide_1 | 344×202 | 516×303 | `fd5c3e9e4cdf000f5bc61f4085c43651d69660227440b27c8af045f9f151d3a8` | `b932710262290615780588d3be155c58d3b740dcc4a6ca17f52a6180772ec863` |
| Firmware/mesh_upgrade_guide_2 | 288×108 | 432×162 | `c7bbadb19562f2d709aad1a37691638a36879fc7d6cc11707aafd1580d28e549` | `d6cce986836e6d5726a68462d291fd63f976de5f19984e9ab1cdcd7ac7610578` |
| Firmware/mesh_upgrade_guide_3 | 288×80 | 432×120 | `7f18fd2220bac8be20088b031ae3659669363028565963b167f6d3023e25c219` | `c15d48f11fd31fc4630fd3d60a7b2cd98d6889ee2e75c3b6c50623cfdfd979fe` |
| Firmware/single_device | 60×60 | 90×90 | `ccca7ac0dea8066400f754481b11e0e7c53263477924897e7aa6db60106eb728` | `14d088745bf4d4a157493541d79aaba9bde22c629056402f8520bdb7bd354174` |
| Profile/adjust_speed_fast | 579×326 | 869×489 | `0e39685c6fd2b3d99055a453f7d3734af984def2c9a54f42614a90b38b1aacbe` | `499d528f56359d316ae16ff05802a2e268a9297ebd787809429335386f856886` |
| Profile/adjust_speed_slow | 579×326 | 869×489 | `fd670c7e645ca1ff95ad083c6191e0c69dc7a75f994323d4f38b8a2118d41234` | `c773db949d8f90f0372c55ed837652b0c9e92eff98c4c5f736cfba950be74335` |
| Profile/daylight_scheme4 | 312×240 | 468×360 | `6428878d086f6353d0732e4fe5f459bad2a786b0ea2d77095f7b5aa70dc72514` | `fdf551c7a9ef15143b8110825dc42ea87f4179c2b26e2f19512f1ccb4a3956b6` |
| Profile/daylight_scheme5 | 312×240 | 468×360 | `70769706125f5ff7a8524ca4d3c140ae33eb2b8dcb3c9456616a297951a6f14b` | `073230fed3604f20c490b9e98e100edddd86b18774a2b67e003bbfbbef50e3cc` |
| Profile/daylight_scheme6 | 312×240 | 468×360 | `6f0c7c6ae38a24e8d73a077aaa0687a66418d41562ab831ebb8459fce4d85e80` | `3b7931dc85a6aae4b5e34ce195e9e5f54c04b0ccc3630a73d7df1970874db936` |
| Profile/daylight_scheme7 | 312×240 | 468×360 | `ad76ea9565e52fd47a44d9de61acb0d3f992259fbe165ac4b81d9a70e1c6e96b` | `96d6cd831010d60f33097487c038c33ac5d838658ceb52a716c21d17395875c6` |
| Profile/daylight_standalone_sensor | 40×40 | 60×60 | `a1da73476f481a01bae01be4c9881519a1ff8dede20580dba9773be4d1b8bf9b` | `66dd69e8099e8a62fb3cafd1c62b6ee51f8b169ef52ee4f36f28971fb3aec06c` |
| Profile/power_state_defined | 132×132 | 198×198 | `7a892dfd8d4b49a1abbd426e53080f4de2b3e7ca974e1f01f8a0f90ced39f74f` | `e72d56445adc7d41382566e77ac9e762db09407e2d1c734ba3b21da8d6fdfadd` |
| Profile/power_state_off | 132×132 | 198×198 | `0fb6fcf32a0e463e921b3c3deac54576f2b0458d2846c8270f9d3af0c623d6e6` | `fd93c0965d3ab105ee6b27af85032098b8f85291f5b0299e1e6a3c570f770223` |
| Profile/power_state_restore | 132×132 | 198×198 | `d98946e4fe4a5dc0ff8252a22329e2621f4408a83afb5608613d89cbdb068e8b` | `6b21cb63c28a6a99217e8288b59abb3345384c06c43fe5788b2708f750e6ce5c` |
| Profile/profile_chart_daylight | 424×467 | 636×701 | `96aea8518a8bf0c586c8a8317478ae768e53495dfabb68c69c191759cfda0f4a` | `7b031dbb30a284fe82695c9e57be557369d362315f21a773dfb1f94126f045db` |
| Profile/profile_chart_manual_control | 424×467 | 636×701 | `de9c4d9f5c0b62cf10d0a770cb87c80df8f2c9ca5ce4d09d1f1b62d99a6fad7f` | `5b0bc11a5a7a4292549419069d795340765a025ad8f53d41130571b2efd56135` |
| Profile/profile_chart_occupancy | 424×467 | 636×701 | `db5f8b765ba235f058d1f0b7568080a18b405f4c90d6c1af4d88bc847a6fef4a` | `10c23ff6b118bc45832a7df28145fad6a708b0d06b8dc3df5894d1ccc9a5a0a8` |
| Profile/profile_person | 40×40 | 60×60 | `ffe253066fbef81ec3820d68be3ea65c6b128b17ad7039e50def8632660ff0b4` | `ad5734adee040d153213b9fca0fa06be25dfdb38a634c68bf89b7cb8d1aa531f` |
| Profile/profile_person_big | 60×60 | 90×90 | `aae99a437ca1b219182ac958b6c0261571010b516dc7217473408ba54dfecd2b` | `cf3afd3eb8cd0a8c4fbb9007138ef2f306b5b624d55e89663c88207df7970b37` |
| Profile/profile_proximity_lighting | 670×408 | 1005×612 | `1010235c5252a4cbd4d7ab1797b97ac84c9a6cc2d72c56d5a4add642d996e0f4` | `5c2902bb4c32252567faa54bb0ff22170a8f262c913e0584c70361c63770372d` |
| Profile/sensor_manul_override_timeout | 656×282 | 984×423 | `cd71eeef261639816d6179d3c1231854b9fefbfc8bfde28b864136051af195e8` | `f0f18f0a78536a74abafa841cc4bce500432e9f5431c63759817a1b735d5545f` |
| Scene/scene_data_add | 48×48 | 72×72 | `9f659569ee5d8d983e00cd836c4ae553fef4eafcd6d865e15555e0efd2dcbe02` | `0ddf3b7c0a17f3926e55aa3cec2d674e9fa25da36f7a87dee3a7082dbc7ffe28` |
| Space/locked | 60×60 | 90×90 | `e3b4ded572f7b005134b4b5f243a8325ed4044962420a145b19acec821216e52` | `8465bd47533051bea362c25973c4490a08496a656c658ec1436e36e7cfccc85f` |
