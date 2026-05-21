//
//  DeviceParameterSettingsViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/14.
//

import UIKit
import SnapKit
import NordicSigMeshSDK

protocol DeviceParameterSettingsViewCellDelegate: AnyObject {

    /// 设置参数
    func cell(_ cell: DeviceParameterSettingsViewCell, settingParameters data: DeviceParameterData)

    /// 修改启用/禁用开关
    func cell(_ cell: DeviceParameterSettingsViewCell, parameterEnableStateChanged enable: Bool)

}

class DeviceParameterSettingsViewCell: UITableViewCell {

    private var containerView: UIView!
    var titleLabel: UILabel!
    var textField: UITextField!
    var unitLabel: UILabel!
    var messageLabel: UILabel!
    var enableSwitch: UISwitch!
    weak var delegate: DeviceParameterSettingsViewCellDelegate?

    var parameterData: DeviceParameterData! {
        didSet {

            let data = parameterData.type.data
            titleLabel.text = data.title

            enableSwitch.isOn = parameterData.enable

            messageLabel.isHidden = false
            textField.isHidden = false
            unitLabel.isHidden = false
            messageLabel.isHidden = false

            messageLabel.text = data.message
            if let range = data.range {
                textField.placeholder = "\(range.lowerBound)~\(range.upperBound)"
            }else {
                textField.placeholder = nil
            }
            if let value = parameterData.data as? Int {
                textField.text = "\(value)"
            }else {
                textField.text = nil
            }
            unitLabel.text = data.unit

            updateParameterEnable(enable: parameterData.enable)
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none
//        layer.cornerRadius = SCRYFrom(10)
//        backgroundColor = .white
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateParameterEnable(enable: Bool) {
        enableSwitch.isOn = enable
        if enable {

            messageLabel.isHidden = false
            textField.isHidden = false
            unitLabel.isHidden = false
            messageLabel.isHidden = false

            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24)).priority(.high)
            }

            messageLabel.snp.remakeConstraints { make in
                make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(10)).priority(.high)
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.bottom.equalTo(SCRYFrom(-22)).priority(.high)
            }
        }else {

            messageLabel.isHidden = true
            textField.isHidden = true
            unitLabel.isHidden = true
            messageLabel.isHidden = true

            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24)).priority(.high)
                make.bottom.equalTo(SCRYFrom(-23))
            }

            messageLabel.snp.remakeConstraints { make in
                make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(10)).priority(.high)
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
            }

        }
    }

    @objc private func enableSwitchValueChanged(sender: UISwitch) {
        updateParameterEnable(enable: sender.isOn)

        delegate?.cell(self, parameterEnableStateChanged: sender.isOn)
    }

    private func setupUI() {

        containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-16))
        }

        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14)
        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(24)).priority(.high)
        }

        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged), for: .valueChanged)
        containerView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }

        textField = UITextField()
        textField.font = UIFont.systemFont(ofSize: SCRYFrom(13), weight: .light)
//        textField.placeholder = "password".localizedString
        textField.textColor = TextBlack_Color
        textField.layer.cornerRadius = SCRYFrom(5)
        textField.layer.borderColor = RGB(220, 220, 220).cgColor
        textField.layer.borderWidth = 0.6
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        textField.leftViewMode = .always
        textField.textAlignment = .center
        textField.backgroundColor = Background_Color
        textField.delegate = self
        containerView.addSubview(textField)
        textField.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16)).priority(.high)
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(96))
            make.height.equalTo(SCRYFrom(32))
        }

        unitLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        containerView.addSubview(unitLabel)
        unitLabel.snp.makeConstraints { make in
            make.left.equalTo(textField.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(textField).offset(SCRYFrom(1))
        }

        messageLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        containerView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(10)).priority(.high)
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-22))
        }

    }

}

extension DeviceParameterSettingsViewCell: UITextFieldDelegate {

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        delegate?.cell(self, settingParameters: parameterData)
        return false
    }

}

protocol DeviceParameterChangeControlPageViewCellDelegate: AnyObject {
    func cell(_ cell: DeviceParameterChangeControlPageViewCell, parameterEnableStateChanged enable: Bool)
    func cell(_ cell: DeviceParameterChangeControlPageViewCell, didSelect value: NodeChangeControlPage)
}

final class DeviceParameterChangeControlPageViewCell: UITableViewCell {

