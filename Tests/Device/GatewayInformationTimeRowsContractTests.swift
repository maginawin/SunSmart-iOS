import Foundation

@main
struct GatewayInformationTimeRowsContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        require(arguments.count == 5, "Expected Gateway, Information, English and Chinese paths")
        let gatewaySource = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let informationSource = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let english = try String(contentsOfFile: arguments[3], encoding: .utf8)
        let chinese = try String(contentsOfFile: arguments[4], encoding: .utf8)

        require(
            gatewaySource.contains("GatewayInformationContext(site: self.site, gateway: self.gateway)"),
            "Gateway Information entry must inject the exact Site and Gateway context"
        )
        require(
            informationSource.contains("gatewayContext: GatewayInformationContext? = nil"),
            "Ordinary device callers must retain a context-free initializer"
        )
        require(informationSource.contains("case dateTime, timeZone"), "Time rows need stable identities")
        let signalRange = informationSource.range(of: "DeviceInfoRow(id: .signalStrength")
        let dateRange = informationSource.range(of: "id: .dateTime")
        let zoneRange = informationSource.range(of: "id: .timeZone")
        require(
            (signalRange?.lowerBound ?? informationSource.endIndex)
                < (dateRange?.lowerBound ?? informationSource.startIndex),
            "Date time must follow Signal strength"
        )
        require(
            (dateRange?.lowerBound ?? informationSource.endIndex)
                < (zoneRange?.lowerBound ?? informationSource.startIndex),
            "Time zone must follow Date time"
        )
        require(
            informationSource.contains("id: .dateTime")
                && informationSource.contains("id: .timeZone"),
            "Gateway Information must contain both time rows"
        )
        require(
            informationSource.contains("case .dateTime, .timeZone:\n            requestGatewayTime()"),
            "Both time rows must invoke the same read path"
        )
        require(
            informationSource.contains("case .mac:")
                && !informationSource.contains("indexPath.row == 1"),
            "MAC copy must use row identity instead of a fragile index"
        )
        require(
            informationSource.contains("gatewayTimeCoordinator?.finishPage()"),
            "Leaving the page must detach the time coordinator"
        )
        require(
            informationSource.contains("XWHUDManager.showErrorTipHUD(\"failed_to_retrieve_data\".localizedString)"),
            "A read failure must use the approved localized Toast"
        )
        require(
            english.contains("\"gateway_date_time\" = \"Date time\";")
                && english.contains("\"gateway_not_connected\" = \"Gateway not connected\";"),
            "English Gateway time strings must exist"
        )
        require(
            chinese.contains("\"gateway_date_time\" = \"日期时间\";")
                && chinese.contains("\"gateway_not_connected\" = \"网关未连接\";"),
            "Simplified Chinese Gateway time strings must exist"
        )

        print("GatewayInformationTimeRowsContractTests passed")
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
