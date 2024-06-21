//
//  ImportData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/23.
//

import Foundation
import NordicSigMeshSDK
import SwiftyJSON

private var jsonDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

extension SiteData {
    
    /// 导入site数据
    /// - Parameters:
    ///   - siteJsonData: site json数据
    /// - Returns: site
    static func `import`(siteJsonData: [String: Any]) async -> SiteData? {
        
        let json = JSON(siteJsonData)
        guard let uuid = json["uuid"].string,
              let name = json["siteName"].string else {
            return nil
        }
        var site = SiteData.load(siteId: uuid)
        if site == nil {
            var permission: Permission = .visitor
            switch json["role"].string {
            case "owner":
                permission = .owner
            case "editor":
                permission = .editor
            default:
                break
            }
            site = SiteData(id: uuid, meshUUID: uuid, name: name, type: .init(rawValue: json["type"].intValue) ?? .office, permission: permission, create: json["createTimestamp"].int64Value, lastUpdate: json["updateTimestamp"].int64Value, isFavourite: false, sourceType: .create)
        }
        await site?.update(siteJsonData: siteJsonData)
        
        return site
    }
    
    
    /// 更新数据
    /// - Parameter siteJsonData: site数据
    func update(siteJsonData: [String: Any]) async {
        
        let json = JSON(siteJsonData)
        guard let uuid = json["uuid"].string,
              let name = json["siteName"].string else {
            return
        }
        let lastUpdate = json["updateTimestamp"].int64Value
        // 服务器最后更新时间比本地时间新才覆盖本地数据
        guard lastUpdate >= self.lastUpdate else {
            return
        }
        
        self.name = name
        self.imageId = json["imageId"].intValue
        self.isFavourite = json["favourite"].boolValue
        self.sourceType = DataSourceType(rawValue: json["type"].intValue) ?? DataSourceType.create
        self.create = json["createTimestamp"].int64Value
        self.lastUpdate = json["updateTimestamp"].int64Value
        if self.lastUploadCloudTimestamp == nil {
            self.lastUploadCloudTimestamp = self.lastUpdate
        }
        
        var meshNetwork = MeshNetwork.load(meshUUID: uuid, allData: false)
        
        if meshNetwork == nil {
            guard let netKeyDict = json["netKey"].dictionaryObject,
                  let netKeyData = try? JSONSerialization.data(withJSONObject: netKeyDict),
                  let netKey = try? jsonDecoder.decode(NetworkKey.self, from: netKeyData),
                  let appKeyDict = json["appKey"].dictionaryObject,
                  let appKeyData = try? JSONSerialization.data(withJSONObject: appKeyDict),
                  let appKey = try? jsonDecoder.decode(ApplicationKey.self, from: appKeyData) else {
                return
            }
            meshNetwork = MeshNetworkManager.createMeshNetwork(meshUUID: uuid, meshNetworkName: name).meshNetwork
            meshNetwork?.add(networkKey: netKey)
            meshNetwork?.add(applicationKey: appKey)
            meshNetwork?.save()
        }
        // TODO: Local Provisioner
        
        if var spaceDicts = json["spaces"].arrayObject as? [[String: Any]] {
            var spaces: [SpaceData] = []
            while let dict = spaceDicts.first {
                if let space = await SpaceData.import(siteId: uuid, spaceJsonData: dict) {
                    spaceDicts.remove(at: 0)
                    spaces.append(space)
                }
            }
            self.spaces = spaces
            self.spaceCount = nil
        }else {
            self.spaceCount = json["spaceCount"].int
        }
        self.save()
    }
    
    
}

extension SpaceData {
    
