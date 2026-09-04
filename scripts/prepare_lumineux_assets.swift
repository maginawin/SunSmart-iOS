import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Mechanical iOS asset packaging only. The Figma artwork is never redrawn or recolored.
// Run from repository root: swift scripts/prepare_lumineux_assets.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let designAssets = root.appendingPathComponent("Lumineux/DesignAssets")
func sourceImage(_ relativePath: String) -> CGImage {
    let url = root.appendingPathComponent(relativePath)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        preconditionFailure("Could not read \(url.path)")
    }
    return image
}
let appIcon = sourceImage("Lumineux/DesignAssets/app_logo_1024.png")
// The 88px preview includes gray rounded corners and cannot supply Retina
// detail. Derive both in-app logo sizes from the unrounded 1024px master.
let launchLogo = appIcon
precondition(appIcon.width == 1024 && appIcon.height == 1024)
let catalog = root.appendingPathComponent("Lumineux/Assets-Lumineux.xcassets")

struct AssetGroupManifest: Decodable {
    let groups: [String]
    let assets: [String: String]
}

func loadAssetGroupManifest() throws -> AssetGroupManifest {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
    process.arguments = [
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("validate_lumineux_asset_groups.rb").path,
        catalog.path,
        designAssets.appendingPathComponent("asset-groups.json").path
    ]
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    let errorText = String(
        data: errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    precondition(process.terminationStatus == 0, errorText)
    return try JSONDecoder().decode(
        AssetGroupManifest.self,
        from: output.fileHandleForReading.readDataToEndOfFile()
    )
}

let assetGroupManifest = try loadAssetGroupManifest()

func assetSetDirectory(named name: String, type: String) throws -> URL {
    guard let group = assetGroupManifest.assets[name] else {
        preconditionFailure("Missing asset group for \(name)")
    }
    let parent = group == "root" ? catalog : catalog.appendingPathComponent(group)
    let directory = parent.appendingPathComponent("\(name).\(type)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

let info: [String: Any] = ["author": "xcode", "version": 1]

func writeJSON(_ object: [String: Any], to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("Contents.json"))
}
func writePNG(_ image: CGImage, size: Int, to url: URL) {
    precondition(image.width >= size && image.height >= size, "Logo master must not be upscaled")
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination), "Could not write \(url.path)")
}

func writeOpaqueAppIcon(_ image: CGImage, to url: URL) {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 1024 * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // The original export is transparent even though its intended app-icon
    // presentation is on white. Flatten only this packaged derivative; never
    // alter the Figma source file or its RGB artwork.
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination), "Could not write \(url.path)")
}

try writeJSON(["info": info], to: catalog)
for (name, logicalSize) in [("launch_logo", 88),
                            ("launch_logo_120", 120),
                            ("lumineux_launch_logo", 88)] {
    let directory = try assetSetDirectory(named: name, type: "imageset")
    let usesRetinaOnlyFiles = ["launch_logo", "lumineux_launch_logo"].contains(name)
    let images = (1...3).map { scale -> [String: String] in
        var entry = ["idiom": "universal", "scale": "\(scale)x"]
        if !usesRetinaOnlyFiles || scale > 1 {
            entry["filename"] = "\(name)@\(scale)x.png"
        }
        return entry
    }
    try writeJSON(["images": images, "info": info], to: directory)
    if usesRetinaOnlyFiles {
        let oneX = directory.appendingPathComponent("\(name)@1x.png")
        if FileManager.default.fileExists(atPath: oneX.path) {
            try FileManager.default.removeItem(at: oneX)
        }
    }
    let scales = usesRetinaOnlyFiles ? 2...3 : 1...3
    for scale in scales {
        writePNG(launchLogo, size: logicalSize * scale,
                 to: directory.appendingPathComponent("\(name)@\(scale)x.png"))
    }
}
let iconDirectory = try assetSetDirectory(named: "AppIcon", type: "appiconset")
try writeJSON(["images": [["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]], "info": info], to: iconDirectory)
writeOpaqueAppIcon(appIcon, to: iconDirectory.appendingPathComponent("AppIcon.png"))
let accentDirectory = try assetSetDirectory(named: "AccentColor", type: "colorset")
try writeJSON(["colors": [["idiom": "universal", "color": ["color-space": "srgb", "components": ["red": "0x4D", "green": "0x73", "blue": "0x8A", "alpha": "1.000"]]]], "info": info], to: accentDirectory)
print("Prepared Lumineux shared-name and dedicated launch iOS assets from the high-resolution original export without recoloring")
