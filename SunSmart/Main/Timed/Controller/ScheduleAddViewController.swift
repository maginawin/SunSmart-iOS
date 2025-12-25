//
//  ScheduleAddViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/5.
//

import UIKit
import NordicSigMeshSDK

/// 日程执行目标
enum ScheduleTarget {
    /// 设备（on/off）
    case devices(_ devices: [Node])
    /// 组（on/off）
    case groups(_ groups: [Group])
    /// 场景（recall）
    case scene(_ scene: Scene?)
}

class ScheduleAddViewController: UIViewController {

    private var scheduleAddView: ScheduleAddView!
    private var bottomView: UIView!
    private var saveBtn: UIButton!
    private var doneBtn: UIButton!
    private var lineView: UIView!
    private var deleteBtn: UIButton!
    /// 添加日程完成
    private var addFineshed = false
    
    let space: SpaceData
    var schedule: Schedule?
    
    init(space: SpaceData, schedule: Schedule? = nil) {
        self.space = space
        self.schedule = schedule
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        view.backgroundColor = Background_Color
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        setupUI()
        setupData()
     
//        updateBtnState()
        
        
    }
    
    deinit {
        if space.isConfiguring {
            space.isConfiguring = false
        }
    }
    
    private func setupData() {
        
        if let schedule = self.schedule {
            title = "schedule_setting".localizedString
            
            scheduleAddView.name = schedule.name
            scheduleAddView.enabled = schedule.enabled
            let targets: [ScheduleTarget] = [.devices(schedule.nodes), .groups(schedule.groups), .scene(schedule.scene)]
            scheduleAddView.targetView.targets = targets
            switch schedule.selectTargetType {
            case .devices:
                scheduleAddView.selectTarget = targets.first
            case .groups:
                scheduleAddView.selectTarget = targets[1]
            case .scene:
                scheduleAddView.selectTarget = targets[2]
            case .profile:
                break
            }
            scheduleAddView.actionType = schedule.action
            scheduleAddView.fadeTime = schedule.fadeTime
            scheduleAddView.weekValue = Schedule.getWeekValue(weekDays: schedule.weekDays)
            scheduleAddView.hour = schedule.hour
            scheduleAddView.minute = schedule.minute
            
            // 判断需要同步设备数据
            if !schedule.getNeedSyncDatas().isEmpty() {
                scheduleAddView.isSyncCompletion = false
            }else {
                scheduleAddView.isSyncCompletion = true
            }
            
            saveBtn.isHidden = true
            deleteBtn.isHidden = false
            doneBtn.isHidden = false
            lineView.isHidden = false
            
        }else {
            title = "add_schedule".localizedString
            scheduleAddView.name = MeshNetworkManager.instance.getNextScheduleName()
        }
        
    }

    
    @objc private func back() {
//        let spaceVc = UIViewController.getVisibleVc()?.presentingViewController
        if addFineshed && self.space.isConfiguring { //  && (spaceVc?.isKind(of: SpaceViewController.classForCoder()) ?? false)
            self.dismiss(animated: false)
            let vc = SpaceNewCreationProcessController(space: self.space, options: .schedule)
//            spaceVc?.present(NavigationViewController(rootViewController: vc), animated: true)
            NotificationCenter.default.post(name: .init(spaceModalViewControllerNotificaitonName), object: NavigationViewController(rootViewController: vc))
            
        }else {
            self.dismiss(animated: true)
        }
        
    }
    
    /// 校验数据是否完整
    private func verify() -> Bool {
        
        guard scheduleAddView.isCompletion else {
            // 提示内容
//            var message = ""
            // 多个内容缺失
            var errorContents: [String] = []
            
            if scheduleAddView.selectTarget == nil {
                errorContents.append("target".localizedString)
//                message = "schedule_target_unselect".localizedString
            }
            if scheduleAddView.actionType == .noAction {
                
                errorContents.append("action".localizedString)
//                message = "schedule_action_unselect".localizedString
//                return
            }
            if scheduleAddView.weekValue == 0 {
                errorContents.append("select_days_and_time".localizedString)
//                message = "schedule_time_unselect".localizedString
            }
            
            if errorContents.count > 0 { // 多个内容缺失合并提示
                var content = "schedule_multiple_unselect_first".localizedString
                errorContents.enumerated().forEach { index, name in
                    content.append("\(index > 0 ? "," : "")“\(name)”")
                }
                content.append(" \("schedule_multiple_unselect_end".localizedString)")
                XWHUDManager.showTipHUD(content, isLineFeed: true)
            }
//            }else { // 单内容缺失
//                XWHUDManager.showTipHUD(message, isLineFeed: true)
//            }
            return false
        }
        return true
    }
    
