//
//  DeviceAddCandidateDeviceListView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/24.
//

import UIKit
import NordicSigMeshSDK

protocol DeviceAddCandidateDeviceListViewDelegate: AnyObject {
    
    /// 设备开始identity
    func candidateView(_ view: DeviceAddCandidateDeviceListView, identify device: ProvisioningDevice)
    
    /// 停止扫描
    func candidateViewStopScan(_ view: DeviceAddCandidateDeviceListView)
    
    /// 设备预选撤销
    func candidateView(_ view: DeviceAddCandidateDeviceListView, candidateRevoke device: ProvisioningDevice)
    
    /// 设备开始添加
    func candidateView(_ view: DeviceAddCandidateDeviceListView, startAdd devices: [ProvisioningDevice])
    
    /// 选择设备添加目地的
    func candidateView(_ view: DeviceAddCandidateDeviceListView, selectAddDevicesTarget touchPoint: CGPoint, currentDeviceTypes: [Node.DeviceType])
    
}

class DeviceAddCandidateDeviceListView: UIView {

    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var candidateBtn: UIButton!
    private var addDeviceToLabel: UILabel!
    private var addDeviceTargetBtn: UIButton!
    /// 设备列表
    private var tableView: UITableView!
    /// 添加设备结果
    private var addResultView: DeviceAddResultView!
    /// 底部全选
    private var footerView: DeviceAddBottomView!
    /// 停止扫描
    private var stopScanView: UIView!
    private var stopScanBtn: UIButton!
    /// 类型view
    private var categoryView: WMMenuView!

    
    /// 最大设备数量
    private var maxDeviceCount = 200
    
    /// 展示的设备类型
    private var showDeviceTypes: [Node.DeviceType] = [.light]
    
    let space: SpaceData
    
    /// 预选的设备list
    var candidateDevices: [ProvisioningDevice] = [] {
        didSet {
            if candidateDevices.count > 0 {
                categoryView.isHidden = false
                updateDeviceCategoryCount()
            }else {
                categoryView.isHidden = true
            }
            updateUIState()
            showDevices = candidateDevices.filter({ showDeviceTypes.contains($0.deviceType) })
            if superview != nil {
                tableView.reloadData()
            }
        }
    }
    private var showDevices: [ProvisioningDevice] = []
    
    /// 添加设备的目的地
    var addTarget: AddDeviceToTarget? {
        didSet {
            var name = addTarget?.name ?? ""
            if showDeviceTypes.contains(.dongle) {
                if case .dongle(let dongle) = addTarget {
                    name = dongle.name
                }
            }else {
                if case .group(let group) = addTarget {
                    name = group.name
                }
            }
            addDeviceTargetBtn.setTitle(name, for: .normal)
        }
    }
    /// 外部传入指定添加该到group
//    var appointGroup: Group?
    
    /// 外部传入指定dognle设备绑定该到dognle数据
//    var forceBindToDongle: DeviceDongleData?
    
    /// 已存在的dognle数据list
//    private var dongles: [DeviceDongleData] = []
    
    weak var delegate: DeviceAddCandidateDeviceListViewDelegate?
    
    var state: DeviceAddState = .none {
        didSet {
            updateUIState()
        }
    }
    
