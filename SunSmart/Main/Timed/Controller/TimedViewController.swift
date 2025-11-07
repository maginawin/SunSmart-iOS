//
//  TimedViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/5.
//

import UIKit
import NordicSigMeshSDK

let schedulesRefreshNotificationName = "schedulesRefreshNotification"
let scheduleDataUpdateNotificationName = "scheduleDataUpdateNotification"

class TimedViewController: UIViewController {

    /// 底部
    private var footerView: SpaceFunctionFooterView!
    private var scheduleFlowLayout: UICollectionViewFlowLayout!
    private var scheduleCollectionView: UICollectionView!
    private var selectTypeView: TimedSelectTypeView!
    
//    private var schedules: [Schedule] = []
    private var refreshData = false
    
    let space: SpaceData
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        setupUI()
        
//        let actions: [SchedulerAction] = [.turnOn, .turnOff, .sceneRecall]
//        
//        let allWeekDays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
//        
//        let workdays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday]
//        
//        let weekends: [WeekDay] = [.Saturday, .Sunday]
//        
//        let irregularity: [WeekDay] = [.Monday, .Wednesday, .Saturday]
//        
//        let randomWeeks = [allWeekDays, workdays, weekends, irregularity]
//        
//        let create = "\(CLongLong(Date().timeIntervalSince1970 * 1000))"
//        for i in 1...4 {
//            let actionIndex = arc4random_uniform(UInt32(actions.count))
//            let weekIndex = arc4random_uniform(UInt32(randomWeeks.count))
//            
//            let schedule = Schedule(id: i, name: "Schedule \(i)", enabled: i < 3, action: actions[Int(actionIndex)], fadeTime: 5, weekDays: randomWeeks[Int(weekIndex)], hour: Int(arc4random_uniform(24)), minute: 0, create: create)
//            schedules.append(schedule)
//        }
        
        footerView.countBtn.setTitle("\(MeshNetworkManager.instance.schedules.count)/16", for: .normal)
        
        addNotification()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
//        if refreshData {
//            refreshData = false
            updateUI()
//        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if scheduleCollectionView.firstShowFlashScrollIndicators {
            scheduleCollectionView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        updateEmptyUI()
        
        if scheduleCollectionView.contentInset.top == 0 {
            var inset = scheduleCollectionView.contentInset
            inset.top = SCRXFrom(16)
            scheduleCollectionView.contentInset = inset
        }
    }

    
    /// 添加通知监听
    private func addNotification() {
        
        NotificationCenter.default.addObserver(forName: .init(schedulesRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            guard let self = self else { return }
            if self.view.window != nil {
                self.updateUI()
            }else {
                self.refreshData = true
            }
            self.space.scheheduleCount = MeshNetworkManager.instance.schedules.count
            self.space.save()
        }
        
        NotificationCenter.default.addObserver(forName: .init(scheduleDataUpdateNotificationName), object: nil, queue: nil) { [weak self] notification in
            guard let self = self, let schedule = notification.object as? Schedule else {
                return
            }
            self.reloadCollectionItem(schedule: schedule)
        }
        
        // space编辑权限变更回调
        NotificationCenter.default.addObserver(forName: .init(spacePermissionChangedNotificaitonName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            self.updateUI()
        }
        
    }
    
    /// 设置日程启用/禁用
    private func setScheduleEnabled(schedule: Schedule, enabled: Bool) {
        
        guard schedule.exitNodes.count > 0 else {
            schedule.enabled = enabled
            schedule.save()
            self.reloadCollectionItem(schedule: schedule)
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            return
        }
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: "processing".localizedString, isWindow: true)
        ScheduleServer.setEnabledState(schedule: schedule, enabled: enabled) {[weak self] _ in
            XWHUDManager.hide()
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            self?.reloadCollectionItem(schedule: schedule)
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
        } failed: {[weak self] _ in
            XWHUDManager.hide()
            XWHUDManager.showErrorTipHUD("failed".localizedString + "!")
            self?.reloadCollectionItem(schedule: schedule)
            
            let vc = SyncDevicesViewController(type: .schedule(schedule))
            vc.syncSuccessCallback = {[weak self] _ in
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                guard let self = self else {
                    return
                }
                schedule.enabled = enabled
                schedule.save()
                self.reloadCollectionItem(schedule: schedule)
                self.dismiss(animated: true)
            }
            vc.backActionCallback = {[weak self] _ in
                self?.dismiss(animated: true)
                self?.reloadCollectionItem(schedule: schedule)
            }
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            self?.present(NavigationViewController(rootViewController: vc), animated: true)
        }
    }
    
    private func updateUI() {
  
        footerView.countBtn.setTitle("\(MeshNetworkManager.instance.schedules.count)/16", for: .normal)
        
        footerView.addBtn.isEnabled = space.scheduleOperates.contains(.add)
        
        updateEmptyUI()
        
        scheduleCollectionView.reloadData()
    }
    
    
    private func updateEmptyUI() {
        
        if MeshNetworkManager.instance.schedules.isEmpty {
            scheduleCollectionView.showEmptyDataView(title: "no_schedules".localizedString, tipText: "no_schedules_message".localizedString, position: .center, bottomMargin: SCRYFit(27))
            if let emptyView = scheduleCollectionView.emptyView {
                emptyView.titleLabel.font = FONTS(SCRYFrom(15))
                emptyView.tipLabel.font = UIFont.systemFont(ofSize: 15, weight: .light)
            }
        }else {
            scheduleCollectionView.hideEmptyDataView()
        }
    }
    
    private func reloadCollectionItem(schedule: Schedule) {
        if let index = MeshNetworkManager.instance.schedules.firstIndex(where: {$0.id == schedule.id}) {
            CATransaction.setDisableActions(true)
            scheduleCollectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
            CATransaction.commit()
        }
    }
    
    
    private func setupUI() {
        
        footerView = SpaceFunctionFooterView()
        footerView.editBtn.isHidden = true
        footerView.sortBtn.isHidden = true
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(44))
        }
        
