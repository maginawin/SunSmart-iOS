import Foundation

@main
struct GatewayScrollPerformanceContractTests {

    static func main() throws {
        let arguments = CommandLine.arguments
        require(arguments.count == 6, "Expected controller, WiFi controller, header, network cell, and clock model paths")
        let controller = try read(arguments[1])
        let wifiController = try read(arguments[2])
        let header = try read(arguments[3])
        let networkCell = try read(arguments[4])
        let clockModel = try read(arguments[5])

        require(
            controller.contains("RunLoop.main.add(gatewayClockTimer, forMode: .default)"),
            "Clock ticks must not run in UI tracking mode"
        )
        require(
            controller.contains("tableView.isTracking || tableView.isDragging || tableView.isDecelerating"),
            "Clock view updates must be deferred while the table is scrolling"
        )
        require(
            controller.contains("updateVisibleGatewayClockRows()"),
            "Clock ticks must update visible cells in place"
        )
        require(
            !controller.contains("tableView.reloadRows(at: indexPaths, with: .none)"),
            "Clock ticks must not structurally reload table rows"
        )
        require(
            controller.contains("private let gatewayClockFormatter = GatewayDetailClockFormatter()"),
            "Clock ticks must reuse a formatter"
        )
        require(
            clockModel.contains("final class GatewayDetailClockFormatter"),
            "Clock formatting must have a reusable owner"
        )
        require(
            wifiController.contains("case backgroundInteractionLock"),
            "Background RSSI requests must have a non-structural presentation"
        )
        require(
            wifiController.contains("presentation: .backgroundInteractionLock"),
            "Automatic RSSI GET must select the non-structural presentation"
        )
        require(
            wifiController.contains("setBackgroundRequestInProgress"),
            "Background RSSI requests must lock the visible cell without a section reload"
        )
        require(
            networkCell.contains("contentView.isUserInteractionEnabled = !inProgress"),
            "The background request lock must not reconfigure input content"
        )
        require(
            wifiController.contains("guard displayedWiFiHeaderStatus != status else { return }"),
            "Equivalent Wi-Fi header states must not repeat UI updates"
        )
        require(
            header.contains("guard layoutShowsTitle != showsTitle || layoutIconSize != iconSize else { return }"),
            "Equivalent header layouts must not rebuild constraints"
        )

        print("GatewayScrollPerformanceContractTests passed")
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
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