    init(frame: CGRect, space: SpaceData) {
        self.space = space
        super.init(frame: frame)
        
        maxDeviceCount = space.maxDevicesCount
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
//    override func layoutSubviews() {
//        super.layoutSubviews()
//        
//        contentView.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: SCRYFrom(15), height: SCRYFrom(15)))
//    }

    func show() {
        if self.superview == nil {
            UIApplication.shared.keyWindow().addSubview(self)
            self.layoutIfNeeded()
        }
        
        self.contentView.y = self.height
        UIView.animate(withDuration: 0.25) {
            self.contentView.y = kNavigationHeight - 8
            
        } completion: { _ in
            self.tableView.reloadData()
        }
    }
    
    @objc func hide() {
        UIView.animate(withDuration: 0.25) {
            self.contentView.y = self.height
            
        }completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    func updateDeviceData(device: ProvisioningDevice) {
        // 更新缓存
//        if let index = candidateDevices.firstIndex(where: { $0.peripheral.identifier.uuidString == device.peripheral.identifier.uuidString }) {
//            candidateDevices.replaceSubrange(index...index, with: [device])
//            if let showIndex = showDevices.firstIndex(where: { $0.peripheral.identifier.uuidString == device.peripheral.identifier.uuidString }) {
//                showDevices.replaceSubrange(showIndex...showIndex, with: [device])
//            }
//        }
        reloadDeviceState(device)
    }
    
    // MARK: - Action
    
    @objc private func candidateBtnAction() {
        hide()
    }
    
    /// 添加目标选择事件
    @objc private func addDeviceTargetBtnClick(sender: UIButton) {
        
        if state == .adding {
            return
        }
        
        let touchPoint = CGPoint(x: sender.frame.maxX - TitleSelectView.defalutWidth, y: sender.frame.maxY + SCRYFrom(2))
        delegate?.candidateView(self, selectAddDevicesTarget: contentView.convert(touchPoint, to: self), currentDeviceTypes: showDeviceTypes)
    }
    
    /// 全选/取消全选
    @objc private func selectAllBtnClick(sender: UIButton) {
        
        // space只能添加200个设备
        let existNodeCount = MeshNetworkManager.instance.realNodes.count + candidateDevices.filter({ $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }).count

        sender.isSelected = !sender.isSelected
        
        let canAddDevices = candidateDevices.filter({ $0.selectedState != .disabled && !($0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting) })
        if sender.isSelected {
            if existNodeCount + canAddDevices.count > maxDeviceCount {
                SRAlertView(title: "notification".localizedString, message: "devices_number_exceeds_message".localizedString, actions: [SRAlertAction(title: "ok".localizedString)]).show()
                canAddDevices.prefix(maxDeviceCount - existNodeCount).forEach({ $0.selectedState = .selected })
            }else {
                canAddDevices.forEach({ $0.selectedState = .selected })
            }
            
//            selectCountLabel.text = "\(devices.count)/\(devices.count)"
        }else {
            canAddDevices.forEach({ $0.selectedState = .unselected })
            
//            selectCountLabel.text = "0/\(devices.count)"
        }
        updateFooterViewState()
        tableView.reloadData()
    }
    
    /// 批量添加
    @objc private func addSelectedBtnClick() {
        let selectDevices = showDevices.filter({ $0.selectedState == .selected })
        
        let dongleDevices = selectDevices.filter({ $0.deviceType == .dongle })
        // 多个dongle一起添加时提示
        if dongleDevices.count > 1 {
            SRAlertView(title: "notification".localizedString, message: "device_add_multiple_dongle_message".localizedString, actions: [.cancelAction, .init(title: "GOT IT".localizedString, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                self.delegate?.candidateView(self, startAdd: selectDevices)
            })]).show()
        }else {
            delegate?.candidateView(self, startAdd: selectDevices)
        }
    }
    
    /// 隐藏添加结果view
    @objc private func closeBtnClick() {
        addResultView.isHidden = true
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
    }
    
    /// 停止添加（取消正在排队的设备）
    @objc private func stopAddBtnClick() {
        guard state == .adding else {
            return
        }
        TestDeviceAddManager.manager.cancelAwaitOperations()
        
        MeshAPI.cancelFastAddAwaitOperations()
        let waitDevices = candidateDevices.filter({ $0.addState == .wait })
        waitDevices.forEach({
            $0.addState = .none
            $0.selectedState = .selected
        })
        tableView.reloadData()
        updateUIState()
    }
    
    /// 停止扫描
    @objc private func stopScanBtnAction() {
        state = .none
        updateUIState()
        tableView.reloadData()
        delegate?.candidateViewStopScan(self)
    }
    
    /// 更新UI
    private func updateUIState() {
        
        stopScanView.isHidden = state != .scanning
        
        switch state {
        case .none:
            footerView.isHidden = false
            addResultView.isHidden = true
            updateFooterViewState()
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(8), right: 0)
        case .scanning:
            footerView.isHidden = true
            tableView.contentInset = .zero
            addResultView.isHidden = true
        case .identifying:
            break
        case .adding, .addFineshed:
            
            footerView.isHidden = false
            updateFooterViewState()
            if state == .adding {
                addResultView.isHidden = false
                tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: addResultView.height + SCRYFrom(8), right: 0)
                addResultView.closeBtn.isHidden = true
                addResultView.stopAddBtn.isHidden = !showDevices.contains(where: { $0.addState == .wait})
                // 添加中设置屏幕常亮
                UIApplication.shared.isIdleTimerDisabled = true
            }else {
                addResultView.closeBtn.isHidden = false
                addResultView.stopAddBtn.isHidden = true
            }
            let successCount = candidateDevices.filter({ $0.addState == .success }).count
            let failedCount = candidateDevices.filter({ $0.addState == .failed }).count
            addResultView.successCountLabel.text = "\("successfully".localizedString) : \(successCount)"
            addResultView.failedCountLabel.text = "\(failedCount)"
            
        }
    }
    
    /// 更新设备类型数量
    private func updateDeviceCategoryCount() {
        categoryView.updateTitle("\("lights".localizedString)-\(candidateDevices.filter({ $0.deviceType == .light }).count)", at: 0, andWidth: false)
        categoryView.updateTitle("\("switches".localizedString)-\(candidateDevices.filter({ $0.deviceType == .switches }).count)", at: 1, andWidth: false)
        categoryView.updateTitle("\("sensors".localizedString)-\(candidateDevices.filter({ $0.deviceType == .sensor }).count)", at: 2, andWidth: false)
        categoryView.updateTitle("\("others".localizedString)-\(candidateDevices.filter({ $0.deviceType == .dongle || $0.deviceType == .gateway || $0.deviceType == .unknown }).count)", at: 3, andWidth: false)
    }
    
    /// 更新底部view数量状态
    private func updateFooterViewState() {
        let selectDevices = showDevices.filter({ $0.selectedState == .selected })
        let enableDevices = showDevices.filter({ $0.selectedState != .disabled })
        footerView.selectCountLabel.text = "\(selectDevices.count)/\(enableDevices.count)"
        if !enableDevices.isEmpty && selectDevices.count >= enableDevices.count {
            footerView.selectAllBtn.isSelected = true
        }else {
            footerView.selectAllBtn.isSelected = false
        }
        footerView.addSelectedBtn.isEnabled = selectDevices.count > 0
    }
    
    /// 刷新设备UI状态
    private func reloadDeviceState(_ device: ProvisioningDevice) {
        
        var indexPath: IndexPath?
        if let index = showDevices.firstIndex(of: device) {
            indexPath = IndexPath(row: index, section: 0)
        }
        
        if let indexPath = indexPath {
            if let cell = tableView.cellForRow(at: indexPath) as? DeviceAddViewCell {
                cell.device = device
            }
        }
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hide)))
//        shadeView.backgroundColor = RGB(0, 0, 0, 0.05)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = Background_Color
        contentView.layer.cornerRadius = SCRYFrom(15)
        contentView.layer.shadowOffset = CGSize(width: 0, height: -5)
        contentView.layer.shadowRadius = 6
        contentView.layer.shadowColor = UIColor.black.withAlphaComponent(0.1).cgColor
        contentView.layer.shadowOpacity = 1
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(self.snp.bottom)
            make.height.equalTo(height - kNavigationHeight + 8)
        }
        
        candidateBtn = UIButton(title: "candidate_device_list".localizedString, titleSize: 15, titleColor: TextBlack_Color, normalImageName: "arrow_down_black", target: self, action: #selector(candidateBtnAction))
        candidateBtn.setImagePosition(position: .right, spacing: SCRXFrom(2))
        contentView.addSubview(candidateBtn)
        candidateBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(54))
        }
        
        addDeviceTargetBtn = UIButton(title: "space", titleSize: 13, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "space_arrow_down", target: self, action: #selector(addDeviceTargetBtnClick))
        addDeviceTargetBtn.contentHorizontalAlignment = .left
        addDeviceTargetBtn.layer.cornerRadius = SCRYFrom(5)
        addDeviceTargetBtn.layer.borderWidth = 1
        addDeviceTargetBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        addDeviceTargetBtn.backgroundColor = .white
        contentView.addSubview(addDeviceTargetBtn)
        addDeviceTargetBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(candidateBtn.snp.bottom)
            make.width.equalTo(SCRXFrom(128))
            make.height.equalTo(SCRYFrom(32))
        }
        addDeviceTargetBtn.layoutIfNeeded()
        addDeviceTargetBtn.imageView?.sizeToFit()
        let imageW = addDeviceTargetBtn.imageView?.image?.size.width ?? 0
        addDeviceTargetBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: addDeviceTargetBtn.width - imageW, bottom: 0, right: 0)
        addDeviceTargetBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8) - imageW, bottom: 0, right: imageW + SCRXFrom(6))
        
        addDeviceToLabel = UILabel(text: "add_device_to".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(addDeviceToLabel)
        addDeviceToLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(17))
            make.centerY.equalTo(addDeviceTargetBtn)
        }
        
        categoryView = WMMenuView(frame: CGRect(x: 0, y: 0, width: self.width, height: CGFloat(Int(SCRYFrom(32)))))
        categoryView.itemBackgroundColor = .clear
        categoryView.itemCornerRadius = CGFloat(Int(SCRYFrom(16)))
        if isIPad {
            categoryView.layoutMode = .center
        }
        categoryView.itemRateAnimation = false
        categoryView.fontWeight = .light
        categoryView.isHidden = true
        categoryView.dataSource = self
        categoryView.delegate = self
        categoryView.selectItem(at: 0)
        contentView.addSubview(categoryView)
        categoryView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(addDeviceTargetBtn.snp.bottom).offset(SCRYFrom(12))
            make.height.equalTo(SCRYFrom(32))
        }
        
        stopScanView = UIView()
        stopScanView.backgroundColor = .white
        contentView.addSubview(stopScanView)
        stopScanView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
        
        stopScanBtn = UIButton(title: "stop_scaning_to_add_devices".localizedString, titleSize: 15, titleWeight: .light, titleColor: TextBlack_Color, target: self, action: #selector(stopScanBtnAction))
        stopScanView.addSubview(stopScanBtn)
        stopScanBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(60))
        }
       
        footerView = DeviceAddBottomView()
        footerView.isHidden = true
        contentView.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
        footerView.selectAllBtn.addTarget(self, action: #selector(selectAllBtnClick), for: .touchUpInside)
        footerView.addSelectedBtn.addTarget(self, action: #selector(addSelectedBtnClick), for: .touchUpInside)
        
        addResultView = DeviceAddResultView()
        addResultView.isHidden = true
        contentView.addSubview(addResultView)
        addResultView.snp.makeConstraints { make in
            make.bottom.equalTo(footerView.snp.top).offset(SCRYFrom(-1))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(72))
        }
        addResultView.closeBtn.addTarget(self, action: #selector(closeBtnClick), for: .touchUpInside)
        addResultView.stopAddBtn.addTarget(self, action: #selector(stopAddBtnClick), for: .touchUpInside)
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(70)
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.register(DeviceAddViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(8), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(footerView.snp.top)
            make.top.equalTo(categoryView.snp.bottom).offset(SCRYFrom(12))
        }
        
    }
    
}

extension DeviceAddCandidateDeviceListView: WMMenuViewDataSource, WMMenuViewDelegate {
    
    func numbersOfTitles(in menu: WMMenuView!) -> Int {
        return 4
    }
    
    func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {

        switch index {
        case 0:
            return "\("lights".localizedString)-\(candidateDevices.filter({ $0.deviceType == .light }).count)"
        case 1:
            return "\("switches".localizedString)-\(candidateDevices.filter({ $0.deviceType == .switches }).count)"
        case 2:
            return "\("sensors".localizedString)-\(candidateDevices.filter({ $0.deviceType == .sensor }).count)"
        case 3:
            return "\("others".localizedString)-\(candidateDevices.filter({ $0.deviceType == .dongle || $0.deviceType == .unknown }).count)"
        default:
            return ""
        }
    }
    
    func menuView(_ menu: WMMenuView!, titleSizeFor state: WMMenuItemState, at index: Int) -> CGFloat {
        return 14
    }
    
    func menuView(_ menu: WMMenuView!, titleColorFor state: WMMenuItemState, at index: Int) -> UIColor! {
        return state == .selected ? .white : Bar_Color
    }
    
    func menuView(_ menu: WMMenuView!, widthForItemAt index: Int) -> CGFloat {
        return isIPad ? SCRXFrom(120) : SCRXFrom(80)
    }
    
    func menuView(_ menu: WMMenuView!, itemMarginAt index: Int) -> CGFloat {

        if index == 0 || index == 4 {
            return SCRXFrom(12)
        }
        return SCRXFrom(10)
    }
    
//    func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
//        if forceBindToDongle != nil && index != 3 {
//            XWHUDManager.showTipHUD("dongle_cannot_select_message".localizedString, isLineFeed: true)
//            return false
//        }
//        return true
//    }
    
    func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
        
        let item = menu.item(at: index)
        item?.backgroundColor = Bar_Color
        item?.font = UIFont.systemFont(ofSize: 14)
        
        guard index != currentIndex else {
            return
        }
        
        let lastItem = menu.item(at: currentIndex)
        lastItem?.backgroundColor = .white
        
        switch index {
        case 0:
            showDeviceTypes = [.light]
        case 1:
            showDeviceTypes = [.switches]
        case 2:
            showDeviceTypes = [.sensor]
        case 3:
            showDeviceTypes = [.dongle, .gateway, .unknown]
        default:
            showDeviceTypes = [.light]
        }
        
        self.showDevices = candidateDevices.filter({ showDeviceTypes.contains($0.deviceType) })
        tableView.reloadData()
        updateFooterViewState()
        
        // 更新设备添加到哪UI
        var name = space.name
        if showDeviceTypes.contains(.dongle) {
            if case .dongle(let dongle) = addTarget {
                name = dongle.name
            }
        }else {
            if case .group(let group) = addTarget {
                name = group.name
            }
        }
        addDeviceTargetBtn.setTitle(name, for: .normal)
    }
    
    func menuView(_ menu: WMMenuView!, initialMenuItem: WMMenuItem!, at index: Int) -> WMMenuItem! {
        if index == 0 {
            initialMenuItem.backgroundColor = Bar_Color
        }else {
            initialMenuItem.backgroundColor = .white
//                .white.withAlphaComponent(0.95)
        }
        return initialMenuItem
    }
    
}

