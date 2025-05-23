//
//  GroupPathSequenceDeviceAddView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/19.
//

import UIKit
import NordicSigMeshSDK

/// 路径添加设备方式
enum PathSequenceDeviceAddMode {
    
    var title: String {
        switch self {
        case .quickAdd:
            return "quick_add".localizedString
        case .triggerAdd:
            return "trigger_add".localizedString
        case .manuallyAdd:
            return "manually_add".localizedString
        }
    }
    
    /// 快速添加 触发感应后自动添加
    case quickAdd
    /// 触发添加 触发后显示设备，点击识别后添加
    case triggerAdd
    /// 手动添加
    case manuallyAdd
}

protocol GroupPathSequenceDeviceAddViewDelegate: AnyObject {
    
    /// 设备添加模式切换
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, deviceAddModeChanged mode: PathSequenceDeviceAddMode)
    
    /// 已使用设备是否可重复使用选项更新 enabled true：可重复使用 false: 忽略
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, showAddedDevices enabled: Bool)
    
    /// 快速添加状态更新
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, quickAddStateChanged state: QuickAddState)
    
    /// 选择设备回调
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, selectDevice device: Node)
    
    /// 识别设备回调
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, identifyDevice device: Node)
    
    /// 触发添加设备刷新事件
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, triggerDevicesRefresh triggerView: GroupPathSequenceTriggerAddView)
    
}

class GroupPathSequenceDeviceAddView: UIView {

    private var addTypeBar: WMMenuView!
    private var barRightBtn: UIButton!
    
    var quickAddView: GroupPathSequenceQuickAddView!
    var triggerAddView: GroupPathSequenceTriggerAddView!
    var refreshBtn: UIButton!
//    private let titles: [String] = ["quick_add".localizedString, "trigger_add".localizedString]
    private let types: [PathSequenceDeviceAddMode] = [.quickAdd, .triggerAdd]
    
    weak var delegate: GroupPathSequenceDeviceAddViewDelegate?
    /// 是否可添加设备
    var canAddDevice: Bool = false {
        didSet {
            if canAddDevice {
                quickAddView.updateQuickAddState(.stop)
                triggerAddView.guideView.isHidden = true
            }else {
                quickAddView.showStepGuideUI()
                triggerAddView.guideView.isHidden = false
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func refreshBtnAction() {
        delegate?.deviceAddView(self, triggerDevicesRefresh: self.triggerAddView)
    }
    
    private func setupUI() {
        
        addTypeBar = WMMenuView(frame: CGRect(x: 0, y: 0, width: SCREEN_WIDTH - SCRXFrom(32), height: SCRYFrom(41)))
        addTypeBar.layoutMode = .left
        addTypeBar.style = .line
        addTypeBar.lineColor = Bar_Color
        addTypeBar.progressWidths = [SCRXFrom(92)]
        addTypeBar.fontWeight = .light
        addTypeBar.progressHeight = 2
        addTypeBar.progressViewBottomSpace = SCRYFrom(8)
        addTypeBar.dataSource = self
        addTypeBar.delegate = self
        addSubview(addTypeBar)
//        addTypeBar.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(9))
//            make.right.equalTo(SCRXFrom(-9))
//            make.top.equalTo(SCRYFrom(15))
//            make.height.equalTo(SCRYFrom(41))
//        }
        
        quickAddView = GroupPathSequenceQuickAddView()
        quickAddView.delegate = self
        addSubview(quickAddView)
        quickAddView.snp.makeConstraints { make in
            make.top.equalTo(addTypeBar.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }
        
        triggerAddView = GroupPathSequenceTriggerAddView()
        triggerAddView.isHidden = true
        triggerAddView.delegate = self
        addSubview(triggerAddView)
        triggerAddView.snp.makeConstraints { make in
            make.edges.equalTo(quickAddView)
        }
        
        refreshBtn = UIButton(normalImageName: "trigger_device_refresh", target: self, action: #selector(refreshBtnAction))
        refreshBtn.isHidden = true
        addSubview(refreshBtn)
        refreshBtn.snp.makeConstraints { make in
            make.centerY.equalTo(addTypeBar)
            make.right.equalTo(SCRXFrom(-8))
        }
    }
    
}

extension GroupPathSequenceDeviceAddView: WMMenuViewDataSource, WMMenuViewDelegate {
    
    func numbersOfTitles(in menu: WMMenuView!) -> Int {
        return types.count
    }
    
    func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return types[index].title
    }
    
    func menuView(_ menu: WMMenuView!, widthForItemAt index: Int) -> CGFloat {
        return SCRXFrom(93)
    }
    
    func menuView(_ menu: WMMenuView!, itemMarginAt index: Int) -> CGFloat {
        return index == 0 ? SCRXFrom(13) : SCRXFrom(20)
    }
    
    func menuView(_ menu: WMMenuView!, titleSizeFor state: WMMenuItemState, at index: Int) -> CGFloat {
        return state == .selected ? 15.5 : 15
    }
    
    func menuView(_ menu: WMMenuView!, titleColorFor state: WMMenuItemState, at index: Int) -> UIColor! {
        return state == .selected ? Bar_Color : Title_Color
    }
    
    func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
        quickAddView.isHidden = true
        triggerAddView.isHidden = true
        refreshBtn.isHidden = true
        switch index {
        case 0:
            quickAddView.isHidden = false
            delegate?.deviceAddView(self, showAddedDevices: quickAddView.showAdded)
        case 1:
            triggerAddView.isHidden = false
            refreshBtn.isHidden = triggerAddView.devices.isEmpty
            delegate?.deviceAddView(self, showAddedDevices: triggerAddView.showAdded)
        default:
            break
        }
        delegate?.deviceAddView(self, deviceAddModeChanged: types[index])
    }
    
}

extension GroupPathSequenceDeviceAddView: GroupPathSequenceQuickAddViewDelegate {
    
    /// 快速添加状态更新
    func quickAddView(_ view: GroupPathSequenceQuickAddView, addStateChanged addState: QuickAddState) {
        delegate?.deviceAddView(self, quickAddStateChanged: addState)
    }
    
    /// 快速添加是否显示已添加设备状态更新  showAdded：是否展示已添加设备
    func quickAddView(_ view: GroupPathSequenceQuickAddView, showAddedDevicesChanged showAdded: Bool) {
        delegate?.deviceAddView(self, showAddedDevices: showAdded)
    }
    
}

extension GroupPathSequenceDeviceAddView: GroupPathSequenceTriggerAddViewDelegate {
  
    /// 识别设备
    func triggerAddView(_ view: GroupPathSequenceTriggerAddView, identifyDevice device: Node) {
        delegate?.deviceAddView(self, identifyDevice: device)
    }
    
    /// 选择设备
    func triggerAddView(_ view: GroupPathSequenceTriggerAddView, selectDevice device: Node) {
        delegate?.deviceAddView(self, selectDevice: device)
    }
    
    /// 是否显示已添加设备状态更新  showAdded：是否展示已添加设备
    func triggerAddView(_ view: GroupPathSequenceTriggerAddView, showAddedDevicesChanged showAdded: Bool) {
        delegate?.deviceAddView(self, showAddedDevices: showAdded)
    }
}
