import Foundation

@main
struct SensorCalibrationWorkflowContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 7 else {
            fatalError("Expected controller, mode view, localizations, SDK manager and MeshAPI paths")
        }

        let controller = try source(CommandLine.arguments[1])
        let modeView = try source(CommandLine.arguments[2])
        let english = try source(CommandLine.arguments[3])
        let chinese = try source(CommandLine.arguments[4])
        let manager = try source(CommandLine.arguments[5])
        let meshAPI = try source(CommandLine.arguments[6])

        require(
            manager.contains("case sensor") &&
                manager.contains("public func calibrateSensor(") &&
                manager.contains("normalizedSensorOnLux") &&
                manager.contains("isNightOnLuxValid") &&
                manager.contains("setIdentityCalibrateRate()"),
            "SDK must expose an explicit Sensor mode with Sensor ON normalization and strict Night validation"
        )
        require(
            manager.contains("sensorRate: 100, ambientLightRate: 100") &&
                manager.contains("daylightCalibrateIlluminanceInflectionPoint") &&
                manager.contains("restorePreviousCalibrationIfNeeded"),
            "Sensor calibration must retain the real 0x38 curve, identity 0x39 ratios and rollback"
        )

        require(
            modeView.contains("LightSensorCalibrationDimLevelView") &&
                modeView.contains("CustomDeviceSlider") &&
                modeView.contains("scene_data_value_minus") &&
                modeView.contains("scene_data_value_add") &&
                modeView.contains("slider_point"),
            "Night and Sensor must share the Figma-aligned Dim level control"
        )
        require(
            modeView.contains("LightSensorTargetSensorValueView") &&
                modeView.contains("0...2500") &&
                modeView.contains("calibration_use_sensor_reading") &&
                modeView.contains("decimalPad"),
            "Sensor target UI must support integer input and Use sensor reading in the confirmed range"
        )
        require(
            modeView.contains("showsTargetBrightness") &&
                modeView.contains("brightnessLabel.isHidden = !showsTargetBrightness"),
            "The shared completed card must hide the Night brightness row for Sensor"
        )

        require(
            controller.contains("MeshSensorCalibrateManager.manager.calibrateSensor(") &&
                controller.contains("profile.calibrationMode = .sensorCal") &&
                controller.contains("profile.lightControlData.taskLevel = targetLux") &&
                controller.contains("profile.lightControlData.occupancyLevel = targetLux"),
            "Sensor Apply must use the Sensor SDK path and save the direct target to the active Profile field"
        )
        require(
            controller.contains("latestFreshSensorLux") &&
                controller.contains("pendingUseSensorReadingAddress") &&
                controller.contains("requestSensorTargetReading") &&
                controller.contains("Self.sensorTargetLuxRange.contains"),
            "Use sensor reading must be sensor-bound, freshness-aware and constrained to 0...2500 lx"
        )
        require(
            controller.contains("suspendGroupAutoForSensorCalibration") &&
                controller.contains("restoreSensorDimLevel") &&
                controller.contains("sensorConfigurationPending") &&
                controller.contains("Node.getLightness(lightness100: sensorCalibrationDimLevel)"),
            "Sensor manual dimming must suspend Auto and restore the Apply-time level without bypassing pending configuration"
        )
        require(
            meshAPI.contains("public static func setGroupLightnessState"),
            "Sensor Dim level must use the existing Group lightness API"
        )

        let requiredLocalizationKeys = [
            "apply_sensor_calibration",
            "apply_plane_calibration",
            "calibration_target_sensor_value",
            "calibration_target_value_placeholder",
            "calibration_use_sensor_reading",
            "calibration_target_sensor_value_note",
            "calibration_dim_level",
            "apply_sensor_calibration_message"
        ]
        requiredLocalizationKeys.forEach { key in
            require(english.contains("\"\(key)\""), "English localization is missing \(key)")
            require(chinese.contains("\"\(key)\""), "Chinese localization is missing \(key)")
        }

        print("SensorCalibrationWorkflowContractTests passed")
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
