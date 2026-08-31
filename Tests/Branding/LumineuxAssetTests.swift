import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

// Run from the repository root with: swift Tests/Branding/LumineuxAssetTests.swift
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Lumineux/Assets-Lumineux.xcassets")
struct AssetGroupManifest: Decodable {
    let groups: [String]
    let assets: [String: String]
}

let expectedGroups = [
    "Common", "Device", "Energy", "FireAlarm1.5", "Firmware", "Group",
    "Path", "Profile", "Scene", "Site", "Space", "Timed"
]
let expectedAssetGroups: [String: String] = [
    "AccentColor": "root",
    "AppIcon": "root",
    "add": "Common",
    "filter_selected": "Common",
    "favourite_normal": "Common",
    "favourite_selected": "Common",
    "hud_loading": "Common",
    "import": "Common",
    "launch_logo": "Common",
    "launch_logo_120": "Common",
    "loading": "Common",
    "loading_big": "Common",
    "lumineux_launch_logo": "Common",
    "menu_select": "Common",
    "navigation_back": "Common",
    "order_down": "Common",
    "order_up": "Common",
    "reset": "Common",
    "select": "Common",
    "server_select": "Common",
    "user_big": "Common",
    "device_add": "Device",
    "device_add_disable": "Device",
    "device_add_setting": "Device",
    "device_add_waiting": "Device",
    "device_all_off": "Device",
    "device_all_on": "Device",
    "device_control_off": "Device",
    "device_control_off_big": "Device",
    "device_control_on": "Device",
    "device_control_on_big": "Device",
    "device_identify": "Device",
    "device_restore": "Device",
    "device_restore_disable": "Device",
    "device_scan": "Device",
    "device_select": "Device",
    "light_value_add": "Device",
    "light_value_minus": "Device",
    "slider_point": "Device",
    "slider_point_disable": "Device",
    "switch_proxy_instructions_1": "Device",
    "switch_proxy_instructions_2": "Device",
    "energy_csv": "Energy",
    "energy_device": "Energy",
    "energy_phone": "Energy",
    "firmware_delete": "Firmware",
    "firmware_history": "Firmware",
    "server_download": "Firmware",
    "auto": "Group",
    "group_control_disable": "Group",
    "group_control_disable_big": "Group",
    "group_empty": "Group",
    "group_off": "Group",
    "group_off_big": "Group",
    "group_on": "Group",
    "group_on_big": "Group",
    "sensor_move": "Group",
    "sync_failed_small": "Group",
    "sync_loading_small": "Group",
    "sync_success_small": "Group",
    "sync_waiting_small": "Group",
    "switch_press": "Group",
    "switch_press_long": "Group",
    "switch_save": "Group",
    "path_direction_left": "Path",
    "path_direction_right": "Path",
    "path_item_add": "Path",
    "profile_chart_occupancy_daylight": "Profile",
    "scene_data_value_add": "Scene",
    "scene_data_value_minus": "Scene",
    "scene_empty": "Scene",
    "scene_group_disable": "Scene",
    "scene_group_off": "Scene",
    "scene_group_on": "Scene",
    "menu_icon": "Site",
    "more_vertical": "Site",
    "no_Internet": "Site",
    "site_empty": "Site",
    "space_add": "Space",
    "space_empty": "Space",
    "space_energy_data": "Space",
    "space_group": "Space",
    "space_group_selected": "Space",
    "space_main": "Space",
    "space_main_selected": "Space",
    "space_more": "Space",
    "space_more_selected": "Space",
    "space_scene": "Space",
    "space_scene_selected": "Space",
    "space_timed": "Space",
    "space_timed_selected": "Space",
    "schedule_target_select": "Timed"
]

let groupManifestURL = root.appendingPathComponent("Lumineux/DesignAssets/asset-groups.json")
check(FileManager.default.fileExists(atPath: groupManifestURL.path),
      "Missing Lumineux asset group manifest")
