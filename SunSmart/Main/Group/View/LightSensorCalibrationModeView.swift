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

final class LightSensorCalibrationDimLevelView: UIView {

    var valueChangedHandler: ((Int) -> Void)?
    var throttleValueChangedHandler: ((Int, Bool) -> Void)?

    private let valueLabel = UILabel()
    private let slider = CustomDeviceSlider()

    var allowedRange: ClosedRange<Int> = 0...100 {
        didSet {
            slider.minimumValue = Float(allowedRange.lowerBound)
            slider.maximumValue = Float(allowedRange.upperBound)
            value = value
        }
    }

    var value: Int {
        get { Int(slider.value) }
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
        throttleValueChangedHandler?(value, true)
    }

    @objc private func increaseValue() {
        value += 1
        valueChangedHandler?(value)
        throttleValueChangedHandler?(value, true)
    }

    private func updateValueLabel() {
        valueLabel.text = "\(value)%"
    }

    private func setupUI() {
        let titleLabel = UILabel(
            text: "calibration_dim_level".localizedString,
            textColor: SubText_Color,
            fontSize: 14,
            fontWeight: .light
        )
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
        }

        valueLabel.textColor = RGB(46, 49, 93)
        valueLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        valueLabel.textAlignment = .right
        addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(8))
        }

        let decreaseButton = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(decreaseValue))
        let increaseButton = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(increaseValue))

        slider.minimumValue = Float(allowedRange.lowerBound)
        slider.maximumValue = Float(allowedRange.upperBound)
        slider.step = 1
        slider.minimumTrackTintColor = Slider_Color
        slider.maximumTrackTintColor = RGB(229, 229, 229)
        slider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        slider.throttle = true
        slider.delegate = self

        addSubview(decreaseButton)
        addSubview(increaseButton)
        addSubview(slider)
        decreaseButton.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(12))
            make.width.height.equalTo(SCRYFrom(30))
            make.bottom.equalToSuperview()
        }
        increaseButton.snp.makeConstraints { make in
            make.right.centerY.equalTo(decreaseButton)
            make.width.height.equalTo(SCRYFrom(30))
        }
        slider.snp.makeConstraints { make in
            make.left.equalTo(decreaseButton.snp.right).offset(SCRXFrom(14))
            make.right.equalTo(increaseButton.snp.left).offset(SCRXFrom(-14))
            make.centerY.equalTo(decreaseButton)
            make.height.equalTo(SCRYFrom(40))
        }

        value = 50
    }
}

extension LightSensorCalibrationDimLevelView: CustomDeviceSliderDelegate {

    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        updateValueLabel()
        valueChangedHandler?(Int(value))
    }

    func slider(_ slider: CustomDeviceSlider, throttleValueChanged value: Float, ended: Bool) {
        throttleValueChangedHandler?(Int(value), ended)
    }
}

final class LightSensorTargetNightBrightnessView: UIView {

    var valueChangedHandler: ((Int) -> Void)?
    private let dimLevelView = LightSensorCalibrationDimLevelView()

    var allowedRange: ClosedRange<Int> = 1...100 {
        didSet { dimLevelView.allowedRange = allowedRange }
    }

    var value: Int {
        get { dimLevelView.value }
        set { dimLevelView.value = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

        let noteLabel = UILabel()
        noteLabel.text = "calibration_target_night_brightness_note".localizedString
        noteLabel.textColor = AssistText_Color
        noteLabel.font = UIFont.systemFont(ofSize: SCRYFrom(11), weight: .regular)
        noteLabel.numberOfLines = 0
        addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(12))
        }

        dimLevelView.valueChangedHandler = { [weak self] value in
            self?.valueChangedHandler?(value)
        }
        addSubview(dimLevelView)
        dimLevelView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalTo(SCRYFrom(-24))
        }

        dimLevelView.allowedRange = allowedRange
        value = Profile.defaultTargetNightBrightness
    }
}

final class LightSensorTargetSensorValueView: UIView {

    static let targetValueRange = 0...2500

    var targetValueChangedHandler: ((Int?) -> Void)?
    var useSensorReadingHandler: (() -> Void)?
    var dimLevelChangedHandler: ((Int) -> Void)?
    var dimLevelThrottleChangedHandler: ((Int, Bool) -> Void)?

    private let targetTextField = UITextField()
    private let dimLevelView = LightSensorCalibrationDimLevelView()

    var targetValue: Int? {
        let value = targetTextField.text.flatMap(Int.init)
        return value.flatMap { Self.targetValueRange.contains($0) ? $0 : nil }
    }

