//
//  Node+MessageHandles.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/2.
//

import Foundation
import NordicSigMeshSDK

extension Scene {
    
    /// 获取场景同步消息数据
    /// - Parameters:
    ///   - node: 设备
    ///   - data: 场景执行数据
    /// - Returns: 消息list
    func getSyncMessageHandles(node: Node, data: SceneExecuteData) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        // 设备是否支持场景model及亮度model
        if let sceneSetupModel = node.sceneSetupModel, let lightnessModel = node.lightnessModel {
            // 设备是否支持色温model
            let lightness = data.lightness
            //Node.getLightness(lightness100: data.lightness, range: node.lightnessRange)
            if let ctlModel = node.ctlModel, node.temperatureModel != nil {
                messageHandles.append(MeshMessageHandle(message: LightCTLSet(lightness: lightness, temperature: UInt16(data.cct), deltaUV: 0, transitionTime: .immediate, delay: 0), model: ctlModel))
            }else { // 不支持则设置亮度
                messageHandles.append(MeshMessageHandle(message: LightLightnessSet(lightness: lightness, transitionTime: .immediate, delay: 0), model: lightnessModel))
            }
            // 保存场景
            messageHandles.append(MeshMessageHandle(message: SceneStore(self.number), model: sceneSetupModel))
            if let vendorModel = node.sunricherVendorModel, node.lightLCModel != nil {
                // 保存场景前禁用灯光控制
                messageHandles.insert(MeshMessageHandle(message: SunricherVendorSet(function: .lightControlEnabled(enabled: false)), model: vendorModel), at: 0)
            }
        }
        return messageHandles
    }
    
    /// 获取场景删除消息数据
    /// - Parameters:
    ///   - node: 设备
    ///   - data: 场景执行数据
    /// - Returns: 消息list
    func getDeleteMessageHandles(node: Node) -> [MeshMessageHandle] {
        guard let sceneSetupModel = node.sceneSetupModel else { return [] }
        // 删除场景
        return [MeshMessageHandle(message: SceneDelete(self.number), model: sceneSetupModel)]
    }
    
}

extension NodeSyncData {
    
