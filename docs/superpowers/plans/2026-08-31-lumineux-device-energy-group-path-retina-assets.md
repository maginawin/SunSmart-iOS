# Lumineux Device、Energy、Group、Path Retina 资源接入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将用户确认的 11 组 Device、Energy、Group、Path Lumineux Retina PNG 作为同名品牌覆盖接入工程，只保存原始 2x/3x 文件，并让静态契约、真实 UIKit 布局、构建期合并及正式签名构建都验证其正确性。

**Architecture:** 原始用户文件按业务分类、最终资源名存档到 `Lumineux/DesignAssets/Provided`，相同字节复制到 `Lumineux/Assets-Lumineux.xcassets` 的 11 个 grouped imageset；每组 `Contents.json` 保留空 universal 1x 槽位。现有 `Merge Lumineux Assets` 构建阶段继续按同名完整 asset set 覆盖公共 catalog，不修改生产 Swift、合并器或其他 target。

**Tech Stack:** Swift、UIKit、Xcode asset catalogs、XCTest、Ruby、shell

## Global Constraints

- 仅接入 `switch_proxy_instructions_1`、`switch_proxy_instructions_2`、`energy_device`、`energy_csv`、`energy_phone`、`switch_press`、`switch_press_long`、`switch_save`、`path_direction_left`、`path_direction_right`、`path_item_add`。
- 明确不接入 `/Users/sr/Documents/SunSmart/assets/new2/icon/路径@2x.png` 与 `路径@3x.png`，也不创建 `path_add`。
- 本轮不接入 `energy_light`、`auto_big`、`member_add`、`switch_save_un`。
- 所有源 PNG 必须逐字节保存；不缩放、不改色、不改透明度、不重编码，也不修改 PNG 元数据。
- 每个新 imageset 恰有 universal 1x/2x/3x 三个槽位；1x 条目不得包含 `filename`，磁盘上不得生成 `@1x.png`。
- 不修改 `SunSmart/` 生产 Swift、公共/SLGSync catalog、`Lumineux/Scripts/merge_assets.rb`、资源生成器、Xcode 工程配置或 NordicSigMeshSDK。
- 保留工作区中现有 Common Retina、Europe 及其他用户改动；不得清理、覆盖、暂存或提交这些改动。
- 本轮实施文件保持未提交；只有用户后续明确要求时才提交。
- UI 验收必须运行真实 UIKit 页面/组件、检查约束与父视图包含关系，并人工查看截图；编译通过不能替代布局验收。
- 正式验证只构建 Lumineux 真机 Debug，不安装、不启动真机 App，不更新 Swift Package 或 CocoaPods 依赖。

## File Map

- `Tests/Branding/LumineuxAssetTests.swift`：固定 92 组品牌 catalog、11 组业务目录、22 个源文件 SHA-256、像素尺寸、空 1x 槽位及 catalog/source 字节一致性。
- `Tests/Branding/LumineuxRuntimeTests.swift`：从独立 reference catalog 逐像素验证图片来源，并装载真实 Device、Energy、Group、Path 页面/组件检查布局与截图。
- `scripts/make_lumineux_test_workspace.rb`：临时 XCTest reference catalog 完整组数从 81 更新为 92。
- `Lumineux/DesignAssets/asset-groups.json`：注册 11 个最终资源名与业务分类。
- `Lumineux/DesignAssets/Provided/{Device,Energy,Group,Path}`：保存用户提供且改为最终资源名的 22 个原始 PNG。
- `Lumineux/Assets-Lumineux.xcassets/{Device,Energy,Group,Path}`：保存 11 个只填 2x/3x 的 grouped imageset。
- `docs/lumineux-missing-assets.md`：更新已覆盖、待提供数量及明确排除项。
- `Tests/Branding/README.md`：记录 92 组 reference catalog、87 组已提供资源、UIKit 矩阵与构建验收结果。

---

### Task 1: 建立静态素材 RED 契约

**Files:**
- Modify: `Tests/Branding/LumineuxAssetTests.swift`

**Interfaces:**
- Consumes: 现有 `expectedAssetGroups`、`assetSetURL(named:)`、`contents(named:)`、`image(named:filename:)`、`providedDirectory` 与 `check`。
- Produces: `providedGroupedAssets` 静态 oracle，覆盖 11 个名字、4 个业务目录、22 个源文件哈希与精确像素尺寸。

- [ ] **Step 1: 将 11 个名字加入静态分组契约并锁定总数 92**

在 `expectedAssetGroups` 中按资源名排序加入以下准确映射：

```swift
"energy_csv": "Energy",
"energy_device": "Energy",
"energy_phone": "Energy",
"path_direction_left": "Path",
"path_direction_right": "Path",
"path_item_add": "Path",
"switch_press": "Group",
"switch_press_long": "Group",
"switch_proxy_instructions_1": "Device",
"switch_proxy_instructions_2": "Device",
"switch_save": "Group",
```

同时做两处精确计数更新：

```swift
check(groupManifest.assets == expectedAssetGroups,
      "Lumineux asset group manifest differs from the approved 92-resource mapping")

check(discovered.count == 92, "Lumineux catalog must contain exactly 92 asset names")
```

