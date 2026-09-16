import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Package the original Figma image fills inside their 120 x 96 component canvas.
// The artwork (including its embedded labels) is never redrawn or recolored.
struct SpaceIconManifest: Decodable {
    struct Asset: Decodable {
        let id: Int
        let source: String
    }
    let assets: [Asset]
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sources = root.appendingPathComponent("Lumineux/DesignAssets")
let catalog = root.appendingPathComponent("Lumineux/Assets-Lumineux.xcassets/Space")
let manifest = try JSONDecoder().decode(SpaceIconManifest.self,
    from: Data(contentsOf: sources.appendingPathComponent("space-icons.json")))
precondition(manifest.assets.map(\.id) == Array(1...60), "Expected Figma order 1...60")

for asset in manifest.assets {
    let source = sources.appendingPathComponent(asset.source)
    guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        fatalError("Missing original Space icon: \(source.path)")
    }
    precondition(image.width == 500 && image.height == 500, "Unexpected Figma source dimensions")
    let name = "space_picture_\(asset.id)"
    let directory = catalog.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var entries: [[String: String]] = [["idiom": "universal", "scale": "1x"]]
    for scale in [2, 3] {
        let context = CGContext(data: nil, width: 120 * scale, height: 96 * scale,
            bitsPerComponent: 8, bytesPerRow: 120 * scale * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        // Exact Figma frame: white fill, 10pt corner radius, centered 96pt image.
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 120, height: 96),
            cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 12, y: 0, width: 96, height: 96))
        let filename = "\(name)@\(scale)x.png"
        let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(filename) as CFURL,
            UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination), "Unable to package \(filename)")
        entries.append(["idiom": "universal", "scale": "\(scale)x", "filename": filename])
    }
    let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
    try (JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]) + Data([10]))
        .write(to: directory.appendingPathComponent("Contents.json"))
}
print("Packaged 60 Lumineux Space icons at 120 x 96pt (2x/3x)")
