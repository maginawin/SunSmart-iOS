//
//  MeshNetwork+SunSmart.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/18.
//

import Foundation
import NordicSigMeshSDK

public enum DataError: Error {
    /// 空间已超出最大范围
    case exceededMaxSpaces
    
}

extension SiteData {
    
    private struct AssociatedKey {
        static var meshManagerKey = 1
    }
    
    /// mesh网络管理
//    var meshManager: MeshNetworkManager? {
////        return MeshNetworkManager.loadMeshNetwork(meshUUID: meshUUID)
//        get {
//            guard let manager = objc_getAssociatedObject(self, &AssociatedKey.meshManagerKey) as? MeshNetworkManager else {
//                self.meshManager = MeshNetworkManager.loadMeshNetwork(meshUUID: meshUUID)
//                return self.meshManager
//            }
//           return manager
////            objc_getAssociatedObject(self, &AssociatedKey.meshManagerKey) as? MeshNetworkManager ?? MeshNetworkManager.loadMeshNetwork(meshUUID: meshUUID)
//        }set {
//            objc_setAssociatedObject(self, &AssociatedKey.meshManagerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
//        }
//    }
    
    /// 添加场所
    /// - Parameter name: 场所名称
    /// - Returns: 场所
    static func add(name: String) -> SiteData {
        let time = Int64(Date().timeIntervalSince1970)
        
        let id = UUID().uuidString
        _ = MeshNetworkManager.createMeshNetwork(meshUUID: id, meshNetworkName: name, localAddress: Address.minUnicastAddress)
//        MeshLibManager.manager.createMeshNetwork(meshUUID: id, meshNetworkName: name, connected: false)
        let site = SiteData(id: id, meshUUID: id, name: name, imageId: 1, type: .office, permission: .owner, create: time,isFavourite: false, sourceType: .create)
        site.localAddress = Address.minUnicastAddress
//        site.meshManager = meshManager
        site.save()
        return site
    }
    
    /// 场所添加空间
    /// - Parameters:
    ///   - name: 空间名称
    ///   - id: 空间id
    ///   - imageId: 空间图片id
    /// - Returns: 空间
    func addSpace(name: String, id: String = UUID().uuidString, imageId: Int = 1) -> SpaceData? {
        
        let time = Int64(Date().timeIntervalSince1970)
        
        let manager = MeshNetworkManager.loadMeshNetwork(meshUUID: meshUUID)
        guard let subnetworkData = manager?.addSubnetwork(networkKeyName: name, applicationKeyName: name) else {
            return nil
        }
//        self.meshManager = manager
        
        let space = SpaceData(name: name, id: id, siteId: self.id, imageId: imageId, create: time, isFavourite: false, permission: .owner, sourceType: .create, meshUUID: self.meshUUID, meshNetworkId: subnetworkData.networkKey.networkId.hex)
//        space.meshManager = self.meshManager
        addSpace(space)
        return space
    }
     
    /// 场所添加空间
    /// - Parameter space: 空间数据
    private func addSpace(_ space: SpaceData) {
        // 没有对应mesh网络时创建一个网络
//        if MeshNetworkManager.loadMeshNetwork(meshUUID: space.meshUUID) == nil {
//            /// 测试数据
//            var meshManager = MeshLibManager.manager.createMeshNetwork(meshUUID: space.meshUUID, meshNetworkName: space.name, connected: false)
//            if meshManager.realNodes.isEmpty {
//                let meshData = testMeshJsonDataString.data(using: .utf8)!
//                do {
//                    if var meshDict = try JSONSerialization.jsonObject(with: meshData) as? [String: Any] {
//                        meshDict.updateValue(space.meshUUID, forKey: "meshUUID")
//                        let setData = try JSONSerialization.data(withJSONObject: meshDict)
//                        _ = try meshManager.import(from: setData)
//                        _ = meshManager.save()
//                    }
//                } catch {
//                    
//                }
//            }
//        }
        // 生成editor密码
//        space.editorPassword = String.generateRandomNumberString()
        space.save()
        spaces.append(space)
        lastUpdate = Int64(Date().timeIntervalSince1970)
    }
    
    /// 克隆场所数据
    /// - Parameter save: 是否本地缓存
    func clone(_ save: Bool = false) -> SiteData {
        let siteData = self.cloneData()
        let spaces = self.spaces.map({ $0.clone() })
        siteData.spaces = spaces
        if save {
            siteData.save(allData: true)
        }
        return siteData
    }
    
    /// 删除场所数据+mesh网络
    @discardableResult func delete() -> Bool {
        
        MeshLibManager.manager.removeMeshNetwork(meshUUID: meshUUID)
        return self.deleteData()
    }
    
    /// 回收地址数据
    struct RecycleAddressData: Codable {
        
        /// 回收后剩余的地址结果
//        struct AddressResult {
//            /// 设备地址rangs
//            let allocatedUnicastRange: [AddressRange]
//            /// 组地址ranges
//            let allocatedGroupRange: [AddressRange]
//            /// 场景地址ranges
//            let allocatedSceneRange: [SceneRange]
//        }
        
        /// 设备地址list
        let deviceAddresses: [Int]
        /// 组地址list
        let groupAddresses: [Int]
        /// 场景地址list
        let sceneAddresses: [Int]
        /// 废弃地址list
        var exclusionAddresses: [ExclusionAddressData]?
        /// 回收地址后的provisioner数据
        var provisionerData: [String: Any]?
        
        var isEmpty: Bool {
            return deviceAddresses.isEmpty && groupAddresses.isEmpty && sceneAddresses.isEmpty && exclusionAddresses?.isEmpty ?? true
        }
        
        struct ExclusionAddressData: Codable {
            let ivIndex: Int
            let addresses: [Int]
        }
        
        init(deviceAddresses: [Int], groupAddresses: [Int], sceneAddresses: [Int], exclusionAddresses: [ExclusionAddressData]? = nil, provisionerData: [String: Any]?) {
            self.deviceAddresses = deviceAddresses
            self.groupAddresses = groupAddresses
            self.sceneAddresses = sceneAddresses
            self.exclusionAddresses = exclusionAddresses
            self.provisionerData = provisionerData
        }
        
        /// 两个回收地址数据合并，provisionerData：外部另行计算
        static public func +(left: SiteData.RecycleAddressData, right: SiteData.RecycleAddressData) -> SiteData.RecycleAddressData {
            var deviceAddresses: [Int] = left.deviceAddresses
            deviceAddresses += right.deviceAddresses.filter({ !deviceAddresses.contains($0) })
            
            var groupAddresses: [Int] = left.groupAddresses
            groupAddresses += right.groupAddresses.filter({ !groupAddresses.contains($0) })
            
            var sceneAddresses: [Int] = left.sceneAddresses
            sceneAddresses += right.sceneAddresses.filter({ !sceneAddresses.contains($0) })

            var exclusionAddresses: [ExclusionAddressData]? = left.exclusionAddresses
            right.exclusionAddresses?.forEach({ data in
                if let index = exclusionAddresses?.firstIndex(where: { $0.ivIndex == data.ivIndex }), let exclusion = exclusionAddresses?.first(where: { $0.ivIndex == data.ivIndex }) {
                    var addresses = exclusion.addresses
                    addresses += data.addresses.filter({ !addresses.contains($0) })
                    addresses.sort()
                    exclusionAddresses?.replaceSubrange(index...index, with: [ExclusionAddressData(ivIndex: exclusion.ivIndex, addresses: addresses)])
                }else {
                    exclusionAddresses?.append(ExclusionAddressData(ivIndex: data.ivIndex, addresses: data.addresses))
                }
            })
            exclusionAddresses?.sort(by: { $0.ivIndex <= $1.ivIndex })
            return RecycleAddressData(deviceAddresses: deviceAddresses.sorted(), groupAddresses: groupAddresses.sorted(), sceneAddresses: sceneAddresses.sorted(), exclusionAddresses: exclusionAddresses, provisionerData: nil)
        }
        
        // MARK: - Codable
        
        private enum CodingKeys: String, CodingKey {
            case deviceAddresses
            case groupAddresses
            case sceneAddresses
            case exclusionAddresses
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.deviceAddresses = try container.decode([Int].self, forKey: .deviceAddresses)
            self.groupAddresses = try container.decode([Int].self, forKey: .groupAddresses)
            self.sceneAddresses = try container.decode([Int].self, forKey: .sceneAddresses)
            self.exclusionAddresses = try container.decode([ExclusionAddressData].self, forKey: .exclusionAddresses)
            self.provisionerData = nil
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.deviceAddresses, forKey: .deviceAddresses)
            try container.encode(self.groupAddresses, forKey: .groupAddresses)
            try container.encode(self.sceneAddresses, forKey: .sceneAddresses)
            try container.encode(self.exclusionAddresses, forKey: .exclusionAddresses)
        }
    }
    
    
    /// 获取site解绑spaces回收地址数据
    /// - Parameter spaces: spaces
    /// - Returns: 回收地址数据
    func getRecycleAddressData(unbindSpaces spaces: [SpaceData]) -> RecycleAddressData {
        
        guard spaces.count > 0 else {
            return .init(deviceAddresses: [], groupAddresses: [], sceneAddresses: [], provisionerData: nil)
        }
//        addressResult
        
        
        /// 回收的设备地址
        var recycleDeviceAddresses: [Int] = []
        /// 回收的组地址
        var recycleGroupAddresses: [Int] = []
        /// 回收的场景地址
        var recycleSceneAddresses: [Int] = []
        
        /// 未使用的设备地址
        var availableDeviceAddresses = MeshAPI.getAvailableUnicastAddresses(meshUUID: self.meshUUID).map { Int($0) }
        /// 未使用的组地址
        let availableGroupAddresses = MeshAPI.getAvailableGroupAddresses(meshUUID: self.meshUUID).map { Int($0) }
        /// 未使用的场景地址
        let availableSceneAddresses = MeshAPI.getAvailableSceneAddresses(meshUUID: self.meshUUID).map { Int($0) }
        /// 废弃地址list
        var exclusionAddresses: [(ivIndex: Int, addresses: [Int])]?
        /// 回收后的网络用户数据
        var provisionerData: [String: Any]?
        
        let meshNetwork = MeshNetwork.load(meshUUID: self.meshUUID)
        
        if self.spaces.count - spaces.count == 0 { // 没有space了
            /// 废弃的设备地址
            exclusionAddresses = MeshAPI.getExclusionAddresses(meshUUID: self.meshUUID).map({ (Int($0.ivIndex), $0.addresses.map({ Int($0) })) })
            // 将手机地址回收
            if let meshNetwork = meshNetwork,
               let localAddress = meshNetwork.localProvisioner?.primaryUnicastAddress {
                let seq = meshNetwork.getCurrentSequenceNumber(localAddress: localAddress)
                // 判断seq大于0说明手机地址已和设备交互，需要回收
                if seq ?? 0 > 0 {
                    if let index = exclusionAddresses?.firstIndex(where: { $0.ivIndex == meshNetwork.currentIVIndex }), let exclusion = exclusionAddresses?.first(where: { $0.ivIndex == meshNetwork.currentIVIndex }) {
                        var addresses = exclusion.addresses
                        addresses.append(Int(localAddress))
                        exclusionAddresses?.replaceSubrange(index...index, with: [(exclusion.ivIndex, addresses)])
                    }else {
                        exclusionAddresses?.append((Int(meshNetwork.currentIVIndex), [Int(localAddress)]))
                    }
                }else { // 手机地址未使用
                    // 回收设备地址
                    availableDeviceAddresses.append(Int(localAddress))
                }
            }
            
            // 全部回收剩余地址和剩余废弃地址
            recycleDeviceAddresses = availableDeviceAddresses
            recycleGroupAddresses = availableGroupAddresses
            recycleSceneAddresses = availableSceneAddresses
        }else {
            // spaces内没有editor权限，应回收未使用的所有地址
            let otherSpaces = self.spaces.filter({ space in spaces.contains(where: { $0.id != space.id }) })
            if !otherSpaces.contains(where: { $0.permission == .editor }) {
                // 全部回收剩余地址和剩余废弃地址
                recycleDeviceAddresses = availableDeviceAddresses
                recycleGroupAddresses = availableGroupAddresses
                recycleSceneAddresses = availableSceneAddresses
            }else {
                
                // site中已存在的设备地址list
                let alreadyExistAddressCount = MeshAPI.getAlreadyExistDeviceAddresses(meshUUID: self.meshUUID).count
                // 剩余地址是否小于site设备数量地址的20%？，小于则取消回收地址，大于则回收space数量*50个地址
                if availableDeviceAddresses.count >= Int(Float(alreadyExistAddressCount) * 0.2) {
                    // 结尾开始回收，避免切割成多段地址范围
                    recycleDeviceAddresses = availableDeviceAddresses.suffix(spaces.filter({ $0.permission == .editor }).count * 50)
                }
                // 回收组地址数量
                var recycleGroupAddresCount = 0
                // 回收场景地址数量
                var recycleSceneAddresCount = 0
                
                spaces.filter({ $0.permission == .editor }).forEach { space in
                    
                    var usedGroupAddresses = Group.loadAddresses(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)
                    
                    var usedSceneAddresses = Scene.loadAddresses(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)
                    
                    if let localProvisioner = meshNetwork?.localProvisioner {
                        // 该用户已使用的组地址
                        usedGroupAddresses = usedGroupAddresses.filter({ localProvisioner.allocatedGroupRange.contains($0) })
                        // 该用户已使用的场景地址
                        usedSceneAddresses = usedSceneAddresses.filter({ localProvisioner.allocatedSceneRange.contains($0) })
                    }
                    
                    // 每解绑一个space，其APP都回收这个space未使用的组地址给服务器  1个空间32个组地址
                    recycleGroupAddresCount += 32 - usedGroupAddresses.count
                    
                    // 每解绑一个space，其APP都回收这个space未使用的场景地址给服务器  1个空间16个场景
                    let spaceScenes = Scene.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)
                    recycleSceneAddresCount += 16 - usedSceneAddresses.count
                }
                
                recycleGroupAddresses = availableGroupAddresses.suffix(recycleGroupAddresCount)
                recycleSceneAddresses = availableSceneAddresses.suffix(recycleSceneAddresCount)
            }
        }
