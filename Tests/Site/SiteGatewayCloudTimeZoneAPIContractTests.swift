import Foundation

@main
struct SiteGatewayCloudTimeZoneAPIContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 5 else {
            fatalError("Expected network target, parser, API client, and coordinator source paths")
        }

        let target = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let parser = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let client = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
        let coordinator = try String(contentsOfFile: CommandLine.arguments[4], encoding: .utf8)

        testNetworkTargetContract(in: target)
        testAPIBoundaryContract(in: coordinator, client: client)
        testClientUsesTheResponseParser(parser: parser, client: client)
        testStatusRequestRejectsNonPositiveIDsBeforeSending(in: client)
        print("SiteGatewayCloudTimeZoneAPIContractTests passed")
    }

    private static func testNetworkTargetContract(in target: String) {
        require(
            target.contains("case gatewayDateTimeUpdate(siteId: String, gateways: [String])") &&
                target.contains("case gatewayDateTimeRequestStatus(requestId: Int64)"),
            "The network target must expose the update and request-status cases"
        )
        require(
            target.contains("case .gatewayDateTimeUpdate: return \"gatewayDateTimeUpdate\"") &&
                target.contains("case .gatewayDateTimeRequestStatus: return \"gatewayDateTimeRequestStatus\""),
            "Diagnostics must identify both Gateway time-zone requests"
        )
        require(
            target.contains("case .gatewayDateTimeUpdate:") &&
                target.contains("return \"/sitespace/gateway/datetime/update\"") &&
                target.contains("case .gatewayDateTimeRequestStatus:") &&
                target.contains("return \"/sitespace/request/status\""),
            "Both Gateway time-zone endpoints must use their exact POST paths"
        )
        require(
            target.contains("var method: Moya.Method") && target.contains("return .post"),
            "Gateway time-zone endpoints must use the target's POST method"
        )

        let updateBranch = substring(
            in: target,
            from: "case .gatewayDateTimeUpdate(let siteId, let gateways):",
            through: "case .gatewayDateTimeRequestStatus(let requestId):"
        )
        let statusBranch = substring(
            in: target,
            from: "case .gatewayDateTimeRequestStatus(let requestId):",
            through: "}\n    }\n    \n    var task"
        )

        require(
            updateBranch.contains("return [\"siteId\": siteId, \"gateways\": gateways]") &&
                !updateBranch.contains("UserData.currentUserId") &&
                !updateBranch.contains("timezone") &&
                !updateBranch.contains("token"),
            "Update payload must contain only siteId and gateways, without user or auth fields"
        )
        require(
            statusBranch.contains("return [\"requestId\": requestId]") &&
                !statusBranch.contains("UserData.currentUserId") &&
                !statusBranch.contains("timezone") &&
                !statusBranch.contains("token"),
            "Status payload must contain only requestId, without user or auth fields"
        )
    }

    private static func testAPIBoundaryContract(in coordinator: String, client: String) {
        require(
            coordinator.contains("protocol SiteGatewayCloudTimeZoneAPI") &&
                coordinator.contains("func submit(siteID: String, gatewayMACs: [String]) async throws -> Int64") &&
                coordinator.contains("func statuses(") &&
                coordinator.contains("requestID: Int64") &&
                coordinator.contains("async throws -> [SiteGatewayCloudTimeZoneRemoteStatusSnapshot]"),
            "Coordinator source must own a replaceable asynchronous Gateway time-zone API protocol"
        )
        require(
            client.contains("enum SiteGatewayCloudTimeZoneAPIClientError: Error") &&
                client.contains("case invalidRequestID") &&
                client.contains("case invalidStatusResponse") &&
                client.contains("struct SiteGatewayCloudTimeZoneAPIClient: SiteGatewayCloudTimeZoneAPI"),
            "The production adapter must expose parser-specific failures and conform to the API protocol"
        )
        require(
            client.contains("case .failure(let error):") && client.contains("throw error"),
            "The adapter must propagate NetworkRequest failures as NetworkApiError"
        )
    }

    private static func testClientUsesTheResponseParser(parser: String, client: String) {
        require(
            parser.contains("static func parseRequestID") &&
                parser.contains("static func parseStatuses"),
            "The API boundary requires the concrete response parser"
        )
        require(
            client.contains(".gatewayDateTimeUpdate(siteId: siteID, gateways: gatewayMACs)") &&
                client.contains(".gatewayDateTimeRequestStatus(requestId: requestID)") &&
                client.contains("SiteGatewayCloudTimeZoneResponseParser.parseRequestID") &&
                client.contains("SiteGatewayCloudTimeZoneResponseParser.parseStatuses"),
            "The API client must send both targets and parse only successful dictionaries through the parser"
        )
    }

    private static func testStatusRequestRejectsNonPositiveIDsBeforeSending(in client: String) {
        let statuses = substring(
            in: client,
            from: "func statuses(\n        requestID: Int64",
            through: "\n    }\n}"
        )
        let guardRange = statuses.range(of: "guard requestID > 0 else {")
        let errorRange = statuses.range(of: "throw SiteGatewayCloudTimeZoneAPIClientError.invalidRequestID")
        let requestRange = statuses.range(of: ".gatewayDateTimeRequestStatus(requestId: requestID)")

        require(
            guardRange != nil &&
                errorRange != nil &&
                requestRange != nil &&
                guardRange!.lowerBound < requestRange!.lowerBound &&
                errorRange!.lowerBound < requestRange!.lowerBound,
            "Status requests must reject non-positive requestId before creating the network target"
        )
    }

    private static func substring(in text: String, from start: String, through end: String) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.lowerBound..<text.endIndex) else {
            return ""
        }
        return String(text[startRange.lowerBound..<endRange.upperBound])
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