- [ ] **Step 2: 加入 11 组源文件的精确哈希与像素尺寸**

紧接现有 `providedCommonAssets` 检查之后加入以下类型和完整数据；方向箭头使用精确像素尺寸，而不是把 31px/47px 强行折算成相同整数 pt：

```swift
struct ProvidedGroupedAsset {
    let group: String
    let name: String
    let pixels: [Int: (width: Int, height: Int)]
    let hashes: [Int: String]
}

let providedGroupedAssets: [ProvidedGroupedAsset] = [
    .init(group: "Device", name: "switch_proxy_instructions_1", pixels: [
        2: (620, 656), 3: (930, 984)
    ], hashes: [
        2: "4ee9aac82760cb73c59d3603e4a3131a48847cf2909de4de87b44caff3369a7b",
        3: "08a1667ed117e6208be89c4001e19edd509bcf09c68f3063e640d6a16a31462b"
    ]),
    .init(group: "Device", name: "switch_proxy_instructions_2", pixels: [
        2: (574, 624), 3: (861, 936)
    ], hashes: [
        2: "0007d325a3167bef8d7b2feea361487ba388066eb14f401bea017e7cca4302a8",
        3: "c66671007ea1611dbd17d31d1537387cf3e1987f0cc606f5980806f8f718bf90"
    ]),
    .init(group: "Energy", name: "energy_device", pixels: [
        2: (40, 40), 3: (60, 60)
    ], hashes: [
        2: "ab8fc4aa61032e4354b143b6902f69e9baa78d36b86bc62edf4c4c35388953a3",
        3: "47b67bbccee798e86fab035f185a6c8c0412460559def2b12a905d6c20297f68"
    ]),
    .init(group: "Energy", name: "energy_csv", pixels: [
        2: (40, 40), 3: (60, 60)
    ], hashes: [
        2: "25869578488f78ef74bb79ce53f87db86ff1130e63f1b5fc89469975ede6c56e",
        3: "fefa6ba82e6b3ccd53e5605448676ff8da897497a08f08794c6833900ab6af4a"
    ]),
    .init(group: "Energy", name: "energy_phone", pixels: [
        2: (40, 40), 3: (60, 60)
    ], hashes: [
        2: "e2141c49d0815ae3b8cd84c0e575bffdf9afab90df0e28ff72949d42fc8fa90c",
        3: "53b02514e7d4d146bc25f69c2cdc33e3eb852f025b6fa94898ed80a8666d1e2f"
    ]),
    .init(group: "Group", name: "switch_press", pixels: [
        2: (60, 60), 3: (90, 90)
    ], hashes: [
        2: "71cae800452a091d06494af4c192f6ad3c2c19d01e705a95de801c98e0fc2c4d",
        3: "04456b561da19a53092c0772eea760fd0c0049c1d0407ff9f1e635d9e7da00ee"
    ]),
    .init(group: "Group", name: "switch_press_long", pixels: [
        2: (60, 60), 3: (90, 90)
    ], hashes: [
        2: "fa75a3ef9ad252d2c0afea24c4029bb7b5f05a582e380ae88a63d4e2bca547a5",
        3: "dd5a9f72ce69b4126b95c955c4dc1cc1bbc72eaa836b7a5ad672a093eb8acc86"
    ]),
    .init(group: "Group", name: "switch_save", pixels: [
        2: (80, 80), 3: (120, 120)
    ], hashes: [
        2: "fcd2afa2fef32f35f07882754d8d6a04a659796ab2d793d177389e79704b5cd9",
        3: "e7260fed14aac7e10b7d685bcab9c75b827f26a80cd8f472ddd27b064da33c00"
    ]),
    .init(group: "Path", name: "path_direction_left", pixels: [
        2: (31, 12), 3: (47, 18)
    ], hashes: [
        2: "10bc5d45a0d8c8047660c46972aeeaf66078d8a00f01a191c1f64b5ddc44fb47",
        3: "b93eac894add60b74f0f34798af4bc2380b6610dff3ddd5e13ad7c42b0aa01c8"
    ]),
    .init(group: "Path", name: "path_direction_right", pixels: [
        2: (31, 12), 3: (47, 18)
    ], hashes: [
        2: "2db9d4d9abf8ab8eaabf76d19e7f29150e1af1f0384198e1f8a4e4c48a4c92ef",
        3: "3ac355dbb4898ada7129e2cebce6e49511408083e5a8c9d8a655e60e81a317ee"
    ]),
    .init(group: "Path", name: "path_item_add", pixels: [
        2: (18, 18), 3: (27, 27)
    ], hashes: [
        2: "1f9c61bb7e67e47f14b0ddb4b9b1bdb010ce4fab4536db4dade4d1b648314ed9",
        3: "30a80c61759e1c18fc1c2562e5d555bd9360fd8615935e8498e6ce3d9c9b9fe5"
    ])
]
```

- [ ] **Step 3: 对每组执行目录、倍率、哈希、字节和尺寸断言**

加入以下完整循环：

