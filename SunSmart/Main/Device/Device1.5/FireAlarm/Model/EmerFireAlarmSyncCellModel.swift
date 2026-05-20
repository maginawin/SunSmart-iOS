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

class EmerFireAlarmSyncCellModel: NSObject {
    
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
    
    /// 操作是否成功
    var isSuccessful: Bool {
        
        switch self {
        case .delete(let node, let type):
            switch type {
            case .scene(let sceneId, _):
                return !node.sceneExecuteDatas.contains(where: { $0.sceneNumber == sceneId })
            case .schedule(let schedule):
                return node.schedulerActions[schedule.id] == nil || !node.schedulerActions[schedule.id]!.isValid
            case .group(let group):
                return node.group != group
            case .profile(let type):
                return type.isSuccessful(node: node)
            case .pirEnabled(let enabled):
                return node.pirEnabled == enabled
            case .enOceanSwitch(let switchData):
                if switchData.linkGroup != nil {
                    return node.getEnOceanUnSubscriptionMessageHandles(switchKeys: switchData.switchKeys).isEmpty
                }
                return true
            case .enOceanProxy(let switchData):
                // 动能开关代理
                if switchData.linkGroup != nil, node.primaryUnicastAddress == switchData.proxyNodeAddress {
                    // 清除代理
                    guard node.getEnOceanSwitchUnBindMessageHandles().isEmpty else {
                        return false
                    }
                }
                //                return switchData.proxyNode?.enOceanMacAddress == nil
                return switchData.deleteProxyNode == nil || switchData.deleteProxyNode?.enOceanMacAddress == nil
            case .deviceInitialize:
                return true
            case .deviceParameters(let parameterType):
                return parameterType.isSuccessful(node: node)
            case .deviceReadParmeters:
                return true
            case .collectionSchedule(let index, _):
                return node.collectionSchedulerEntrys[index] == nil || !node.collectionSchedulerEntrys[index]!.isValid
            case .proximityLightingEnabled:
                return true
            case .proximityLightingNeighbor:
                return true
            case .gatewaySIMAPN, .gatewayMQTTInformation, .gatewaySubnetAppkeyIndexs, .gatewayAssociationProjectId:
                return true
            case .deviceRouteList:
                return true
            case .gatewayAssociatedSpace:
                return true
            case .gatewayUnbindAssociatedSpace(let networkKey, let applicationKey, let activate):
                guard !node.knows(networkKey: networkKey) && !node.knows(applicationKey: applicationKey) && !node.subnetAppkeyBindModels.contains(where: { $0.isBoundTo(applicationKey) }) else {
                    return false
                }
                if activate {
                    if node.gatewayInfo?.subnetAppkeyIndexs.contains(applicationKey.index) ?? false {
                        return false
                    }
                }
                return true
            default:
                return true
            }
        case .configuration(let node, let type):
            switch type {
            case .scene(let sceneId, let sceneData):
                guard let sceneData = sceneData, let nodeScene = node.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneId }) else {
                    return false
                }
                guard nodeScene == sceneData else {
                    print("scene\(sceneData.sceneNumber) target: lightness \(sceneData.lightness) cct \(sceneData.cct)")
                    print("scene\(nodeScene.sceneNumber) real: lightness \(nodeScene.lightness) cct \(nodeScene.cct)")
                    return false
                }
                return true
            case .schedule(let schedule):
                return node.schedulerActions[schedule.id] != nil && node.schedulerActions[schedule.id]! == schedule.schedulerEntry
            case .group(let group):
                return node.group == group && node.getSubscribeToGroupMessages(group).count == 0
            case .profile(let type):
                return type.isSuccessful(node: node)
            case .pirEnabled(let enabled):
                return node.pirEnabled == enabled
            case .enOceanSwitch(let switchData):
                if switchData.linkGroup != nil {
                    return node.getEnOceanSubscriptionMessageHandles(switchKeys: switchData.switchKeys).isEmpty
                }
                return true
            case .enOceanProxy(let switchData):
                // 如果是动能开关代理并且已启用状态，则判断代理是否绑定按键成功
                if switchData.linkGroup != nil, node.primaryUnicastAddress == switchData.proxyNodeAddress, let macAddress = switchData.enOceanMacAddress, let key = switchData.enOceanSecurityKey {
                    let syncMessageHandles = node.getEnOceanSwitchBindMessageHandles(enOceanMacAddress: macAddress, securityKey: key, keyCount: switchData.maxKeyCount, enabled: switchData.enabled, switchKeys: switchData.switchKeys)
                    guard syncMessageHandles.isEmpty else {
                        return false
                    }
                }
                return true
            case .deviceInitialize:
                return node.isKeybindComplete
            case .deviceParameters(let parameterType):
                return parameterType.isSuccessful(node: node)
            case .deviceReadParmeters:
                return true
            case .collectionSchedule(let index, let entry):
                return node.collectionSchedulerEntrys[index] != nil && node.collectionSchedulerEntrys[index]! == entry
            case .proximityLightingEnabled(let enabled):
                return node.proximityLightingEnabled == enabled
            case .proximityLightingRelayNumber(let relayNumber):
                return node.proximityLightingRelayCount == relayNumber
            case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                return node.proximityLightingRelayCount == relayNumber && node.proximityLightingNeighborAddresses.sorted() == neighborAddresses.sorted()
            case .gatewaySIMAPN(let apn):
                return node.gatewayInfo?.simInfo?.apn == apn
            case .gatewayMQTTInformation(let mqttInformation):
                
                guard let mqttConnectInfo = node.gatewayInfo?.mqttConnectInfo else { return false }
                return mqttConnectInfo == mqttInformation
            case .gatewayAssociationProjectId(let projectId):
                return node.gatewayInfo?.projectId == projectId
            case .gatewaySubnetAppkeyIndexs(let appkeyIndexs):
                return node.gatewayInfo?.subnetAppkeyIndexs.sorted() == appkeyIndexs.sorted()
            case .gatewayAssociatedSpace(let networkKey, let applicationKey, let activate):
                guard node.knows(networkKey: networkKey) && node.knows(applicationKey: applicationKey) && !node.subnetAppkeyBindModels.contains(where: { !$0.isBoundTo(applicationKey) }) else {
                    return false
                }
                if activate {
                    if !(node.gatewayInfo?.subnetAppkeyIndexs.contains(applicationKey.index) ?? false) {
                        return false
                    }
                }
                return true
            case .gatewayUnbindAssociatedSpace(let networkKey, let applicationKey, let activate):
                guard !node.knows(networkKey: networkKey) && !node.knows(applicationKey: applicationKey) && !node.subnetAppkeyBindModels.contains(where: { $0.isBoundTo(applicationKey) }) else {
                    return false
                }
                if activate {
                    if node.gatewayInfo?.subnetAppkeyIndexs.contains(applicationKey.index) ?? false {
                        return false
                    }
                }
                return true
            case .deviceRouteList:
                return true
            case .autoSetRatedPower:
                return true
            }
        case .read(let node, let type):
            switch type {
            case .deviceParameters(let parameterType):
                switch parameterType {
                case .motionSensitivityRange:
                    return node.motionSensitivityRange != nil
                default:
                    return true
                }
            default:
                return true
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
                if let scene = node.scenes.first(where: { $0.number == sceneId }) {
                    messageHandles.append(contentsOf: scene.getDeleteMessageHandles(node: node))
                }
            case .schedule(let schedule):
                messageHandles.append(contentsOf: schedule.getMessageHandles(node: node, delete: true))
                
            case .profile(let type):
                
                messageHandles.append(contentsOf: type.getMessageHandles(node: node))
//                if let lightLCSetupModel = node.lightLCSetupModel {
//                    messageHandles.append(MeshMessageHandle(message: LightLCModeSet(false), model: lightLCSetupModel))
//                    messageHandles.append(MeshMessageHandle(message: LightLCOccupancyModeSet(false), model: lightLCSetupModel))
//                }
            case .pirEnabled(let enabled):
                messageHandles.append(contentsOf: NodeSyncData.pirEnabled(enabled).getMessageHandles(node: node))
            case .enOceanSwitch(let switchData):
                if switchData.linkGroup != nil {
                    messageHandles.append(contentsOf: node.getEnOceanUnSubscriptionMessageHandles(switchKeys: switchData.switchKeys))
                }
            case .enOceanProxy(let switchData):
//                node.primaryUnicastAddress == switchData.proxyNodeAddress ||
                if switchData.linkGroup != nil, node.primaryUnicastAddress == switchData.proxyNodeAddress || node.primaryUnicastAddress == switchData.deleteProxyNodeAddress {
                    messageHandles.append(contentsOf: node.getEnOceanSwitchUnBindMessageHandles())
                }
            case .deviceInitialize:
                break
            case .deviceParameters(let parameterType):
                messageHandles.append(contentsOf: parameterType.getMessageHandles(node: node))
            case .deviceReadParmeters:
                break
            case .collectionSchedule(let index, let entry):
                if let model = node.collectionSchedulerSetupModel {
                    messageHandles.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(index), entry: entry), model: model))
                }
            case .proximityLightingEnabled, .proximityLightingRelayNumber:
                break
            case .proximityLightingNeighbor:
                break
            case .gatewaySIMAPN, .gatewayMQTTInformation, .gatewayAssociationProjectId, .gatewaySubnetAppkeyIndexs:
                break
            case .deviceRouteList:
                break
            case .gatewayAssociatedSpace:
                break
            case .gatewayUnbindAssociatedSpace(let networkKey, let applicationKey, let activate):
                let associatedMessageHandles = NodeSyncData.gatewayUnbindAssociatedSpaces(datas: [(networkKey, applicationKey)], activate: activate).getMessageHandles(node: node)
                messageHandles.append(contentsOf: associatedMessageHandles)
            case .autoSetRatedPower:
                break
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
                
                if let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneId }), let data = executeData {
                    messageHandles.append(contentsOf: scene.getSyncMessageHandles(node: node, data: data))
                }
            case .schedule(let schedule):
                messageHandles.append(contentsOf: schedule.getMessageHandles(node: node))
            case .profile(let type):
                messageHandles.append(contentsOf: type.getMessageHandles(node: node))
            case .pirEnabled(let enabled):
                messageHandles.append(contentsOf: NodeSyncData.pirEnabled(enabled).getMessageHandles(node: node))
            case .enOceanSwitch(let switchData):
                if switchData.linkGroup != nil {
                    // 判断是否已订阅动能开关按键事件
                    messageHandles.append(contentsOf: node.getEnOceanSubscriptionMessageHandles(switchKeys: switchData.switchKeys))
                }
            case .enOceanProxy(let switchData):
                if switchData.linkGroup != nil, node.primaryUnicastAddress == switchData.proxyNodeAddress, let macAddress = switchData.enOceanMacAddress, let key = switchData.enOceanSecurityKey {
                    let handles = node.getEnOceanSwitchBindMessageHandles(enOceanMacAddress: macAddress, securityKey: key, keyCount: switchData.maxKeyCount, enabled: switchData.enabled, switchKeys: switchData.switchKeys)
                    messageHandles.append(contentsOf: handles)
                }
            case .deviceInitialize:
                if !node.isInitialize {
                    messageHandles.append(contentsOf: node.getInitializeMessageHandles())
                }else {
                    messageHandles.append(contentsOf: node.getConfigMessageHandles())
                }
            case .deviceParameters(let parameterType):
                messageHandles.append(contentsOf: parameterType.getMessageHandles(node: node))
            case .deviceReadParmeters:
                break
            case .collectionSchedule(let index, let entry):
                if let timeModel = node.timeModel {
                    messageHandles.append(MeshMessageHandle(message: Node.setLocalTimeMessage(), model: timeModel))
                }
                if let schedulerSetupModel = node.collectionSchedulerSetupModel {
                    messageHandles.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(index), entry: entry), model: schedulerSetupModel))
                }
            case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                if let vendorModel = node.sunricherVendorModel {
                    messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .proximityLightingNeighborSet(enabled: true, relay: relayNumber, ttl: 0, relayAppKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index, neighborAddresses: neighborAddresses)), model: vendorModel))
                }
            case .proximityLightingEnabled(let enabled):
                if let vendorModel = node.sunricherVendorModel {
                    messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .proximityLightingEnabled(enabled)), model: vendorModel))
                }
            case .proximityLightingRelayNumber(let relayNumber):
                if let vendorModel = node.sunricherVendorModel {
                    messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .proximityLightingRelaySet(relay: relayNumber)), model: vendorModel))
                }
            case .gatewaySIMAPN(let apn):
                messageHandles.append(contentsOf: NodeSyncData.syncGatewaySIMAPN(apn: apn).getMessageHandles(node: node))
            case .gatewayMQTTInformation(let mqttInformation):
                messageHandles.append(contentsOf: NodeSyncData.syncGatewayMQTTInformation(mqttInformation: mqttInformation).getMessageHandles(node: node))
            case .gatewayAssociationProjectId(let projectId):
                messageHandles.append(contentsOf: NodeSyncData.syncGatewayProjectId(projectId: projectId).getMessageHandles(node: node))
            case .gatewaySubnetAppkeyIndexs(let appkeyIndexs):
                messageHandles.append(contentsOf: NodeSyncData.syncGatewaySubnetAppkeyIndexs(appkeyIndexs: appkeyIndexs).getMessageHandles(node: node))
            case .gatewayAssociatedSpace(let networkKey, let applicationKey, let activate):
                let associatedMessageHandles = NodeSyncData.gatewayAssociatedSpaces(datas: [(networkKey, applicationKey)], activate: activate).getMessageHandles(node: node)
                messageHandles.append(contentsOf: associatedMessageHandles)
            case .gatewayUnbindAssociatedSpace(let networkKey, let applicationKey, let activate):
                let associatedMessageHandles = NodeSyncData.gatewayUnbindAssociatedSpaces(datas: [(networkKey, applicationKey)], activate: activate).getMessageHandles(node: node)
                messageHandles.append(contentsOf: associatedMessageHandles)
            case .deviceRouteList:
                break
            case .autoSetRatedPower:
                if let vendorModel = node.sunricherVendorModel, let pid = node.productIdentifier {
                    messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .ratedPower(pid: pid)), model: vendorModel))
                }
            }
        case .read(let node, let type):
            switch type {
            case .deviceReadParmeters(let parameterType):
                messageHandles.append(contentsOf: parameterType.getMessageHandles(node: node))
            case .deviceRouteList(let proxyAddress):
                if let vendorModel = node.sunricherVendorModel {
                    messageHandles.append(MeshMessageHandle(message: SunricherVendorGet(function: .routeTableGet(proxyAddress: proxyAddress)), model: vendorModel))
                }
            default:
                break
            }
        }
        return messageHandles
    }
    
    /// 设备删除操作
    case delete(node: Node, type: ActionType)
    /// 配置操作（添加/同步数据）
    case configuration(node: Node, type: ActionType)
    /// 读取数据
    case read(node: Node, type: ActionType)
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
    /// 设备pir启用/禁用
    case pirEnabled(_ enabled: Bool)
    /// 动能开关（关联）
    case enOceanSwitch(switchData: DeviceSwitchData)
    /// 动能开关代理
    case enOceanProxy(switchData: DeviceSwitchData)
    /// pwm周期
