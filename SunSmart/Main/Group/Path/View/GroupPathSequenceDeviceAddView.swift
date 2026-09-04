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
    enum ContentHeightPolicy {
        case fixedBase
        case dynamicSelected
    }

    private enum LayoutMetrics {
        static let headerHeight: CGFloat = 44
        static let addTypeBarHeight: CGFloat = 44
        static let contentCardTopSpacing: CGFloat = 8
        static let contentCardBottomSpacing: CGFloat = 8
        static let contentCardHorizontalInset: CGFloat = 16
        static let baseContentHeight: CGFloat = 160
        static let cornerRadius: CGFloat = 15
        static let contentCornerRadius: CGFloat = 10
    }

    private var headerView: UIView!
    private var headerTitleLabel: UILabel!
    private var collapseBtn: UIButton!
    private var bodyContainerView: UIView!
    private var addTypeBar: WMMenuView!
    private var contentCardView: UIView!
    private var bodyHeightConstraint: NSLayoutConstraint?
    private var contentCardHeightConstraint: NSLayoutConstraint?

    var quickAddView: GroupPathSequenceQuickAddView!
    var triggerAddView: GroupPathSequenceTriggerAddView!
    var manuallyAddView: GroupPathSequenceManuallyAddView!
    var refreshBtn: UIButton!
    var unfoldBtn: UIButton!
    private var deviceFilterBtn: UIButton!
    private let types: [PathSequenceDeviceAddMode] = [.quickAdd, .triggerAdd, .manuallyAdd]

    weak var delegate: GroupPathSequenceDeviceAddViewDelegate?
    var contentHeightChanged: ((CGFloat) -> Void)?
    var contentHeightPolicy: ContentHeightPolicy = .fixedBase {
        didSet {
            refreshPreferredHeight()
        }
    }

    private var currentMode: PathSequenceDeviceAddMode = .quickAdd
    private var collapsed: Bool = true
    private var headerIndex: Int?
    private var lastPreferredContentHeight: CGFloat = 0
    private var lastMenuWidth: CGFloat = 0
    private var deviceNameFilterSession: DeviceNameFilterSession?
    private var deviceNameFilterObservation: UUID?

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
        layer.cornerRadius = LayoutMetrics.cornerRadius
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let deviceNameFilterObservation {
            deviceNameFilterSession?.removeObserver(deviceNameFilterObservation)
        }
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
        let rowNum = max(1, min(Int(ceilf(Float(manuallyAddView.visibleDevices.count) / Float(manuallyAddView.colNum))), 3))
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

    @objc private func deviceFilterBtnAction() {
        guard let deviceNameFilterSession else {
            return
        }
        DeviceNameFilterMenuView.show(
            from: deviceFilterBtn,
            onSearch: { [weak self] in
                guard let self, let deviceNameFilterSession = self.deviceNameFilterSession else {
                    return
                }
                DeviceNameFilterSearchView.show(
                    initialText: deviceNameFilterSession.query,
                    onSubmit: { [weak deviceNameFilterSession] text in
                        deviceNameFilterSession?.submit(text)
                    }
                )
            },
            onReset: { [weak deviceNameFilterSession] in
                deviceNameFilterSession?.reset()
            }
        )
    }
    
    private func setupUI() {
        headerView = UIView()
        addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(LayoutMetrics.headerHeight)
        }
        headerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(collapseBtnAction)))

        collapseBtn = UIButton(type: .custom)
        collapseBtn.isUserInteractionEnabled = false
        collapseBtn.setImage(UIImage(named: "arrow_up_black"), for: .normal)
        headerView.addSubview(collapseBtn)
        collapseBtn.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(-16)
            make.width.height.equalTo(30)
        }

        headerTitleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14, fit: false)
        headerTitleLabel.numberOfLines = 1
        headerTitleLabel.lineBreakMode = .byTruncatingTail
        headerTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerView.addSubview(headerTitleLabel)
        headerTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(16)
            make.right.lessThanOrEqualTo(collapseBtn.snp.left).offset(-8)
            make.top.greaterThanOrEqualTo(6)
            make.bottom.lessThanOrEqualTo(-6)
            make.centerY.equalToSuperview()
        }

        bodyContainerView = UIView()
        addSubview(bodyContainerView)
        bodyContainerView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom)
            make.left.right.equalToSuperview()
        }
        let initialBodyHeight = LayoutMetrics.addTypeBarHeight
            + LayoutMetrics.contentCardTopSpacing
            + LayoutMetrics.baseContentHeight
            + LayoutMetrics.contentCardBottomSpacing
        bodyHeightConstraint = bodyContainerView.heightAnchor.constraint(equalToConstant: initialBodyHeight)
        bodyHeightConstraint?.isActive = true

        addTypeBar = WMMenuView(frame: CGRect(x: 0, y: 0, width: SCREEN_WIDTH, height: LayoutMetrics.addTypeBarHeight))
        addTypeBar.layoutMode = .left
        addTypeBar.style = .line
        addTypeBar.lineColor = Bar_Color
        addTypeBar.progressWidths = [92, 92, 92]
        addTypeBar.fontWeight = .light
        addTypeBar.progressHeight = 2
        addTypeBar.itemRateAnimation = false
        addTypeBar.progressViewBottomSpace = 6
        addTypeBar.dataSource = self
        addTypeBar.delegate = self
        bodyContainerView.addSubview(addTypeBar)
        addTypeBar.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalToSuperview()
            make.height.equalTo(LayoutMetrics.addTypeBarHeight)
        }

        contentCardView = UIView()
        contentCardView.backgroundColor = .white
        contentCardView.layer.cornerRadius = LayoutMetrics.contentCornerRadius
        bodyContainerView.addSubview(contentCardView)
        contentCardView.snp.makeConstraints { make in
            make.top.equalTo(addTypeBar.snp.bottom).offset(LayoutMetrics.contentCardTopSpacing)
            make.left.right.equalToSuperview().inset(LayoutMetrics.contentCardHorizontalInset)
            make.bottom.equalToSuperview().inset(LayoutMetrics.contentCardBottomSpacing)
        }
        contentCardHeightConstraint = contentCardView.heightAnchor.constraint(equalToConstant: LayoutMetrics.baseContentHeight)
        contentCardHeightConstraint?.isActive = true
        
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
        manuallyAddView.visibleDevicesChanged = { [weak self] in
            self?.manualVisibleDevicesDidChange()
        }
        contentCardView.addSubview(manuallyAddView)
        manuallyAddView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        refreshBtn = UIButton(normalImageName: "trigger_device_refresh", target: self, action: #selector(refreshBtnAction))
        refreshBtn.isHidden = true
        bodyContainerView.addSubview(refreshBtn)
        refreshBtn.snp.makeConstraints { make in
            make.centerY.equalTo(addTypeBar)
            make.right.equalTo(-24)
        }
        
        unfoldBtn = UIButton(normalImageName: "devices_unfold", selectedImageName: "devices_fold", target: self, action: #selector(unfoldBtnAction))
        unfoldBtn.isHidden = true
        bodyContainerView.addSubview(unfoldBtn)
        unfoldBtn.snp.makeConstraints { make in
            make.center.equalTo(refreshBtn)
        }

        deviceFilterBtn = UIButton(
            normalImageName: "device_filter",
            selectedImageName: "device_filter_selected",
            target: self,
            action: #selector(deviceFilterBtnAction)
        )
        deviceFilterBtn.isHidden = true
        deviceFilterBtn.accessibilityLabel = "device_filter_search_by_name".localizedString
        addSubview(deviceFilterBtn)
        deviceFilterBtn.snp.makeConstraints { make in
            make.centerY.equalTo(collapseBtn)
            make.right.equalTo(collapseBtn.snp.left).offset(-16)
            make.width.height.equalTo(30)
        }
        
        updateHeaderTitle()
        updateCollapseUI(animated: false)
    }
    
    func updateUnfoldState() {
        updateAccessoryButtons()
        refreshPreferredHeight()
    }

    func configureDeviceNameFilter(session: DeviceNameFilterSession) {
        if let deviceNameFilterObservation {
            deviceNameFilterSession?.removeObserver(deviceNameFilterObservation)
        }
        deviceNameFilterSession = session
        manuallyAddView.configureDeviceNameFilter(session: session)
        deviceNameFilterObservation = session.observe { [weak self] _ in
            guard let self else { return }
            self.deviceFilterBtn.isSelected = session.isActive
            self.updateAccessoryButtons()
        }
    }

    private func manualVisibleDevicesDidChange() {
        let maxManualRows = max(
            1,
            min(Int(ceilf(Float(manuallyAddView.visibleDevices.count) / Float(manuallyAddView.colNum))), 3)
        )
        if manuallyAddView.rowNum > maxManualRows {
            manuallyAddView.rowNum = maxManualRows
            unfoldBtn.isSelected = maxManualRows > 1
        }
        updateUnfoldState()
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
            let imageName = self.collapsed ? "arrow_up_black" : "arrow_down_black"
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
        guard !collapsed, canAddDevice else {
            refreshBtn.isHidden = true
            unfoldBtn.isHidden = true
            deviceFilterBtn.isHidden = true
            return
        }

        let maxManualRows = max(1, min(Int(ceilf(Float(manuallyAddView.visibleDevices.count) / Float(manuallyAddView.colNum))), 3))
        refreshBtn.isHidden = currentMode != .triggerAdd || triggerAddView.devices.isEmpty
        unfoldBtn.isHidden = currentMode != .manuallyAdd || maxManualRows <= 1 || !manuallyAddView.guideContentView.isHidden
        deviceFilterBtn.isHidden = currentMode != .manuallyAdd || deviceNameFilterSession == nil
    }

    private func emitPreferredHeightIfNeeded() {
        let bodyHeight = updateContentHeightConstraints()
        let contentHeight: CGFloat
        if isHidden {
            contentHeight = 0
        } else if collapsed {
            contentHeight = LayoutMetrics.headerHeight
        } else {
            contentHeight = LayoutMetrics.headerHeight + bodyHeight
        }
        guard let contentHeightChanged else {
            return
        }
        guard abs(contentHeight - lastPreferredContentHeight) > 0.5 else {
            return
        }
        lastPreferredContentHeight = contentHeight
        contentHeightChanged(contentHeight)
    }

    private func updateContentHeightConstraints() -> CGFloat {
        let contentHeight = resolvedContentHeight()
        let bodyHeight = LayoutMetrics.addTypeBarHeight
            + LayoutMetrics.contentCardTopSpacing
            + contentHeight
            + LayoutMetrics.contentCardBottomSpacing
        contentCardHeightConstraint?.constant = contentHeight
        bodyHeightConstraint?.constant = bodyHeight
        return bodyHeight
    }

    private func resolvedContentHeight() -> CGFloat {
        switch contentHeightPolicy {
        case .fixedBase:
            if currentMode == .manuallyAdd, manuallyAddView.guideContentView.isHidden {
                return max(LayoutMetrics.baseContentHeight, manuallyAddView.preferredContentHeight)
            }
            return LayoutMetrics.baseContentHeight
        case .dynamicSelected:
            return max(LayoutMetrics.baseContentHeight, maximumPreferredContentHeightAcrossModes())
        }
    }

    private func maximumPreferredContentHeightAcrossModes() -> CGFloat {
        return max(
            quickAddView.preferredContentHeight,
            max(
                triggerAddView.preferredContentHeight,
                manuallyAddView.preferredContentHeight
            )
        )
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
        return isIPad ? 150 : 92
    }
    
    func menuView(_ menu: WMMenuView!, itemMarginAt index: Int) -> CGFloat {
        return index == 0 ? 16 : 4
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
