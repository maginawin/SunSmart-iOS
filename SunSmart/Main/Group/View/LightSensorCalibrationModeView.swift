//
//  LightSensorCalibrationModeView.swift
//  SunSmart
//
//  Created by One on 2026/8/21.
//

import UIKit

enum LightSensorCalibrationMode: Int, CaseIterable {
    case night
    case sensor
    case plane

    var title: String {
        switch self {
        case .night:
            return "calibration_mode_night".localizedString
        case .sensor:
            return "calibration_mode_sensor".localizedString
        case .plane:
            return "calibration_mode_plane".localizedString
        }
    }

    var aboutTitle: String {
        switch self {
        case .night:
            return "calibration_about_night_title".localizedString
        case .sensor:
            return "calibration_about_sensor_title".localizedString
        case .plane:
            return "calibration_about_plane_title".localizedString
        }
    }

    var aboutDescription: String {
        switch self {
        case .night:
            return "calibration_about_night_description".localizedString
        case .sensor:
            return "calibration_about_sensor_description".localizedString
        case .plane:
            return "calibration_about_plane_description".localizedString
        }
    }

    var bestForDescription: String {
        switch self {
        case .night:
            return "calibration_about_night_best_for".localizedString
        case .sensor:
            return "calibration_about_sensor_best_for".localizedString
        case .plane:
            return "calibration_about_plane_best_for".localizedString
        }
    }

    var avoidIfDescription: String {
        switch self {
        case .night:
            return "calibration_about_night_avoid_if".localizedString
        case .sensor:
            return "calibration_about_sensor_avoid_if".localizedString
        case .plane:
            return "calibration_about_plane_avoid_if".localizedString
        }
    }
}

final class LightSensorCalibrationModeView: UIView {

    var modeChangedHandler: ((LightSensorCalibrationMode) -> Void)?

    private let activeValueLabel = UILabel()
    private let segmentedControl = UISegmentedControl(items: LightSensorCalibrationMode.allCases.map(\.title))

    var selectedMode: LightSensorCalibrationMode {
        LightSensorCalibrationMode(rawValue: segmentedControl.selectedSegmentIndex) ?? .plane
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateActiveMode(_ mode: LightSensorCalibrationMode?) {
        activeValueLabel.text = mode?.title ?? "none".localizedString
    }

    func setSelectedMode(_ mode: LightSensorCalibrationMode, notify: Bool = false) {
        segmentedControl.selectedSegmentIndex = mode.rawValue
        if notify {
            modeChangedHandler?(mode)
        }
    }

    @objc private func modeValueChanged() {
        guard let mode = LightSensorCalibrationMode(rawValue: segmentedControl.selectedSegmentIndex) else {
            return
        }
        modeChangedHandler?(mode)
    }

    private func setupUI() {
        let titleLabel = UILabel(
            text: "calibration_mode".localizedString,
            textColor: TextBlack_Color,
            fontSize: 16,
            fontWeight: .light
        )

        let activeIndicator = UIView()
        activeIndicator.backgroundColor = RGB(0, 212, 146)
        activeIndicator.layer.cornerRadius = SCRYFrom(3)
        activeIndicator.snp.makeConstraints { make in
            make.width.height.equalTo(SCRYFrom(6))
        }

        let activeTitleLabel = UILabel(
            text: "calibration_mode_active".localizedString,
            textColor: AssistText_Color,
            fontSize: 12,
            fontWeight: .light
        )

        activeValueLabel.textColor = TextBlack_Color
        activeValueLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
        activeValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let activeStackView = UIStackView(arrangedSubviews: [activeIndicator, activeTitleLabel, activeValueLabel])
        activeStackView.axis = .horizontal
        activeStackView.alignment = .center
        activeStackView.spacing = SCRXFrom(4)

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(30))
        }

