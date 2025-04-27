//
//  Node+SyncData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/3/22.
//

import Foundation
import NordicSigMeshSDK

/// 节点同步类型
enum NodeSyncType {
    /// 组
    case group(_ group: Group?)
    /// 场景
    case scenes(scene: Scene? = nil)
    /// 日程
    case schedules(schedule: Schedule? = nil)
    /// 动能开关 （传入则获取对应的数据）
    case switches(switchData: DeviceSwitchData? = nil)
    /// Dongle数据
    case dongle(dongleData: DeviceDongleData)
    /// 全部
    case all
}

enum NodeSyncData {
    
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
}

/// 配置类型
enum ProfileType {
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
    /// 手动控制后延迟时间（期间内保存控制后状态） enabled：是否开启  second： 0xFFFFFFFF无限长 默认10min
    case manualOverrideTimeout(enabled: Bool, second: UInt32 = 600)
    /// 是否手动控制后进入感应状态
    case manualControl(enabled: Bool)
    /// 上电状态
    case powerOnState(state: Profile.PowerUpState, cct: UInt16? = nil)
    /// 光照传感器校准
    case daylightCalibration(value: UInt16)
}

enum DeviceParameterType {
    
    /// 根据设备参数类型获取对应消息发送对象
    func getMessageHandles(node: Node) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        switch self {
        case .pwmPeriod(let period):
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorSet(function: .pwmPeriod(period)), model: vendorModel))
            }
        case .ratedPower(let value):
            break
        }
        return messageHandles
    }
    
    /// pwm周期
    case pwmPeriod(period: UInt16)
    /// 额定功率
    case ratedPower(value: Int)
}

enum DeviceReadParameterType {
    
    /// 根据设备参数类型获取对应消息发送对象
    func getMessageHandles(node: Node) -> [MeshMessageHandle] {
        var messageHandles: [MeshMessageHandle] = []
        switch self {
        case .pwmPeriod:
            if let vendorModel = node.sunricherVendorModel {
                messageHandles.append(MeshMessageHandle(message: SunricherVendorGet(function: .pwmPeriod), model: vendorModel))
            }
        }
        return messageHandles
    }
    
    /// pwm周期
    case pwmPeriod
    
}


extension Node {
    
    
    /// 获取设备需要同步的数据
    /// - Parameter type: 同步数据类型
    /// - Returns: 数据同步项list
    func getSyncData(type: NodeSyncType) -> [NodeSyncData] {
        
        var syncDatas: [NodeSyncData] = []
        switch type {
        case .group(let group):
            guard let group = group ?? self.group else {
                return syncDatas
            }
            // 设备退出组失败
            if self.group != nil && groupState == GroupState.exitFailure {
                syncDatas.append(.unsubscribeGroup(group: self.group!))
            }else if getSubscribeToGroupMessages(group).count > 0 { // 设备订阅组数据不完整
                syncDatas.append(.subscribeGroup(group: group))
            }
            
            // profile
            let syncProfiles = getNodeSyncProfiles(group: group)
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
            let deleteSchedules = getNodeNeedDeleteSchedules()
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
            
        case .all:
            
            // 未配置完成
            if !self.isKeybindComplete {
                syncDatas.append(.deviceInitialize)
            }
            if let group = self.group ?? self.restoreData?.addGroup {
                syncDatas.append(contentsOf: getSyncData(type: .group(group)))
            }else { // 未加入组的profile
                // profile
                let syncProfiles = getNodeSyncProfiles(group: nil)
                if syncProfiles.count > 0 {
                    syncDatas.append(.profile(types: syncProfiles))
                }
                syncDatas.append(contentsOf: getSyncData(type: .schedules()))
            }
            
            // PWM
            if let pwmPeriod = self.restoreData?.pwmPeriod, self.pwmPeriod != pwmPeriod {
                syncDatas.append(.deviceParameterTypes(types: [.pwmPeriod(period: pwmPeriod)]))
            }
            
            // Dongle
            if self.deviceType == .dongle, let dongleData = MeshNetworkManager.instance.dongles.first(where: { $0.bindNodeAddress == self.primaryUnicastAddress }) {
                syncDatas.append(contentsOf: getSyncData(type: .dongle(dongleData: dongleData)))
            }
            
        }
        return syncDatas
    }
    