let groupManifest = try JSONDecoder().decode(
    AssetGroupManifest.self,
    from: Data(contentsOf: groupManifestURL)
)
check(groupManifest.groups == expectedGroups,
      "Lumineux groups must match SLGSync order and names")
check(groupManifest.assets == expectedAssetGroups,
      "Lumineux asset group manifest differs from the approved 92-resource mapping")

func setExtension(for name: String) -> String {
    switch name {
    case "AppIcon": return "appiconset"
    case "AccentColor": return "colorset"
    default: return "imageset"
    }
}

func assetSetURL(named name: String) -> URL {
    guard let group = expectedAssetGroups[name] else {
        preconditionFailure("No approved group for \(name)")
    }
    let parent = group == "root" ? catalog : catalog.appendingPathComponent(group)
    return parent.appendingPathComponent("\(name).\(setExtension(for: name))")
}

func contents(in set: URL) throws -> [String: Any] {
    try JSONSerialization.jsonObject(
        with: Data(contentsOf: set.appendingPathComponent("Contents.json"))
    ) as! [String: Any]
}

func image(in set: URL, filename: String) throws -> CGImage {
    let data = try Data(contentsOf: set.appendingPathComponent(filename))
    return CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
}

func contents(named name: String) throws -> [String: Any] {
    try contents(in: assetSetURL(named: name))
}

func image(named name: String, filename: String) throws -> CGImage {
    try image(in: assetSetURL(named: name), filename: filename)
}

for group in expectedGroups {
    let directory = catalog.appendingPathComponent(group)
    check(FileManager.default.fileExists(atPath: directory.path),
          "Missing Lumineux asset group: \(group)")
    let metadata = try JSONSerialization.jsonObject(
        with: Data(contentsOf: directory.appendingPathComponent("Contents.json"))
    ) as! [String: Any]
    check(metadata["properties"] == nil,
          "Lumineux asset groups must not provide a namespace: \(group)")
}

let supportedSetExtensions = Set(["imageset", "appiconset", "colorset"])
let catalogGroupNames = try FileManager.default.contentsOfDirectory(
    at: catalog,
    includingPropertiesForKeys: [.isDirectoryKey]
).filter { url in
    let values = try url.resourceValues(forKeys: [.isDirectoryKey])
    return values.isDirectory == true && !supportedSetExtensions.contains(url.pathExtension)
}.map(\.lastPathComponent)
check(Set(catalogGroupNames) == Set(expectedGroups),
      "Lumineux catalog top-level groups must exactly match the approved groups")

let enumerator = FileManager.default.enumerator(
    at: catalog,
    includingPropertiesForKeys: [.isDirectoryKey],
    options: [.skipsHiddenFiles]
)!
var discovered: [String: [URL]] = [:]
while let url = enumerator.nextObject() as? URL {
    guard supportedSetExtensions.contains(url.pathExtension) else { continue }
    let name = url.deletingPathExtension().lastPathComponent
    discovered[name, default: []].append(url.standardizedFileURL)
    enumerator.skipDescendants()
}
check(discovered.count == 92, "Lumineux catalog must contain exactly 92 asset names")
check(Set(discovered.keys) == Set(expectedAssetGroups.keys),
      "Lumineux catalog asset names differ from the approved set")
for name in expectedAssetGroups.keys.sorted() {
    let locations = discovered[name] ?? []
    check(locations.count == 1, "Lumineux asset \(name) must appear exactly once")
    check(locations.first == assetSetURL(named: name).standardizedFileURL,
          "Lumineux asset \(name) is in the wrong business group")
}
let rootImagesets = try FileManager.default.contentsOfDirectory(
    at: catalog,
    includingPropertiesForKeys: [.isDirectoryKey]
).filter { $0.pathExtension == "imageset" }
check(rootImagesets.isEmpty, "Lumineux catalog root must not contain imagesets")

func whiteBackgroundPixels(_ image: CGImage, side: Int) -> [UInt8] {
    let context = CGContext(data: nil, width: side, height: side,
                            bitsPerComponent: 8, bytesPerRow: side * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: side * side * 4))
}