```swift
check(providedGroupedAssets.count == 11,
      "Expected exactly 11 supplied Device/Energy/Group/Path assets")
for asset in providedGroupedAssets {
    check(expectedAssetGroups[asset.name] == asset.group,
          "Wrong business group for supplied asset: \(asset.name)")
    let entries = try contents(named: asset.name)["images"] as! [[String: String]]
    check(entries.count == 3,
          "Expected empty 1x plus supplied 2x/3x for \(asset.name)")
    check(entries.first { $0["scale"] == "1x" }?["filename"] == nil,
          "\(asset.name) must not generate a 1x file")
    let sourceDirectory = providedDirectory.appendingPathComponent(asset.group)
    for scale in 2...3 {
        let filename = "\(asset.name)@\(scale)x.png"
        let source = sourceDirectory.appendingPathComponent(filename)
        check(FileManager.default.fileExists(atPath: source.path),
              "Missing supplied \(asset.group) source artwork: \(filename)")
        let sourceData = try Data(contentsOf: source)
        let digest = SHA256.hash(data: sourceData)
            .map { String(format: "%02x", $0) }.joined()
        check(digest == asset.hashes[scale],
              "Supplied \(asset.name) @\(scale)x bytes changed")
        let catalogFilename = entries.first { $0["scale"] == "\(scale)x" }?["filename"]
        check(catalogFilename == filename,
              "Unexpected catalog filename for \(asset.name) @\(scale)x")
        let catalogData = try Data(contentsOf:
            assetSetURL(named: asset.name).appendingPathComponent(catalogFilename!))
        check(catalogData == sourceData,
              "Catalog must preserve \(asset.name) @\(scale)x bytes")
        let rendered = try image(named: asset.name, filename: catalogFilename!)
        let expected = asset.pixels[scale]!
        check(rendered.width == expected.width && rendered.height == expected.height,
              "Incorrect pixel canvas for \(asset.name) @\(scale)x")
    }
    let unexpectedOneX = assetSetURL(named: asset.name)
        .appendingPathComponent("\(asset.name)@1x.png")
    check(!FileManager.default.fileExists(atPath: unexpectedOneX.path),
          "\(asset.name) must not contain a generated 1x PNG")
}
```

- [ ] **Step 4: 运行静态测试并确认 RED 原因正确**

Run:

```sh
mkdir -p /private/tmp/lumineux-grouped-swift-module-cache
CLANG_MODULE_CACHE_PATH=/private/tmp/lumineux-grouped-swift-module-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/lumineux-grouped-swift-module-cache \
swift Tests/Branding/LumineuxAssetTests.swift
```

Expected: 进程非 0，并因 92-resource manifest/catalog 尚不存在或首个新 source/imageset 缺失而失败；不得是 Swift 编译、模块缓存或哈希数据语法错误。

---

### Task 2: 建立真实 UIKit RED 契约

**Files:**
- Modify: `Tests/Branding/LumineuxRuntimeTests.swift`

**Interfaces:**
- Consumes: 现有 `show(_:)`、`host(_:size:)`、`descendants(_:)`、`image(_:matchesNamed:)`、`assertResolvedImageMatchesLumineuxSource` 与 `snapshot` helpers，以及生产类型 `SwitchProxyInstructionsViewController`、`EnergyTimeSeriesDataImportView`、`EnergyTimeSeriesDataExportView`、`GroupSwitchPanelViewCell`、`GroupPathSequencePathViewCell`。
- Produces: `testProvidedGroupedRetinaAssetsFitProductionControls()`，每次运行保留 5 张页面/组件截图。

- [ ] **Step 1: 增加统一的父视图包含关系断言 helper**

在 `host(_:size:)` helper 后加入：

```swift
private func assertContained(_ child: UIView, in parent: UIView,
                             file: StaticString = #filePath, line: UInt = #line) {
    let frame = child.convert(child.bounds, to: parent)
    XCTAssertTrue(parent.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                  "View is outside its production container: \(frame)",
                  file: file, line: line)
    XCTAssertFalse(child.hasAmbiguousLayout, file: file, line: line)
}
```

- [ ] **Step 2: 增加 Device、Energy、Group、Path 的完整真实组件测试**

在 `testProvidedCommonRetinaAssetsFitProductionControls()` 后加入以下测试。它先对 11 个名字做独立 reference catalog 来源验证，再检查真实调用点；不创建站点、不写业务数据、不操作 Mesh：