//    case pwmPeriod(period: UInt16)
    /// 设备初始化
    case deviceInitialize
    /// 设备参数
    case deviceParameters(parameterType: DeviceParameterType)
    /// 设备参数读取
    case deviceReadParmeters(parameterType: DeviceReadParameterType)
    /// 采集日程（Dongle）
    case collectionSchedule(index: Int, entry: SchedulerRegistryEntry)
    /// 设置邻近照明邻居数量+邻居list
    case proximityLightingNeighbor(relayNumber: UInt8, neighborAddresses: [Address])
    /// 启用/禁用邻近照明
    case proximityLightingEnabled(enabled: Bool)
    /// 设置邻近照明邻居数量
    case proximityLightingRelayNumber(relayNumber: UInt8)
    /// 网关关联项目id
    case gatewayAssociationProjectId(projectId: String)
    /// 同步网关子网appkey indexs
    case gatewaySubnetAppkeyIndexs(appkeyIndexs: [KeyIndex])
    /// 同步网关SIM卡APN
    case gatewaySIMAPN(apn: String)
    /// 同步网关MQTT参数
    case gatewayMQTTInformation(mqttInformation: GatewayInformation.MQTTConnectInformation)
    /// 网关关联space
    case gatewayAssociatedSpace(networkKey: NetworkKey, applicationKey: ApplicationKey, activate: Bool)
    /// 网关解除关联space
    case gatewayUnbindAssociatedSpace(networkKey: NetworkKey, applicationKey: ApplicationKey, activate: Bool)
    
    /// 设备路由list
    case deviceRouteList(proxyAddress: Address)
    /// 自动设置额定功率
    case autoSetRatedPower
}

