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
    private let containerTopInset = SCRYFrom(6)
    private let containerBottomInset = SCRYFrom(14)
    private let headerHeight = SCRYFrom(40)
    private let headerBodySpacing = SCRYFrom(4)
    private let addTypeBarHeight = SCRYFrom(41)
    private let contentCardTopSpacing = SCRYFrom(8)

    private var containerStackView: UIStackView!
    private var headerView: UIView!
    private var headerTitleLabel: UILabel!
    private var collapseBtn: UIButton!
    private var bodyContainerView: UIView!
    private var addTypeBar: WMMenuView!
    private var contentCardView: UIView!
    private var contentCardMinHeightConstraint: NSLayoutConstraint?

    var quickAddView: GroupPathSequenceQuickAddView!
    var triggerAddView: GroupPathSequenceTriggerAddView!
    var manuallyAddView: GroupPathSequenceManuallyAddView!
    var refreshBtn: UIButton!
    var unfoldBtn: UIButton!
    private let types: [PathSequenceDeviceAddMode] = [.quickAdd, .triggerAdd, .manuallyAdd]

    weak var delegate: GroupPathSequenceDeviceAddViewDelegate?
    var heightChanged: ((CGFloat) -> Void)?

    private var currentMode: PathSequenceDeviceAddMode = .quickAdd
    private var collapsed: Bool = false
    private var headerIndex: Int?
    private var lastPreferredHeight: CGFloat = 0
    private var lastMenuWidth: CGFloat = 0

    /// 是否可添加设备
    var canAddDevice: Bool = false {
        didSet {
            if canAddDevice {
                quickAddView.updateQuickAddState(.stop)
                triggerAddView.setGuideVisible(false)
                manuallyAddView.setGuideVisible(false)
            }else {
                quickAddView.updateQuickAddState(.stop)
                quickAddView.showStepGuideUI()
                triggerAddView.setGuideVisible(true)
                manuallyAddView.setGuideVisible(true)
            }
            updateUnfoldState()
            updateAccessoryButtons()
            refreshPreferredHeight()
        }
    }
    
    var isSequence: Bool = true {
        didSet {
            quickAddView.isSequence = isSequence
            triggerAddView.isSequence = isSequence
            manuallyAddView.isSequence = isSequence
            updateHeaderTitle()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = Background_Color
        layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        layer.shadowOffset = CGSize(width: 0, height: -4)
        layer.shadowRadius = 4
        layer.shadowOpacity = 1
        layer.cornerRadius = SCRYFrom(15)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if addTypeBar.bounds.width > 0, abs(addTypeBar.bounds.width - lastMenuWidth) > 0.5 {
            lastMenuWidth = addTypeBar.bounds.width
            addTypeBar.reload()
            if let index = types.firstIndex(of: currentMode) {
                addTypeBar.selectItem(at: index)
            }
        }
        emitPreferredHeightIfNeeded()
    }
    
    @objc private func refreshBtnAction() {
        refreshBtn.isHidden = true
        delegate?.deviceAddView(self, triggerDevicesRefresh: self.triggerAddView)
    }
    
    @objc private func unfoldBtnAction(sender: UIButton) {
        let rowNum = max(1, min(Int(ceilf(Float(manuallyAddView.devices.count) / Float(manuallyAddView.colNum))), 3))
        if !sender.isSelected, rowNum == 1 {
            return
        }
        sender.isSelected = !sender.isSelected
        
        manuallyAddView.rowNum = sender.isSelected ? rowNum : 1
        updateAccessoryButtons()
        refreshPreferredHeight()
    }

    @objc private func collapseBtnAction() {
        collapsed.toggle()
        updateCollapseUI(animated: true)
    }
    
    private func setupUI() {
        containerStackView = UIStackView()
        containerStackView.axis = .vertical
        containerStackView.spacing = headerBodySpacing
        addSubview(containerStackView)
        containerStackView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(containerTopInset)
            make.bottom.equalTo(-containerBottomInset)
        }

        headerView = UIView()
        containerStackView.addArrangedSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.height.equalTo(headerHeight)
        }
        headerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(collapseBtnAction)))

        collapseBtn = UIButton(type: .custom)
        collapseBtn.isUserInteractionEnabled = false
        collapseBtn.setImage(UIImage(named: "arrow_down_black"), for: .normal)
        headerView.addSubview(collapseBtn)
        collapseBtn.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-16))
            make.width.height.equalTo(30)
        }

        headerTitleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14, fit: false)
        headerTitleLabel.numberOfLines = 1
        headerTitleLabel.lineBreakMode = .byTruncatingTail
        headerTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerView.addSubview(headerTitleLabel)
        headerTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.lessThanOrEqualTo(collapseBtn.snp.left).offset(SCRXFrom(-8))
            make.top.greaterThanOrEqualTo(SCRYFrom(6))
            make.bottom.lessThanOrEqualTo(SCRYFrom(-6))
            make.centerY.equalToSuperview()
        }

        bodyContainerView = UIView()
        containerStackView.addArrangedSubview(bodyContainerView)

        addTypeBar = WMMenuView(frame: CGRect(x: 0, y: 0, width: SCREEN_WIDTH, height: SCRYFrom(41)))
        addTypeBar.layoutMode = .left
        addTypeBar.style = .line
        addTypeBar.lineColor = Bar_Color
        addTypeBar.progressWidths = [SCRXFrom(92), SCRXFrom(92), SCRXFrom(92)]
        addTypeBar.fontWeight = .light
        addTypeBar.progressHeight = 2
        addTypeBar.itemRateAnimation = false
        addTypeBar.progressViewBottomSpace = SCRYFrom(6)
        addTypeBar.dataSource = self
        addTypeBar.delegate = self
        bodyContainerView.addSubview(addTypeBar)
        addTypeBar.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalToSuperview()
            make.height.equalTo(addTypeBarHeight)
        }

        contentCardView = UIView()
        contentCardView.backgroundColor = .white
        contentCardView.layer.cornerRadius = SCRYFrom(10)
        bodyContainerView.addSubview(contentCardView)
        contentCardView.snp.makeConstraints { make in
            make.top.equalTo(addTypeBar.snp.bottom).offset(contentCardTopSpacing)
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalToSuperview()
        }
        
        quickAddView = GroupPathSequenceQuickAddView()
        quickAddView.delegate = self
        quickAddView.backgroundColor = .clear
        quickAddView.layer.cornerRadius = 0
        contentCardView.addSubview(quickAddView)
        quickAddView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        triggerAddView = GroupPathSequenceTriggerAddView()
        triggerAddView.isHidden = true
        triggerAddView.delegate = self
        triggerAddView.backgroundColor = .clear
        triggerAddView.layer.cornerRadius = 0
        contentCardView.addSubview(triggerAddView)
        triggerAddView.snp.makeConstraints { make in
            make.edges.equalTo(quickAddView)
        }
        
        manuallyAddView = GroupPathSequenceManuallyAddView()
        manuallyAddView.isHidden = true
        manuallyAddView.delegate = self
        manuallyAddView.backgroundColor = .clear
        manuallyAddView.layer.cornerRadius = 0
        contentCardView.addSubview(manuallyAddView)
        manuallyAddView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        refreshBtn = UIButton(normalImageName: "trigger_device_refresh", target: self, action: #selector(refreshBtnAction))
        refreshBtn.isHidden = true
        bodyContainerView.addSubview(refreshBtn)
        refreshBtn.snp.makeConstraints { make in
            make.centerY.equalTo(addTypeBar)
            make.right.equalTo(SCRXFrom(-24))
        }
        
        unfoldBtn = UIButton(normalImageName: "devices_unfold", selectedImageName: "devices_fold", target: self, action: #selector(unfoldBtnAction))
        unfoldBtn.isHidden = true
        bodyContainerView.addSubview(unfoldBtn)
        unfoldBtn.snp.makeConstraints { make in
            make.center.equalTo(refreshBtn)
        }
        
        contentCardMinHeightConstraint = contentCardView.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumContentHeight)
        contentCardMinHeightConstraint?.isActive = true

        updateHeaderTitle()
        updateCollapseUI(animated: false)
    }
    
    func updateUnfoldState() {
        updateAccessoryButtons()
        refreshPreferredHeight()
    }

    func updateHeaderIndex(_ index: Int?) {
        headerIndex = index
        updateHeaderTitle()
    }

    func setCollapsed(_ collapsed: Bool, animated: Bool = false) {
        guard self.collapsed != collapsed else {
            return
        }
        self.collapsed = collapsed
        updateCollapseUI(animated: animated)
    }

    func refreshPreferredHeight() {
        setNeedsLayout()
        layoutIfNeeded()
        emitPreferredHeightIfNeeded()
    }

    private func updateHeaderTitle() {
        if let index = headerIndex {
            let key = isSequence ? "device_add_title_path_index" : "device_add_title_zone_index"
            headerTitleLabel.text = String(format: key.localizedString, index)
        } else {
            headerTitleLabel.text = (isSequence ? "device_add_title_path" : "device_add_title_zone").localizedString
        }
    }

    private func updateCollapseUI(animated: Bool) {
        let applyState = {
            let imageName = self.collapsed ? "arrow_down_black" : "arrow_up_black"
            self.collapseBtn.setImage(UIImage(named: imageName), for: .normal)
            self.bodyContainerView.isHidden = self.collapsed
        }
        if animated {
            if collapsed {
                applyState()
            } else {
                bodyContainerView.isHidden = false
                applyState()
            }
        } else {
            applyState()
        }
        updateAccessoryButtons()
        refreshPreferredHeight()
    }

    private func updateAccessoryButtons() {
        guard !collapsed else {
            refreshBtn.isHidden = true
            unfoldBtn.isHidden = true
            return
        }

        let maxManualRows = max(1, min(Int(ceilf(Float(manuallyAddView.devices.count) / Float(manuallyAddView.colNum))), 3))
        refreshBtn.isHidden = currentMode != .triggerAdd || triggerAddView.devices.isEmpty
        unfoldBtn.isHidden = currentMode != .manuallyAdd || maxManualRows <= 1 || !manuallyAddView.guideContentView.isHidden
    }

    private func emitPreferredHeightIfNeeded() {
        updateContentMinimumHeight()
        let height: CGFloat
        if isHidden {
            height = 0
        } else if collapsed {
            height = containerTopInset + headerHeight + containerBottomInset
        } else {
            height = preferredExpandedHeight()
        }
        guard let heightChanged else {
            return
        }
        guard abs(height - lastPreferredHeight) > 0.5 else {
            return
        }
        lastPreferredHeight = height
        heightChanged(height)
    }

    private var minimumContentHeight: CGFloat {
        max(SCRYFrom(136), manuallyAddView.preferredMinimumContentHeight)
    }

    private func updateContentMinimumHeight() {
        contentCardMinHeightConstraint?.constant = minimumContentHeight
    }

    private func visibleContentHeight() -> CGFloat {
        switch currentMode {
        case .quickAdd:
            return quickAddView.preferredContentHeight
        case .triggerAdd:
            return triggerAddView.preferredContentHeight
        case .manuallyAdd:
            return manuallyAddView.preferredContentHeight
        }
    }

    private func preferredExpandedHeight() -> CGFloat {
        let contentHeight = max(minimumContentHeight, visibleContentHeight())
        return containerTopInset + headerHeight + headerBodySpacing + addTypeBarHeight + contentCardTopSpacing + contentHeight + containerBottomInset
    }

    private func switchMode(to type: PathSequenceDeviceAddMode) {
        currentMode = type

        quickAddView.isHidden = true
        triggerAddView.isHidden = true
        manuallyAddView.isHidden = true

        if type != .manuallyAdd, manuallyAddView.rowNum != 1 {
            manuallyAddView.rowNum = 1
            unfoldBtn.isSelected = false
        }

        switch type {
        case .quickAdd:
            quickAddView.isHidden = false
            delegate?.deviceAddView(self, showAddedDevices: quickAddView.showAdded)
        case .triggerAdd:
            triggerAddView.isHidden = false
            delegate?.deviceAddView(self, showAddedDevices: triggerAddView.showAdded)
        case .manuallyAdd:
            manuallyAddView.isHidden = false
            delegate?.deviceAddView(self, showAddedDevices: manuallyAddView.showAdded)
        }

        updateAccessoryButtons()
        refreshPreferredHeight()
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
        return isIPad ? SCRXFrom(150) : SCRXFrom(92)
    }
    
    func menuView(_ menu: WMMenuView!, itemMarginAt index: Int) -> CGFloat {
        return index == 0 ? SCRXFrom(16) : SCRXFrom(4)
    }
    
    func menuView(_ menu: WMMenuView!, titleSizeFor state: WMMenuItemState, at index: Int) -> CGFloat {
        // state == .selected ? 15.5 : 15
        return 15
    }
    
    func menuView(_ menu: WMMenuView!, titleColorFor state: WMMenuItemState, at index: Int) -> UIColor! {
        return state == .selected ? Bar_Color : Title_Color
    }
    
    func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
        guard index != currentIndex else {
            return
        }
        
        let type = types[index]
        switchMode(to: type)
        delegate?.deviceAddView(self, deviceAddModeChanged: type)
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

extension GroupPathSequenceDeviceAddView: GroupPathSequenceManuallyAddViewDelegate {
    
    /// 识别设备
    func manuallyAddView(_ view: GroupPathSequenceManuallyAddView, identifyDevice device: Node) {
        delegate?.deviceAddView(self, identifyDevice: device)
    }
    
    /// 选择设备
    func manuallyAddView(_ view: GroupPathSequenceManuallyAddView, selectDevice device: Node) {
        delegate?.deviceAddView(self, selectDevice: device)
    }
 
    /// 是否显示已添加设备状态更新  showAdded：是否展示已添加设备
    func manuallyAddView(_ view: GroupPathSequenceManuallyAddView, showAddedDevicesChanged showAdded: Bool) {
        delegate?.deviceAddView(self, showAddedDevices: showAdded)
    }
    
}