extension DeviceAddCandidateDeviceListView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return showDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceAddViewCell
        cell.selectionStyle = .none
        let device = showDevices[indexPath.row]
        cell.device = device
        if state == .scanning {
            cell.addBtn.setImage(UIImage(named: "device_add_revoke"), for: .normal)
            cell.addBtn.setImage(nil, for: .disabled)
        }else {
            cell.addBtn.setImage(UIImage(named: "device_add"), for: .normal)
            cell.addBtn.setImage(UIImage(named: "device_add_disable"), for: .disabled)
        }
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let device = showDevices[indexPath.row]
        guard device.selectedState == .unselected || device.selectedState == .selected else {
            return
        }
        // space只能添加200个设备
        guard MeshNetworkManager.instance.realNodes.count + showDevices.filter({ $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }).count < maxDeviceCount else {
            SRAlertView(title: "notification".localizedString, message: "devices_number_exceeds_message".localizedString, actions: [SRAlertAction(title: "ok".localizedString)]).show()
            return
        }
        
        if device.selectedState == .unselected {
            device.selectedState = .selected
        }else {
            device.selectedState = .unselected
        }
        if device.addState == .failed {
            device.addState = .none
            device.selectedState = .selected
            tableView.reloadRows(at: [indexPath], with: .none)
            updateUIState()
        }else {
            if let cell = tableView.cellForRow(at: indexPath) as? DeviceAddViewCell {
                switch device.selectedState {
                case .unselected:
                    cell.selectImageView.image = UIImage(named: "device_select_un")
                case .selected:
                    cell.selectImageView.image = UIImage(named: "device_select")
                case .disabled:
                    cell.selectImageView.image = UIImage(named: "device_select_disable")
                }
            }else {
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
        
        updateFooterViewState()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isTracking else {
            return
        }
        
        let offsetY = scrollView.contentOffset.y
        
        if offsetY < 0 { // 向上
            let showContentY = self.height - self.contentView.height
            if contentView.y >= showContentY {
                contentView.y += abs(offsetY)
                scrollView.contentOffset = .zero
            }else {
                if contentView.y > showContentY {
                    contentView.y -= offsetY
                    scrollView.contentOffset = .zero
                }
            }
        }else {
            let showContentY = self.height - self.contentView.height
            if contentView.y > showContentY {
                contentView.y -= offsetY
                scrollView.contentOffset = .zero
            }
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.contentView.isUserInteractionEnabled = false
        self.shadeView.isUserInteractionEnabled = false
    }
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        self.contentView.isUserInteractionEnabled = true
        self.shadeView.isUserInteractionEnabled = true
        // 判断滑动结束后距离起始点距离，>100则认为隐藏，否则还原；velocity滑动力度大的时候直接退出
        let showContentY = self.height - self.contentView.height
        if scrollView.contentOffset.y <= 0 && (contentView.y - showContentY >= 120 || velocity.y < -0.5) {
            hide()
        }else {
            UIView.animate(withDuration: 0.25) {
                self.contentView.y = showContentY
            }
        }
    }
    
}

