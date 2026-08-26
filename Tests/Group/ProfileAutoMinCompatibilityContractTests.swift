import Foundation

@main
struct ProfileAutoMinCompatibilityContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 6 else {
            fatalError("Expected Profile, ImportData, Database, ProfileSettings and Node sync source paths")
        }

        let profile = try source(CommandLine.arguments[1])
        let importData = try source(CommandLine.arguments[2])
        let database = try source(CommandLine.arguments[3])
        let settings = try source(CommandLine.arguments[4])
        let nodeSync = try source(CommandLine.arguments[5])

        require(
            profile.contains("static let autoMinLevelRange = 0...30") &&
                profile.contains("static let disabledAutoMinLevel = 255") &&
                profile.contains("static func normalizedAutoMinLevel(_ value: Int?) -> Int") &&
                profile.contains("static func isAutoMinLevelEnabled(_ value: Int) -> Bool") &&
                profile.contains("func clampAutoMinLevel(to range: ClosedRange<Int>)"),
            "LightControlData must own Auto min range, disabled, normalization and clamping semantics"
        )
        require(
            profile.contains("return Self.isAutoMinLevelEnabled(autoMinLevel)") &&
                !profile.contains("return autoMinLevel != 255") &&
                !profile.contains("enabled: autoMinLevel <= 30"),
            "UI and LightData enabled state must use the shared valid-range predicate"
        )
        require(
            profile.contains("case .occupancy_daylight, .vacancy_daylight, .daylight:") &&
                profile.contains("var daylightType: Bool"),
            "The three daylight harvesting profile types must remain centrally identifiable"
        )

        require(
            importData.contains("Profile.LightControlData.normalizedAutoMinLevel(profileJson[\"autoMinLevel\"].int)") &&
                importData.contains("Profile.LightControlData.normalizedAutoMinLevel(sceneJson[\"autoMinLevel\"].int)") &&
                !importData.contains("autoMinLevel: profileJson[\"autoMinLevel\"].int ?? 0"),
            "Daylight cloud import must distinguish missing Auto min from explicit zero for top-level and scene data"
        )
        require(
            database.contains("profileType.daylightType") &&
                database.contains("LightControlData.normalizedAutoMinLevel(storedAutoMinLevel)") &&
                database.contains("scene.lightControlData.autoMinLevel = LightControlData.normalizedAutoMinLevel"),
            "Database load must repair invalid historical daylight Auto min values in columns and scenes"
        )

        require(
            settings.contains("let levelConfig = !self.selectProfile.type.daylightType") &&
                settings.contains("data.clampAutoMinLevel(to: range)") &&
                !settings.contains("data.autoMinLevel = max(min(data.autoMinLevel, high), low)") &&
                settings.contains("enabled: data.autoMinLevelEnabled"),
            "High/Low trim and Auto min UI must preserve disabled through shared model semantics"
        )

        require(
            nodeSync.contains("case .autoMinValue(let value, let enabled):") &&
                nodeSync.contains("let level = enabled ? value : 0") &&
                nodeSync.contains("syncProfile.append(.occupancyLevel(value: level))") &&
                nodeSync.contains("syncProfile.append(.vacantLevel(value: level))") &&
                nodeSync.contains("syncProfile.append(.standbyLevel(value: level))"),
            "Existing daylight Auto min to On/Prolong/Standby sync behavior must remain intact"
        )

        print("ProfileAutoMinCompatibilityContractTests passed")
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
