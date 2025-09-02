//
//  ExportData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/23.
//

import Foundation
import NordicSigMeshSDK

private var jsonEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .withoutEscapingSlashes
    return encoder
}

extension SiteData {
    
    /// 导出site数据
    func export(spaceIds: [String]? = nil) async -> [String: Any]  {
        
//        return await withTaskCancellationHandler {
            var siteData = await withCheckedContinuation { continuation in
                
                var siteJsonData: [String: Any] = [:]
                guard let meshNetwork = MeshNetwork.load(meshUUID: self.id, allData: false),
                      let networkKey = meshNetwork.networkKeys.first(where: { $0.isPrimary }),
                      let appKey = meshNetwork.applicationKeys.first(where: { $0.boundNetworkKey == networkKey }) else {
                    continuation.resume(returning: siteJsonData)
                    return
                }
                
                siteJsonData.updateValue(self.name, forKey: "siteName")
                siteJsonData.updateValue(self.id, forKey: "uuid")
                siteJsonData.updateValue(self.imageId, forKey: "imageId")
                siteJsonData.updateValue(self.type.rawValue, forKey: "type")
                siteJsonData.updateValue(self.sourceType.rawValue, forKey: "source")
//                siteJsonData.updateValue(self.isFavourite, forKey: "favourite")
                siteJsonData.updateValue(self.create, forKey: "createTimestamp")
                siteJsonData.updateValue(self.lastUpdate, forKey: "updateTimestamp")
                siteJsonData.updateValue(meshNetwork.currentIVIndex, forKey: "ivIndex")
                
                if let data = try? jsonEncoder.encode(networkKey), let networkKeyDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    siteJsonData.updateValue(networkKeyDict, forKey: "netKey")
                }
                if let data = try? jsonEncoder.encode(appKey), let appKeyDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    siteJsonData.updateValue(appKeyDict, forKey: "appKey")
                }
                
                // 用户地址数据
                if let provisioner = meshNetwork.localProvisioner {
                    var provisionerJson: [String: Any] = [:]
                    provisionerJson.updateValue(provisioner.uuid.uuidString, forKey: "UUID")
                    provisionerJson.updateValue(provisioner.name, forKey: "provisionerName")
                    // 正在使用的手机地址
                    if let addressHex = (provisioner.primaryUnicastAddress ?? self.localAddress)?.hex {
                        provisionerJson.updateValue(addressHex, forKey: "address")
                    }
                    // 已使用地址
                    provisionerJson.updateValue(meshNetwork.deviceUsedAddresses.map({ $0.hex }), forKey: "usedAddresses")
                    
                    // 设备、组、场景可分配地址
                    let allocatedUnicastRange = provisioner.allocatedUnicastRange.map({
                        ["lowAddress": $0.lowAddress.hex, "highAddress": $0.highAddress.hex]
                    })
                    provisionerJson.updateValue(allocatedUnicastRange, forKey: "allocatedUnicastRange")
                    
                    let allocatedGroupRange = provisioner.allocatedGroupRange.map({
                        ["lowAddress": $0.lowAddress.hex, "highAddress": $0.highAddress.hex]
                    })
                    
                    provisionerJson.updateValue(allocatedGroupRange, forKey: "allocatedGroupRange")
                    
                    let allocatedSceneRange = provisioner.allocatedSceneRange.map({
                        ["lowAddress": $0.firstScene.hex, "highAddress": $0.lastScene.hex]
                    })
                    provisionerJson.updateValue(allocatedSceneRange, forKey: "allocatedSceneRange")
                    
                    siteJsonData.updateValue(provisionerJson, forKey: "provisioner")
                }
                
