import Foundation

@main
struct EnergyStatisticsFilteringContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }

        let root = CommandLine.arguments[1]
        let controller = try source(
            root,
            "SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift"
        )
        let spaceView = try source(
            root,
            "SunSmart/Main/Energy/View/EnergyStaticDataSpaceView.swift"
        )
        let groupView = try source(
            root,
            "SunSmart/Main/Energy/View/EnergyStaticDataGroupView.swift"
        )
        let staticData = try source(
            root,
            "SunSmart/Main/Energy/Model/EnergyStatisticsStaticData.swift"
        )
        let project = try source(root, "SunSmart.xcodeproj/project.pbxproj")

        let updateUI = section(
            in: controller,
            from: "private func updateUI()",
            to: "/// 过滤数据类型"
        )
        require(
            updateUI.contains("latestHarvestData?.filtered(by: statisticsFilterType.filter)"),
            "Energy views must receive a category-filtered latest snapshot"
        )
        require(
            updateUI.contains("previousHarvestData?.filtered(by: statisticsFilterType.filter)"),
            "Energy interval must compare category-filtered snapshots"
        )
        require(
            !updateUI.contains("showDevices = []") && !updateUI.contains("0.00 kWh"),
            "True power UI still contains placeholder zero/empty behavior"
        )
        require(
            !spaceView.contains("statisticsType") && !groupView.contains("statisticsType"),
            "Space or Group view still owns category-specific placeholder behavior"
        )
        require(
            controller.contains("meteringType: meteringType")
                && staticData.contains("let meteringType: EnergyMeteringType?")
                && staticData.contains("var effectiveMeteringType: EnergyMeteringType"),
            "Harvest snapshots must persist a backward-compatible metering source"
        )
        require(
            project.components(separatedBy: "/* EnergyStatisticsFilterPolicy.swift in Sources */,").count - 1 == 5,
            "Energy filter policy must be compiled into all five App targets"
        )

        print("PASS: Energy statistics filtering contracts hold.")
    }

    private static func source(_ root: String, _ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: root).appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) -> String {
        guard let start = source.range(of: startMarker)?.lowerBound,
              let end = source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound else {
            return ""
        }
        return String(source[start..<end])
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
