import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let manifestURL = root.appendingPathComponent("Lumineux/DesignAssets/asset-groups.json")
let manifest = try JSONSerialization.jsonObject(
    with: Data(contentsOf: manifestURL)
) as! [String: Any]
let assetGroups = manifest["assets"] as! [String: String]
check(assetGroups["bluetooth_required"] == "Space",
      "bluetooth_required must be registered in the Space group")

let imageSet = root.appendingPathComponent(
    "Lumineux/Assets-Lumineux.xcassets/Space/bluetooth_required.imageset"
)
check(FileManager.default.fileExists(atPath: imageSet.path),
      "Missing Lumineux bluetooth_required.imageset")

let contents = try JSONSerialization.jsonObject(
    with: Data(contentsOf: imageSet.appendingPathComponent("Contents.json"))
) as! [String: Any]
let entries = contents["images"] as! [[String: String]]
check(entries.count == 3, "bluetooth_required must have 1x, 2x, and 3x entries")
let oneX = entries.first { $0["scale"] == "1x" }
check(oneX?["idiom"] == "universal" && oneX?["filename"] == nil,
      "bluetooth_required 1x must remain an empty universal slot")

let expected: [Int: (filename: String, width: Int, height: Int, sha256: String)] = [
    2: ("bluetooth_required@2x.png", 480, 388,
        "82f42e27406d67bff533811bdb51d9d739354978ddb048a3689bf805e046db4d"),
    3: ("bluetooth_required@3x.png", 720, 582,
        "379ff2bf589091e8b64bd14ae12e934b552fe26efae8b83fa4fb36a08f7f4c3d")
]

for scale in 2...3 {
    let expectedVariant = expected[scale]!
    let entry = entries.first { $0["scale"] == "\(scale)x" }
    check(entry?["idiom"] == "universal",
          "bluetooth_required @\(scale)x must be universal")
    check(entry?["filename"] == expectedVariant.filename,
          "bluetooth_required @\(scale)x has the wrong filename")

    let imageURL = imageSet.appendingPathComponent(expectedVariant.filename)
    let data = try Data(contentsOf: imageURL)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    check(digest == expectedVariant.sha256,
          "bluetooth_required @\(scale)x does not match the approved input PNG")

    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    check(image.width == expectedVariant.width && image.height == expectedVariant.height,
          "bluetooth_required @\(scale)x has the wrong pixel canvas")
    check(![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo),
          "bluetooth_required @\(scale)x must preserve transparency")
}

print("Lumineux bluetooth_required asset tests passed")
