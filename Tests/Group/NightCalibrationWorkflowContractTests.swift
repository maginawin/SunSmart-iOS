import Foundation

@main
struct NightCalibrationWorkflowContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 9 else {
            fatalError("Expected controller, mode view, about view, localizations, SDK manager, MeshAPI and disclosure asset paths")
        }

        let controller = try source(CommandLine.arguments[1])
        let modeView = try source(CommandLine.arguments[2])
        let aboutView = try source(CommandLine.arguments[3])
        let english = try source(CommandLine.arguments[4])
        let chinese = try source(CommandLine.arguments[5])
        let manager = try source(CommandLine.arguments[6])
        let meshAPI = try source(CommandLine.arguments[7])
        let disclosureAsset = try source(CommandLine.arguments[8])

        require(
            manager.contains("public func calibrateNight(") &&
                manager.contains("pairCount: Int = 3") &&
                manager.contains("getStableLightnessLuxData") &&
                manager.contains("stableWindowSize"),
            "SDK must expose a three-pair Night calibration path with stable-window sampling"
        )
        let initialize = section(
            in: manager,
            from: "private func initialize()",
            to: "private func stabilityVerify()"
        )
        require(
            initialize.contains("case .night:") &&
                initialize.contains("event: \"environment_stability_skipped\"") &&
                initialize.contains("reason=controlled_night_sampling") &&
                initialize.contains("self.setLightingAndSensorInflectionPoint()") &&
                initialize.contains("case .plane, .sensor:") &&
                initialize.contains("self.stabilityVerify()"),
            "Night must skip the uncontrolled environment gate while Plane and Sensor retain it"
        )
        require(
            manager.contains("case .night:") &&
                manager.contains("setIdentityCalibrateRate()") &&
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
                  of: "private func makeDaylightCalibrationSnapshot",
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
                controller.contains("commitCalibrationSensorSelection") &&
                controller.contains("selectedSensorPublish: sensor.ambientLightSensorModel?.publish") &&
                controller.contains("publicationRollbackSucceeded && calibrationRollbackSucceeded") &&
                controller.contains("invalidateCalibrationAfterRollbackFailure"),
            "Night and Sensor switches must remain draft until Apply, with unknown rollback state clearing Active"
        )
        require(
            controller.contains("LightLCLightOnOffSetUnacknowledged(false)") &&
                controller.contains("beginDaylightCalibration(mode: \"plane\")") &&
                controller.contains("beginDaylightCalibration(mode: \"night\")") &&
                controller.contains("beginDaylightCalibration(mode: \"sensor\")") &&
                controller.contains("saveCalibrationMode(.none)"),
            "Every calibration mode must suspend Group Auto and an incomplete rollback must keep Auto disabled"
        )
        require(
            controller.contains("isNightRecalibrationDraft = true") &&
                controller.contains("effectiveActiveCalibrationMode == .nightCal && !isNightRecalibrationDraft"),
            "Re-calibrate must be a page-only draft that does not erase stored Night Active"
        )
        require(
            controller.contains("let initialMode = lightSensorMode(for: effectiveActiveCalibrationMode) ?? .night"),
            "An uncalibrated daylight Group must initially select Night Cal. while Active remains None"
        )
        let initialAboutExpansion = "calibrationAboutView.setExpanded(effectiveActiveCalibrationMode == .none)"
        require(
            aboutView.contains("func setExpanded(_ isExpanded: Bool)") &&
                controller.components(separatedBy: initialAboutExpansion).count == 2,
            "About must initialize exactly once from the entry Active state"
        )

        require(
            modeView.contains("LightSensorTargetNightBrightnessView") &&
                modeView.contains("var allowedRange: ClosedRange<Int> = 1...100") &&
            modeView.contains("LightSensorCalibrationCompleteView") &&
                modeView.contains("showsTargetBrightness") &&
                modeView.contains("calibration_pending_devices") &&
                modeView.contains("calibration_target_level_value") &&
                modeView.contains("site_entry_sync_warning") &&
                modeView.contains("night_calibration_disclosure") &&
                modeView.contains("recalibrateLabel.attributedText = attributedText(") &&
                modeView.contains("recalibrateLabel.isAccessibilityElement = false") &&
                modeView.contains("disclosureImageView.isAccessibilityElement = false") &&
                modeView.contains("profileType == .daylight") &&
                modeView.contains("calibration_complete_task_notice") &&
                modeView.contains("calibration_complete_occupancy_notice_format"),
            "Night UI must include the Figma value, notice and action components without losing pending state"
        )
        let targetNightBrightnessView = section(
            in: modeView,
            from: "final class LightSensorTargetNightBrightnessView",
            to: "final class LightSensorTargetSensorValueView"
        )
        require(
            targetNightBrightnessView.contains("make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))") &&
                targetNightBrightnessView.contains("make.top.equalTo(dimLevelView.snp.bottom).offset(SCRYFrom(20))") &&
                targetNightBrightnessView.contains("make.bottom.equalTo(SCRYFrom(-24))") &&
                !targetNightBrightnessView.contains("make.height.equalTo"),
            "Night Target Brightness must order Dim level before its description and keep an adaptive height"
        )
        require(
            targetNightBrightnessView.contains("calibration_target_night_brightness_note") &&
                targetNightBrightnessView.contains("fontSize: 12") &&
                targetNightBrightnessView.contains("lineHeight: 19.5") &&
                targetNightBrightnessView.contains("noteLabel.numberOfLines = 0"),
            "Night Target Brightness description must retain the localized Figma typography and wrapping"
        )
        require(
            modeView.contains("RGB(246, 248, 255)") &&
                modeView.contains("RGB(255, 249, 239)") &&
                modeView.contains("Border_Color"),
            "Night completed UI must retain the Figma card colors and action border"
        )
        require(
            disclosureAsset.contains("width=\"16\" height=\"16\"") &&
                disclosureAsset.contains("M3.33333 8H12.6667") &&
                disclosureAsset.contains("stroke=\"#8B96A8\""),
            "Night completed UI must use the exact Figma disclosure asset"
        )
        let requiredLocalizationKeys = [
            "apply_night_calibration",
            "apply_calibration_title",
            "calculating_target_illuminance",
            "calibration_complete",
            "calibration_target_level_value",
            "calibration_complete_occupancy_notice_format",
            "calibration_complete_occupancy_notice_emphasis",
            "calibration_complete_task_notice",
            "calibration_pending_devices"
        ]
        requiredLocalizationKeys.forEach { key in
            require(english.contains("\"\(key)\""), "English localization is missing \(key)")
            require(chinese.contains("\"\(key)\""), "Chinese localization is missing \(key)")
        }
        require(
            english.contains("Once applied, the device will automatically learn the environment and adjust brightness to maintain the target illuminance. When ambient light drops to zero, the device will stabilize close to the target night brightness.") &&
                chinese.contains("应用后，设备将自动学习环境并调节亮度，以维持目标照度。当环境光降至零时，设备将稳定在接近目标夜间亮度的水平。"),
            "Night Target Brightness learning description must match the approved English and Chinese copy"
        )
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

    private static func section(in source: String, from start: String, to end: String) -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            fatalError("Missing section from \(start) to \(end)")
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}