extension DeviceAddCandidateDeviceListView: DeviceAddViewCellDelegate {
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceAddViewCell, identify device: ProvisioningDevice) {
        if device.addState == .identifying {
            return
        }
        delegate?.candidateView(self, identify: device)
    }
    
    /// 设备添加点击事件回调
    func cell(_ cell: DeviceAddViewCell, deviceAdd device: ProvisioningDevice) {
        if state == .scanning {
            delegate?.candidateView(self, candidateRevoke: device)
//            candidateDevices.removeAll(where: { $0.macAddress == device.macAddress })
//            showDevices.removeAll(where: { $0.macAddress == device.macAddress })
//            if let index = self.tableView.indexPath(for: cell)?.row {
//                tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
//            }
            return
        }
        // space只能添加200个设备
        guard MeshNetworkManager.instance.realNodes.count + showDevices.filter({ $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }).count < maxDeviceCount else {
            SRAlertView(title: "notification".localizedString, message: String(format: "devices_number_exceeds_message".localizedString, maxDeviceCount), actions: [SRAlertAction(title: "ok".localizedString)]).show()
            return
        }
        delegate?.candidateView(self, startAdd: [device])
    }
    
    /// 设备状态图标点击
    func cell(_ cell: DeviceAddViewCell, deviceStateImageClick device: ProvisioningDevice) {
        
        guard device.addState == .wait || device.addState == .failed else {
            return
        }
        if device.addState == .wait { // 等待添加
            MeshAPI.cancelFastAddAwaitOperations(devices: [device])
        }
        
        // 设备状态回归为默认状态
        device.addState = .none
        device.selectedState = .selected
        reloadDeviceState(device)
        
        updateUIState()
    }
}