extension NodeSyncData {
    
    /// 同步等级（越小表示优先级越高，0-6）
    var level: Int {
        switch self {
        case .subscribeGroup:
            return 1
        case .unsubscribeGroup:
            return 1
        case .profile, .pirEnabled:
            return 2
        case .syncScenes:
            return 3
        case .deleteScenes:
            return 3
        case .syncSchedules:
            return 4
        case .deleteSchedules:
            return 4
        case .syncSwitchProxy:
            return 5
        case .deleteSwitchProxy:
            return 5
        case .syncSwitchs:
            return 5
        case .deleteSwitchs:
            return 5
        case .deviceInitialize:
            return 0
        case .deviceParameterTypes:
            return 6
        case .syncCollectionSchedules:
            return 4
        case .deleteCollectionSchedules:
            return 4
        case .proximityLightingEnabled, .proximityLightingNeighbor, .proximityLightingRelayNumber:
            return 2
        case .addNetworkKey, .addApplicationkey, .removeNetworkKey, .removeApplicationkey:
            return 1
        case .gatewayAssociatedSpaces, .gatewayUnbindAssociatedSpaces:
            return 2
        case .syncGatewaySubnetAppkeyIndexs:
            return 2
        case .syncGatewayProjectId, .syncGatewaySIMAPN, .syncGatewayMQTTInformation:
            return 3
        }
    }
    
}