    private var containerView: UIView!
    private var titleLabel: UILabel!
    private var enableSwitch: UISwitch!
    private var optionsContainerView: UIView!
    private var singleWhiteContentView: UIView!
    private var singleWhiteButton: UIControl!
    private var singleWhiteIconView: UIImageView!
    private var singleWhiteLabel: UILabel!
    private var tunableWhiteContentView: UIView!
    private var tunableWhiteButton: UIControl!
    private var tunableWhiteIconView: UIImageView!
    private var tunableWhiteLabel: UILabel!
    private var noteLabel: UILabel!
    private var selectedValue: NodeChangeControlPage = .tunableWhite
    private var defaultValue: NodeChangeControlPage = .tunableWhite

    weak var delegate: DeviceParameterChangeControlPageViewCellDelegate?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setupUI()
        updateParameterEnable(enable: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(value: NodeChangeControlPage, enabled: Bool, defaultValue: NodeChangeControlPage) {
        self.selectedValue = value
        self.defaultValue = defaultValue
        configureOptionTitles()
        updateOptionUI()
        updateParameterEnable(enable: enabled)
    }
    
    private func configureOptionTitles() {
        let defaultText = "default".localizedString
        let singleWhiteText = "single_white".localizedString
        let tunableWhiteText = "tunable_white".localizedString
        singleWhiteLabel.text = defaultValue == .singleWhite ? "\(singleWhiteText) (\(defaultText))" : singleWhiteText
        tunableWhiteLabel.text = defaultValue == .tunableWhite ? "\(tunableWhiteText) (\(defaultText))" : tunableWhiteText
    }

    private func updateOptionUI() {
        singleWhiteIconView.image = UIImage(named: selectedValue == .singleWhite ? "select" : "select_un")
        tunableWhiteIconView.image = UIImage(named: selectedValue == .tunableWhite ? "select" : "select_un")
    }

    private func updateParameterEnable(enable: Bool) {
        enableSwitch.isOn = enable
        optionsContainerView.isHidden = !enable
        noteLabel.isHidden = !enable

        if enable {
            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24)).priority(.high)
            }
            noteLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(optionsContainerView.snp.bottom).offset(SCRYFrom(14)).priority(.high)
                make.bottom.equalTo(SCRYFrom(-20)).priority(.high)
            }
        }else {
            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24)).priority(.high)
                make.bottom.equalTo(SCRYFrom(-23)).priority(.high)
            }
            noteLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(optionsContainerView.snp.bottom).offset(SCRYFrom(14)).priority(.high)
            }
        }
    }

    @objc private func enableSwitchValueChanged(_ sender: UISwitch) {
        updateParameterEnable(enable: sender.isOn)
        delegate?.cell(self, parameterEnableStateChanged: sender.isOn)
    }

    @objc private func optionTapped(_ sender: UIControl) {
        selectedValue = sender === singleWhiteButton ? .singleWhite : .tunableWhite
        updateOptionUI()
        delegate?.cell(self, didSelect: selectedValue)
    }

    private func setupUI() {
        containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-16))
        }

        titleLabel = UILabel(text: "change_control_page".localizedString + ":", textColor: TextBlack_Color, fontSize: 14)
        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(24)).priority(.high)
        }

        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged(_:)), for: .valueChanged)
        containerView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }

        optionsContainerView = UIView()
        optionsContainerView.backgroundColor = RGB(249, 250, 252)
        optionsContainerView.layer.cornerRadius = SCRYFrom(7)
        containerView.addSubview(optionsContainerView)
        optionsContainerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(20)).priority(.high)
            make.height.equalTo(SCRYFrom(40))
        }

        singleWhiteContentView = UIView()
        optionsContainerView.addSubview(singleWhiteContentView)
        singleWhiteContentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(30))
        }

        tunableWhiteContentView = UIView()
        optionsContainerView.addSubview(tunableWhiteContentView)
        tunableWhiteContentView.snp.makeConstraints { make in
            make.left.equalTo(singleWhiteContentView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(30))
            make.right.lessThanOrEqualTo(SCRXFrom(-8))
        }

        singleWhiteIconView = UIImageView(image: UIImage(named: "select_un"))
        singleWhiteContentView.addSubview(singleWhiteIconView)
        singleWhiteIconView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }

        singleWhiteLabel = UILabel(text: "single_white".localizedString, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        singleWhiteLabel.adjustsFontSizeToFitWidth = true
        singleWhiteLabel.minimumScaleFactor = 0.75
        singleWhiteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        singleWhiteContentView.addSubview(singleWhiteLabel)
        singleWhiteLabel.snp.makeConstraints { make in
            make.left.equalTo(singleWhiteIconView.snp.right).offset(SCRXFrom(4))
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }

        tunableWhiteIconView = UIImageView(image: UIImage(named: "select_un"))
        tunableWhiteContentView.addSubview(tunableWhiteIconView)
        tunableWhiteIconView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }

        tunableWhiteLabel = UILabel(text: "tunable_white".localizedString, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        tunableWhiteLabel.adjustsFontSizeToFitWidth = true
        tunableWhiteLabel.minimumScaleFactor = 0.75
        tunableWhiteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tunableWhiteContentView.addSubview(tunableWhiteLabel)
        tunableWhiteLabel.snp.makeConstraints { make in
            make.left.equalTo(tunableWhiteIconView.snp.right).offset(SCRXFrom(4))
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }

        singleWhiteButton = UIControl()
        singleWhiteButton.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
        optionsContainerView.addSubview(singleWhiteButton)
        singleWhiteButton.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.right.equalTo(singleWhiteContentView.snp.right).offset(SCRXFrom(4))
        }

        tunableWhiteButton = UIControl()
        tunableWhiteButton.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
        optionsContainerView.addSubview(tunableWhiteButton)
        tunableWhiteButton.snp.makeConstraints { make in
            make.left.equalTo(tunableWhiteContentView.snp.left).offset(SCRXFrom(-4))
            make.top.bottom.equalToSuperview()
            make.right.equalTo(tunableWhiteContentView.snp.right).offset(SCRXFrom(8))
        }

        noteLabel = UILabel(text: "change_control_page_message".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0
        containerView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(optionsContainerView.snp.bottom).offset(SCRYFrom(14)).priority(.high)
            make.bottom.equalTo(SCRYFrom(-20)).priority(.high)
        }
    }
}

