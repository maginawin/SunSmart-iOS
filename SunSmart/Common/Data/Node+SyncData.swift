//
//  Node+SyncData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/3/22.
//

import Foundation
import NordicSigMeshSDK

/// Context for group profile synchronization that needs behavior beyond normal diff-based sync.
struct GroupProfileSyncContext {
    enum Reason {
        case profileTypeChanged(previous: Profile.ProfileType, saved: Profile.ProfileType)
        case memberAdded
    }

    let reason: Reason

    var shouldForceFullProfileSync: Bool {
        switch reason {
        case .profileTypeChanged(let previous, let saved):
            return previous != saved
        case .memberAdded:
            return true
        }
    }
}

/// 节点同步类型
enum NodeSyncType {
    /// 组
    case group(_ group: Group?, effectiveMemberCount: Int? = nil)
    /// 场景
    case scenes(scene: Scene? = nil)
    /// 日程
    case schedules(schedule: Schedule? = nil)
    /// 动能开关 （传入则获取对应的数据）
    case switches(switchData: DeviceSwitchData? = nil)
    /// Dongle数据
    case dongle(dongleData: DeviceDongleData)
    /// 邻近照明
    case proximityLightingPath(path: GroupProximityLightingPathData)
    /// 网关信息
    case gateway(_ gateway: GatewayModel)
    /// 全部
    case all
}

enum NodeSyncData {
    
    /// 添加网络key
    case addNetworkKey(networkKey: NetworkKey)
    /// 删除网络key
    case removeNetworkKey(networkKey: NetworkKey)
    /// 添加appkey
    case addApplicationkey(applicationKey: ApplicationKey)
    /// 删除appkey
    case removeApplicationkey(applicationKey: ApplicationKey)
    /// 设备是否需要订阅/加入组（订阅信息不完整）
    case subscribeGroup(group: Group)
    /// 设备需要退出组
    case unsubscribeGroup(group: Group)
    /// profile数据
    case profile(types: [ProfileType])
    /// 同步场景list
    case syncScenes(datas: [(scene: Scene, data: SceneExecuteData)])
    /// 删除场景list
    case deleteScenes(scenes: [Scene])
    /// 同步日程list
    case syncSchedules(schedules: [Schedule])
    /// 删除日程list
    case deleteSchedules(schedules: [Schedule])
    /// 同步动能开关代理
    case syncSwitchProxy(switchData: DeviceSwitchData)
    /// 删除动能开关代理
    case deleteSwitchProxy(switchData: DeviceSwitchData)
    /// 同步绑定动能开关list
    case syncSwitchs(switchDatas: [DeviceSwitchData])
    /// 删除绑定动能开关list
    case deleteSwitchs(switchDatas: [DeviceSwitchData])
    /// pwm周期
//    case pwmPeriod(value: UInt16)
    /// 初始化（config）
    case deviceInitialize
    /// 设备参数类型list
    case deviceParameterTypes(types: [DeviceParameterType])
    /// 同步采集能耗日程
    case syncCollectionSchedules(schedules: [(Int, SchedulerRegistryEntry)])
    /// 删除采集能耗日程
    case deleteCollectionSchedules(scheduleIds: [Int])
    /// 设置邻近照明启用禁用
    case proximityLightingEnabled(_ enabled: Bool)
    /// 设置临近照明转发次数
    case proximityLightingRelayNumber(_ relayNumber: UInt8)
    /// 设置邻近照明邻居数量+邻居list
    case proximityLightingNeighbor(relayNumber: UInt8, neighborAddresses: [Address])
    /// 同步网关SIM卡APN
    case syncGatewaySIMAPN(apn: String)
    /// 同步网关MQTT参数
    case syncGatewayMQTTInformation(mqttInformation: GatewayInformation.MQTTConnectInformation)
    /// 同步网关项目id  projectId: siteid
    case syncGatewayProjectId(projectId: String)
    /// 同步网关关联的子网appkey index list
    case syncGatewaySubnetAppkeyIndexs(appkeyIndexs: [KeyIndex])
    /// 网关关联spaces activate: 是否激活
    case gatewayAssociatedSpaces(datas: [(networkKey: NetworkKey, applicationKey: ApplicationKey)], activate: Bool)
    /// 网关解除关联spaces  activate: 是否激活
    case gatewayUnbindAssociatedSpaces(datas: [(networkKey: NetworkKey, applicationKey: ApplicationKey)], activate: Bool)
    /// pir传感器启用/禁用
    case pirEnabled(_ enabled: Bool)
    /// EFC 关联灯组订阅/退订
    case emergencyFireControllerAssociations(data: DeviceEmerFireData, tasks: [EmergencyFireControllerSyncTask])
}

extension Group {
    
    func sensorServerPublicationRetransmit(effectiveMemberCount: Int? = nil) -> Publish.Retransmit {
        let memberCount = effectiveMemberCount ?? nodes.count
        guard memberCount <= 3 else {
            return Publish.Retransmit(1, timesWithInterval: 0.1)
        }
        return Publish.Retransmit(2, timesWithInterval: 0.1)
    }
    
}

enum SensorPublicationSyncMode {
    case strictTarget
    case legacyCompatible
}

extension Model {
    
    func isSensorServerPublicationConfigured(
        publishAddress: Address,
        retransmit: Publish.Retransmit,
        syncMode: SensorPublicationSyncMode = .strictTarget
    ) -> Bool {
        guard modelIdentifier == .sensorServerModelId, let publication = self.publish else {
            return false
        }
        guard publication.publicationAddress.address == publishAddress else {
            return false
        }

        switch syncMode {
        case .strictTarget:
            return publication.retransmit == retransmit
        case .legacyCompatible:
            return publication.retransmit == retransmit || publication.retransmit == .disabled
        }
    }
    
}

/// 配置类型
enum ProfileType {
    /// 传感器启用（启用后才能与接收传感器状态）
    case sensorEnabled(sensorModels: [Model], publishAddress: Address, delay: TimeInterval = 0, retransmit: Publish.Retransmit = .disabled)
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
    /// 第三阶段待机亮度值 0~100%
    case standbyLevel(value: Int)
//    /// 第三阶段待机照度值 lux
    case standbyLux(lux: Int)
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
    /// 手动控制后延迟时间（期间内保存控制后状态） enabled：是否开启 manualOverrideState: 手动控制结束后状态  second： 0xFFFFFFFF无限长 默认10min
    case manualOverrideTimeout(enabled: Bool, manualOverrideState: ManualOverrideState = .standby, second: UInt32 = 600)
    /// 是否手动控制后进入感应状态
    case manualControl(enabled: Bool)
    /// 上电状态
    case powerOnState(state: Profile.PowerUpState, cct: UInt16? = nil)
    /// 光照传感器校准
    case daylightCalibration(value: UInt16)
    /// 光感校准倍率
    case daylightCalibrateRate(sensorRatio: UInt16, ambientlightRatio: UInt16)
    /// 光感校准清除
//    case daylightCalibrateReset
    /// 光感校准灯光拐点
    case daylightCalibrateInflectionPoint(minLightPoint: DaylightSensorCalibrationData.LightnessLuxData, maxLightPoint: DaylightSensorCalibrationData.LightnessLuxData)
    /// 灵敏度 0~100%
    case sensitivity(value: UInt16, range: ClosedRange<UInt16>? = nil)
    /// 当前灯光控制数据保存快照
    case lightControlSnapshoot(sceneNumber: SceneNumber = .snapshotScene)
    /// 切换光照传感器配置的灯光控制数据场景（白天/晚上）
    case daylightSensorConditionRecall(id: UInt8)
    /// 切换灯光控制数据场景（profile SceneA => SceneB）
    case lightControlSwitch(sceneNumber: SceneNumber)
    /// 灯光数据缓存到场景
    case lightControlStore(sceneNumber: SceneNumber, turnOffBeforeStore: Bool = false)
    /// 当前灯光控制数据恢复
    case lightControlRestore(sceneNumber: SceneNumber = .snapshotScene)
    /// 删除灯光控制场景
    case lightControlDelete(sceneNumber: SceneNumber)
    /// 根据lux切换白天profile条件配置
    case profileDayToggleTriggerConditionLux(id: UInt8, minLux: UInt16, maxLux: UInt16, useCalibrationValues: Bool, destination: Address, sceneNumber: SceneNumber, forceFullSet: Bool)
    /// 根据lux切换晚上profile条件配置
    case profileNightToggleTriggerConditionLux(id: UInt8, minLux: UInt16, maxLux: UInt16, useCalibrationValues: Bool, destination: Address, sceneNumber: SceneNumber, forceFullSet: Bool)
    /// 删除lux切换profile条件配置
    case profileToggleTriggerConditionLuxDelete(id: UInt8)
    /// 光照传感器lux条件触发锁定 delay: 锁定时间
    case profileToggleTriggerConditionLuxLock(delay: UInt16)
    /// 光照传感器lux条件触发解锁
    case profileToggleTriggerConditionLuxUnLock
    /// 配置文件lux触发条件切换配置
//    case profileToggleTriggerConditionLux(id: UInt8, minLux: UInt16, maxLux: UInt16, destination: Address, sceneNumber: SceneNumber)
}

extension ProfileType {
    func targetPowerUpCct(for node: Node) -> UInt16? {
        guard case .powerOnState(.definedLightLevel(_), let cct) = self,
              let cct = cct,
              node.effectiveSupportCct else {
            return nil
        }
        return node.clampEffectiveCct(cct)
    }
}

enum DeviceParameterType {
    