                // 废弃的设备地址
                let exclusions = meshNetwork.getNetworkExclusionAddresses()
                let exclusionsData = exclusions.compactMap({
                    if $0.addresses.count > 0 {
                        return ["ivIndex": $0.ivIndex, "addresses": $0.addresses.map({ $0.hex })]
                    }
                    return nil
                })
                siteJsonData.updateValue(exclusionsData, forKey: "exclusions")
             
                
        //        var exportSpaces: [SpaceData] = []
                continuation.resume(returning: siteJsonData)
//                return siteJsonData
                
//            }
        }
        
        if spaceIds != nil {
            let exportSpaces = self.spaces.filter({ space in spaceIds!.contains(where: { $0 == space.id }) })
            var spaceDicts: [[String: Any]] = []
            
            await withTaskGroup(of: [String: Any]?.self) { group in
                for space in exportSpaces {
                    group.addTask {
                        // 异步处理每个数据
                        return await space.export()
                    }
                }
                // 收集结果
                for await spaceData in group {
                    if let spaceData = spaceData {
                        spaceDicts.append(spaceData)
                    }
                }
            }
            siteData.updateValue(spaceDicts, forKey: "spaces")
        }else {
            siteData.updateValue(self.spaces.count > 0 ? [[:]] : [], forKey: "spaces")
        }
        return siteData
      
    }
}

extension SpaceData {
    
    /// 导出space数据
    func export() async -> [String: Any]  {
       
        return await withCheckedContinuation { continuation in
            
            var spaceJsonData: [String: Any] = [:]
            
//            guard let meshNetworkManager = MeshNetworkManager.loadMeshNetwork(meshUUID: meshUUID, subnetworkId: self.meshNetworkId) else {
//                continuation.resume(returning: spaceJsonData)
//                return
//            }
            guard let meshNetwork = MeshNetwork.load(meshUUID: meshUUID, subnetworkId: self.meshNetworkId) else {
                continuation.resume(returning: spaceJsonData)
                return
            }
            let switchs = DeviceSwitchData.load(meshUUID: meshUUID, meshNetworkId: self.meshNetworkId)
//            meshNetworkManager.switchs = DeviceSwitchData.load(meshUUID: meshUUID, meshNetworkId: self.meshNetworkId)
            // SigMesh + SunSmart扩展数据
            let schedules = Schedule.load(meshUUID: meshUUID, meshNetworkId: self.meshNetworkId)
            meshNetwork.groups.forEach({ group in
                group.info = GroupInfo.load(meshUUID: meshUUID, address: group.address.address) ?? GroupInfo(address: group.address.address)
                
                let bindSchedules = schedules.filter({ schedule in
                    schedule.groups.contains(where: { $0.address == group.address }) ||
                    schedule.needDeleteGroups.contains(where: { $0.address == group.address }) ||
                    (schedule.scene?.info.groups.contains(where: { $0.address == group.address }) ?? false)
                })
                group.info.bindSchedules = bindSchedules
            })
            meshNetwork.scenes.forEach({
                $0.info = SceneInfo.load(meshUUID: meshUUID, sceneId: $0.number) ?? SceneInfo(sceneId: $0.number)
            })
            
            spaceJsonData.updateValue(self.id, forKey: "uuid")
            spaceJsonData.updateValue(self.name, forKey: "spaceName")
            spaceJsonData.updateValue(self.imageId, forKey: "imageId")
            spaceJsonData.updateValue(self.sourceType.rawValue, forKey: "source")
//            spaceJsonData.updateValue(self.isFavourite, forKey: "favourite")
            spaceJsonData.updateValue(Int64(self.create) , forKey: "createTimestamp")
            spaceJsonData.updateValue(Int64(self.lastUpdate) , forKey: "updateTimestamp")
            
            
            let networkKey = meshNetwork.networkKeys.first(where: { $0.networkId.hex == self.meshNetworkId })
            let appKey = meshNetwork.applicationKeys.first(where: { $0.boundNetworkKeyIndex == networkKey?.index })
            
            if let data = try? jsonEncoder.encode(networkKey), let networkKeyDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                spaceJsonData.updateValue(networkKeyDict, forKey: "netKey")
            }
            if let data = try? jsonEncoder.encode(appKey), let appKeyDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                spaceJsonData.updateValue(appKeyDict, forKey: "appKey")
            }
            
            //        let networkKeyDict: [String: Any] = [
            //            "oldKey" : networkKey.oldKey?.hex ?? "00000000000000000000000000000000",
            //            "phase" : networkKey.phase.rawValue,
            //            "index" : networkKey.index,
            //            "key" : networkKey.key.hex,
            //            "timestamp" : Int64(networkKey.timestamp.timeIntervalSince1970),
            //            "minSecurity" : networkKey.minSecurity.rawValue,
            //            "name" : networkKey.name
            //        ]
            