protocol DeviceParameterAbsoluteCctRangeViewCellDelegate: AnyObject {
    func cell(_ cell: DeviceParameterAbsoluteCctRangeViewCell, parameterEnableStateChanged enable: Bool)
    func cell(_ cell: DeviceParameterAbsoluteCctRangeViewCell, rangeChanged range: ClosedRange<UInt16>)
    func absoluteCctRangeViewCellResetAction(_ cell: DeviceParameterAbsoluteCctRangeViewCell)
}

protocol DeviceParameterCctRangeSliderDelegate: AnyObject {
    func cctRangeSlider(_ slider: DeviceParameterCctRangeSlider, rangeChanged range: ClosedRange<UInt16>)
}

final class DeviceParameterCctRangeSlider: UIControl {

    enum Thumb {
        case lower
        case upper
    }

    private let trackLayer = CALayer()
    private let highlightedTrackLayer = CALayer()
    private let lowerThumbImageView = UIImageView(image: UIImage(named: "slider_point"))
    private let upperThumbImageView = UIImageView(image: UIImage(named: "slider_point"))

    private(set) var selectedThumb: Thumb = .upper
    private var lowerBound: UInt16 = NodeAbsoluteCctRange.defaultRange.lowerBound
    private var upperBound: UInt16 = NodeAbsoluteCctRange.defaultRange.upperBound

    weak var delegate: DeviceParameterCctRangeSliderDelegate?

    private var thumbSize: CGFloat { SCRYFrom(30) }
    private var usableWidth: CGFloat { max(1, bounds.width - thumbSize) }
    private var absoluteMinBound: UInt16 { NodeAbsoluteCctRange.minLowerBound }
    private var absoluteMaxBound: UInt16 { NodeAbsoluteCctRange.maxUpperBound }
    private var absoluteRange: CGFloat { max(1, CGFloat(absoluteMaxBound - absoluteMinBound)) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSlider()
    }

    func configure(range: ClosedRange<UInt16>) {
        lowerBound = normalizedLower(range.lowerBound)
        upperBound = normalizedUpper(range.upperBound)
        setNeedsLayout()
    }

