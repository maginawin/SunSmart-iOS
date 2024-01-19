//
//  SyncDevicesCellModel.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/28.
//

import Foundation
import NordicSigMeshSDK

/// 状态
enum SyncDevicesState {
    /// 空
    case none
    /// 等待
    case wait
    /// 成功
    case successful
    /// 失败
    case failed
    /// 设置中
    case inSettings
    /// 重复失败
//    case repeatedFailure
}

class SyncCellModel: NSObject {
    
    /// 图标
//    var imageName: String? { get set }
    /// 名称
//    var name: String? { get set }
    /// 地址（设备、组）
//    var address: Address? { get set }
    /// 是否完成整个同步操作
    var isFineshed: Bool = false
    /// 状态
    var state: SyncDevicesState = .none
}

/// 操作类型
enum DeviceOperationType {
    
    /// 完成操作处理
    func finneshHandle() {
        let meshUUID = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString
        switch self {
        case .delete(let node, let type):
            switch type {
            case .group(let group): // 节点退出组
                node.unsubscribe(from: group)
            case .scene(let sceneId, _): // 删除场景
                if let scene = MeshNetworkManager.instance.meshNetwork?.scenes.first(where: { $0.number == sceneId }) {
                    scene.remove(node: node)
                    node.sceneDatas.removeValue(forKey: sceneId)
                    if let uuid = meshUUID {
                        SceneExecuteData.deleteData(meshUUID: uuid, address: node.primaryUnicastAddress, sceneId: Int(sceneId))
                    }
                    // 组对应场景数据是否待删除
                    if let group = node.group, let groupSceneData = group.info.bindSceneDatas[sceneId], groupSceneData.state == .waitDelete {
                        // 组内设备已删除对应场景缓存
                        if !group.nodes.contains(where: { $0.sceneDatas[sceneId] != nil }) {
                            group.info.bindSceneDatas.removeValue(forKey: sceneId)
                            // 设备加入组，组加入场景，场景加入日程 Node->Group->Scene->Schedule
                            // 场景加入日程后关联场景的组也加入日程，场景移出组后吧组间接关联的日程删除
                            group.info.bindSchedules.removeAll(where: { groupSchedule in scene.info.bindSchedules.contains(where: { $0.id == groupSchedule.id }) })
                            if let uuid = meshUUID { // 删除组对应的场景数据缓存
                                scene.info.groups.removeAll(where: { $0.address.address == group.address.address })
                                SceneExecuteData.deleteData(meshUUID: uuid, address: group.address.address, sceneId: Int(sceneId))
                            }
                        }
                    }
                }
            case .schedule(let schedule): // 删除日程
                node.scheduleDatas.removeValue(forKey: schedule.id)
                node.scheduleIds.removeAll(where: { $0 == schedule.id })
                if let uuid = meshUUID {
                    Node.deleteSchedule(meshUUID: uuid, address: node.primaryUnicastAddress, scheduleId: schedule.id)
                    
                    var isSaveSchedule = false
                    // 判断组是否因为此设备而无法从日程中删除，设备删除后组也从日程中删除
                    if let group = schedule.needDeleteGroups.first(where: { $0.nodes.contains(node) }), !group.nodes.contains(where: { $0.scheduleDatas[schedule.id] != nil }) {
                        schedule.needDeleteGroups.removeAll(where: { $0.address.address == group.address.address })
                        
                        isSaveSchedule = true
                    }
                    // 判断场景是否因为此设备无法从日程中删除，设备删除后场景也从日程中删除
                    if let scene = schedule.needDeleteScenes.first(where: { $0.info.groups.contains(where: { $0.nodes.contains(node) }) }), !scene.info.groups.contains(where: { $0.nodes.contains(where: { $0.scheduleDatas[schedule.id] != nil }) }) {
                        schedule.needDeleteScenes.removeAll(where: { $0.number == scene.number })
                        
                        isSaveSchedule = true
                    }
                    if schedule.needDeleteNodes.contains(node) {
                        schedule.needDeleteNodes.removeAll(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress })
                        isSaveSchedule = true
                    }
                    
                    if isSaveSchedule {
                        schedule.save(meshUUID: uuid)
                    }
                }
             
            }
        case .configuration(let node, let type):
            switch type {
            case .group(let group): // 节点加入组
                node.subscribe(to: group)
            case .scene(let sceneId, let executeData): // 添加/同步场景
                if let scene = MeshNetworkManager.instance.meshNetwork?.scenes.first(where: { $0.number == sceneId }) {
                    scene.add(address: node.primaryUnicastAddress)
                    node.sceneDatas.updateValue(executeData!, forKey: sceneId)
                    if let uuid = meshUUID {
                        SceneExecuteData.save(meshUUID: uuid, address: node.primaryUnicastAddress, sceneId: Int(sceneId), sceneData: executeData!)
                    }
                }
            case .schedule(let schedule): // 添加日程
                node.scheduleDatas.updateValue(schedule.schedulerEntry, forKey: schedule.id)
                node.scheduleIds.append(schedule.id)
                if let uuid = meshUUID {
                    Node.saveSchedule(meshUUID: uuid, address: node.primaryUnicastAddress, scheduleId: schedule.id, entry: schedule.schedulerEntry)
                }
            }
        }
        
    }
    
    
    /// 对应操作需要发送的消息处理
    var messageHandles: [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        switch self {
        case .delete(let node, let type): // 删除操作
            
            switch type {
            case .group(let group):
                // 设备退出组
                node.getUnsubscribeGroupMessages(group).forEach({
                    let handle = MeshMessageHandle(message: $0, address: node.primaryUnicastAddress)
                    handle.continuous = false
                    messageHandles.append(handle)
                })
            case .scene(let sceneId, _):
                // 设备是否支持场景model
                if let sceneSetupModel = node.sceneSetupModel {
                    // 删除场景
                    messageHandles.append(MeshMessageHandle(message: SceneDelete(sceneId), model: sceneSetupModel))
                }
            case .schedule(let schedule):
                if let schedulerSetupModel = node.schedulerSetupModel {
                    // 删除日程，协议不支持删除，将对应id的日程设置为无效数据
                    messageHandles.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(schedule.id), entry: SchedulerRegistryEntry()), model: schedulerSetupModel))
                }
            }
        case .configuration(let node, let type): // 添加/配置操作
            
            switch type {
            case .group(let group):
                // 设备加入组
                node.getSubscribeToGroupMessages(group).forEach({
                    let handle = MeshMessageHandle(message: $0, address: node.primaryUnicastAddress)
                    handle.continuous = false
                    messageHandles.append(handle)
                })
            case .scene(let sceneId, let executeData):
                // 设备是否支持场景model及亮度model
                if let sceneSetupModel = node.sceneSetupModel, let lightnessModel = node.lightnessModel, let data = executeData {
                    // 设备是否支持色温model
                    let lightness = Node.getLightness(lightness100: data.lightness)
                    if let ctlModel = node.ctlModel {
                        messageHandles.append(MeshMessageHandle(message: LightCTLSet(lightness: lightness, temperature: UInt16(data.cct), deltaUV: 0), model: ctlModel))
                    }else { // 不支持则设置亮度
                        messageHandles.append(MeshMessageHandle(message: LightLightnessSet(lightness: lightness), model: lightnessModel))
                    }
                    // 保存场景
                    messageHandles.append(MeshMessageHandle(message: SceneStore(sceneId), model: sceneSetupModel))
                }
            case .schedule(let schedule):
                // 设置时区
                if node.timezome == nil, let timeModel = node.timeModel {
                    messageHandles.append(MeshMessageHandle(message: Node.setLocalTimeMessage(), model: timeModel))
                }
                // 设置日程
                if let schedulerSetupModel = node.schedulerSetupModel {
                    messageHandles.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(schedule.id), entry: SchedulerRegistryEntry(year: .any(), month: .any(of: [.January,.February,.March,.April,.May,.June,.July,.August,.September,.October,.November,.December]), day: .any(), hour: .specific(hour: schedule.hour), minute: .specific(minute: schedule.minute), second: .specific(second: 0), dayOfWeek: .any(of: schedule.weekDays), action: schedule.action, transitionTime: .init(steps: UInt8(schedule.fadeTime), stepResolution: .seconds), sceneNumber: schedule.scene?.number ?? 0)), model: schedulerSetupModel))
                }
            }
        }
        return messageHandles
    }
    
    /// 设备删除操作
    case delete(node: Node, type: ActionType)
    /// 配置操作（添加/同步数据）
    case configuration(node: Node, type: ActionType)
}

