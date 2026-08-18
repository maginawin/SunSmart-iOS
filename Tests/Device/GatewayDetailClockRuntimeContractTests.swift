import Foundation

@main
struct GatewayDetailClockRuntimeContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        require(arguments.count == 8, "Expected coordinator, controller, WiFi controller, project, localization, and loading asset paths")
        let coordinator = try read(arguments[1])
        let controller = try read(arguments[2])
        let wifiController = try read(arguments[3])
        let project = try read(arguments[4])
        let english = try read(arguments[5])
        let chinese = try read(arguments[6])
        let loadingAsset = try read(arguments[7])

        require(coordinator.contains("currentProxyReadyContext"), "Clock operations must require Proxy Ready")
        require(coordinator.contains("currentProxy?.nodeAddress"), "Clock operations must target the direct Gateway Proxy")
        require(coordinator.contains("node.timeModel"), "TimeGet must require Time Server")
        require(coordinator.contains("node.timeSetupModel"), "TimeSet must require Time Setup Server")
        require(coordinator.contains("ConfigModelAppBind"), "Missing Time Model bindings must be configured")
        require(coordinator.contains("Node.setLocalTimeMessage"), "Clock sync must construct TimeSet with the target timezone")
        require(coordinator.contains("TimeGet()"), "Clock sync must perform final TimeGet readback")
        require(coordinator.contains("isVerifiedSync"), "Final readback must enforce offset and tolerance")
        require(coordinator.contains("restore(backup)"), "Failures must restore the previous persisted sample")

        require(controller.contains("isGatewayProxyReady"), "Clock sections must depend on direct Proxy Ready")
        require(controller.contains("timeInterval: 0.5"), "Clock rows must refresh every 0.5 seconds")
        require(controller.contains("GatewayDetailClockCore.gatewayDisplayDate"), "Gateway ticks must derive from Local and the stored offset")
        require(controller.contains("gateway_time_zone_sync_unknown_message"), "Unknown Gateway timezone must use dedicated prompt copy")
        require(
            coordinator.contains("struct GatewayClockAutoPromptState"),
            "Automatic prompt repetition must be controlled by a testable session state"
        )
        require(
            controller.contains("readGatewayClock(autoPromptSessionID: context.sessionID)"),
            "The first Proxy Ready TimeGet must carry the session into automatic prompt evaluation"
        )
        require(
            controller.contains("gatewayClockAutoPromptState.request"),
            "The completed TimeGet must request the automatic prompt from requiresSync"
        )
        require(
            controller.contains("gatewayClockAutoPromptState.shouldPresent"),
            "Automatic presentation must pass the session eligibility gate"
        )
        require(
            controller.contains("SRAlertView.getCurrentAlertView() != nil"),
            "An automatic timezone prompt must not replace an existing alert"
        )
        require(
            controller.contains("markCurrentGatewayClockSessionHandled()"),
            "Manual prompt and synchronization actions must suppress duplicate automatic prompts"
        )
        require(
            controller.contains("var timeZoneSyncDidFinish: ((String, Int) -> Void)?") &&
                controller.contains("self.timeZoneSyncDidFinish?(") &&
                controller.contains("value.0.offsetMinutes"),
            "A verified Gateway clock sync must publish its Gateway ID and readback offset to the source page"
        )
        require(
            controller.contains("var gatewayPageDidClose: (() -> Void)?") &&
                controller.contains("let completion = gatewayPageDidClose") &&
                controller.contains("completion?()"),
            "Explicit Gateway dismissal must notify the source page after the modal closes"
        )
        require(controller.contains("appearance: .siteUpdate"), "Sync result must reuse Edit Site toast appearance")
        require(
            controller.contains("remainingSyncPresentationDuration"),
            "Sync completion must preserve the minimum Syncing presentation duration"
        )
        require(
            controller.contains("make.height.equalTo(28)"),
            "Sync clock button height must be fixed at 28 points"
        )
        require(
            controller.contains("actionButton.layer.cornerRadius = 10"),
            "Sync clock button corner radius must be fixed at 10 points"
        )
        require(
            controller.contains("pendingGatewayClockSync"),
            "A click during the initial TimeGet must stay Syncing until synchronization can start"
        )
        require(
            controller.contains("updateSyncingAppearance(isSyncing: true)"),
            "The tapped button must enter Syncing appearance immediately"
        )
        require(
            controller.contains("UIImage(named: \"site_entry_sync_loading\")"),
            "Syncing appearance must use the current shared loading asset"
        )
        require(
            controller.contains("UIAccessibility.isReduceMotionEnabled"),
            "Loading animation must respect Reduce Motion"
        )
        require(
            controller.contains("CABasicAnimation(keyPath: \"transform.rotation.z\")"),
            "Loading icon must rotate while synchronization is active"
        )
        require(
            controller.contains("contentStack.spacing = 6"),
            "Loading icon and Syncing text must keep the Figma 6-point gap"
        )
        require(
            controller.contains("make.size.equalTo(24)"),
            "Loading icon must use the Figma 24-point container"
        )
        require(
            controller.contains("make.size.equalTo(16)"),
            "Loading glyph must use the Figma 16-point visible size"
        )
        require(
            controller.contains("for row in 0..<2"),
            "Clock ticking must not recreate the animated action row"
        )
        require(wifiController.contains("super.gatewayProxyReadyStateDidUpdate(isReady)"), "WiFi Gateway must preserve shared clock visibility logic")
        require(wifiController.contains("super.gatewayProxyDidBecomeReady(context)"), "WiFi Gateway must preserve shared initial TimeGet")
        require(
            occurrences(of: "GatewayDetailClockCoordinator.swift", in: project) >= 9,
            "Clock coordinator must have one file reference and four target memberships"
        )

        let localizationKeys = [
            "gateway_sync_required",
            "gateway_sync_clock",
            "gateway_clock_syncing",
            "gateway_time_zone_sync_title",
            "gateway_clock_synced",
            "gateway_clock_sync_failed"
        ]
        for key in localizationKeys {
            require(english.contains("\"\(key)\""), "English localization missing \(key)")
            require(chinese.contains("\"\(key)\""), "Chinese localization missing \(key)")
        }

        require(loadingAsset.contains("width=\"42\" height=\"42\""), "Shared loading asset must preserve its source geometry")
        require(loadingAsset.contains("opacity=\"0.3\""), "Loading asset must preserve the Figma track opacity")
        require(loadingAsset.contains("stroke=\"#6667AB\""), "Loading asset must preserve the Figma theme color")

        print("GatewayDetailClockRuntimeContractTests passed")
    }

    private static func read(_ path: String) throws -> String {
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