    /// 保存（添加）
    @objc private func saveBtnAction() {
        
        guard let id = MeshNetworkManager.instance.getNextAvailableScheduleId() else {
            // 已有16个日程
            XWHUDManager.showTipHUD("schedules_overrun_message".localizedString, isLineFeed: true)
            return
        }
        // 检验数据完整性
        guard verify() else {
            return
        }

        let name = scheduleAddView.name
        
        let isEnabled = scheduleAddView.enabled
        
        let action = scheduleAddView.actionType
        
        let fadeTime = scheduleAddView.fadeTime
        
        var nodes: [Node] = []
        var groups: [Group] = []
        var scene: Scene?
        var selectTargetType: Schedule.TargetType = .groups
        // 是否需要同步
        var needSync = false
        
        let target = scheduleAddView.selectTarget!
        
        // 选择的目标
        switch target {
        case .devices(let selectNodes):
            nodes = selectNodes
            needSync = selectNodes.count > 0
            selectTargetType = .devices
        case .groups(let selectGroups):
            groups = selectGroups
            needSync = selectGroups.contains(where: { $0.nodes.count > 0 })
            selectTargetType = .groups
        case .scene(let selectScene):
            scene = selectScene
            if selectScene != nil {
                needSync = selectScene!.info.groups.contains(where: { $0.nodes.count > 0 })
            }
            selectTargetType = .scene
        }
        
        
        // 日程是否有设备
        let isExitNodes = nodes.count > 0 || groups.contains(where: { $0.nodes.count > 0 }) || (scene?.info.groups.contains(where: { $0.nodes.count > 0 }) ?? false)
        
        guard MeshLibManager.manager.isMeshNetworkConnected || !isExitNodes else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        let weekDays = Schedule.getWeekDays(weekValue: scheduleAddView.weekValue)
//        let create = "\(Date().timeIntervalSince1970 * 1000)"
        
       
        let schedule = Schedule(id: id, name: name, enabled: isEnabled, nodeAddresses: nodes.map({ $0.primaryUnicastAddress }), groupAddresses: groups.map({ $0.address.address }), sceneNumber: scene?.number, selectTargetType: selectTargetType, action: action, fadeTime: fadeTime, weekDays: weekDays, hour: scheduleAddView.hour, minute: scheduleAddView.minute)
        if schedule.save() {
//            groups.forEach({ $0.info.bindSchedules.append(schedule) })
            MeshNetworkManager.instance.schedules.append(schedule)
            space.scheheduleCount = MeshNetworkManager.instance.schedules.count
            space.save()
            addFineshed = true
        }
        
        groups.forEach({
            $0.info.bindSchedules.append(schedule)
        })
            
        scene?.info.groups.forEach({
            $0.info.bindSchedules.append(schedule)
        })
        
        if needSync { // 是否需要同步
            pushToSyncDevices(schedule: schedule)
        }else {
            XWHUDManager.showSuccessTipHUD("done".localizedString)
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1.5, execute: {
                XWHUDManager.hide()
                self.back()
                NotificationCenter.default.post(name: .init(schedulesRefreshNotificationName), object: nil)
            })
        }
        saveBtn.isEnabled = false
    }
    
    /// 删除（编辑）
    @objc private func deleteBtnAction() {
        
        guard let schedule = self.schedule else { return }
        guard schedule.existNodes.count > 0 else {
//            Schedule.deleteData(meshUUID: self.space.meshUUID, meshNetworkKey: space.meshNetworkKey, scheduleId: schedule.id)
            schedule.deleteData()
            MeshNetworkManager.instance.schedules.removeAll(where: { $0.id == schedule.id })
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            NotificationCenter.default.post(name: .init(schedulesRefreshNotificationName), object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                self?.back()
            }
            return
        }
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
        ScheduleServer.deleteSchedule(schedule: schedule) {[weak self] _ in
            XWHUDManager.hide()
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
//            Schedule.deleteData(meshUUID: self.space.meshUUID, meshNetworkKey: self.space.meshNetworkKey, scheduleId: schedule.id)
            schedule.deleteData()
            MeshNetworkManager.instance.schedules.removeAll(where: { $0.id == schedule.id })
            // 删除关联组缓存的对应日程
            var groups = schedule.groups
            groups.append(contentsOf: schedule.needDeleteGroups)
            if let sceneGroups = schedule.scene?.info.groups {
                groups.append(contentsOf: sceneGroups)
            }
            schedule.needDeleteScenes.forEach({
                groups.append(contentsOf: $0.info.groups)
            })
            if let sceneGroups = schedule.scene?.info.groups {
                groups.append(contentsOf: sceneGroups)
            }
            schedule.needDeleteScenes.forEach({
                groups.append(contentsOf: $0.info.groups)
            })
            groups.forEach({
                $0.info.bindSchedules.removeAll(where: {$0.id == schedule.id })
            })
            
            NotificationCenter.default.post(name: .init(schedulesRefreshNotificationName), object: nil)
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                self?.back()
            }
        } failed: { _ in
            XWHUDManager.hide()
            XWHUDManager.showErrorTipHUD("schedule_delete_failed".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                self?.pushToSyncDevices(schedule: schedule, delete: true)
            }
        }
        
    }
    
    /// 完成（编辑）
    @objc private func doneBtnAction() {
        guard let schedule = self.schedule else { return }
        
        // 检验数据完整性
        guard verify() else {
            return
        }
        
        let name = scheduleAddView.name
        let isEnabled = scheduleAddView.enabled
        let action = scheduleAddView.actionType
        let fadeTime = scheduleAddView.fadeTime
        var nodes: [Node] = []
        var groups: [Group] = []
        var scene: Scene?
        var selectTargetType: Schedule.TargetType = .groups
        let weekDays = Schedule.getWeekDays(weekValue: scheduleAddView.weekValue)
        let hour = scheduleAddView.hour
        let minute = scheduleAddView.minute
        
        // 选择的目标
        if let target = scheduleAddView.selectTarget {
            switch target {
            case .devices(let selectNodes):
                nodes = selectNodes
                selectTargetType = .devices
            case .groups(let selectGroups):
                groups = selectGroups
                selectTargetType = .groups
            case .scene(let selectScene):
                scene = selectScene
                selectTargetType = .scene
            }
        }
        
        // 日程是否有设备
        let isExitNodes = schedule.existNodes.count > 0 || nodes.count > 0 || groups.contains(where: { $0.nodes.count > 0 }) || (scene?.info.groups.contains(where: { $0.nodes.count > 0 }) ?? false)
        
        guard MeshLibManager.manager.isMeshNetworkConnected || !isExitNodes else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        if schedule.name != name {
            schedule.name = name
        }
        
        schedule.enabled = isEnabled
        schedule.action = action
        schedule.fadeTime = fadeTime
    
        schedule.selectTargetType = selectTargetType
        // 选中之前移除失败的设备，则把设备改为待添加
        schedule.needDeleteNodeAddresses.removeAll(where: { address in
            nodes.contains(where: { $0.primaryUnicastAddress == address }) || groups.contains(where: { $0.nodes.contains(where: { $0.primaryUnicastAddress == address }) || scene?.info.groups.contains(where: { $0.nodes.contains(where: { $0.primaryUnicastAddress == address }) }) ?? false })
        })
        
        let deleteNodes = schedule.nodes.filter({ !nodes.contains($0) && !schedule.needDeleteNodes.contains($0) })
        if deleteNodes.count > 0 {
            schedule.needDeleteNodeAddresses.append(contentsOf: deleteNodes.map({ $0.primaryUnicastAddress }))
//            schedule.needDeleteNodes.append(contentsOf: deleteNodes)
        }
        schedule.nodeAddresses = nodes.map({ $0.primaryUnicastAddress })
        
        schedule.needDeleteGroupAddresses.removeAll(where: { address in
            groups.contains(where: { $0.address.address == address }) || scene?.info.groups.contains(where: { $0.address.address == address }) ?? false
        })
        
        let deleteGroups = schedule.groups.filter({ !groups.contains($0) && $0.nodes.contains(where: { groupNode in !schedule.nodeAddresses.contains(groupNode.primaryUnicastAddress) }) && !schedule.needDeleteGroups.contains($0) })
        if deleteGroups.count > 0 {
            schedule.needDeleteGroupAddresses.append(contentsOf: deleteGroups.map({ $0.address.address }))
//            schedule.needDeleteGroups.append(contentsOf: deleteGroups)
        }
        schedule.groupAddresses = groups.map({ $0.address.address })
        
        
        if schedule.scene != scene { // 切换场景
            schedule.needDeleteSceneNumbers.removeAll(where: { $0 == scene?.number })
//            schedule.needDeleteScenes.removeAll(where: { $0 == scene })
            if let lastScene = schedule.scene { // 上一个场景
                lastScene.info.groups.forEach({ group in
                    if !groups.contains(group) {
                        group.info.bindSchedules.removeAll(where: { $0.id == schedule.id })
                    }
                })
                schedule.needDeleteSceneNumbers.append(lastScene.number)
//                schedule.needDeleteScenes.append(lastScene)
            }
            scene?.info.groups.forEach({ group in
                group.info.bindSchedules.append(schedule)
            })
            schedule.sceneNumber = scene?.number
        }
        
        schedule.weekDays = weekDays
        schedule.hour = hour
        schedule.minute = minute
        
        schedule.save()
        schedule.existNodes.forEach { node in
            node.clearSyncStateCache()
        }
        
        // 判断需要同步设备数据
        if !schedule.getNeedSyncDatas().isEmpty() {
            pushToSyncDevices(schedule: schedule)
        }else { // 无需同步，仅编辑名称参数不影响设备配置
            XWHUDManager.showSuccessTipHUD("done".localizedString)
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1.5, execute: {
                XWHUDManager.hide()
                self.back()
                NotificationCenter.default.post(name: .init(schedulesRefreshNotificationName), object: nil)
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            })
        }
        
    }
    
    /// 跳转到同步设备页面
    private func pushToSyncDevices(schedule: Schedule, delete: Bool = false) {
        
        let vc = SyncDevicesViewController(type: .schedule(schedule))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done".localizedString)
            guard let self = self else { return }
//            self.schedule?.needDeleteNodeAddresses.removeAll()
//            self.schedule?.needDeleteGroupAddresses.removeAll()
//            self.schedule?.needDeleteSceneNumbers.removeAll()
//            self.schedule?.save()
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1.5, execute: {
                XWHUDManager.hide()
                self.back()
                if self.schedule == nil || delete { // 新增
                    NotificationCenter.default.post(name: .init(schedulesRefreshNotificationName), object: nil)
                }else { //编辑
                    NotificationCenter.default.post(name: .init(scheduleDataUpdateNotificationName), object: schedule)
                }
            })
        }
        vc.backActionCallback = {[weak self] _ in
            guard let self = self else { return }
            self.back()
            if self.schedule == nil || delete { // 新增
                NotificationCenter.default.post(name: .init(schedulesRefreshNotificationName), object: nil)
            }else { //编辑
                NotificationCenter.default.post(name: .init(scheduleDataUpdateNotificationName), object: schedule)
            }
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    
    /// 更新保存/完成按钮状态
    private func updateBtnState() {
        saveBtn.isEnabled = scheduleAddView.isCompletion
        doneBtn.isEnabled = scheduleAddView.isCompletion
    }
    
    private func setupUI() {
    
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaTopHeight + SCRYFrom(56))
        }
        
        let bottomLineView = UIView()
        bottomLineView.backgroundColor = Line_Color
        bottomView.addSubview(bottomLineView)
        bottomLineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
        saveBtn = UIButton(title: "save".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(saveBtnAction))
        saveBtn.setTitleColor(Message_Color, for: .disabled)
        bottomView.addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(58))
        }
        
        lineView = UIView()
        lineView.isHidden = true
        lineView.backgroundColor = Line_Color
        bottomView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
            make.width.equalTo(SCRXFrom(1))
        }
        
        deleteBtn = UIButton(title: "DELETE".localizedString, titleSize: 16, titleWeight: .light, titleColor: Red_Color, target: self, action: #selector(deleteBtnAction))
        deleteBtn.isHidden = true
        bottomView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.right.equalTo(lineView.snp.left)
            make.centerY.height.equalTo(lineView)
        }
        
        doneBtn = UIButton(title: "save".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(doneBtnAction))
        doneBtn.setTitleColor(Message_Color, for: .disabled)
        doneBtn.isHidden = true
        bottomView.addSubview(doneBtn)
        doneBtn.snp.makeConstraints { make in
            make.left.equalTo(lineView.snp.right)
            make.right.equalToSuperview()
            make.centerY.height.equalTo(deleteBtn)
        }
        
        scheduleAddView = ScheduleAddView()
        scheduleAddView.delegate = self
        scheduleAddView.targetView.delegate = self
        view.addSubview(scheduleAddView)
        scheduleAddView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(bottomView.snp.top)
        }
        
    }
    
    /// 更新日程target数据
    private func updateScheduleTarget(_ target: ScheduleTarget) {
        
        var index: Int = 0
        switch target {
        case .devices:
            index = 0
        case .groups:
            index = 1
        case .scene:
            index = 2
        }
        var targets = scheduleAddView.targetView.targets
        targets.replaceSubrange(index...index, with: [target])
        scheduleAddView.targetView.targets = targets
        scheduleAddView.selectTarget = target
        
//        updateBtnState()
    }

}