// Independent source oracle: the approved 1024px Figma export, not the small
// rounded 88px preview or another packaged logo that could carry the same bug.
let logoSourceURL = root.appendingPathComponent("Lumineux/DesignAssets/app_logo_1024.png")
let logoSource = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(logoSourceURL as CFURL, nil)!, 0, nil)!
check(logoSource.width == 1024 && logoSource.height == 1024, "Logo master must remain 1024px")
var logoFailures: [String] = []
for (name, logicalSize) in [("launch_logo", 88),
                            ("launch_logo_120", 120),
                            ("lumineux_launch_logo", 88)] {
    let imageSet = assetSetURL(named: name)
    guard FileManager.default.fileExists(atPath: imageSet.path) else {
        print("FAIL: Missing dedicated Lumineux image set: \(name)")
        exit(1)
    }
    let entries = try contents(named: name)["images"] as! [[String: String]]
    check(entries.count == 3, "Each logo needs 1x/2x/3x variants")
    for scale in 1...3 {
        let entry = entries.first { $0["scale"] == "\(scale)x" }!
        let pixels = try image(named: name, filename: entry["filename"]!)
        check(pixels.width == logicalSize * scale && pixels.height == logicalSize * scale,
              "Wrong pixel size for \(name) @\(scale)x")
        let side = logicalSize * scale
        let actual = whiteBackgroundPixels(pixels, side: side)
        let expected = whiteBackgroundPixels(logoSource, side: side)
        let meanDifference = Double(zip(actual, expected).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(actual.count)
        if meanDifference > 0.5 {
            logoFailures.append("\(name) @\(scale)x does not match the downsampled high-resolution source (mean delta \(meanDifference))")
        }
        let corner = side / 8
        let cornersAreWhite = [0, side - corner].allSatisfy { left in
            [0, side - corner].allSatisfy { top in
                (top..<(top + corner)).allSatisfy { y in
                    (left..<(left + corner)).allSatisfy { x in
                        (0..<3).allSatisfy { actual[(y * side + x) * 4 + $0] >= 253 }
                    }
                }
            }
        }
        if !cornersAreWhite { logoFailures.append("\(name) @\(scale)x contains gray corner artwork") }
    }
}
if !logoFailures.isEmpty {
    logoFailures.forEach { print("FAIL: \($0)") }
    exit(1)
}
let manifestData = try Data(contentsOf: root.appendingPathComponent("Lumineux/DesignAssets/icon-manifest.json"))
let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
let iconAssets = manifest["assets"] as! [[String: Any]]
// Page artwork must use the exact supplied node and the existing iOS canvas.
for (name, node, size) in [("add", "16001:24116", 48),
                           ("select", "5776:95965", 30),
                           ("space_add", "16001:97684", 30)] {
    let asset = iconAssets.first { $0["asset"] as? String == name }
    check(asset != nil, "Missing page artwork: \(name)")
    check(asset?["node"] as? String == node, "Incorrect Figma source node for \(name)")
    check(asset?["size"] as? Int == size, "Page artwork must preserve the original canvas for \(name)")
}
// Profile and Safe Mode artwork must use the exact approved Figma nodes. The
// profile chart is non-square, while device_select keeps the project's 30pt
// control canvas around the original centered 18pt glyph.
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
// Compact device status artwork must export the whole 24pt component rather
// than an inner vector, otherwise the visible symbol is scaled too large.
for (name, node) in [("sync_success_small", "0:18004"),
                     ("sync_failed_small", "0:18014"),
                     ("sync_waiting_small", "0:18424"),
                     ("sync_loading_small", "0:19394"),
                     ("device_scan", "0:19460")] {
    let asset = iconAssets.first { $0["asset"] as? String == name }
    check(asset != nil, "Missing compact Lumineux status artwork: \(name)")
    check(asset?["node"] as? String == node, "Incorrect Figma source node for \(name)")
    check(asset?["size"] as? Int == 24, "Compact status artwork must preserve its 24pt canvas for \(name)")
}
for asset in iconAssets {
    let name = asset["asset"] as! String
    let width = (asset["width"] as? Int) ?? (asset["size"] as! Int)
    let height = (asset["height"] as? Int) ?? (asset["size"] as! Int)
    let entries = try contents(named: name)["images"] as! [[String: String]]
    check(entries.count == 3, "Missing scale variants for \(name)")
    for scale in 1...3 {
        let entry = entries.first { $0["scale"] == "\(scale)x" }!
        let pixels = try image(named: name, filename: entry["filename"]!)
        check(pixels.width == width * scale && pixels.height == height * scale, "Incorrect logical size for \(name)")
        var rgba = [UInt8](repeating: 0, count: pixels.width * pixels.height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: pixels.width, height: pixels.height,
                                    bitsPerComponent: 8, bytesPerRow: pixels.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(pixels, in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        }
        let visible = (0..<(pixels.width * pixels.height)).filter { rgba[$0 * 4 + 3] > 20 }
        check(!visible.isEmpty, "Blank artwork for \(name)")
        let xs = visible.map { $0 % pixels.width }, ys = visible.map { $0 / pixels.width }
        let visibleWidth = xs.max()! - xs.min()! + 1
        let visibleHeight = ys.max()! - ys.min()! + 1
        let visibleExtent = max(visibleWidth, visibleHeight)
        check(Double(visibleExtent) >= Double(max(width, height) * scale) * 0.45,
              "Artwork unexpectedly shrunk for \(name) @\(scale)x")
        if let contentSize = asset["contentSize"] as? Int {
            check(visibleWidth <= (contentSize + 1) * scale && visibleHeight <= (contentSize + 1) * scale,
                  "Padded artwork unexpectedly enlarged for \(name) @\(scale)x")
            let left = xs.min()!, right = pixels.width - xs.max()! - 1
            let top = ys.min()!, bottom = pixels.height - ys.max()! - 1
            check(abs(left - right) <= scale && abs(top - bottom) <= scale,
                  "Padded artwork is not centered for \(name) @\(scale)x")
        }
    }
}

// Some final artwork is supplied as original Retina PNGs rather than a Figma
// vector node. Preserve those source bytes separately and only derive 1x.
let providedDirectory = root.appendingPathComponent("Lumineux/DesignAssets/Provided")
let providedAutoHashes = [
    2: "d7da9e2b0c702a74a92e2a9341b46e4f8c44af4ada2c6703598134130ce30abc",
    3: "c068c328b6770a6c9322c9d09d1b2a4a5e16e73b749f7b79e9e9b97570e6d814"
]
for scale in 2...3 {
    let sourceURL = providedDirectory.appendingPathComponent("auto@\(scale)x.png")
    check(FileManager.default.fileExists(atPath: sourceURL.path),
          "Missing supplied Lumineux source artwork: auto@\(scale)x.png")
    let sourceData = try Data(contentsOf: sourceURL)
    let sourceDigest = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
    check(sourceDigest == providedAutoHashes[scale],
          "Supplied auto@\(scale)x source bytes must remain unchanged")
}
let autoSet = assetSetURL(named: "auto")
let autoEntries = try contents(named: "auto")["images"] as! [[String: String]]
check(autoEntries.count == 3, "Supplied auto icon needs 1x/2x/3x variants")
for scale in 1...3 {
    let entry = autoEntries.first { $0["scale"] == "\(scale)x" }
    check(entry != nil, "Missing auto @\(scale)x")
    let filename = entry!["filename"]!
    let pixels = try image(named: "auto", filename: filename)
    check(pixels.width == 40 * scale && pixels.height == 40 * scale,
          "Incorrect 40pt canvas for auto @\(scale)x")
    if scale >= 2 {
        let data = try Data(contentsOf: autoSet.appendingPathComponent(filename))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        check(digest == providedAutoHashes[scale],
              "auto @\(scale)x must remain the exact supplied PNG")
    }
}

// These supplied Common assets intentionally match the existing two-scale
// catalog contract: preserve exact 2x/3x bytes and leave the 1x slot empty.
let providedCommonDirectory = providedDirectory.appendingPathComponent("Common")
let providedCommonAssets: [(name: String, points: Int, hashes: [Int: String])] = [
    ("filter_selected", 30, [
        2: "7cc3af31b9f828c33d7765d96fc994843ffbca6d244474ae27326da10f3aafbb",
        3: "d49d67ea0137cd5c292ac421acbca80acb989d462e88e53a91f91ce2db33ddbb"
    ]),
    ("menu_select", 30, [
        2: "51fef836f1866e60b602ca435294a001abad681855d07e38b7ef95c7e9d29b05",
        3: "6b6e29ab8be3581095143edc8395bf065ffc88308edf532f271501e2f11d9bc3"
    ]),
    ("order_down", 30, [
        2: "cf7cff430c9ff3bd08ef60e461a740fc43d0d460ee3e1098acb17f0a1ce08d98",
        3: "a381f2c1266f7fa7fff2c0f60b5083f4d89accc43fe59c7b818e9640d14bb492"
    ]),
    ("order_up", 30, [
        2: "5eef3c88c7cbf77f8d472b2256efb2b5791af8224fd8407c762e46ae5cf1eede",
        3: "ddaeb1db793212aebaf7b1f28af29afc0f9531f60e2e8749ced29ac147c7443f"
    ]),
    ("server_select", 30, [
        2: "b17653195109f25d9ec08df9454a6976e314f1c50055c8c1c5d6b7cccd49c61b",
        3: "067222632c85ea3c9f3e35f9a046c280844015fc48e96b0c3dddb5333e6f216a"
    ]),
    ("user_big", 88, [
        2: "6c7d79fe8c5757fbdf067820f2c810a7792325b040ec7cef5beb7372b5bbd0f7",
        3: "c0063e0e178986fd318c08bfd3de7af92e4298233e197c3f467005f8606b159b"
    ])
]
for asset in providedCommonAssets {
    let entries = try contents(named: asset.name)["images"] as! [[String: String]]
    check(entries.count == 3,
          "Expected empty 1x plus supplied 2x/3x for \(asset.name)")
    check(entries.first { $0["scale"] == "1x" }?["filename"] == nil,
          "\(asset.name) must not generate a 1x file")
    for scale in 2...3 {
        let filename = "\(asset.name)@\(scale)x.png"
        let source = providedCommonDirectory.appendingPathComponent(filename)
        check(FileManager.default.fileExists(atPath: source.path),
              "Missing supplied Common source artwork: \(filename)")
        let sourceData = try Data(contentsOf: source)
        let digest = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
        check(digest == asset.hashes[scale],
              "Supplied \(asset.name) @\(scale)x bytes changed")
        let catalogFilename = entries.first { $0["scale"] == "\(scale)x" }?["filename"]
        check(catalogFilename == filename,
              "Unexpected catalog filename for \(asset.name) @\(scale)x")
        let catalogData = try Data(
            contentsOf: assetSetURL(named: asset.name).appendingPathComponent(catalogFilename!)
        )
        check(catalogData == sourceData,
              "Catalog must preserve \(asset.name) @\(scale)x bytes")
        let pixels = try image(named: asset.name, filename: catalogFilename!)
        check(pixels.width == asset.points * scale && pixels.height == asset.points * scale,
              "Incorrect logical canvas for \(asset.name) @\(scale)x")
    }
}

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

check(providedGroupedAssets.count == 11,
      "Expected exactly 11 supplied Device/Energy/Group/Path assets")
for asset in providedGroupedAssets {
    check(expectedAssetGroups[asset.name] == asset.group,
          "Wrong business group for supplied asset: \(asset.name)")
    let entries = try contents(named: asset.name)["images"] as! [[String: String]]
    check(entries.count == 3,
          "Expected empty 1x plus supplied 2x/3x for \(asset.name)")
    for scale in 1...3 {
        check(entries.filter { $0["scale"] == "\(scale)x" }.count == 1,
              "Expected exactly one universal \(scale)x entry for \(asset.name)")
    }
    check(entries.allSatisfy { $0["idiom"] == "universal" },
          "All scale entries must use the universal idiom for \(asset.name)")
    check(entries.first { $0["scale"] == "1x" }!["filename"] == nil,
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

// Empty-state illustrations are complete Figma node exports. Keep their
// original non-square canvas, scale, alpha, and exact exported bytes.
let emptyStates: [(name: String, node: String, width: Int, height: Int, hashes: [Int: String])] = [
    ("site_empty", "0:11425", 353, 298, [
        2: "8b454a46adee9a1f18f730cab8b24788abbaaa17c6b3a67922dd9e6be2180ef7",
        3: "9f4bdd85208ca2bb8d94d27de802ea875731587b082f5b2b7ef62cec8e626e83"
    ]),
    ("space_empty", "2090:132420", 240, 194, [
        2: "d30ec96f934f2a8ad396f4cb1d96adad43ab21effadfb863f046727fcd9bffed",
        3: "f8c28f59f9a714cf68e7a0f8a2468774416f7bddf9b58d6302c720c5e92ed279"
    ]),
    ("group_empty", "0:2719", 343, 288, [
        2: "801044b73511933f50e71c2a1a6184bc6218c1934e6662cb6d535b42a7fd9a6a",
        3: "c0887c82b7dfdf0c460fada6d81dae2d3f1bb3d0b466b160994cf1d1dd468b2b"
    ]),
    ("scene_empty", "0:4474", 343, 288, [
        2: "a6a12bbcc7a84830441cee216cfffde8b76c6efe913108dfa1875261c4c5b5c3",
        3: "12fd0972a9694161e6197a29f9d54fe7a8d36c950a9ebb5a1076324550b69898"
    ])
]
check(Set(emptyStates.map(\.name)).count == 4, "Empty-state manifest must contain four distinct assets")
for asset in emptyStates {
    let imageSet = assetSetURL(named: asset.name)
    check(FileManager.default.fileExists(atPath: imageSet.path),
          "Missing Lumineux empty-state image set: \(asset.name) from Figma \(asset.node)")
    let entries = try contents(named: asset.name)["images"] as! [[String: String]]
    let populatedEntries = entries.filter { $0["filename"] != nil }
    check(populatedEntries.count == 2, "Empty-state assets must contain exact 2x/3x Figma exports")
    for scale in 2...3 {
        let entry = populatedEntries.first { $0["scale"] == "\(scale)x" }
        check(entry != nil, "Missing \(asset.name) @\(scale)x")
        let filename = entry!["filename"]!
        let data = try Data(contentsOf: imageSet.appendingPathComponent(filename))
        let pixels = try image(named: asset.name, filename: filename)
        check(pixels.width == asset.width * scale && pixels.height == asset.height * scale,
              "Incorrect Figma canvas for \(asset.name) @\(scale)x")
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        check(digest == asset.hashes[scale],
              "\(asset.name) @\(scale)x must remain the exact Figma node \(asset.node) export")
    }
}
let iconEntries = try contents(named: "AppIcon")["images"] as! [[String: String]]
let icon = try image(named: "AppIcon", filename: iconEntries[0]["filename"]!)
check(icon.width == 1024 && icon.height == 1024, "App icon must be 1024 square")
check([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(icon.alphaInfo), "App icon must be opaque")
let colors = try contents(named: "AccentColor")["colors"] as! [[String: Any]]
let components = (colors[0]["color"] as! [String: Any])["components"] as! [String: String]
check(components == ["red": "0x4D", "green": "0x73", "blue": "0x8A", "alpha": "1.000"], "Accent color must be #4D738A")
print("Lumineux asset tests passed: \(iconAssets.count) Figma-vector icons, 7 supplied PNG icons, 4 exact Figma empty states, retina logos, opaque 1024 AppIcon, exact AccentColor")
