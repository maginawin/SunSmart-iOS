import Foundation

@main
struct SiteGatewayOnlineStateContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("Expected SiteViewController.swift and GatewayViewController.swift paths")
        }

        let source = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )
        let gatewaySource = try String(
            contentsOfFile: CommandLine.arguments[2],
            encoding: .utf8
        )

        let setupData = section(
            in: source,
            from: "private func setupData()",
            to: "/// 添加通知监听"
        )
        require(
            !setupData.contains("space.gatewayStatus ="),
            "setupData must not mutate server-owned Space gateway status"
        )

        require(
            source.contains("private func sitePrimaryMeshNetwork() -> MeshNetwork?"),
            "SiteViewController must expose an explicit Site primary-network resolver"
        )

        let loadGatewaysData = section(
            in: source,
            from: "private func loadGatewaysData()",
            to: "// MARK: - Action"
        )
        require(
            loadGatewaysData.contains("sitePrimaryMeshNetwork()"),
            "loadGatewaysData must resolve gateways from the Site primary network"
        )
        require(
            loadGatewaysData.contains("model.resolveNode(in: meshNetwork)"),
            "Gateway node resolution must receive the explicit Site primary network"
        )
        require(
            !loadGatewaysData.contains("Gateway.resolve(model:"),
            "loadGatewaysData must not use the current global Mesh network implicitly"
        )
        require(
            !loadGatewaysData.contains("isWiFiGateway"),
            "Site Internet state loading must not branch by Wi-Fi versus 4G gateway type"
        )

        require(
            source.contains("private func shouldShowGatewayStatus(for spaces: [SpaceData]) -> Bool"),
            "Gateway overview visibility must have a shared server-state policy"
        )
        let visibilityUseCount = source.components(
            separatedBy: "shouldShowGatewayStatus(for: spaces)"
        ).count - 1
        require(
            visibilityUseCount >= 2,
            "Gateway status visibility policy must be reused by header rendering and layout"
        )

        require(
            source.contains("let siteGatewayAssociationTopologyChangedNotificationName"),
            "Site must define a dedicated gateway-association topology notification"
        )
        require(
            source.contains("forName: .init(siteGatewayAssociationTopologyChangedNotificationName)"),
            "Site must observe gateway-association topology changes"
        )
        let gatewayObservers = section(
            in: source,
            from: "/// 网关数据更新回调",
            to: "// 手机网络状态观察者"
        )
        require(
            !gatewayObservers.contains("self.reloadData = false"),
            "Gateway data updates must not cancel a pending authoritative Site refresh"
        )
        require(
            gatewayObservers.contains("self?.refreshSiteAfterGatewayAssociationChange()"),
            "Gateway association topology changes must trigger the Site refresh policy"
        )

        require(
            source.contains("private func refreshSiteAfterGatewayAssociationChange()"),
            "Site must expose a dedicated gateway-association refresh policy"
        )
        let associationRefresh = section(
            in: source,
            from: "private func refreshSiteAfterGatewayAssociationChange()",
            to: "// MARK: - Request"
        )
        require(
            associationRefresh.contains("viewIfLoaded?.window != nil"),
            "Visible Site pages must support immediate authoritative refresh"
        )
        require(
            associationRefresh.contains("NetworkRequest.shared.networkable"),
            "Immediate Site refresh must require phone network availability"
        )
        require(
            associationRefresh.contains("loadSiteRequest()"),
            "Visible and networkable Site pages must immediately request siteInfo"
        )
        require(
            associationRefresh.contains("reloadData = true"),
            "Unavailable Site pages must retain the lifecycle refresh fallback"
        )
        require(
            gatewaySource.contains("private struct AssociatedSpacesSaveResult"),
            "Gateway save flow must retain both success and topology-change outcomes"
        )
        require(
            gatewaySource.contains("let topologyChanged: Bool"),
            "Gateway association result must expose topologyChanged"
        )
        require(
            gatewaySource.contains("notifySiteGatewayAssociationTopologyChanged()"),
            "Gateway save flow must notify Site after confirmed topology changes"
        )

        print("SiteGatewayOnlineStateContractTests passed")
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) -> String {
        guard let startRange = source.range(of: startMarker) else {
            fatalError("Missing source marker: \(startMarker)")
        }
        let remainder = source[startRange.lowerBound...]
        guard let endRange = remainder.range(of: endMarker) else {
            fatalError("Missing source marker: \(endMarker)")
        }
        return String(remainder[..<endRange.lowerBound])
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        precondition(condition(), message)
    }
}