    func stepSelectedThumb(by step: Int) {
        switch selectedThumb {
        case .lower:
            lowerBound = normalizedLower(steppedValue(lowerBound, by: step))
        case .upper:
            upperBound = normalizedUpper(steppedValue(upperBound, by: step))
        }
        layoutSlider()
        notifyRangeChanged()
    }

    private func setupUI() {
        trackLayer.backgroundColor = RGB(220, 220, 220).cgColor
        highlightedTrackLayer.backgroundColor = Slider_Color.cgColor
        layer.addSublayer(trackLayer)
        layer.addSublayer(highlightedTrackLayer)

        [lowerThumbImageView, upperThumbImageView].forEach {
            $0.contentMode = .scaleAspectFit
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }

    private func normalizedLower(_ value: UInt16) -> UInt16 {
        let rounded = roundedToStep(value)
        return min(max(rounded, NodeAbsoluteCctRange.minLowerBound), NodeAbsoluteCctRange.maxLowerBound)
    }

    private func normalizedUpper(_ value: UInt16) -> UInt16 {
        let rounded = roundedToStep(value)
        return min(max(rounded, NodeAbsoluteCctRange.minUpperBound), NodeAbsoluteCctRange.maxUpperBound)
    }

    private func roundedToStep(_ value: UInt16) -> UInt16 {
        let step = Int(NodeAbsoluteCctRange.step)
        let rounded = ((Int(value) + step / 2) / step) * step
        return UInt16(min(rounded, Int(UInt16.max)))
    }

    private func steppedValue(_ value: UInt16, by step: Int) -> UInt16 {
        let value = Int(value) + step
        return UInt16(max(0, min(value, Int(UInt16.max))))
    }

    private func xPosition(for value: UInt16) -> CGFloat {
        let clampedValue = min(max(value, absoluteMinBound), absoluteMaxBound)
        let progress = CGFloat(clampedValue - absoluteMinBound) / absoluteRange
        return usableWidth * progress
    }

    private func lowerValue(for x: CGFloat) -> UInt16 {
        let lowerMaxX = xPosition(for: NodeAbsoluteCctRange.maxLowerBound)
        let position = max(0, min(x - thumbSize / 2, lowerMaxX))
        let progress = position / usableWidth
        let value = CGFloat(absoluteMinBound) + absoluteRange * progress
        return normalizedLower(UInt16(value.rounded()))
    }

    private func upperValue(for x: CGFloat) -> UInt16 {
        let upperMinX = xPosition(for: NodeAbsoluteCctRange.minUpperBound)
        let position = max(upperMinX, min(x - thumbSize / 2, usableWidth))
        let progress = position / usableWidth
        let value = CGFloat(absoluteMinBound) + absoluteRange * progress
        return normalizedUpper(UInt16(value.rounded()))
    }

    private func layoutSlider() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let trackHeight = SCRYFrom(4)
        let trackY = (bounds.height - trackHeight) / 2
        let trackX = thumbSize / 2
        let lowerX = xPosition(for: lowerBound)
        let upperX = xPosition(for: upperBound)
        let lowerCenterX = lowerX + thumbSize / 2
        let upperCenterX = upperX + thumbSize / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.cornerRadius = trackHeight / 2
        trackLayer.frame = CGRect(x: trackX, y: trackY, width: usableWidth, height: trackHeight)
        highlightedTrackLayer.cornerRadius = trackHeight / 2
        highlightedTrackLayer.frame = CGRect(
            x: lowerCenterX,
            y: trackY,
            width: max(0, upperCenterX - lowerCenterX),
            height: trackHeight
        )
        CATransaction.commit()

        let thumbY = (bounds.height - thumbSize) / 2
        lowerThumbImageView.frame = CGRect(x: lowerX, y: thumbY, width: thumbSize, height: thumbSize)
        upperThumbImageView.frame = CGRect(x: upperX, y: thumbY, width: thumbSize, height: thumbSize)
    }

    private func nearestThumb(to point: CGPoint) -> Thumb {
        let lowerDistance = abs(point.x - lowerThumbImageView.center.x)
        let upperDistance = abs(point.x - upperThumbImageView.center.x)
        return lowerDistance < upperDistance ? .lower : .upper
    }

    private func updateSelectedThumb(at point: CGPoint) {
        selectedThumb = nearestThumb(to: point)
        switch selectedThumb {
        case .lower:
            lowerBound = lowerValue(for: point.x)
        case .upper:
            upperBound = upperValue(for: point.x)
        }
        layoutSlider()
        notifyRangeChanged()
    }

