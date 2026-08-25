//
//  GroupDevicesFunctionView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/15.
//

import UIKit

protocol GroupDevicesFunctionViewDelegate: AnyObject {
    
    /// 点击同步数据回调
    func functionDidSyncDataAction(view: GroupDevicesFunctionView)
    
    /// 点击检查回调
    func functionDidCheckAction(view: GroupDevicesFunctionView)
    
    /// 点击排序回调
    func functionDidSortAction(view: GroupDevicesFunctionView)
    
    /// 全选点击回调  selectAll：是否全选
    func function(view: GroupDevicesFunctionView, selectAllStateChanged selectAll: Bool)

    /// 点击设备名称过滤
    func functionDidFilterDevicesAction(view: GroupDevicesFunctionView)

}

extension GroupDevicesFunctionViewDelegate {
    
    /// 点击同步数据回调
    func functionDidSyncDataAction(view: GroupDevicesFunctionView) {
        
    }
    
    /// 点击检查回调
    func functionDidCheckAction(view: GroupDevicesFunctionView) {
        
    }
    
    /// 点击排序回调
    func functionDidSortAction(view: GroupDevicesFunctionView) {
        
    }
    
    /// 全选点击回调  selectAll：是否全选
    func function(view: GroupDevicesFunctionView, selectAllStateChanged selectAll: Bool) {
        
    }

    /// 点击设备名称过滤
    func functionDidFilterDevicesAction(view: GroupDevicesFunctionView) {

    }

}

class GroupDevicesFunctionView: UIView {

    /// 同步数据按钮
    var syncBtn: UIButton!
    /// 检查按钮
//    var checkBtn: UIButton!
    /// 排序按钮
    var sortBtn: UIButton!
    /// 全选按钮
    var selectAllBtn: UIButton!
    /// 设备名称过滤按钮
    var deviceFilterBtn: UIButton!
    
    weak var delegate: GroupDevicesFunctionViewDelegate?
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func selectAllBtnClick(sender: UIButton) {
//        sender.isSelected = !sender.isSelected
        delegate?.function(view: self, selectAllStateChanged: !sender.isSelected)
    }
    
    @objc private func syncBtnClick() {
        
        delegate?.functionDidSyncDataAction(view: self)
    }
    
    
    @objc private func sortBtnClick() {
        
        delegate?.functionDidSortAction(view: self)
    }
    
    @objc private func checkBtnClick() {
        
        delegate?.functionDidCheckAction(view: self)
    }

    @objc private func deviceFilterBtnClick() {
        delegate?.functionDidFilterDevicesAction(view: self)
    }

    func setDeviceFilterEnabled(_ enabled: Bool) {
        deviceFilterBtn.isHidden = !enabled
        updateDeviceFilterButtonPosition()
    }

    func setSyncButtonHidden(_ hidden: Bool) {
        syncBtn.isHidden = hidden
        updateDeviceFilterButtonPosition()
    }

    private func updateDeviceFilterButtonPosition() {
        guard !deviceFilterBtn.isHidden else {
            return
        }
        deviceFilterBtn.snp.remakeConstraints { make in
            make.centerY.equalTo(syncBtn)
            make.width.height.equalTo(30)
            if syncBtn.isHidden {
                make.left.equalTo(SCRXFrom(20))
            } else {
                make.left.equalTo(syncBtn.snp.right).offset(SCRXFrom(16))
            }
        }
    }
    
    private func setupUI() {
        
        syncBtn = UIButton(title: "sync".localizedString, titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color1, normalImageName: "scene_sync", target: self, action: #selector(syncBtnClick))
        syncBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        addSubview(syncBtn)
        syncBtn.snp.makeConstraints { make in
            if isIPad {
                make.centerY.equalToSuperview()
            }else {
                make.top.equalTo(SCRYFrom(17))
            }
            make.left.equalTo(SCRXFrom(20))
        }

        deviceFilterBtn = UIButton(
            normalImageName: "device_filter",
            selectedImageName: "device_filter_selected",
            target: self,
            action: #selector(deviceFilterBtnClick)
        )
        deviceFilterBtn.isHidden = true
        deviceFilterBtn.accessibilityLabel = "device_filter_search_by_name".localizedString
        addSubview(deviceFilterBtn)
        deviceFilterBtn.snp.makeConstraints { make in
            make.centerY.equalTo(syncBtn)
            make.left.equalTo(syncBtn.snp.right).offset(SCRXFrom(16))
            make.width.height.equalTo(30)
        }
        
        selectAllBtn = UIButton(title: "select_all".localizedString, titleSize: 12, titleColor: TextBlack_Color, normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllBtnClick))
        selectAllBtn.setTitleColor(Message_Color, for: .disabled)
        addSubview(selectAllBtn)
        selectAllBtn.setImagePosition(position: .left, spacing: SCRXFrom(8))
        selectAllBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-26))
            make.centerY.equalTo(syncBtn)
        }
        
        sortBtn = UIButton(normalImageName: "space_sort", target: self, action: #selector(sortBtnClick))
        addSubview(sortBtn)
        sortBtn.snp.makeConstraints { make in
            make.right.equalTo(selectAllBtn.snp.left).offset(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
        }

//        checkBtn = UIButton(normalImageName: "check", target: self, action: #selector(checkBtnClick))
//        addSubview(checkBtn)
//        checkBtn.snp.makeConstraints { make in
//            make.right.equalTo(sortBtn.snp.left).offset(SCRXFrom(-24))
//            make.centerY.equalTo(selectAllBtn)
//        }
        
    }
}
