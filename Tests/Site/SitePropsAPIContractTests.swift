import Foundation

@main
struct SitePropsAPIContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 || arguments.count == 5 else {
            fatalError("Expected API paths, optionally followed by coordinator and cloud manager")
        }

        let target = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let client = try String(contentsOfFile: arguments[2], encoding: .utf8)

        require(
            target.contains("case sitePropsRetrieve(siteId: String)") &&
                target.contains("case sitePropsUpdate(siteId: String, props: [String: Any])"),
            "The network target must expose retrieve and partial update cases"
        )
        require(
            target.contains("return \"/sitespace/retrieve/siteprops\"") &&
                target.contains("return \"/sitespace/update/siteprops\""),
            "Site props paths must match the server contract"
        )
        require(
            target.contains("case .sitePropsRetrieve: return \"sitePropsRetrieve\"") &&
                target.contains("case .sitePropsUpdate: return \"sitePropsUpdate\""),
            "Diagnostics must identify both new requests"
        )

        require(
            target.contains("\"timezone\": NSNull()") &&
                target.contains("\"imageId\": NSNull()") &&
                target.contains("\"siteName\": NSNull()") &&
                target.contains("\"updateTimestamp\": NSNull()"),
            "Retrieve props must request all four fields with JSON null"
        )
        require(
            target.contains("case .sitePropsRetrieve(let siteId):") &&
                target.contains("return [\"userId\": UserData.currentUserId, \"siteId\": siteId, \"props\": props]") &&
                target.contains("case .sitePropsUpdate(let siteId, let props):"),
            "New request bodies must use userId/siteId/props at the root"
        )
        require(
            target.contains("return .requestParameters(parameters: requestParameters, encoding: JSONEncoding.default)"),
            "Site props requests must use regular JSONEncoding"
        )

        require(
            client.contains("protocol SitePropsAPIClientProtocol") &&
                client.contains("func retrieve(siteId: String) async -> Result<SitePropsRemoteSnapshot, NetworkApiError>") &&
                client.contains("func update(snapshot: SitePropsUpdateSnapshot) async -> Result<SitePropsRemoteSnapshot, NetworkApiError>"),
            "The API client must expose testable retrieve/update operations"
        )
        require(
            client.contains("var props: [String: Any] = [\"updateTimestamp\": snapshot.timestamp]") &&
                client.contains("snapshot.fields.contains(.siteName)") &&
                client.contains("snapshot.fields.contains(.imageId)") &&
                client.contains("snapshot.fields.contains(.timezone)"),
            "Update must always send timestamp and include only masked optional fields"
        )
        require(
            client.contains("providedFields.insert(.siteName)") &&
                client.contains("providedFields.insert(.imageId)") &&
                client.contains("providedFields.insert(.timezone)"),
            "Response parsing must track which optional props were actually provided"
        )
        require(
            client.contains("SiteTimeZoneValue(storageValue: timezoneString)") &&
                client.contains("guard let timestamp = int64Value"),
            "Responses must validate full timezone and updateTimestamp"
        )

        let headersSwitch = substring(
            in: target,
            from: "var headers: [String : String]?",
            through: "return headers"
        )
        require(
            !headersSwitch.contains("sitePropsRetrieve") &&
                !headersSwitch.contains("sitePropsUpdate"),
            "New JSON requests must not enter the legacy gzip header branch"
        )

        if arguments.count == 5 {
            let coordinator = try String(contentsOfFile: arguments[3], encoding: .utf8)
            let cloudManager = try String(contentsOfFile: arguments[4], encoding: .utf8)

            require(
                coordinator.contains("@MainActor") &&
                    coordinator.contains("final class SitePropsEditCoordinator") &&
                    coordinator.contains("await apiClient.retrieve(siteId: site.id)") &&
                    coordinator.contains("SitePropsEditPolicy.mergeRetrieve"),
                "Coordinator prepare must await retrieve and delegate merge policy"
            )
            require(
                coordinator.contains("SitePropsEditPolicy.makeUpdateSnapshot") &&
                    coordinator.contains("site.pendingSitePropsMask = state.pending.fields") &&
                    coordinator.contains("site.pendingSitePropsTimestamp = state.pending.timestamp") &&
                    coordinator.contains("guard site.save() else"),
                "Coordinator persist must save values/version/pending before submit"
            )
            require(
                coordinator.contains("SitePropsEditPolicy.updateResponseMatches") &&
                    coordinator.contains("SitePropsEditPolicy.localStateAfterSuccessfulUpdate") &&
                    coordinator.contains("await apiClient.update(snapshot: snapshot)"),
                "Coordinator submit must validate the immutable response snapshot before cleanup"
            )
            require(
                coordinator.contains("func currentState() -> SitePropsLocalState") &&
                    coordinator.contains("func persistState(_ state: SitePropsLocalState) -> Bool"),
                "Site entry and Edit Site must share one state persistence boundary"
            )
            require(
                coordinator.contains("private func apply(_ state: SitePropsLocalState)"),
                "Raw state application must remain private so callers cannot bypass rollback"
            )
            require(
                !coordinator.contains("CloudSynchronizationManager") &&
                    !cloudManager.contains("pendingSitePropsMask") &&
                    !cloudManager.contains("pendingSitePropsTimestamp"),
                "Edit props pending must not change whole-site synchronization routing"
            )
        }

        print("SitePropsAPIContractTests passed")
    }

    private static func substring(in text: String, from start: String, through end: String) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.lowerBound..<text.endIndex) else {
            return ""
        }
        return String(text[startRange.lowerBound..<endRange.upperBound])
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
