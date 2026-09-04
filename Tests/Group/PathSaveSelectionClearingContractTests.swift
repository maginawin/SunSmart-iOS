import Foundation

@main
struct PathSaveSelectionClearingContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }

        let root = CommandLine.arguments[1]
        let groupPage = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift"
        )
        let sequencePage = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift"
        )
        let groupZonePage = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift"
        )
        let spaceZonePage = try source(
            root,
            "SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift"
        )

        let groupSave = section(
            in: groupPage,
            from: "@objc private func saveAction()",
            to: "private func makeSyncDatas("
        )
        require(
            appearsBefore("vc.stopSetPath()", "showCapacityLimitIfNeeded(for: plan)", in: groupSave)
                && appearsBefore("vc.stopSetZone()", "showCapacityLimitIfNeeded(for: plan)", in: groupSave),
            "Group SAVE must clear Sequence and Trigger Zone selection before validation or sync"
        )

        requireSelectionClearing(
            in: sequencePage,
            deselectFunction: "func deselectPath()",
            deselectEnd: "func addPath()",
            stopFunction: "func stopSetPath()",
            stopEnd: "/// 路径操作",
            selectionClear: "selectPathData.path = nil",
            expectedDelegation: "deselectPath()",
            name: "Group Sequence"
        )
        requireSelectionClearing(
            in: groupZonePage,
            deselectFunction: "func deselectZone()",
            deselectEnd: "func addZone()",
            stopFunction: "func stopSetZone()",
            stopEnd: "/// 区域操作",
            selectionClear: "selectZone = nil",
            expectedDelegation: "deselectZone()",
            name: "Group Trigger Zone"
        )

        let spaceSave = section(
            in: spaceZonePage,
            from: "@objc private func saveAction()",
            to: "private func exitToSpaceMore()"
        )
        require(
            appearsBefore("stopSetZone()", "sanitizeSetZones()", in: spaceSave),
            "Space Trigger Zone SAVE must clear selection before validation or sync"
        )
        requireSelectionClearing(
            in: spaceZonePage,
            deselectFunction: "func deselectZone()",
            deselectEnd: "func stopSetZone()",
            stopFunction: "func stopSetZone()",
            stopEnd: "@objc private func addAction()",
            selectionClear: "selectZone = nil",
            expectedDelegation: "deselectZone()",
            name: "Space Trigger Zone"
        )

        print("PASS: Path and Trigger Zone SAVE selection-clearing contracts hold.")
    }

    private static func requireSelectionClearing(
        in sourceText: String,
        deselectFunction: String,
        deselectEnd: String,
        stopFunction: String,
        stopEnd: String,
        selectionClear: String,
        expectedDelegation: String,
        name: String
    ) {
        let deselect = section(in: sourceText, from: deselectFunction, to: deselectEnd)
        let stop = section(in: sourceText, from: stopFunction, to: stopEnd)
        require(
            stop.contains(expectedDelegation),
            "\(name) SAVE clearing must reuse its visual deselection path"
        )
        require(
            deselect.contains(selectionClear)
                && deselect.contains("tableView.reloadSections")
                && deselect.contains("updateDeviceAddViewUI()"),
            "\(name) deselection must clear state, redraw the selected row, and update the add view"
        )
        require(
            appearsBefore(selectionClear, "tableView.reloadSections", in: deselect),
            "\(name) must clear selection state before redrawing the row"
        )
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

    private static func appearsBefore(
        _ first: String,
        _ second: String,
        in source: String
    ) -> Bool {
        guard let firstRange = source.range(of: first),
              let secondRange = source.range(of: second) else {
            return false
        }
        return firstRange.lowerBound < secondRange.lowerBound
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