            //        let appKey = meshNetworkManager.currentApplicationKey
            //        let appKeyDict: [String: Any] = [
            //            "oldKey" : appKey.oldKey?.hex ?? "00000000000000000000000000000000",
            //            "key" : appKey.key.hex,
            //            "name" : appKey.name,
            //            "boundNetKey" : appKey.boundNetworkKey.index,
            //            "index" : appKey.index
            //        ]
            
            //        spaceJsonData.updateValue(networkKeyDict, forKey: "netKey")
            //        spaceJsonData.updateValue(appKeyDict, forKey: "appKey")
            
            var nodeDicts: [[String: Any]] = []
            var groupDicts: [[String: Any]] = []
            var sceneDicts: [[String: Any]] = []
            var scheheduleDicts: [[String: Any]] = []
            
            let allNodes = meshNetwork.nodes.filter({!$0.isLocalProvisioner && !$0.isProvisioner && !$0.isConfigComplete })
            // 设备
            allNodes.filter({ !$0.isProvisioner }).forEach { node in
                if let data = try? jsonEncoder.encode(node), var nodeDict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] {
                    if let uuid = nodeDict["UUID"] as? String { // 修改UUID=>uuid提交服务器
                        nodeDict.updateValue(uuid, forKey: "uuid")
                        nodeDict.removeValue(forKey: "UUID")
                    }
                    nodeDict.updateValue(node.macAddress ?? "", forKey: "macAddress")
                    let types = node.sensorModels.compactMap({ node.sensorModelTypes[$0]?.id.hex })
                    nodeDict.updateValue(types, forKey: "sensorTypes")
                    nodeDict.updateValue(node.groupState.rawValue, forKey: "groupState")
                    if let group = node.group {
                        nodeDict.updateValue(group.address.address.hex, forKey: "groupAddress")
                    }
                    nodeDict.updateValue(node.versionSEQ, forKey: "versionSEQ")
                    nodeDict.updateValue(node.lightnessRange.lowerBound, forKey: "lightnessRangeMin")
                    nodeDict.updateValue(node.lightnessRange.upperBound, forKey: "lightnessRangeMax")
                    if let range = node.lightCTLTemperatureRange {
                        nodeDict.updateValue(range.lowerBound, forKey: "lightCTLTemperatureRangeMin")
                        nodeDict.updateValue(range.upperBound, forKey: "lightCTLTemperatureRangeMax")
                    }
                    if let state = node.powerUpState {
                        nodeDict.updateValue(state.rawValue, forKey: "powerUpState")
                    }
                    if let defaultLightness = node.defalutLightness {
                        nodeDict.updateValue(defaultLightness, forKey: "defaultLightness")
                    }
                    if let defaultCct = node.defaultCct {
                        nodeDict.updateValue(defaultCct, forKey: "defaultCct")
                    }
                    if let timezone = node.timezone {
                        nodeDict.updateValue(timezone.encodeToTzOffset(), forKey: "timezoneOffset")
                        nodeDict.updateValue(node.timestamp, forKey: "timestamp")
                    }
                    if let enOceanMacAddress = node.enOceanMacAddress {
                        nodeDict.updateValue(enOceanMacAddress, forKey: "enOceanMacAddress")
                        nodeDict.updateValue(node.enOceanKeySceneNumbers.map({ $0.hex }), forKey: "enOceanKeyScenes")
                        
                        if node.enOceanProxySwitchKeys.count > 0, let data = try? jsonEncoder.encode(node.enOceanProxySwitchKeys), let switchKeyDicts = try? JSONSerialization.jsonObject(with: data) as? [[String : Any]] {
                            nodeDict.updateValue(switchKeyDicts, forKey: "enOceanProxySwitchKeys")
                        }
                    }
                    
                    if let firmwareID = node.firmwareID {
                        nodeDict.updateValue(firmwareID.hex, forKey: "firmwareID")
                    }
                    if let distributionFirmwareID = node.distributionFirmwareID {
                        nodeDict.updateValue(distributionFirmwareID.hex, forKey: "distributionFirmwareID")
                    }
                    if let compositionHash = node.compositionHash {
                        nodeDict.updateValue(compositionHash, forKey: "compositionHash")
                    }
                    if let defaultTransitionTime = node.defaultTransitionTime {
                        nodeDict.updateValue(defaultTransitionTime.rawValue, forKey: "defaultTransitionTime")
                    }
                    
                    if let data = try? jsonEncoder.encode(node.sceneExecuteDatas), let scenesDatas = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        nodeDict.updateValue(scenesDatas, forKey: "scenesDatas")
                    }
                    //                                    let scenesDatas = node.sceneExecuteDatas.map({ data in
                    //                                        [
                    //                                            "sceneNumber" : data.sceneNumber,
                    //                                            "isOn" : data.isOn,
                    //                                            "lightness" : data.lightness,
                    //                                            "cct" : data.cct,
                    //                                            "hue" : data.hue,
                    //                                            "saturation" : data.saturation,
                    //                                            "state" : data.state
                    //                                        ]
                    //                                    })
                    //                                    nodeDict.updateValue(scenesDatas, forKey: "scenesDatas")
                    //                     .filter({ $0.value.isValid })
                    let scheduleDatas = node.schedulerActions.map { (key: Int, value: SchedulerRegistryEntry) in
                        [
                            "id" : key,
                            "year" : value.year.value,
                            "month" : value.month.value,
                            "day" : value.day.value,
                            "hour" : value.hour.value,
                            "minute" : value.minute.value,
                            "second" : value.second.value,
                            "dayOfWeek" : value.dayOfWeek.value,
                            "action" : value.action.rawValue,
                            "transitionTime" : Int(value.transitionTime.interval ?? 0),
                            "sceneNumber" : value.sceneNumber
                        ]
                    }
                    nodeDict.updateValue(scheduleDatas, forKey: "schedules")
                    