/// 事件类型
enum ActionType {
    /// 场景
    case scene(sceneId: SceneNumber, executeData: SceneExecuteData?)
    /// 日程
    case schedule(schedule: Schedule)
    /// 组
    case group(group: Group)
}

class SyncDevicesSectionModel {
    /// 标题
    var title: String
    /// 组list（场景、日程）
    var groups: [SyncDevicesGroupModel] = []
    /// 设备list（组、日程（设备））
    var devices: [SyncDevicesModel] = []
    
    init(title: String) {
        self.title = title
    }
    
    /// 所有相关model
    var allModels: [SyncCellModel] {
        var models: [SyncCellModel] = []
        groups.forEach({
            models.append($0)
            models.append(contentsOf: $0.deviceModels)
//            $0.deviceModels.forEach({
//                models.append(contentsOf: $0.steps)
//            })
        })
        
        devices.forEach({
            models.append($0)
            $0.steps.forEach({
                models.append($0)
                models.append(contentsOf: $0.tasks)
            })
        })
        return models
    }
    
    /// 一级列表结构model（用于列表展示）
    var rowModels: [SyncCellModel] {
        var models: [SyncCellModel] = []
        groups.forEach({
            models.append($0)
            if $0.isShow {
                $0.deviceModels.forEach({ device in
                    models.append(device)
                    if device.isShow {
                        models.append(contentsOf: device.steps)
                    }
                })
            }
        })
        devices.forEach({
            models.append($0)
            if $0.isShow {
                models.append(contentsOf: $0.steps)
            }
        })
        return models
    }
    
}

