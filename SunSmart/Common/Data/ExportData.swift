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
                
                // 已使用的地址
                
                
                
        //        var exportSpaces: [SpaceData] = []
                continuation.resume(returning: siteJsonData)
//                return siteJsonData
                
//            }
        }
        
        if spaceIds != nil {
            var exportSpaces = self.spaces.filter({ space in spaceIds!.contains(where: { $0 == space.id }) })
            var spaceDicts: [[String: Any]] = []
            
            while let data = await exportSpaces.first?.export() {
                exportSpaces.remove(at: 0)
                spaceDicts.append(data)
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
            
            guard let meshNetworkManager = MeshNetworkManager.loadMeshNetwork(meshUUID: meshUUID, subnetworkId: self.meshNetworkId) else {
                continuation.resume(returning: spaceJsonData)
                return
            }
            meshNetworkManager.switchs = DeviceSwitchData.load(meshUUID: meshUUID, meshNetworkId: self.meshNetworkId)
            // SigMesh + SunSmart扩展数据
            meshNetworkManager.schedules = Schedule.load(meshUUID: meshUUID, meshNetworkId: self.meshNetworkId)
            meshNetworkManager.groups.forEach({ group in
                group.info = GroupInfo.load(meshUUID: meshUUID, address: group.address.address) ?? GroupInfo(address: group.address.address)
                
                let bindSchedules = meshNetworkManager.schedules.filter({ schedule in
                    schedule.groups.contains(where: { $0.address == group.address }) ||
                    schedule.needDeleteGroups.contains(where: { $0.address == group.address }) ||
                    (schedule.scene?.info.groups.contains(where: { $0.address == group.address }) ?? false)
                })
                group.info.bindSchedules = bindSchedules
            })
            meshNetworkManager.scenes.forEach({
                $0.info = SceneInfo.load(meshUUID: meshUUID, sceneId: $0.number) ?? SceneInfo(sceneId: $0.number)
            })
            
            spaceJsonData.updateValue(self.id, forKey: "uuid")
            spaceJsonData.updateValue(self.name, forKey: "spaceName")
            spaceJsonData.updateValue(self.imageId, forKey: "imageId")
            spaceJsonData.updateValue(self.sourceType.rawValue, forKey: "source")
//            spaceJsonData.updateValue(self.isFavourite, forKey: "favourite")
            spaceJsonData.updateValue(Int64(self.create) , forKey: "createTimestamp")
            spaceJsonData.updateValue(Int64(self.lastUpdate) , forKey: "updateTimestamp")
            
            
            let networkKey = meshNetworkManager.meshNetwork?.networkKeys.first(where: { $0.networkId.hex == self.meshNetworkId })
            let appKey = meshNetworkManager.meshNetwork?.applicationKeys.first(where: { $0.boundNetworkKeyIndex == networkKey?.index })
            
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
            
            // 设备
            meshNetworkManager.realNodes.forEach { node in
                if let data = try? jsonEncoder.encode(node), var nodeDict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] {
                    if let uuid = nodeDict["UUID"] as? String { // 修改UUID=>uuid提交服务器
                        nodeDict.updateValue(uuid, forKey: "uuid")
                        nodeDict.removeValue(forKey: "UUID")
                    }
                    nodeDict.updateValue(node.macAddress ?? "", forKey: "macAddress")
                    let types = node.sensorModels.compactMap({ node.sensorModelTypes[$0]?.id.hex })
                    nodeDict.updateValue(types, forKey: "sensorTypes")
                    nodeDict.updateValue(node.groupState.rawValue, forKey: "groupState")
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
                    if let timezone = node.timezone {
                        nodeDict.updateValue(timezone.encodeToTzOffset(), forKey: "timezoneOffset")
                        nodeDict.updateValue(node.timestamp, forKey: "timestamp")
                    }
                    if let enOceanMacAddress = node.enOceanMacAddress {
                        nodeDict.updateValue(enOceanMacAddress, forKey: "enOceanMacAddress")
                        nodeDict.updateValue(node.enOceanKeySceneNumbers.map({ $0.hex }), forKey: "enOceanKeyScenes")
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
                    nodeDicts.append(nodeDict)
                }
            }
            
            // 组
            meshNetworkManager.groups.forEach { group in
                if let data = try? jsonEncoder.encode(group), var groupDict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] {
                    groupDict.updateValue(group.info.imageId, forKey: "imageId")
                    groupDict.updateValue(group.isVirtual, forKey: "isVirtual")
                    if let imageText = group.info.imageText {
                        groupDict.updateValue(imageText, forKey: "imageText")
                    }
                    let profile = group.info.profile
                    let lightData = profile.lightData.data
                    let profileDict: [String: Any] = [
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
                        "adjustSpeed": profile.adjustSpeed
                    ]
                    groupDict.updateValue(profileDict, forKey: "profile")
                    if let sensorNode = group.info.ambientLightSensorNode {
                        groupDict.updateValue(sensorNode.primaryUnicastAddress.hex, forKey: "daylightSensorAddress")
                    }
                    if let scenesDatas = try? jsonEncoder.encode(group.info.sceneExecuteDatas), let scenesDicts = try? JSONSerialization.jsonObject(with: scenesDatas) as? [[String : Any]] {
                        groupDict.updateValue(scenesDicts, forKey: "scenesDatas")
                    }
                    groupDicts.append(groupDict)
                }
            }
            
            // 虚拟组
            meshNetworkManager.virtualGroups.forEach { group in
                if let data = try? jsonEncoder.encode(group), var groupDict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] {
                    groupDict.updateValue(group.isVirtual, forKey: "isVirtual")
                    groupDicts.append(groupDict)
                }
            }
            
            // 动能开关
            let switcheDicts = meshNetworkManager.switchs.map { switchData in
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
                if let proxyNodeAddress = switchData.proxyNodeAddress {
                    dict.updateValue(proxyNodeAddress.hex, forKey: "proxyNodeAddress")
                }
                if let deleteProxyNodeAddress = switchData.deleteProxyNodeAddress {
                    dict.updateValue(deleteProxyNodeAddress.hex, forKey: "deleteProxyNodeAddress")
                }
                
                if let linkGroupAddress = switchData.linkGroupAddress {
                    dict.updateValue(linkGroupAddress.hex, forKey: "linkGroupAddress")
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
            meshNetworkManager.scenes.forEach { scene in
                sceneDicts.append(["number": scene.number.hex, "name": scene.name, "imageId": scene.info.imageId])
            }
            
            // 日程
            if let data = try? jsonEncoder.encode(meshNetworkManager.schedules), let schedules = try? JSONSerialization.jsonObject(with: data) as? [[String : Any]] {
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