                    if let lightLCPropertyData = try? jsonEncoder.encode(node.lightLCProperty), let lightLCPropertyDict = try? JSONSerialization.jsonObject(with: lightLCPropertyData) as? [String : Any] {
                        nodeDict.updateValue(lightLCPropertyDict, forKey: "lightLCPropertys")
                    }
                    // 光感校准值
                    if node.sensorCalibrated, let daylightCalibrationValue = node.daylightCalibrationValue {
                        nodeDict.updateValue(daylightCalibrationValue, forKey: "daylightCalibrationValue")
                    }
                    // pwm频率
                    if let pwmFrequency = node.pwmFrequency {
                        nodeDict.updateValue(pwmFrequency, forKey: "pwmFrequency")
                    }
                    // 阶段功率
                    nodeDict.updateValue(node.phaseEnergyConsumptions.map({ ["percent": $0.percent, "power": $0.power] }), forKey: "ratedPowerPhases")
                    // 相对灵敏度
                    if let motionSensitivity = node.motionSensitivity {
                        nodeDict.updateValue(motionSensitivity, forKey: "motionSensitivity")
                    }
                    // 灵敏度范围
                    if let motionSensitivityRange = node.motionSensitivityRange {
                        nodeDict.updateValue(motionSensitivityRange.lowerBound, forKey: "motionSensitivityRangeMin")
                        nodeDict.updateValue(motionSensitivityRange.upperBound, forKey: "motionSensitivityRangeMax")
                    }
                    // 邻近照明
                    nodeDict.updateValue(node.proximityLightingEnabled, forKey: "proximityLightingEnabled")
                    if let proximityLightingRelayCount = node.proximityLightingRelayCount {
                        nodeDict.updateValue(proximityLightingRelayCount, forKey: "proximityLightingRelayCount")
                    }
                    nodeDict.updateValue(node.proximityLightingNeighborAddresses, forKey: "proximityLightingNeighborAddresses")
                    