    private func notifyRangeChanged() {
        delegate?.cctRangeSlider(self, rangeChanged: lowerBound...upperBound)
        sendActions(for: .valueChanged)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            selectedThumb = nearestThumb(to: point)
            fallthrough
        case .changed:
            switch selectedThumb {
            case .lower:
                lowerBound = lowerValue(for: point.x)
            case .upper:
                upperBound = upperValue(for: point.x)
            }
            layoutSlider()
            notifyRangeChanged()
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        updateSelectedThumb(at: gesture.location(in: self))
    }
}

final class DeviceParameterAbsoluteCctRangeViewCell: UITableViewCell {

    private var containerView: UIView!
    private var titleLabel: UILabel!
    private var enableSwitch: UISwitch!
    private var resetBtn: UIButton!
    private var sliderContentView: UIView!
    private var lowerValueLabel: UILabel!
    private var upperValueLabel: UILabel!
    private var minusBtn: UIButton!
    private var addBtn: UIButton!
    private var cctRangeSlider: DeviceParameterCctRangeSlider!
    private var noteLabel: UILabel!

    private var lowerBound: UInt16 = NodeAbsoluteCctRange.defaultRange.lowerBound
    private var upperBound: UInt16 = NodeAbsoluteCctRange.defaultRange.upperBound

    weak var delegate: DeviceParameterAbsoluteCctRangeViewCellDelegate?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setupUI()
        updateParameterEnable(enable: false)
        updateValueLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(range: ClosedRange<UInt16>, enabled: Bool) {
        lowerBound = range.lowerBound
        upperBound = range.upperBound
        normalizeRange()
        updateValueLabels()
        cctRangeSlider.configure(range: lowerBound...upperBound)
        updateParameterEnable(enable: enabled)
    }

    private func updateParameterEnable(enable: Bool) {
        enableSwitch.isOn = enable
        resetBtn.isHidden = !enable
        sliderContentView.isHidden = !enable
        noteLabel.isHidden = !enable

        if enable {
            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24)).priority(.high)
            }
            noteLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(sliderContentView.snp.bottom).offset(SCRYFrom(16)).priority(.high)
                make.bottom.equalTo(SCRYFrom(-20)).priority(.high)
            }
        }else {
            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24)).priority(.high)
                make.bottom.equalTo(SCRYFrom(-23)).priority(.high)
            }
            noteLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(sliderContentView.snp.bottom).offset(SCRYFrom(16)).priority(.high)
            }
        }
    }

    private func normalizeRange() {
        lowerBound = min(max(lowerBound, NodeAbsoluteCctRange.minLowerBound), NodeAbsoluteCctRange.maxLowerBound)
        upperBound = min(max(upperBound, NodeAbsoluteCctRange.minUpperBound), NodeAbsoluteCctRange.maxUpperBound)
        if lowerBound >= upperBound {
            lowerBound = min(NodeAbsoluteCctRange.maxLowerBound, upperBound - NodeAbsoluteCctRange.step)
        }
    }

    private func updateValueLabels() {
        lowerValueLabel.text = "\(lowerBound)K"
        upperValueLabel.text = "\(upperBound)K"
    }

    @objc private func enableSwitchValueChanged(_ sender: UISwitch) {
        updateParameterEnable(enable: sender.isOn)
        delegate?.cell(self, parameterEnableStateChanged: sender.isOn)
    }

    @objc private func resetBtnAction() {
        delegate?.absoluteCctRangeViewCellResetAction(self)
    }

    @objc private func minusBtnClick() {
        cctRangeSlider.stepSelectedThumb(by: -Int(NodeAbsoluteCctRange.step))
    }

    @objc private func addBtnClick() {
        cctRangeSlider.stepSelectedThumb(by: Int(NodeAbsoluteCctRange.step))
    }

    private func setupUI() {
        containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-16))
        }

        titleLabel = UILabel(text: "absolute_cct_range".localizedString + ":", textColor: TextBlack_Color, fontSize: 14)
        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(24)).priority(.high)
        }

        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged(_:)), for: .valueChanged)
        containerView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }

        resetBtn = UIButton(title: "reset".localizedString, titleSize: 12, titleWeight: .regular, titleColor: Bar_Color, target: self, action: #selector(resetBtnAction))
        resetBtn.layer.cornerRadius = SCRYFrom(12)
        resetBtn.layer.borderWidth = 0.5
        resetBtn.layer.borderColor = Bar_Color.withAlphaComponent(0.5).cgColor
        resetBtn.isHidden = true
        containerView.addSubview(resetBtn)
        resetBtn.snp.makeConstraints { make in
            make.right.equalTo(enableSwitch.snp.left).offset(SCRXFrom(-24))
            make.centerY.equalTo(titleLabel)
            make.height.equalTo(SCRYFrom(24))
            make.width.greaterThanOrEqualTo(SCRXFrom(56))
        }

        sliderContentView = UIView()
        containerView.addSubview(sliderContentView)
        sliderContentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(20)).priority(.high)
            make.height.equalTo(SCRYFrom(76))
        }

        lowerValueLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        sliderContentView.addSubview(lowerValueLabel)
        lowerValueLabel.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.equalToSuperview()
        }

        upperValueLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        upperValueLabel.textAlignment = .right
        sliderContentView.addSubview(upperValueLabel)
        upperValueLabel.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.top.equalToSuperview()
        }

        minusBtn = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(minusBtnClick))
        sliderContentView.addSubview(minusBtn)
        minusBtn.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.bottom.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }

        addBtn = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(addBtnClick))
        sliderContentView.addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalTo(minusBtn)
            make.width.height.equalTo(SCRYFrom(30))
        }

        cctRangeSlider = DeviceParameterCctRangeSlider()
        cctRangeSlider.delegate = self
        sliderContentView.addSubview(cctRangeSlider)
        cctRangeSlider.snp.makeConstraints { make in
            make.left.equalTo(minusBtn.snp.right).offset(SCRXFrom(15))
            make.right.equalTo(addBtn.snp.left).offset(SCRXFrom(-15))
            make.centerY.equalTo(minusBtn)
            make.height.equalTo(SCRYFrom(40))
        }

        noteLabel = UILabel(text: "absolute_cct_range_message".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0
        containerView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(sliderContentView.snp.bottom).offset(SCRYFrom(16)).priority(.high)
            make.bottom.equalTo(SCRYFrom(-20)).priority(.high)
        }
    }
}