```swift
func testProvidedGroupedRetinaAssetsFitProductionControls() throws {
    let expectedGeometry: [(String, CGSize)] = [
        ("switch_proxy_instructions_1", CGSize(width: 310, height: 328)),
        ("switch_proxy_instructions_2", CGSize(width: 287, height: 312)),
        ("energy_device", CGSize(width: 20, height: 20)),
        ("energy_csv", CGSize(width: 20, height: 20)),
        ("energy_phone", CGSize(width: 20, height: 20)),
        ("switch_press", CGSize(width: 30, height: 30)),
        ("switch_press_long", CGSize(width: 30, height: 30)),
        ("switch_save", CGSize(width: 40, height: 40)),
        ("path_item_add", CGSize(width: 9, height: 9))
    ]
    for (name, size) in expectedGeometry {
        try assertNamedImage(name, size: size)
        try assertResolvedImageMatchesLumineuxSource(UIImage(named: name), name: name)
    }
    for name in ["path_direction_left", "path_direction_right"] {
        let direction = try XCTUnwrap(UIImage(named: name))
        XCTAssertEqual(direction.size.height, 6, accuracy: 0.01, name)
        XCTAssertGreaterThan(direction.size.width, 15, name)
        XCTAssertLessThan(direction.size.width, 16, name)
        try assertResolvedImageMatchesLumineuxSource(direction, name: name)
    }

    let instructions = SwitchProxyInstructionsViewController()
    show(NavigationViewController(rootViewController: instructions))
    let guides = descendants(instructions.view)
        .compactMap { $0 as? SwitchProxyInstructionsGuideView }
    XCTAssertEqual(guides.count, 2)
    for name in ["switch_proxy_instructions_1", "switch_proxy_instructions_2"] {
        let guide = try XCTUnwrap(guides.first {
            image($0.imageView.image, matchesNamed: name)
        })
        try assertResolvedImageMatchesLumineuxSource(guide.imageView.image, name: name)
        assertContained(guide.imageView, in: guide)
    }
    snapshot(window, "Provided-grouped-device-instructions")

    let importView = EnergyTimeSeriesDataImportView(frame: .zero)
    _ = host(importView, size: CGSize(width: 343, height: 190))
    for name in ["energy_device", "energy_csv", "energy_phone"] {
        let imageView = try XCTUnwrap(descendants(importView)
            .compactMap { $0 as? UIImageView }
            .first { image($0.image, matchesNamed: name) })
        try assertResolvedImageMatchesLumineuxSource(imageView.image, name: name)
        assertContained(imageView, in: importView)
    }
    snapshot(window, "Provided-grouped-energy-import")

    let exportView = EnergyTimeSeriesDataExportView(frame: .zero)
    _ = host(exportView, size: CGSize(width: 343, height: 330))
    for name in ["energy_phone", "energy_csv"] {
        let imageView = try XCTUnwrap(descendants(exportView)
            .compactMap { $0 as? UIImageView }
            .first { image($0.image, matchesNamed: name) })
        try assertResolvedImageMatchesLumineuxSource(imageView.image, name: name)
        assertContained(imageView, in: exportView)
    }
    snapshot(window, "Provided-grouped-energy-export")

    let switchCell = GroupSwitchPanelViewCell(style: .default, reuseIdentifier: nil)
    _ = host(switchCell, size: CGSize(width: 343, height: 520))
    for (button, name) in [
        (switchCell.key1ShortPressBtn!, "switch_press"),
        (switchCell.key1LongPressBtn!, "switch_press_long"),
        (switchCell.saveBtn!, "switch_save")
    ] {
        try assertResolvedImageMatchesLumineuxSource(button.image(for: .normal), name: name)
        assertContained(button, in: switchCell.contentView)
    }
    snapshot(window, "Provided-grouped-switch-panel")

    let path = GroupProximityLightingSequencePath(
        items: GroupProximityLightingSequencePath.GroupProximityLightingPathItem.default(count: 1)
    )
    let pathCell = GroupPathSequencePathViewCell(style: .default, reuseIdentifier: nil)
    _ = host(pathCell, size: CGSize(width: 343, height: 116))
    pathCell.reloadData(pathIndex: 0, path: path)
    let selected = GroupPathSequenceSelectData()
    selected.path = path
    selected.item = path.items[0]
    selected.direction = .right
    pathCell.selectPathData = selected
    pathCell.layoutIfNeeded()
    let collection = try XCTUnwrap(descendants(pathCell)
        .compactMap { $0 as? UICollectionView }.first)
    collection.layoutIfNeeded()
    let addItem = try XCTUnwrap(
        collection.cellForItem(at: IndexPath(item: 0, section: 0))
            as? GroupPathSequencePathAddItem
    )
    try assertResolvedImageMatchesLumineuxSource(addItem.addImageView.image,
                                                 name: "path_item_add")
    assertContained(addItem.addImageView, in: addItem.boxView)
    var pathItem = try XCTUnwrap(
        collection.cellForItem(at: IndexPath(item: 1, section: 0))
            as? GroupPathSequencePathItem
    )
    try assertResolvedImageMatchesLumineuxSource(pathItem.arrowImageView.image,
                                                 name: "path_direction_right")
    assertContained(pathItem.arrowImageView, in: pathItem.boxView)
    selected.direction = .left
    pathCell.selectPathData = selected
    collection.layoutIfNeeded()
    pathItem = try XCTUnwrap(
        collection.cellForItem(at: IndexPath(item: 1, section: 0))
            as? GroupPathSequencePathItem
    )
    try assertResolvedImageMatchesLumineuxSource(pathItem.arrowImageView.image,
                                                 name: "path_direction_left")
    assertContained(pathItem.arrowImageView, in: pathItem.boxView)
    snapshot(window, "Provided-grouped-path")
}
```

- [ ] **Step 3: 生成 81 组 reference catalog 的临时 workspace 并确认 UIKit RED**

此时先不要改 `scripts/make_lumineux_test_workspace.rb` 的 81。执行：

