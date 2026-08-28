import Foundation
import CoreGraphics
import ImageIO

// Run from the repository root with: swift Tests/Branding/LumineuxAssetTests.swift
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Lumineux/Assets-Lumineux.xcassets")
func json(_ path: String) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: catalog.appendingPathComponent(path))) as! [String: Any]
}
func image(_ path: String) throws -> CGImage {
    let data = try Data(contentsOf: catalog.appendingPathComponent(path))
    return CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
}

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
for (name, logicalSize) in [("launch_logo", 88), ("launch_logo_120", 120)] {
    let entries = try json("\(name).imageset/Contents.json")["images"] as! [[String: String]]
    check(entries.count == 3, "Each logo needs 1x/2x/3x variants")
    for scale in 1...3 {
        let entry = entries.first { $0["scale"] == "\(scale)x" }!
        let pixels = try image("\(name).imageset/\(entry["filename"]!)")
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
for asset in iconAssets {
    let name = asset["asset"] as! String
    let size = asset["size"] as! Int
    let entries = try json("\(name).imageset/Contents.json")["images"] as! [[String: String]]
    check(entries.count == 3, "Missing scale variants for \(name)")
    for scale in 1...3 {
        let entry = entries.first { $0["scale"] == "\(scale)x" }!
        let pixels = try image("\(name).imageset/\(entry["filename"]!)")
        check(pixels.width == size * scale && pixels.height == size * scale, "Incorrect logical size for \(name)")
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
        let visibleExtent = max(xs.max()! - xs.min()! + 1, ys.max()! - ys.min()! + 1)
        check(Double(visibleExtent) >= Double(size * scale) * 0.45, "Artwork unexpectedly shrunk for \(name) @\(scale)x")
    }
}
let iconEntries = try json("AppIcon.appiconset/Contents.json")["images"] as! [[String: String]]
let icon = try image("AppIcon.appiconset/\(iconEntries[0]["filename"]!)")
check(icon.width == 1024 && icon.height == 1024, "App icon must be 1024 square")
check([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(icon.alphaInfo), "App icon must be opaque")
let colors = try json("AccentColor.colorset/Contents.json")["colors"] as! [[String: Any]]
let components = (colors[0]["color"] as! [String: Any])["components"] as! [String: String]
check(components == ["red": "0x4D", "green": "0x73", "blue": "0x8A", "alpha": "1.000"], "Accent color must be #4D738A")
print("Lumineux asset tests passed: \(iconAssets.count) same-name icons at 1x/2x/3x, retina logos, opaque 1024 AppIcon, exact AccentColor")
