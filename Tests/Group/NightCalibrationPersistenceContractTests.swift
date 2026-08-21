import Foundation

@main
struct NightCalibrationPersistenceContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 5 else {
            fatalError("Expected Profile, Database, ExportData and ImportData source paths")
        }

        let profile = try source(CommandLine.arguments[1])
        let database = try source(CommandLine.arguments[2])
        let exportData = try source(CommandLine.arguments[3])
        let importData = try source(CommandLine.arguments[4])

        require(
            profile.contains("enum DaylightCalibrationMode: String, Codable, CaseIterable") &&
                profile.contains("case none") &&
                profile.contains("case nightCal") &&
                profile.contains("case sensorCal") &&
                profile.contains("case planeCal"),
            "Profile must define stable daylight calibration mode raw values"
        )
        require(
            profile.contains("var calibrationMode: DaylightCalibrationMode? = DaylightCalibrationMode.none") &&
                profile.contains("var targetNightBrightness: Int = Profile.defaultTargetNightBrightness"),
            "Profile must retain mode and target night brightness"
        )
        guard let effectiveModeStart = profile.range(of: "func effectiveCalibrationMode(sensorCalibrated: Bool)"),
              let effectiveModeEnd = profile.range(
                  of: "static func normalizedTargetNightBrightness",
                  range: effectiveModeStart.upperBound..<profile.endIndex
              ) else {
            fatalError("Effective calibration mode method is missing")
        }
        let effectiveMode = String(profile[effectiveModeStart.lowerBound..<effectiveModeEnd.lowerBound])
        require(
            effectiveMode.contains("guard type.daylightType, sensorCalibrated else") &&
                effectiveMode.contains("return calibrationMode ?? .planeCal"),
            "A stored mode requires a valid calibrated sensor, while legacy missing mode falls back to Plane"
        )
        require(
            profile.contains("profile.calibrationMode = calibrationMode") &&
                profile.contains("profile.targetNightBrightness = targetNightBrightness"),
            "Profile copy must preserve Night calibration metadata"
        )
        require(
            profile.contains("lhs.calibrationMode == rhs.calibrationMode") &&
                profile.contains("lhs.targetNightBrightness == rhs.targetNightBrightness"),
            "Profile equality must include Night calibration metadata"
        )

        require(
            database.contains("Expression<String?>(\"calibrationMode\")") &&
                database.contains("Expression<Int>(\"targetNightBrightness\")"),
            "SQLite must define both Night calibration columns"
        )
        require(
            database.contains("$0.name == \"calibrationMode\"") &&
                database.contains("addColumn(ExpressionKey.calibrationMode)") &&
                database.contains("$0.name == \"targetNightBrightness\"") &&
                database.contains("addColumn(ExpressionKey.targetNightBrightness, defaultValue: Profile.defaultTargetNightBrightness)"),
            "Old profile databases must migrate both Night calibration columns"
        )
        require(
            database.contains("Profile.DaylightCalibrationMode(rawValue: rawCalibrationMode) ?? Profile.DaylightCalibrationMode.none") &&
                database.contains("profile.calibrationMode = nil") &&
                database.contains("ExpressionKey.calibrationMode <- self.calibrationMode?.rawValue"),
            "SQLite load/save must preserve explicit modes and legacy missing-mode state"
        )

        require(
            exportData.contains("\"calibrationMode\": profile.effectiveCalibrationMode") &&
                exportData.contains("\"targetNightBrightness\": Profile.normalizedTargetNightBrightness"),
            "Space export must upload both Night calibration fields"
        )
        require(
            importData.contains("profileJson[\"calibrationMode\"].string") &&
                importData.contains("Profile.DaylightCalibrationMode(rawValue: rawCalibrationMode) ?? Profile.DaylightCalibrationMode.none") &&
                importData.contains("profile.calibrationMode = nil") &&
                importData.contains("profileJson[\"targetNightBrightness\"].int"),
            "Space import must restore fields and distinguish missing legacy mode"
        )

        print("NightCalibrationPersistenceContractTests passed")
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
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
