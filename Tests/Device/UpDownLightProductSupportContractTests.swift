import Foundation
import NordicSigMeshSDK

@main
struct UpDownLightProductSupportContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root argument")
        }

        let repositoryRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try testBundledDeviceConfiguration(repositoryRoot: repositoryRoot)
        testUpDownRatioCapability()
        testDefaultCctStepsCapability()
        testExternalLightSensorCapability()
        testMotionSensitivityExclusion()

        print("UpDownLightProductSupportContractTests passed")
    }

    private static func testBundledDeviceConfiguration(repositoryRoot: URL) throws {
        let configURL = repositoryRoot.appendingPathComponent("SunSmart/devices_config.json")
        let data = try Data(contentsOf: configURL)
        let records = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let matches = records.filter {
            $0["companyId"] as? String == "0A78" &&
                $0["productId"] as? String == "2321"
        }

        precondition(matches.count == 1, "Expected exactly one 0x0A78/0x2321 device config")
        let record = matches[0]
        precondition(record["categoryName"] as? String == "CCT Up&Down Lighting")
        precondition(record["elementCount"] as? Int == 3)
        precondition(record["iconCategory"] as? String == "BidirectionalController")
        precondition(record["deviceCategory"] as? String == "Lighting")
        precondition(record["modelName"] as? String == "SRPL-BL9105N-XXCCXXE")

        let cctDriverMatches = records.filter {
            $0["companyId"] as? String == "0A78" &&
                $0["productId"] as? String == "2322"
        }
        precondition(cctDriverMatches.count == 1, "Expected exactly one 0x0A78/0x2322 device config")
        let cctDriverRecord = cctDriverMatches[0]
        precondition(cctDriverRecord["categoryName"] as? String == "Driver Lighting")
        precondition(cctDriverRecord["elementCount"] as? Int == 3)
        precondition(cctDriverRecord["iconCategory"] as? String == "Lighting")
        precondition(cctDriverRecord["deviceCategory"] as? String == "Lighting")
        precondition(cctDriverRecord["modelName"] as? String == "SRPL-BL9105N-XXCCTXXE")
    }

    private static func testUpDownRatioCapability() {
        precondition(makeNode(companyIdentifier: 0x0A78, productIdentifier: 0x2491).supportsUpDownRatioControl)
        precondition(makeNode(companyIdentifier: 0x0A78, productIdentifier: 0x2321).supportsUpDownRatioControl)
        precondition(!makeNode(companyIdentifier: 0x0A78, productIdentifier: 0x2492).supportsUpDownRatioControl)
        precondition(!makeNode(companyIdentifier: 0x1234, productIdentifier: 0x2321).supportsUpDownRatioControl)
    }

    private static func testDefaultCctStepsCapability() {
        precondition(makeNode(companyIdentifier: 0x0A78, productIdentifier: 0x2491).supportsUpDownLightDefaultCctSteps)
        precondition(makeNode(companyIdentifier: 0x0A78, productIdentifier: 0x2492).supportsUpDownLightDefaultCctSteps)
        precondition(makeNode(companyIdentifier: 0x0A78, productIdentifier: 0x2321).supportsUpDownLightDefaultCctSteps)
        precondition(!makeNode(companyIdentifier: 0x0A78, productIdentifier: 0x24A1).supportsUpDownLightDefaultCctSteps)
        precondition(!makeNode(companyIdentifier: 0x1234, productIdentifier: 0x2321).supportsUpDownLightDefaultCctSteps)
    }

    private static func testExternalLightSensorCapability() {
        let supportedProducts: [UInt16] = [
            0x2121, 0x2122, 0x2132, 0x2133, 0x2321, 0x2322,
            0x2491, 0x2492, 0x2493, 0x2494
        ]
        for productIdentifier in supportedProducts {
            precondition(SunricherProductCapabilityPolicy.isExternalLightSensorCapableLuminaire(companyIdentifier: 0x0A78, productIdentifier: productIdentifier))
            precondition(!SunricherProductCapabilityPolicy.isExternalLightSensorCapableLuminaire(companyIdentifier: 0x1234, productIdentifier: productIdentifier))
        }
        // 0x2131 仅排除绝对灵敏度，不触发外接光感能力对应的 Group 提示。
        precondition(!SunricherProductCapabilityPolicy.isExternalLightSensorCapableLuminaire(companyIdentifier: 0x0A78, productIdentifier: 0x2131))
        precondition(!SunricherProductCapabilityPolicy.isExternalLightSensorCapableLuminaire(companyIdentifier: 0x0A78, productIdentifier: 0x24A1))
        precondition(!SunricherProductCapabilityPolicy.isExternalLightSensorCapableLuminaire(companyIdentifier: nil, productIdentifier: 0x2322))
        precondition(!SunricherProductCapabilityPolicy.isExternalLightSensorCapableLuminaire(companyIdentifier: 0x0A78, productIdentifier: nil))
    }

    private static func testMotionSensitivityExclusion() {
        precondition(SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x0A78, productIdentifier: 0x2491))
        precondition(SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x0A78, productIdentifier: 0x2321))
        precondition(!SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x0A78, productIdentifier: 0x24A1))
        precondition(!SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x1234, productIdentifier: 0x2321))
        precondition(SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x0A78, productIdentifier: 0x2131))
        precondition(SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x0A78, productIdentifier: 0x2132))
        precondition(SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x0A78, productIdentifier: 0x2322))
        precondition(!SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x1234, productIdentifier: 0x2322))
        precondition(!SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: nil, productIdentifier: 0x2322))
        precondition(!SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x0A78, productIdentifier: nil))
    }

    private static func makeNode(companyIdentifier: UInt16, productIdentifier: UInt16) -> Node {
        let node = Node()
        node.companyIdentifier = companyIdentifier
        node.productIdentifier = productIdentifier
        return node
    }
}