    /// 获取节点是否需要同步组数据
    func getNeedSyncGroup(group: Group? = nil) -> Bool {
        
        // 设备退出组失败
        if self.group != nil && groupState == GroupState.exitFailure {
            return true
        }else if let addToGroup = group, getSubscribeToGroupMessages(addToGroup).count > 0 { // 设备订阅组数据不完整
            return true
        }
        
        // profile
        let syncProfiles = getNodeSyncProfiles(group: group)
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
        let deleteSchedules = getNodeNeedDeleteSchedules()
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
        if let pwmPeriod = self.restoreData?.pwmPeriod, self.pwmPeriod != pwmPeriod {
            return true
        }
        return false
    }
    
    /// 获取需要同步的profile
    func getNodeSyncProfiles(group: Group? = nil) -> [ProfileType] {
        
        var syncProfile: [ProfileType] = []
        
        guard let group = group ?? self.group else {
            if powerUpState != .restore {
                syncProfile.append(.powerOnState(state: .restore))
            }
            if sunricherVendorModel != nil, lightLCProperty.manualOverrideEnabled == nil || !lightLCProperty.manualOverrideEnabled! || lightLCProperty.manualOverrideTimeout != .max {
                syncProfile.append(.manualOverrideTimeout(enabled: true, second: .max))
            }
            return syncProfile
        }
        
        let groupProfile = group.info.profile
        
        // 启用的传感器model
        var enableSensorModels: [Model] = []
        // 禁用的传感器model
        var disableSensorModels: [Model] = []
        
        if self.group == nil || groupState == .inGroup {
            
            // 光照类型
            let daylightType = groupProfile.type == .occupancy_daylight || groupProfile.type == .vacancy_daylight || groupProfile.type == .daylight
        
            // 占用类型
            let occupancyType = groupProfile.type == .occupancy_daylight || groupProfile.type == .vacancy_daylight || groupProfile.type == .occupancy || groupProfile.type == .vacancy
            // 组内是否启用了光照传感器
            var daylightEnabled = false
            if let daylightNode = group.info.ambientLightSensorNode, daylightNode.sensorCalibrated || daylightNode.restoreData?.daylightCalibrationValue != nil {
                daylightEnabled = true
            }
            if daylightType {
                if group.info.ambientLightSensorNode?.primaryUnicastAddress == primaryUnicastAddress, let model = ambientLightSensorModel, model.publish?.publicationAddress != group.address { //光照传感器并且已校准
                    enableSensorModels.append(model)
                }
            }else {
                if let model = ambientLightSensorModel, model.publish?.publicationAddress == group.address {
                    disableSensorModels.append(model)
                }
            }
            
            if occupancyType {
                if let model = presenceDetectedSensorModel, model.publish?.publicationAddress != group.address {
                    enableSensorModels.append(model)
                }
            }else {
                if let model = presenceDetectedSensorModel, model.publish?.publicationAddress == group.address {
                    disableSensorModels.append(model)
                }
            }
            
            if enableSensorModels.count > 0 {
                syncProfile.append(.sensorEnabled(sensorModels: enableSensorModels, group: group))
            }
            if disableSensorModels.count > 0 {
                syncProfile.append(.sensorDisable(sensorModels: disableSensorModels))
            }
            
            // 恢复光照校准值
            if daylightEnabled, let value = self.restoreData?.daylightCalibrationValue, self.sunricherVendorModel != nil {
                syncProfile.append(.daylightCalibration(value: value))
            }
            
           if self.lightLCSetupModel != nil { // 灯设备
               if lightLCProperty.mode == nil || !lightLCProperty.mode! {
                   syncProfile.append(.mode(enabled: true))
               }
             
               if groupProfile.type == .occupancy_daylight || groupProfile.type == .occupancy {
                   if lightLCProperty.occupancyMode == nil || !lightLCProperty.occupancyMode! {
                       syncProfile.append(.occupancyMode(enabled: true))
                   }
               }else {
                   if lightLCProperty.occupancyMode == nil || lightLCProperty.occupancyMode! {
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
               
               // 手动控制后延时开启灯光控制
               if lightLCProperty.manualOverrideEnabled == nil || !lightLCProperty.manualOverrideEnabled! || lightLCProperty.manualOverrideTimeout != manualOverrideTimeout {
                   syncProfile.append(.manualOverrideTimeout(enabled: true, second: groupProfile.manualOverrideTimeout))
               }
               
               // 手动控制后进入第一阶段
//               let vacancyType = groupProfile.type == .vacancy_daylight || groupProfile.type == .vacancy || groupProfile.type == .manualControl
               if groupProfile.type == .manualControl {
                   if lightLCProperty.manualControlMode == nil || !lightLCProperty.manualControlMode! {
                       syncProfile.append(.manualControl(enabled: true))
                   }
               }else {
                   if lightLCProperty.manualControlMode ?? false {
                       syncProfile.append(.manualControl(enabled: false))
                   }
               }
               
               if self.sunricherVendorModel != nil {
                   if daylightType && daylightEnabled {
                       if lightLCProperty.lightAutoAdjustEnabled == nil || !lightLCProperty.lightAutoAdjustEnabled! {
                           syncProfile.append(.lightAutoAdujustEnabled(enabled: true))
                       }
                   }else {
                       if lightLCProperty.lightAutoAdjustEnabled == nil || lightLCProperty.lightAutoAdjustEnabled! {
                           syncProfile.append(.lightAutoAdujustEnabled(enabled: false))
                       }
                   }
               }
               
                groupProfile.lightData.levels.forEach { levelType in
                    switch levelType {
                    case .lightnessRange(let range):
                        let minLightness = Node.getLightness100(lightness: lightnessRange.lowerBound)
                        let maxLightness = Node.getLightness100(lightness: lightnessRange.upperBound)
                        if lightnessSetupModel != nil && (range.lowerBound != minLightness || range.upperBound != maxLightness) {
                            syncProfile.append(.highLowEndTrim(range: range))
                        }
                    case .occupancyLevel(let level):
                        if daylightType {
                            if lightLCProperty.luxLevelOn == nil || lightLCProperty.luxLevelOn! != level {
                                syncProfile.append(.occupancyLux(lux: level))
                            }
                        }else {
                            if lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: level) {
                                syncProfile.append(.occupancyLevel(value: level))
                            }
                        }
                    case .vacantLevel(let level):
                        if daylightType {
                            if lightLCProperty.luxLevelProlong == nil || lightLCProperty.luxLevelProlong! != level {
                                syncProfile.append(.vacantLux(lux: level))
                            }
                        }else {
                            if lightLCProperty.lightnessProlong == nil || lightLCProperty.lightnessProlong! != Node.getLightness(lightness100: level) {
                                syncProfile.append(.vacantLevel(value: level))
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
                                if lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: level) {
                                    syncProfile.append(.occupancyLevel(value: level))
                                }
                                if lightLCProperty.lightnessProlong == nil || lightLCProperty.lightnessProlong! != Node.getLightness(lightness100: level) {
                                    syncProfile.append(.vacantLevel(value: level))
                                }
                            }else if occupancyType { // 日光感应并且存在占用感应profile，未校准时阶段启用默认百分比调光
                                let occupancyLevel = 100
                                let vacantLevel = 50
                                if lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: occupancyLevel) {
                                    syncProfile.append(.occupancyLevel(value: occupancyLevel))
                                }
                                if lightLCProperty.lightnessProlong == nil || lightLCProperty.lightnessProlong! != Node.getLightness(lightness100: vacantLevel) {
                                    syncProfile.append(.vacantLevel(value: vacantLevel))
                                }
                            }
                        }
                        
                    case .taskLevel(let level):
                        if daylightType {
                            if lightLCProperty.luxLevelOn == nil || lightLCProperty.luxLevelOn! != level { // 设置占用阶段无限长，维持该照度
                                syncProfile.append(.occupancyLux(lux: level))
                            }
                        }else {
                            if lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: level) { // 设置占用阶段无限长，维持该亮度
                                syncProfile.append(.occupancyLevel(value: level))
                            }
                        }
                        if lightLCProperty.timeRunOn != 0xFFFFFE {
                            syncProfile.append(.t2(second: 0xFFFFFE))
                        }
                    }
                }
                
                groupProfile.lightData.times.forEach { time in
                    switch time {
                    case .t1(let second):
                        if lightLCProperty.timeFadeOn == nil || lightLCProperty.timeFadeOn! != min(second * 1000, 0xFFFFFE) {
                            syncProfile.append(.t1(second: second))
                        }
                    case .t2(let second):
                        if lightLCProperty.timeRunOn == nil || lightLCProperty.timeRunOn! != min(second * 1000, 0xFFFFFE) {
                            syncProfile.append(.t2(second: second))
                        }
                    case .t3(let second):
                        if lightLCProperty.timeFade == nil || lightLCProperty.timeFade! != min(second * 1000, 0xFFFFFE) {
                            syncProfile.append(.t3(second: second))
                        }
                    case .t4(let second):
                        if lightLCProperty.timeProlong == nil || lightLCProperty.timeProlong! != min(second * 1000, 0xFFFFFE) {
                            syncProfile.append(.t4(second: second))
                        }
                    case .t5(let second):
                        if lightLCProperty.timeFadeStandbyAuto == nil || lightLCProperty.timeFadeStandbyAuto! != min(second * 1000, 0xFFFFFE) {
                            syncProfile.append(.t5(second: second))
                        }
                    }
                }
               
               if daylightType { // 光照配置下生效
                   // 调节速率
                   let speedValue = groupProfile.adjustSpeed
                   let regulatorData = Node.getLightRegulator(speed: speedValue)
                   if lightLCProperty.regulatorKid == nil || lightLCProperty.regulatorKid!.roundf2 != regulatorData.regulatorKid.roundf2 ||
                        lightLCProperty.regulatorKiu == nil || lightLCProperty.regulatorKiu!.roundf2 != regulatorData.regulatorKiu.roundf2 ||
                        lightLCProperty.regulatorKpd == nil || lightLCProperty.regulatorKpd!.roundf2 != regulatorData.regulatorKpd.roundf2 ||
                        lightLCProperty.regulatorKpu == nil || lightLCProperty.regulatorKpu!.roundf2 != regulatorData.regulatorKpu.roundf2 ||
                        lightLCProperty.regulatorAccuracy == nil || lightLCProperty.regulatorAccuracy! != regulatorData.regulatorAccuracy {
                       syncProfile.append(.adjustSpeed(speed: groupProfile.adjustSpeed))
                   }
               }
            }
            