    /// 导入space数据
    /// - Parameters:
    ///   - siteId: 所属site id
    ///   - spaceJsonData: space数据
    /// - Returns: space
    static func `import`(siteId: String, spaceJsonData: [String: Any]) async -> SpaceData? {
        
//       return await withCheckedContinuation { continuation in
            let json = JSON(spaceJsonData)
            guard let uuid = json["uuid"].string,
                  let name = json["spaceName"].string else {
                return nil
            }
            
            var space = SpaceData.load(siteId: siteId, spaceId: uuid).first
            if space == nil{
                guard let netKeyDict = json["netKey"].dictionaryObject,
                      let netKeyData = try? JSONSerialization.data(withJSONObject: netKeyDict),
                      let netKey = try? jsonDecoder.decode(NetworkKey.self, from: netKeyData),
                      let appKeyDict = json["appKey"].dictionaryObject,
                      let appKeyData = try? JSONSerialization.data(withJSONObject: appKeyDict),
                      let appKey = try? jsonDecoder.decode(ApplicationKey.self, from: appKeyData),
                      let meshNetwork = MeshNetwork.load(meshUUID: siteId, allData: false) else {
//                    continuation.resume(returning: nil)
                    return nil
                }
                
                if !meshNetwork.networkKeys.contains(where: { $0.index == netKey.index }) {
                    meshNetwork.add(networkKey: netKey)
                    meshNetwork.add(applicationKey: appKey)
                    meshNetwork.save()
                }
                
                var permission: Permission = .visitor
                if json["role"].string == "owner" {
                    permission = .owner
                }
                
                let newSpace = SpaceData(name: name, id: uuid, siteId: siteId, imageId: 0, create: json["createTimestamp"].int64Value, lastUpdate: json["updateTimestamp"].int64Value, isFavourite: false, permission: permission, sourceType: .share, meshUUID: siteId, meshNetworkId: netKey.networkId.hex)
                space = newSpace
            }
//            Task {
                await space?.update(spaceJsonData: spaceJsonData)
//                continuation.resume(returning: space)
//            }
            return space
//        }
    }
 
