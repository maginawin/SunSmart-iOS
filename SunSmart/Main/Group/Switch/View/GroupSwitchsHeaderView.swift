//
//  GroupSwitchsHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/12.
//

import UIKit

protocol GroupSwitchsHeaderViewDelegate: AnyObject {
    /// 点击view回调  isShow：是否展开
    func view(_ view: GroupSwitchsHeaderView, viewDidClick isShow: Bool)
    
    /// 长按view回调
    func headerViewDidLongPress(_ view: GroupSwitchsHeaderView)
    
    /// 开关点击回调  enabled：是否启用
    func view(_ view: GroupSwitchsHeaderView, switchDidClick enabled: Bool)
    
    /// 重新同步点击回调
    func headerViewDidResyncAction(_ view: GroupSwitchsHeaderView)
}

class GroupSwitchsHeaderView: UITableViewHeaderFooterView {

    private var titleLabel: UILabel!
    private var contentLabel: UILabel!
    private var arrowImageView: UIImageView!
    private var enabledSwitch: UISwitch!
    private var enabledBtn: UIButton!
    private var lineView: UIView!
    var failedImageView: UIImageView!
    
    weak var delegate: GroupSwitchsHeaderViewDelegate?
    
    var groupSwitch: DeviceSwitchData! {
        didSet {
            
            titleLabel.text = groupSwitch.name
            if let mac = groupSwitch.enOceanMacAddress {
                contentLabel.text = "ID:\(mac)"
            }else {
                contentLabel.text =  "switch_not_linked".localizedString
            }
            enabledSwitch.isOn = groupSwitch.enabled
            
            failedImageView.isHidden = !groupSwitch.needSyncData
        }
    }
    
    
    var isShow: Bool = false {
        didSet {
            arrowImageView.image = UIImage(named: isShow ? "arrow_up" : "arrow_down")
//            lineView.isHidden = isShow
        }
    }
    
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        contentView.backgroundColor = .white
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewClick)))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction))
        longPress.minimumPressDuration = 0.5
        addGestureRecognizer(longPress)
        
        setupUI()
    }
    
    @objc private func viewClick() {
        
        delegate?.view(self, viewDidClick: !isShow)
    }
    
    @objc private func longPressAction(sender: UIGestureRecognizer) {
        if sender.state == .began {
            delegate?.headerViewDidLongPress(self)
        }
    }
    
    @objc private func enabledBtnAction() {
        
        delegate?.view(self, switchDidClick: !enabledSwitch.isOn)
    }
    
    @objc private func resyncAction() {
        delegate?.headerViewDidResyncAction(self)
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(13))
        }
        
        contentLabel = UILabel(text: "switch_not_linked".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(5))
        }
        
        failedImageView = UIImageView(image: UIImage(named: "schedule_sync_failed"))
        failedImageView.isHidden = true
        failedImageView.isUserInteractionEnabled = true
        failedImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(resyncAction)))
        contentView.addSubview(failedImageView)
        failedImageView.snp.makeConstraints { make in
            make.left.equalTo(contentLabel.snp.right).offset(SCRXFrom(11))
            make.centerY.equalTo(contentLabel)
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_up"))
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(1)
        }
        
        enabledSwitch = UISwitch()
        enabledSwitch.onTintColor = Bar_Color
        enabledSwitch.tintColor = RGB(207, 207, 207)
        contentView.addSubview(enabledSwitch)
        enabledSwitch.snp.makeConstraints { make in
            make.right.equalTo(arrowImageView.snp.left).offset(SCRXFrom(-12))
            make.centerY.equalToSuperview()
        }
        
        enabledBtn = UIButton(target: self, action: #selector(enabledBtnAction))
        enabledSwitch.addSubview(enabledBtn)
        enabledBtn.snp.makeConstraints { make in
            make.edges.equalTo(enabledSwitch)
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