                    // 网关
                    if node.deviceType == .gateway {
                        // 设备真实网关数据
                        if let gatewaInfo = node.gatewayInfo,
                           let data = try? jsonEncoder.encode(gatewaInfo), let gatewayInfoDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            nodeDict.updateValue(gatewayInfoDict, forKey: "gatewayInfo")
                        }
                        // 预配置网关数据
                        if let mac = node.macAddress, let gatewayModel = node.gatewayModel ?? GatewayModel.load(siteId: siteId, macAddress: mac).first {
                            var gatewayPreconfigured: [String: Any] = [:]
                            gatewayPreconfigured.updateValue(gatewayModel.activate, forKey: "activate")
                            gatewayPreconfigured.updateValue(gatewayModel.associatedSpaces.map({ $0.id }), forKey: "associatedSpaces")
                            if let apn = gatewayModel.apn {
                                gatewayPreconfigured.updateValue(apn, forKey: "apn")
                            }
                            if let mqttServerInfo = gatewayModel.mqttServerInfo {
                                var mqttConnectInfo: [String: Any] = [:]
                                mqttConnectInfo.updateValue(mqttServerInfo.serverAddress, forKey: "serverAddress")
                                if let userName = mqttServerInfo.userName {
                                    mqttConnectInfo.updateValue(userName, forKey: "userName")
                                }
                                if let password = mqttServerInfo.password {
                                    mqttConnectInfo.updateValue(password, forKey: "password")
                                }
                                mqttConnectInfo.updateValue(mqttServerInfo.clientId, forKey: "clientId")
                                mqttConnectInfo.updateValue(mqttServerInfo.keepalive, forKey: "keepalive")
                                mqttConnectInfo.updateValue(mqttServerInfo.clearSession, forKey: "clearSession")
                                mqttConnectInfo.updateValue(mqttServerInfo.authMode.rawValue, forKey: "authMode")
                                mqttConnectInfo.updateValue(mqttServerInfo.sslVersion.rawValue, forKey: "sslVersion")
                                gatewayPreconfigured.updateValue(mqttConnectInfo, forKey: "mqttConnectInfo")
                            }
                            nodeDict.updateValue(gatewayPreconfigured, forKey: "gatewayPreconfigured")
                        }
                    }
                    nodeDicts.append(nodeDict)
                }
            }
            
            // 组
            // 真实组
            let realGroups = meshNetwork.groups.filter({ $0.address.address.isGroup && !$0.address.address.isSpecialGroup && !$0.isVirtual })
            // 虚拟组
            let virtualGroups = meshNetwork.groups.filter({ $0.address.address.isGroup && !$0.address.address.isSpecialGroup && $0.isVirtual })
            
            realGroups.forEach { group in
                if let data = try? jsonEncoder.encode(group), var groupDict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] {
                    groupDict.updateValue(group.info.imageId, forKey: "imageId")
                    groupDict.updateValue(group.isVirtual, forKey: "isVirtual")
                    if let imageText = group.info.imageText {
                        groupDict.updateValue(imageText, forKey: "imageText")
                    }
                    let profile = group.info.profile
                    let lightData = profile.lightData.data
                    var profileDict: [String: Any] = [
                        "id": profile.id,
                        "type": profile.type.rawValue,
                        "highEndTrim": lightData.highEndTrim,
                        "lowEndTrim": lightData.lowEndTrim,
                        "occupancyLevel": lightData.occupancyLevel,
                        "vacantLevel": lightData.vacantLevel,
                        "taskLevel": lightData.taskLevel,
                        "autoMinLevel": lightData.autoMinLevelEnabled ? lightData.autoMinLevel : 255, 
                        "timeT1": lightData.t1,
                        "timeT2": lightData.t2,
                        "timeT3": lightData.t3,
                        "timeT4": lightData.t4,
                        "timeT5": lightData.t5,
                        "manualOverrideTimeout": profile.manualOverrideTimeout,
                        "powerUpState": profile.powerUpState.rawValue,
                        "powerOnCct": profile.powerUpCct,
                        "adjustSpeed": profile.adjustSpeed
                    ]
                    if profile.type == .proximityLighting {
                        profileDict.updateValue(profile.proximityLightingNumber, forKey: "proximityLightingNumber")
                    }
                    profileDict.updateValue(profile.sensitivity, forKey: "relativeSensitivity")
                    groupDict.updateValue(profileDict, forKey: "profile")
                    
                    
                    if let sensorNode = group.info.ambientLightSensorNode {
                        groupDict.updateValue(sensorNode.primaryUnicastAddress.hex, forKey: "daylightSensorAddress")
                    }
                    if let scenesDatas = try? jsonEncoder.encode(group.info.sceneExecuteDatas), let scenesDicts = try? JSONSerialization.jsonObject(with: scenesDatas) as? [[String : Any]] {
                        groupDict.updateValue(scenesDicts, forKey: "scenesDatas")
                    }
                    
                    // 临近照明
                    if let proximityLightingPath = group.info.proximityLightingPath {
                        
                        let pathDicts = proximityLightingPath.paths.map({ path in
                            ["items": path.items.map({ Int($0.address ?? 0) })]
                        })
                        let zoneDicts = proximityLightingPath.zones.map({ zone in
                            ["addresses": zone.addresses.map({ Int($0) })]
                        })
                        groupDict.updateValue(["paths": pathDicts, "zones": zoneDicts], forKey: "proximityLightingPath")
                    }
                    
                    groupDicts.append(groupDict)
                }
            }
            
            // 虚拟组
            virtualGroups.forEach { group in
                if let data = try? jsonEncoder.encode(group), var groupDict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] {
                    groupDict.updateValue(group.isVirtual, forKey: "isVirtual")
                    groupDicts.append(groupDict)
                }
            }
            
            // 动能开关
            let switcheDicts = switchs.map { switchData in
                var dict = [
                    "id" : switchData.id,
                    "name" : switchData.name,
                    "enabled" : switchData.enabled,
                    "panelType" : switchData.panelType.rawValue,
                ]
                if let sceneA = switchData.sceneANumber {
                    dict.updateValue(sceneA.hex, forKey: "sceneA")
                }
                if let sceneB = switchData.sceneBNumber {
                    dict.updateValue(sceneB.hex, forKey: "sceneB")
                }
                if let sceneC = switchData.sceneCNumber {
                    dict.updateValue(sceneC.hex, forKey: "sceneC")
                }
                if let sceneD = switchData.sceneDNumber {
                    dict.updateValue(sceneD.hex, forKey: "sceneD")
                }
                if let proxyNodeAddress = switchData.proxyNodeAddress {
                    dict.updateValue(proxyNodeAddress.hex, forKey: "proxyNodeAddress")
                }
                if let deleteProxyNodeAddress = switchData.deleteProxyNodeAddress {
                    dict.updateValue(deleteProxyNodeAddress.hex, forKey: "deleteProxyNodeAddress")
                }
                
                if let linkGroupAddress = switchData.linkGroupAddress {
                    dict.updateValue(linkGroupAddress.hex, forKey: "linkGroupAddress")
                }
                if let subLinkGroupAddress = switchData.subLinkGroupAddress {
                    dict.updateValue(subLinkGroupAddress.hex, forKey: "subLinkGroupAddress")
                }
                let bindGroupAddresses = switchData.bindGroupAddresses.map({ $0.hex })
                dict.updateValue(bindGroupAddresses, forKey: "bindGroupAddresses")
                
                let unbindGroupAddresses = switchData.unbindGroupAddresses.map({ $0.hex })
                dict.updateValue(unbindGroupAddresses, forKey: "unbindGroupAddresses")
                
                if let enOceanMacAddress = switchData.enOceanMacAddress {
                    dict.updateValue(enOceanMacAddress, forKey: "enOceanMacAddress")
                }
                if let enOceanSecurityKey = switchData.enOceanSecurityKey {
                    dict.updateValue(enOceanSecurityKey, forKey: "enOceanSecurityKey")
                }
                
                return dict
            }

            // 场景
            meshNetwork.scenes.forEach { scene in
                sceneDicts.append(["number": scene.number.hex, "name": scene.name, "imageId": scene.info.imageId])
            }
            
            // 日程
            if let data = try? jsonEncoder.encode(schedules), let schedules = try? JSONSerialization.jsonObject(with: data) as? [[String : Any]] {
                scheheduleDicts = schedules
            }
            
            // IVIndex
//            meshNetworkManager.meshNetwork.networkExclusions
            
            spaceJsonData.updateValue(nodeDicts, forKey: "nodes")
            spaceJsonData.updateValue(groupDicts, forKey: "groups")
            spaceJsonData.updateValue(switcheDicts, forKey: "switches")
            spaceJsonData.updateValue(sceneDicts, forKey: "scenes")
            spaceJsonData.updateValue(scheheduleDicts, forKey: "schedules")
            continuation.resume(returning: spaceJsonData)
        }
    }
    
}
