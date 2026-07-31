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
        let proxyDeletionSource = section(
            in: syncDevicesSource,
            from: "case .deleteSwitchProxy(let switchData):",
            to: "case .syncSwitchs(let switchDatas):"
        )
        require(
            proxyDeletionSource.contains("deleteSteps.append(step)"),
            "Proxy cleanup must remain a group unsubscription dependency"
        )
        require(
            !proxyDeletionSource.contains("nonBlockingGroupExitSteps.append(step)"),
            "Proxy cleanup must not be excluded from group unsubscription dependencies"
        )

        let groupExitDependencies = section(
            in: syncDevicesSource,
            from: "if let step = removeGroupStep {",
            to: "if let initStep = initializeStepModel {"
        )
        require(
            groupExitDependencies.contains(
                "step.relevanceStepModels = deleteSteps.filter { dependencyStep in"
            ),
            "Real group unsubscription must derive dependencies from prior cleanup steps"
        )
        require(
            groupExitDependencies.contains("dependencyStep != step"),
            "Group unsubscription must not depend on itself"
        )
        require(
            groupExitDependencies.contains(
                "!nonBlockingGroupExitSteps.contains(where:"
            )
                && groupExitDependencies.contains("$0 === dependencyStep"),
            "Only explicitly non-blocking cleanup steps may be excluded from group unsubscription dependencies"
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

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) -> String {
        guard
            let startRange = source.range(of: startMarker),
            let endRange = source.range(
                of: endMarker,
                range: startRange.upperBound..<source.endIndex
            )
        else {
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