extension DeviceParameterAbsoluteCctRangeViewCell: DeviceParameterCctRangeSliderDelegate {

    func cctRangeSlider(_ slider: DeviceParameterCctRangeSlider, rangeChanged range: ClosedRange<UInt16>) {
        lowerBound = range.lowerBound
        upperBound = range.upperBound
        updateValueLabels()
        delegate?.cell(self, rangeChanged: range)
    }

}

protocol DeviceParameterBehaviorAfterSetupViewCellDelegate: AnyObject {
    func cell(_ cell: DeviceParameterBehaviorAfterSetupViewCell, didSelect mode: DeviceBlinkMode)
    func cell(_ cell: DeviceParameterBehaviorAfterSetupViewCell, detailsExpandedChanged expanded: Bool)
}

class DeviceParameterBehaviorAfterSetupViewCell: UITableViewCell {


    private var containerView: UIView!
    private var titleLabel: UILabel!
    private var optionButtons: [UIButton] = []
    private var detailsRow: UIControl!
    private var detailsTitleLabel: UILabel!
    private var detailsArrowImageView: UIImageView!
    private var noteLabel: UILabel!
    private var noteLabelHeightConstraint: Constraint?
    private var noteLabelTopConstraint: Constraint?

    weak var delegate: DeviceParameterBehaviorAfterSetupViewCellDelegate?

    var selectedMode: DeviceBlinkMode = .breathing {
        didSet {
            updateOptionUI()
        }
    }

    var detailsExpanded: Bool = true {
        didSet {
            updateDetailsUI()
        }
    }

