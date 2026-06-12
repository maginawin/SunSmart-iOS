//
//  DeviceLightControlPanelView.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/11.
//

import UIKit

final class DeviceLightControlPanelView: UIView {

    private static let cctInputStep = 10

    struct Configuration: Equatable {
        var controlType: SpaceControlType
        var showCCTQuickButtons: Bool
        var showsBrightness: Bool
        var showsCCT: Bool
        var brightnessValue: Int
        var brightnessRange: ClosedRange<Int>
        var cctValue: Int
        var cctRange: ClosedRange<Int>

        var cctQuickButtonValues: [Int] {
            if cctRange.upperBound >= 6500 {
                return [2700, 3000, 3500, 4000, 5000, 6500]
            }
            return [2700, 3000, 3500, 4000, 5000]
        }

        var showsQuickButtons: Bool {
            showCCTQuickButtons && showsCCT
        }
    }

    var brightnessValueChanged: ((Int) -> Void)?
    var brightnessThrottleValueChanged: ((Int, Bool) -> Void)?
    var cctValueChanged: ((Int) -> Void)?
    var cctThrottleValueChanged: ((Int, Bool) -> Void)?
    var cctQuickButtonValueSelected: ((Int) -> Void)?
    var editBrightnessRequested: (() -> Void)?
    var editCCTRequested: (() -> Void)?

    private let stackView = UIStackView()
    private let simpleBrightnessSlider = BuoySliderView(frame: .zero, functionType: .level())
    private let simpleCCTSlider = BuoySliderView(frame: .zero, functionType: .cct())
    private let detailedBrightnessView = DetailedControlSliderView(functionType: .level())
    private let detailedCCTView = DetailedControlSliderView(functionType: .cct())
    private let quickButtonsView = CCTQuickButtonsView()

    private var configuration: Configuration?
    private var suppressCallbacks = false

    var currentBrightnessValue: Int {
        configuration?.brightnessValue ?? 0
    }
    
    var currentBrightnessRange: ClosedRange<Int> {
        configuration?.brightnessRange ?? 0...100
    }

    var currentCCTValue: Int {
        configuration?.cctValue ?? 0
    }
    
    var currentCCTRange: ClosedRange<Int> {
        configuration?.cctRange ?? 2700...6500
    }

    static func normalizedCCTInputValue(_ value: Int, range: ClosedRange<Int>) -> Int {
        let rounded = Int((Double(value) / Double(cctInputStep)).rounded()) * cctInputStep
        return max(range.lowerBound, min(range.upperBound, rounded))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        bindActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ configuration: Configuration) {
        let shouldRebuildArrangedViews = needsRebuildArrangedViews(from: self.configuration, to: configuration)
        self.configuration = configuration
        suppressCallbacks = true
        UIView.performWithoutAnimation {
            configureSliderValues(configuration)
            if shouldRebuildArrangedViews {
                rebuildArrangedViews(configuration)
            }
            layoutIfNeeded()
        }
        suppressCallbacks = false
    }

    func setBrightnessValue(_ value: Int) {
        guard var configuration else { return }
        let clamped = max(configuration.brightnessRange.lowerBound, min(configuration.brightnessRange.upperBound, value))
        configuration.brightnessValue = clamped
        configure(configuration)
    }

    func setCCTValue(_ value: Int) {
        guard var configuration else { return }
        let clamped = max(configuration.cctRange.lowerBound, min(configuration.cctRange.upperBound, value))
        configuration.cctValue = clamped
        configure(configuration)
    }

    private func setupUI() {
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 0
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        [simpleBrightnessSlider, simpleCCTSlider].forEach { slider in
            slider.slider.interval = 0.3
            slider.snp.makeConstraints { make in
                make.height.equalTo(SCRYFrom(76))
            }
        }

        simpleCCTSlider.slider.step = 10
        detailedCCTView.slider.step = 10
    }

    private func bindActions() {
        simpleBrightnessSlider.valueChangedCallback = { [weak self] value in
            self?.handleBrightnessValueChanged(value)
        }
        simpleBrightnessSlider.valueThrottleChangedCallback = { [weak self] value, ended in
            self?.handleBrightnessThrottleValueChanged(value, ended: ended)
        }
        simpleCCTSlider.valueChangedCallback = { [weak self] value in
            self?.handleCCTValueChanged(value)
        }
        simpleCCTSlider.valueThrottleChangedCallback = { [weak self] value, ended in
            self?.handleCCTThrottleValueChanged(value, ended: ended)
        }

        detailedBrightnessView.valueChanged = { [weak self] value in
            self?.handleBrightnessValueChanged(value)
        }
        detailedBrightnessView.throttleValueChanged = { [weak self] value, ended in
            self?.handleBrightnessThrottleValueChanged(value, ended: ended)
        }
        detailedBrightnessView.editRequested = { [weak self] in
            self?.editBrightnessRequested?()
        }

        detailedCCTView.valueChanged = { [weak self] value in
            self?.handleCCTValueChanged(value)
        }
        detailedCCTView.throttleValueChanged = { [weak self] value, ended in
            self?.handleCCTThrottleValueChanged(value, ended: ended)
        }
        detailedCCTView.editRequested = { [weak self] in
            self?.editCCTRequested?()
        }

        quickButtonsView.valueSelected = { [weak self] value in
            guard let self else { return }
            self.handleCCTQuickButtonValueSelected(value)
        }
    }

