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
    "favourite_normal": "Common",
    "favourite_selected": "Common",
    "hud_loading": "Common",
    "import": "Common",
    "launch_logo": "Common",
    "launch_logo_120": "Common",
    "loading": "Common",
    "loading_big": "Common",
    "lumineux_launch_logo": "Common",
    "navigation_back": "Common",
    "reset": "Common",
    "select": "Common",
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
      "Lumineux asset group manifest differs from the approved 75-resource mapping")

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
check(discovered.count == 75, "Lumineux catalog must contain exactly 75 asset names")
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
print("Lumineux asset tests passed: \(iconAssets.count) Figma-vector icons, 1 supplied PNG icon, 4 exact Figma empty states, retina logos, opaque 1024 AppIcon, exact AccentColor")