class SyncDevicesGroupModel: SyncCellModel {
    
    /// 图标名称
    var imageName: String = "space_device_count"
    /// 组名称
    let name: String
    /// 组地址
    let address: Address
    /// 是否展示选择
//    var showSelect: Bool = false
    /// 所属的section
    var parentSectionIndex: Int?
    
    /// 是否选中
    var isSelected: Bool = false
    /// 状态
    override var state: SyncDevicesState {
        get {
            let notSetDevices = deviceModels.filter({ $0.state == .none || $0.state == .wait })
            let inSetDevices = deviceModels.filter({ $0.state == .inSettings })
            if notSetDevices.count == 0 && inSetDevices.count == 0 { // 设置完成
                return deviceModels.contains(where: { $0.state == .failed }) ? .failed : .successful
            }else if notSetDevices.count == deviceModels.count { // 未开始
                return .wait
            }else if notSetDevices.count < deviceModels.count { // 进行中
                return .inSettings
            }
            return .none
//                .successful
        }set {
//            self.state = newValue
            super.state = newValue
        }
    }
    /// 是否展开
    var isShow: Bool = false
    /// 节点list
//    let nodes: [Node]
    /// 组下面的设备model list
    let deviceModels: [SyncDevicesModel]
    
    init(groupName: String, groupAddress: Address, deviceModels: [SyncDevicesModel]) {
        self.name = groupName
        self.address = groupAddress
        self.deviceModels = deviceModels
    }
    
}

class SyncDevicesModel: SyncCellModel {
    
//    /// 状态
//    enum State {
//        /// 空
//        case none
//        /// 等待
////        case wait
//        /// 设置中
//        case inSettings
//        /// 成功
//        case successful
//        /// 失败
//        case failure
//        /// 重复失败
//        case repeatedFailure
//    }
//    
    /// 图标名称
    var imageName: String = "device_light"
    /// 设备名称
    let name: String
    /// 设备地址
    let address: Address
    /// 失败次数
    var failedCount: Int = 0
    
