//
//  DeviceParameterDeviceCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/11.
//

import UIKit
import NordicSigMeshSDK

private final class DeviceParameterStatusRowView: UIView {
    let textLabel: UILabel
    let failedImageView: UIImageView
    
    private let stackView: UIStackView
    
    init(numberOfLines: Int = 1) {
        textLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        textLabel.numberOfLines = numberOfLines
        failedImageView = UIImageView(image: UIImage(named: "setting_failed"))
        failedImageView.isHidden = true
        
        stackView = UIStackView()
        super.init(frame: .zero)
        
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = SCRXFrom(4)
        stackView.addArrangedSubview(textLabel)
        stackView.addArrangedSubview(failedImageView)
        
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

protocol DeviceParameterDeviceCellDelegate: AnyObject {
    
    /// 设备identity事件
    func cell(_ cell: DeviceParameterDeviceCell, deviceIdentifyAction device: Node)
    
    /// 设备onoff事件
    func cell(_ cell: DeviceParameterDeviceCell, deviceOnOffAction device: Node, isOn: Bool)
}

class DeviceParameterDeviceCell: UITableViewCell {
    /// 选择状态
    enum SelectState {
        /// 未选中
        case none
        /// 选中
        case selected
        /// 不可选
        case disable
    }

    var selectImageView: UIImageView!
    var deviceImageView: UIImageView!
    var nameLabel: UILabel!
//    private var contentLabel: UILabel!
    var pwmLabel: UILabel!
    var pwmFailedImageView: UIImageView!
    var ratedPowerLabel: UILabel!
    var ratedPowerFailedImageView: UIImageView!
    var sensitivityLabel: UILabel!
    var sensitivityImageView: UIImageView!
    
    var transitionTimeLabel: UILabel!
    var transitionTimeImageView: UIImageView!
    
    var identifyBtn: UIButton!
//    private var onoffBtn: UIButton!
    var onBtn: UIButton!
    var offBtn: UIButton!
    var groupNameLabel: UILabel!
    private var lineView: UIView!
    private var parameterStackView: UIStackView!
    private var pwmRowView: DeviceParameterStatusRowView!
    private var ratedPowerRowView: DeviceParameterStatusRowView!
    private var sensitivityRowView: DeviceParameterStatusRowView!
    private var transitionTimeRowView: DeviceParameterStatusRowView!
    private var changeControlPageRowView: DeviceParameterStatusRowView!
    private var absoluteCctRangeRowView: DeviceParameterStatusRowView!
    
    weak var delegate: DeviceParameterDeviceCellDelegate?
    
    var device: Node! {
        didSet {
            
            nameLabel.text = device.name
            onBtn.isSelected = device.selectOn
            offBtn.isSelected = device.selectOff
            
//            onBtn.backgroundColor = onBtn.isSelected ? Bar_Color : Background_Color
            
            if let group = device.group {
                groupNameLabel.text = group.name
            }else {
                groupNameLabel.text = "not_in_group".localizedString
            }
        }
    }

    var selectState: SelectState = .none {
        didSet {
            if selectState == .disable {
                deviceImageView.image = UIImage(named: "device_light_gray")
                nameLabel.textColor = SubText_Color
                selectImageView.isHidden = true
            }else {
                deviceImageView.image = UIImage(named: device.iconName)
                nameLabel.textColor = TextBlack_Color
                selectImageView.isHidden = false
                selectImageView.image = UIImage(named: selectState == .selected ? "device_select" : "device_select_un")
            }
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func offBtnAction(sender: UIButton) {
        sender.isSelected = true
//        sender.backgroundColor = sender.isSelected ? Bar_Color : Background_Color
        delegate?.cell(self, deviceOnOffAction: device, isOn: false)
    }
    
    @objc private func onBtnAction(sender: UIButton) {
        sender.isSelected = true
//        sender.backgroundColor = sender.isSelected ? Bar_Color : Background_Color
        delegate?.cell(self, deviceOnOffAction: device, isOn: true)
    }
    
    @objc private func identifyBtnAction() {
        
        delegate?.cell(self, deviceIdentifyAction: device)
    }
    
    private struct ParameterDisplayItem {
        let type: DeviceParameterData.ParameterType
        let isSupported: Bool
        let rowView: DeviceParameterStatusRowView
        let normalText: String
    }
    
    func configureParameterViews(
        visibleTypes: Set<DeviceParameterData.ParameterType>? = nil,
        failedParameters: [DeviceParameterType]?,
        ratedPowerFormatter: ([NodePhaseEnergyConsumption]) -> String
    ) {
        let failedParameterMap = (failedParameters ?? []).reduce(into: [Int: DeviceParameterType]()) { result, item in
            result[item.rawValue] = item
        }
        
        let normalPwmText = device.tempPwm.map({ "PWM: \($0) Hz" }) ?? "PWM: --"
        
        let normalRatedPowerText = "\("rated_power".localizedString): \(ratedPowerFormatter(device.tempRatedPowerPhases))"
        
        let normalSensitivityText: String
        if let range = device.tempSensitivityRange {
            normalSensitivityText = "\("absolute_sensitivity".localizedString): \(range.lowerBound.percentageFloat.toSimplifyStr(maxDigits: 1))%~\(range.upperBound.percentageFloat.toSimplifyStr(maxDigits: 1))%"
        } else {
            normalSensitivityText = "\("absolute_sensitivity".localizedString) : --"
        }
        
        let normalTransitionTimeText: String
        if let transitionTime = device.tempTransitionTime {
            let timeStr = DeviceParameterData.transitionTimeDatas.first(where: { $0.timeInterval == transitionTime.interval })?.timeStr ?? "\(transitionTime.interval ?? 0)s"
            normalTransitionTimeText = "\("transition_time".localizedString): \(timeStr)"
        } else {
            normalTransitionTimeText = "\("transition_time".localizedString): --"
        }

        let changeControlPageText = "\("change_control_page".localizedString): \(device.tempChangeControlPage == .singleWhite ? "single_white".localizedString : "tunable_white".localizedString)"
        let absoluteCctRangeText = "\("absolute_cct_range".localizedString): \(device.tempAbsoluteCctRange.lowerBound)K~\(device.tempAbsoluteCctRange.upperBound)K"
        
        let items: [ParameterDisplayItem] = [
            ParameterDisplayItem(
                type: .pwmFrequency,
                isSupported: device.supportPwmFrequency,
                rowView: pwmRowView,
                normalText: normalPwmText
            ),
            ParameterDisplayItem(
                type: .ratedPower,
                isSupported: true,
                rowView: ratedPowerRowView,
                normalText: normalRatedPowerText
            ),
            ParameterDisplayItem(
                type: .motionSensitivityRange,
                isSupported: device.supportMotionSensitivity,
                rowView: sensitivityRowView,
                normalText: normalSensitivityText
            ),
            ParameterDisplayItem(
                type: .defalutTransitionTime,
                isSupported: device.supportDefaultTransitionTime,
                rowView: transitionTimeRowView,
                normalText: normalTransitionTimeText
            ),
            ParameterDisplayItem(
                type: .changeControlPage,
                isSupported: device.rawSupportCct,
                rowView: changeControlPageRowView,
                normalText: changeControlPageText
            ),
            ParameterDisplayItem(
                type: .absoluteCctRange,
                isSupported: device.rawSupportCct,
                rowView: absoluteCctRangeRowView,
                normalText: absoluteCctRangeText
            )
        ]
        
        items.forEach { item in
            render(item: item, failedParameterMap: failedParameterMap, visibleTypes: visibleTypes)
        }
    }
    
    private func render(
        item: ParameterDisplayItem,
        failedParameterMap: [Int: DeviceParameterType],
        visibleTypes: Set<DeviceParameterData.ParameterType>?
    ) {
        let isVisibleByBusiness = item.isSupported && (visibleTypes?.contains(item.type) ?? true)
        guard isVisibleByBusiness else {
            item.rowView.isHidden = true
            return
        }
        
        if failedParameterMap[item.type.rawValue] != nil {
            item.rowView.failedImageView.isHidden = false
        } else {
            item.rowView.failedImageView.isHidden = true
        }
        item.rowView.textLabel.text = item.normalText
        item.rowView.isHidden = false
    }
    
    
    
    private func setupUI() {
        
        selectImageView = UIImageView(image: UIImage(named: "device_select_un"))
        selectImageView.sizeToFit()
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
            make.width.equalTo(selectImageView.width)
        }
        
        deviceImageView = UIImageView()
        contentView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(selectImageView.snp.right).offset(SCRXFrom(2))
            make.centerY.equalTo(selectImageView)
            make.width.height.equalTo(30)
        }
        
        let height = Int(SCRYFrom(30))
        let onoffSize = CGSize(width: height, height: height)
        
        offBtn = UIButton(title: "Off".localizedString, titleSize: 13, titleWeight: .light, titleColor: RGB(20, 46, 79), target: self, action: #selector(offBtnAction))
        offBtn.setTitleColor(.white, for: .selected)
        offBtn.setBackgroundImage(UIImage.image(size: onoffSize, color: Background_Color), for: .normal)
        offBtn.setBackgroundImage(UIImage.image(size: onoffSize, color: Bar_Color), for: .selected)
        offBtn.backgroundColor = Background_Color
        offBtn.layer.cornerRadius = CGFloat(height) * 0.5
        offBtn.layer.masksToBounds = true
        contentView.addSubview(offBtn)
        offBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(deviceImageView)
            make.size.equalTo(onoffSize)
        }
        
        onBtn = UIButton(title: "On".localizedString, titleSize: 13, titleWeight: .light, titleColor: RGB(20, 46, 79), target: self, action: #selector(onBtnAction))
        onBtn.setTitleColor(.white, for: .selected)
        onBtn.backgroundColor = Background_Color
        onBtn.setBackgroundImage(UIImage.image(size: onoffSize, color: Background_Color), for: .normal)
        onBtn.setBackgroundImage(UIImage.image(size: onoffSize, color: Bar_Color), for: .selected)
        onBtn.layer.cornerRadius = CGFloat(height) * 0.5
        onBtn.layer.masksToBounds = true
        contentView.addSubview(onBtn)
        onBtn.snp.makeConstraints { make in
            make.right.equalTo(offBtn.snp.left).offset(SCRXFrom(-10))
            make.centerY.size.equalTo(offBtn)
        }
        
        identifyBtn = UIButton(target: self, action: #selector(identifyBtnAction))
        identifyBtn.setBackgroundImage(UIImage(named: "device_identify"), for: .normal)
        contentView.addSubview(identifyBtn)
        identifyBtn.snp.makeConstraints { make in
            make.right.equalTo(onBtn.snp.left).offset(SCRXFrom(-10))
            make.centerY.size.equalTo(onBtn)
        }
        
        nameLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        nameLabel.lineBreakMode = .byTruncatingHead
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
//            make.top.equalTo(deviceImageView).offset(SCRYFrom(-3))
            make.centerY.equalTo(deviceImageView)
            make.width.lessThanOrEqualTo(SCRXFrom(170))
//            make.right.equalTo(identifyBtn.snp.left).offset(SCRXFrom(-30)).priority(.medium)
        }
        
        parameterStackView = UIStackView()
        parameterStackView.axis = .vertical
        parameterStackView.alignment = .leading
        parameterStackView.spacing = SCRYFrom(2)
        contentView.addSubview(parameterStackView)
        parameterStackView.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(2))
            make.width.lessThanOrEqualTo(SCRXFrom(220))
        }

        pwmRowView = DeviceParameterStatusRowView()
        ratedPowerRowView = DeviceParameterStatusRowView(numberOfLines: 2)
        sensitivityRowView = DeviceParameterStatusRowView()
        transitionTimeRowView = DeviceParameterStatusRowView()
        changeControlPageRowView = DeviceParameterStatusRowView()
        absoluteCctRangeRowView = DeviceParameterStatusRowView()
        parameterStackView.addArrangedSubview(pwmRowView)
        parameterStackView.addArrangedSubview(ratedPowerRowView)
        parameterStackView.addArrangedSubview(sensitivityRowView)
        parameterStackView.addArrangedSubview(transitionTimeRowView)
        parameterStackView.addArrangedSubview(changeControlPageRowView)
        parameterStackView.addArrangedSubview(absoluteCctRangeRowView)
        
        pwmLabel = pwmRowView.textLabel
        pwmFailedImageView = pwmRowView.failedImageView
        ratedPowerLabel = ratedPowerRowView.textLabel
        ratedPowerFailedImageView = ratedPowerRowView.failedImageView
        sensitivityLabel = sensitivityRowView.textLabel
        sensitivityImageView = sensitivityRowView.failedImageView
        transitionTimeLabel = transitionTimeRowView.textLabel
        transitionTimeImageView = transitionTimeRowView.failedImageView
        
        groupNameLabel = UILabel(text: "not_in_group".localizedString, textColor: Message_Color, fontSize: 12, fontWeight: .light)
        groupNameLabel.lineBreakMode = .byTruncatingHead
        contentView.addSubview(groupNameLabel)
        groupNameLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(onBtn.snp.bottom).offset(SCRYFrom(4))
            make.width.lessThanOrEqualTo(SCRXFrom(100))
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(selectImageView)
            make.top.greaterThanOrEqualTo(groupNameLabel.snp.bottom).offset(SCRYFrom(8))
            make.top.greaterThanOrEqualTo(parameterStackView.snp.bottom).offset(SCRYFrom(8))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
    }
    
}