    var dimLevel: Int {
        get { dimLevelView.value }
        set { dimLevelView.value = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTargetValue(_ value: Int?) {
        guard let value, Self.targetValueRange.contains(value) else {
            targetTextField.text = nil
            targetValueChangedHandler?(nil)
            return
        }
        targetTextField.text = "\(value)"
        targetValueChangedHandler?(value)
    }

    @objc private func targetValueEditingChanged() {
        targetValueChangedHandler?(targetValue)
    }

    @objc private func useSensorReading() {
        useSensorReadingHandler?()
    }

    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(16)

        let titleLabel = UILabel(
            text: "calibration_target_sensor_value".localizedString,
            textColor: TextBlack_Color,
            fontSize: 14,
            fontWeight: .regular
        )
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }

        targetTextField.placeholder = "calibration_target_value_placeholder".localizedString
        targetTextField.textColor = SubText_Color
        targetTextField.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        targetTextField.keyboardType = .decimalPad
        targetTextField.layer.borderWidth = 0.5
        targetTextField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        targetTextField.layer.cornerRadius = SCRYFrom(5)
        targetTextField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(8), height: 1))
        targetTextField.leftViewMode = .always
        targetTextField.addTarget(self, action: #selector(targetValueEditingChanged), for: .editingChanged)

        let unitLabel = UILabel(text: "LX", textColor: SubText_Color, fontSize: 15, fontWeight: .light)
        let useReadingButton = UIButton(
            title: "calibration_use_sensor_reading".localizedString,
            titleSize: 12,
            titleWeight: .light,
            titleColor: Bar_Color,
            target: self,
            action: #selector(useSensorReading)
        )
        useReadingButton.layer.borderWidth = 0.5
        useReadingButton.layer.borderColor = RGB(147, 148, 196).cgColor
        useReadingButton.layer.cornerRadius = SCRYFrom(15)

        let inputRow = UIStackView(arrangedSubviews: [targetTextField, unitLabel, useReadingButton])
        inputRow.axis = .horizontal
        inputRow.alignment = .center
        inputRow.spacing = SCRXFrom(8)
        addSubview(inputRow)
        inputRow.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(SCRYFrom(32))
        }
        targetTextField.snp.makeConstraints { make in
            make.width.equalTo(SCRXFrom(152))
            make.height.equalTo(SCRYFrom(32))
        }
        useReadingButton.snp.makeConstraints { make in
            make.width.equalTo(SCRXFrom(114))
            make.height.equalTo(SCRYFrom(32))
        }

        let noteLabel = UILabel(
            text: "calibration_target_sensor_value_note".localizedString,
            textColor: AssistText_Color,
            fontSize: 12,
            fontWeight: .regular,
            fit: false
        )
        noteLabel.numberOfLines = 0
        addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.right.equalTo(inputRow)
            make.top.equalTo(inputRow.snp.bottom).offset(SCRYFrom(12))
        }

        dimLevelView.valueChangedHandler = { [weak self] value in
            self?.dimLevelChangedHandler?(value)
        }
        dimLevelView.throttleValueChangedHandler = { [weak self] value, ended in
            self?.dimLevelThrottleChangedHandler?(value, ended)
        }
        addSubview(dimLevelView)
        dimLevelView.snp.makeConstraints { make in
            make.left.right.equalTo(inputRow)
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalTo(SCRYFrom(-24))
        }
        dimLevel = 50
    }
}

final class LightSensorCalibrationCompleteView: UIView {

    var recalibrateHandler: (() -> Void)?

