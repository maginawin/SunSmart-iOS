import Foundation

@main
struct GatewayMultiRoleConsistencyContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 10 else {
            fatalError(
                "Expected import, database, gateway model, gateway controller, picker, node sync, cloud manager, English, and Chinese paths"
            )
        }

        let importSource = try source(CommandLine.arguments[1])
        let databaseSource = try source(CommandLine.arguments[2])
        let modelSource = try source(CommandLine.arguments[3])
        let controllerSource = try source(CommandLine.arguments[4])
        let pickerSource = try source(CommandLine.arguments[5])
        let nodeSyncSource = try source(CommandLine.arguments[6])
        let cloudSource = try source(CommandLine.arguments[7])
        let english = try source(CommandLine.arguments[8])
        let chinese = try source(CommandLine.arguments[9])

        require(
            importSource.contains("GatewayCloudConfigurationPatch") &&
                importSource.contains("case .mergeFields:") &&
                !importSource.contains("cacheGateway.update(gatewayModel: remoteGateway)"),
            "Clean cached Gateways must apply a presence-aware response patch"
        )
        require(
            modelSource.contains("registrationProtectionSnapshot") &&
                databaseSource.contains("registrationProtectionSnapshot") &&
                databaseSource.contains("GatewayRegistrationProtectionSnapshot(data:"),
            "The sanitized registration snapshot must survive Gateway database reloads"
        )
        require(
            importSource.contains("if gatewaySnapshot.isComplete") &&
                importSource.contains("Editor/Visitor缺失项不能用于删除本地Node"),
            "Only a complete Owner Gateway snapshot may delete a missing local Gateway"
        )
        require(
            modelSource.contains("var canEditGatewayAssociation: Bool") &&
                modelSource.contains("canEditing && deviceOperates.contains(.edit)") &&
                modelSource.contains("func updatePermission(from space: SpaceData?)"),
            "Gateway Space editability must have one shared permission definition"
        )
        require(
            controllerSource.contains("GatewayAssociatedSpaceMutationPolicy.resolve") &&
                controllerSource.contains("reconcileAssociatedSpacesAfterPartialSave") &&
                controllerSource.contains("applyAuthoritativeAssociatedSpaces"),
            "Gateway SAVE must revalidate and reconcile association mutations"
        )
        require(
            pickerSource.contains("let selectedSpaces = bindSpaces.sorted"),
            "Associated Spaces picker must select the latest server bindings, including locked associations"
        )
        require(
            nodeSyncSource.contains("GatewaySubnetAppKeyIndexPolicy") &&
                nodeSyncSource.contains("gateway.associatedSpaces.map(\\.appKeyIndex)"),
            "Devices-not-synced comparison must use the complete associated-space indexes"
        )
        require(
            cloudSource.contains("GatewayRegistrationPayloadPolicy") &&
                cloudSource.contains("registrationProtectionSnapshot?.nodeData"),
            "Gateway register must use the persisted opaque association snapshot"
        )
        require(
            english.contains("\"gateway_associated_spaces_changed_message\" = ") &&
                chinese.contains("\"gateway_associated_spaces_changed_message\" = "),
            "Association topology-change feedback must be localized in English and Simplified Chinese"
        )

        print("GatewayMultiRoleConsistencyContractTests passed")
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
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
