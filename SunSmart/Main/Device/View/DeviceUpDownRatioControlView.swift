//
//  DeviceUpDownRatioControlView.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/13.
//

import UIKit

final class DeviceUpDownRatioControlView: UIView {

    var valueChanging: ((Int) -> Void)?
    var valueSampled: ((Int) -> Void)?
    var valueChanged: ((Int) -> Void)?

    var upValue: Int {
        get {
            currentUpValue
        }
        set {
            setUpValue(newValue, notifyChanging: false, notifyChanged: false)
        }
    }

    var downValue: Int {
        100 - upValue
    }

    private let titleLabel = UILabel(text: "Up/Down Ratio", textColor: RGB(100, 116, 139), fontSize: 14, fontWeight: .light)
    private let valueLabel = UILabel(text: "50/50", textColor: RGB(46, 49, 93), fontSize: 14, fontWeight: .light)
    private let sliderView = BuoySliderView(frame: .zero, functionType: .level())
    private let quickButtonsView = UpDownRatioQuickButtonsView()

    private var currentUpValue = -1
    private var suppressCallbacks = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        bindActions()
        setUpValue(50, notifyChanging: false, notifyChanged: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
        }

        valueLabel.textAlignment = .right
        addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(12))
        }

        sliderView.slider.minimumValue = 0
        sliderView.slider.maximumValue = 100
        sliderView.slider.step = 1
        sliderView.slider.limitRange = 0...100
        sliderView.slider.interval = 0.3
        sliderView.slider.sendsFinalValueOnTouchCancel = true
        sliderView.slider.minimumTrackTintColor = Slider_Color
        sliderView.slider.maximumTrackTintColor = RGB(229, 229, 229)
        sliderView.valueTextProvider = { [weak self] value in
            self?.ratioText(upValue: self?.upValue(fromSliderValue: value) ?? 50) ?? "50/50"
        }
        addSubview(sliderView)
        sliderView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFit(4))
            make.height.equalTo(SCRYFrom(40))
        }

        addSubview(quickButtonsView)
        quickButtonsView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(sliderView.snp.bottom).offset(SCRYFit(8))
            make.height.equalTo(SCRYFrom(32))
            make.bottom.equalToSuperview()
        }
    }

    private func bindActions() {
        sliderView.valueChangedCallback = { [weak self] value in
            guard let self = self else { return }
            self.setUpValue(self.upValue(fromSliderValue: value), notifyChanging: true, notifyChanged: false)
        }

        sliderView.valueThrottleChangedCallback = { [weak self] value, ended in
            guard let self = self else { return }
            let upValue = self.upValue(fromSliderValue: value)
            if ended {
                self.valueChanged?(upValue)
            } else {
                self.valueSampled?(upValue)
            }
        }

        quickButtonsView.valueSelected = { [weak self] value in
            self?.setUpValue(value, notifyChanging: true, notifyChanged: true)
        }
    }

    private func setUpValue(_ value: Int, notifyChanging: Bool, notifyChanged: Bool) {
        let clampedValue = max(0, min(100, value))
        guard clampedValue != currentUpValue else { return }
        currentUpValue = clampedValue

        UIView.performWithoutAnimation {
            sliderView.value = sliderValue(fromUpValue: clampedValue)
            valueLabel.text = ratioText(upValue: clampedValue)
            quickButtonsView.configure(selectedValue: clampedValue)
        }

        guard !suppressCallbacks else { return }
        if notifyChanging {
            valueChanging?(clampedValue)
        }
        if notifyChanged {
            valueChanged?(clampedValue)
        }
    }

    private func ratioText(upValue: Int) -> String {
        "\(upValue)/\(100 - upValue)"
    }

    private func upValue(fromSliderValue value: Int) -> Int {
        100 - max(0, min(100, value))
    }

    private func sliderValue(fromUpValue value: Int) -> Int {
        100 - max(0, min(100, value))
    }
}

private final class UpDownRatioQuickButtonsView: UIView {

    var valueSelected: ((Int) -> Void)?

    private let stackView = UIStackView()
    private let values = [100, 70, 50, 30, 0]
    private var buttons: [UIButton] = []
    private var selectedValue: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        configure(selectedValue: 50)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(selectedValue: Int) {
        let normalizedValue = values.contains(selectedValue) ? selectedValue : nil
        guard normalizedValue != self.selectedValue else { return }
        self.selectedValue = normalizedValue

        UIView.performWithoutAnimation {
            buttons.enumerated().forEach { index, button in
                let value = values[index]
                let isSelected = value == self.selectedValue
                button.backgroundColor = isSelected ? RGB(102, 103, 171) : .white
                button.layer.borderColor = isSelected ? RGB(102, 103, 171).cgColor : RGB(236, 236, 236).cgColor
                button.setTitleColor(isSelected ? .white : RGB(102, 103, 171), for: .normal)
            }
        }
    }

    private func setupUI() {
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = SCRXFrom(6)
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        values.enumerated().forEach { index, value in
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.font = FONTS(SCRYFrom(12))
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.7
            button.layer.cornerRadius = SCRYFrom(16)
            button.layer.borderWidth = 1
            button.setTitle("\(value)/\(100 - value)", for: .normal)
            button.addTarget(self, action: #selector(buttonClick(sender:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
            button.snp.makeConstraints { make in
                make.height.equalTo(SCRYFrom(32))
            }
            buttons.append(button)
        }
    }

    @objc private func buttonClick(sender: UIButton) {
        guard values.indices.contains(sender.tag) else { return }
        valueSelected?(values[sender.tag])
    }
}