    private let targetLevelLabel = UILabel()
    private let brightnessLabel = UILabel()
    private let pendingLabel = UILabel()
    private let noticeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        targetLux: Int,
        targetBrightness: Int,
        showsTargetBrightness: Bool,
        pendingDeviceCount: Int,
        profileType: Profile.ProfileType
    ) {
        targetLevelLabel.attributedText = attributedText(
            String(format: "calibration_target_level_value".localizedString, targetLux),
            color: TextBlack_Color,
            fontSize: 12,
            lineHeight: 20
        )
        brightnessLabel.attributedText = attributedText(
            String(format: "calibration_set_at_brightness".localizedString, targetBrightness),
            color: AssistText_Color,
            fontSize: 12,
            lineHeight: 16
        )
        brightnessLabel.isHidden = !showsTargetBrightness
        pendingLabel.text = pendingDeviceCount == 0
            ? nil
            : String(format: "calibration_pending_devices".localizedString, pendingDeviceCount)
        pendingLabel.isHidden = pendingDeviceCount == 0
        noticeLabel.attributedText = noticeAttributedText(profileType: profileType)
    }

    @objc private func recalibrateAction() {
        recalibrateHandler?()
    }

    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(16)
        clipsToBounds = true

        let titleLabel = UILabel(
            text: "calibration_complete".localizedString,
            textColor: Bottom_Done_Color,
            fontSize: 14,
            fontWeight: .regular
        )
        titleLabel.attributedText = attributedText(
            "calibration_complete".localizedString,
            color: Bottom_Done_Color,
            fontSize: 14,
            lineHeight: 20
        )

        targetLevelLabel.numberOfLines = 0
        brightnessLabel.numberOfLines = 0
        let valueStackView = UIStackView(arrangedSubviews: [targetLevelLabel, brightnessLabel])
        valueStackView.axis = .vertical
        valueStackView.spacing = SCRYFrom(2)

        let valueCardView = UIView()
        valueCardView.backgroundColor = RGB(246, 248, 255)
        valueCardView.layer.cornerRadius = SCRYFrom(14)
        valueCardView.addSubview(valueStackView)
        valueStackView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(SCRYFrom(12))
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
        }

        pendingLabel.textColor = RGB(225, 113, 0)
        pendingLabel.font = UIFont.systemFont(ofSize: SCRYFrom(11), weight: .regular)
        pendingLabel.numberOfLines = 0
        pendingLabel.isHidden = true

        noticeLabel.numberOfLines = 0
        let noticeIconView = UIImageView(image: UIImage(named: "site_entry_sync_warning"))
        noticeIconView.contentMode = .scaleAspectFit
        noticeIconView.isAccessibilityElement = false

        let noticeView = UIView()
        noticeView.backgroundColor = RGB(255, 249, 239)
        noticeView.layer.cornerRadius = SCRYFrom(14)
        noticeView.addSubview(noticeIconView)
        noticeIconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(14))
            make.size.equalTo(SCRYFrom(16))
        }
        noticeView.addSubview(noticeLabel)
        noticeLabel.snp.makeConstraints { make in
            make.left.equalTo(noticeIconView.snp.right).offset(SCRXFrom(8))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(12))
        }

        let recalibrateButton = UIButton(type: .custom)
        recalibrateButton.layer.borderWidth = 1
        recalibrateButton.layer.borderColor = Border_Color.cgColor
        recalibrateButton.layer.cornerRadius = SCRYFrom(14)
        recalibrateButton.accessibilityLabel = "recalibrate".localizedString
        recalibrateButton.addTarget(
            self,
            action: #selector(recalibrateAction),
            for: .touchUpInside
        )
        let recalibrateLabel = UILabel(
            text: "recalibrate".localizedString,
            textColor: Bottom_Done_Color,
            fontSize: 14,
            fontWeight: .regular
        )
        recalibrateLabel.attributedText = attributedText(
            "recalibrate".localizedString,
            color: Bottom_Done_Color,
            fontSize: 14,
            lineHeight: 20
        )
        recalibrateLabel.isAccessibilityElement = false
        let disclosureImageView = UIImageView(image: UIImage(named: "night_calibration_disclosure"))
        disclosureImageView.contentMode = .scaleAspectFit
        disclosureImageView.isAccessibilityElement = false
        recalibrateButton.addSubview(recalibrateLabel)
        recalibrateButton.addSubview(disclosureImageView)
        recalibrateLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualTo(disclosureImageView.snp.left).offset(SCRXFrom(-8))
        }
        disclosureImageView.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(16))
        }
        recalibrateButton.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(48))
        }

        let contentStackView = UIStackView(arrangedSubviews: [
            valueCardView,
            pendingLabel,
            noticeView,
            recalibrateButton
        ])
        contentStackView.axis = .vertical
        contentStackView.spacing = SCRYFrom(12)

        let rootStackView = UIStackView(arrangedSubviews: [titleLabel, contentStackView])
        rootStackView.axis = .vertical
        rootStackView.spacing = SCRYFrom(16)
        addSubview(rootStackView)
        rootStackView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(16))
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.bottom.equalToSuperview().offset(SCRYFrom(-20))
        }
    }

    private func noticeAttributedText(profileType: Profile.ProfileType) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = SCRYFrom(17.875)
        paragraphStyle.maximumLineHeight = SCRYFrom(17.875)
        let regularAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: SCRYFrom(11), weight: .regular),
            .foregroundColor: RGB(187, 77, 0),
            .paragraphStyle: paragraphStyle
        ]

        if profileType == .daylight {
            return NSAttributedString(
                string: "calibration_complete_task_notice".localizedString,
                attributes: regularAttributes
            )
        }

        let emphasis = "calibration_complete_occupancy_notice_emphasis".localizedString
        let text = String(
            format: "calibration_complete_occupancy_notice_format".localizedString,
            emphasis
        )
        let attributedText = NSMutableAttributedString(string: text, attributes: regularAttributes)
        let emphasisRange = (text as NSString).range(of: emphasis)
        if emphasisRange.location != NSNotFound {
            attributedText.addAttribute(
                .font,
                value: UIFont.systemFont(ofSize: SCRYFrom(11), weight: .semibold),
                range: emphasisRange
            )
        }
        return attributedText
    }

    private func attributedText(
        _ text: String,
        color: UIColor,
        fontSize: CGFloat,
        lineHeight: CGFloat
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = SCRYFrom(lineHeight)
        paragraphStyle.maximumLineHeight = SCRYFrom(lineHeight)
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: SCRYFrom(fontSize), weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ])
    }
}
