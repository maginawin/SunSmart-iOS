import Foundation

@main
struct SyncGatewaysUIContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 9 else {
            fatalError("Expected three views, two controllers, two localizations, and project paths")
        }

        let timeZoneCard = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let gatewayCell = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let supportingViews = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let syncController = try String(contentsOfFile: arguments[4], encoding: .utf8)
        let siteController = try String(contentsOfFile: arguments[5], encoding: .utf8)
        let english = try String(contentsOfFile: arguments[6], encoding: .utf8)
        let simplifiedChinese = try String(contentsOfFile: arguments[7], encoding: .utf8)
        let project = try String(contentsOfFile: arguments[8], encoding: .utf8)

        let allViews = timeZoneCard + gatewayCell + supportingViews
        let allConsumers = allViews + syncController + siteController
        let keys = [
            "site_sync_gateways_timezone_title_format",
            "site_sync_gateways_progress_format",
            "site_sync_gateways_gateway_fallback",
            "site_sync_gateways_onsite_title",
            "site_sync_gateways_onsite_message",
            "site_sync_gateways_nearby_title",
            "site_sync_gateways_nearby_empty",
            "site_sync_gateways_other_title",
            "site_sync_gateways_attention_single",
            "site_sync_gateways_attention_multiple",
            "site_sync_gateways_sync",
            "site_sync_gateways_syncing",
            "site_sync_gateways_retry",
            "site_sync_gateways_synced",
            "site_sync_gateways_no_signal",
            "site_sync_gateways_done",
            "site_sync_gateways_failure_toast",
            "site_sync_gateways_success_toast"
        ]

        for key in keys {
            require(
                occurrences(of: "\"\(key)\" =", in: english) == 1,
                "English must define \(key) exactly once"
            )
            require(
                occurrences(of: "\"\(key)\" =", in: simplifiedChinese) == 1,
                "Simplified Chinese must define \(key) exactly once"
            )
            require(
                allConsumers.contains("\"\(key)\".localizedString"),
                "The UI must consume \(key)"
            )
        }

        require(timeZoneCard.contains("final class SyncGatewaysTimeZoneCardView: UIView"))
        require(allViews.contains("RGB(246, 247, 251)"))
        require(timeZoneCard.contains("RGB(229, 232, 240)"))
        require(timeZoneCard.contains("RGB(104, 100, 179)"))
        require(timeZoneCard.contains("make.height.equalTo(SCRYFrom(4))"))

        require(gatewayCell.contains("final class SyncGatewayCell: UIView"))
        require(gatewayCell.contains("time-zone-sync-status-gateway"))
        require(gatewayCell.contains("gateway_sync_fail"))
        require(gatewayCell.contains("make.height.equalTo(SCRYFrom(60))"))
        require(gatewayCell.contains("make.size.equalTo(SCRYFrom(30))"))
        require(gatewayCell.contains("width: SCRXFrom(64), height: SCRYFrom(30)"))
        require(gatewayCell.contains("width: SCRXFrom(64), height: SCRYFrom(24)"))

        require(supportingViews.contains("site_entry_sync_loading"))
        require(supportingViews.contains("site_entry_sync_warning"))
        require(supportingViews.contains("final class SyncGatewaysBottomActionBar: UIView"))
        require(supportingViews.contains("make.height.equalTo(SCRYFrom(90))"))
        require(supportingViews.contains("startSearchingAnimation()"))
        require(supportingViews.contains("stopSearchingAnimation()"))

        require(syncController.contains("private func mutateState("))
        require(syncController.contains("private func render(_ state: SyncGatewaysState)"))
        require(syncController.contains("scanSession.peripheral(for:"))
        require(syncController.contains("timeSyncCoordinator.synchronize("))
        require(syncController.contains("cloudBridge.recordDeviceSuccessAndEnqueue"))
        require(syncController.contains("UIApplication.didEnterBackgroundNotification"))
        require(syncController.contains("UIApplication.willEnterForegroundNotification"))
        require(syncController.contains("transitionCoordinator.notifyWhenInteractionChanges"))
        require(syncController.contains("context.isCancelled"))
        require(syncController.contains("private func finish(reason: SyncGatewaysFinishReason)"))
        require(syncController.contains("scanSession.finish()"))
        require(syncController.contains("timeSyncCoordinator.finishPage()"))
        require(syncController.contains("appearance: .siteUpdate"))
        require(syncController.contains("position: .bottom"))

        let sourceMembership: [(String, String)] = [
            ("SiteGatewayAccessScope.swift", "160"),
            ("SyncGatewaysContext.swift", "170"),
            ("SyncGatewaysState.swift", "180"),
            ("SyncGatewaysScanSession.swift", "190"),
            ("GatewayTimeSyncCoordinator.swift", "200"),
            ("SyncGatewaysCloudBridge.swift", "210"),
            ("SyncGatewaysDirtyTimeOverride.swift", "220"),
            ("SyncGatewaysTimeZoneCardView.swift", "230"),
            ("SyncGatewayCell.swift", "240"),
            ("SyncGatewaysSupportingViews.swift", "250"),
            ("GatewayCloudSyncGenerationPolicy.swift", "260")
        ]
        for (fileName, idStem) in sourceMembership {
            require(
                occurrences(of: "/* \(fileName) in Sources */", in: project) == 8,
                "\(fileName) must belong to all four app targets"
            )
            require(
                project.contains(
                    "F260813000000000000\(idStem)0 /* \(fileName) */ = {isa = PBXFileReference"
                ) && occurrences(
                    of: "F260813000000000000\(idStem)0 /* \(fileName) */," ,
                    in: project
                ) == 1,
                "\(fileName) must have one file reference and one group entry"
            )
            for targetSuffix in 1...4 {
                require(
                    occurrences(
                        of: "F260813000000000000\(idStem)\(targetSuffix) /* \(fileName) in Sources */",
                        in: project
                    ) == 2,
                    "\(fileName) must be declared and referenced by target \(targetSuffix)"
                )
            }
        }

        print("SyncGatewaysUIContractTests passed")
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Sync gateways UI contract failed"
    ) {
        guard condition() else { fatalError(message) }
    }
}