    private func configureSliderValues(_ configuration: Configuration) {
        configureBrightnessSlider(simpleBrightnessSlider, configuration: configuration)
        configureBrightnessSlider(detailedBrightnessView.sliderView, configuration: configuration)
        configureCCTSlider(simpleCCTSlider, configuration: configuration)
        configureCCTSlider(detailedCCTView.sliderView, configuration: configuration)

        detailedBrightnessView.configure(
            title: "brightness".localizedString,
            valueText: "\(configuration.brightnessValue)%",
            range: configuration.brightnessRange,
            value: configuration.brightnessValue
        )
        detailedCCTView.configure(
            title: "color_temp".localizedString,
            valueText: "\(configuration.cctValue)K",
            range: configuration.cctRange,
            value: configuration.cctValue
        )
        quickButtonsView.configure(values: configuration.cctQuickButtonValues, selectedValue: configuration.cctValue)
    }

    private func needsRebuildArrangedViews(from oldConfiguration: Configuration?, to newConfiguration: Configuration) -> Bool {
        guard let oldConfiguration else { return true }
        return oldConfiguration.controlType != newConfiguration.controlType
            || oldConfiguration.showsBrightness != newConfiguration.showsBrightness
            || oldConfiguration.showsCCT != newConfiguration.showsCCT
            || oldConfiguration.showsQuickButtons != newConfiguration.showsQuickButtons
    }

    private func configureBrightnessSlider(_ sliderView: BuoySliderView, configuration: Configuration) {
        sliderView.slider.minimumValue = Float(configuration.brightnessRange.lowerBound)
        sliderView.slider.maximumValue = Float(configuration.brightnessRange.upperBound)
        sliderView.slider.limitRange = configuration.brightnessRange
        sliderView.value = configuration.brightnessValue
    }

    private func configureCCTSlider(_ sliderView: BuoySliderView, configuration: Configuration) {
        sliderView.updateCctRange(UInt16(configuration.cctRange.lowerBound)...UInt16(configuration.cctRange.upperBound))
        sliderView.value = configuration.cctValue
    }

    private func rebuildArrangedViews(_ configuration: Configuration) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch configuration.controlType {
        case .simple:
            if configuration.showsBrightness {
                stackView.addArrangedSubview(simpleBrightnessSlider)
            }
            if configuration.showsCCT {
                stackView.addArrangedSubview(simpleCCTSlider)
            }
        case .detailed:
            if configuration.showsBrightness {
                stackView.addArrangedSubview(detailedBrightnessView)
            }
            if configuration.showsCCT {
                stackView.addArrangedSubview(detailedCCTView)
            }
        }

        if configuration.showsQuickButtons {
            stackView.setCustomSpacing(SCRYFit(8), after: configuration.controlType == .simple ? simpleCCTSlider : detailedCCTView)
            stackView.addArrangedSubview(quickButtonsView)
        }
    }

    private func handleBrightnessValueChanged(_ value: Int) {
        guard !suppressCallbacks else { return }
        updateStoredBrightness(value)
        brightnessValueChanged?(value)
    }

    private func handleBrightnessThrottleValueChanged(_ value: Int, ended: Bool) {
        guard !suppressCallbacks else { return }
        brightnessThrottleValueChanged?(value, ended)
    }

    private func handleCCTValueChanged(_ value: Int) {
        guard !suppressCallbacks else { return }
        updateStoredCCT(value)
        cctValueChanged?(value)
    }

    private func handleCCTThrottleValueChanged(_ value: Int, ended: Bool) {
        guard !suppressCallbacks else { return }
        cctThrottleValueChanged?(value, ended)
    }

    private func handleCCTQuickButtonValueSelected(_ value: Int) {
        guard !suppressCallbacks else { return }
        cctQuickButtonValueSelected?(value)
    }

    private func updateStoredBrightness(_ value: Int) {
        guard var configuration else { return }
        configuration.brightnessValue = max(configuration.brightnessRange.lowerBound, min(configuration.brightnessRange.upperBound, value))
        self.configuration = configuration
        detailedBrightnessView.updateValueText("\(configuration.brightnessValue)%")
    }

    private func updateStoredCCT(_ value: Int) {
        guard var configuration else { return }
        configuration.cctValue = max(configuration.cctRange.lowerBound, min(configuration.cctRange.upperBound, value))
        self.configuration = configuration
        detailedCCTView.updateValueText("\(configuration.cctValue)K")
        quickButtonsView.configure(values: configuration.cctQuickButtonValues, selectedValue: configuration.cctValue)
    }
}

private final class DetailedControlSliderView: UIView {

    let sliderView: BuoySliderView
    var valueChanged: ((Int) -> Void)?
    var throttleValueChanged: ((Int, Bool) -> Void)?
    var editRequested: (() -> Void)?

