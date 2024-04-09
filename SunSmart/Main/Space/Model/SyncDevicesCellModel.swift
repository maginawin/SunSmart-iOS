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
            case .profile:
                if let uuid = meshUUID {
                    node.saveNodeProfile(meshUUID: uuid)
                }
            case .enOceanSwitch:
                node.deleteEnOceanSwitch()
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
            case .profile:
                if let uuid = meshUUID {
                    node.saveNodeProfile(meshUUID: uuid)
                }
            case .enOceanSwitch:
                break
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
                    // 移动检测传感器退出组停止上报状态到组
//                if let presenceDetectedModel = node.presenceDetectedSensorModel, presenceDetectedModel.publish?.publicationAddress == group.address {
//                    let handle = MeshMessageHandle(message: ConfigModelPublicationSet(disablePublicationFor: presenceDetectedModel)!, address: node.primaryUnicastAddress)
//                    handle.continuous = false
//                    messageHandles.append(handle)
//                }
//                
//                // 光照传感器退出组停止上报状态到组
//                if let ambientLightModel = node.ambientLightSensorModel, ambientLightModel.publish?.publicationAddress == group.address {
//                    let handle = MeshMessageHandle(message: ConfigModelPublicationSet(disablePublicationFor: ambientLightModel)!, address: node.primaryUnicastAddress)
//                    handle.continuous = false
//                    messageHandles.append(handle)
//                }
                
            
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
            case .profile(let type):
                
                messageHandles.append(contentsOf: type.getMessageHandles(node: node))
//                if let lightLCSetupModel = node.lightLCSetupModel {
//                    messageHandles.append(MeshMessageHandle(message: LightLCModeSet(false), model: lightLCSetupModel))
//                    messageHandles.append(MeshMessageHandle(message: LightLCOccupancyModeSet(false), model: lightLCSetupModel))
//                }
            case .enOceanSwitch:
                if let group = node.group {
                    messageHandles.append(contentsOf: node.getEnOceanSwitchDisableMessageHandles(group: group, delete: true))
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
                
//                let profileType = group.info.profile.type
//                // 移动检测传感器加入组上报状态到组
//                if profileType == .occupancy_daylight || profileType == .occupancy || profileType == .vacancy_daylight || profileType == .vacancy {
//                    if let presenceDetectedModel = node.presenceDetectedSensorModel, presenceDetectedModel.publish?.publicationAddress != group.address {
//                        let message = ConfigModelPublicationSet(Publish(to: group.address, using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: .disabled, retransmit: .disabled), to: presenceDetectedModel)
//                        let handle = MeshMessageHandle(message: message!, address: node.primaryUnicastAddress)
//                        messageHandles.append(handle)
//                        
//                    }
//                }
                
            case .scene(let sceneId, let executeData):
                // 设备是否支持场景model及亮度model
                if let sceneSetupModel = node.sceneSetupModel, let lightnessModel = node.lightnessModel, let data = executeData {
                    // 设备是否支持色温model
                    let lightness = Node.getLightness(lightness100: data.lightness, range: node.lightnessRange)
                    if let ctlModel = node.ctlModel {
                        messageHandles.append(MeshMessageHandle(message: LightCTLSet(lightness: lightness, temperature: UInt16(data.cct), deltaUV: 0, transitionTime: .immediate, delay: 0), model: ctlModel))
                    }else { // 不支持则设置亮度
                        messageHandles.append(MeshMessageHandle(message: LightLightnessSet(lightness: lightness, transitionTime: .immediate, delay: 0), model: lightnessModel))
                    }
                    // 保存场景
                    messageHandles.append(MeshMessageHandle(message: SceneStore(sceneId), model: sceneSetupModel))
                    if let vendorModel = node.sunricherVendorModel {
                        // 保存场景前禁用灯光控制
//                        if node.lightLCProperty.lightControlEnabled {
                            messageHandles.insert(MeshMessageHandle(message: SunricherVendorSet(code: .lightControlEnabled, parameters: .lightControlEnabled(enabled: false)), model: vendorModel), at: 0)
//                        }
                        // 保存完场景开启灯光控制
//                        if !node.lightLCProperty.lightControlEnabled {
//                            messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(code: .lightControlEnabled, parameters: .lightControlEnabled(enabled: true)), model: vendorModel))
//                        }
                    }
                    
                }
            case .schedule(let schedule):
                // 设置时区
                if node.timezome == nil, let timeModel = node.timeModel {
                    messageHandles.append(MeshMessageHandle(message: Node.setLocalTimeMessage(), model: timeModel))
                }
                // 设置日程
                if let schedulerSetupModel = node.schedulerSetupModel {
                    let months: [Month] = schedule.enabled ? [.January,.February,.March,.April,.May,.June,.July,.August,.September,.October,.November,.December] : []
                    
                    messageHandles.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(schedule.id), entry: SchedulerRegistryEntry(year: .any(), month: .any(of: months), day: .any(), hour: .specific(hour: schedule.hour), minute: .specific(minute: schedule.minute), second: .specific(second: 0), dayOfWeek: .any(of: schedule.weekDays), action: schedule.action, transitionTime: .init(steps: UInt8(schedule.fadeTime), stepResolution: .seconds), sceneNumber: schedule.scene?.number ?? 0)), model: schedulerSetupModel))
                }
            case .profile(let type): 
                messageHandles.append(contentsOf: type.getMessageHandles(node: node))
            case .enOceanSwitch:
                break
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
    /// 配置
    case profile(type: ProfileType)
    /// 动能开关
    case enOceanSwitch
}

