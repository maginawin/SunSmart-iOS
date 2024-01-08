//
//  DeviceLightControlViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/10/17.
//

import UIKit

protocol DeviceLightControlViewCellDelegate: AnyObject {
    
    /// 设备属性修改回调（限流）
    /// - Parameters:
    ///   - cell: cell
    ///   - type: 控制类型
    ///   - value: 参数
    ///   - ended: 是否完成
    func cell(_ cell: DeviceLightControlViewCell, type: DeviceSliderFunctionView.FunctionType, throttleValueChanged value: Int, ended: Bool)
    
    /// 设备属性修改回调（滑动则回调）
    /// - Parameters:
    ///   - cell: cell
    ///   - type: 控制类型
    ///   - value: 参数
    ///   - ended: 是否完成
    func cell(_ cell: DeviceLightControlViewCell, type: DeviceSliderFunctionView.FunctionType, valueChanged value: Int)
}

class DeviceLightControlViewCell: UITableViewCell {

    var controlView: DeviceSliderFunctionView!
    var valueTagsContentView: UIView!
    var lineView: UIView!
    
    weak var delegate: DeviceLightControlViewCellDelegate?
    
    let defaultLevelValueTags = [("10%", 10), ("25%", 25), ("50%", 50), ("75%", 75), ("100%", 100)]
    let defaultCCTValueTags = [("3000K", 3000), ("4000K", 4000), ("4500K", 4500), ("5000K", 5000), ("6000K", 6000)]
    
    var type: DeviceSliderFunctionView.FunctionType = .level() {
        didSet {
            
            var title = "brightness".localizedString
            switch type {
            case .cct:
                title = "color_temperature".localizedString
            default:
                break
            }
            controlView.title = title
            controlView.type = type
            
            if valueTags.isEmpty {
                switch type {
                case .level:
                    valueTags = defaultLevelValueTags
                case .cct:
                    valueTags = defaultCCTValueTags
                }
            }
            setupValueTagsUI()
        }
    }
    
    var value: Int = 0 {
        didSet {
            controlView.value = value
        }
    }
    
    private var valueTagBtns: [UIButton] = []
    var valueTags: [(title: String, value: Int)] = []
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        valueTagBtns.forEach({ $0.removeFromSuperview() })
        valueTagBtns.removeAll()
    }
    
    // MARK: - Action
    @objc private func tagBtnClick(sender: UIButton) {
        let value = valueTags[sender.tag].value
        controlView.value = valueTags[sender.tag].value
        self.delegate?.cell(self, type: self.type, valueChanged: value)
        self.delegate?.cell(self, type: self.type, throttleValueChanged: value, ended: true)
    }
    
    // MARK: - UI
    
    private func setupUI() {
        
        var title = "brightness".localizedString
        switch type {
        case .cct:
            title = "color_temperature".localizedString
        default:
            break
        }
        
        controlView = DeviceSliderFunctionView(frame: .zero, title: title, value: 0, functionType: type)
        controlView.slider.throttle = true
        controlView.slider.interval = 0.3
        controlView.setValueAnimated = false
        controlView.lineView.isHidden = true
        controlView.throttleValueChangedCallback = {[weak self] (value, ended) in
            guard let self = self else { return }
            self.delegate?.cell(self, type: self.type, throttleValueChanged: value, ended: ended)
        }
        controlView.valueChangedCallback = {[weak self] value in
            guard let self = self else { return }
            self.delegate?.cell(self, type: self.type, valueChanged: value)
        }
        contentView.addSubview(controlView)
        controlView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
//            make.top.equalTo(SCRYFrom(18))
            make.height.equalTo(SCRYFrom(109))
        }
        controlView.slider.snp.updateConstraints { make in
            make.left.equalTo(SCRXFrom(45))
            make.right.equalTo(SCRXFrom(-70))
        }
        
        valueTagsContentView = UIView()
        contentView.addSubview(valueTagsContentView)
        valueTagsContentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.bottom.equalTo(SCRYFrom(-28))
            make.height.equalTo(SCRYFrom(32))
        }
    
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        
        setupValueTagsUI()
    }
    
    private func setupValueTagsUI() {
        
        valueTagBtns.forEach({ $0.removeFromSuperview() })
        valueTagBtns.removeAll()
        
        var lastAddTagBtn: UIButton?
        for index in 0..<valueTags.count {
            let tagBtn = UIButton(title: valueTags[index].title, titleSize: 14, titleColor: TextBlack_Color, target: self, action: #selector(tagBtnClick))
            tagBtn.layer.cornerRadius = SCRYFrom(5)
            tagBtn.layer.borderColor = RGB(216, 216, 216).cgColor
            tagBtn.layer.borderWidth = 1
            tagBtn.tag = index
            valueTagsContentView.addSubview(tagBtn)
            tagBtn.snp.makeConstraints { make in
                if let btn = lastAddTagBtn {
                    make.left.equalTo(btn.snp.right).offset(SCRXFrom(9))
                    make.width.equalTo(btn)
                }else {
                    make.left.equalToSuperview()
                }
                if index == valueTags.count - 1 {
                    make.right.equalToSuperview()
                }
                make.height.equalToSuperview()
            }
            lastAddTagBtn = tagBtn
            valueTagBtns.append(tagBtn)
        }
        
    }
    
    
    
}

extension DeviceLightControlViewCell {
    /// cell类型
    enum LightControlCellType {
        /// 亮度
        case brightness
        /// 色温
        case cct
    }
}
