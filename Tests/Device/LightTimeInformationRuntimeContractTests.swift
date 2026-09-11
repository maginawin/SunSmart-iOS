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
        let sharedClock = try source(at: "SunSmart/Main/Device/InformationClockRecovery.swift")

        require(
            sharedClock.contains("status.applicationKeyIndex == self.applicationKey.index")
                && sharedClock.contains("status.elementAddress == model.parentElement?.unicastAddress")
                && sharedClock.contains("status.modelIdentifier == model.modelIdentifier")
                && sharedClock.contains("status.companyIdentifier == model.companyIdentifier"),
            "The SDK adapter must validate the complete binding response identity"
        )
        require(
            sharedClock.contains("model.parentElement?.unicastAddress")
                && sharedClock.contains("message, to: MeshAddress(destination), using: applicationKey"),
            "Clock commands must target the actual Element with the current AppKey"
        )
        require(
            sharedClock.contains("ensureLocalTimeClientModelBinding()")
                && sharedClock.contains("node.timeSetupModel")
                && sharedClock.contains("SiteTimeSetMessageFactory.resolve(node: node, at: date)"),
            "Both entries must share local-client preparation, setup capability and Site timezone resolution"
        )
        require(
            occurrences(of: "InformationClockRecovery.swift in Sources */", in: project) == 10,
            "The shared recovery must be compiled by all five brands"
        )

        require(coordinator.contains("node.timeModel"), "Capability must come from the actual Time Server Model")
        require(coordinator.contains("InformationClockRecovery(transport: transport)"), "Use the shared bounded recovery")
        require(coordinator.contains("canConfigure: context.canConfigureTimeServer"), "Recovery must use current Light permission")
        require(coordinator.contains("requiresDirectProxy: false"), "Light may use another Mesh Proxy")
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
                && lightController.contains("self?.space.deviceOperates.contains(.edit) == true"),
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
            !informationController.contains("\"device_offline_message\".localizedString"),
            "Information clock disconnection must remain silent"
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