//        selectTypeView = TimedSelectTypeView()
//        selectTypeView.delegate = self
//        view.addSubview(selectTypeView)
//        selectTypeView.snp.makeConstraints { make in
//            make.left.right.equalToSuperview()
//            make.height.equalTo(SCRYFrom(106))
//            make.bottom.equalTo(footerView.snp.top)
//        }
        
//        view.sendSubviewToBack(selectTypeView)
        
        scheduleFlowLayout = UICollectionViewFlowLayout()
        scheduleFlowLayout.minimumLineSpacing = SCRXFrom(16)
        scheduleFlowLayout.minimumInteritemSpacing = 0
        scheduleFlowLayout.headerReferenceSize = .zero
//        scheduleFlowLayout.sectionInset = UIEdgeInsets(top: SCRXFrom(16), left: SCRXFrom(16), bottom: SCRXFrom(16), right: SCRXFrom(16))
        
        scheduleCollectionView = UICollectionView(frame: .zero, collectionViewLayout: scheduleFlowLayout)
//        scheduleCollectionView.showsVerticalScrollIndicator = false
        scheduleCollectionView.backgroundColor = .clear
        scheduleCollectionView.alwaysBounceVertical = true
        scheduleCollectionView.dataSource = self
        scheduleCollectionView.delegate = self
        scheduleCollectionView.register(SchedulesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        scheduleCollectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: SCRXFrom(16), right: SCRXFrom(16))
        view.addSubview(scheduleCollectionView)
        scheduleCollectionView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(footerView.snp.top)
        }
        
    }

}

extension TimedViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return MeshNetworkManager.instance.schedules.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SchedulesViewCell
        let schedule = MeshNetworkManager.instance.schedules[indexPath.item]
        cell.schedule = schedule
        cell.enabledActionCallback = {[weak self] enabled in
            guard let self = self else {
                return
            }
            guard self.space.scheduleOperates.contains(.edit) else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                return
            }
            self.setScheduleEnabled(schedule: schedule, enabled: enabled)
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - scheduleFlowLayout.sectionInset.left - scheduleFlowLayout.sectionInset.right
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        let schedule = MeshNetworkManager.instance.schedules[indexPath.item]
        
        return CGSize(width: itemW, height: schedule.enabled ? SCRYFrom(isIPad ? 130 : 114) : SCRYFrom(isIPad ? 84 : 64))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        guard self.space.scheduleOperates.contains(.edit) else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        
        let schedule = MeshNetworkManager.instance.schedules[indexPath.item]
        
        let vc = ScheduleAddViewController(space: space, schedule: schedule)
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
        
    }
}

extension TimedViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        guard MeshNetworkManager.instance.schedules.count < 16 else {
            SRAlertView(title: "notification".localizedString, message: "schedules_overrun_message".localizedString, actions: [SRAlertAction(title: "GOT_IT".localizedString)]).show()
            return
        }
        
        let vc = ScheduleAddViewController(space: space)
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
        
    }
}

extension TimedViewController: TimedSelectTypeViewDelegate {
    
    /// 选择类型
    func view(_ view: TimedSelectTypeView, selectTypeAction type: TimedSelectTypeView.TimedType) {
        
        guard type == .schedule else {
            scheduleCollectionView.isHidden = true
            XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)
            return
        }
        scheduleCollectionView.isHidden = false
    }
}