```sh
grouped_red_root="$(mktemp -d /private/tmp/lumineux-grouped-red.XXXXXX)"
ruby scripts/make_lumineux_test_workspace.rb "$grouped_red_root/runtime"
xcodebuild \
  -workspace "$grouped_red_root/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -derivedDataPath "$grouped_red_root/DerivedData" \
  -clonedSourcePackagesDirPath /Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath "$grouped_red_root/red.xcresult" \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedGroupedRetinaAssetsFitProductionControls \
  -testLanguage en -testRegion US -parallel-testing-enabled NO -jobs 4 \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: 测试 bundle 可以编译，测试因独立 Lumineux reference catalog 找不到 `switch_proxy_instructions_1`（或列表中的另一项）而失败；不得以编译错误、模拟器不可用或生产页面初始化崩溃代替预期 RED。

---

### Task 3: 最小接入 11 组 2x/3x 资源并转为 GREEN

**Files:**
- Create: `Lumineux/DesignAssets/Provided/Device/{switch_proxy_instructions_1,switch_proxy_instructions_2}@{2,3}x.png`
- Create: `Lumineux/DesignAssets/Provided/Energy/{energy_device,energy_csv,energy_phone}@{2,3}x.png`
- Create: `Lumineux/DesignAssets/Provided/Group/{switch_press,switch_press_long,switch_save}@{2,3}x.png`
- Create: `Lumineux/DesignAssets/Provided/Path/{path_direction_left,path_direction_right,path_item_add}@{2,3}x.png`
- Create: matching 11 imageset directories and 22 catalog PNGs under `Lumineux/Assets-Lumineux.xcassets/{Device,Energy,Group,Path}`
- Create: matching 11 `Contents.json` files
- Modify: `Lumineux/DesignAssets/asset-groups.json`
- Modify: `scripts/make_lumineux_test_workspace.rb`

**Interfaces:**
- Consumes: Task 1 的 `providedGroupedAssets` hashes/pixel sizes 与 Task 2 的独立 reference oracle。
- Produces: 92 组 Lumineux 原始 catalog（90 imageset + AppIcon + AccentColor）；其中新增 11 组按同名覆盖公共资源，合并总数仍为 695。

- [ ] **Step 1: 原样复制并按最终资源名存档 22 个 PNG**

使用以下准确脚本；函数只执行目录创建与 `cp`，不会处理图片内容：

```sh
copy_grouped_retina_pair() {
  grouped_source_base="$1"
  grouped_category="$2"
  grouped_asset_name="$3"
  grouped_provided="Lumineux/DesignAssets/Provided/$grouped_category"
  grouped_imageset="Lumineux/Assets-Lumineux.xcassets/$grouped_category/$grouped_asset_name.imageset"
  mkdir -p "$grouped_provided" "$grouped_imageset"
  cp "${grouped_source_base}@2x.png" "$grouped_provided/${grouped_asset_name}@2x.png"
  cp "${grouped_source_base}@3x.png" "$grouped_provided/${grouped_asset_name}@3x.png"
  cp "$grouped_provided/${grouped_asset_name}@2x.png" "$grouped_imageset/${grouped_asset_name}@2x.png"
  cp "$grouped_provided/${grouped_asset_name}@3x.png" "$grouped_imageset/${grouped_asset_name}@3x.png"
}

copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/Frame 133' Device switch_proxy_instructions_1
copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/Frame 132' Device switch_proxy_instructions_2
copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/images/Hard-Drive20' Energy energy_device
copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/images/csv' Energy energy_csv
copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/images/phone20' Energy energy_phone
copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/images/press' Group switch_press
copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/images/press_long' Group switch_press_long
copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/images/save' Group switch_save
copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/箭头左' Path path_direction_left
copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/箭头右' Path path_direction_right
copy_grouped_retina_pair '/Users/sr/Documents/SunSmart/assets/new2/images/add' Path path_item_add
```

执行后确认 `Lumineux/DesignAssets/Provided` 与 catalog 内对应文件逐字节相同；不要调用图片转换工具，也不要复制 `new2/icon/路径`。

- [ ] **Step 2: 使用 `apply_patch` 创建 11 个空 1x 的 Contents.json**

每个文件使用以下准确内容；文件名必须与 imageset 名一致：

```diff
*** Begin Patch
*** Add File: Lumineux/Assets-Lumineux.xcassets/Device/switch_proxy_instructions_1.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "switch_proxy_instructions_1@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "switch_proxy_instructions_1@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** Add File: Lumineux/Assets-Lumineux.xcassets/Device/switch_proxy_instructions_2.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "switch_proxy_instructions_2@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "switch_proxy_instructions_2@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** Add File: Lumineux/Assets-Lumineux.xcassets/Energy/energy_device.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "energy_device@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "energy_device@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** Add File: Lumineux/Assets-Lumineux.xcassets/Energy/energy_csv.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "energy_csv@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "energy_csv@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** Add File: Lumineux/Assets-Lumineux.xcassets/Energy/energy_phone.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "energy_phone@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "energy_phone@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** Add File: Lumineux/Assets-Lumineux.xcassets/Group/switch_press.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "switch_press@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "switch_press@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** Add File: Lumineux/Assets-Lumineux.xcassets/Group/switch_press_long.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "switch_press_long@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "switch_press_long@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** Add File: Lumineux/Assets-Lumineux.xcassets/Group/switch_save.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "switch_save@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "switch_save@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** Add File: Lumineux/Assets-Lumineux.xcassets/Path/path_direction_left.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "path_direction_left@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "path_direction_left@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** Add File: Lumineux/Assets-Lumineux.xcassets/Path/path_direction_right.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "path_direction_right@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "path_direction_right@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** Add File: Lumineux/Assets-Lumineux.xcassets/Path/path_item_add.imageset/Contents.json
+{
+  "images" : [
+    { "idiom" : "universal", "scale" : "1x" },
+    { "filename" : "path_item_add@2x.png", "idiom" : "universal", "scale" : "2x" },
+    { "filename" : "path_item_add@3x.png", "idiom" : "universal", "scale" : "3x" }
+  ],
+  "info" : { "author" : "xcode", "version" : 1 }
+}
*** End Patch
```

- [ ] **Step 3: 注册 11 个业务分组并更新 reference catalog 计数**

在 `Lumineux/DesignAssets/asset-groups.json` 的 `assets` 对象中加入 Task 1 的 11 个准确键值，保持现有键和 `groups` 顺序不变。

在 `scripts/make_lumineux_test_workspace.rb` 只改这一行：

```ruby
abort("Expected 92 complete Lumineux catalog sets for reference catalog; found #{brand_sets.length}") unless brand_sets.length == 92
```

- [ ] **Step 4: 运行静态、分组、生成器、合并器与配置 GREEN**

Run:

```sh
mkdir -p /private/tmp/lumineux-grouped-swift-module-cache
CLANG_MODULE_CACHE_PATH=/private/tmp/lumineux-grouped-swift-module-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/lumineux-grouped-swift-module-cache \
swift Tests/Branding/LumineuxAssetTests.swift
ruby scripts/validate_lumineux_asset_groups.rb \
  Lumineux/Assets-Lumineux.xcassets \
  Lumineux/DesignAssets/asset-groups.json
