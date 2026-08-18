import Foundation

@main
struct GatewayForceClearSpacesContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 9 else {
            fatalError(
                "Expected API, NetworkRequest, Gateway VC, GatewayModel, Database, Cloud manager, English, and Chinese paths"
            )
        }

        let api = try source(arguments[1])
        let networkRequest = try source(arguments[2])
        let gatewayController = try source(arguments[3])
        let gatewayModel = try source(arguments[4])
        let database = try source(arguments[5])
        let cloudManager = try source(arguments[6])
        let english = try source(arguments[7])
        let chinese = try source(arguments[8])

        testAtomicUnbindAPI(api)
        testScopedTimeout(api: api, networkRequest: networkRequest)
        testNormalAssociatedSpacesSaveStillUsesPerSpaceUnbind(gatewayController)
        testForceClearUIAndCommit(gatewayController)
        testServerFirstDeletion(gatewayController)
        testPersistentDeletionTombstone(
            model: gatewayModel,
            database: database,
            cloudManager: cloudManager,
            gatewayController: gatewayController
        )
        testLocalization(english: english, chinese: chinese)

        print("GatewayForceClearSpacesContractTests passed")
    }

    private static func testAtomicUnbindAPI(_ api: String) {
        require(
            api.contains("case gatewayUnbindAllSpaces(gatewayId: String)"),
            "Atomic clear must have a dedicated API case"
        )
        require(
            api.contains("case .gatewayUnbindSpace, .gatewayUnbindAllSpaces:") &&
                api.contains("return \"/sitespace/sapce/gateway/unbind\""),
            "Single and all-space unbind must use the existing server endpoint"
        )
        let allSpacesParameters = substring(
            in: api,
            from: "case .gatewayUnbindAllSpaces(let gatewayId):",
            through: "//        case .gatewayRegister"
        )
        require(
            allSpacesParameters.contains("[\"gatewayId\": gatewayId, \"userId\": UserData.currentUserId]") &&
                !allSpacesParameters.contains("spaceId"),
            "Atomic clear request body must completely omit spaceId"
        )
    }

    private static func testScopedTimeout(api: String, networkRequest: String) {
        let timeout = substring(
            in: api,
            from: "var requestTimeoutInterval: TimeInterval",
            through: "var declaredContentEncodingGzip"
        )
        require(
            timeout.contains("case .gatewayUnbindAllSpaces, .gatewayDelete:") &&
                timeout.contains("return 30") &&
                timeout.contains("default:") &&
                timeout.contains("return 10"),
            "Only destructive Gateway APIs should receive the 30 second target timeout"
        )
        require(
            networkRequest.contains("NetworkRequestTimeoutPlugin()") &&
                networkRequest.contains("func prepare(_ request: URLRequest, target: TargetType)") &&
                networkRequest.contains("request.timeoutInterval = api.requestTimeoutInterval"),
            "Moya plugin must apply timeout by API target, not shared URL path"
        )
        require(
            networkRequest.contains("maximumDuration: TimeInterval") &&
                networkRequest.contains("NetworkTimedRequestGate") &&
                networkRequest.contains("gate.finish(with: .failure(.requestTimeout))"),
            "The full destructive operation must have a single-completion deadline"
        )
    }

    private static func testNormalAssociatedSpacesSaveStillUsesPerSpaceUnbind(_ controller: String) {
        let normalSave = substring(
            in: controller,
            from: "private func saveAssociatedSpacesIfNeeded()",
            through: "private func showForceClearAssociatedSpacesConfirmation()"
        )
        require(
            normalSave.contains(".gatewayUnbindSpace(spaceId: space.spaceId, gatewayId: gateway.mac)") &&
                !normalSave.contains("gatewayUnbindAllSpaces"),
            "Normal association editing must continue to unbind only the removed spaces"
        )
    }

    private static func testForceClearUIAndCommit(_ controller: String) {
        require(
            controller.contains("isGatewayBluetoothOffline") &&
                controller.contains("case .disconnected = proxyConnectionStateMachine.state") &&
                controller.contains("hasAssociatedSpaces: !setGatewayModel.associatedSpaces.isEmpty"),
            "Force Clear visibility must use actual Offline plus a nonempty association list"
        )
        require(
            controller.contains("icon: UIImage(named: \"menu_clear_spaces\")") &&
                controller.contains("actions.contains(.forceClearSpaces) ? 164 : 120"),
            "Menu must use the supplied icon and expand for its English title"
        )
        let confirmation = substring(
            in: controller,
            from: "private func showForceClearAssociatedSpacesConfirmation()",
            through: "private func beginForceClearAssociatedSpaces()"
        )
        require(
            confirmation.contains("contentMinHeight: SCRYFrom(222)") &&
                confirmation.contains("tapBackgroundHide: false") &&
                confirmation.contains("titleColor: Error_Red_Color") &&
                confirmation.contains("gateway_force_clear_spaces_action"),
            "Force Clear confirmation must preserve the Figma card and destructive action styling"
        )
        let operation = substring(
            in: controller,
            from: "private func beginForceClearAssociatedSpaces()",
            through: "private func finishForceClearAssociatedSpacesWithFailure()"
        )
        require(
            operation.contains(".gatewayUnbindAllSpaces(gatewayId: self.gateway.mac)") &&
                operation.contains("self.gatewayModel.associatedSpaces.removeAll()") &&
                operation.contains("self.setGatewayModel.associatedSpaces.removeAll()") &&
                operation.contains("gateway_force_clear_spaces_success") &&
                operation.contains("appearance: .siteUpdate"),
            "Server success must clear both local models and route the exact Site Update Toast"
        )
        let failure = substring(
            in: controller,
            from: "private func finishForceClearAssociatedSpacesWithFailure()",
            through: "private func verifyDestructiveOperationPermission"
        )
        require(
            failure.contains("gateway_force_clear_spaces_failed") &&
                !failure.contains("associatedSpaces.removeAll"),
            "Force Clear failure must not mutate local associations"
        )
    }

    private static func testServerFirstDeletion(_ controller: String) {
        let deletion = substring(
            in: controller,
            from: "private func beginGatewayDeletion()",
            through: "private func finishGatewayServerDeletionWithFailure"
        )
        guard let serverCall = deletion.range(of: ".gatewayDelete(gatewayId: self.gateway.mac)"),
              let resetCall = deletion.range(of: "self.resetNodeAfterServerDeletion()") else {
            fatalError("Delete flow must contain server delete and Bluetooth reset")
        }
        require(
            serverCall.lowerBound < resetCall.lowerBound,
            "gatewayDelete must complete before Bluetooth Reset starts"
        )
        require(
            deletion.contains("case .success:") &&
                deletion.contains("serverDeletionPendingLocalReset = true") &&
                !deletion.contains("mqttServerInfo = nil") &&
                !deletion.contains("associatedSpaces.removeAll") &&
                !deletion.contains("lastUploadCloudTimestamp = nil"),
            "Server success may persist only the tombstone before Reset"
        )
        let failure = substring(
            in: controller,
            from: "private func finishGatewayServerDeletionWithFailure",
            through: "/// 服务器删除成功后重置设备"
        )
        require(
            failure.contains("gateway_delete_server_failed") &&
                failure.contains("restoreCloudSynchronization") &&
                !failure.contains("resetNodeAfterServerDeletion"),
            "Server failure must restore prior sync intent, show the fixed Toast, and never Reset"
        )
        let reset = substring(
            in: controller,
            from: "private func resetNodeAfterServerDeletion()",
            through: "/// 服务器授权绑定网关"
        )
        require(
            reset.contains("guard serverDeletionConfirmed") &&
                !reset.contains("siteGatewayDataChangedNotificaitonName") &&
                !reset.contains("gatewayDelete"),
            "Reset/Force Delete must be gated by server success and cannot re-delete or re-register"
        )
    }

    private static func testPersistentDeletionTombstone(
        model: String,
        database: String,
        cloudManager: String,
        gatewayController: String
    ) {
        require(
            model.contains("var serverDeletionPendingLocalReset: Bool") &&
                model.contains("var isServerDeletionInProgress: Bool = false") &&
                model.contains("serverDeletionPendingLocalReset: Bool = false") &&
                model.contains("serverDeletionPendingLocalReset: self.serverDeletionPendingLocalReset"),
            "Gateway model and edit copy must retain the deletion tombstone"
        )
        require(
            database.contains("Expression<Bool>(\"serverDeletionPendingLocalReset\")") &&
                database.contains("addColumn(ExpressionKey.serverDeletionPendingLocalReset, defaultValue: false)") &&
                database.contains("ExpressionKey.serverDeletionPendingLocalReset <- self.serverDeletionPendingLocalReset"),
            "Tombstone must migrate, load, and save in the Gateway table"
        )
        require(
            cloudManager.contains("gateway.serverDeletionPendingLocalReset") &&
                cloudManager.contains("state = .cancel"),
            "Cloud synchronization must stop tombstoned Gateway registration"
        )
        require(
            gatewayController.contains("cancelSynchronizationHandle(") &&
                gatewayController.contains("getGatewayCurrentSyncState") &&
                gatewayController.contains("isServerDeletionInProgress = true") &&
                gatewayController.contains("waitForInFlightAuthorizationToFinish") &&
                gatewayController.contains("restoreCloudSynchronization"),
            "Delete must block new registration, drain the in-flight request, and restore sync only when server deletion fails"
        )
        let deletionStart = substring(
            in: gatewayController,
            from: "private func beginGatewayDeletion()",
            through: "private func finishGatewayServerDeletionWithFailure"
        )
        guard let pendingReset = deletionStart.range(
            of: "if gatewayModel.serverDeletionPendingLocalReset"
        ), let permissionCheck = deletionStart.range(
            of: "verifyDestructiveOperationPermission"
        ) else {
            fatalError("A persisted server deletion must resume local Reset")
        }
        require(
            pendingReset.lowerBound < permissionCheck.lowerBound &&
                deletionStart.contains("resetNodeAfterServerDeletion()"),
            "A retained tombstone must retry local Reset without querying the deleted Gateway"
        )
    }

    private static func testLocalization(english: String, chinese: String) {
        require(
            english.contains("\"gateway_force_clear_spaces_success\" = \"All associated spaces cleared from server\";") &&
                english.contains("\"gateway_force_clear_spaces_failed\" = \"Failed to clear all associated spaces\";") &&
                english.contains("\"gateway_delete_server_failed\" = \"Failed to delete gateway from server\";"),
            "English success/failure copy must match the confirmed strings exactly"
        )
        let keys = [
            "gateway_force_clear_spaces",
            "gateway_force_clear_spaces_title",
            "gateway_force_clear_spaces_message",
            "gateway_force_clear_spaces_action",
            "gateway_force_clear_spaces_success",
            "gateway_force_clear_spaces_failed",
            "gateway_delete_server_failed"
        ]
        require(
            keys.allSatisfy { chinese.contains("\"\($0)\" = ") },
            "All new user-visible copy must include Simplified Chinese localization"
        )
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func substring(
        in text: String,
        from start: String,
        through end: String
    ) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(
                of: end,
                range: startRange.upperBound..<text.endIndex
              ) else {
            return ""
        }
        return String(text[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }
}