    /// 根据同步数据获取需要发送的mesh消息list
    func getMessageHandles(node: Node) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        switch self {
        case .addNetworkKey(let networkKey):
            messageHandles.append(MeshMessageHandle(message: ConfigNetKeyAdd(networkKey: networkKey), address: node.primaryUnicastAddress))
        case .removeNetworkKey(let networkKey):
            messageHandles.append(MeshMessageHandle(message: ConfigNetKeyDelete(networkKey: networkKey), address: node.primaryUnicastAddress))
        case .addApplicationkey(let applicationKey):
            messageHandles.append(MeshMessageHandle(message: ConfigAppKeyAdd(applicationKey: applicationKey), address: node.primaryUnicastAddress))
        case .removeApplicationkey(let applicationKey):
            messageHandles.append(MeshMessageHandle(message: ConfigAppKeyDelete(applicationKey: applicationKey), address: node.primaryUnicastAddress))
        case .subscribeGroup(let group):
            node.getSubscribeToGroupMessages(group).forEach({
                let handle = MeshMessageHandle(message: $0, address: node.primaryUnicastAddress)
                handle.continuous = false
                messageHandles.append(handle)
            })
        case .unsubscribeGroup(let group):
            node.getUnsubscribeGroupMessages(group).forEach({
                let handle = MeshMessageHandle(message: $0, address: node.primaryUnicastAddress)
                handle.continuous = false
                messageHandles.append(handle)
            })
        case .profile(let types):
            types.forEach({
                messageHandles.append(contentsOf: $0.getMessageHandles(node: node))
            })
        case .syncScenes(let datas):
            datas.forEach { (scene: Scene, data: SceneExecuteData) in
                messageHandles.append(contentsOf: scene.getSyncMessageHandles(node: node, data: data))
            }
        case .deleteScenes(let scenes):
            scenes.forEach({
                messageHandles.append(contentsOf: $0.getDeleteMessageHandles(node: node))
            })
        case .syncSchedules(let schedules):
            schedules.forEach({
                messageHandles.append(contentsOf: $0.getMessageHandles(node: node))
            })
        case .deleteSchedules(let schedules):
            schedules.forEach({
                messageHandles.append(contentsOf: $0.getMessageHandles(node: node, delete: true))
            })
        case .syncSwitchProxy(let switchData):
            if switchData.linkGroup != nil, node.primaryUnicastAddress == switchData.proxyNodeAddress, let macAddress = switchData.enOceanMacAddress, let key = switchData.enOceanSecurityKey {
                let handles = node.getEnOceanSwitchBindMessageHandles(enOceanMacAddress: macAddress, securityKey: key, enabled: switchData.enabled, switchKeys: switchData.switchKeys)
                messageHandles.append(contentsOf: handles)
            }
        case .deleteSwitchProxy(let switchData):
            if switchData.linkGroup != nil, node.primaryUnicastAddress == switchData.proxyNodeAddress || node.primaryUnicastAddress == switchData.deleteProxyNodeAddress {
                messageHandles.append(contentsOf: node.getEnOceanSwitchUnBindMessageHandles())
            }
        case .syncSwitchs(let switchDatas):
            switchDatas.forEach { switchData in
                if switchData.linkGroup != nil {
                    // 判断是否已订阅动能开关按键事件
                    messageHandles.append(contentsOf: node.getEnOceanSubscriptionMessageHandles(switchKeys: switchData.switchKeys))
                }
            }
        case .deleteSwitchs(let switchDatas):
            switchDatas.forEach { switchData in
                if switchData.linkGroup != nil {
                    messageHandles.append(contentsOf: node.getEnOceanUnSubscriptionMessageHandles(switchKeys: switchData.switchKeys))
                }
            }
        case .deviceInitialize:
            if !node.isInitialize {
                messageHandles.append(contentsOf: node.getInitializeMessageHandles())
            }else {
                messageHandles.append(contentsOf: node.getConfigMessageHandles())
            }
        case .deviceParameterTypes(let types):
            types.forEach({
                messageHandles.append(contentsOf: $0.getMessageHandles(node: node))
            })
        case .syncCollectionSchedules(let schedules):
            if let timeModel = node.timeModel {
                messageHandles.append(MeshMessageHandle(message: Node.setLocalTimeMessage(), model: timeModel))
            }
            if let schedulerSetupModel = node.collectionSchedulerSetupModel {
                schedules.forEach { (index, entry) in
                    messageHandles.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(index), entry: entry), model: schedulerSetupModel))
                }
            }
        case .deleteCollectionSchedules(let scheduleIds):
            if let model = node.collectionSchedulerSetupModel {
                scheduleIds.forEach { index in
                    messageHandles.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(index), entry: .init()), model: model))
                }
            }
        case .proximityLightingEnabled(let enabled):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .proximityLightingEnabled(enabled)), model: vendorModel))
            }
        case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .proximityLightingNeighborSet(enabled: true, relay: relayNumber, ttl: 0, relayAppKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index, neighborAddresses: neighborAddresses)), model: vendorModel))
            }
        case .syncGatewayProjectId(let projectId):
            if let mac = node.gatewayModel?.mac, let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .gatewayProjectRelevance(gatewayId: mac, projectId: projectId)), model: vendorModel))
            }
        case .syncGatewaySubnetAppkeyIndexs(let appkeyIndexs):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .gatewaySubnetsRelevanceSet(subnetAppkeyIndexs: appkeyIndexs)), model: vendorModel))
            }
        case .syncGatewaySIMAPN(let apn):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .gatewaySimInfoSet(simInfo: .init(customId: customId, ipType: .ip, apn: apn))), model: vendorModel))
            }
        case .syncGatewayMQTTInformation(let mqttInformation):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .gatewayMQTTConnectInfoSet(connectInfo: mqttInformation)), model: vendorModel))
            }
        }
        return messageHandles
    }
}

extension Schedule {
    
