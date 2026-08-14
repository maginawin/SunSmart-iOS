import Foundation

@main
struct SiteGatewayTimeZoneNameColorContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 5 else {
            fatalError("Expected context, gateway list, gateway menu, and site controller paths")
        }

        let context = try source(arguments[1])
        let gatewayList = try source(arguments[2])
        let gatewayMenu = try source(arguments[3])
        let siteController = try source(arguments[4])

        require(
            context.contains("static func makeTargets("),
            "Context builder must expose one reusable target construction entry"
        )
        require(
            context.contains("let targets = makeTargets("),
            "Full SyncGatewaysContext construction must reuse makeTargets"
        )
        require(
            occurrences(of: "SyncGatewaysContextSelectionPolicy.select(", in: context) == 1,
            "Gateway selection policy must not be duplicated"
        )

        require(gatewayList.contains("enum SiteGatewayTimeZoneSyncAppearance"))
        require(gatewayList.contains("static let pendingNameColor = RGB(187, 77, 0)"))
        require(
            gatewayList.contains("static let menuPendingNameColor = RGB(255, 210, 48)"),
            "Gateway menu must use the brighter #FFD230 pending name color"
        )
        require(gatewayList.contains("var needsTimeZoneSync: Bool"))
        require(gatewayList.contains("needsTimeZoneSync: Bool = false"))
        require(gatewayList.contains("item.needsTimeZoneSync"))
        require(gatewayList.contains("SiteGatewayTimeZoneSyncAppearance.pendingNameColor"))
        require(gatewayList.contains("item.isSelected ? Bar_Color : ImportantText_Color"))
        require(gatewayList.contains("underlineView.isHidden = !item.isSelected"))

        require(
            siteController.contains("private func pendingTimeZoneSyncGatewayIDs() -> Set<String>"),
            "Site controller must expose one read-only pending ID query"
        )
        require(siteController.contains("SyncGatewaysContextBuilder.makeTargets("))
        require(
            siteController.contains("private func makeGatewayListItems("),
            "All horizontal Gateway items must use one builder"
        )
        require(
            occurrences(of: "makeGatewayListItems(showGatewayModels)", in: siteController) == 2,
            "Header and all-space refresh must share the same item builder"
        )
        require(
            occurrences(of: "makeGatewayListItems(gatewayModels)", in: siteController) == 1,
            "Favourite refresh must preserve its existing Gateway source"
        )

        require(gatewayMenu.contains("let needsTimeZoneSync: Bool"))
        require(gatewayMenu.contains("data.needsTimeZoneSync"))
        require(
            gatewayMenu.contains("SiteGatewayTimeZoneSyncAppearance.menuPendingNameColor"),
            "Gateway menu pending rows must not reuse the darker horizontal-list color"
        )
        require(
            occurrences(of: "cell.titleLabel.textColor = titleColor", in: gatewayMenu) >= 1,
            "Normal Gateway and Add Gateway rows must restore the original title color"
        )
        require(gatewayMenu.contains("cell.backgroundColor = selectIndex == indexPath.row"))
        require(gatewayMenu.contains("cell.iconImageView.image = UIImage(named: \"gateway_status_online\")"))

        require(
            siteController.contains("SiteGatewaysMenuView.GatewayMenuData("),
            "Site controller must still build menu presentation data"
        )
        require(
            occurrences(
                of: "needsTimeZoneSync: id.map(pendingIDs.contains) ?? false",
                in: siteController
            ) == 2,
            "Horizontal list and menu data must use the same normalized pending ID set"
        )

        print("SiteGatewayTimeZoneNameColorContractTests passed")
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Site Gateway timezone name color contract failed"
    ) {
        guard condition() else { fatalError(message) }
    }
}