    func configure(mode: DeviceBlinkMode, detailsExpanded: Bool, noteText: String? = nil) {
        selectedMode = mode
        self.detailsExpanded = detailsExpanded
        if let noteText = noteText {
            applyNoteText(noteText)
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setupUI()
        updateOptionUI()
        updateDetailsUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func optionTapped(_ sender: UIButton) {
        guard sender.tag < DeviceBlinkMode.modes.count else { return }
        let mode = DeviceBlinkMode.modes[sender.tag]
//        guard selectedMode != mode else { return }
        selectedMode = mode
        delegate?.cell(self, didSelect: mode)
    }

    @objc private func detailsRowTapped() {
        detailsExpanded.toggle()
        delegate?.cell(self, detailsExpandedChanged: detailsExpanded)
    }

    private func updateOptionUI() {
        optionButtons.enumerated().forEach { index, button in
            let isSelected = DeviceBlinkMode.modes[index] == selectedMode
            button.backgroundColor = isSelected ? Bar_Color : Background_Color
            button.setTitleColor(isSelected ? .white : AssistText_Color, for: .normal)
        }
    }

    private func updateDetailsUI() {
        noteLabel.isHidden = !detailsExpanded
        detailsTitleLabel.text = detailsExpanded ? "hide_details".localizedString : "show_details".localizedString
        detailsArrowImageView.image = UIImage(named: detailsExpanded ? "arrow_up_black" : "arrow_down_black")

        if detailsExpanded {
            noteLabelTopConstraint?.update(offset: SCRYFrom(8))
            noteLabelHeightConstraint?.deactivate()
        } else {
            noteLabelTopConstraint?.update(offset: 0)
            noteLabelHeightConstraint?.activate()
        }
    }

    private func applyNoteText(_ noteText: String) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.lineBreakMode = .byWordWrapping
        noteLabel.attributedText = NSAttributedString(
            string: noteText,
            attributes: [.paragraphStyle: paragraphStyle]
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        applyNoteText("behavior_after_setup_success_note".localizedString)
        detailsExpanded = true
        selectedMode = .breathing
    }

    private func setupUI() {
        containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-16))
        }

        titleLabel = UILabel(
            text: "\("behavior_after_setup_success".localizedString):",
            textColor: TextBlack_Color,
            fontSize: 14,
            fontWeight: .light
        )
        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
            make.right.equalTo(SCRXFrom(-16))
        }

        var previousBtn: UIButton?
        for (index, mode) in DeviceBlinkMode.modes.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.layer.cornerRadius = SCRYFrom(10)
            button.clipsToBounds = true
            button.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(13))
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(7), bottom: 0, right: SCRXFrom(7))
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.75
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.lineBreakMode = .byClipping
            button.setTitle(mode.title, for: .normal)
            button.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
            containerView.addSubview(button)
            button.snp.makeConstraints { make in
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(12))
                make.height.equalTo(SCRYFrom(32))
                if let prev = previousBtn {
                    make.left.equalTo(prev.snp.right).offset(SCRXFrom(12))
                    make.width.equalTo(prev)
                } else {
                    make.left.equalTo(SCRXFrom(16))
                }
                if index == DeviceBlinkMode.modes.count - 1 {
                    make.right.equalTo(SCRXFrom(-16))
                }
            }
            optionButtons.append(button)
            previousBtn = button
        }

        detailsRow = UIControl()
        detailsRow.addTarget(self, action: #selector(detailsRowTapped), for: .touchUpInside)
        containerView.addSubview(detailsRow)
        detailsRow.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(56))
            make.height.equalTo(SCRYFrom(30))
        }

        detailsTitleLabel = UILabel(
            text: "hide_details".localizedString,
            textColor: Bar_Color,
            fontSize: 12,
            fontWeight: .regular
        )
        detailsRow.addSubview(detailsTitleLabel)

        detailsArrowImageView = UIImageView()
        detailsArrowImageView.contentMode = .scaleAspectFit
        detailsArrowImageView.tintColor = Bar_Color
        detailsRow.addSubview(detailsArrowImageView)
        detailsArrowImageView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        detailsTitleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualTo(detailsArrowImageView.snp.left).offset(SCRXFrom(-8))
        }

        noteLabel = UILabel(
            text: nil,
            textColor: AssistText_Color,
            fontSize: 12,
            fontWeight: .light,
            fit: false
        )
        noteLabel.numberOfLines = 0
        noteLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        noteLabel.setContentHuggingPriority(.required, for: .vertical)
        applyNoteText("behavior_after_setup_success_note".localizedString)
        containerView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            noteLabelTopConstraint = make.top.equalTo(detailsRow.snp.bottom).offset(SCRYFrom(8)).constraint
            make.bottom.equalTo(SCRYFrom(-16))
            noteLabelHeightConstraint = make.height.equalTo(0).constraint
        }

        noteLabelHeightConstraint?.deactivate()
    }
}