extension ProfileType {
    
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
        case .standbyLevel:
            return "profile_standby_level".localizedString
        case .standbyLux:
            return "profile_standby_lux".localizedString
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
        case .daylightCalibration:
            return "guidance_sensor_calibration".localizedString
        case .daylightCalibrateRate:
            return "calibration_ratio".localizedString
        case .daylightCalibrateInflectionPoint:
            return "calibration_light_point".localizedString
        case .sensitivity:
            return "sensitivity".localizedString
        case .lightControlSnapshoot:
            return "profile_snapshoot".localizedString
        case .lightControlSwitch, .daylightSensorConditionRecall:
            return "profile_switch".localizedString
        case .lightControlStore:
            return "profile_store".localizedString
        case .lightControlRestore:
            return "profile_restore".localizedString
        case .lightControlDelete:
            return "profile_scene_delete".localizedString
        case .profileDayToggleTriggerConditionLux:
            return "profile_day_threshold".localizedString
        case .profileNightToggleTriggerConditionLux:
            return "profile_night_threshold".localizedString
        case .profileToggleTriggerConditionLuxDelete(let id):
            return id == 0 ? "profile_night_threshol_delete".localizedString : "profile_day_threshold_delete".localizedString
        case .profileToggleTriggerConditionLuxLock:
            return "profile_lux_trigger_lock".localizedString
        case .profileToggleTriggerConditionLuxUnLock:
            return "profile_lux_trigger_unlock".localizedString
        }
    }
    
    /// 判断是否设置成功
    func isSuccessful(node: Node) -> Bool {
        switch self {
        case .sensorEnabled(let sensorModels, let publishAddress, _, let retransmit):
            return !sensorModels.contains(where: {
                !$0.isSensorServerPublicationConfigured(publishAddress: publishAddress, retransmit: retransmit)
            })
        case .sensorDisable(let sensorModels):
            return !sensorModels.contains(where: { $0.publish?.publicationAddress != nil })
        case .mode(let enabled):
            return node.lightLCProperty.mode == enabled
        case .occupancyMode(let enabled):
            return node.lightLCProperty.occupancyMode == enabled
        case .highLowEndTrim(let range):
            let lightnessRange = Node.getLightness100(lightness: node.lightnessRange.lowerBound)...Node.getLightness100(lightness: node.lightnessRange.upperBound)
            return lightnessRange == range
        case .occupancyLevel(let value):
            return node.lightLCProperty.lightnessOn == Node.getLightness(lightness100: value)
        case .occupancyLux(let lux):
            return node.lightLCProperty.luxLevelOn == UInt16(lux)
        case .vacantLevel(let value):
            return node.lightLCProperty.lightnessProlong == Node.getLightness(lightness100: value)
        case .vacantLux(let lux):
            return node.lightLCProperty.luxLevelProlong == UInt16(lux)
        case .standbyLevel(let value):
            return node.lightLCProperty.lightnessStandby == Node.getLightness(lightness100: value)
        case .standbyLux(let lux):
            return node.lightLCProperty.luxLevelStandby == UInt16(lux)
        case .lightAutoAdujustEnabled(let enabled):
            return node.lightLCProperty.lightAutoAdjustEnabled == enabled
        case .adjustSpeed(let speed):
            let data = Node.getLightRegulator(speed: speed)
            return node.lightLCProperty.regulatorKid == data.regulatorKid && node.lightLCProperty.regulatorKiu == data.regulatorKiu && node.lightLCProperty.regulatorKpd == data.regulatorKpd && node.lightLCProperty.regulatorKpu == data.regulatorKpu
        case .t1(let second):
           return node.lightLCProperty.timeFadeOn == UInt32(min(second * 1000, 0xFFFFFE))
        case .t2(let second):
            return node.lightLCProperty.timeRunOn == UInt32(min(second * 1000, 0xFFFFFE))
        case .t3(let second):
            return node.lightLCProperty.timeFade == UInt32(min(second * 1000, 0xFFFFFE))
        case .t4(let second):
            return node.lightLCProperty.timeProlong == UInt32(min(second * 1000, 0xFFFFFE))
        case .t5(let second):
            return node.lightLCProperty.timeFadeStandbyAuto == UInt32(min(second * 1000, 0xFFFFFE))
        case .manualOverrideTimeout(let enabled, let state, let second):
            return node.lightLCProperty.manualOverrideEnabled == enabled && node.lightLCProperty.manualOverrideTimeout == min(second != .max ? second * 1000 : second, UInt32.max) && node.lightLCProperty.manualControlState == state
        case .manualControl(let enabled):
            return node.lightLCProperty.manualControlMode == enabled
        case .powerOnState(let state, let cct):
            switch state {
            case .off:
                return node.powerUpState == .off
            case .restore:
                return node.powerUpState == .restore
            case .definedLightLevel(let level):
                return node.powerUpState == .default && node.defalutLightness == Node.getLightness(lightness100: Int(level)) && (cct == nil || cct != nil && cct == node.defaultCct)
            }
        case .daylightCalibration(let value):
            return node.daylightCalibrationValue == value
        case .sensitivity(let value, _):
            return node.motionSensitivity == value
        case .daylightCalibrateRate, .daylightCalibrateInflectionPoint:
            return true
        case .lightControlSnapshoot(let sceneNumber):
            return node.lightControlSnapshotSceneExecuteData != nil && node.lightControlSnapshotSceneExecuteData?.sceneNumber == sceneNumber
        case .lightControlSwitch, .daylightSensorConditionRecall:
            return true
        case .lightControlStore(let sceneNumber):
            return node.lightControlSceneExecuteDatas.contains(where: { $0.sceneNumber == sceneNumber })
        case .lightControlRestore:
            return true
        case .lightControlDelete(let sceneNumber):
            return !node.lightControlSceneExecuteDatas.contains(where: { $0.sceneNumber == sceneNumber })
        case .profileDayToggleTriggerConditionLux(let id, _, _, _, _, _):
            return node.lightControlLuxTriggerConditions.contains(where: { $0.index == id })
        case .profileNightToggleTriggerConditionLux(let id, _, _, _, _, _):
            return node.lightControlLuxTriggerConditions.contains(where: { $0.index == id })
        case .profileToggleTriggerConditionLuxDelete(let id):
            return !node.lightControlLuxTriggerConditions.contains(where: { $0.index == id })
        case .profileToggleTriggerConditionLuxLock, .profileToggleTriggerConditionLuxUnLock:
            return true
        }
    }
}

