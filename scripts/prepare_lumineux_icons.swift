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
    let size: Int?
    let width: Int?
    let height: Int?
    let contentSize: Int?
    let source: String

    var canvasWidth: Int {
        guard let value = width ?? size else { fatalError("Missing canvas width for \(asset)") }
        return value
    }

    var canvasHeight: Int {
        guard let value = height ?? size else { fatalError("Missing canvas height for \(asset)") }
        return value
    }

    var contentWidth: Int { contentSize ?? canvasWidth }
    var contentHeight: Int { contentSize ?? canvasHeight }
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
    precondition(bounds.width > 0 && bounds.height > 0, "Unexpected export bounds for \(asset.node)")
    precondition(asset.canvasWidth > 0 && asset.canvasHeight > 0,
                 "Invalid output canvas for \(asset.node)")
    precondition(asset.contentWidth > 0 && asset.contentWidth <= asset.canvasWidth &&
                 asset.contentHeight > 0 && asset.contentHeight <= asset.canvasHeight,
                 "Invalid content canvas for \(asset.node)")
    let directory = catalog.appendingPathComponent("\(asset.asset).imageset")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for scale in 1...3 {
        let pixelWidth = asset.canvasWidth * scale
        let pixelHeight = asset.canvasHeight * scale
        let filename = "\(asset.asset)@\(scale)x.png"
        let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                bytesPerRow: pixelWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high
        let contentWidth = CGFloat(asset.contentWidth * scale)
        let contentHeight = CGFloat(asset.contentHeight * scale)
        let drawingScale = min(contentWidth / bounds.width, contentHeight / bounds.height)
        let drawingWidth = bounds.width * drawingScale
        let drawingHeight = bounds.height * drawingScale
        context.translateBy(x: (CGFloat(pixelWidth) - drawingWidth) / 2,
                            y: (CGFloat(pixelHeight) - drawingHeight) / 2)
        context.scaleBy(x: drawingScale, y: drawingScale)
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