//        exclusionAddresses.map({ data in RecycleAddressData.ExclusionAddressData(ivIndex: data.$0, addresses: data.$1) })
        let exclusions = exclusionAddresses?.map({ (ivIndex: Int, addresses: [Int]) in
            return RecycleAddressData.ExclusionAddressData(ivIndex: ivIndex, addresses: addresses)
        })
        
        
        if let localProvisioner = meshNetwork?.localProvisioner {
            let deallocatedUnicastRange = recycleDeviceAddresses.splitArray().compactMap { array in
                if let lowAddress = array.first, let highAddress = array.last {
                    return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
                }
                return nil
            }
            deallocatedUnicastRange.forEach({
                localProvisioner.deallocate(unicastAddressRange: $0)
            })
            // 组地址
            let deallocatedGroupRange = recycleGroupAddresses.splitArray().compactMap { array in
                if let lowAddress = array.first, let highAddress = array.last {
                    return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
                }
                return nil
            }
            deallocatedGroupRange.forEach({
                localProvisioner.deallocate(groupAddressRange: $0)
            })
            
            // 场景地址
            let deallocatedSceneRange = recycleSceneAddresses.splitArray().compactMap { array in
                if let firstScene = array.first, let lastScene = array.last {
                    return SceneRange(from: UInt16(firstScene), to: UInt16(lastScene))
                }
                return nil
            }
            deallocatedSceneRange.forEach({
                localProvisioner.deallocate(sceneRange: $0)
            })
            provisionerData = localProvisioner.toJson()
        }
        
        
        return .init(deviceAddresses: recycleDeviceAddresses.sorted(), groupAddresses: recycleGroupAddresses.sorted(), sceneAddresses: recycleSceneAddresses.sorted(), exclusionAddresses: exclusions, provisionerData: provisionerData)
    }
    
}

extension SpaceData {
    
    private struct AssociatedKey {
        static var meshManagerKey = 1
    }
    
//    var meshManager: MeshNetworkManager? {
//        get {
//            objc_getAssociatedObject(self, &AssociatedKey.meshManagerKey) as? MeshNetworkManager ??
//            MeshNetworkManager.loadMeshNetwork(meshUUID: meshUUID)
//        }set {
//            objc_setAssociatedObject(self, &AssociatedKey.meshManagerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
//        }
//    }
    
    /// 克隆空间数据（空间信息、mesh网络数据）
    /// - Parameter save: 是否本地缓存
    func clone(_ save: Bool = false) -> SpaceData {
        
        let spaceData = self.cloneData()
        // 创建的mesh网络
        let meshManager = MeshNetworkManager.createMeshNetwork(meshUUID: spaceData.id, meshNetworkName: spaceData.name)
        // 克隆目标的mesh网络，同步数据
//        if let cloneMeshManager = spaceData.meshManager {
//            // clone 组，场景，日程，节律等这些能够预设的参数。（目前只有组、场景）
//            cloneMeshManager.groups.forEach { group in
//                try? meshManager.meshNetwork?.add(group: group)
//            }
//            cloneMeshManager.scenes.forEach { scene in
//                try? meshManager.meshNetwork?.add(scene: scene.number, name: scene.name)
//            }
//        }
        _ = meshManager.meshNetwork?.save()
        if save {
            spaceData.save()
        }
        return spaceData
    }
    
    /// 删除空间数据+mesh网络
    @discardableResult func delete() -> Bool {
        
//        MeshLibManager.manager.removeMeshNetwork(meshUUID: self.meshUUID)
        // 删除子网并断开连接
//        _ = MeshNetworkManager.instance.removeSubnetwork(networkKey: self.meshNetworkKey)
        let meshManager = MeshNetworkManager.loadMeshNetwork(meshUUID: meshUUID)
        _ = meshManager?.removeSubnetwork(networkId: self.meshNetworkId)
//        _ = meshManager?.removeSubnetwork(networkKey: self.meshNetworkKey)
        if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == self.meshUUID && MeshNetworkManager.instance.currentNetworkKey.networkId.hex == self.meshNetworkId && MeshLibManager.manager.meshNetworkManager?.meshNetwork?.uuid == MeshNetworkManager.instance.meshNetwork?.uuid {
            MeshLibManager.manager.meshNetworkDisconnect()
        }
        DispatchQueue.global().async {
//            _ = MeshNetworkManager.removeMeshNetwork(meshUUID: self.meshUUID)
            // 删除网络扩展数据
            GroupInfo.delete(meshUUID: self.meshUUID, networkId: self.meshNetworkId)
            SceneInfo.delete(meshUUID: self.meshUUID, networkId: self.meshNetworkId)
            Schedule.deleteAll(meshUUID: self.meshUUID, meshNetworkId: self.meshNetworkId)
            Profile.deleteProfiles(meshUUID: self.meshUUID, meshNetworkId: self.meshNetworkId)
//            GroupSwitch.deleteSwitchs(meshUUID: self.meshUUID, networkId: self.meshNetworkId)
            DeviceSwitchData.deleteSwitchs(meshUUID: self.meshUUID, networkId: self.meshNetworkId)
            UserData.delete(spaceId: self.id)
            self.deleteData()
        }
        return true
    }
    
}

extension MeshLibManager {
    
    static var supportDeviceInfosKey = 5
    