extension DeviceParameterType {
    
    /// 判断是否设置成功
    func isSuccessful(node: Node) -> Bool {
        switch self {
        case .pwmFrequency(let frequency):
            return node.pwmFrequency == frequency
        case .ratedPower(let list):
            return node.phaseEnergyConsumptions == list
        case .motionSensitivityRange(range: let range):
            return node.motionSensitivityRange == range
        case .defaultTransitionTime(let transitionTime):
            return node.defaultTransitionTime?.rawValue == transitionTime.rawValue
        case .powerCalibration(let calibrationValue):
            return node.calibrationRatedPower == calibrationValue
        case .absoluteCctRange(let range):
            return node.absoluteCctRange == range
        }
    }
    
}


class EmerFireAlarmSyncSectionModel {
    /// 标题
    var title: String
    /// 组list（场景、日程）
    var groups: [EmerFireAlarmSyncGroupModel] = []
    /// 设备list（组、日程（设备））
    var devices: [EmerFireAlarmSyncDeviceModel] = []
    /// 动能开关代理
    var switchProxy: EmerFireAlarmSyncSwitchProxyModel?
    
    init(title: String) {
        self.title = title
    }
    
    /// 所有相关model
    var allModels: [EmerFireAlarmSyncCellModel] {
        var models: [EmerFireAlarmSyncCellModel] = []
        if let model = switchProxy {
            models.append(model)
            models.append(model.deviceModel)
        }
        
        groups.forEach({
            models.append($0)
//            models.append(contentsOf: $0.deviceModels)
            
            $0.deviceModels.forEach({
                models.append($0)
                $0.steps.forEach({
                    models.append($0)
                    models.append(contentsOf: $0.tasks)
                })
//                models.append(contentsOf: $0.steps)
            })
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
    var rowModels: [EmerFireAlarmSyncCellModel] {
        var models: [EmerFireAlarmSyncCellModel] = []
        
        if let model = switchProxy {
            models.append(model)
            models.append(model.deviceModel)
        }
        
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

class EmerFireAlarmSyncSwitchProxyModel: EmerFireAlarmSyncCellModel {
    
    /// 图标名称
    var imageName: String = "switch_proxy"
    /// 名称
    var name: String
    /// 所属的section
    var parentSectionIndex: Int?
    /// 设置的设备
    let deviceModel: EmerFireAlarmSyncDeviceModel
    
    /// 状态
    override var state: SyncDevicesState {
        get {
            return deviceModel.state
        }set {
//            self.state = newValue
            super.state = newValue
        }
    }
    
    init(imageName: String = "switch_proxy", name: String, deviceModel: EmerFireAlarmSyncDeviceModel) {
        self.imageName = imageName
        self.name = name
        self.deviceModel = deviceModel
    }
    
}

class EmerFireAlarmSyncGroupModel: EmerFireAlarmSyncCellModel {
    
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
    let deviceModels: [EmerFireAlarmSyncDeviceModel]
    
    init(groupName: String, groupAddress: Address, deviceModels: [EmerFireAlarmSyncDeviceModel]) {
        self.name = groupName
        self.address = groupAddress
        self.deviceModels = deviceModels
    }
    
}

class EmerFireAlarmSyncDeviceModel: EmerFireAlarmSyncCellModel {
    
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
    var steps: [EmerFireAlarmSyncStepModel] = []
    /// 设备指定操作数据（场景、日程）
    var operationType: DeviceOperationType?
    /// 上级model（group）
    var parentGroupModel : EmerFireAlarmSyncGroupModel?
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
        default:
            break
        }
        return nil
    }
    
    
    init(name: String, address: Address) {
        self.name = name
        self.address = address
    }
}

class EmerFireAlarmSyncStepModel: EmerFireAlarmSyncCellModel {
    
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
            
            let existRelevance = notSetTasks.contains(where: { $0.relevanceTaskModels.count > 0 && $0.relevanceTaskModels.contains(where: { $0.state == .failed }) && !$0.relevanceTaskModels.contains(where: { $0.state == .inSettings }) })
            
            if (notSetTasks.count == 0 && inSetDevices.count == 0) || existRelevance { // 设置完成
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
    var tasks: [EmerFireAlarmSyncStepTaskModel] = []
    /// 上级model
    var parentDeviceModel: EmerFireAlarmSyncDeviceModel?
    /// 关联的进度model(如果关联model未成功则当前任务进入等待状态)
    var relevanceStepModels: [EmerFireAlarmSyncStepModel] = []
    /// 加载动画
    var loadingAnimation: CAAnimation?
    /// 是否显示进度（1/4）
    var showProgress: Bool = true
    
    
    init(type: String, state: SyncDevicesState, tasks: [EmerFireAlarmSyncStepTaskModel]) {
        self.type = type
        super.init()
        self.tasks = tasks
        self.state = state
    }
    
}

class EmerFireAlarmSyncStepTaskModel: EmerFireAlarmSyncCellModel {
    
    /// 任务名称
    let name: String
    /// 状态
//    var state: SyncDevicesState = .none
    /// 操作类型
    let operationType: DeviceOperationType
    /// 上级model
    var parentStepModel: EmerFireAlarmSyncStepModel?
    
    /// 关联的任务model(如果关联model未成功则当前任务进入等待状态)
    var relevanceTaskModels: [EmerFireAlarmSyncStepTaskModel] = []
    
    /// 失败次数
    var failedCount: Int = 0

    init(name: String, operationType: DeviceOperationType) {
        self.name = name
        self.operationType = operationType
    }
    
}