ruby Tests/Branding/LumineuxGeneratorTests.rb
ruby Tests/Branding/LumineuxMergeTests.rb
ruby Tests/Branding/LumineuxConfigurationTests.rb
ruby -c scripts/make_lumineux_test_workspace.rb
```

Expected: 所有命令退出 0；Lumineux 原始 catalog 为 92 组，其中 90 个 imageset、1 个 AppIcon、1 个 AccentColor；合并 catalog 仍为 695 组，11 个新增名字均覆盖而不是增加合并总数。

- [ ] **Step 5: 重建临时 workspace 并确认 focused UIKit GREEN**

Run:

```sh
grouped_green_root="$(mktemp -d /private/tmp/lumineux-grouped-green.XXXXXX)"
ruby scripts/make_lumineux_test_workspace.rb "$grouped_green_root/runtime"
xcodebuild \
  -workspace "$grouped_green_root/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -derivedDataPath "$grouped_green_root/DerivedData" \
  -clonedSourcePackagesDirPath /Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath "$grouped_green_root/green.xcresult" \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedGroupedRetinaAssetsFitProductionControls \
  -testLanguage en -testRegion US -parallel-testing-enabled NO -jobs 4 \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: focused test 通过并保留 5 张附件；11 个 App bundle 图片均与独立 reference catalog 逐像素一致，无约束歧义、裁切或父视图越界断言。

- [ ] **Step 6: 做实施范围检查且不提交**

Run:

```sh
git status --short
git diff --check
git diff -- Lumineux/DesignAssets/asset-groups.json \
  Tests/Branding/LumineuxAssetTests.swift \
  Tests/Branding/LumineuxRuntimeTests.swift \
  scripts/make_lumineux_test_workspace.rb
find Lumineux/DesignAssets/Provided/Device \
  Lumineux/DesignAssets/Provided/Energy \
  Lumineux/DesignAssets/Provided/Group \
  Lumineux/DesignAssets/Provided/Path -type f -print | sort
```

Expected: 新增文件严格为 22 个 Provided PNG、22 个 catalog PNG、11 个 Contents.json；`new2/icon/路径`、`path_add`、4 个未提供资源及任何 `@1x.png` 均不存在。不要 `git add` 或 `git commit`。

---

### Task 4: 更新清单和可复现验证说明

**Files:**
- Modify: `docs/lumineux-missing-assets.md`
- Modify: `Tests/Branding/README.md`

**Interfaces:**
- Consumes: 已通过的 92 组静态/运行时结果。
- Produces: 与仓库当前资源状态一致的数量、来源、排除项和验收记录。

- [ ] **Step 1: 在缺失清单增加本轮 11 组来源表**

在 Common Retina 小节之后增加 `2026-08-31 Device、Energy、Group、Path Retina PNG 补充`，逐项记录：