    /// 支持的设备信息list（未配置设备则不可添加）
    var supportDeviceInfos: [MeshDeviceConfigInfo] {
        get {
            objc_getAssociatedObject(self, &MeshLibManager.supportDeviceInfosKey) as? [MeshDeviceConfigInfo] ?? MeshDeviceConfigInfo.defaultConfigInfos
        }set {
            objc_setAssociatedObject(self, &MeshLibManager.supportDeviceInfosKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}

extension Provisioner {
    
    func toJson() -> [String: Any] {
        var provisionerJson: [String: Any] = [:]
        provisionerJson.updateValue(self.uuid.uuidString, forKey: "UUID")
        provisionerJson.updateValue(self.name, forKey: "provisionerName")
        
        // 已使用地址
        if let meshNetwork = self.network {
            
            // 正在使用的手机地址
            if let addressHex = self.primaryUnicastAddress?.hex ?? SiteData.load(siteId: meshNetwork.uuid.uuidString)?.localAddress?.hex {
                provisionerJson.updateValue(addressHex, forKey: "address")
            }
            
            provisionerJson.updateValue(meshNetwork.deviceUsedAddresses.map({ $0.hex }), forKey: "usedAddresses")
        }
        
        // 设备、组、场景可分配地址
        let allocatedUnicastRange = self.allocatedUnicastRange.map({
            ["lowAddress": $0.lowAddress.hex, "highAddress": $0.highAddress.hex]
        })
        provisionerJson.updateValue(allocatedUnicastRange, forKey: "allocatedUnicastRange")
        
        let allocatedGroupRange = self.allocatedGroupRange.map({
            ["lowAddress": $0.lowAddress.hex, "highAddress": $0.highAddress.hex]
        })
        
        provisionerJson.updateValue(allocatedGroupRange, forKey: "allocatedGroupRange")
        
        let allocatedSceneRange = self.allocatedSceneRange.map({
            ["lowAddress": $0.firstScene.hex, "highAddress": $0.lastScene.hex]
        })
        provisionerJson.updateValue(allocatedSceneRange, forKey: "allocatedSceneRange")
        return provisionerJson
    }
}

extension MeshNetworkManager {
    
    private struct AssociatedKey {
        static var groupsKey = 1
        static var scenesKey = 2
        static var schedulesKey = 3
        static var switchsKey = 4
    }
    
    /// 日程list
//    var schedules: [Schedule] {
//        get {
//            objc_getAssociatedObject(self, &MeshNetworkManager.schedulesKey) as? [Schedule] ?? []
//        }set {
//            objc_setAssociatedObject(self, &MeshNetworkManager.schedulesKey, newValue, .OBJC_ASSOCIATION_RETAIN)
//        }
//    }
    
    /// 当前子网内设备list
//    var subnetworkNodes: [Node] {
//        return realNodes.filter({ $0.networkKeys.contains(where: { $0.index == currentNetworkKey.index && !$0.isPrimary }) })
//    }
    
//    var subnetworkLightNodes: [Node] {
//        return subnetworkNodes.filter({ $0.lightnessModel != nil })
//    }
    
    /// 当前子网内组list
//    var subnetworkGroups: [Group] {
//        get {
//            objc_getAssociatedObject(self, &AssociatedKey.groupsKey) as? [Group] ?? []
//        }set {
//            objc_setAssociatedObject(self, &AssociatedKey.groupsKey, newValue, .OBJC_ASSOCIATION_RETAIN)
//        }
//    }
//    
//    /// 当前子网内场景list
//    var subnetworkScenes: [Scene] {
//        get {
//            objc_getAssociatedObject(self, &AssociatedKey.scenesKey) as? [Scene] ?? []
//        }set {
//            objc_setAssociatedObject(self, &AssociatedKey.scenesKey, newValue, .OBJC_ASSOCIATION_RETAIN)
//        }
//    }
    
    /// 当前子网内日程list
    var schedules: [Schedule] {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.schedulesKey) as? [Schedule] ?? []
        }set {
            objc_setAssociatedObject(self, &AssociatedKey.schedulesKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    

    /// 当前子网内动能开关list
    var switchs: [DeviceSwitchData] {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.switchsKey) as? [DeviceSwitchData] ?? []
        }set {
            objc_setAssociatedObject(self, &AssociatedKey.switchsKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 获取网络扩展数据
    func loadExtensionData(result: (()->Void)? = nil) {
        
        guard let uuid = self.meshNetwork?.uuid.uuidString else { return }
        
        DispatchQueue.global().async {
            
            self.schedules = Schedule.load(meshUUID: uuid, meshNetworkId: self.currentNetworkKey.networkId.hex)
            
            self.groups.forEach({ group in
                group.info = GroupInfo.load(meshUUID: uuid, address: group.address.address) ?? GroupInfo(address: group.address.address)
             
               let bindSchedules = self.schedules.filter({ schedule in
                   schedule.groups.contains(where: { $0.address == group.address }) ||
                   schedule.needDeleteGroups.contains(where: { $0.address == group.address }) ||
                   (schedule.scene?.info.groups.contains(where: { $0.address == group.address }) ?? false)
               })
                group.info.bindSchedules = bindSchedules
            })
            self.scenes.forEach({
                $0.info = SceneInfo.load(meshUUID: uuid, sceneId: $0.number) ?? SceneInfo(sceneId: $0.number)
            })
            
            self.switchs = DeviceSwitchData.load(meshUUID: uuid, meshNetworkId: self.currentNetworkKey.networkId.hex)
            
//            var isUnsubscribe: Bool = false
            // 解绑本地节点订阅组信息，用于接收按键发出指令本地显示状态
//            for element in MeshNetworkManager.instance.localNode?.elements ?? [] {
//                element.models.forEach { model in
//                    model.subscriptions.forEach({ group in
////                        if group.isVirtual {
//                            model.unsubscribe(from: group)
////                        }
//                    })
//                }
//            }
//            if isUnsubscribe {
//                MeshNetworkManager.instance.localNode?.save()
//            }
            
//            var subnetworkScenes: [Scene] = []
//            let sceneInfos = SceneInfo.load(meshUUID: uuid, networkKey: self.currentNetworkKey)
//            sceneInfos.forEach { info in
//                if let scene = self.scenes.first(where: { $0.number == info.sceneId }) {
//                    scene.info = info
//                    let sceneSchedules = self.subnetworkSchedules.filter({ schedule in info.bindSchedules.contains(where: { schedule.id == $0.id }) })
//                    scene.info.groups.forEach({ group in
//                        sceneSchedules.forEach({ sceneSchedule in
//                            if !group.info.bindSchedules.contains(where: {$0.id == sceneSchedule.id }) {
//                                group.info.bindSchedules.append(sceneSchedule)
//                            }
//                        })
//                    })
//                    subnetworkScenes.append(scene)
//                }
//            }
            DispatchQueue.main.async {
                result?()
            }
        }
        
    }
    
    /// 获取下一个节点名称
    /// - Parameter defaultName: 默认名称
    /// - Returns: 分配的节点名称
    func getNextNodeName(_ defaultName: String = "device_defalut_name".localizedString) -> String {
        objc_sync_enter(self)
        
        var resultName = defaultName + "001"
        // 已存在的节点名称
        let existNames = realNodes.map({ $0.name ?? "" })
        for index in 1...32767 {
            // ID001
            let name = defaultName + String(format: "%03d", index)
            if !existNames.contains(name) {
                resultName = name
                break
            }
        }
        objc_sync_exit(self)
        return resultName
        
    }
    
    /// 设备节点是否重名
    /// - Parameter nodeName: 节点名称
    /// - Returns: 是否重名
    func isNodeTautonym(nodeName: String) -> Bool {
        return realNodes.contains(where: { $0.name == nodeName })
    }
    
    /// 获取下一个场景名称
    /// - Parameter defaultName: 默认名称
    /// - Returns: 分配的场景名称
    func getNextSceneName(_ defaultName: String = "scene_defalut_name".localizedString) -> String {
        // 已存在的场景名称
        let existNames = scenes.map({ $0.name })
        for index in 1...16 {
            let name = defaultName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defaultName + "1"
    }
    
    /// 场景是否重名
    /// - Parameter name: 名称
    /// - Returns: 是否重名
    func isSceneTautonym(name: String) -> Bool {
        return scenes.contains(where: { $0.name == name })
    }
    
    /// 获取下一个组名称
    /// - Parameter defaultName: 默认名称
    /// - Returns: 分配的组名称
    func getNextGroupName(_ defaultName: String = "group_defalut_name".localizedString) -> String {
        // 已存在的组名称
        let existNames = groups.map({ $0.name })
        for index in 1...16 {
            let name = defaultName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defaultName + "1"
    }
    
    /// 组是否重名
    /// - Parameter name: 名称
    /// - Returns: 是否重名
    func isGroupTautonym(name: String) -> Bool {
        return groups.contains(where: { $0.name == name })
    }
    
    /// 获取下一个日程名称
    /// - Parameter defaultName: 默认名称
    /// - Returns: 分配的日程名称
    func getNextScheduleName(_ defaultName: String = "schedule_defalut_name".localizedString) -> String {
        // 已存在的日程名称
        let existNames = schedules.map({ $0.name })
        for index in 1...16 {
            let name = defaultName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defaultName + "1"
    }
    
    /// 获取下一个日程id 0~15
    func getNextAvailableScheduleId() -> Int? {
        for id in 0...15 {
            if !schedules.contains(where: { $0.id == id }) {
                return id
            }
        }
        return nil
    }
    
    /// 日程是否重名
    /// - Parameter name: 名称
    /// - Returns: 是否重名
    func isScheduleTautonym(name: String) -> Bool {
        return schedules.contains(where: { $0.name == name })
    }
    
    /// 获取下一个动能开关名称
    func getNextSwitchName(_ defaultName: String = "switch".localizedString) -> String {
        // 已存在的开关名称
        let existNames = switchs.map({ $0.name })
        for index in 1...16 {
            let name = defaultName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defaultName + "1"
    }
    
    /// 动能开关是否重名
    /// - Parameter name: 名称
    /// - Returns: 是否重名
    func isSwitchTautonym(name: String) -> Bool {
        return switchs.contains(where: { $0.name == name })
    }
    
    /// 获取节点随机mac地址
    func getRandomMacAddress() -> String {
        
        var mac: String = ""
        while true {
            mac.removeAll()
            for _ in 0..<6 {
                let value = UInt8.random(in: 0...0xFF)
                mac.append(String(format: "%02X", value))
            }
            if !realNodes.contains(where: { $0.macAddress == mac }) {
                break
            }
        }
        print(mac)
        return mac
    }
    
    /// 创建动能开关
    func createDefaultSwitch() -> DeviceSwitchData? {
        // 是否超出限制
        guard self.switchs.count < 16 else {
            return nil
        }
        let newSwtich = DeviceSwitchData.default()
        self.switchs.append(newSwtich)
        newSwtich.save()
        return newSwtich
    }
    
    /// 删除动能开关
    func deleteSwitch(switchData: DeviceSwitchData) {
        guard let meshUUID = self.meshNetwork?.uuid.uuidString else { return }
        switchData.delete(meshUUID: meshUUID, networkId: self.currentNetworkKey.networkId.hex)
        self.switchs.removeAll(where: { $0.id == switchData.id })
        if let group = switchData.linkGroup {
            var isUnsubscribe: Bool = false
            // 解绑本地节点订阅组信息，用于接收按键发出指令本地显示状态
            for element in MeshNetworkManager.instance.localNode?.elements ?? [] {
                let subscribeModels = element.models.filter({ $0.isSubscribed(to: group) })
                subscribeModels.forEach({
                    $0.unsubscribe(from: group)
                })
                if subscribeModels.count > 0 {
                    isUnsubscribe = true
                }
            }
            if isUnsubscribe {
                MeshNetworkManager.instance.localNode?.save()
            }
            try? self.meshNetwork?.remove(group: group)
        }
        
    }
    
}

extension Group {
    
    private static var infoKey = 0
    private static var lightnessKey = 1
    private static var cctKey = 2
    private static var isOnKey = 3
    
    static let defaultLightness: UInt16 = .max
    static let defaultCct: Int = 4500
    
    /// 扩展信息
    var info: GroupInfo {
        get {
            guard let info = objc_getAssociatedObject(self, &Group.infoKey) as? GroupInfo else {
                let newInfo = GroupInfo(address: address.address)
                self.info = newInfo
                return newInfo
            }
            return info
        }set {
            objc_setAssociatedObject(self, &Group.infoKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 组亮度值 0~65535
    var lightness: UInt16 {
        get {
            // 缓存值->相同频率最高值->默认值
            // 读取缓存
            guard let lightness = objc_getAssociatedObject(self, &Group.lightnessKey) as? UInt16 else {
                if nodes.isEmpty {
                    return Group.defaultLightness
                }
                // 计算频率最高值 出现次数>1
                let lightnesss = self.nodes.filter({ $0.lightnessModel != nil && $0.state }).map({ $0.lightness })
                var lightnessDatas: [UInt16: Int] = [:]
                lightnesss.forEach { lightness in
                    if lightnessDatas.keys.contains(lightness) {
                        lightnessDatas.updateValue((lightnessDatas[lightness] ?? 0) + 1, forKey: lightness)
                    }else {
                        lightnessDatas.updateValue(1, forKey: lightness)
                    }
                }
                // 默认值
                var lightness = Group.defaultLightness
                if let result = lightnessDatas.max(by: { $1.value > $0.value || ($1.value == $0.value && $1.key > $0.key) }) {
                    lightness = result.key
                }
                return lightness
            }
            return lightness
        }set {
            objc_setAssociatedObject(self, &Group.lightnessKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 组色温值 2700K-6500K
    var cct: Int {
        get {
            // 缓存值->相同频率最高值->默认值
            // 读取缓存
            guard let cct = objc_getAssociatedObject(self, &Group.cctKey) as? Int else {
                if nodes.isEmpty {
                    return 4500
                }
                // 计算频率最高值 出现次数>1
                let ccts = self.nodes.filter({ $0.temperatureModel != nil && $0.state }).map({ $0.temperature })
                var cctDatas: [UInt16: Int] = [:]
                ccts.forEach { cct in
                    if cctDatas.keys.contains(cct) {
                        cctDatas.updateValue((cctDatas[cct] ?? 0) + 1, forKey: cct)
                    }else {
                        cctDatas.updateValue(1, forKey: cct)
                    }
                }
                // 默认值
                var cct = Group.defaultCct
                if let result = cctDatas.max(by: { $1.value > $0.value || ($1.value == $0.value && $1.key > $0.key) }) {
                    cct = Int(result.key)
                }
                return cct
            }
            return cct
        }set {
            objc_setAssociatedObject(self, &Group.cctKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 组开关
    var isOn: Bool {
        get {
            objc_getAssociatedObject(self, &Group.isOnKey) as? Bool ?? (nodes.isEmpty || nodes.contains(where: { $0.isOn }))
        }set {
            objc_setAssociatedObject(self, &Group.isOnKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 是否支持onoff
    var supportOnOff: Bool {
        return nodes.contains(where: { $0.onoffModel != nil })
    }
    
    /// 是否支持亮度
    var supportLightness: Bool {
        return nodes.contains(where: { $0.lightnessModel != nil })
    }
    
    /// 是否支持色温
    var supportCct: Bool {
        return nodes.contains(where: { $0.temperatureModel != nil })
    }
    
    /// 删除本地化缓存数据（只处理业务扩展数据）
    func deleteExtension() {
        guard let uuid = self.network?.uuid.uuidString else {
            return
        }
        let subnetworkId = self.subNetworkId
        // 删除基本信息
        info.delete(meshUUID: uuid)
        
        // 删除组设置的日程数据
        MeshNetworkManager.instance.schedules.forEach({
            if let index = $0.groupAddresses.firstIndex(of: self.address.address) {
                $0.groupAddresses.remove(at: index)
                $0.save(meshUUID: uuid, meshNetworkId: subnetworkId)
            }
            if let index = $0.needDeleteGroupAddresses.firstIndex(of: self.address.address) {
                $0.needDeleteGroupAddresses.remove(at: index)
                $0.save(meshUUID: uuid, meshNetworkId: subnetworkId)
            }
        })
        // 删除配置文件
        self.info.profile.delete(meshUUID: uuid, meshNetworkId: subnetworkId)
        // 删除关联的动能开关
        MeshNetworkManager.instance.switchs.filter({ switchData in switchData.bindGroupAddresses.contains(self.address.address) || switchData.unbindGroupAddresses.contains(self.address.address) }).forEach {
            $0.bindGroupAddresses.removeAll(where: { $0 == self.address.address })
            $0.unbindGroupAddresses.removeAll(where: { $0 == self.address.address })
            $0.save(meshUUID: uuid, networkId: subnetworkId)
        }
        
//        GroupSwitch.deleteSwitchs(meshUUID: uuid, networkId: subnetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex, groupAddress: address.address)
    }
    
    /// 删除组内的场景缓存
    /// - Parameter sceneId: 场景id
    func delete(sceneId: SceneNumber) {
      
        if let index = self.info.sceneExecuteDatas.firstIndex(where: { $0.sceneNumber == sceneId }) {
            self.info.sceneExecuteDatas.remove(at: index)
            self.info.save(meshUUID: self.network?.uuid.uuidString, subnetworkId: self.subNetworkId)
        }
    }
    
    /// 更新组内的场景状态
    /// - Parameter sceneId: 场景id
    func updateSceneState(sceneId: SceneNumber, state: SceneExecuteData.State) {
      
        if let sceneData = self.info.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneId }) {
            sceneData.state = state
//            guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
//                return
//            }
            self.info.save(meshUUID: self.network?.uuid.uuidString, subnetworkId: self.subNetworkId)
        }
    }
    
    /// 添加一个虚拟按键
//    @discardableResult func addGroupSwitch() -> GroupSwitch {
////        var nextId = 1
////        let exitIds = self.info.switchs.map({ $0.id })
////        for id in 1...1000 {
////            if !exitIds.contains(id) {
////                nextId = id
////                break
////            }
////        }
//        let groupSwitch = GroupSwitch(id: UUID().uuidString, groupAddress: self.address.address, enabled: true, name: nextSwitchName())
//        self.info.switchs.append(groupSwitch)
//        if let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
//            groupSwitch.save(meshUUID: uuid, networkId: MeshNetworkManager.instance.currentNetworkKey.networkId.hex)
//        }
//        return groupSwitch
//    }
    
    /// 判断虚拟按键是否重名
//    func isSwitchTautonym(name: String) -> Bool {
//        return self.info.switchs.contains(where: { $0.name == name })
//    }
    
    /// 获取下一个虚拟按键名称
//    func nextSwitchName() -> String {
//        var nextName = ""
//        let exitNames = self.info.switchs.map({ $0.name })
//        let defalutName = "switch".localizedString
//        for index in 1...1000 {
//            let name = "\(defalutName) \(index)"
//            if !exitNames.contains(name) {
//                nextName = name
//                break
//            }
//        }
//        return nextName
//    }
    
    /// 删除组内虚拟按键
    /// - Parameter groupSwitch: 虚拟按键
//    func delete(groupSwitch: GroupSwitch) {
//        
//        self.info.switchs.removeAll(where: { $0.id == groupSwitch.id })
//        guard let uuid = self.network?.uuid.uuidString else {
//            return
//        }
//        groupSwitch.delete(meshUUID: uuid, networkId: (self.network?.networkKeys.first(where: { $0.isSecondary }) ?? MeshNetworkManager.instance.currentNetworkKey).networkId.hex)
//    }
    
    /// 本地化缓存组数据（只处理业务扩展数据）
    func saveExtension() {
        
        guard let uuid = self.network?.uuid.uuidString else {
            return
        }
//        let subnetworkId = self.network?.networkKeys.first(where: { $0.isSecondary })?.networkId.hex
        // 保存基本信息
        self.info.save(meshUUID: uuid, subnetworkId: self.subNetworkId)
        // 保存场景数据
//        self.info.sceneExecuteDatas.forEach({
//            SceneExecuteData.save(meshUUID: uuid, networkKey: networkKey, address: address.address, sceneId: Int($0.key), sceneData: $0.value)
//        })
        self.info.profile.save(meshUUID: uuid, meshNetworkId: self.subNetworkId)
        // 保存虚拟按键数据
//        self.info.switchs.forEach({
//            $0.save(meshUUID: uuid, networkId: subnetworkId)
//        })
    }
    
    
    /// 获取组需要同步对应场景的设备
    /// - Parameter scene: 场景
    /// - Returns: 待同步的设备、待删除场景的设备
    func getNeedSyncDataNodes(scene: Scene) -> (syncNodes: [Node], deleteNodes: [Node]) {
        // 需要同步场景参数的设备list
        var needSyncNodes: [Node] = []
        // 需要删除场景参数的设备list
        var needDeleteNodes: [Node] = []
        guard let sceneData = info.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) else {
            return (needSyncNodes, needDeleteNodes)
        }
        if sceneData.state == .waitDelete { // 待删除
            needDeleteNodes = nodes.filter({ $0.sceneSetupModel != nil && $0.sceneExecuteDatas.contains(where: { $0.sceneNumber == scene.number }) })
        }else { // 同步
            needSyncNodes = nodes.filter({
                guard $0.sceneSetupModel != nil else {
                    return false
                }
                if let nodeSceneData = $0.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
                    return !(nodeSceneData == sceneData)
                }
                return true
            })
        }
        return (needSyncNodes, needDeleteNodes)
    }
    
    /// 获取组需要同步对应日程的设备
    /// - Parameter schedule: 日程
    /// - Returns: 待同步的设备、待删除日程的设备
    func getNeedSyncScheduleDataNodes(_ schedule: Schedule) -> (syncNodes: [Node], deleteNodes: [Node]) {
        
        // 需要同步日程参数的设备list
        var needSyncNodes: [Node] = []
        // 需要删除日程参数的设备list
        var needDeleteNodes: [Node] = []
        guard info.bindSchedules.contains(where: { $0.id == schedule.id }) else {
            return (needSyncNodes, needDeleteNodes)
        }
        
        // 待删除的组,获取组内待删除的设备
        if schedule.needDeleteGroups.contains(self) {
            needDeleteNodes = self.nodes.filter({ $0.schedulerSetupModel != nil && $0.schedulerActions.keys.contains(schedule.id) })
        }else { // 待同步，获取组内待同步的设备
            needSyncNodes = self.nodes.filter({ $0.schedulerSetupModel != nil && !$0.schedulerActions.keys.contains(schedule.id) || !($0.schedulerActions[schedule.id]! == schedule.schedulerEntry) })
        }
        return (needSyncNodes, needDeleteNodes)
    }

}

extension Scene {
    
    private static var infoKey = 0
    /// 扩展信息
    var info: SceneInfo {
        get {
            guard let info = objc_getAssociatedObject(self, &Scene.infoKey) as? SceneInfo else {
                let newInfo = SceneInfo(sceneId: self.number)
                self.info = newInfo
                return newInfo
            }
            return info
        }set {
            objc_setAssociatedObject(self, &Scene.infoKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 获取需要同步数据的组
    var needSyncGroups: [Group] {
        info.groups.filter({ group in
            let sceneResult = group.getNeedSyncDataNodes(scene: self)
            let isSyncScene = sceneResult.syncNodes.count > 0 || sceneResult.deleteNodes.count > 0
            let isSyncSchedule = info.bindSchedules.contains(where: {
                let scheduleSyncResult = group.getNeedSyncScheduleDataNodes($0)
                return scheduleSyncResult.syncNodes.count > 0 || scheduleSyncResult.deleteNodes.count > 0
            })
            return isSyncSchedule || isSyncScene
        })
        
    }
    
    
    /// 删除场景缓存数据
    func deleteExtension() {
        guard let uuid = self.network?.uuid.uuidString else {
            return
        }
        let subnetworkId = self.network?.networkKeys.first(where: { $0.isSecondary })?.networkId.hex
        // 删除场景内组缓存数据
        info.groups.forEach({
            $0.info.sceneExecuteDatas.removeAll(where: { $0.sceneNumber == self.number })
            $0.info.save(meshUUID: uuid, subnetworkId: subnetworkId)
//            if $0.info.sceneExecuteDatas[number] != nil {
//                SceneExecuteData.deleteData(meshUUID: uuid, address: $0.address.address, sceneId: Int(number))
//                $0.info.bindSceneDatas.removeValue(forKey: number)
//            }
            // 删除组内设备缓存的场景数据
            $0.nodes.forEach({ node in
                node.sceneExecuteDatas.removeAll(where: { $0.sceneNumber == self.number })
                node.savePropertys()
//                if node.sceneDatas[number] != nil {
//                    SceneExecuteData.deleteData(meshUUID: uuid, address: node.primaryUnicastAddress, sceneId: Int(number))
//                    node.sceneDatas.removeValue(forKey: number)
//                }
            })
        })
        info.delete(meshUUID: uuid)
    }
    

    /// 本地化缓存组数据（只处理业务扩展数据）
//    func save() {
//        
//        guard let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
//            return
//        }
//        // 保存基本信息
//        self.info.save(meshUUID: uuid)
//        // 保存场景数据
//        self.info.groups.forEach({
//            SceneExecuteData.save(meshUUID: uuid, address: $0.address.address, sceneId: Int(sceneId), sceneData: data)
//        })
//    }
    
    
}

class SceneInfo {
    
    /// 场景id
    let sceneId: SceneNumber
    
    /// 图片id
    var imageId: Int = 0
    
    /// 添加的组list
    var groups: [Group] {
        return MeshNetworkManager.instance.groups.filter({ $0.info.sceneExecuteDatas.contains(where: { $0.sceneNumber == self.sceneId }) })
    }
    
    /// 场景内绑定的日程list
    var bindSchedules: [Schedule] {
        return MeshNetworkManager.instance.schedules.filter({ $0.scene?.number == self.sceneId })
    }
    
    
    init(sceneId: SceneNumber, imageId: Int = 0) {
        self.sceneId = sceneId
        self.imageId = imageId
//        self.groups = groups
    }
}

class GroupInfo {
    
    /// 组地址
    let address: Address

    /// 图片id
    var imageId: Int = 0
    
    /// 图标文本（自定义）
    var imageText: String?
    
    /// 绑定的场景数据
//    var bindSceneDatas: [SceneNumber : SceneExecuteData] = [:]
    
    /// 设置的场景数据
    var sceneExecuteDatas: [SceneExecuteData] = []
    
    /// 绑定的日程数据
    var bindSchedules: [Schedule] = []
    
    /// 使用的配置数据
    var profile: Profile
    
    /// 绑定的光照传感器
    var ambientLightSensorNodeAddress: Address?
    
    var ambientLightSensorNode: Node? {
        return MeshNetworkManager.instance.realNodes.first(where: { $0.primaryUnicastAddress == ambientLightSensorNodeAddress })
    }
    
    /// 虚拟按键list
//    var switchs: [GroupSwitch] = []
    
    /// 组内绑定的动能开关list
    var switchs: [DeviceSwitchData] {
        return MeshNetworkManager.instance.switchs.filter({ $0.bindGroupAddresses.contains(self.address) })
    }
    

    /// 组内绑定/待解绑的动能开关list
    var allSwitchs: [DeviceSwitchData] {
        return MeshNetworkManager.instance.switchs.filter({ $0.bindGroupAddresses.contains(self.address) || $0.unbindGroupAddresses.contains(self.address) })
    }
    
    init(address: Address, imageId: Int = 0, imageText: String? = nil, sceneExecuteDatas: [SceneExecuteData] = [], bindSchedules: [Schedule] = [], profile: Profile = .init(type: .occupancy_daylight)) {
        self.address = address
        self.imageId = imageId
        self.imageText = imageText
        self.sceneExecuteDatas = sceneExecuteDatas
        self.bindSchedules = bindSchedules
        self.profile = profile
    }
    
}

/// 场景执行数据
extension SceneExecuteData {
    
    /// 场景执行数据色温范围
    static let cctRange: ClosedRange<UInt16> = 2700...6500
    
//    convenience init(lightness: UInt16, cct: UInt16, state: SceneExecuteData.State = .normal) {
//        
//        self.lightness = lightness
//        self.cct = cct
//        self.state = state
//    }
    
    static func == (lhs: SceneExecuteData, rhs: SceneExecuteData) -> Bool {
        return lhs.lightness == rhs.lightness && lhs.cct == rhs.cct
    }
}

class Schedule: Codable, Copyable {
    
    /// 重复周期字符串list
    static let weeklyStrs = ["week_mo".localizedString, "week_tu".localizedString, "week_we".localizedString, "week_th".localizedString, "week_fr".localizedString, "week_sa".localizedString, "week_su".localizedString]
    /// 所有月份
    static let allMonths: [Month] = [.January,.February,.March,.April,.May,.June,.July,.August,.September,.October,.November,.December]
    
    /// 日程执行目标类型
    enum TargetType: Int {
        /// 组
        case groups = 0
        /// 设备
        case devices = 1
        /// 设备
        case scene = 2
    }
    
    /// 计划id  0~15
    var id: Int = 0
    /// 是否启用
    var enabled: Bool = false
    /// 名称
    var name: String = ""
    /// 设置的节点list nodes、groups、scenes三选一
    var nodeAddresses: [Address] = []
    var nodes: [Node] {
        return MeshNetworkManager.instance.realNodes.filter({ nodeAddresses.contains($0.primaryUnicastAddress) })
    }
    /// 设置的组list nodes、groups、scenes三选一
    var groupAddresses: [Address] = []
    var groups: [Group] {
        return MeshNetworkManager.instance.groups.filter({ groupAddresses.contains($0.address.address) })
    }
    /// 设置执行的场景，目前只能设置一个，并且nodes、groups、scenes三选一
    var sceneNumber: SceneNumber?
    var scene: Scene? {
        guard let number = sceneNumber else { return nil }
        return MeshNetworkManager.instance.scenes.first(where: { $0.number == number })
    }
    /// 选择的执行目标类型
    var selectTargetType: TargetType = .groups
    /// 执行的场景id
//    var actionSceneId: SceneNumber = 0
    /// 执行动作 off、on、recall scene、no action
    var action: SchedulerAction = .noAction
    /// 渐变时间（s）
    var fadeTime: Int = 0
    /// 周重复
    var weekDays: [WeekDay] = []
    /// 时
    var hour: Int = 0
    /// 分
    var minute: Int = 0

    /// 需要移出日程的设备
    var needDeleteNodeAddresses: [Address] = []
    var needDeleteNodes: [Node] {
        return MeshNetworkManager.instance.realNodes.filter({ needDeleteNodeAddresses.contains($0.primaryUnicastAddress) })
    }
    /// 需要移出日程的组
    var needDeleteGroupAddresses: [Address] = []
    var needDeleteGroups: [Group] {
        return MeshNetworkManager.instance.groups.filter({ needDeleteGroupAddresses.contains($0.address.address) })
    }
    /// 需要移出的日程的场景
    var needDeleteSceneNumbers: [SceneNumber] = []
    var needDeleteScenes: [Scene] {
        return MeshNetworkManager.instance.scenes.filter({ needDeleteSceneNumbers.contains($0.number) })
    }
    /// 存在的设备
    var exitNodes: [Node] {
        var nodes: [Node] = []
        nodes.append(contentsOf: self.nodes)
        nodes.append(contentsOf: self.needDeleteNodes.filter({ !nodes.contains($0) }))
        
        groups.forEach({
            nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
        })
        needDeleteGroups.forEach({
            nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
        })
        
        scene?.info.groups.forEach({
            nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
        })
        needDeleteScenes.forEach { scene in
            scene.info.groups.forEach({
                nodes.append(contentsOf: $0.nodes.filter({ !nodes.contains($0) }))
            })
        }
        return nodes
    }
    
    
    /// 重复周期描述
    var weekStr: String {
        
        let allWeekDays: [WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
        
        var weekStr = ""
        if weekDays == allWeekDays { // 每天
            weekStr = "everyday".localizedString
        }else if weekDays == allWeekDays.dropLast(2) { // 工作日
            weekStr = "workday".localizedString
        }else if weekDays == allWeekDays.suffix(2) { // 周末
            weekStr = "weekend".localizedString
        }else { // 无规律 Mo, Tu, We, Fr, Sa, Su
            let weekStrs = weekDays.compactMap({
                if let index = allWeekDays.firstIndex(of: $0) {
                    return Schedule.weeklyStrs[min(Schedule.weeklyStrs.count, index)]
                }
                return nil
            })
            
            weekStrs.forEach({
                weekStr.append(weekStr.isEmpty ? $0 : ",\($0)")
            })
        }
        
        return weekStr
    }
    
    
    /// 设置的数据
    var data: Data {
        return SchedulerRegistryEntry.marshal(index: UInt8(id), entry: schedulerEntry)
    }
    /// 设备的日程数据
    var schedulerEntry: SchedulerRegistryEntry {
//        日程删除 => (action==noAction && dayOfWeek=0)
//        日程关闭=>  (action==noAction && dayOfWeek>0)
        let entry = SchedulerRegistryEntry(year: .any(), month: .any(of: Schedule.allMonths), day: .any(), hour: .specific(hour: hour), minute: .specific(minute: minute), second: .specific(second: 0), dayOfWeek: .any(of: weekDays), action: enabled ? action : .noAction, transitionTime: .init(steps: UInt8(fadeTime), stepResolution: .seconds), sceneNumber: scene?.number ?? 0)
        return entry
    }
    
    init(id: Int, name: String, enabled: Bool, nodeAddresses: [Address] = [], groupAddresses: [Address] = [], sceneNumber: SceneNumber?, selectTargetType: TargetType = .groups, action: SchedulerAction, fadeTime: Int, weekDays: [WeekDay], hour: Int, minute: Int) {
        self.id = id
        self.enabled = enabled
        self.name = name
        self.nodeAddresses = nodeAddresses
        self.groupAddresses = groupAddresses
        self.sceneNumber = sceneNumber
        self.selectTargetType = selectTargetType
        self.action = action
        self.fadeTime = fadeTime
        self.weekDays = weekDays
        self.hour = hour
        self.minute = minute
    }
    
    init(id: Int, name: String, scheduleEntry: SchedulerRegistryEntry, nodeAddresses: [Address] = [], groupAddresses: [Address] = [], sceneNumber: SceneNumber?, selectTargetType: TargetType = .groups) {
        
        self.id = id
        self.name = name
        self.selectTargetType = selectTargetType
        self.nodeAddresses = nodeAddresses
        self.groupAddresses = groupAddresses
        self.sceneNumber = sceneNumber
        
        updata(entry: scheduleEntry)
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case enabled
        case nodeAddresses = "deviceAddresses"
        case groupAddresses
        case sceneNumber = "sceneAddress"
        case target = "selectTarget"
        case action
        case fadeTime
        case dayOfWeek
        case hour
        case minute
        case second
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
        self.selectTargetType = .init(rawValue: try container.decode(Int.self, forKey: .target)) ?? .groups
        self.action = .init(rawValue: try container.decode(UInt8.self, forKey: .action)) ?? .noAction
        self.fadeTime = try container.decode(Int.self, forKey: .fadeTime)
        self.hour = try container.decode(Int.self, forKey: .hour)
        self.minute = try container.decode(Int.self, forKey: .minute)
        self.weekDays = Schedule.getWeekDays(weekValue: try container.decode(Int.self, forKey: .dayOfWeek))
        
        let nodeAddressStrings = try container.decode([String].self, forKey: .nodeAddresses)
        nodeAddressStrings.forEach({
            if let address = Address($0) {
                self.nodeAddresses.append(address)
            }
        })
        
        let groupAddressStrings = try container.decode([String].self, forKey: .groupAddresses)
        groupAddressStrings.forEach({
            if let address = Address($0) {
                self.groupAddresses.append(address)
            }
        })
        
        let sceneNumber = try container.decode(SceneNumber?.self, forKey: .sceneNumber)
        self.sceneNumber = sceneNumber
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.enabled, forKey: .enabled)
        try container.encode(self.selectTargetType.rawValue, forKey: .target)
        try container.encode(self.action.rawValue, forKey: .action)
        try container.encode(self.fadeTime, forKey: .fadeTime)
        try container.encode(self.hour, forKey: .hour)
        try container.encode(self.minute, forKey: .minute)
        try container.encode(Schedule.getWeekValue(weekDays: self.weekDays), forKey: .dayOfWeek)
        try container.encode(self.nodeAddresses.map { $0.hex }, forKey: .nodeAddresses)
        try container.encode(self.groupAddresses.map { $0.hex }, forKey: .groupAddresses)
        try container.encode(self.scene?.number, forKey: .sceneNumber)
    }
    
    /// 复制日程
    func copy() -> Self {
        let schedule = Schedule(id: id, name: name, enabled: enabled, nodeAddresses: nodeAddresses, groupAddresses: groupAddresses, sceneNumber: sceneNumber, selectTargetType: selectTargetType, action: action, fadeTime: fadeTime, weekDays: weekDays, hour: hour, minute: minute)
        return schedule as! Self
    }
    
    
    /// 更新日程数据
    /// - Parameter entry: 设备日程数据
    func updata(entry: SchedulerRegistryEntry) {
        
        self.enabled = entry.isEnabled
//        entry.month.value > 0 && entry.action != .noAction
        self.action = entry.action
        self.sceneNumber = entry.sceneNumber
        self.fadeTime = Int(entry.transitionTime.steps)
        
        // 计算选中的重复周期
        if entry.isEnabled {
            self.weekDays = Schedule.getWeekDays(weekValue: Int(entry.dayOfWeek.value))
        }else {
            self.weekDays = []
        }
        self.hour = Int(entry.hour.value)
        self.minute = Int(entry.minute.value)
    }
    
    /// 根据周重复值获取重复周期
    static func getWeekDays(weekValue: Int) -> [WeekDay] {
        let allWeekDays :[WeekDay] = [.Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday, .Sunday]
        var selectWeekDays: [WeekDay] = []
        for (weekInt, weekDay) in allWeekDays.enumerated() {
            if weekValue >> weekInt & 1 == 1 {
                selectWeekDays.append(weekDay)
            }
        }
        return selectWeekDays
    }
    
    /// 根据重复周期获取周重复值
    static func getWeekValue(weekDays: [WeekDay]) -> Int {
        return Int(weekDays.reduce(0, { (result, day) -> UInt8 in result + day.rawValue}))
    }
    
    static func == (lhs: Schedule, rhs: Schedule) -> Bool {
        
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.enabled == rhs.enabled && lhs.selectTargetType == rhs.selectTargetType && lhs.scene?.number == rhs.scene?.number && lhs.action == rhs.action && lhs.fadeTime == rhs.fadeTime && lhs.weekDays == rhs.weekDays && lhs.hour == rhs.hour && lhs.minute == rhs.minute
    }
    
    /// 获取日程需要同步/删除的数据
    /// nodes：add/remove  【Node】
    /// groups：add/remove 【(group: [Node])】
    /// scene: add/remove  【(scene：[Group])】
    func getNeedSyncDatas() -> ScheduleSyncData {
        
        var syncNodes: [Node] = []
        var syncGroupData: [Group: [Node]] = [:]
        
//        var allSetScheduleNodes: [Node] = []
        
        // 所有需要同步的设备 直接关联-间接关联（组、场景）只设置一次不需要重复同步
        var allSyncNodes: [Node] = []
        // 所有需要删的设备 直接关联-间接关联（组、场景） 只删除一次不需要重复删除
//        var allDeleteNodes: [Node] = []
        
        switch selectTargetType {
        case .devices:
            syncNodes = nodes.filter({ $0.schedulerActions[id] == nil || !($0.schedulerActions[id]! == schedulerEntry) })
            allSyncNodes.append(contentsOf: nodes)
        case .groups:
            groups.forEach({
                let groupSyncNodes = $0.nodes.filter({ $0.schedulerSetupModel != nil && ($0.schedulerActions[id] == nil || !($0.schedulerActions[id]! == schedulerEntry)) })
                if groupSyncNodes.count > 0 {
                    syncGroupData.updateValue(groupSyncNodes, forKey: $0)
                }
                allSyncNodes.append(contentsOf: $0.nodes)
            })
        case .scene:
            scene?.info.groups.forEach({
                let groupSyncNodes = $0.nodes.filter({ $0.schedulerSetupModel != nil && ($0.schedulerActions[id] == nil || !($0.schedulerActions[id]! == schedulerEntry)) })
                if groupSyncNodes.count > 0 {
                    syncGroupData.updateValue(groupSyncNodes, forKey: $0)
                }
                allSyncNodes.append(contentsOf: $0.nodes)
            })
        }
        
        let deleteNodes = needDeleteNodes.filter({ !allSyncNodes.contains($0) })
        
        var deleteGroupData: [Group: [Node]] = [:]
        needDeleteGroups.forEach({
            let groupDeleteNodes = $0.nodes.filter({ $0.schedulerSetupModel != nil && $0.schedulerActions[id] != nil && !allSyncNodes.contains($0) && !deleteNodes.contains($0) })
            // ((!allSyncNodes.contains($0) && !allDeleteNodes.contains($0)) || !nodes.contains($0))
            if groupDeleteNodes.count > 0 {
                deleteGroupData.updateValue(groupDeleteNodes, forKey: $0)
//                allDeleteNodes.append(contentsOf: groupDeleteNodes)
            }
        })

        needDeleteScenes.forEach({ scene in
            scene.info.groups.forEach { group in
                let groupDeleteNodes = group.nodes.filter({ $0.schedulerSetupModel != nil && $0.schedulerActions[id] != nil && !allSyncNodes.contains($0) && !deleteNodes.contains($0) })
                // && !allSyncNodes.contains($0)) && !allDeleteNodes.contains($0)
                if groupDeleteNodes.count > 0 {
                    deleteGroupData.updateValue(groupDeleteNodes, forKey: group)
//                    allDeleteNodes.append(contentsOf: groupDeleteNodes)
                }
            }
        })
        
        let data = ScheduleSyncData(syncNodes: syncNodes, deleteNodes: deleteNodes, syncGroups: syncGroupData, deleteGroups: deleteGroupData)
        return data
    }
    
    /// 日程同步数据
    struct ScheduleSyncData {
        /// 需要同步的节点
        var syncNodes: [Node] = []
        /// 需要删除的节点
        var deleteNodes: [Node] = []

        /// 需要同步的组-设备
        var syncGroups: [Group: [Node]] = [:]
        /// 需要删除的组-设备
        var deleteGroups: [Group: [Node]] = [:]
  
        /// 是否空数据
        func isEmpty() -> Bool {
            return syncNodes.isEmpty && deleteNodes.isEmpty && syncGroups.isEmpty && deleteGroups.isEmpty
        }
    }

}

extension DeviceSwitchData {
    
    /// 获取动能开关需要同步/删除的数据
    func getNeedSyncDatas(deleteSwitch: Bool = false) -> SwitchSyncData {
        
        var syncGroupData: [Group: [Node]] = [:]
        var deleteGroupData: [Group: [Node]] = [:]
        var syncProxy: Node?
        var deleteProxy: Node?
        
        if let linkGroup = self.linkGroup {
            var allNodes: [Node] = []
            if deleteSwitch { // 删除动能开关
                
                bindGroups.forEach { group in
                    allNodes.append(contentsOf: group.nodes)
                    let nodes = group.nodes.filter({ $0.getEnOceanUnSubscriptionMessageHandles(group: linkGroup).count > 0 })
                    if nodes.count > 0 {
                        deleteGroupData.updateValue(nodes, forKey: group)
                    }
                }
                // 当前设置动能开关的代理设备
                let currentProxy = allNodes.first(where: { $0.enOceanMacAddress != nil && $0.enOceanMacAddress == self.enOceanMacAddress })
                deleteProxy = currentProxy
                
            }else {
                // 同步数据
                bindGroups.forEach { group in
                    allNodes.append(contentsOf: group.nodes)
                    if !unbindGroups.contains(group) {
                        let nodes = group.nodes.filter({
                            $0.getEnOceanSubscriptionMessageHandles(group: linkGroup).count > 0
                        })
                        if nodes.count > 0 {
                            syncGroupData.updateValue(nodes, forKey: group)
                        }
                    }
                }
                
                unbindGroups.forEach({ group in
                    let nodes = group.nodes.filter({ $0.getEnOceanUnSubscriptionMessageHandles(group: linkGroup).count > 0 })
                    if nodes.count > 0 {
                        deleteGroupData.updateValue(nodes, forKey: group)
                    }
                })
                
                // 判断是否需要同步动能开关代理
                if let mac = self.enOceanMacAddress, let key = self.enOceanSecurityKey, let proxyNode = self.proxyNode {
                    if proxyNode.getEnOceanSwitchBindMessageHandles(enOceanMacAddress: mac, securityKey: key, group: linkGroup, enabled: self.enabled, switchKeys: MeshEnOceanProxyServer.SwitchKey.defaultKeys(sceneA: self.sceneA, sceneB: self.sceneB)).count > 0 {
                        syncProxy = proxyNode
                    }
                }
                
                
                // 当前设置动能开关的代理设备
//                let currentProxy = allNodes.first(where: { $0.enOceanMacAddress != nil && $0.enOceanMacAddress == self.enOceanMacAddress })
                // 判断当前的代理设备和目标的代理设备是否不一样，不一样需要删除之前的代理
//                if currentProxy?.primaryUnicastAddress != self.proxyNodeAddress {
//                    deleteProxy = currentProxy
//                }
                if let node = self.deleteProxyNode, node.enOceanMacAddress != nil {
                    deleteProxy = node
                }
            }
        }
        let data = SwitchSyncData(syncGroups: syncGroupData, deleteGroups: deleteGroupData, syncProxy: syncProxy, deleteProxy: deleteProxy)
        return data
    }
    
    /// 动能开关同步数据
    struct SwitchSyncData {
        /// 需要同步的组-设备
        var syncGroups: [Group: [Node]] = [:]
        /// 需要删除的组-设备
        var deleteGroups: [Group: [Node]] = [:]
        /// 同步的代理设备
        var syncProxy: Node?
        /// 删除的代理设备
        var deleteProxy: Node?
  
        /// 是否空数据
        func isEmpty() -> Bool {
            return syncGroups.isEmpty && deleteGroups.isEmpty && syncProxy == nil && deleteProxy == nil
        }
    }
    
    /// 是否需要同步数据
    var needSyncData: Bool {
        return !self.getNeedSyncDatas().isEmpty()
    }
}

extension Node {

    static private var localVersionSEQ = 1
    
    /// 本地缓存的配置版本号
    var localVersionSEQ: UInt32 {
        get {
            objc_getAssociatedObject(self, &Node.localVersionSEQ) as? UInt32 ?? 0
        }set {
            objc_setAssociatedObject(self, &Node.localVersionSEQ, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// mac地址分割
    var macAddressResult: String? {
        if let macAddress = macAddress, !macAddress.isEmpty {
            var result = ""
            var offset = 0
            for _ in 0..<Int(macAddress.count / 2) {
                if offset + 2 > macAddress.count { break }
                let string = macAddress.subString(rang: NSRange(location: offset, length: 2))
                offset += 2
                result.append(String(format: "%@%@", result.isEmpty ? "" : ":", string))
            }
            return result
        }
        return nil
    }
    
    /// 图标名称
    var iconName: String {
        return "device_\(self.productIdentifier?.hex ?? "unknown")"
    }
    
    /// 离线图标名称
    var offlineIconName: String {
        return "device_offline_\(self.productIdentifier?.hex ?? "unknown")"
    }
    
    /// 待同步图标名称
    var unsyncIconName: String {
        return "device_unsync_\(self.productIdentifier?.hex ?? "0001")"
    }
    
    /// 是否需要同步数据
    var needSync: Bool {
        return !getNeedSyncGroupData().isEmpty()
    }
    
    /// 获取设备需要同步组的数据
    /// - Parameter group: 传入需要加入的组，不传则当前组
    func getNeedSyncGroupData(group: Group? = nil) -> SyncData {
        
        var data = SyncData()
        guard let group = group ?? self.group else {
            return data
        }
        
        if self.group != nil && groupState == GroupState.exitFailure { // 设备退出组失败
            data.unsubscribeGroup = true
        }else if getSubscribeToGroupMessages(group).count > 0 { // 设备订阅组数据不完整
            data.subscribeGroup = true
        }
        
        var nodeDeleteScenes: [Scene] = []
        var nodeSyncScenes: [SceneExecuteData] = []
        
        if self.sceneModel != nil {
            // 组内待删除的场景
            let deleteScenes = group.info.sceneExecuteDatas.filter({ $0.state == .waitDelete })
            
            // 设备待删除的场景list
            nodeDeleteScenes = self.scenes.filter({ scene in deleteScenes.contains(where: { scene.number == $0.sceneNumber }) })
            // 设备待同步的场景list
            nodeSyncScenes = group.info.sceneExecuteDatas.filter({ sceneData in
                self.sceneSetupModel != nil && (!self.sceneExecuteDatas.contains(where: { $0.sceneNumber == sceneData.sceneNumber }) || !(self.sceneExecuteDatas.first(where: {$0.sceneNumber == sceneData.sceneNumber})! == sceneData) )
            })
        }
        
        var nodeSyncSchedules: [Schedule] = []
        var deleteSchedules: [Schedule] = []
        if self.schedulerModel != nil {
            // 组内待删除的日程
            let groupDeleteSchedules = group.info.bindSchedules.filter({ schedule in
                return schedule.needDeleteGroups.contains(where: { $0.address.address == group.address.address })
            })
            // 设备待删除的日程list
            deleteSchedules = groupDeleteSchedules.filter({ schedule in self.schedulerActions.contains(where: { $0.key == schedule.id }) })
            // 设备待同步的日程list
            nodeSyncSchedules = group.info.bindSchedules.filter { schedule in
                !self.schedulerActions.contains(where: { $0.key == schedule.id }) || !self.schedulerActions.contains(where: { $0.value == schedule.schedulerEntry })
            }
        }
        
        // 设备待删除的动能开关list
        var deleteSwitchs: [DeviceSwitchData] = []
        // 设备待同步的动能开关list
        var nodeSyncSwitchs: [DeviceSwitchData] = []
//        group.info.switchs.filter({ switchData in
//            switchData.unbindGroupAddresses.contains(group.address.address)
//        })
        // 设置动能开关代理
        var setSwitchProxy: DeviceSwitchData?
        // 删除设备动能开关代理
        var deleteSwitchProxy: DeviceSwitchData?
        if self.sunricherVendorModel != nil {
            group.info.allSwitchs.forEach({ switchData in
                if let linkGroup = switchData.linkGroup {
                    // 判断代理设备是否未设置完成
                    if switchData.proxyNodeAddress == self.primaryUnicastAddress, let enOceanMacAddress = switchData.enOceanMacAddress, let enOceanSecurityKey = switchData.enOceanSecurityKey {
                        if self.getEnOceanSwitchBindMessageHandles(enOceanMacAddress: enOceanMacAddress, securityKey: enOceanSecurityKey, group: linkGroup, enabled: switchData.enabled, switchKeys: MeshEnOceanProxyServer.SwitchKey.defaultKeys(sceneA: switchData.sceneA, sceneB: switchData.sceneB)).count > 0 {
                            setSwitchProxy = switchData
                        }
                    }
                    if switchData.unbindGroupAddresses.contains(group.address.address), self.getEnOceanUnSubscriptionMessageHandles(group: linkGroup).count > 0 {
                        deleteSwitchs.append(switchData)
                    }else if switchData.bindGroupAddresses.contains(group.address.address), self.getEnOceanSubscriptionMessageHandles(group: linkGroup).count > 0 {
                        nodeSyncSwitchs.append(switchData)
                    }
                }
            })
        }
        
        let groupProfile = group.info.profile
        var syncProfile: [ProfileType] = []
        // 启用的传感器model
        var enableSensorModels: [Model] = []
        // 禁用的传感器model
        var disableSensorModels: [Model] = []
        
        if groupState == .inGroup || data.subscribeGroup { // 在组内待同步/将要加入组
            // 光照类型
            let daylightType = groupProfile.type == .occupancy_daylight || groupProfile.type == .vacancy_daylight || groupProfile.type == .daylight
        
            // 占用类型
            let occupancyType = groupProfile.type == .occupancy_daylight || groupProfile.type == .vacancy_daylight || groupProfile.type == .occupancy || groupProfile.type == .vacancy
            // 组内是否启用了光照传感器
            var daylightEnabled = false
            if let daylightNode = group.info.ambientLightSensorNode, daylightNode.sensorCalibrated {
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
                        if lightLCProperty.timeRunOn != 0xFFFFFF {
                            syncProfile.append(.t2(second: 0xFFFFFF))
                        }
                    }
                }
                
                groupProfile.lightData.times.forEach { time in
                    switch time {
                    case .t1(let second):
                        if lightLCProperty.timeFadeOn == nil || lightLCProperty.timeFadeOn! != min(second * 1000, 0xFFFFFF) {
                            syncProfile.append(.t1(second: second))
                        }
                    case .t2(let second):
                        if lightLCProperty.timeRunOn == nil || lightLCProperty.timeRunOn! != min(second * 1000, 0xFFFFFF) {
                            syncProfile.append(.t2(second: second))
                        }
                    case .t3(let second):
                        if lightLCProperty.timeFade == nil || lightLCProperty.timeFade! != min(second * 1000, 0xFFFFFF) {
                            syncProfile.append(.t3(second: second))
                        }
                    case .t4(let second):
                        if lightLCProperty.timeProlong == nil || lightLCProperty.timeProlong! != min(second * 1000, 0xFFFFFF) {
                            syncProfile.append(.t4(second: second))
                        }
                    case .t5(let second):
                        if lightLCProperty.timeFadeStandbyAuto == nil || lightLCProperty.timeFadeStandbyAuto! != min(second * 1000, 0xFFFFFF) {
                            syncProfile.append(.t5(second: second))
                        }
                    }
                }
               
               if daylightType { // 光照配置下生效
                   // 调节速率
                   let speedValue = groupProfile.adjustSpeed
                   let regulatorData = Node.getLightRegulator(speed: speedValue)
                   if lightLCProperty.regulatorKid == nil || lightLCProperty.regulatorKid! != regulatorData.regulatorKid ||
                        lightLCProperty.regulatorKiu == nil || lightLCProperty.regulatorKiu! != regulatorData.regulatorKiu ||
                        lightLCProperty.regulatorKpd == nil || lightLCProperty.regulatorKpd! != regulatorData.regulatorKpd ||
                        lightLCProperty.regulatorKpu == nil || lightLCProperty.regulatorKpu! != regulatorData.regulatorKpu ||
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
                if powerUpState != .default || Node.getLightness(lightness100: Int(level)) != defalutLightness {
                    syncProfile.append(.powerOnState(state: .definedLightLevel(level)))
                }
            }
            
        }else if groupState == .exitFailure || data.unsubscribeGroup { // 退出组
            
            let disableSensorModels = sensorModels.filter({ $0.publish?.publicationAddress == group.address })
            if disableSensorModels.count > 0 {
                syncProfile.append(.sensorDisable(sensorModels: disableSensorModels))
            }
            
            let defaultRange: ClosedRange<UInt16> = 0...65535
            if lightnessSetupModel != nil, lightnessRange != defaultRange {
                syncProfile.append(.highLowEndTrim(range: 0...100))
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
                if self.enOceanMacAddress != nil {
                    if let proxySwitch = group.info.allSwitchs.first(where: { ($0.proxyNodeAddress == self.primaryUnicastAddress && $0.enOceanMacAddress == self.enOceanMacAddress) || $0.deleteProxyNodeAddress == self.primaryUnicastAddress }) {
                        deleteSwitchProxy = proxySwitch
                    }
                }
            }
        }
        
        data.syncScenes = nodeSyncScenes
        data.syncSchedules = nodeSyncSchedules
        data.deleteScenes = nodeDeleteScenes
        data.deleteSchedules = deleteSchedules
        data.syncProfile = syncProfile
        data.syncSwitchs = nodeSyncSwitchs
        data.deleteSwitchs = deleteSwitchs
        data.syncSwitchProxy = setSwitchProxy
        data.deleteSwitchProxy = deleteSwitchProxy
        return data
    }

    
    /// 根据色温范围获取对应色温颜色
    /// - Parameter cct100: 0~100色温
    /// - Returns: 对应色温颜色
    static func getCctMixColor(temperature100: Int) -> UIColor {
        // 暖色
        let components1 = RGB(255, 108, 0).cgColor.components!
        // 过渡色
        let components2 = RGB(255, 255, 255).cgColor.components!
        // 冷色
        let components3 = RGB(114, 179, 255).cgColor.components!
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        // 0~1比例
        var ratio: CGFloat = 0
        switch temperature100 {
        case 0...50: // 0~50取暖色到过渡色的混色
            ratio = CGFloat(temperature100) / 50.0
            r = components2[0] * ratio + components1[0] * (1.0 - ratio)
            g = components2[1] * ratio + components1[1] * (1.0 - ratio)
            b = components2[2] * ratio + components1[2] * (1.0 - ratio)
        case 50...100: // 50~100取过渡色到冷色的混色
            ratio = CGFloat(temperature100 - 50) / 50.0
            r = components3[0] * ratio + components2[0] * (1.0 - ratio)
            g = components3[1] * ratio + components2[1] * (1.0 - ratio)
            b = components3[2] * ratio + components2[2] * (1.0 - ratio)
        default:
            break
        }
        let color =  UIColor(red: r, green: g, blue: b, alpha: 1)
        return color
    }
    
    /// 删除设备缓存的所有扩展数据
    func deleteExtension() {
        guard let uuid = self.network?.uuid.uuidString else {
            return
        }
        // 删除动能开关
        deleteEnOceanSwitch()
        // 判断删除的设备是不是组绑定的光照传感器
        if let group = self.network?.groups.first(where: { $0.info.ambientLightSensorNodeAddress == primaryUnicastAddress }) {
            group.info.ambientLightSensorNodeAddress = nil
            group.info.save(meshUUID: uuid, subnetworkId: group.subNetworkId)
        }
    }
    
    /// 删除组内的场景缓存
    /// - Parameter sceneId: 场景id
    func delete(sceneId: SceneNumber) {
        if let index = self.sceneExecuteDatas.firstIndex(where: { $0.sceneNumber == sceneId }) {
            self.sceneExecuteDatas.remove(at: index)
            self.savePropertys()
        }
    }
    
    /// 删除绑定的动能开关
    func deleteEnOceanSwitch(enOceanMacAddress: String? = nil) {

        guard let uuid = self.network?.uuid.uuidString else {
            return
        }
        let subNetworkId = self.subNetworkId
        // 删除group switch代理缓存
        
        if let mac = enOceanMacAddress ?? self.enOceanMacAddress, let switchData = MeshNetworkManager.instance.switchs.first(where: { $0.deleteProxyNodeAddress == self.primaryUnicastAddress || $0.enOceanMacAddress == mac }) {
//           let switchData = DeviceSwitchData.load(meshUUID: uuid, macAddress: mac).first {
            if switchData.proxyNodeAddress == self.primaryUnicastAddress {
                switchData.proxyNodeAddress = nil
                switchData.enOceanMacAddress = nil
                switchData.enOceanSecurityKey = nil
            }
            if switchData.deleteProxyNodeAddress == self.primaryUnicastAddress {
                switchData.deleteProxyNodeAddress = nil
            }
            switchData.save(meshUUID: uuid, networkId: subNetworkId)
            // 更新开关对应组缓存
//            if let groupCacheSwitch = groupSwitch.group?.info.switchs.first(where: { $0.id == groupSwitch.id }) {
//                groupCacheSwitch.proxyNodeAddress = nil
//            }
        }
        
//        self.enOceanMacAddress = nil
//        self.enOceanKeySceneNumbers = []
        
    }
    
    
    /// 更新节点缓存数据
    /// - Parameter isSuccess: 消息发送成功
    func updateData(message: MeshMessage, isSuccess: Bool = true) {
       
        guard isSuccess || message is ConfigModelSubscriptionDelete else {
            return
        }
        
//        let meshUUID = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString
//        let networkKey = MeshNetworkManager.instance.currentNetworkKey
//        let isSuccess = messageHandle.isSuccessful
//        let message = messageHandle.message
        switch message {
        case is ConfigModelSubscriptionAdd:
            let subscriptionMessage = message as! ConfigModelSubscriptionAdd
            // 加入组
            if subscriptionMessage.address == self.group?.address.address {
                if self.groupState != .inGroup {
                    self.groupState = .inGroup
                    self.save()
                }
            }
//            else if let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(subscriptionMessage.address)), group.isVirtual { // 订阅其它组（动能开关功能组等）
//                
//                
//                
//            }
//                self.saveNodeInfo(meshUUID: uuid, networkKey: networkKey)
            
        case is ConfigModelSubscriptionDelete:
            
            let subscriptionMessage = message as! ConfigModelSubscriptionDelete
            
            if let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(subscriptionMessage.address)) {
                if group.isVirtual { // 动能开关虚拟组
                    guard isSuccess else {
                        return
                    }
                    if let switchData = MeshNetworkManager.instance.switchs.first(where: { $0.linkGroupAddress == group.address.address }), let nodeGroup = self.group {
                        if isSuccess { // 删除成功
                            // 判断是否之前动能开关删除组失败，再次删除后成功，接着判断组里面是否设备都清空动能开关数据
                            if switchData.unbindGroupAddresses.contains(nodeGroup.address.address), !nodeGroup.nodes.contains(where: { $0.getEnOceanUnSubscriptionMessageHandles(group: group).count > 0 }) {
                                switchData.unbindGroupAddresses.removeAll(where: { $0 == nodeGroup.address.address })
                                switchData.save()
                            }
                            
                        }else { // 删除失败
                            if !switchData.unbindGroupAddresses.contains(nodeGroup.address.address) {
                                switchData.unbindGroupAddresses.append(nodeGroup.address.address)
                                switchData.save()
                            }
                        }
                    }
                }else { // 设备组 退出真实组
                    if isSuccess {
                        if self.group == nil { // 组删除设备成功
                            self.groupState = .none
                            let groupAddress = (message as! ConfigModelSubscriptionDelete).address
                            if let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(groupAddress)), group.info.ambientLightSensorNodeAddress == primaryUnicastAddress { // 判断删除的设备是不是组绑定的光照传感器
                                group.info.ambientLightSensorNodeAddress = nil
                                 // 保存缓存
                                group.info.save()
                            }
                            self.save()
                        }
                    }else { // 删除失败
                        if self.groupState != .exitFailure {
                            self.groupState = .exitFailure
                            self.save()
                        }
                    }
                }
            }
            
        case is SceneStore:
            let sceneId = (message as! SceneStore).scene
            var cct = temperature
            // 不支持cct，使用group预配置的cct值
            if self.temperatureModel == nil, let groupCct = self.group?.info.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneId })?.cct {
                cct = groupCct
            }
            if let sceneData = self.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneId }) {
                sceneData.cct = cct
            }else {
                self.sceneExecuteDatas.append(SceneExecuteData(sceneNumber: sceneId, isOn: self.lightness > 0, lightness: self.lightness, cct: cct))
            }
            self.savePropertys()
//            let executeData = SceneExecuteData(scenenumber: sceneId, lightness: self.lightness, cct: cct)
//            print("address: \(primaryUnicastAddress) scene:\(sceneId) lightness: \(self.lightness100) cct: \(cct)")
//            let groupScene = self.group?.info.sceneExecuteDatas[sceneId]
//            print("target scene:\(sceneId) lightness: \(groupScene!.lightness) cct: \(groupScene!.cct)")
//            self.sceneDatas.updateValue(executeData, forKey: sceneId)
//            if let uuid = meshUUID {
//                SceneExecuteData.save(meshUUID: uuid, networkKey: networkKey, address: primaryUnicastAddress, sceneId: Int(sceneId), sceneData: executeData)
//            }
            break
        case is SceneDelete:
            let sceneId = (message as! SceneDelete).scene
//            self.sceneDatas.removeValue(forKey: sceneId)
            delete(sceneId: sceneId)
//            if let uuid = meshUUID {
//                SceneExecuteData.deleteData(meshUUID: uuid, address: primaryUnicastAddress, sceneId: Int(sceneId))
                
                // 组对应场景数据是否待删除
                if let scene = MeshNetworkManager.instance.scenes.first(where: {$0.number == sceneId}), let group = self.group, let groupSceneData = group.info.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneId }), groupSceneData.state == .waitDelete {
                    // 组内设备已删除对应场景缓存
                    if !group.nodes.contains(where: { node in node.sceneExecuteDatas.contains(where: { $0.sceneNumber == sceneId }) }) {
                        group.info.sceneExecuteDatas.removeAll(where: { $0.sceneNumber == sceneId })
                        // 设备加入组，组加入场景，场景加入日程 Node->Group->Scene->Schedule
                        // 场景加入日程后关联场景的组也加入日程，场景移出组后吧组间接关联的日程删除
                        group.info.bindSchedules.removeAll(where: { groupSchedule in scene.info.bindSchedules.contains(where: { $0.id == groupSchedule.id }) })
                        group.info.save()
                    }
                }
//            }
           
        case is SchedulerActionSet:
//            let actionMessage = (message as! SchedulerActionSet)
//            if !actionMessage.entry.isValid {
//                self.schedulerActions.removeValue(forKey: Int(actionMessage.index))
//                if let uuid = meshUUID {
//                    self.savePropertys()
//                    
//                    // 对应日程删除设备/组
//                    if let schedule = MeshNetworkManager.instance.schedules.first(where: {$0.id == actionMessage.index}) {
//
//                        // 设备已加入组，并且组内没有设备缓存对应日程数据，则直接让日程删除该组缓存
//                        var isSaveSchedule = false
                        // 判断组是否因为此设备而无法从日程中删除，设备删除后组也从日程中删除
//                        if let group = schedule.needDeleteGroups.first(where: { $0.nodes.contains(self) }), !group.nodes.contains(where: { $0.schedulerActions[schedule.id] != nil }) {
//                            schedule.needDeleteGroups.removeAll(where: { $0.address.address == group.address.address })
//                            group.info.bindSchedules.removeAll(where: { $0.id == schedule.id })
//                            
//                            isSaveSchedule = true
//                        }
                        // 判断场景是否因为此设备无法从日程中删除，设备删除后场景也从日程中删除
//                        if let scene = schedule.needDeleteScenes.first(where: { $0.info.groups.contains(where: { $0.nodes.contains(self) }) }), !scene.info.groups.contains(where: { $0.nodes.contains(where: { $0.scheduleDatas[schedule.id] != nil }) }) {
//                            schedule.needDeleteScenes.removeAll(where: { $0.number == scene.number })
//                            isSaveSchedule = true
//                        }
                        
//                        if schedule.needDeleteNodes.contains(self) {
//                            schedule.needDeleteNodes.removeAll(where: { $0.primaryUnicastAddress == self.primaryUnicastAddress })
//                            isSaveSchedule = true
//                        }
//                        if isSaveSchedule {
//                            schedule.save(meshUUID: uuid, meshNetworkKey: networkKey)
//                        }
//                    }
//                    
//                }
//                
//            }
            break
        case is LightLCLightOnOffSet, is LightLCLightOnOffSetUnacknowledged: // 点击Auto
            if let isOn = (message as? LightLCLightOnOffSet)?.isOn ?? (message as? LightLCLightOnOffSetUnacknowledged)?.isOn, let group = group {
                if isOn {
                    let profile = group.info.profile
                    let lightData = profile.lightData.data
                    // daylight并且已校准则不更新本地数据，更新设备状态到第一阶段
                    if !((profile.type == .occupancy_daylight || profile.type == .vacancy_daylight || profile.type == .daylight) && group.info.ambientLightSensorNode != nil) {
                        let lightness = Node.getLightness(lightness100: lightData.occupancyLevel)
                        group.lightnessNodes.forEach({
                            if !isOn {
                                $0.trunOffLightness = $0.lightness
                            }
                            $0.lightness = lightness
                            $0.isOn = lightness > 0
                        })
                    }
                    
                }else {
                    group.nodes.forEach({
                        $0.isOn = false
                        $0.lightness = 0
                    })
                }
            }
//        case is GenericDeltaSetUnacknowledged: // 亮度+/-
//            let delta = (message as! GenericDeltaSetUnacknowledged).delta
//            if let group = self.group {
//                group.nodes.forEach({
//                    
//                    var result = Int($0.lightness) + Int(delta)
//                    result = min(max(result, Int($0.lightnessRange.lowerBound)), Int($0.lightnessRange.upperBound))
//                    $0.lightness = UInt16(result)
//                })
//            }            
            
        case is SceneRecall, is SceneRecallUnacknowledged: // 场景激活
            if let sceneNumber = (message as? SceneRecall)?.scene ?? (message as? SceneRecallUnacknowledged)?.scene, let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneNumber }) {
                scene.info.groups.forEach({
                    if let sceneData = $0.info.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneNumber }) {
                        let lightness = sceneData.lightness
                        $0.nodes.forEach({ node in
                            node.isOn = lightness > 0
                            node.lightness = lightness
                            node.temperature = UInt16(sceneData.cct)
                        })
                    }
                })
            }
        case is SunricherVendorSet: // 设置自定义消息
            if let vendorMessage = message as? SunricherVendorSet {
                if case .enOceanDelete(let macAddress) = vendorMessage.function { // 删除EnOcean按键绑定
                    // 判断是否之前删除代理失败
//                    if let switchData = MeshNetworkManager.instance.switchs.first(where: { ($0.proxyNodeAddress == self.primaryUnicastAddress || $0.deleteProxyNodeAddress == self.primaryUnicastAddress) }) {
//                        if switchData.deleteProxyNodeAddress == self.primaryUnicastAddress {
//                            switchData.deleteProxyNodeAddress = nil
//                        }
//                        if switchData.proxyNodeAddress == self.primaryUnicastAddress {
//                            switchData.proxyNodeAddress = nil
//                        }
//                        switchData.save()
//                    }
                    deleteEnOceanSwitch(enOceanMacAddress: macAddress)
                }
            }
        default:
            break
        }
        
        
    }
    
}

/// 同步数据
struct SyncData {
    /// 设备是否需要订阅/加入组（订阅信息不完整）
    var subscribeGroup: Bool = false
    /// 设备是否需要退出组
    var unsubscribeGroup: Bool = false
    /// 设备需要同步的场景数据list
    var syncScenes: [SceneExecuteData] = []
    /// 设备需要同步的日程list
    var syncSchedules: [Schedule] = []
    /// 设备待删除的场景数据list
    var deleteScenes: [Scene] = []
    /// 设备待删除的日程list
    var deleteSchedules: [Schedule] = []
    /// 设备需要同步的灯光配置
    var syncProfile: [ProfileType] = []
    /// 设备是否需要删除动能开关绑定
    var deleteSwitchProxy: DeviceSwitchData?
    /// 设备是否需要设置动能开关绑定
    var syncSwitchProxy: DeviceSwitchData?
    /// 设备待同步的开关list
    var syncSwitchs: [DeviceSwitchData] = []
    /// 设备待删除的开关list
    var deleteSwitchs: [DeviceSwitchData] = []
    
    /// 是否不需要同步
    func isEmpty() -> Bool {
        return !(subscribeGroup || unsubscribeGroup || syncScenes.count > 0 || syncSchedules.count > 0 || deleteScenes.count > 0 || deleteSchedules.count > 0 || syncProfile.count > 0 || syncSwitchs.count > 0 || deleteSwitchs.count > 0 || syncSwitchProxy != nil || deleteSwitchProxy != nil)
    }
}