        addSubview(activeStackView)
        activeStackView.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalTo(titleLabel)
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(8))
        }

        segmentedControl.selectedSegmentIndex = LightSensorCalibrationMode.plane.rawValue
        segmentedControl.backgroundColor = .white
        segmentedControl.selectedSegmentTintColor = Bar_Color
        segmentedControl.layer.cornerRadius = SCRYFrom(10)
        segmentedControl.layer.masksToBounds = true
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: AssistText_Color,
            .font: UIFont.systemFont(ofSize: SCRYFrom(14), weight: .regular)
        ], for: .normal)
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: SCRYFrom(14), weight: .regular)
        ], for: .selected)
        let segmentStates: [UIControl.State] = [.normal, .selected]
        segmentStates.forEach { leftState in
            segmentStates.forEach { rightState in
                segmentedControl.setDividerImage(UIImage(), forLeftSegmentState: leftState, rightSegmentState: rightState, barMetrics: .default)
            }
        }
        segmentedControl.addTarget(self, action: #selector(modeValueChanged), for: .valueChanged)
        addSubview(segmentedControl)
        segmentedControl.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(36))
        }
    }
}

final class LightSensorTargetNightBrightnessView: UIView {

    var valueChangedHandler: ((Int) -> Void)?

    private let valueLabel = UILabel()
    private let slider = UISlider()

    var allowedRange: ClosedRange<Int> = 1...100 {
        didSet {
            slider.minimumValue = Float(allowedRange.lowerBound)
            slider.maximumValue = Float(allowedRange.upperBound)
            value = value
        }
    }

    var value: Int {
        get { Int(slider.value.rounded()) }
        set {
            slider.value = Float(min(max(newValue, allowedRange.lowerBound), allowedRange.upperBound))
            updateValueLabel()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func decreaseValue() {
        value -= 1
        valueChangedHandler?(value)
    }

    @objc private func increaseValue() {
        value += 1
        valueChangedHandler?(value)
    }

    @objc private func sliderValueChanged() {
        slider.value = Float(value)
        updateValueLabel()
        valueChangedHandler?(value)
    }

    private func updateValueLabel() {
        valueLabel.text = String(format: "calibration_target_night_brightness_value".localizedString, value)
    }

    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(16)

        let titleLabel = UILabel(
            text: "calibration_target_night_brightness".localizedString,
            textColor: TextBlack_Color,
            fontSize: 15,
            fontWeight: .regular
        )
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }

        valueLabel.textColor = Bar_Color
        valueLabel.font = UIFont.systemFont(ofSize: SCRYFrom(13), weight: .regular)
        addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(8))
        }

        let decreaseButton = UIButton(type: .system)
        decreaseButton.setTitle("−", for: .normal)
        decreaseButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(24), weight: .light)
        decreaseButton.tintColor = Bar_Color
        decreaseButton.addTarget(self, action: #selector(decreaseValue), for: .touchUpInside)

        let increaseButton = UIButton(type: .system)
        increaseButton.setTitle("+", for: .normal)
        increaseButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(22), weight: .light)
        increaseButton.tintColor = Bar_Color
        increaseButton.addTarget(self, action: #selector(increaseValue), for: .touchUpInside)

        slider.minimumValue = Float(allowedRange.lowerBound)
        slider.maximumValue = Float(allowedRange.upperBound)
        slider.minimumTrackTintColor = Bar_Color
        slider.maximumTrackTintColor = RGB(222, 226, 235)
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)

        let sliderStack = UIStackView(arrangedSubviews: [decreaseButton, slider, increaseButton])
        sliderStack.axis = .horizontal
        sliderStack.alignment = .center
        sliderStack.spacing = SCRXFrom(8)
        decreaseButton.snp.makeConstraints { make in make.width.height.equalTo(SCRYFrom(32)) }
        increaseButton.snp.makeConstraints { make in make.width.height.equalTo(SCRYFrom(32)) }
        addSubview(sliderStack)
        sliderStack.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.right.equalTo(SCRXFrom(-12))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(15))
        }

        let noteLabel = UILabel()
        noteLabel.text = "calibration_target_night_brightness_note".localizedString
        noteLabel.textColor = AssistText_Color
        noteLabel.font = UIFont.systemFont(ofSize: SCRYFrom(11), weight: .regular)
        noteLabel.numberOfLines = 0
        addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(sliderStack.snp.bottom).offset(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-16))
        }

        value = Profile.defaultTargetNightBrightness
    }
}

