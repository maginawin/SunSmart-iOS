import Foundation

@main
struct LightTimeInformationRuntimeContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        require(arguments.count == 6, "Expected coordinator, light controller, information controller, SDK and project paths")
        let coordinator = try source(at: arguments[1])
        let lightController = try source(at: arguments[2])
        let informationController = try source(at: arguments[3])
        let sdkManager = try source(at: arguments[4])
        let project = try source(at: arguments[5])

        require(coordinator.contains("node.timeModel"), "Capability must come from the actual Time Server Model")
        require(coordinator.contains("ensureLocalTimeClientModelBinding"), "Local Time Client binding must be repaired")
        require(coordinator.contains("ConfigModelAppBind"), "Remote Time Server binding must be repairable")
        require(coordinator.contains("canConfigureTimeServer"), "Remote binding must be permission-aware")
        require(coordinator.contains("ConfigModelAppStatus"), "Binding must validate the typed status")
        require(coordinator.contains("status.applicationKeyIndex == applicationKey.index"), "Binding must validate AppKey")
        require(coordinator.contains("status.elementAddress == model.parentElement?.unicastAddress"), "Binding must validate the actual Element")
        require(coordinator.contains("TimeGet()"), "A supported light must send TimeGet")
        require(!coordinator.contains("TimeSet("), "Light Information must remain read-only")
        require(!coordinator.contains("ConfigModelAppUnbind"), "A completed remote binding must not be rolled back")
        require(!coordinator.contains("syncGateway"), "Light Information must not trigger Gateway cloud sync")
        require(
            coordinator.contains("isMeshNetworkConnected")
                && !coordinator.contains("addObserver")
                && !coordinator.contains("publisher(for:"),
            "A disconnected page must wait for a user retry instead of observing Mesh reconnection"
        )

        require(
            lightController.contains("LightTimeInformationContext(")
                && lightController.contains("canConfigureTimeServer: space.deviceOperates.contains(.edit)"),
            "Only the Light detail entry may inject its permission-aware context"
        )
        require(
            informationController.contains("lightTimeContext: LightTimeInformationContext? = nil"),
            "Shared Information callers must remain opted out by default"
        )
        require(
            informationController.contains("if lightTimeContext != nil")
                && informationController.contains("\"not_supported\".localizedString"),
            "Unsupported lights must show both rows with localized Not supported values"
        )
        require(
            informationController.contains("\"device_offline_message\".localizedString"),
            "A disconnected light must show the localized offline Toast"
        )
        require(
            informationController.contains("lightTimeCoordinator?.finishPage()"),
            "Leaving the page must detach the Light coordinator"
        )

        require(
            sdkManager.contains(".timeClientModelId")
                && sdkManager.contains("public func ensureLocalTimeClientModelBinding() -> Bool"),
            "SDK must expose an idempotent local Time Client repair"
        )
        require(
            occurrences(of: "LightTimeInformationCoordinator.swift", in: project) >= 9,
            "The coordinator needs one file reference and four target memberships"
        )

        print("LightTimeInformationRuntimeContractTests passed")
    }

    private static func source(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
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
