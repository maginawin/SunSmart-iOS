import Foundation

@main
struct GatewayTimeInformationRuntimeContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        require(arguments.count == 3, "Expected coordinator and project file paths")
        let source = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let project = try String(contentsOfFile: arguments[2], encoding: .utf8)

        require(source.contains("currentProxyReadyContext"), "Read must require Proxy Ready")
        require(source.contains("currentProxy?.nodeAddress"), "Read must match the current direct Proxy")
        require(source.contains("TimeGet()"), "Information must send TimeGet")
        require(source.contains("node.timeModel"), "TimeGet must use the actual Time Server Model")
        require(!source.contains("TimeSet("), "Information coordinator must never send TimeSet")
        require(
            source.contains("GatewayCloudSyncGenerationPolicy.next"),
            "Gateway generation policy must be reused"
        )
        require(
            source.contains(".syncGateway(gateway: gatewayModel, node: node)"),
            "Gateway Register must update only the Cloud gateway snapshot"
        )
        require(!source.contains("site.timezone"), "Information must not read or mutate Site timezone")
        require(
            occurrences(of: "GatewayTimeInformationCoordinator.swift", in: project) >= 9,
            "Coordinator must have one file reference and four target build memberships"
        )

        print("GatewayTimeInformationRuntimeContractTests passed")
    }

    private static func occurrences(of value: String, in source: String) -> Int {
        source.components(separatedBy: value).count - 1
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
        }
    }
}
