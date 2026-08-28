import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Mechanical packaging of complete Figma exports; never redraw or recolor artwork.
// Run from the repository root: swift scripts/prepare_lumineux_icons.swift
struct Manifest: Decodable { let assets: [Asset] }
struct Asset: Decodable {
    let asset: String
    let node: String
    let size: Int
    let source: String
}
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let designAssets = root.appendingPathComponent("Lumineux/DesignAssets")
let catalog = root.appendingPathComponent("Lumineux/Assets-Lumineux.xcassets")
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: designAssets.appendingPathComponent("icon-manifest.json")))
precondition(Set(manifest.assets.map(\.asset)).count == manifest.assets.count, "Duplicate asset name")
for asset in manifest.assets {
    let source = designAssets.appendingPathComponent(asset.source)
    guard let document = CGPDFDocument(source as CFURL), let page = document.page(at: 1) else {
        fatalError("Missing or invalid original export: \(source.path)")
    }
    let bounds = page.getBoxRect(.mediaBox)
    precondition(bounds.width == bounds.height && bounds.width > 0, "Unexpected export bounds for \(asset.node)")
    let directory = catalog.appendingPathComponent("\(asset.asset).imageset")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for scale in 1...3 {
        let side = asset.size * scale
        let filename = "\(asset.asset)@\(scale)x.png"
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        // getDrawingTransform centers small pages without upscaling them.
        // Explicitly scale the complete source canvas for Retina variants.
        context.scaleBy(x: CGFloat(side) / bounds.width, y: CGFloat(side) / bounds.height)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(page)
        let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(filename) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination), "Unable to write \(filename)")
        images.append(["idiom": "universal", "filename": filename, "scale": "\(scale)x"])
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("Contents.json"), options: .atomic)
}
print("Packaged \(manifest.assets.count) same-name Lumineux imagesets from original Figma vector exports")
