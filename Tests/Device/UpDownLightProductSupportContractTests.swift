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
        precondition(SunricherProductCapabilityPolicy.isExternalLightSensorCapableLuminaire(companyIdentifier: 0x0A78, productIdentifier: 0x2491))
        precondition(SunricherProductCapabilityPolicy.isExternalLightSensorCapableLuminaire(companyIdentifier: 0x0A78, productIdentifier: 0x2321))
        precondition(!SunricherProductCapabilityPolicy.isExternalLightSensorCapableLuminaire(companyIdentifier: 0x1234, productIdentifier: 0x2321))
    }

    private static func testMotionSensitivityExclusion() {
        precondition(SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x0A78, productIdentifier: 0x2491))
        precondition(SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x0A78, productIdentifier: 0x2321))
        precondition(!SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x0A78, productIdentifier: 0x24A1))
        precondition(!SunricherProductCapabilityPolicy.isMotionSensitivityUnsupported(companyIdentifier: 0x1234, productIdentifier: 0x2321))
    }

    private static func makeNode(companyIdentifier: UInt16, productIdentifier: UInt16) -> Node {
        let node = Node()
        node.companyIdentifier = companyIdentifier
        node.productIdentifier = productIdentifier
        return node
    }
}
