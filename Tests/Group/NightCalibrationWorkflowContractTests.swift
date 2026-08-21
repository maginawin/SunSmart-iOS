import Foundation

@main
struct NightCalibrationWorkflowContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 7 else {
            fatalError("Expected controller, mode view, English localization, Chinese localization, SDK manager and MeshAPI paths")
        }

        let controller = try source(CommandLine.arguments[1])
        let modeView = try source(CommandLine.arguments[2])
        let english = try source(CommandLine.arguments[3])
        let chinese = try source(CommandLine.arguments[4])
        let manager = try source(CommandLine.arguments[5])
        let meshAPI = try source(CommandLine.arguments[6])

        require(
            manager.contains("public func calibrateNight(") &&
                manager.contains("pairCount: Int = 3") &&
                manager.contains("getStableLightnessLuxData") &&
                manager.contains("stableWindowSize"),
            "SDK must expose a three-pair Night calibration path with stable-window sampling"
        )
        require(
            manager.contains("case .night:") &&
                manager.contains("setNightCalibrateRate()") &&
                manager.contains("sensorRate: 100, ambientLightRate: 100") &&
                manager.contains("daylightCalibrateIlluminanceInflectionPoint"),
            "Night calibration must write the real 0x38 curve and identity 0x39 ratios"
        )
        require(
            manager.contains("restorePreviousCalibrationIfNeeded") &&
                manager.contains("public func restoreDaylightCalibration(") &&
                manager.contains("applyDaylightCalibration") &&
                manager.contains("calibrationRollbackFailed"),
            "SDK failure handling must restore the previous 0x38/0x39 state before preserving old Active"
        )

        let waitIndex = meshAPI.range(of: "waitFor(messageFrom: address")?.lowerBound
        let sendIndex = meshAPI.range(
            of: "MeshAPI.sendMessage(message: SensorGet(.presentAmbientLightLevel), model: sensorModel)",
            options: [],
            range: waitIndex.map { $0..<meshAPI.endIndex }
        )?.lowerBound
        require(
            waitIndex != nil && sendIndex != nil && waitIndex! < sendIndex!,
            "Ambient Sensor Get must register its response callback before sending"
        )

        require(
            controller.contains("if profile.type == .daylight") &&
                controller.contains("profile.lightControlData.taskLevel = Int(result.targetLux)") &&
                controller.contains("profile.lightControlData.occupancyLevel = Int(result.targetLux)") &&
                controller.contains("profile.calibrationMode = .nightCal"),
            "Night result must update taskLevel for pure daylight and occupancyLevel for other daylight profiles"
        )
        guard let nightCommitStart = controller.range(of: "profile.calibrationMode = .nightCal"),
              let nightCommitEnd = controller.range(
                  of: "private func makeNightCalibrationSnapshot",
                  range: nightCommitStart.upperBound..<controller.endIndex
              ) else {
            fatalError("Night calibration commit section is missing")
        }
        let nightCommit = String(controller[nightCommitStart.lowerBound..<nightCommitEnd.lowerBound])
        let configuringIndex = nightCommit.range(
            of: "self.configuring(lightNodes: self.group.nodes) { [weak self] success in"
        )?.lowerBound
        let successGuardIndex = nightCommit.range(of: "guard success else { return }")?.lowerBound
        let restoreAutoIndex = nightCommit.range(
            of: "self?.restoreGroupAutoAfterDaylightCalibration()"
        )?.lowerBound
        require(
            configuringIndex != nil && successGuardIndex != nil && restoreAutoIndex != nil &&
                configuringIndex! < successGuardIndex! && successGuardIndex! < restoreAutoIndex!,
            "Night calibration must restore Group Auto only after all member configuration succeeds"
        )
        require(
            controller.contains("calibrationModeView.selectedMode != .plane") &&
                controller.contains("commitNightSensorSelection") &&
                controller.contains("selectedSensorPublish: sensor.ambientLightSensorModel?.publish") &&
                controller.contains("publicationRollbackSucceeded && calibrationRollbackSucceeded") &&
                controller.contains("invalidateCalibrationAfterRollbackFailure"),
            "Night and Sensor switches must remain draft until Apply, with unknown rollback state clearing Active"
        )
        require(
            controller.contains("LightLCLightOnOffSetUnacknowledged(false)") &&
                controller.contains("saveCalibrationMode(.none)"),
            "An incomplete rollback must clear Active and disable Group auto"
        )
        require(
            controller.contains("isNightRecalibrationDraft = true") &&
                controller.contains("effectiveActiveCalibrationMode == .nightCal && !isNightRecalibrationDraft"),
            "Re-calibrate must be a page-only draft that does not erase stored Night Active"
        )

        require(
            modeView.contains("LightSensorTargetNightBrightnessView") &&
                modeView.contains("var allowedRange: ClosedRange<Int> = 1...100") &&
            modeView.contains("LightSensorNightCalibrationCompleteView") &&
                modeView.contains("calibration_pending_devices"),
            "Night UI must include a trim-bound target, completed and pending-sync states"
        )
        let requiredLocalizationKeys = [
            "apply_night_calibration",
            "apply_calibration_title",
            "calculating_target_illuminance",
            "calibration_complete",
            "calibration_pending_devices"
        ]
        requiredLocalizationKeys.forEach { key in
            require(english.contains("\"\(key)\""), "English localization is missing \(key)")
            require(chinese.contains("\"\(key)\""), "Chinese localization is missing \(key)")
        }
        require(
            modeView.contains("return \"calibration_about_sensor_title\".localizedString") &&
                modeView.contains("return \"calibration_about_sensor_description\".localizedString"),
            "Sensor Cal. About content routing must remain unchanged"
        )

        print("NightCalibrationWorkflowContractTests passed")
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