    /// 是否展示选择
//    var showSelect: Bool = false
    /// 是否选中
    var isSelected: Bool = false
    /// 状态
    override var state: SyncDevicesState {
        get {
            if steps.count > 0 {
                let notSetSteps = steps.filter({ $0.state == .none || $0.state == .wait })
                let inSetDevices = steps.filter({ $0.state == .inSettings })
                let existRelevance = notSetSteps.contains(where: { $0.relevanceStepModels.count > 0 && $0.relevanceStepModels.contains(where: { $0.state == .failed }) && !$0.relevanceStepModels.contains(where: { $0.state == .inSettings }) })
                if (notSetSteps.count == 0 && inSetDevices.count == 0) || existRelevance { // 设置完成
                    return steps.contains(where: { $0.state == .failed }) ? .failed : .successful
                }else if notSetSteps.count == steps.count { // 未开始
                    return .wait
                }else if notSetSteps.count < steps.count { // 进行中
                    return .inSettings
                }
                return .none
            }
            return super.state
        }set {
            super.state = newValue
//            self.state = newValue
        }
    }
    /// 是否可以展开
//    var canShowSteps: Bool = false
    /// 是否展开
    var isShow: Bool = false
    /// 操作步骤(group操作)
    var steps: [SyncDeviceStepModel] = []
    /// 设备指定操作数据（场景、日程）
    var operationType: DeviceOperationType?
    /// 上级model（group）
    var parentGroupModel : SyncDevicesGroupModel?
    /// 所属的section
    var parentSectionIndex: Int?
    
    /// 所属group
    var group: Group? {
        guard let operationType = operationType else {
            return nil
        }
        switch operationType {
        case .configuration(_, let type):
            switch type {
            case .group(let group):
                return group
            default:
                break
            }
        case .delete(_, let type):
            switch type {
            case .group(let group):
                return group
            default:
                break
            }
        }
        return nil
    }
    
    
    init(name: String, address: Address) {
        self.name = name
        self.address = address
    }
}

class SyncDeviceStepModel: SyncCellModel {
    
    /// 当前进度
    var current: Int {
        return tasks.filter({ $0.state == .successful }).count
    }
    /// 总进度
    var count: Int {
        return tasks.count
    }
    /// 数据类型
    let type: String
    /// 状态
    override var state: SyncDevicesState {
        get {
            let notSetTasks = tasks.filter({ $0.state == .none || $0.state == .wait })
            let inSetDevices = tasks.filter({ $0.state == .inSettings })
            if notSetTasks.count == 0 && inSetDevices.count == 0 { // 设置完成
                return tasks.contains(where: { $0.state == .failed }) ? .failed : .successful
            }else if notSetTasks.count == tasks.count || inSetDevices.count == 0 { // 未开始
                return .wait
            }else if notSetTasks.count < tasks.count && inSetDevices.count > 0 { // 进行中
                return .inSettings
            }
            return .none
        }set {
            super.state = newValue
        }
    }
    /// 任务list
    let tasks: [SyncDeviceStepTaskModel]
    /// 上级model
    var parentDeviceModel: SyncDevicesModel?
    /// 关联的进度model(如果关联model未成功则当前任务进入等待状态)
    var relevanceStepModels: [SyncDeviceStepModel] = []
    /// 加载动画
    var loadingAnimation: CAAnimation?
    /// 是否显示进度（1/4）
    var showProgress: Bool = true
    
    
    init(type: String, state: SyncDevicesState, tasks: [SyncDeviceStepTaskModel]) {
        self.type = type
        self.tasks = tasks
        super.init()
        self.state = state
    }
    
}

class SyncDeviceStepTaskModel: SyncCellModel {
    
    /// 任务名称
    let name: String
    /// 状态
//    var state: SyncDevicesState = .none
    /// 操作类型
    let operationType: DeviceOperationType
    /// 上级model
    var parentStepModel: SyncDeviceStepModel?
    
    /// 失败次数
    var failedCount: Int = 0

    init(name: String, operationType: DeviceOperationType) {
        self.name = name
        self.operationType = operationType
    }
    
}