final class LightSensorNightCalibrationCompleteView: UIView {

    var recalibrateHandler: (() -> Void)?

    private let targetLevelValueLabel = UILabel()
    private let brightnessLabel = UILabel()
    private let pendingLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(targetLux: Int, targetBrightness: Int, pendingDeviceCount: Int) {
        targetLevelValueLabel.text = "\(targetLux) lx"
        brightnessLabel.text = String(format: "calibration_set_at_brightness".localizedString, targetBrightness)
        pendingLabel.text = pendingDeviceCount == 0
            ? nil
            : String(format: "calibration_pending_devices".localizedString, pendingDeviceCount)
        pendingLabel.isHidden = pendingDeviceCount == 0
    }

    @objc private func recalibrateAction() {
        recalibrateHandler?()
    }

    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(16)

        let titleLabel = UILabel(
            text: "calibration_complete".localizedString,
            textColor: TextBlack_Color,
            fontSize: 15,
            fontWeight: .regular
        )
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }

        let targetTitleLabel = UILabel(
            text: "calibration_target_level".localizedString,
            textColor: AssistText_Color,
            fontSize: 12,
            fontWeight: .regular
        )
        targetLevelValueLabel.textColor = TextBlack_Color
        targetLevelValueLabel.font = UIFont.systemFont(ofSize: SCRYFrom(22), weight: .light)
        brightnessLabel.textColor = AssistText_Color
        brightnessLabel.font = UIFont.systemFont(ofSize: SCRYFrom(11), weight: .regular)

        let levelStack = UIStackView(arrangedSubviews: [targetTitleLabel, targetLevelValueLabel, brightnessLabel])
        levelStack.axis = .vertical
        levelStack.spacing = SCRYFrom(5)
        addSubview(levelStack)
        levelStack.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(18))
        }

        pendingLabel.textColor = RGB(225, 113, 0)
        pendingLabel.font = UIFont.systemFont(ofSize: SCRYFrom(11), weight: .regular)
        pendingLabel.numberOfLines = 0
        addSubview(pendingLabel)
        pendingLabel.snp.makeConstraints { make in
            make.left.right.equalTo(levelStack)
            make.top.equalTo(levelStack.snp.bottom).offset(SCRYFrom(10))
        }

        let noticeLabel = UILabel()
        noticeLabel.text = "calibration_complete_profile_notice".localizedString
        noticeLabel.textColor = RGB(74, 85, 120)
        noticeLabel.backgroundColor = RGB(240, 244, 255)
        noticeLabel.font = UIFont.systemFont(ofSize: SCRYFrom(11), weight: .regular)
        noticeLabel.numberOfLines = 0
        noticeLabel.layer.cornerRadius = SCRYFrom(8)
        noticeLabel.clipsToBounds = true
        addSubview(noticeLabel)
        noticeLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(pendingLabel.snp.bottom).offset(SCRYFrom(12))
            make.height.greaterThanOrEqualTo(SCRYFrom(42))
        }

        let recalibrateButton = UIButton(
            title: "recalibrate".localizedString,
            titleSize: 14,
            titleWeight: .regular,
            titleColor: Bar_Color,
            target: self,
            action: #selector(recalibrateAction)
        )
        addSubview(recalibrateButton)
        recalibrateButton.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(noticeLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(48))
            make.bottom.equalToSuperview()
        }
    }
}
