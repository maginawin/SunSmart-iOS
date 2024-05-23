//
//  ExportData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/23.
//

import Foundation
import NordicSigMeshSDK

enum ExportError: Error {
case noNetwork
case unknown
}

private var jsonEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .withoutEscapingSlashes
    return encoder
}

private var jsonDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

extension SpaceData {
    
    /// 导出space数据
    func export() -> [String: Any]  {
        
        var spaceJsonData: [String: Any] = [:]
        
        guard let meshNetworkManager = MeshNetworkManager.loadMeshNetwork(meshUUID: meshUUID, subnetworkId: self.meshNetworkId) else {
            return spaceJsonData
        }
        
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
        spaceJsonData.updateValue(self.name, forKey: "name")
        spaceJsonData.updateValue(self.imageId, forKey: "imageId")
        spaceJsonData.updateValue(self.sourceType.rawValue, forKey: "source")
        spaceJsonData.updateValue(self.isFavourite, forKey: "favourite")
        spaceJsonData.updateValue(Int64(self.create) ?? 0, forKey: "createTimestamp")
        spaceJsonData.updateValue(Int64(self.lastUpdate) ?? 0, forKey: "updateTimestamp")
        
        let networkKey = meshNetworkManager.currentNetworkKey
        let appKey = meshNetworkManager.currentApplicationKey
        
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
            if let data = try? JSONEncoder().encode(node), var nodeDict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] {
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
                if let defalutLightness = node.defalutLightness {
                    nodeDict.updateValue(defalutLightness, forKey: "defalutLightness")
                }
                if let timezone = node.timezone {
                    nodeDict.updateValue(timezone.encodeToTzOffset(), forKey: "timezoneOffset")
                    nodeDict.updateValue(node.timestamp, forKey: "timestamp")
                }
                if let enOceanMacAddress = node.enOceanMacAddress {
                    nodeDict.updateValue(enOceanMacAddress, forKey: "enOceanMacAddress")
                    nodeDict.updateValue(node.enOceanKeySceneNumbers.map({ $0.hex }), forKey: "enOceanKeyScenes")
                }
                let scenesDatas = node.sceneExecuteDatas.map({ data in
                    [
                        "sceneNumber" : data.sceneNumber,
                        "isOn" : data.isOn,
                        "lightness" : data.lightness,
                        "cct" : data.cct,
                        "hue" : data.hue,
                        "saturation" : data.saturation,
                        "state" : data.state
                    ]
                })
                nodeDict.updateValue(scenesDatas, forKey: "scenesDatas")
                // .filter({ $0.value.isValid })
                let scheduleDatas = node.schedulerActions.map { (key: Int, value: SchedulerRegistryEntry) in
                    [
                        "id" : key,
                        "year" : value.year.value,
                        "month" : value.month.value,
                        "day" : value.day.value,
                        "hour" : value.hour.value,
                        "minute" : value.minute.value,
                        "second" : value.second.value,
                        "dayOfWeek" : value.dayOfWeek,
                        "action" : value.action.rawValue,
                        "transitionTime" : value.transitionTime.interval ?? 0,
                        "sceneNumber" : value.sceneNumber
                    ]
                }
                nodeDict.updateValue(scheduleDatas, forKey: "schedules")
                
                if let lightLCPropertyData = try? JSONEncoder().encode(node.lightLCProperty), let lightLCPropertyDict = try? JSONSerialization.jsonObject(with: lightLCPropertyData) as? [String : Any] {
                    nodeDict.updateValue(lightLCPropertyDict, forKey: "lightLCPropertys")
                }
                nodeDicts.append(nodeDict)
            }
        }
        
        // 组
        meshNetworkManager.groups.forEach { group in
            if let data = try? JSONEncoder().encode(group), var groupDict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] {
                groupDict.updateValue(group.info.imageId, forKey: "imageId")
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
                if let scenesDatas = try? JSONEncoder().encode(group.info.sceneExecuteDatas), let scenesDicts = try? JSONSerialization.jsonObject(with: scenesDatas) as? [[String : Any]] {
                    groupDict.updateValue(scenesDicts, forKey: "scenesDatas")
                }
                
                let switcheDicts = group.info.switchs.map({ switchData in
                    var dict = [
                        "id" : switchData.id,
                        "name" : switchData.name,
                        "enabled" : switchData.enabled,
                        "panelType" : switchData.panelType.rawValue,
                    ]
                    if let sceneA = switchData.sceneA {
                        dict.updateValue(sceneA.number, forKey: "sceneA")
                    }
                    if let sceneB = switchData.sceneB {
                        dict.updateValue(sceneB.number, forKey: "sceneB")
                    }
                    if let macAddress = switchData.enOceanMacAddress {
                        dict.updateValue(macAddress, forKey: "enOceanMacAddress")
                    }
                    return dict
                })
                groupDict.updateValue(switcheDicts, forKey: "switches")
                groupDicts.append(groupDict)
            }
        }
        
        // 场景
        if let data = try? JSONEncoder().encode(meshNetworkManager.scenes), let scenes = try? JSONSerialization.jsonObject(with: data) as? [[String : Any]] {
            sceneDicts = scenes
        }
        
        // 日程
        if let data = try? JSONEncoder().encode(meshNetworkManager.schedules), let schedules = try? JSONSerialization.jsonObject(with: data) as? [[String : Any]] {
            scheheduleDicts = schedules
        }
        
        spaceJsonData.updateValue(nodeDicts, forKey: "nodes")
        spaceJsonData.updateValue(groupDicts, forKey: "groups")
        spaceJsonData.updateValue(sceneDicts, forKey: "scenes")
        spaceJsonData.updateValue(scheheduleDicts, forKey: "schedules")
        
        return spaceJsonData
    }
    
}