/// 配置类型
enum ProfileType {
    
    var title: String {
        switch self {
        case .mode:
            return "light_mode".localizedString
        case .occupancyMode:
            return "occupancy_mode".localizedString
        case .highLowEndTrim:
            return "profile_high_low_end_trim".localizedString
        case .occupancyLevel:
            return "profile_occupancy_level".localizedString
        case .occupancyLux:
            return "profile_occupancy_lux".localizedString
        case .vacantLevel:
            return "profile_vacancy_level".localizedString
        case .vacantLux:
            return "profile_vacancy_lux".localizedString
//        case .autoMinValue:
//            return "profile_auto_min_value".localizedString
        case .adjustSpeed:
            return "adjust_speed".localizedString
        case .t1:
            return "profile_t1".localizedString
        case .t2:
            return "profile_t2".localizedString
        case .t3:
            return "profile_t3".localizedString
        case .t4:
            return "profile_t4".localizedString
        case .t5:
            return "profile_t5".localizedString
        case .manualOverrideTimeout:
            return "manual_override_timeout".localizedString
        case .manualControl:
            return "profile_manual_control".localizedString
        case .powerOnState:
            return "power_up_behavior".localizedString
        case .lightAutoAdujustEnabled:
            return "light_auto_adujust_enabled".localizedString
        case .sensorEnabled:
            return "sensor_enabled".localizedString
        case .sensorDisable:
            return "sensor_disable".localizedString
        }
    }
    
    /// 根据profile类型获取对应消息发送对象
    func getMessageHandles(node: Node) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        
        if case .powerOnState(let state) = self { // 上电状态
            if let lightnessSetupModel = node.lightnessSetupModel, let powerUpModel = node.powerOnOffSetupModel {
                var onPowerUp: OnPowerUp = .restore
                switch state {
                case .off:
                    onPowerUp = .off
                case .restore:
                    onPowerUp = .restore
                case .definedLightLevel(let level):
                    onPowerUp = .default
                    let lightness = Node.getLightness(lightness100: level)
                    messageHandles.append(MeshMessageHandle(message: LightLightnessDefaultSet(lightness: lightness), model: lightnessSetupModel))
                }
                messageHandles.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: onPowerUp), model: powerUpModel))
            }
            return messageHandles
        }
        
        guard let lightLCModel = node.lightLCModel, let lightLCSetupModel = node.lightLCSetupModel else { return messageHandles }
        switch self {
        case .mode(let enabled):
            messageHandles.append(MeshMessageHandle(message: LightLCModeSet(enabled), model: lightLCModel))
        case .occupancyMode(let enabled):
            messageHandles.append(MeshMessageHandle(message: LightLCOccupancyModeSet(enabled), model: lightLCModel))
        case .highLowEndTrim(let range):
            let minLightness = max(Node.getLightness(lightness100: range.lowerBound), 1)
            let maxLightness = Node.getLightness(lightness100: range.upperBound)
            if let lightnessModel = node.lightnessModel {
                messageHandles.append(MeshMessageHandle(message: LightLightnessRangeSet(minLightness...maxLightness), model: lightnessModel))
            }
        case .occupancyLevel(let value):
            let lightness = Node.getLightness(lightness100: value)
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlLightnessOn, value: .perceivedLightness(lightness)), model: lightLCSetupModel))
        case .occupancyLux(let lux):
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlAmbientLuxLevelOn, value: .illuminance(Decimal(lux))), model: lightLCSetupModel))
        case .vacantLevel(let value):
            let lightness = Node.getLightness(lightness100: value)
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlLightnessProlong, value: .perceivedLightness(lightness)), model: lightLCSetupModel))
        case .vacantLux(let lux):
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlAmbientLuxLevelProlong, value: .illuminance(Decimal(lux))), model: lightLCSetupModel))
//        case .autoMinValue(let value):
//            if let vendorModel = node.sunricherVendorModel {
//                
//                let message = SunricherVendorSet(code: .lightAutoMinLevel, parameters: .lightAutoMinLevel(level: Node.getLightness(lightness100: value)))
//                messageHandles.append(MeshMessageHandle(message: message, model: vendorModel))
//            }
            
        case .adjustSpeed(let speed):
            