    /// 获取对应消息数据
    /// - Parameters:
    ///   - node: 设备
    ///   - delete: 是否删除
    /// - Returns: 消息list
    func getMessageHandles(node: Node, delete: Bool = false) -> [MeshMessageHandle] {
        guard let schedulerSetupModel = node.schedulerSetupModel else {
            return []
        }
        var messageHandles: [MeshMessageHandle] = []
        if delete {
            
            let message = SchedulerActionSet(index: UInt8(self.id), entry: SchedulerRegistryEntry())
            // Auto
            if self.action == .turnOn, node.group != nil, let lightLCSchedulerSetupModel = node.lightLCSchedulerSetupModel {
                messageHandles.append(MeshMessageHandle(message: message, model: lightLCSchedulerSetupModel))
            }else {
                // 删除日程，协议不支持删除，将对应id的日程设置为无效数据
                messageHandles.append(MeshMessageHandle(message: message, model: schedulerSetupModel))
            }
        }else {
            // 设置时区
            if self.enabled, let timeModel = node.timeModel {
                messageHandles.append(MeshMessageHandle(message: Node.setLocalTimeMessage(), model: timeModel))
            }
            // 设置日程
            let message = SchedulerActionSet(index: UInt8(self.id), entry: self.schedulerEntry)
            
            // Auto
            if self.action == .turnOn, node.group != nil, let lightLCSchedulerSetupModel = node.lightLCSchedulerSetupModel {
                messageHandles.append(MeshMessageHandle(message: message, model: lightLCSchedulerSetupModel))
            }else {
                messageHandles.append(MeshMessageHandle(message: message, model: schedulerSetupModel))
            }
        }
        
        return messageHandles
    }
    
}

extension ProfileType {
    
    /// 根据profile类型获取对应消息发送对象
    func getMessageHandles(node: Node) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        
        if case .powerOnState(let state, let cct) = self { // 上电状态
            if let lightnessSetupModel = node.lightnessSetupModel, let powerUpModel = node.powerOnOffSetupModel {
                var onPowerUp: OnPowerUp = .restore
                switch state {
                case .off:
                    onPowerUp = .off
                case .restore:
                    onPowerUp = .restore
                case .definedLightLevel(let level):
                    onPowerUp = .default
                    let lightness = Node.getLightness(lightness100: Int(level))
                    if let defaultCct = cct, let ctlSetupModel = node.ctlSetupModel {
                        messageHandles.append(MeshMessageHandle(message: LightCTLDefaultSet(lightness: lightness, temperature: defaultCct, deltaUV: 0), model: ctlSetupModel))
                    }else {
                        messageHandles.append(MeshMessageHandle(message: LightLightnessDefaultSet(lightness: lightness), model: lightnessSetupModel))
                    }
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
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlTimeRunOn, value: .timeMillisecond24(UInt32(min(second * 1000, 0xFFFFFE)))), model: lightLCSetupModel))
        case .t3(let second):
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlTimeFade, value: .timeMillisecond24(UInt32(second * 1000))), model: lightLCSetupModel))
        case .t4(let second):
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlTimeProlong, value: .timeMillisecond24(UInt32(min(second * 1000, 0xFFFFFE)))), model: lightLCSetupModel))
        case .t5(let second):
            messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlTimeFadeStandbyAuto, value: .timeMillisecond24(UInt32(second * 1000))), model: lightLCSetupModel))
        case .manualOverrideTimeout(let enabled, let second):
            if let vendorModel = node.sunricherVendorModel {
                var interval = second
                if second < UInt32.max {
                    interval = min(interval * 1000, UInt32.max)
                }
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .manualOverrideTimeout(enabled: enabled, state: .standby, interval: interval)), model: vendorModel))
            }
        case .manualControl(let enabled):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .manualControlEnabled(enabled: enabled)), model: vendorModel))
            }
            
        case .powerOnState:
            break
        case .lightAutoAdujustEnabled(let enabled):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .lightAutoAdjustEnabled(enabled: enabled)), model: vendorModel))
            }
        case .sensorEnabled(let sensorModels, let publishAddress, let delay):
            let models = sensorModels.filter({ $0.modelIdentifier == .sensorServerModelId })
            
            var period: Publish.Period = .disabled
            if delay > 0 {
                period = .init(delay)
            }
            models.forEach({
                let message = ConfigModelPublicationSet(Publish(to: MeshAddress(publishAddress), using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: period, retransmit: .disabled), to: $0)!
                messageHandles.append(MeshMessageHandle(message: message, address: node.primaryUnicastAddress))
            })
      
        case .sensorDisable(let sensorModels):
            let models = sensorModels.filter({ $0.modelIdentifier == .sensorServerModelId })
            models.forEach({
                let message = ConfigModelPublicationSet(disablePublicationFor: $0)!
                messageHandles.append(MeshMessageHandle(message: message, address: node.primaryUnicastAddress))
            })
        case .daylightCalibration(let value):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .daylightCalibrate(value)), model: vendorModel))
            }
        case .sensitivity(let value, let range):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .motionSensitivity(value, maxValue: range?.upperBound, minValue: range?.lowerBound)), model: vendorModel))
            }
        }
        return messageHandles
    }
    
}
