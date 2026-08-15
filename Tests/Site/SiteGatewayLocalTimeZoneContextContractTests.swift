import Foundation

@main
struct SiteGatewayLocalTimeZoneContextContractTests {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            fatalError("Expected local context and Gateway model paths")
        }
        let context = try String(
            contentsOfFile: arguments[1],
            encoding: .utf8
        )
        let gatewayModel = try String(
            contentsOfFile: arguments[2],
            encoding: .utf8
        )

        require(
            context.contains("enum SiteGatewayLocalTimeZoneContextBuilder") &&
                context.contains("GatewayModel.load(siteId: site.id)") &&
                context.contains("MeshNetwork.load(") &&
                context.contains("meshUUID: site.meshUUID") &&
                context.contains("subnetworkId: site.meshNetworkId") &&
                context.contains("gateway.resolveNode(in: meshNetwork)") &&
                context.contains("site.canConfigureGateway(gateway)") &&
                context.contains("node?.timezone?.secondsFromGMT()") &&
                context.contains("$0 / 60") &&
                context.contains("SiteGatewayLocalTimeZoneTargetBuilder.build("),
            "Edit Site must build Gateway timezone targets directly from the local database, primary Mesh Node, and shared permission boundary"
        )

        let permission = section(
            gatewayModel,
            from: "func canConfigureGateway(_ gateway: GatewayModel) -> Bool",
            to: "/// 网关space数据"
        )
        require(
            permission.contains("if permission == .owner") &&
                permission.contains("return true") &&
                permission.contains("$0.canEditing") &&
                permission.contains("$0.deviceOperates.contains(.edit)") &&
                permission.contains("gateway.associatedSpaces.isEmpty") &&
                permission.contains("effectiveEditableSpaceIds.contains($0.spaceId)"),
            "The shared Gateway permission must keep Owner-all and effective Editor-Space behavior"
        )

        print("SiteGatewayLocalTimeZoneContextContractTests passed")
    }

    private static func section(
        _ source: String,
        from start: String,
        to end: String
    ) -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(
                of: end,
                range: startRange.upperBound..<source.endIndex
              ) else {
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
