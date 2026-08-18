import Foundation

@main
struct GatewayRecoveryAssociatedSpacesContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            fatalError("Expected SyncDevicesViewController source path")
        }

        let controller = try String(
            contentsOfFile: arguments[1],
            encoding: .utf8
        )
        let recoveryBuilder = substring(
            in: controller,
            from: "private func makeGatewayRecoveryDeviceModel(",
            through: "/// 返回"
        )

        require(
            recoveryBuilder.contains("let desiredAppKeyIndexes = Set(") &&
                recoveryBuilder.contains("node.networkKeys") &&
                recoveryBuilder.contains(".filter { networkKey in") &&
                recoveryBuilder.contains("networkKey.isSecondary") &&
                recoveryBuilder.contains("!desiredAppKeyIndexes.contains(networkKey.index)"),
            "Gateway Recovery must derive obsolete secondary keys from actual Gateway state"
        )
        require(
            recoveryBuilder.contains("type: .gatewayUnbindAssociatedSpace(") &&
                recoveryBuilder.contains("type: \"unbind_associated_spaces\".localizedString"),
            "Gateway Recovery must create the existing per-Space unbind tasks"
        )
        require(
            recoveryBuilder.contains("associationMutationSteps.append(step)") &&
                recoveryBuilder.contains(
                    "syncSpacesStep.relevanceStepModels = [initializeStep] + associationMutationSteps"
                ),
            "Sync Spaces must wait for all associated-Space additions and removals"
        )
        require(
            recoveryBuilder.contains("verificationStep.relevanceStepModels = steps"),
            "Verify Configuration must wait for every recovery step, including removals"
        )

        print("GatewayRecoveryAssociatedSpacesContractTests passed")
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