//            let range: ClosedRange<Int> = 0...1000
//            let accuracyRange: ClosedRange<Int> = 0...100
//            let value = Float(speed)
//            
//            let kid = 1 + Float(15) * Float(10) / 100.0
//            let kiu = 1 + Float(32) * Float(10) / 100.0
//            let kpd = Float(0)
//            let kpu = Float(1)
//            let accuracy = 5
            let data = Node.getLightRegulator(speed: speed)
            
            let kidMessage = LightLCPropertySet(of: .lightControlRegulatorKid, value: .coefficient(data.regulatorKid))
            let kiuMessage = LightLCPropertySet(of: .lightControlRegulatorKiu, value: .coefficient(data.regulatorKiu))
            let kpdMessage = LightLCPropertySet(of: .lightControlRegulatorKpd, value: .coefficient(data.regulatorKpd))
            let kpuMessage = LightLCPropertySet(of: .lightControlRegulatorKpu, value: .coefficient(data.regulatorKpu))
            let accuracyMessage = LightLCPropertySet(of: .lightControlRegulatorAccuracy, value: .percentage8(Decimal(data.regulatorAccuracy)))
            
            messageHandles.append(MeshMessageHandle(message: kidMessage, model: lightLCSetupModel))
            messageHandles.append(MeshMessageHandle(message: kiuMessage, model: lightLCSetupModel))
            messageHandles.append(MeshMessageHandle(message: kpdMessage, model: lightLCSetupModel))
            messageHandles.append(MeshMessageHandle(message: kpuMessage, model: lightLCSetupModel))
            messageHandles.append(MeshMessageHandle(message: accuracyMessage, model: lightLCSetupModel))
            
        case .t1(let second):
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlTimeFadeOn, value: .timeMillisecond24(UInt32(second * 1000))), model: lightLCSetupModel))
        case .t2(let second):
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlTimeRunOn, value: .timeMillisecond24(UInt32(min(second * 1000, 0xFFFFFF)))), model: lightLCSetupModel))
        case .t3(let second):
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlTimeFade, value: .timeMillisecond24(UInt32(second * 1000))), model: lightLCSetupModel))
        case .t4(let second):
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlTimeProlong, value: .timeMillisecond24(UInt32(min(second * 1000, 0xFFFFFF)))), model: lightLCSetupModel))
        case .t5(let second):
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlTimeFadeStandbyAuto, value: .timeMillisecond24(UInt32(second * 1000))), model: lightLCSetupModel))
        case .manualOverrideTimeout(let enabled, let second):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(code: .manualOverrideTimeout, parameters: .manualOverrideTimeout(enabled: enabled, state: .standby, interval: second)), model: vendorModel))
            }
        case .manualControl(let enabled):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(code: .manualControlEnabled, parameters: .manualControlEnabled(enabled: enabled)), model: vendorModel))
            }
            
        case .powerOnState:
            break
        case .lightAutoAdujustEnabled(let enabled):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(code: .lightAutoAdjustEnabled, parameters: .lightAutoAdjustEnabled(enabled: enabled)), model: vendorModel))
            }
        case .sensorEnabled(let sensorModels, let group):
            let models = sensorModels.filter({ $0.modelIdentifier == .sensorServerModelId })
            models.forEach({
                let message = ConfigModelPublicationSet(Publish(to: group.address, using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: .disabled, retransmit: .disabled), to: $0)!
                messageHandles.append(MeshMessageHandle(message: message, address: node.primaryUnicastAddress))
            })
      
        case .sensorDisable(let sensorModels):
            let models = sensorModels.filter({ $0.modelIdentifier == .sensorServerModelId })
            models.forEach({
                let message = ConfigModelPublicationSet(disablePublicationFor: $0)!
                messageHandles.append(MeshMessageHandle(message: message, address: node.primaryUnicastAddress))
            })
        }
        return messageHandles
    }
    
    /// 传感器启用（启用后才能与接收传感器状态）
    case sensorEnabled(sensorModels: [Model], group: Group)
    /// 禁用传感器状态发布（禁用发布传感器状态）
    case sensorDisable(sensorModels: [Model])
    /// 灯光控制模式是否打开
    case mode(enabled: Bool)
    /// 占用模式是否打开
    case occupancyMode(enabled: Bool)
    /// high / low end trim  0~100
    case highLowEndTrim(range: ClosedRange<Int>)
    /// 第一阶段亮度值  0~100%
    case occupancyLevel(value: Int)
    /// 第一阶段照度值 lux
    case occupancyLux(lux: Int)
    /// 第二阶段亮度值 0~100%
    case vacantLevel(value: Int)
    /// 第二阶段照度值 lux
    case vacantLux(lux: Int)
    /// 光照补偿是否开启
    case lightAutoAdujustEnabled(enabled: Bool)
    /// 光照补偿调节速率 0~100
    case adjustSpeed(speed: Int)
    /// 进入第一阶段时间（s）
    case t1(second: Int)
    /// 第一阶段持续时间（s）
    case t2(second: Int)
    /// 进入第二阶段时间（s）
    case t3(second: Int)
    /// 第二阶段持续时间（s）
    case t4(second: Int)
    /// 进入休眠阶段时间（s）
    case t5(second: Int)
    /// 手动控制后延迟时间（期间内保存控制后状态） enabled：是否开启  second： 0xFFFFFFFF无限长 默认60s
    case manualOverrideTimeout(enabled: Bool, second: UInt32 = 600)
    /// 是否手动控制后进入感应状态
    case manualControl(enabled: Bool)
    /// 上电状态
    case powerOnState(state: Profile.PowerUpState)
    
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