    var rawValue: Int {
        switch self {
        case .pwmFrequency:
            return 1
        case .ratedPower:
            return 2
        case .motionSensitivityRange:
            return 3
        case .defaultTransitionTime:
            return 4
        case .powerCalibration:
            return 5
        case .absoluteCctRange:
            return 6
        case .photosensorException:
            return 8
        }
    }
    
    /// 根据设备参数类型获取对应消息发送对象
    func getMessageHandles(node: Node) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        switch self {
        case .pwmFrequency(let frequency):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .pwmFrequency(frequency)), model: vendorModel))
            }
        case .ratedPower(let datas):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .phaseEnergyConsumption(list: datas)), model: vendorModel))
            }
        case .motionSensitivityRange(let range):
            if let vendorModel = node.sunricherVendorModel {
                let addToGroup = node.group ?? node.restoreData?.addGroup
                let sensitivity = node.motionSensitivity ?? min(UInt8(addToGroup?.info.profile.sensitivity ?? 100).value16, 65535)
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .motionSensitivity(sensitivity, maxValue: range.upperBound, minValue: range.lowerBound)), model: vendorModel))
            }
        case .defaultTransitionTime(let transitionTime):
            if let defaultTransitionTimeModel = node.defaultTransitionTimeModel {
                messageHandles.append(MeshMessageHandle(message: GenericDefaultTransitionTimeSet(transitionTime: transitionTime), model: defaultTransitionTimeModel))
            }
        case .powerCalibration(let calibrationValue):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .dimmerPowerCalibrate(calibrationValue: calibrationValue)), model: vendorModel))
            }
        case .absoluteCctRange(let range):
            if let ctlModel = node.ctlModel, node.rawSupportCct {
                messageHandles.append(MeshMessageHandle(message: LightCTLTemperatureRangeSet(range), model: ctlModel))
            }
        case .photosensorException(let state):
            if node.supportPhotosensorException, let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .photosensorException(state)), model: vendorModel))
            }
        }
        return messageHandles
    }
    
    /// pwm频率
    case pwmFrequency(frequency: UInt16)
    /// 额定功率
    case ratedPower(datas: [NodePhaseEnergyConsumption])
    /// 移动感应灵敏度范围
    case motionSensitivityRange(range: ClosedRange<UInt16>)
    /// 默认过渡时间
    case defaultTransitionTime(transitionTime: TransitionTime)
    /// 功率校准
    case powerCalibration(calibrationValue: UInt32)
    /// 绝对色温范围
    case absoluteCctRange(range: ClosedRange<UInt16>)
    /// 灯具内置光感异常保护
    case photosensorException(PhotosensorExceptionState)
}

enum DeviceReadParameterType {
    
    /// 根据设备参数类型获取对应消息发送对象
    func getMessageHandles(node: Node) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        switch self {
        case .pwmFrequency:
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorGet(function: .pwmFrequency), model: vendorModel))
            }
        case .ratedPower:
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorGet(function: .phaseEnergyConsumption), model: vendorModel))
            }
        case .totalDeviceEnergyUse:
            
            if let energyModel = node.energyModel {
                messageHandles.append(MeshMessageHandle(message: SensorGet(), model: energyModel))
            }
        case .motionSensitivityRange:
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorGet(function: .motionSensitivity), model: vendorModel))
            }
        case .firmwareVension:
            if let firmwareUpdateServerModel = node.firmwareUpdateServerModel {
                messageHandles.append(MeshMessageHandle(message: FirmwareUpdateInformationGet(firstIndex: 0, entriesLimit: 1), model: firmwareUpdateServerModel))
            }
        case .defaultTransitionTime:
            if let defaultTransitionTimeModel = node.defaultTransitionTimeModel {
                messageHandles.append(MeshMessageHandle(message: GenericDefaultTransitionTimeGet(), model: defaultTransitionTimeModel))
            }
        case .photosensorException:
            if node.supportPhotosensorException, let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorGet(function: .photosensorException), model: vendorModel))
            }
        }
        return messageHandles
    }
    
    /// pwm频率
    case pwmFrequency
    /// 额定功率
    case ratedPower
    /// 设备已使用的总能耗
    case totalDeviceEnergyUse
    /// 移动感应灵敏度范围
    case motionSensitivityRange
    /// 固件版本
    case firmwareVension
    /// 默认过渡时间
    case defaultTransitionTime
    /// 灯具内置光感异常保护
    case photosensorException
}


extension Node {
    
    static var preConfigurationKey: UInt8 = 0
    private static let defaultUpRatio = 50
    
    /// 设备预配置数据
    class PreConfiguration: Codable {
        /// 白天profile lux阈值
        var dayProfileStartsAboveLux: UInt16?
        /// 晚上profile lux阈值
        var nightProfileStartsBelowLux: UInt16?
        /// 白天profile灯光数据（暂未使用）
        var dayProfileLightData: Profile.LightControlData?
        /// 晚上profile灯光数据（暂未使用）
        var nightProfileLightData: Profile.LightControlData?
        /// 是否重置光感校准数据
        var resetDaylightCalibration: Bool?
        /// 是否显示lux（光感设备在设备页面）
        var displayLux: Bool = false
        /// Up/Down Ratio 中 up 的比例，本地永久存储，不参与云同步。
        var upRatio: Int?
    }
    