```text
Frame 133              -> Device/switch_proxy_instructions_1 -> 310 × 328pt -> 2x / 3x
Frame 132              -> Device/switch_proxy_instructions_2 -> 287 × 312pt -> 2x / 3x
images/Hard-Drive20    -> Energy/energy_device                -> 20 × 20pt   -> 2x / 3x
images/csv             -> Energy/energy_csv                   -> 20 × 20pt   -> 2x / 3x
images/phone20         -> Energy/energy_phone                 -> 20 × 20pt   -> 2x / 3x
images/press           -> Group/switch_press                  -> 30 × 30pt   -> 2x / 3x
images/press_long      -> Group/switch_press_long             -> 30 × 30pt   -> 2x / 3x
images/save            -> Group/switch_save                   -> 40 × 40pt   -> 2x / 3x
箭头左                  -> Path/path_direction_left            -> 31 × 12px / 47 × 18px -> 2x / 3x
箭头右                  -> Path/path_direction_right           -> 31 × 12px / 47 × 18px -> 2x / 3x
images/add             -> Path/path_item_add                  -> 9 × 9pt     -> 2x / 3x
```

同一小节明确写明 `new2/icon/路径` 暂不处理，且没有接入 `energy_light`、`auto_big`、`member_add`、`switch_save_un`。

- [ ] **Step 2: 精确更新缺失清单数量和名字**

把统计更新为：

```text
SLGSync 94 组范围内已覆盖：54
SLGSync 94 组范围内待提供：40
额外已打包：33
已提供资源总数：87

Common: 1
Device: 0
Energy: 1
Firmware: 10
Group: 3
Path: 0
Profile: 23
Scene: 1
Site: 0
Space: 1
Timed: 0
合计: 40
```

从待提供明细中删除本轮 11 个名字；保留：

```text
Energy: energy_light
Group: auto_big, member_add, switch_save_un
```

其他分类和名字完全不变。

- [ ] **Step 3: 更新 Branding README 的 catalog 与来源契约**

把 README 中当前状态改为：

```text
Lumineux 原始 catalog：90 imageset + AppIcon + AccentColor = 92 组
临时 XCTest reference catalog：92 组
已提供资源：87 组
新增 grouped Retina：11 组、22 个原始 PNG、全部空 1x
合并 catalog：695 组，其中 92 组匹配 Lumineux，603 组保留公共资源
待提供：40 组；Common 仍只有 value_buoy
```

增加真实调用点说明：Device 代理说明页、Energy 导入/导出组件、Group 开关面板、Path 路径 item；不要宣称未运行的测试、未审阅的截图或未完成的构建已经通过。

- [ ] **Step 4: 文档检查**

Run:

```sh
grep -n "92 组\|90 个 imageset\|87 组\|40 组\|value_buoy\|new2/icon/路径" \
  docs/lumineux-missing-assets.md Tests/Branding/README.md
git diff --check
```

Expected: 新数字均可定位；旧的当前状态 `81 组`、`79 个 imageset`、`76`、`51 组` 不再作为最新结论出现，但历史验证段落中的旧阶段数字保留原样。

---

### Task 5: 完整 UIKit 矩阵、静态回归、正式构建与最终审计

**Files:**
- Verify only: all files listed above

**Interfaces:**
- Consumes: 92 组 Lumineux catalog、focused GREEN 和更新后的文档。
- Produces: 六个本地化/设备组合的结果包、30 张本轮截图、正常 DerivedData3 真机构建与签名/合并产物证据。

- [ ] **Step 1: 生成最终临时 workspace 并 build-for-testing**

Run:

```sh
grouped_matrix_root="$(mktemp -d /private/tmp/lumineux-grouped-matrix.XXXXXX)"
ruby scripts/make_lumineux_test_workspace.rb "$grouped_matrix_root/runtime"
xcodebuild \
  -workspace "$grouped_matrix_root/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -derivedDataPath "$grouped_matrix_root/DerivedData" \
  -clonedSourcePackagesDirPath /Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -parallel-testing-enabled NO -jobs 4 \
  build-for-testing CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: `BUILD FOR TESTING SUCCEEDED`，不更新依赖。

- [ ] **Step 2: 在三设备、英文和简体中文共六个组合运行 focused test**

Run:

```sh
for grouped_case in \
  'se3-en|9FCF83EB-38F9-4B61-A35E-D88F8665A1B5|en|US' \
  'iphone16-en|5E6F7D5C-CC01-4760-8D6E-2489835F1748|en|US' \
  'ipad-en|1B4321CD-F455-4252-8504-105435A02C9A|en|US' \
  'se3-zh|9FCF83EB-38F9-4B61-A35E-D88F8665A1B5|zh-Hans|CN' \
  'iphone16-zh|5E6F7D5C-CC01-4760-8D6E-2489835F1748|zh-Hans|CN' \
  'ipad-zh|1B4321CD-F455-4252-8504-105435A02C9A|zh-Hans|CN'
do
  IFS='|' read -r grouped_label grouped_device grouped_language grouped_region <<< "$grouped_case"
  xcodebuild \
    -workspace "$grouped_matrix_root/runtime/LumineuxBranding.xcworkspace" \
    -scheme LumineuxBranding -configuration Debug \
    -destination "platform=iOS Simulator,id=$grouped_device,arch=x86_64" \
    -derivedDataPath "$grouped_matrix_root/DerivedData" \
    -clonedSourcePackagesDirPath /Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages \
    -disableAutomaticPackageResolution -skipPackageUpdates \
    -resultBundlePath "$grouped_matrix_root/$grouped_label.xcresult" \
    -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedGroupedRetinaAssetsFitProductionControls \
    -testLanguage "$grouped_language" -testRegion "$grouped_region" \
    -parallel-testing-enabled NO -jobs 4 \
    test-without-building CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