            switch groupProfile.powerUpState {
            case .off:
                if powerUpState != .off {
                    syncProfile.append(.powerOnState(state: .off))
                }
            case .restore:
                if powerUpState != .restore {
                    syncProfile.append(.powerOnState(state: .restore))
                }
            case .definedLightLevel(let level):
                let setCct = (ctlModel != nil && groupProfile.powerUpCct != self.defaultCct)
                if powerUpState != .default || Node.getLightness(lightness100: Int(level)) != defalutLightness || setCct {
                    if setCct {
                        syncProfile.append(.powerOnState(state: .definedLightLevel(level), cct: groupProfile.powerUpCct))
                    }else {
                        syncProfile.append(.powerOnState(state: .definedLightLevel(level)))
                    }
                }
            }
            
            
        }else {
            let disableSensorModels = sensorModels.filter({ $0.publish?.publicationAddress == group.address })
            if disableSensorModels.count > 0 {
                syncProfile.append(.sensorDisable(sensorModels: disableSensorModels))
            }
            
            let defaultRange: ClosedRange<UInt16> = 0...65535
            if lightnessSetupModel != nil, lightnessRange != defaultRange {
                syncProfile.append(.highLowEndTrim(range: 0...100))
            }
            
            if powerUpState != .restore {
                syncProfile.append(.powerOnState(state: .restore))
            }
            
            if lightLCSetupModel != nil {
                //            if lightLCProperty.mode {
//                syncProfile.append(.mode(enabled: false))
                //            }
                // 占用类型
                let occupancyType = groupProfile.type == .occupancy_daylight || groupProfile.type == .vacancy_daylight || groupProfile.type == .occupancy || groupProfile.type == .vacancy
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
                if data.state == .normal, sceneData == nil || !(sceneData! == data) {
                    syncSceneData.append((scene, data))
                }
            }
        }
        return syncSceneData
    }
    
    /// 获取需要删除的场景list
    ///   - scene: 场景（传入则只获取该场景是否有同步，不传入则获取所有场景是否有同步）
    func getNodeNeedDeleteSceneDatas(scene: Scene? = nil) -> [Scene] {
        
        guard let group = self.group, self.schedulerSetupModel != nil else {
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
            // 判断日程是否存在该设备
            if schedule.nodes.contains(self) || (group != nil && (schedule.groups.contains(group!) || schedule.scene?.info.groups.contains(group!) ?? false)) {
                // 判断日程数据是否需同步
                if self.schedulerActions[schedule.id] == nil || !(self.schedulerActions[schedule.id]! == schedule.schedulerEntry) {
                    return true
                }
            }
            return false
        })
    }
    
    /// 获取需要删除的日程list
    /// - Parameters:
    ///   - schedule: 日程（传入则只获取该日程是否需要删除，不传入则获取所有日程是否有删除）
    /// - Returns: 日程list
    func getNodeNeedDeleteSchedules(schedule: Schedule? = nil) -> [Schedule] {
        
        guard self.schedulerSetupModel != nil else {
            return []
        }

        var schedules = MeshNetworkManager.instance.schedules
        if schedule != nil {
            schedules = [schedule!]
        }
        /// 待删除的日程
        return schedules.filter({ schedule in
            // 日程是否关联设备
            let isBindNode = schedule.nodeAddresses.contains(self.primaryUnicastAddress)
            // 判断日程待删除设备中是否存在该设备
            if schedule.needDeleteNodes.contains(self) || (self.group != nil && ((groupState == .exitFailure && !isBindNode) || (schedule.needDeleteGroups.contains(self.group!) || schedule.needDeleteScenes.contains(where: { scene in scene.info.groups.contains(self.group!) })))) {
                // 判断日程数据是否存在
                if self.schedulerActions[schedule.id] != nil {
                    return true
                }
            }
            return false
        })
    }
    
    /// 获取需要同步的动能开关数据list
    ///   - group: 设备所在组
    ///   - switchData: 动能开关（传入则只获取该动能开关是否有同步，不传入则获取所有动能开关是否有同步）
    func getNodeSyncSwitchs(group: Group? = nil, switchData: DeviceSwitchData? = nil) -> (switchProxy: DeviceSwitchData?, linkSwitchs: [DeviceSwitchData]) {
        
        guard let group = group ?? self.group, self.sunricherVendorModel != nil else {
            return (nil, [])
        }
        
        var switchProxy: DeviceSwitchData?
        var linkSwitchs: [DeviceSwitchData] = []
        
        var switchs: [DeviceSwitchData] = group.info.switchs
        if switchData != nil {
            switchs = [switchData!]
        }
        switchs.forEach { switchData in
            if switchData.switchKeys.count > 0 {
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
        
        guard let group = self.group, self.schedulerSetupModel != nil else {
            return (nil, [])
        }
        var delteSwitchProxy: DeviceSwitchData?
        var switchs = group.info.allSwitchs
        if switchData != nil {
            switchs = [switchData!]
        }
        
        var unlinkSwitchs: [DeviceSwitchData] = []
        switchs.filter({ self.groupState == .exitFailure || $0.unbindGroupAddresses.contains(group.address.address) }).forEach { switchData in
            if switchData.switchKeys.count > 0 {
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
    
}