    /// 设备预配置数据
    var preConfiguration: PreConfiguration {
        get {
            var preConfiguration = objc_getAssociatedObject(self, &Node.preConfigurationKey) as? PreConfiguration
            if preConfiguration == nil {
                if let uuid = self.network?.uuid.uuidString {
                    
                    preConfiguration = Node.PreConfiguration.load(meshUUID: uuid, nodeAddress: self.primaryUnicastAddress) ?? PreConfiguration()
                }else {
                    preConfiguration = PreConfiguration()
                }
                self.preConfiguration = preConfiguration!
            }
            return preConfiguration!
        }set  {
            objc_setAssociatedObject(self, &Node.preConfigurationKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    var upRatio: Int {
        get {
            let value = preConfiguration.upRatio ?? Self.defaultUpRatio
            return max(0, min(100, value))
        }
        set {
            preConfiguration.upRatio = max(0, min(100, newValue))
        }
    }

    var downRatio: Int {
        100 - upRatio
    }

    
    /// 获取设备需要同步的数据
    /// - Parameter type: 同步数据类型
    /// - Returns: 数据同步项list
    func getSyncData(type: NodeSyncType, profileSyncContext: GroupProfileSyncContext? = nil) -> [NodeSyncData] {
        
        var syncDatas: [NodeSyncData] = []
        switch type {
        case .group(let group, let effectiveMemberCount):
            guard let group = group ?? self.group else {
                return syncDatas
            }
            // 未配置完成
            if !self.isKeybindComplete {
                syncDatas.append(.deviceInitialize)
            }
            // 设备退出组失败
            if self.group != nil && groupState == GroupState.exitFailure {
                // 退出组时pir默认启用
                if self.capabilities.contains(.pirEnabled), !self.pirEnabled {
                    syncDatas.append(.pirEnabled(true))
                }
                syncDatas.append(.unsubscribeGroup(group: self.group!))
            }else if getSunSmartSubscribeToGroupMessageHandles(group).count > 0 { // 设备订阅组数据不完整
                syncDatas.append(.subscribeGroup(group: group))
            }
            
            // profile
            let syncProfiles = getNodeSyncProfiles(
                group: group,
                effectiveMemberCount: effectiveMemberCount,
                profileSyncContext: profileSyncContext
            )
            if syncProfiles.count > 0 {
                syncDatas.append(.profile(types: syncProfiles))
            }
            
            // 场景
            let syncScenes = getNodeSyncSceneDatas(group: group)
            if syncScenes.count > 0 {
                syncDatas.append(.syncScenes(datas: syncScenes))
            }
            let deleteScenes = getNodeNeedDeleteSceneDatas()
            if deleteScenes.count > 0 {
                syncDatas.append(.deleteScenes(scenes: deleteScenes))
            }
            
            // 日程
            let syncSchedules = getNodeSyncSchedules(group: group)
            if syncSchedules.count > 0 {
                syncDatas.append(.syncSchedules(schedules: syncSchedules))
            }
            let deleteSchedules = getNodeNeedDeleteSchedules(group: group)
            if deleteSchedules.count > 0 {
                syncDatas.append(.deleteSchedules(schedules: deleteSchedules))
            }
            
            // 动能开关
            let syncSwitchData = getNodeSyncSwitchs(group: group)
            if let switchProxy = syncSwitchData.switchProxy {
                syncDatas.append(.syncSwitchProxy(switchData: switchProxy))
            }
            if syncSwitchData.linkSwitchs.count > 0 {
                syncDatas.append(.syncSwitchs(switchDatas: syncSwitchData.linkSwitchs))
            }
            let deleteSwitchData = getNodeNeedDeleteSwitchs()
            if let delteSwitchProxy = deleteSwitchData.delteSwitchProxy {
                syncDatas.append(.deleteSwitchProxy(switchData: delteSwitchProxy))
            }
            if deleteSwitchData.unlinkSwitchs.count > 0 {
                syncDatas.append(.deleteSwitchs(switchDatas: deleteSwitchData.unlinkSwitchs))
            }
            
            // 邻近照明
            if let syncData = getNodeSyncProximityLighting(group: group) {
                syncDatas.append(syncData)
            }
            
        case .scenes(let scene):
            
            let syncScenes = getNodeSyncSceneDatas(scene: scene)
            if syncScenes.count > 0 {
                syncDatas.append(.syncScenes(datas: syncScenes))
            }
            let deleteScenes = getNodeNeedDeleteSceneDatas(scene: scene)
            if deleteScenes.count > 0 {
                syncDatas.append(.deleteScenes(scenes: deleteScenes))
            }
            
        case .schedules(let schedule):
            
            let syncSchedules = getNodeSyncSchedules(schedule: schedule)
            if syncSchedules.count > 0 {
                syncDatas.append(.syncSchedules(schedules: syncSchedules))
            }
            let deleteSchedules = getNodeNeedDeleteSchedules(schedule: schedule)
            if deleteSchedules.count > 0 {
                syncDatas.append(.deleteSchedules(schedules: deleteSchedules))
            }
            
        case .switches(let switchData):
            
            let syncSwitchData = getNodeSyncSwitchs(switchData: switchData)
            if let switchProxy = syncSwitchData.switchProxy {
                syncDatas.append(.syncSwitchProxy(switchData: switchProxy))
            }
            if syncSwitchData.linkSwitchs.count > 0 {
                syncDatas.append(.syncSwitchs(switchDatas: syncSwitchData.linkSwitchs))
            }
            let deleteSwitchData = getNodeNeedDeleteSwitchs(switchData: switchData)
            if let delteSwitchProxy = deleteSwitchData.delteSwitchProxy {
                syncDatas.append(.deleteSwitchProxy(switchData: delteSwitchProxy))
            }
            if deleteSwitchData.unlinkSwitchs.count > 0 {
                syncDatas.append(.deleteSwitchs(switchDatas: deleteSwitchData.unlinkSwitchs))
            }
        case .dongle(let dongleData):
            // dongle设备同步dongle预配置数据
            guard self.deviceType == .dongle else {
                return syncDatas
            }
            // TODO: - TimeAuthority
            
            // 日程
            if let collectionSchedulerSetupModel = self.collectionSchedulerSetupModel {
                // 设备采集日程数据list
                let schedulerEntrys = allSchedulerModelEntrys[collectionSchedulerSetupModel] ?? [:]
                // 启用采集
                if dongleData.collectionEnable {
                    // 获取需要同步日程
                    let syncSchedules = dongleData.schedules.filter { schedule in
                        let id = Int(schedule.id)
                        // 判断日程数据是否需同步
                        if schedulerEntrys[id] == nil || !(schedulerEntrys[id]! == schedule.schedulerEntry) {
                            return true
                        }
                        return false
                    }
                    
                    syncDatas.append(.syncCollectionSchedules(schedules: syncSchedules.map({ (Int($0.id), $0.schedulerEntry) })))
                    
                    // 需要删除的日程
                    let deleteSchedules = schedulerEntrys.filter({ entry in !dongleData.schedules.contains(where: { $0.id == entry.key }) })
                    syncDatas.append(.deleteCollectionSchedules(scheduleIds: deleteSchedules.map({ $0.key })))
                }else { // 禁用采集
                    
                    // 需要同步的日程（禁用后应设置无效）
                    let syncScheduleEntrys = schedulerEntrys.filter({ $0.value.isValid })
                    let ids = syncScheduleEntrys.keys.sorted()
                    
                    let syncSchedules = ids.map({ ($0, syncScheduleEntrys[$0]!) })
                    syncDatas.append(.syncCollectionSchedules(schedules: syncSchedules))
                }
            }
        case .proximityLightingPath:
            // 邻近照明
            if let syncData = getNodeSyncProximityLighting() {
                syncDatas.append(syncData)
            }
        case .gateway(let gatewayModel): // 网关
            syncDatas.append(contentsOf: getNodeSyncGatewayData(gateway: gatewayModel))
        case .all:
            
            // 未配置完成
            if !self.isKeybindComplete {
                syncDatas.append(.deviceInitialize)
            }
            if let group = self.group ?? self.restoreData?.addGroup {
                syncDatas.append(contentsOf: getSyncData(type: .group(group)))
                syncDatas.append(contentsOf: getNodeEmergencyFireControllerAssociationSyncDatas(group: group))
            }else { // 未加入组的profile
                // profile
                let syncProfiles = getNodeSyncProfiles(group: nil)
                if syncProfiles.count > 0 {
                    syncDatas.append(.profile(types: syncProfiles))
                }
                syncDatas.append(contentsOf: getSyncData(type: .schedules()))
            }
            
            // 设备参数
            var deviceParameterTypes: [DeviceParameterType] = []
            if self.sunricherVendorModel != nil {
                // PWM
                if let pwmFrequency = self.restoreData?.pwmFrequency, self.pwmFrequency != pwmFrequency {
                    deviceParameterTypes.append(.pwmFrequency(frequency: pwmFrequency))
                }
                // Rated power
                if let phaseEnergyConsumptions = self.restoreData?.phaseEnergyConsumptions, self.phaseEnergyConsumptions != phaseEnergyConsumptions {
                    deviceParameterTypes.append(.ratedPower(datas: phaseEnergyConsumptions))
                }
                // Absolute Sensitivity
                if let motionSensitivityRange = self.restoreData?.motionSensitivityRange,
                   self.motionSensitivityRange != motionSensitivityRange {
                    deviceParameterTypes.append(.motionSensitivityRange(range: motionSensitivityRange))
                }
                if let photosensorException = self.restoreData?.photosensorException,
                   self.photosensorException != photosensorException,
                   self.supportPhotosensorException {
                    deviceParameterTypes.append(.photosensorException(photosensorException))
                }
            }
            if let targetRawValue = DeviceRestoreDefaultTransitionTimePolicy.pendingTargetRawValue(
                restoreTargetRawValue: self.restoreData?.defaultTransitionTime?.rawValue,
                currentRawValue: self.defaultTransitionTime?.rawValue,
                isSupported: self.supportDefaultTransitionTime
            ) {
                deviceParameterTypes.append(.defaultTransitionTime(transitionTime: .init(rawValue: targetRawValue)))
            }
            if deviceParameterTypes.count > 0 {
                syncDatas.append(.deviceParameterTypes(types: deviceParameterTypes))
            }
            
            // Dongle
            if self.deviceType == .dongle, let dongleData = MeshNetworkManager.instance.dongles.first(where: { $0.bindNodeAddress == self.primaryUnicastAddress }) {
                syncDatas.append(contentsOf: getSyncData(type: .dongle(dongleData: dongleData)))
            }
            
            // Gateway
            if self.deviceType == .gateway, let gatewayModel = GatewayModel.load(node: self) {
                syncDatas.append(contentsOf: getNodeSyncGatewayData(gateway: gatewayModel))
            }
            
        }
        return syncDatas
    }
    
    /// 获取节点是否需要同步组数据
    func getNeedSyncGroup(group: Group? = nil) -> Bool {
        
        // 设备退出组失败
        if self.group != nil && groupState == GroupState.exitFailure {
            return true
        }else if let addToGroup = group, getSunSmartSubscribeToGroupMessageHandles(addToGroup).count > 0 { // 设备订阅组数据不完整
            return true
        }
        
        // profile
        let syncProfiles = getNodeSyncProfiles(group: group, sensorPublicationSyncMode: .legacyCompatible)
        if syncProfiles.count > 0 {
            return true
        }
        
        // 场景
        let syncScenes = getNodeSyncSceneDatas(group: group)
        if syncScenes.count > 0 {
            return true
        }
        let deleteScenes = getNodeNeedDeleteSceneDatas()
        if deleteScenes.count > 0 {
            return true
        }
        
        // 日程
        let syncSchedules = getNodeSyncSchedules(group: group)
        if syncSchedules.count > 0 {
            return true
        }
        let deleteSchedules = getNodeNeedDeleteSchedules(group: group)
        if deleteSchedules.count > 0 {
            return true
        }
        
        // 动能开关
        let syncSwitchData = getNodeSyncSwitchs(group: group)
        if syncSwitchData.switchProxy != nil {
            return true
        }
        if syncSwitchData.linkSwitchs.count > 0 {
            return true
        }
        let deleteSwitchData = getNodeNeedDeleteSwitchs()
        if deleteSwitchData.delteSwitchProxy != nil {
            return true
        }
        if deleteSwitchData.unlinkSwitchs.count > 0 {
            return true
        }
        
        // 邻近照明
        if getNodeSyncProximityLighting(group: group) != nil {
            return true
        }

        if !getNodeEmergencyFireControllerAssociationSyncDatas(group: group).isEmpty {
            return true
        }
        
        return false
    }
    
    /// 获取节点是否要同步
    func getNeedSync() -> Bool {
        
        // 未配置完成
        if !self.isKeybindComplete {
            return true
        }
        
        if let group = self.group ?? self.restoreData?.addGroup {
            if getNeedSyncGroup(group: group) {
                return true
            }
        }else { // 未加入组的profile
            // profile
            let syncProfiles = getNodeSyncProfiles(group: nil)
            if syncProfiles.count > 0 {
                return true
            }
            // 日程
            let syncSchedules = getNodeSyncSchedules()
            if syncSchedules.count > 0 {
                return true
            }
            let deleteSchedules = getNodeNeedDeleteSchedules()
            if deleteSchedules.count > 0 {
                return true
            }
        }
        
        // PWM
        if let pwmFrequency = self.restoreData?.pwmFrequency, self.pwmFrequency != pwmFrequency {
            return true
        }
        
        // Rated power
        if let phaseEnergyConsumptions = self.restoreData?.phaseEnergyConsumptions, self.phaseEnergyConsumptions != phaseEnergyConsumptions {
            return true
        }
        // Absolute Sensitivity
        if let motionSensitivityRange = self.restoreData?.motionSensitivityRange,
           self.motionSensitivityRange != motionSensitivityRange {
            return true
        }
        if let photosensorException = self.restoreData?.photosensorException,
           self.photosensorException != photosensorException,
           self.supportPhotosensorException {
            return true
        }
        if DeviceRestoreDefaultTransitionTimePolicy.pendingTargetRawValue(
            restoreTargetRawValue: self.restoreData?.defaultTransitionTime?.rawValue,
            currentRawValue: self.defaultTransitionTime?.rawValue,
            isSupported: self.supportDefaultTransitionTime
        ) != nil {
            return true
        }
 
        // Dongle
        if self.deviceType == .dongle, let dongleData = MeshNetworkManager.instance.dongles.first(where: { $0.bindNodeAddress == self.primaryUnicastAddress }) {
            if getSyncData(type: .dongle(dongleData: dongleData)).count > 0 {
                return true
            }
        }

        // Gateway
        if self.deviceType == .gateway, let gatewayModel = GatewayModel.load(node: self) {
            if getNodeSyncGatewayData(gateway: gatewayModel).count > 0 {
                return true
            }
        }
        
        return false
    }

    func getNodeEmergencyFireControllerAssociationSyncDatas(group: Group? = nil) -> [NodeSyncData] {
        EmergencyFireControllerSyncPlanner.makeNodeAssociationSyncs(node: self, group: group).map {
            .emergencyFireControllerAssociations(data: $0.controller, tasks: $0.tasks)
        }
    }
    
    /// 获取需要同步的白天晚上lux条件profile
    func getSyncDayNightLuxProfiles() -> [ProfileType] {
        guard let group = self.group else { return [] }
        let profile = group.info.profile
        var profileTypes: [ProfileType] = []
        guard self.ambientLightSensorModel != nil, self.sunricherVendorModel != nil else {
            return profileTypes
        }
        
        if profile.type == .proximityLightingWithPhotocell, let nightData = profile.nightData, let dayData = profile.dayData {
            
            // 场景执行的目标地址
            let sceneDestination = self.lightLCSceneModel?.parentElement?.unicastAddress ?? self.lightLCModel?.parentElement?.unicastAddress ?? self.primaryUnicastAddress
            
            let nightTargetLux = preConfiguration.nightProfileStartsBelowLux ?? nightData.startsBelowLux
            let dayTargetLux = preConfiguration.dayProfileStartsAboveLux ?? dayData.startsBelowLux
            
            let nightCondition = self.lightControlLuxTriggerConditions.first(where: { $0.index == nightData.id })
            let dayCondition = self.lightControlLuxTriggerConditions.first(where: { $0.index == dayData.id })
            
            if nightCondition == nil || nightCondition!.maxLux != nightTargetLux || nightCondition!.useCalibrationValues != nightData.useCalibrationValues || nightCondition!.destination != sceneDestination || nightCondition!.sceneNumber != nightData.sceneData.sceneNumber {
                profileTypes.append(.profileNightToggleTriggerConditionLux(id: nightData.id, minLux: 0, maxLux: nightTargetLux, useCalibrationValues: nightData.useCalibrationValues, destination: sceneDestination, sceneNumber: nightData.sceneData.sceneNumber, forceFullSet: false))
            }
            
            if dayCondition == nil || dayCondition!.minLux != dayTargetLux || dayCondition!.useCalibrationValues != dayData.useCalibrationValues || dayCondition!.destination != sceneDestination || dayCondition!.sceneNumber != dayData.sceneData.sceneNumber {
                profileTypes.append(.profileDayToggleTriggerConditionLux(id: dayData.id, minLux: dayTargetLux, maxLux: .max, useCalibrationValues: dayData.useCalibrationValues, destination: sceneDestination, sceneNumber: dayData.sceneData.sceneNumber, forceFullSet: false))
            }
            
        }
        return profileTypes
    }
    
    /// 获取需要同步的profile
    func getNodeSyncProfiles(
        group: Group? = nil,
        effectiveMemberCount: Int? = nil,
        profileSyncContext: GroupProfileSyncContext? = nil,
        sensorPublicationSyncMode: SensorPublicationSyncMode = .strictTarget
    ) -> [ProfileType] {
        
        var syncProfile: [ProfileType] = []
        
        guard let group = group ?? self.group else {
            if self.deviceType != .dongle && self.deviceType != .gateway {
                if powerUpState != .restore {
                    syncProfile.append(.powerOnState(state: .restore))
                }
                if sunricherVendorModel != nil, lightLCModel != nil, lightLCProperty.manualOverrideEnabled == nil || !lightLCProperty.manualOverrideEnabled! || lightLCProperty.manualOverrideTimeout != .max {
                    syncProfile.append(.manualOverrideTimeout(enabled: true, second: .max))
                }
            }
            return syncProfile
        }
        
        let groupProfile = group.info.profile
        let forceFullProfileSync = profileSyncContext?.shouldForceFullProfileSync == true
        
        // 启用的传感器model
        var enableSensorModels: [Model] = []
        // 禁用的传感器model
        var disableSensorModels: [Model] = []
        /// 传感器model上报地址
        let publishAddress = group.address.address
        let publishRetransmit = group.sensorServerPublicationRetransmit(effectiveMemberCount: effectiveMemberCount)
        // 邻近照明profile不能将publish发送到组里，否则会让全部设备进入第一阶段，但客户端需要收到传感器状态，所以设置上报到客户端组
//        if groupProfile.type == .proximityLighting {
//            publishAddress = .localClientGroupAddress
//        }
        
        if self.group == nil || groupState == .inGroup {
            
            // 光照类型
            let daylightType = groupProfile.type == .occupancy_daylight || groupProfile.type == .vacancy_daylight || groupProfile.type == .daylight
        
            // 占用类型
            let occupancyType = groupProfile.type == .occupancy_daylight || groupProfile.type == .vacancy_daylight || groupProfile.type == .occupancy || groupProfile.type == .vacancy //|| groupProfile.type == .proximityLighting
            
       
            // 组内是否启用了光照传感器
            var daylightEnabled = false
            if let daylightNode = group.info.ambientLightSensorNode, daylightNode.sensorCalibrated || daylightNode.restoreData?.daylightCalibrationValue != nil || daylightNode.restoreData?.daylightCalibrationData != nil {
                daylightEnabled = true
            }
            if daylightType {
                if group.info.ambientLightSensorNode?.primaryUnicastAddress == primaryUnicastAddress,
                   let model = ambientLightSensorModel,
                   !model.isSensorServerPublicationConfigured(publishAddress: publishAddress, retransmit: publishRetransmit, syncMode: sensorPublicationSyncMode) { //光照传感器并且已校准
                    enableSensorModels.append(model)
                }
            }else {
                if let model = ambientLightSensorModel, model.publish != nil {
                    disableSensorModels.append(model)
                }
            }
            
            if occupancyType {
                if let model = presenceDetectedSensorModel,
                   !model.isSensorServerPublicationConfigured(publishAddress: publishAddress, retransmit: publishRetransmit, syncMode: sensorPublicationSyncMode) {
                    enableSensorModels.append(model)
                }
            }else {
                if let model = presenceDetectedSensorModel, model.publish?.publicationAddress.address == publishAddress {
                    disableSensorModels.append(model)
                }
            }
            
            if enableSensorModels.count > 0 {
                syncProfile.append(.sensorEnabled(sensorModels: enableSensorModels, publishAddress: publishAddress, delay: 0, retransmit: publishRetransmit))
            }
            if disableSensorModels.count > 0 {
                syncProfile.append(.sensorDisable(sensorModels: disableSensorModels))
            }
            
            // 恢复光照校准值
            if daylightEnabled, let value = self.restoreData?.daylightCalibrationValue, value > 0, value < 0xFFFF, self.sunricherVendorModel != nil {
                syncProfile.append(.daylightCalibration(value: value))
            }
            
            if self.sunricherVendorModel != nil {
                if daylightEnabled { // 恢复光照校准数据
                    if let calibrationData = self.restoreData?.daylightCalibrationData {
                        if let sensorRatio = calibrationData.sensorRatio, let ambientlightRatio = calibrationData.ambientlightRatio {
                            syncProfile.append(.daylightCalibrateRate(sensorRatio: sensorRatio, ambientlightRatio: ambientlightRatio))
                        }
                        if let minLightInflectionPointData = calibrationData.minLightInflectionPointData, let maxLightInflectionPointData = calibrationData.maxLightInflectionPointData {
                            syncProfile.append(.daylightCalibrateInflectionPoint(minLightPoint: minLightInflectionPointData, maxLightPoint: maxLightInflectionPointData))
                        }
                    }
                }
            }
            
            if self.lightLCSetupModel != nil { // 灯设备
                //               var lightLCProperty: LightLCProperty
                //               if groupProfile.scenes.contains(where: { $0.sceneNumber == .generalLightControlScene }) {
                //
                //               }
                
                var scenes = groupProfile.scenes
                if groupProfile.type == .proximityLightingWithPhotocell { // 白天/黑夜临近照明时不需要通用profile
                    scenes = scenes.filter({ $0.sceneNumber != .generalLightControlScene })
                }
                // 组profile亮度范围
                let groupLightnessRange = groupProfile.lightControlData.lowEndTrim...groupProfile.lightControlData.highEndTrim
                
                // 设备亮度范围
                let minLightness = Node.getLightness100(lightness: lightnessRange.lowerBound)
                let maxLightness = Node.getLightness100(lightness: lightnessRange.upperBound)
                
                if lightnessSetupModel != nil && (forceFullProfileSync || groupLightnessRange.lowerBound != minLightness || groupLightnessRange.upperBound != maxLightness) {
                    syncProfile.append(.highLowEndTrim(range: groupLightnessRange))
                }
                
                // 设备在profile内删除不需要的场景
                if self.supportLightLCScene {
                    let deleteScenes = self.lightControlSceneExecuteDatas.filter({ data in data.sceneNumber != .generalLightControlScene && !scenes.contains(where: { $0.sceneNumber == data.sceneNumber }) })
                    deleteScenes.forEach { sceneExecuteData in
                        syncProfile.append(.lightControlDelete(sceneNumber: sceneExecuteData.sceneNumber))
                    }
                }
                if groupProfile.type != .proximityLightingWithPhotocell {
                    self.lightControlLuxTriggerConditions.forEach({ condition in
                        syncProfile.append(.profileToggleTriggerConditionLuxDelete(id: condition.index))
                    })
                }
                
                scenes.forEach { profileScene in
                    /// 白天/晚上场景条件id
                    var nightDayCooditionId: UInt8?
                    
                    var syncSceneProfiles: [ProfileType] = []
                    var forcedRecallConditionProfile: ProfileType?
                    // 固定的待机亮度
                    var fixedStandbyLevel: Int?
                    
                    // 场景执行的目标地址
                    let sceneDestination = self.lightLCSceneModel?.parentElement?.unicastAddress ?? self.lightLCModel?.parentElement?.unicastAddress ?? self.primaryUnicastAddress
                    // 需要执行的灯光数据
                    var lightControlData = profileScene.lightControlData
                    
                    // 晚上
                    if let nightData = groupProfile.nightData, nightData.sceneData.sceneNumber == profileScene.sceneNumber {
                        if nightData.executeType == .fixedLevel {
                            fixedStandbyLevel = nightData.fixedStandbyLevel
                        }else {
                            if let preConfigurationNightData = self.preConfiguration.nightProfileLightData {
                                lightControlData = preConfigurationNightData
                            }
                        }
                        nightDayCooditionId = nightData.id
                        if self.ambientLightSensorModel != nil && self.sunricherVendorModel != nil {
                            let coodition = self.lightControlLuxTriggerConditions.first(where: { $0.index == nightData.id })
                            let targetLux = preConfiguration.nightProfileStartsBelowLux ?? nightData.startsBelowLux
                            let conditionProfile = ProfileType.profileNightToggleTriggerConditionLux(id: nightData.id, minLux: 0, maxLux: targetLux, useCalibrationValues: nightData.useCalibrationValues, destination: sceneDestination, sceneNumber: nightData.sceneData.sceneNumber, forceFullSet: true)
                            forcedRecallConditionProfile = conditionProfile
                            if forceFullProfileSync || coodition == nil || coodition!.maxLux != targetLux || coodition!.useCalibrationValues != nightData.useCalibrationValues || coodition!.destination != sceneDestination || coodition!.sceneNumber != nightData.sceneData.sceneNumber {
                                syncSceneProfiles.insert(conditionProfile, at: 0)
                            }
                        }
                    }
                    // 白天
                    if let dayData = groupProfile.dayData, dayData.sceneData.sceneNumber == profileScene.sceneNumber {
                        if dayData.executeType == .fixedLevel {
                            fixedStandbyLevel = dayData.fixedStandbyLevel
                        }else {
                            if let preConfigurationDayData = self.preConfiguration.dayProfileLightData {
                                lightControlData = preConfigurationDayData
                            }
                        }
                        nightDayCooditionId = dayData.id
                        if self.ambientLightSensorModel != nil && self.sunricherVendorModel != nil {
                            let coodition = self.lightControlLuxTriggerConditions.first(where: { $0.index == dayData.id })
                            let targetLux = preConfiguration.dayProfileStartsAboveLux ?? dayData.startsBelowLux
                            let conditionProfile = ProfileType.profileDayToggleTriggerConditionLux(id: dayData.id, minLux: targetLux, maxLux: .max, useCalibrationValues: dayData.useCalibrationValues, destination: sceneDestination, sceneNumber: dayData.sceneData.sceneNumber, forceFullSet: true)
                            forcedRecallConditionProfile = conditionProfile
                            if forceFullProfileSync || coodition == nil || coodition!.minLux != targetLux || coodition!.useCalibrationValues != dayData.useCalibrationValues || coodition!.destination != sceneDestination || coodition!.sceneNumber != dayData.sceneData.sceneNumber {
                                syncSceneProfiles.insert(conditionProfile, at: 0)
                            }
                        }
                    }
                    
                    if let level = fixedStandbyLevel {
                        lightControlData = lightControlData.copy()
                        lightControlData.occupancyLevel = level
                        lightControlData.vacantLevel = level
                        lightControlData.standbyLevel = level
                    }
                    
                    var lightLCProperty: LightLCProperty!
                    if self.supportLightLCScene {
                        lightLCProperty = self.lightControlSceneExecuteDatas.first(where: { $0.sceneNumber == profileScene.sceneNumber })?.lightControlData ?? LightLCProperty()
                    }else {
                        lightLCProperty = self.lightLCProperty
                    }
                    
                    let lightSyncProfiles = getNodeLightDataSyncProfiles(
                        group: group,
                        groupLightData: lightControlData,
                        lightLCProperty: lightLCProperty,
                        forceFullProfileSync: forceFullProfileSync
                    )
                    if lightSyncProfiles.count > 0 {
                        let daylightRecallConditionId: UInt8? = {
                            guard self.sunricherVendorModel != nil,
                                  self.ambientLightSensorModel != nil,
                                  self.capabilities.contains(.lightSensorConditionRecall),
                                  let id = nightDayCooditionId,
                                  self.lightControlLuxTriggerConditions.contains(where: { $0.index == id }) else {
                                return nil
                            }
                            return id
                        }()
                        // Lux trigger conditions must exist on the device before recalling them.
                        if daylightRecallConditionId != nil, syncSceneProfiles.isEmpty, let forcedRecallConditionProfile = forcedRecallConditionProfile {
                            syncProfile.append(forcedRecallConditionProfile)
                        }
                        syncProfile.append(contentsOf: syncSceneProfiles)
                        // 是否修改control数据
                        if self.supportLightLCScene {
                            // 切换到对应场景
                            if let id = daylightRecallConditionId { // 使用光感模块激活对应场景
                                syncProfile.append(.daylightSensorConditionRecall(id: id))
                            }else {
                                syncProfile.append(.lightControlSwitch(sceneNumber: profileScene.sceneNumber))
                            }
                        }
                        // 设置profile数据
                        syncProfile.append(contentsOf: lightSyncProfiles)
                        // 保存场景
                        if self.supportLightLCScene {
                            syncProfile.append(.lightControlStore(sceneNumber: profileScene.sceneNumber))
                        }
                    }else {
                        // 设置profile数据
                        syncProfile.append(contentsOf: syncSceneProfiles)
                        if syncProfile.contains(where: { type in
                            switch type {
                            case .lightControlDelete:
                                return true
                            default:
                                return false
                            }
                        }) {
                           // 存在删除场景最后也切换到当前的场景，防止灯光控制数据还是跑的上一份删除的场景配置数据
                            if self.supportLightLCScene {
                                syncProfile.append(.lightControlSwitch(sceneNumber: profileScene.sceneNumber))
                            }
                        }
                    }
                    
                }
                
                // 判断是否需要切换profile
                if groupProfile.type == .proximityLightingWithPhotocell && syncProfile.contains(where: { type in
                    switch type {
                    case .lightControlSwitch, .daylightSensorConditionRecall:
                        return true
                    default:
                        return false
                    }
                }) {
                    
                    //                   .profileNightToggleTriggerConditionLux, .profileDayToggleTriggerConditionLux
                    // 配置条件后锁定触发，避免设置过程切换profile
                    if syncProfile.contains(where: { type in
                        switch type {
                        case .profileNightToggleTriggerConditionLux, .profileDayToggleTriggerConditionLux:
                            return true
                        default:
                            return false
                        }
                    }) || self.lightControlLuxTriggerConditions.count > 0 {
                        // 锁定
                        syncProfile.insert(.profileToggleTriggerConditionLuxLock(delay: 600), at: 0)
                        // 解锁
                        syncProfile.append(.profileToggleTriggerConditionLuxUnLock)
                    }
                }
                
            }
            
            switch groupProfile.powerUpState {
            case .off:
                if forceFullProfileSync || powerUpState != .off {
                    syncProfile.append(.powerOnState(state: .off))
                }
            case .restore:
                if forceFullProfileSync || powerUpState != .restore {
                    syncProfile.append(.powerOnState(state: .restore))
                }
            case .definedLightLevel(let level):
                let profileType = ProfileType.powerOnState(state: .definedLightLevel(level), cct: groupProfile.powerUpCct)
                let targetCct = profileType.targetPowerUpCct(for: self)
                let setCct = targetCct.map { $0 != self.defaultCct } ?? false
                if forceFullProfileSync || powerUpState != .default || Node.getLightness(lightness100: Int(level)) != defalutLightness || setCct {
                    if let targetCct = targetCct {
                        syncProfile.append(.powerOnState(state: .definedLightLevel(level), cct: targetCct))
                    }else {
                        syncProfile.append(.powerOnState(state: .definedLightLevel(level)))
                    }
                }
            }
            
            // 移动感应配置
            if occupancyType || groupProfile.type == .proximityLighting || groupProfile.type == .proximityLightingWithPhotocell, self.presenceDetectedSensorModel != nil {
                // profile 0~100% => 0~255
                let resultValue = groupProfile.sensitivity.value16
                if forceFullProfileSync || self.motionSensitivity != resultValue {
                    syncProfile.append(.sensitivity(value: resultValue))
                }
            }
            
        }else {
            let disableSensorModels = sensorModels.filter({ $0.publish != nil })
            if disableSensorModels.count > 0 {
                syncProfile.append(.sensorDisable(sensorModels: disableSensorModels))
            }
            
            let defaultRange: ClosedRange<UInt16> = 0...65535
            if lightnessSetupModel != nil, lightnessRange != defaultRange {
                syncProfile.append(.highLowEndTrim(range: 0...100))
            }
            
            if powerOnOffSetupModel != nil, powerUpState != .restore {
                syncProfile.append(.powerOnState(state: .restore))
            }
            
            // 移动感应设备 灵敏度还原到默认
            if self.presenceDetectedSensorModel != nil {
                if self.motionSensitivity != 65535 {
                    syncProfile.append(.sensitivity(value: 65535))
                }
            }
            
            if lightLCSetupModel != nil {
                // 删除设置的灯光控制数据
                if self.supportLightLCScene {
                    self.lightControlSceneExecuteDatas.forEach { executeData in
                        syncProfile.append(.lightControlDelete(sceneNumber: executeData.sceneNumber))
                    }
                    self.lightControlLuxTriggerConditions.forEach({ condition in
                        syncProfile.append(.profileToggleTriggerConditionLuxDelete(id: condition.index))
                    })
                }
                
                
                
//                if lightLCProperty.mode ?? false {
                syncProfile.append(.mode(enabled: false))
//                }
                // 占用类型
                let occupancyType = groupProfile.type == .occupancy_daylight || groupProfile.type == .vacancy_daylight || groupProfile.type == .occupancy || groupProfile.type == .vacancy || groupProfile.type == .proximityLighting || groupProfile.type == .proximityLightingWithPhotocell
                if occupancyType {
                    //                if lightLCProperty.occupancyMode {
                    syncProfile.append(.occupancyMode(enabled: false))
                    //                }
                }
                if sunricherVendorModel != nil {
                    //            if lightLCProperty.manualControlMode {
                    syncProfile.append(.manualControl(enabled: false))
                    //            }
                    //            if lightLCProperty.manualOverrideEnabled {
                    syncProfile.append(.manualOverrideTimeout(enabled: true, second: .max))
                    //            }
                    //            if lightLCProperty.lightAutoAdjustEnabled {
                    syncProfile.append(.lightAutoAdujustEnabled(enabled: false))
                    //            }
                }
            }
        }
        // 是否清除校准数据
        if self.preConfiguration.resetDaylightCalibration ?? false {
            if let calibrationData = self.sensorCalibrationData, calibrationData.isCalibration {
                syncProfile.append(.daylightCalibrateRate(sensorRatio: 100, ambientlightRatio: 100))
            }
        }
        
        return syncProfile
    }
    
    func getNodeLightDataSyncProfiles(
        group: Group,
        groupLightData: Profile.LightControlData,
        lightLCProperty: LightLCProperty,
        forceFullProfileSync: Bool = false
    ) -> [ProfileType] {
        
        let groupProfile = group.info.profile
        // 光照类型
        let daylightType = groupProfile.type == .occupancy_daylight || groupProfile.type == .vacancy_daylight || groupProfile.type == .daylight
    
        // 占用类型
        let occupancyType = groupProfile.type == .occupancy_daylight || groupProfile.type == .vacancy_daylight || groupProfile.type == .occupancy || groupProfile.type == .vacancy //|| groupProfile.type == .proximityLighting
        
        // 组内是否启用了光照传感器
        var daylightEnabled = false
        if let daylightNode = group.info.ambientLightSensorNode, daylightNode.sensorCalibrated || daylightNode.restoreData?.daylightCalibrationValue != nil || daylightNode.restoreData?.daylightCalibrationData != nil {
            daylightEnabled = true
        }
        
        
        var syncProfile: [ProfileType] = []
        if forceFullProfileSync || lightLCProperty.mode == nil || !lightLCProperty.mode! {
            syncProfile.append(.mode(enabled: true))
        }
        
        if groupProfile.type == .occupancy_daylight || groupProfile.type == .occupancy || groupProfile.type == .proximityLighting || groupProfile.type == .proximityLightingWithPhotocell {
            if forceFullProfileSync || lightLCProperty.occupancyMode == nil || !lightLCProperty.occupancyMode! {
                syncProfile.append(.occupancyMode(enabled: true))
            }
        }else {
            if forceFullProfileSync || lightLCProperty.occupancyMode == nil || lightLCProperty.occupancyMode! {
                syncProfile.append(.occupancyMode(enabled: false))
            }
        }
        
        // 手动控制延时（s）
        var manualOverrideTimeout = groupProfile.manualOverrideTimeout
        if manualOverrideTimeout < UInt32.max {
            manualOverrideTimeout = min(manualOverrideTimeout * 1000, UInt32.max)
        }
//               if groupProfile.type == .daylight || groupProfile.type == .manualControl {
//                   manualOverrideTimeout = .max
//               }
        // daylight配置手动控制后恢复on，其它恢复到off
        var manualOverrideState: ManualOverrideState = .standby
        if groupProfile.type == .daylight {
            manualOverrideState = .on
        }
        // 手动控制后延时开启灯光控制
        if forceFullProfileSync || lightLCProperty.manualOverrideEnabled == nil || !lightLCProperty.manualOverrideEnabled! || lightLCProperty.manualOverrideTimeout != manualOverrideTimeout ||  lightLCProperty.manualControlState != manualOverrideState {
            syncProfile.append(.manualOverrideTimeout(enabled: true, manualOverrideState: manualOverrideState, second: groupProfile.manualOverrideTimeout))
        }
        
        // 手动控制后进入第一阶段
        //               let vacancyType = groupProfile.type == .vacancy_daylight || groupProfile.type == .vacancy || groupProfile.type == .manualControl
        if groupProfile.type == .manualControl {
            if forceFullProfileSync || lightLCProperty.manualControlMode == nil || !lightLCProperty.manualControlMode! {
                syncProfile.append(.manualControl(enabled: true))
            }
        }else {
            if forceFullProfileSync || (lightLCProperty.manualControlMode ?? true) {
                syncProfile.append(.manualControl(enabled: false))
            }
        }
        
        if self.sunricherVendorModel != nil {
            if daylightType && daylightEnabled {
                if forceFullProfileSync || lightLCProperty.lightAutoAdjustEnabled == nil || !lightLCProperty.lightAutoAdjustEnabled! {
                    syncProfile.append(.lightAutoAdujustEnabled(enabled: true))
                }
            }else {
                if forceFullProfileSync || lightLCProperty.lightAutoAdjustEnabled == nil || lightLCProperty.lightAutoAdjustEnabled! {
                    syncProfile.append(.lightAutoAdujustEnabled(enabled: false))
                }
            }
        }
        
        let lightData = groupLightData.convertLightData(profileType: groupProfile.type)
                
        lightData.levels.forEach { levelType in
            switch levelType {
            case .lightnessRange:
//                let minLightness = Node.getLightness100(lightness: lightnessRange.lowerBound)
//                let maxLightness = Node.getLightness100(lightness: lightnessRange.upperBound)
//                if lightnessSetupModel != nil && (range.lowerBound != minLightness || range.upperBound != maxLightness) {
//                    syncProfile.append(.highLowEndTrim(range: range))
//                }
                break
            case .occupancyLevel(let level):
                if daylightType {
                    if forceFullProfileSync || lightLCProperty.luxLevelOn == nil || lightLCProperty.luxLevelOn! != level {
                        syncProfile.append(.occupancyLux(lux: level))
                    }
                }else {
                    if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: level) {
                        syncProfile.append(.occupancyLevel(value: level))
                    }
                }
            case .vacantLevel(let level):
                if daylightType {
                    if forceFullProfileSync || lightLCProperty.luxLevelProlong == nil || lightLCProperty.luxLevelProlong! != level {
                        syncProfile.append(.vacantLux(lux: level))
                    }
                }else {
                    if forceFullProfileSync || lightLCProperty.lightnessProlong == nil || lightLCProperty.lightnessProlong! != Node.getLightness(lightness100: level) {
                        syncProfile.append(.vacantLevel(value: level))
                    }
                }
            case .standbyLevel(let level):
                if daylightType {
                    if forceFullProfileSync || lightLCProperty.luxLevelStandby == nil || lightLCProperty.luxLevelStandby! != level {
                        syncProfile.append(.standbyLux(lux: level))
                    }
                }else {
                    if forceFullProfileSync || lightLCProperty.lightnessStandby == nil || lightLCProperty.lightnessStandby! != Node.getLightness(lightness100: level) {
                        syncProfile.append(.standbyLevel(value: level))
                    }
                }
            case .autoMinValue(let value, let enabled):
                
                //                        if Node.getLightness100(lightness: lightLCProperty.lightAutoMinLevel) != level {
                //                            syncProfile.append(.autoMinValue(value: level))
                //                        }
                // 校准后启用日光感应，关闭百分比调光
                if daylightType {
                    let level = enabled ? value : 0
                    
                    if daylightEnabled {
                        if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: level) {
                            syncProfile.append(.occupancyLevel(value: level))
                        }
                        if forceFullProfileSync || lightLCProperty.lightnessProlong == nil || lightLCProperty.lightnessProlong! != Node.getLightness(lightness100: level) {
                            syncProfile.append(.vacantLevel(value: level))
                        }
                        if forceFullProfileSync || lightLCProperty.lightnessStandby == nil || lightLCProperty.lightnessStandby! != Node.getLightness(lightness100: level) {
                            syncProfile.append(.standbyLevel(value: level))
                        }
                    }else if occupancyType { // 日光感应并且存在占用感应profile，未校准时阶段启用默认百分比调光
                        let occupancyLevel = daylightType ? groupLightData.highEndTrim : 100
                        let vacantLevel = 50
                        let standbyLevel = 0
                        if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: occupancyLevel) {
                            syncProfile.append(.occupancyLevel(value: occupancyLevel))
                        }
                        if forceFullProfileSync || lightLCProperty.lightnessProlong == nil || lightLCProperty.lightnessProlong! != Node.getLightness(lightness100: vacantLevel) {
                            syncProfile.append(.vacantLevel(value: vacantLevel))
                        }
                        if forceFullProfileSync || lightLCProperty.lightnessStandby == nil || lightLCProperty.lightnessStandby! != Node.getLightness(lightness100: standbyLevel) {
                            syncProfile.append(.standbyLevel(value: standbyLevel))
                        }
                    }
                }
                
            case .taskLevel(let level):
                if groupProfile.type == .daylight && !daylightEnabled {
                    let fallbackLevel = groupLightData.highEndTrim
                    if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: fallbackLevel) {
                        syncProfile.append(.occupancyLevel(value: fallbackLevel))
                    }
                }else if daylightType {
                    if forceFullProfileSync || lightLCProperty.luxLevelOn == nil || lightLCProperty.luxLevelOn! != level { // 设置占用阶段无限长，维持该照度
                        syncProfile.append(.occupancyLux(lux: level))
                    }
                }else {
                    if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: level) { // 设置占用阶段无限长，维持该亮度
                        syncProfile.append(.occupancyLevel(value: level))
                    }
                }
                if forceFullProfileSync || lightLCProperty.timeRunOn != 0xFFFFFE {
                    syncProfile.append(.t2(second: 0xFFFFFE))
                }
            }
        }
        
        lightData.times.forEach { time in
            switch time {
            case .t1(let second):
                if forceFullProfileSync || lightLCProperty.timeFadeOn == nil || lightLCProperty.timeFadeOn! != min(second * 1000, 0xFFFFFE) {
                    syncProfile.append(.t1(second: second))
                }
            case .t2(let second):
                if forceFullProfileSync || lightLCProperty.timeRunOn == nil || lightLCProperty.timeRunOn! != min(second * 1000, 0xFFFFFE) {
                    syncProfile.append(.t2(second: second))
                }
            case .t3(let second):
                if forceFullProfileSync || lightLCProperty.timeFade == nil || lightLCProperty.timeFade! != min(second * 1000, 0xFFFFFE) {
                    syncProfile.append(.t3(second: second))
                }
            case .t4(let second):
                if forceFullProfileSync || lightLCProperty.timeProlong == nil || lightLCProperty.timeProlong! != min(second * 1000, 0xFFFFFE) {
                    syncProfile.append(.t4(second: second))
                }
            case .t5(let second):
                if forceFullProfileSync || lightLCProperty.timeFadeStandbyAuto == nil || lightLCProperty.timeFadeStandbyAuto! != min(second * 1000, 0xFFFFFE) {
                    syncProfile.append(.t5(second: second))
                }
            }
        }
        
        if daylightType { // 光照配置下生效
            // 调节速率
            let speedValue = groupProfile.adjustSpeed
            let regulatorData = Node.getLightRegulator(speed: speedValue)
            if forceFullProfileSync ||
                lightLCProperty.regulatorKid == nil || lightLCProperty.regulatorKid!.roundf2 != regulatorData.regulatorKid.roundf2 ||
                lightLCProperty.regulatorKiu == nil || lightLCProperty.regulatorKiu!.roundf2 != regulatorData.regulatorKiu.roundf2 ||
                lightLCProperty.regulatorKpd == nil || lightLCProperty.regulatorKpd!.roundf2 != regulatorData.regulatorKpd.roundf2 ||
                lightLCProperty.regulatorKpu == nil || lightLCProperty.regulatorKpu!.roundf2 != regulatorData.regulatorKpu.roundf2 ||
                lightLCProperty.regulatorAccuracy == nil || lightLCProperty.regulatorAccuracy! != regulatorData.regulatorAccuracy {
                syncProfile.append(.adjustSpeed(speed: groupProfile.adjustSpeed))
            }
        }
        
        return syncProfile
    }
    
    /// 获取需要同步的场景数据list
    ///   - group: 设备所在组
    ///   - scene: 场景（传入则只获取该场景是否有同步，不传入则获取所有场景是否有同步）
    func getNodeSyncSceneDatas(group: Group? = nil, scene: Scene? = nil) -> [(scene: Scene, data: SceneExecuteData)] {
        
        guard let group = group ?? self.group, self.sceneSetupModel != nil else {
            return []
        }
        var syncSceneData: [(scene: Scene, data: SceneExecuteData)] = []
        
        var scenes = group.info.sceneExecuteDatas
        if scene != nil {
             scenes = scenes.filter({ $0.sceneNumber == scene!.number })
        }
        
        scenes.forEach { data in
            if let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == data.sceneNumber }) {
                let sceneData = self.sceneExecuteDatas.first(where: { $0.sceneNumber == data.sceneNumber })
                if data.state == .normal {
                    guard let sceneData = sceneData else {
                        syncSceneData.append((scene, data))
                        return
                    }
                    if !sceneData.isSynced(with: data, for: self) {
                        syncSceneData.append((scene, data))
                    }
                }
            }
        }
        return syncSceneData
    }
    
    /// 获取需要删除的场景list
    ///   - scene: 场景（传入则只获取该场景是否有同步，不传入则获取所有场景是否有同步）
    func getNodeNeedDeleteSceneDatas(scene: Scene? = nil) -> [Scene] {
        
        guard let group = self.group,
              SceneDeleteCapability.isSupported(sceneSetupModel: self.sceneSetupModel) else {
            return []
        }
        var scenes = self.scenes
        if scene != nil {
            scenes = [scene!]
        }
        
        return scenes.filter({ scene in
            groupState == .exitFailure && group.info.sceneExecuteDatas.contains(where: { $0.sceneNumber == scene.number }) ||  group.info.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number })?.state == .waitDelete
        })
    }
    
    /// 获取需要同步的日程list
    /// - Parameters:
    ///   - group: 设备所在组
    ///   - schedule: 日程（传入则只获取该日程是否有同步，不传入则获取所有日程是否有同步）
    /// - Returns: 日程list
    func getNodeSyncSchedules(group: Group? = nil, schedule: Schedule? = nil) -> [Schedule] {
        guard schedulerSetupModel != nil else {
            return []
        }
        let group = group ?? self.group
        var schedules = MeshNetworkManager.instance.schedules
        if schedule != nil {
            schedules = [schedule!]
        }
        /// 待同步的日程
        return schedules.filter({ schedule in
            schedule.needsSync(on: self, contextGroup: group)
        })
    }
    
    /// 获取需要删除的日程list
    /// - Parameters:
    ///   - schedule: 日程（传入则只获取该日程是否需要删除，不传入则获取所有日程是否有删除）
    /// - Returns: 日程list
    func getNodeNeedDeleteSchedules(group: Group? = nil, schedule: Schedule? = nil) -> [Schedule] {
        
        guard self.schedulerSetupModel != nil else {
            return []
        }
        let group = group ?? self.group

        var schedules = MeshNetworkManager.instance.schedules
        if schedule != nil {
            schedules = [schedule!]
        }
        /// 待删除的日程
        return schedules.filter({ schedule in
            schedule.needsDelete(from: self, contextGroup: group)
        })
    }
    
    /// 获取需要同步的动能开关数据list
    ///   - group: 设备所在组
    ///   - switchData: 动能开关（传入则只获取该动能开关是否有同步，不传入则获取所有动能开关是否有同步）
    func getNodeSyncSwitchs(group: Group? = nil, switchData: DeviceSwitchData? = nil) -> (switchProxy: DeviceSwitchData?, linkSwitchs: [DeviceSwitchData]) {
        
        guard let group = group ?? self.group else {
            return (nil, [])
        }
        guard groupState != .exitFailure else {
            return (nil, [])
        }
        let supportsEnOceanSwitchSync = self.sunricherVendorModel != nil
        
        var switchProxy: DeviceSwitchData?
        var linkSwitchs: [DeviceSwitchData] = []
        
        var switchs: [DeviceSwitchData] = group.info.switchs
        if switchData != nil {
            switchs = [switchData!]
        }
        switchs.forEach { switchData in
            if switchData.batteryPowerSwitchData != nil {
                let handleCount: Int
                if batteryPowerSwitchRestoreTargetSubscriptionSnapshots != nil {
                    handleCount = self.getBatteryPowerSwitchRestoreTargetSubscriptionMessageHandles(switchData: switchData).count
                } else {
                    handleCount = self.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: switchData, unsubscribe: false).count
                }
                if handleCount > 0 {
                    linkSwitchs.append(switchData)
                }
                return
            }
            if supportsEnOceanSwitchSync, switchData.switchKeys.count > 0 {
                // 判断是否需要绑定
                if self.getEnOceanSubscriptionMessageHandles(switchKeys: switchData.switchKeys).count > 0 {
                    linkSwitchs.append(switchData)
                }
                // 判断是否设置代理
                if switchData.enabled, switchData.proxyNodeAddress == self.primaryUnicastAddress, self.getEnOceanSwitchEnabledMessageHandles(enOceanMacAddress: switchData.enOceanMacAddress, switchKeys: switchData.switchKeys).count > 0 {
                    switchProxy = switchData
                }
            }
        }
        return (switchProxy, linkSwitchs)
    }
    
    /// 获取需要删除的动能开关list
    ///   - switchData: 动能开关（传入则只获取该动能开关是否需要删除，不传入则获取所有动能开关是否有需要删除）
    func getNodeNeedDeleteSwitchs(switchData: DeviceSwitchData? = nil) -> (delteSwitchProxy: DeviceSwitchData?, unlinkSwitchs: [DeviceSwitchData]) {
        
        guard let group = self.group else {
            return (nil, [])
        }
        let supportsEnOceanSwitchSync = self.schedulerSetupModel != nil
        var delteSwitchProxy: DeviceSwitchData?
        var switchs = group.info.allSwitchs
        if switchData != nil {
            switchs = [switchData!]
        }
        
        var unlinkSwitchs: [DeviceSwitchData] = []
        switchs.filter({ self.groupState == .exitFailure || $0.unbindGroupAddresses.contains(group.address.address) }).forEach { switchData in
            if switchData.batteryPowerSwitchData != nil {
                if self.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: switchData, unsubscribe: true).count > 0 {
                    unlinkSwitchs.append(switchData)
                }
                return
            }
            if supportsEnOceanSwitchSync, switchData.switchKeys.count > 0 {
                // 判断是否需要解绑
                if self.getEnOceanUnSubscriptionMessageHandles(switchKeys: switchData.switchKeys).count > 0 {
                    unlinkSwitchs.append(switchData)
                }
                // 判断是否设置代理
                if switchData.proxyNodeAddress == self.primaryUnicastAddress || switchData.deleteProxyNodeAddress == self.primaryUnicastAddress, self.getEnOceanSwitchDisableMessageHandles(switchKeys: switchData.switchKeys).count > 0 {
                    delteSwitchProxy = switchData
                }
            }
        }
        return (delteSwitchProxy, unlinkSwitchs)
    }
    
    
    /// 获取需要同步的邻近照明数据
    func getNodeSyncProximityLighting(group: Group? = nil) -> NodeSyncData? {
        guard self.sunricherVendorModel != nil else {
            return nil
        }
        // 检查所在组的profile类型是否是临近照明
        guard let group = group ?? self.group, group.info.profile.type == .proximityLighting || group.info.profile.type == .proximityLightingWithPhotocell, groupState != .exitFailure else {
            if self.proximityLightingEnabled { // 禁用邻近照明功能
                return .proximityLightingEnabled(false)
            }
            return nil
        }
        
        // 邻居数量
        let neighborNumber = group.info.profile.proximityLightingNumber
        let proximityLightingPath = group.info.proximityLightingPath
//        guard let proximityLightingPath = group.info.proximityLightingPath else {
//            return nil
//        }
        // 邻居地址list
        var neighborAddresses: [Address] = []
        
        let groupNodes = group.nodes
        // 获取路径上的邻居
        for path in proximityLightingPath?.paths ?? [] {
            // 包含当前设备的item index
            if let pathItemIndex = path.items.firstIndex(where: { $0.address != nil && self.contains(elementWithAddress: $0.address!) }) {
                
                // 获取设备前一个邻居
                if pathItemIndex > 0 {
//                    let neighborItems = path.items[max(0, pathItemIndex - Int(neighborNumber))..<pathItemIndex]
//                    neighborItems.forEach({ item in
//                        if let address = item.address, !neighborAddresses.contains(address) {
//                            neighborAddresses.append(address)
//                        }
//                    })
                    let neighborItem = path.items[pathItemIndex - 1]
                    if let address = neighborItem.address, groupNodes.contains(where: { $0.contains(elementWithAddress: address) }), !neighborAddresses.contains(address) {
                        neighborAddresses.append(address)
                    }
                }
                
                // 获取设备后一个邻居
                if pathItemIndex + 1 < path.items.count {
//                    let start = pathItemIndex + 1
//                    let neighborItems = path.items[start..<min(start + Int(neighborNumber), path.items.count)]
//                    neighborItems.forEach({ item in
//                        if let address = item.address, !neighborAddresses.contains(address) {
//                            neighborAddresses.append(address)
//                        }
//                    })
                    let neighborItem = path.items[pathItemIndex + 1]
                    if let address = neighborItem.address, groupNodes.contains(where: { $0.contains(elementWithAddress: address) }), !neighborAddresses.contains(address) {
                        neighborAddresses.append(address)
                    }
                }
            }
        }
        
        // 获取zone内的邻居
        for zone in proximityLightingPath?.zones ?? [] {
            var addresses = zone.addresses
            if let index = addresses.firstIndex(where: { self.contains(elementWithAddress: $0) }) {
                addresses.remove(at: index)
                let zoneNeighborAddresses = addresses.filter({ address in groupNodes.contains(where: { $0.contains(elementWithAddress: address) }) && !neighborAddresses.contains(address)  })
                neighborAddresses.append(contentsOf: zoneNeighborAddresses)
            }
        }
//        let proximityLightingNeighborNodes = self.proximityLightingNeighborAddresses.compactMap({ self.network?.node(withAddress: $0) })
//        print("node: \((self.name ?? "", self.primaryUnicastAddress)) neighbors: \(proximityLightingNeighborNodes.compactMap({ ($0.name, $0.primaryUnicastAddress) }))")
        
        // 邻居是否一致
        let neighborsEqual = self.proximityLightingNeighborAddresses.sorted() == neighborAddresses.sorted()
        
        // 需配置的邻居列表与设备是否相符
        if neighborsEqual, self.proximityLightingRelayCount == neighborNumber {
            if !self.proximityLightingEnabled {
                return .proximityLightingEnabled(true)
            }
        }else {
            // 同步转发次数
            if self.proximityLightingEnabled, neighborsEqual, self.proximityLightingRelayCount != neighborNumber {
                return .proximityLightingRelayNumber(neighborNumber)
            }
            // 同步邻居数据
            return .proximityLightingNeighbor(relayNumber: neighborNumber, neighborAddresses: neighborAddresses)
        }
        return nil
    }
    
    /// 获取网关设备同步的配置
    func getNodeSyncGatewayData(gateway: GatewayModel) -> [NodeSyncData] {
        var syncDatas: [NodeSyncData] = []
        guard deviceType == .gateway else {
            return syncDatas
        }
        // 关联项目，siteid
        if gateway.siteId != gatewayInfo?.projectId {
            syncDatas.append(.syncGatewayProjectId(projectId: gateway.siteId))
        }
        
        
        // 需要关联的spaces同步数据
        var associatedSpaceDatas: [(networkKey: NetworkKey, applicationKey: ApplicationKey)] = []
        // 需要解除关联的spaces同步数据
        var unbindAssociatedSpaceDatas: [(networkKey: NetworkKey, applicationKey: ApplicationKey)] = []

        if let meshNetwork = MeshNetworkManager.instance.meshNetwork {
            
            gateway.associatedSpaces.forEach { space in
                // 是否绑定对应子网space
                if let networkKey = networkKeys.first(where: { $0.index == space.appKeyIndex }) {
                    // 是否绑定app key
                    if let appKey = applicationKeys.boundTo(networkKey).first {
                        if subnetAppkeyBindModels.contains(where: { !$0.isBoundTo(appKey) }) { // 检查是否有model没绑定对应appkey
                            associatedSpaceDatas.append((networkKey: networkKey, applicationKey: appKey))
                        }
                    }else {
                        if let bindAppkey = meshNetwork.applicationKeys.first(where: { $0.isBound(to: networkKey) }) {
                            associatedSpaceDatas.append((networkKey: networkKey, applicationKey: bindAppkey))
                        }
                    }
                }else {
                    if let networkKey = meshNetwork.networkKeys.first(where: { $0.index == space.appKeyIndex }), let appKey = meshNetwork.applicationKeys.first(where: { $0.index == space.appKeyIndex }) {
                        associatedSpaceDatas.append((networkKey: networkKey, applicationKey: appKey))
                    }
                }
            }
            
            /// 需要解绑的子网key
            let unbindNetworkKeys = networkKeys.filter({ netKey in netKey.isSecondary && !gateway.associatedSpaces.contains(where: { $0.appKeyIndex == netKey.index }) })
            unbindNetworkKeys.forEach { networkKey in
                if let appKey = meshNetwork.applicationKeys.first(where: { $0.index == networkKey.index }) {
                    unbindAssociatedSpaceDatas.append((networkKey: networkKey, applicationKey: appKey))
                }
            }
            if associatedSpaceDatas.count > 0 {
                syncDatas.append(.gatewayAssociatedSpaces(datas: associatedSpaceDatas, activate: gateway.activate))
            }
            if unbindAssociatedSpaceDatas.count > 0 {
                syncDatas.append(.gatewayUnbindAssociatedSpaces(datas: unbindAssociatedSpaceDatas, activate: gateway.activate))
            }
        }
      
        // 同步绑定哪些子网appkey index
        // 网格激活状态同步关联子网数据
//        if associatedSpaceDatas.isEmpty && unbindAssociatedSpaceDatas.isEmpty {
            let currentAppkeyIndexs = gateway.activate ? self.applicationKeys.filter({ $0.boundNetworkKey.isSecondary }).map({ $0.index }).sorted() : []
            if currentAppkeyIndexs != gatewayInfo?.subnetAppkeyIndexs.sorted() {
                syncDatas.append(.syncGatewaySubnetAppkeyIndexs(appkeyIndexs: currentAppkeyIndexs))
            }
//        }
        
        // 判断SIM卡apn是否需要同步
        if !isWiFiGateway, let apn = gateway.apn, gatewayInfo?.simInfo?.apn != apn {
            syncDatas.append(.syncGatewaySIMAPN(apn: apn))
        }
        
        if let mqttServerInfo = gateway.mqttServerInfo {
            // 判断MQTT信息是否需要同步
            if mqttServerInfo.serverAddress != gatewayInfo?.mqttConnectInfo?.serverAddress || mqttServerInfo.clientId != gatewayInfo?.mqttConnectInfo?.clientId ||
                mqttServerInfo.userName != gatewayInfo?.mqttConnectInfo?.userName ||
                mqttServerInfo.password != gatewayInfo?.mqttConnectInfo?.password {
                syncDatas.append(.syncGatewayMQTTInformation(mqttInformation: mqttServerInfo))
            }
        }
        return syncDatas
    }
    
}