done
```

Expected: 六次运行均 1 test、0 failure、0 skip；每次 5 张附件，合计 30 张。

- [ ] **Step 3: 导出并人工审阅 30 张截图**

Run:

```sh
for grouped_label in se3-en iphone16-en ipad-en se3-zh iphone16-zh ipad-zh
do
  xcrun xcresulttool get test-results summary \
    --path "$grouped_matrix_root/$grouped_label.xcresult"
  xcrun xcresulttool export attachments \
    --path "$grouped_matrix_root/$grouped_label.xcresult" \
    --output-path "$grouped_matrix_root/screenshots-$grouped_label"
done
```

逐张检查以下 5 类画面在三种宽度、两种语言下均无错图、拉伸、裁切、重叠或越界：

```text
Provided-grouped-device-instructions
Provided-grouped-energy-import
Provided-grouped-energy-export
Provided-grouped-switch-panel
Provided-grouped-path
```

Device 长页面中第二张说明图即使不在首屏，也必须由断言确认存在于真实 guide view、图片来源正确且在 guide bounds 内；截图不替代该结构断言。

- [ ] **Step 4: 运行完整静态与依赖回归**

Run:

```sh
ruby Tests/Branding/LumineuxConfigurationTests.rb
ruby Tests/Branding/LumineuxMergeTests.rb
ruby Tests/Branding/LumineuxGeneratorTests.rb
mkdir -p /private/tmp/lumineux-grouped-swift-module-cache
CLANG_MODULE_CACHE_PATH=/private/tmp/lumineux-grouped-swift-module-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/lumineux-grouped-swift-module-cache \
swift Tests/Branding/LumineuxAssetTests.swift
bash scripts/check_nordic_sdk_dependency.sh
git diff --check
```

Expected: 全部退出 0；合并器保持当前完整覆盖/恢复契约，生成器不删除 11 个 Provided imageset，SDK 依赖仍指向工程锁定配置。

- [ ] **Step 5: 在正常 DerivedData3 路径构建 Lumineux 真机 Debug 并验证签名**

Run:

```sh
grouped_build_root="$(mktemp -d /Users/sr/Library/Developer/Xcode/DerivedData3/LumineuxGroupedAssets.XXXXXX)"
xcodebuild \
  -workspace SunSmart.xcworkspace \
  -scheme Lumineux -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$grouped_build_root" \
  -clonedSourcePackagesDirPath /Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  build
codesign --verify --deep --strict \
  "$grouped_build_root/Build/Products/Debug-iphoneos/Lumineux.app"
codesign -dvv \
  "$grouped_build_root/Build/Products/Debug-iphoneos/Lumineux.app"
```

Expected: `BUILD SUCCEEDED`；签名完整性通过，Bundle ID 与 Team 不变；命令不包含 `-allowProvisioningUpdates`，也不安装或启动 App。

- [ ] **Step 6: 核对实际合并源 catalog 的 695/92/603 契约**

Run:

```sh
grouped_merged_catalog="$(find "$grouped_build_root/Build/Intermediates.noindex" \
  -type d -path '*/LumineuxAssets/Assets-Lumineux-Merged.xcassets' -print -quit)"
test -n "$grouped_merged_catalog"
grouped_total_sets="$(find "$grouped_merged_catalog" -type d \
  \( -name '*.imageset' -o -name '*.appiconset' -o -name '*.colorset' \) | wc -l | tr -d ' ')"
test "$grouped_total_sets" = 695
grouped_brand_matches=0
while IFS= read -r grouped_brand_set
do
  grouped_relative_set="${grouped_brand_set#Lumineux/Assets-Lumineux.xcassets/}"
  diff -qr "$grouped_brand_set" "$grouped_merged_catalog/$grouped_relative_set"
  grouped_brand_matches=$((grouped_brand_matches + 1))
done < <(find Lumineux/Assets-Lumineux.xcassets -type d \
  \( -name '*.imageset' -o -name '*.appiconset' -o -name '*.colorset' \) | sort)
test "$grouped_brand_matches" = 92
test $((grouped_total_sets - grouped_brand_matches)) = 603
```

Expected: 695 个合并 set、92 个 Lumineux set 逐文件匹配、603 个剩余公共 set；无重复资源警告。Task 1 的静态哈希同时证明新增 22 个 catalog PNG 与用户源文件一致且没有 1x 文件。

- [ ] **Step 7: 最终范围、排除项和脏工作区审计**

Run:

```sh
git status --short
git diff --check
git diff --name-only
find Lumineux/Assets-Lumineux.xcassets/{Device,Energy,Group,Path} \
  -name '*@1x.png' -print
find Lumineux/DesignAssets/Provided -type f -path '*path_add*' -print
```

Expected:

- `*@1x.png` 与 `path_add` 查询无输出。
- `SunSmart/` 生产文件没有本轮新增 diff；既有 Europe 用户改动仍原样存在。
- 公共/SLGSync catalog、合并器、Xcode 工程及 SDK 均未改变。
- 本轮资源、测试、脚本与文档改动全部保持未提交，供用户检查。