    private let titleLabel = UILabel(text: "", textColor: RGB(100, 116, 139), fontSize: 14, fontWeight: .light)
    private let valueButton = UIButton(type: .system)

    var slider: CustomDeviceSlider {
        sliderView.slider
    }

    init(functionType: DeviceSliderFunctionView.FunctionType) {
        sliderView = BuoySliderView(frame: .zero, functionType: functionType)
        super.init(frame: .zero)
        setupUI()
        bindActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, valueText: String, range: ClosedRange<Int>, value: Int) {
        titleLabel.text = title
        updateValueText(valueText)
        sliderView.slider.minimumValue = Float(range.lowerBound)
        sliderView.slider.maximumValue = Float(range.upperBound)
        sliderView.slider.limitRange = range
        sliderView.value = value
    }

    func updateValueText(_ text: String) {
        if valueButton.attributedTitle(for: .normal)?.string == text {
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: FONTS(SCRYFrom(14)),
            .foregroundColor: RGB(46, 49, 93),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        UIView.performWithoutAnimation {
            valueButton.setAttributedTitle(NSAttributedString(string: text, attributes: attributes), for: .normal)
            valueButton.layoutIfNeeded()
        }
    }

    private func setupUI() {
        insertSubview(sliderView, at: 0)
        sliderView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(SCRYFrom(76))
        }

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.bottom.equalTo(sliderView.slider.snp.top).offset(SCRYFit(-4))
        }

        valueButton.contentHorizontalAlignment = .right
        valueButton.addTarget(self, action: #selector(valueButtonClick), for: .touchUpInside)
        addSubview(valueButton)
        valueButton.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalTo(titleLabel)
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(12))
        }

        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(76))
        }
    }

    private func bindActions() {
        sliderView.valueChangedCallback = { [weak self] value in
            self?.setSliderOverlayActive(true)
            self?.valueChanged?(value)
        }
        sliderView.valueThrottleChangedCallback = { [weak self] value, ended in
            self?.setSliderOverlayActive(!ended)
            self?.throttleValueChanged?(value, ended)
        }
    }

    private func setSliderOverlayActive(_ active: Bool) {
        if active {
            bringSubviewToFront(sliderView)
        } else {
            insertSubview(sliderView, at: 0)
        }
    }

    @objc private func valueButtonClick() {
        editRequested?()
    }
}

private final class CCTQuickButtonsView: UIView {

    var valueSelected: ((Int) -> Void)?

    private let stackView = UIStackView()
    private var buttons: [UIButton] = []
    private var values: [Int] = []
    private var selectedValue: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(values: [Int], selectedValue: Int) {
        if self.values == values, !buttons.isEmpty {
            updateSelection(selectedValue)
            setNeedsLayout()
            return
        }

        self.values = values
        self.selectedValue = nil
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        values.enumerated().forEach { index, value in
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.font = FONTS(SCRYFrom(12))
            button.layer.cornerRadius = SCRYFrom(16)
            button.layer.borderWidth = 1
            button.setTitle("\(value)K", for: .normal)
            button.addTarget(self, action: #selector(buttonClick(sender:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
            button.snp.makeConstraints { make in
                make.width.equalTo(SCRXFrom(48))
                make.height.equalTo(SCRYFrom(32))
            }
            buttons.append(button)
        }

        updateSelection(selectedValue)
        setNeedsLayout()
    }

    private func setupUI() {
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(SCRYFrom(32))
        }
        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(32))
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateButtonMetrics()
    }

    private func updateSelection(_ selectedValue: Int) {
        if self.selectedValue == selectedValue {
            return
        }
        self.selectedValue = selectedValue

        UIView.performWithoutAnimation {
            buttons.enumerated().forEach { index, button in
                let isSelected = values[index] == selectedValue
                button.backgroundColor = isSelected ? RGB(102, 103, 171) : .white
                button.layer.borderColor = isSelected ? RGB(102, 103, 171).cgColor : RGB(236, 236, 236).cgColor
                button.setTitleColor(isSelected ? .white : RGB(102, 103, 171), for: .normal)
                button.layoutIfNeeded()
            }
        }
    }
    
    private func updateButtonMetrics() {
        guard !buttons.isEmpty, bounds.width > 0 else { return }
        let spacing = SCRXFrom(4)
        let availableWidth = bounds.width - CGFloat(max(buttons.count - 1, 0)) * spacing
        let buttonWidth = min(SCRXFrom(48), max(SCRXFrom(34), floor(availableWidth / CGFloat(buttons.count))))
        stackView.spacing = spacing
        
        buttons.forEach { button in
            let fontSize = buttonWidth < SCRXFrom(40) ? SCRYFrom(10) : (buttonWidth < SCRXFrom(45) ? SCRYFrom(11) : SCRYFrom(12))
            button.titleLabel?.font = FONTS(fontSize)
            button.snp.updateConstraints { make in
                make.width.equalTo(buttonWidth)
            }
        }
    }

    @objc private func buttonClick(sender: UIButton) {
        guard values.indices.contains(sender.tag) else { return }
        valueSelected?(values[sender.tag])
    }
}