extension ScheduleAddViewController: ScheduleAddViewDelegate {
    
    func view(_ view: ScheduleAddView, nameDidEditing name: String) -> String? {
        if name.count > 32 {
            return "text_length_exceeded".localizedString
        } else if MeshNetworkManager.instance.isScheduleTautonym(name: name) && self.schedule?.name != name { // 重名
            return "name_already_exists".localizedString
        }
        return nil
    }
    
    func view(_ view: ScheduleAddView, completionStateChanged completion: Bool) {
//        updateBtnState()
    }
}

extension ScheduleAddViewController: ScheduleAddTargetViewDelegate {
    
    func view(_ view: ScheduleAddTargetView, didClickTargetAction target: ScheduleTarget) {
        switch target {
        case .devices(let nodes):

            ScheduleDevicesView(nodes: MeshNetworkManager.instance.lightNodes, selectNodes: nodes, schedule: self.schedule, selectBack: {[weak self] selectNodes in
                self?.updateScheduleTarget(.devices(selectNodes))
            }).show()
            
        case .groups(let groups):
            
            ScheduleGroupsView(groups: MeshNetworkManager.instance.groups, selectGroups: groups, schedule: self.schedule) {[weak self] selectGroups in
                self?.updateScheduleTarget(.groups(selectGroups))
            }.show()
            
        case .scene(let scene):
            ScheduleScenesView(scenes: MeshNetworkManager.instance.scenes, selectScene: scene, schedule: self.schedule) {[weak self] selectScene in
                self?.updateScheduleTarget(.scene(selectScene))
            }.show()
        }
    }
    
    /// 点击同步失败提示回调
    func viewDidClickSyncFailedAction(_ view: ScheduleAddTargetView) {
        if let schedule = self.schedule {
            
            let vc = SyncDevicesViewController(type: .schedule(schedule), reSync: true)
            vc.syncSuccessCallback = {[weak self] _ in
                self?.navigationController?.popViewController(animated: true)
                self?.setupData()
                NotificationCenter.default.post(name: .init(scheduleDataUpdateNotificationName), object: schedule)
            }
            navigationController?.pushViewController(vc, animated: true)
        }
        
    }
    
}
