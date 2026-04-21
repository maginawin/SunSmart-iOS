//
//  DeviceAddMenuView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/3/20.
//

import UIKit

class DeviceAddMenuView: UIView {
    
    /// 菜单选项
    enum MenuOptions {
        /// 搜索设备
        case searchDevices
        /// 预配置动能开关
        case preCreatedSwitches
        /// 预配置传感器
        case preCreatedSensors
        /// 预配置dongle（能耗设备）
        case preCreatedDongles
        /// 恢复设备
        case restoreDevice
    }
    
    typealias MenuSelectCallback = ((MenuOptions)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var hideBtn: UIButton!
    private var searchDevicesBtn: UIButton!
    private var preCreatedDevicesLabel: UILabel!
    private var switchesBtn: UIButton!
    private var switchesLabel: UILabel!
    private var sensorsBtn: UIButton!
    private var sensorsLabel: UILabel!
    private var donglesBtn: UIButton!
    private var donglesLabel: UILabel!
    private var preCreatedMessageLabel: UILabel!
    private var restoreDeviceBtn: UIButton!
    
    private var lastScrollOffsetY: CGFloat = 0
    
    private var selectCallback: MenuSelectCallback?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init(selectCallback: MenuSelectCallback?) {
        self.init(frame: UIScreen.main.bounds)
        self.selectCallback = selectCallback
    }
    
    func show() {
        if self.superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
        }
        self.layoutIfNeeded()
        contentView.y = self.height
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.contentView.y = self.height - self.contentView.height
            self.shadeView.alpha = 1
        }
    }
    
    private func hide(animation: Bool = true) {
        if animation {
            UIView.animate(withDuration: 0.3) {
                self.contentView.y = self.height
                self.shadeView.alpha = 0
            } completion: { _ in
                self.removeFromSuperview()
            }
        }else {
            self.removeFromSuperview()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        contentView.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: 15, height: 15))
    }
    
    /// 搜索设备
    @objc private func searchDevicesAction() {
        selectCallback?(.searchDevices)
        hide(animation: false)
    }
    
    /// 动能开关
    @objc private func switchesAction() {
        selectCallback?(.preCreatedSwitches)
        hide(animation: false)
    }
    
    /// 传感器
    @objc private func sensorsAction() {
        selectCallback?(.preCreatedSensors)
        hide()
    }
    
    /// 其它设备
    @objc private func othersAction() {
        selectCallback?(.preCreatedDongles)
        hide()
    }
    
    /// 恢复设备数据
    @objc private func restoreDeviceAction() {
        selectCallback?(.restoreDevice)
        hide(animation: false)
    }
    
    /// 隐藏事件
    @objc private func hideAction() {
        hide()
    }
    
    /// 内容view拖拽手势
    @objc private func contentViewPanAction(sender: UIPanGestureRecognizer) {
        
        let offset = sender.translation(in: contentView)
        
        switch sender.state {
        case .began:
            self.shadeView.isUserInteractionEnabled = false
            lastScrollOffsetY = offset.y
        case .changed:
            let offsetY = offset.y - lastScrollOffsetY
            contentView.y = max(contentView.y + offsetY, self.height - self.contentView.height)
            lastScrollOffsetY = offset.y
        case .ended:
            // 判断滑动结束后距离起始点距离，>100则认为隐藏，否则还原；velocity滑动力度大的时候直接退出
            if offset.y > contentView.height * 0.3 || sender.velocity(in: contentView).y > 1000 {
                hide()
            }else {
                let showContentY = self.height - contentView.height
                UIView.animate(withDuration: 0.25) {
                    self.contentView.y = showContentY
                }
            }
            self.shadeView.isUserInteractionEnabled = true
        default:
            break
        }
        
    }
    
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.4)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        let pan = UIPanGestureRecognizer(target: self, action: #selector(contentViewPanAction))
        contentView.addGestureRecognizer(pan)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
//            make.height.equalTo(SCRYFrom(460))
        }
        
        hideBtn = UIButton(normalImageName: "arrow_down_black", target: self, action: #selector(hideAction))
        contentView.addSubview(hideBtn)
        hideBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(38))
        }
        
        searchDevicesBtn = UIButton(title: "device_add_search_mesh_device".localizedString, titleSize: 15, titleWeight: .light, titleColor: .white, normalImageName: "search_icon", target: self, action: #selector(searchDevicesAction))
        searchDevicesBtn.setImage(UIImage(named: "search_icon")?.withTintColor(.white), for: .normal)
        searchDevicesBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        searchDevicesBtn.layer.cornerRadius = SCRYFrom(15)
//        searchDevicesBtn.layer.borderColor = Border_Color.cgColor
//        searchDevicesBtn.layer.borderWidth = 1
        searchDevicesBtn.backgroundColor = Bar_Color
        contentView.addSubview(searchDevicesBtn)
        searchDevicesBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(38))
            make.right.equalTo(SCRXFrom(-37))
            make.top.equalTo(hideBtn.snp.bottom).offset(SCRYFrom(30))
            make.height.equalTo(SCRYFrom(44))
        }
        
        preCreatedDevicesLabel = UILabel(text: "pre-created_devices".localizedString, textColor: TextBlack_Color, fontSize: 15)
        preCreatedDevicesLabel.textAlignment = .center
        contentView.addSubview(preCreatedDevicesLabel)
        preCreatedDevicesLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(searchDevicesBtn.snp.bottom).offset(SCRYFrom(48))
        }
        
        sensorsBtn = UIButton(normalImageName: "device_sensor", target: self, action: #selector(sensorsAction))
        sensorsBtn.layer.cornerRadius = SCRXFrom(34)
        sensorsBtn.backgroundColor = Bar_Color
        contentView.addSubview(sensorsBtn)
        sensorsBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(preCreatedDevicesLabel.snp.bottom).offset(SCRYFrom(30))
            make.width.height.equalTo(SCRXFrom(68))
        }
        
        sensorsLabel = UILabel(text: "sensors".localizedString, textColor: Title_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(sensorsLabel)
        sensorsLabel.snp.makeConstraints { make in
            make.centerX.equalTo(sensorsBtn)
            make.top.equalTo(sensorsBtn.snp.bottom).offset(SCRYFrom(12))
        }
        
        switchesBtn = UIButton(normalImageName: "device_switches", target: self, action: #selector(switchesAction))
        switchesBtn.layer.cornerRadius = sensorsBtn.layer.cornerRadius
//        switchesBtn.layer.borderWidth = 1
//        switchesBtn.layer.borderColor = Border_Color.cgColor
        switchesBtn.backgroundColor = Bar_Color
        contentView.addSubview(switchesBtn)
        switchesBtn.snp.makeConstraints { make in
//            make.right.equalTo(sensorsBtn.snp.left).offset(SCRXFrom(-20))
            make.left.equalTo(searchDevicesBtn)
            make.centerY.width.height.equalTo(sensorsBtn)
        }
        
        switchesLabel = UILabel(text: "switches".localizedString, textColor: Title_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(switchesLabel)
        switchesLabel.snp.makeConstraints { make in
            make.centerX.equalTo(switchesBtn)
            make.top.equalTo(sensorsLabel)
        }
        
        donglesBtn = UIButton(normalImageName: "Frame 249", target: self, action: #selector(othersAction))
        donglesBtn.layer.cornerRadius = switchesBtn.layer.cornerRadius
        donglesBtn.backgroundColor = Bar_Color
        contentView.addSubview(donglesBtn)
        donglesBtn.snp.makeConstraints { make in
//            make.left.equalTo(sensorsBtn.snp.right).offset(SCRXFrom(20))
            make.right.equalTo(searchDevicesBtn)
            make.centerY.width.height.equalTo(switchesBtn)
        }
        
        donglesLabel = UILabel(text: "others".localizedString, textColor: Title_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(donglesLabel)
        donglesLabel.snp.makeConstraints { make in
            make.centerX.equalTo(donglesBtn)
            make.top.equalTo(sensorsLabel)
        }
        
        preCreatedMessageLabel = UILabel(text: "pre-created_devices_message".localizedString, textColor: Message_Color, fontSize: 13)
        preCreatedMessageLabel.textAlignment = .center
        preCreatedMessageLabel.numberOfLines = 0
        contentView.addSubview(preCreatedMessageLabel)
        preCreatedMessageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-22))
            make.top.equalTo(sensorsLabel.snp.bottom).offset(SCRYFrom(24))
        }
        
        restoreDeviceBtn = UIButton(titleSize: 15, titleColor: Bar_Color, target: self, action: #selector(restoreDeviceAction))
        let attStr = NSMutableAttributedString(string: "Restore_device_data".localizedString, attributes: [.underlineStyle: 1, .underlineColor: Bar_Color])
        restoreDeviceBtn.setAttributedTitle(attStr, for: .normal)
        contentView.addSubview(restoreDeviceBtn)
        restoreDeviceBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(preCreatedMessageLabel.snp.bottom).offset(SCRYFrom(20))
            make.bottom.equalTo(kSafeAreaBottomHeight > 0 ? -(SCRYFrom(8) + kSafeAreaBottomHeight) : SCRYFrom(-20))
        }
        
    }
    
}