    /// 更新空间内基本数据+设备、组、场景、日程
    /// - Parameter spaceJsonData: 空间数据
    func update(spaceJsonData: [String: Any]) async {
        await withCheckedContinuation { continuation in
            let json = JSON(spaceJsonData)
            guard json["uuid"].string == self.id,
                  //              let netKeyDict = json["netKey"].dictionary,
                  //              let appKeyDict = json["appKey"].dictionary,
                    let nodeDicts = json["nodes"].arrayObject as? [[String: Any]],
                  let groupDicts = json["groups"].arrayObject as? [[String: Any]],
                  let sceneDicts = json["scenes"].arrayObject as? [[String: Any]],
                  let scheduleDicts = json["schedules"].arrayObject as? [[String: Any]] else {
//                return
                continuation.resume()
                return
            }
            
            let lastUpdate = json["updateTimestamp"].int64Value
            // 服务器最后更新时间比本地时间新才覆盖本地数据
            guard lastUpdate >= self.lastUpdate else {
//                return
                continuation.resume()
                return
            }
            
            let meshUUID = self.meshUUID
            
            var meshNetwork: MeshNetwork?
            if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == meshUUID && MeshNetworkManager.instance.currentNetworkKey.networkId.hex == self.meshNetworkId {
                meshNetwork = MeshNetworkManager.instance.meshNetwork
            }else {
                meshNetwork = MeshNetwork.load(meshUUID: meshUUID, subnetworkId: self.meshNetworkId)
            }
            guard let network = meshNetwork else { return }
            
            self.name = json["spaceName"].stringValue
            self.imageId = json["imageId"].intValue
            self.sourceType = .init(rawValue: json["source"].intValue) ?? .create
            self.isFavourite = json["favourite"].boolValue
            self.create = json["createTimestamp"].int64Value
            self.lastUpdate = json["updateTimestamp"].int64Value
            if self.lastUploadCloudTimestamp == nil {
                self.lastUploadCloudTimestamp = self.lastUpdate
            }
            
            if self.state == .waitDeleted {
                self.state = .normal
            }
            
            let localNodes = Node.load(meshUUID: self.meshUUID, subnetworkId: self.meshNetworkId)
            
            network.nodes.filter({ !$0.isLocalProvisioner }).forEach { node in
                network.remove(node: node)
            }
            // 设备
            let nodes = nodeDicts.compactMap { nodeDict in
                if let data = try? JSONSerialization.data(withJSONObject: nodeDict), var node = try? jsonDecoder.decode(Node.self, from: data) {
                    let nodeJson = JSON(nodeDict)
                    if let version = nodeJson["versionSEQ"].uInt32 {
                        node.versionSEQ = version
                    }
                    if let localNode = localNodes.first(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) {
                        // 判断本地缓存比线上节点版本高则使用本地节点数据
                        if localNode.versionSEQ > node.versionSEQ {
                            return localNode
                        }
                        node = localNode
                    }
                    
                    node.macAddress = nodeJson["macAddress"].string
                    if let sensorTypes = nodeJson["sensorTypes"].arrayObject as? [String] {
                        let propertys = sensorTypes.map({ DeviceProperty(UInt16(hex: $0) ?? 0) })
                        for index in 0..<propertys.count {
                            if index < node.sensorModels.count {
                                node.sensorModelTypes.updateValue(propertys[index], forKey: node.sensorModels[index])
                            }
                        }
                    }
                    if let state = nodeJson["groupState"].int {
                        node.groupState = Node.GroupState(rawValue: state) ?? .none
                    }
                    if let min = nodeJson["lightnessRangeMin"].uInt16, let max = nodeJson["lightnessRangeMax"].uInt16 {
                        node.lightnessRange = min...max
                    }
                    if let min = nodeJson["lightCTLTemperatureRangeMin"].uInt16, let max = nodeJson["lightCTLTemperatureRangeMax"].uInt16 {
                        node.lightCTLTemperatureRange = min...max
                    }
                    if let powerUpState = nodeJson["powerUpState"].uInt8 {
                        node.powerUpState = OnPowerUp(rawValue: powerUpState)
                    }
                    if let defalutLightness = nodeJson["defalutLightness"].uInt16 {
                        node.defalutLightness = defalutLightness
                    }
                    if let timezoneOffset = nodeJson["timezoneOffset"].uInt8, let timestamp = nodeJson["timestamp"].uInt64 {
                        node.timezone = timezoneOffset.decodeFromTzOffset()
                        node.timestamp = timestamp
                    }
                    if let enOceanMacAddress = nodeJson["enOceanMacAddress"].string, let enOceanKeyScenes = nodeJson["enOceanKeyScenes"].arrayObject as? [String] {
                        node.enOceanMacAddress = enOceanMacAddress
                        node.enOceanKeySceneNumbers = enOceanKeyScenes.map({ SceneNumber(hex: $0) ?? 0 })
                    }
                    if let sceneDataDicts = nodeJson["scenesDatas"].arrayObject,
                       let data = try? JSONSerialization.data(withJSONObject: sceneDataDicts),
                       let sceneExecuteDatas = try? jsonDecoder.decode([SceneExecuteData].self, from: data) {
                        node.sceneExecuteDatas = sceneExecuteDatas
                    }
                    if let scheduleDicts = nodeJson["schedules"].arrayObject as? [[String: Any]] {
                        
                        scheduleDicts.forEach { dict in
                            let scheduleJson = JSON(dict)
                            if let id = scheduleJson["id"].int {
                                let dayOfWeek = Schedule.getWeekDays(weekValue: scheduleJson["dayOfWeek"].int ?? 0)
                                let entry = SchedulerRegistryEntry(year: .any(), month: .any(of: Schedule.allMonths), day: .specific(day: scheduleJson["day"].int ?? 0), hour: .specific(hour: scheduleJson["hour"].int ?? 0), minute: .specific(minute: scheduleJson["minute"].int ?? 0), second: .specific(second: scheduleJson["second"].int ?? 0), dayOfWeek: .any(of: dayOfWeek), action: SchedulerAction(rawValue: scheduleJson["action"].uInt8 ?? 0x0F) ?? .noAction, transitionTime: .init(rawValue: scheduleJson["transitionTime"].uInt8 ?? 0), sceneNumber: scheduleJson["sceneNumber"].uInt16 ?? 0)
                                node.schedulerActions.updateValue(entry, forKey: id)
                            }
                        }
                        node.scheduleIds = node.schedulerActions.map({ $0.key })
                    }
                    
                    if let lightLCPropertyDict = nodeJson["lightLCPropertys"].dictionaryObject,
                       let lightLCPropertyData = try? JSONSerialization.data(withJSONObject: lightLCPropertyDict),
                       let lightLCProperty = try? jsonDecoder.decode(LightLCProperty.self, from: lightLCPropertyData)  {
                        node.lightLCProperty = lightLCProperty
                    }
                    return node
                }
                return nil
            }
            nodes.forEach({
                try? network.add(node: $0)
            })
            
            
            while network.scenes.count > 0 {
                network.forceRemove(scene: network.scenes.first!.number)
            }
            // 场景
            let scenes = sceneDicts.compactMap { sceneDict in
                let sceneJson = JSON(sceneDict)
                if let sceneNumberHex = sceneJson["number"].string, let sceneNumber = SceneNumber(sceneNumberHex), let name = sceneJson["name"].string {
                    let scene = Scene(sceneNumber, name: name)
                    let existNodes = nodes.filter({ $0.sceneExecuteDatas.contains(where: { $0.sceneNumber == sceneNumber }) })
                    existNodes.forEach({
                        scene.add(address: $0.primaryUnicastAddress)
                    })
                    network.add(scene: scene)
                    scene.info = .init(sceneId: sceneNumber, imageId: sceneJson["imageId"].int ?? 0)
                    scene.info.save(meshUUID: meshUUID, subnetworkId: self.meshNetworkId)
                    
                    return scene
                }
                return nil
            }
            
            // 日程
            Schedule.deleteAll(meshUUID: meshUUID, meshNetworkId: self.meshNetworkId)
            var schedules: [Schedule] = []
            if let data = try? JSONSerialization.data(withJSONObject: scheduleDicts), let list = try? jsonDecoder.decode([Schedule].self, from: data) {
                schedules = list
            }
            if meshUUID == MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
                MeshNetworkManager.instance.schedules = schedules
            }
            schedules.forEach({
                $0.save(meshUUID: meshUUID, meshNetworkId: self.meshNetworkId)
            })
            
            // 组
            // TODO: 需判断是否业务组
            while network.groups.count > 0 {
                let group = network.groups.first!
                //            try? network.remove(group: group)
                network.forceRemove(group: group)
                group.deleteExtension()
            }
            
            // 按键
            var switches: [GroupSwitch] = []
            
            let groups = groupDicts.compactMap { groupDict in
                if let data = try? JSONSerialization.data(withJSONObject: groupDict), let group = try? jsonDecoder.decode(Group.self, from: data) {
                    let groupJson = JSON(groupDict)
                    group.info = GroupInfo(address: group.address.address, imageId: groupJson["imageId"].int ?? 1, imageText: groupJson["imageText"].string)
                    // profile
                    if let profileDict = groupJson["profile"].dictionaryObject {
                        let profileJson = JSON(profileDict)
                        if let id = profileJson["id"].string, let type = Profile.ProfileType(rawValue: profileJson["type"].int ?? 0) {
                            
                            let lightData = Profile.LightData(profileType: type, highEndTrim: profileJson["highEndTrim"].int ?? 100, lowEndTrim: profileJson["lowEndTrim"].int ?? 0, occupancyLevel: profileJson["occupancyLevel"].int ?? 100, vacantLevel: profileJson["vacantLevel"].int ?? 50, taskLevel: profileJson["taskLevel"].int ?? 100, autoMinLevel: profileJson["autoMinLevel"].int ?? 0, t1: profileJson["timeT1"].int ?? 0, t2: profileJson["timeT2"].int ?? 0, t3: profileJson["timeT3"].int ?? 0, t4: profileJson["timeT4"].int ?? 0, t5: profileJson["timeT5"].int ?? 0)
                            
                            let profile = Profile(id: id, type: type, lightData: lightData, powerUpState: Profile.PowerUpState(rawValue: profileJson["powerUpState"].uInt8 ?? 0), manualOverrideTimeout: profileJson["manualOverrideTimeout"].uInt32 ?? 600)
                            profile.adjustSpeed = profileJson["adjustSpeed"].int ?? 50
                            group.info.profile = profile
                        }
                    }
                    // 选择的光照传感器
                    if let sensorAddressHex = groupJson["daylightSensorAddress"].string,
                       let sensorAddress = Address(sensorAddressHex),
                       let sensorNode = nodes.first(where: { $0.primaryUnicastAddress == sensorAddress }) {
                        group.info.ambientLightSensorNode = sensorNode
                    }
                    // scenes data
                    if let sceneDicts = groupJson["scenesDatas"].arrayObject,
                       let data = try? JSONSerialization.data(withJSONObject: sceneDicts),
                       let sceneExecuteDatas = try? jsonDecoder.decode([SceneExecuteData].self, from: data) {
                        group.info.sceneExecuteDatas = sceneExecuteDatas
                    }
                    
                    // schedules
                    let bindSchedules = schedules.filter({ schedule in
                        schedule.groupAddresses.contains(group.address.address) ||
                        schedule.needDeleteGroupAddresses.contains(group.address.address) ||
                        group.info.sceneExecuteDatas.contains(where: { $0.sceneNumber == schedule.sceneNumber })
                    })
                    group.info.bindSchedules = bindSchedules
                    
                    // switches
                    if let switcheDicts = groupJson["switches"].arrayObject {
                        switcheDicts.forEach { switcheDict in
                            let switcheJson = JSON(switcheDict)
                            if let id = switcheJson["id"].string, let name = switcheJson["name"].string {
                                var sceneA: SceneNumber?
                                var sceneB: SceneNumber?
                                if let sceneAHex = switcheJson["sceneA"].string,
                                   let sceneANumber = SceneNumber(sceneAHex) {
                                    sceneA = sceneANumber
                                }
                                if let sceneBHex = switcheJson["sceneB"].string,
                                   let sceneBNumber = SceneNumber(sceneBHex) {
                                    sceneB = sceneBNumber
                                }
                                
                                var proxyNode: Node?
                                if let macAddress = switcheJson["enOceanMacAddress"].string {
                                    proxyNode = nodes.first(where: { $0.enOceanMacAddress == macAddress })
                                }
                                let groupSwitch = GroupSwitch(id: id, groupAddress: group.address.address, enabled: switcheJson["enabled"].bool ?? true, name: name, sceneANumber: sceneA, sceneBNumber: sceneB, proxyNodeAddress: proxyNode?.primaryUnicastAddress)
                                group.info.switchs.append(groupSwitch)
                                switches.append(groupSwitch)
                            }
                        }
                    }
                    return group
                }
                return nil
            }
            groups.forEach({
                try? network.add(group: $0)
                $0.saveExtension()
            })
            self.deviceCount = nodes.count
            self.luminairesCount = nodes.filter({ $0.lightnessModel != nil }).count
            self.groupCount = groups.count
            self.sceneCount = scenes.count
            self.scheheduleCount = schedules.count
            self.switchesCount = switches.filter({ $0.enOceanMacAddress != nil }).count
            self.save()
            continuation.resume()
        }
    }
    
}
