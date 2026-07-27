import Foundation

@main
struct KineticSwitchProxyTransactionContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 7 else {
            fatalError("Expected Group Members, Node sync, Sync Devices, sync model, English and Chinese localization paths")
        }

        let groupMembersSource = try source(at: CommandLine.arguments[1])
        let nodeSyncSource = try source(at: CommandLine.arguments[2])
        let syncDevicesSource = try source(at: CommandLine.arguments[3])
        let syncModelSource = try source(at: CommandLine.arguments[4])
        let englishStrings = try source(at: CommandLine.arguments[5])
        let chineseStrings = try source(at: CommandLine.arguments[6])

        require(
            groupMembersSource.contains("groupMemberProxyRemovalPlans"),
            "Group Members must preflight proxy removals before changing state"
        )
        require(
            groupMembersSource.contains("\"group_remove_switch_proxy_confirmation\".localizedString"),
            "Group Members must confirm the proxy impact before continuing"
        )
        require(
            nodeSyncSource.contains("guard groupState != .exitFailure else"),
            "A node exiting its group must not recreate switch bindings"
        )
        require(
            syncDevicesSource.contains("step.relevanceStepModels = deleteSteps.filter({ $0 != step })"),
            "Real group unsubscription must depend on prior cleanup steps"
        )
        require(
            syncDevicesSource.contains("proxyConfigurationStep.relevanceStepModels = [proxyDeletionStep]"),
            "A replacement proxy must not be configured before the previous proxy is removed"
        )
        require(
            syncDevicesSource.contains("section.switchProxy?.deviceModel.parentSectionIndex = index"),
            "A failed proxy operation must remain selectable for retry"
        )
        require(
            syncModelSource.contains("models.append(contentsOf: model.deviceModel.steps)"),
            "Proxy steps must participate in sync state and retry aggregation"
        )
        require(
            englishStrings.contains("\"group_remove_switch_proxy_confirmation\""),
            "English proxy removal confirmation is required"
        )
        require(
            chineseStrings.contains("\"group_remove_switch_proxy_confirmation\""),
            "Chinese proxy removal confirmation is required"
        )

        print("KineticSwitchProxyTransactionContractTests passed")
    }

    private static func source(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
