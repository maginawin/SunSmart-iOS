//
//  MeshNetwork+SunSmart.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/18.
//

import Foundation
import NordicSigMeshSDK

struct BatteryPowerSwitchTargetSubscriptionSnapshot: Hashable {
    let linkGroupAddress: Address
    let elementOffset: UInt16
    let modelIdentifier: UInt16
    let companyIdentifier: UInt16?
}

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
        let meshNetworkManager = MeshNetworkManager.createMeshNetwork(meshUUID: id, meshNetworkName: name, localAddress: Address.minUnicastAddress)
//        MeshLibManager.manager.createMeshNetwork(meshUUID: id, meshNetworkName: name, connected: false)
        let site = SiteData(region: UserData.currentServerRegion, id: id, meshUUID: id, meshNetworkId: meshNetworkManager.mainNetworkKey.networkId.hex, name: name, imageId: 1, type: .office, permission: .owner, create: time,isFavourite: false, sourceType: .create)
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
        
        guard let subnetworkData = MeshNetworkManager.addSubnetwork(meshUUID: meshUUID, networkKeyName: name, applicationKeyName: name) else {
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
        
        /// 获取回收后的供应者地址数据
        func getResultProvisionerData(meshUUID: String) -> [String: Any]? {
            var provisionerData: [String: Any]?
            let meshNetwork = MeshNetwork.load(meshUUID: meshUUID, allData: false)
            if let localProvisioner = meshNetwork?.localProvisioner {
                
                let deallocatedUnicastRange = self.deviceAddresses.splitArray().compactMap { array in
                    if let lowAddress = array.first, let highAddress = array.last {
                        return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
                    }
                    return nil
                }
                deallocatedUnicastRange.forEach({
                    localProvisioner.deallocate(unicastAddressRange: $0)
                })
                // 组地址
                let deallocatedGroupRange = self.groupAddresses.splitArray().compactMap { array in
                    if let lowAddress = array.first, let highAddress = array.last {
                        return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
                    }
                    return nil
                }
                deallocatedGroupRange.forEach({
                    localProvisioner.deallocate(groupAddressRange: $0)
                })
                
                // 场景地址
                let deallocatedSceneRange = self.sceneAddresses.splitArray().compactMap { array in
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
            return provisionerData
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
    
    
    /// 获取site解绑spaces回收地址数据（异步加载数据，避免阻塞主线程）
    /// - Parameter spaces: spaces
    /// - Returns: 回收地址数据
    func getRecycleAddressData(unbindSpaces spaces: [SpaceData]) async -> RecycleAddressData {

        return await withCheckedContinuation { continuation in
            
            guard spaces.count > 0 else {
                continuation.resume(returning: .init(deviceAddresses: [], groupAddresses: [], sceneAddresses: [], provisionerData: nil))
                return
            }
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
            
            let meshNetwork = MeshNetwork.load(meshUUID: self.meshUUID, allData: false)
            
            if self.spaces.count - spaces.count <= 0 { // 没有space了
                /// 废弃的设备地址
                exclusionAddresses = MeshAPI.getExclusionAddresses(meshUUID: self.meshUUID).map({ (Int($0.ivIndex), $0.addresses.map({ Int($0) })) })
                // 将手机地址回收
                if let meshNetwork = meshNetwork,
                   let localProvisioner = meshNetwork.localProvisioner,
                   let localAddress = localProvisioner.primaryUnicastAddress {
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
                    // 删除本地手机节点
                    if let localNode = localProvisioner.node {
                        meshNetwork.remove(node: localNode)
                    }
                    self.localAddress = nil
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
            continuation.resume(returning: .init(deviceAddresses: recycleDeviceAddresses.sorted(), groupAddresses: recycleGroupAddresses.sorted(), sceneAddresses: recycleSceneAddresses.sorted(), exclusionAddresses: exclusions, provisionerData: provisionerData))
        }
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
//        let meshManager = MeshNetworkManager.loadMeshNetwork(meshUUID: meshUUID)
//        _ = meshManager?.removeSubnetwork(networkId: self.meshNetworkId)
        _ = MeshNetworkManager.removeSubnetwork(meshUUID: self.meshUUID, networkId: self.meshNetworkId)
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
            self.deleteData()
        }
        return true
    }
    
}

extension MeshLibManager {
    
    static var supportDeviceInfosKey: UInt8 = 0
    
    /// 支持的设备信息list（未配置设备则不可添加）
    var supportDeviceInfos: [MeshDeviceConfigInfo] {
        get {
            guard let infos = objc_getAssociatedObject(self, &MeshLibManager.supportDeviceInfosKey) as? [MeshDeviceConfigInfo] else {
                let defaultConfigInfos = MeshDeviceConfigInfo.defaultConfigInfos
                self.supportDeviceInfos = defaultConfigInfos
                return defaultConfigInfos
            }
            return infos
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
        static var schedulesKey: UInt8 = 0
        static var switchsKey: UInt8 = 0
        static var donglesKey: UInt8 = 0
    }

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

    func batteryPowerSwitchData(linkGroupAddress: Address) -> PJEightKeySwitchData? {
        guard let switchData = switchs.first(where: { switchData in
            guard switchData.linkGroupAddress == linkGroupAddress else {
                return false
            }
            return switchData is PJEightKeySwitchData || switchData.proxyNode?.isBatteryPowerSwitch == true
        }) else {
            return nil
        }
        if let batteryPowerSwitchData = switchData as? PJEightKeySwitchData {
            return batteryPowerSwitchData
        }
        return switchData.batteryPowerSwitchData
    }
    
    /// 当前子网内dongle list
    var dongles: [DeviceDongleData] {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.donglesKey) as? [DeviceDongleData] ?? []
        }set {
            objc_setAssociatedObject(self, &AssociatedKey.donglesKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 获取网络扩展数据
    func loadExtensionData(result: ((Bool)->Void)? = nil) {
        
        guard let uuid = self.meshNetwork?.uuid.uuidString else {
            result?(false)
            return
        }
        
        DispatchQueue.global().async {
            
            let subNetworkId = self.currentNetworkKey.networkId.hex
            
            self.schedules = Schedule.load(meshUUID: uuid, meshNetworkId: subNetworkId)
            
            self.groups.forEach({ group in
                group.info = GroupInfo.load(meshUUID: uuid, address: group.address.address) ?? GroupInfo(address: group.address.address)
                
                // 兼容旧版本profile未保存到场景的设备
//                let noGeneralLightControlSceneNodes = group.nodes.filter({ node in node.requiredFunctionTypes.contains(.lightLCScene) && node.lightLCSceneSetupModel != nil && !node.lightControlSceneExecuteDatas.contains(where: { $0.sceneNumber == .generalLightControlScene }) })
//                noGeneralLightControlSceneNodes.forEach({ node in
//                    let sceneExecuteData = SceneExecuteData(sceneNumber: .generalLightControlScene, isOn: node.isOn, lightness: node.lightness, cct: node.temperature, lightControlData: node.lightLCProperty.copy())
//                    node.lightControlSceneExecuteDatas.insert(sceneExecuteData, at: 0)
//                })
                
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
            
            self.switchs = DeviceSwitchData.load(meshUUID: uuid, meshNetworkId: subNetworkId)
            self.dongles = DeviceDongleData.load(meshUUID: uuid, meshNetworkId: subNetworkId)

            DispatchQueue.main.async {
                result?(true)
            }
        }
        
    }
    
    /// 获取下一个节点名称
    /// - Parameter defaultName: 默认名称
    /// - Returns: 分配的节点名称
    func getNextNodeName(_ defaultName: String? = nil) -> String {
        objc_sync_enter(self)
        
        
        var resultName = (defaultName ?? "device_defalut_name".localizedString) + String(format: "%d", 1)
        // 已存在的节点名称
        let existNames = realNodes.map({ $0.name ?? "" })
        for index in 1...32767 {
            // ID001
            
            let name = (defaultName ?? "device_defalut_name".localizedString) + String(format: "%d", index)
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
        for index in 1...1000 {
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
    func getNextSwitchName(_ defaultName: String = "switch_defalut_name".localizedString) -> String {
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
    
    /// 获取下一个Dongle名称
    func getNextDongleName(_ defaultName: String = "etc_default_name".localizedString) -> String {
        
        // 已存在的开关名称
        let existNames = dongles.map({ $0.name })
        for index in 1...16 {
            let name = defaultName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defaultName + "1"
    }
    
    /// Dongle是否重名
    /// - Parameter name: 名称
    /// - Returns: 是否重名
    func isDongleTautonym(name: String) -> Bool {
        return dongles.contains(where: { $0.name == name })
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

    @discardableResult
    func ensureBatteryPowerSwitchLinkGroup(_ switchData: DeviceSwitchData) -> Bool {
        if switchData.linkGroupAddress != nil {
            return true
        }
        guard let meshUUID = self.meshNetwork?.uuid.uuidString,
              MeshAPI.getAvailableGroupAddresses(meshUUID: meshUUID).count >= 1 else {
            return false
        }
        guard let group = try? MeshAPI.createGroup(name: switchData.name + "-Group", isVirtual: true) else {
            return false
        }
        switchData.linkGroupAddress = group.address.address
        switchData.subLinkGroupAddress = nil
        return true
    }

    /// 为 Power Switch 创建对应的 8 键开关数据
    @discardableResult
    func createDefaultSwitch(forBatteryPowerSwitch node: Node) -> DeviceSwitchData? {
        guard node.isPowerSwitch,
              let powerSwitchKind = node.powerSwitchKind else {
            return nil
        }
        if let existingSwitch = self.switchs.first(where: { $0.proxyNodeAddress == node.primaryUnicastAddress }) {
            return existingSwitch
        }
        guard self.switchs.count < 16 else {
            return nil
        }

        let baseSwitch = DeviceSwitchData.default()
        baseSwitch.proxyNodeAddress = node.primaryUnicastAddress
        baseSwitch.maxKeyCount = 8
        let panelType = node.batteryPowerSwitchPanelType ?? .scene8Key
        baseSwitch.panelType = panelType == .scene8Key ? .scenes_4key : .default_4key
        let metadata = PJEightKeySwitchRepository.Metadata(
            panelType: panelType,
            powerSwitchKind: powerSwitchKind,
            moreSettingsState: .default
        )
        let newSwitch = PJEightKeySwitchData(baseSwitchData: baseSwitch, metadata: metadata)
        ensureBatteryPowerSwitchLinkGroup(newSwitch)
        newSwitch.syncState = .pending
        newSwitch.desiredConfigVersion = 1
        newSwitch.desiredConfigHash = newSwitch.batteryPowerSwitchDesiredConfigHash(appKeyIndex: currentApplicationKey.index)
        newSwitch.appliedConfigHash = ""
        self.switchs.append(newSwitch)
        newSwitch.save()
        PJEightKeySwitchRepository.shared.save(newSwitch)
        return newSwitch
    }
    
    /// 删除动能开关
    func deleteSwitch(switchData: DeviceSwitchData) {
        guard let meshUUID = self.meshNetwork?.uuid.uuidString else { return }
        let realPowerSwitchNode = switchData.proxyNode?.isPowerSwitch == true
            ? switchData.proxyNode
            : nil
        silentlyResetPowerSwitchIfNeeded(realPowerSwitchNode)
        // 检查代理设备的数据有没有清空
        if let proxyNode = MeshNetworkManager.instance.realNodes.first(where: { $0.enOceanMacAddress == switchData.enOceanMacAddress }) {
            proxyNode.enOceanMacAddress = nil
            proxyNode.savePropertys()
        }
        PJEightKeySwitchRepository.shared.delete(for: switchData, meshUUID: meshUUID, networkId: self.currentNetworkKey.networkId.hex)
        switchData.delete(meshUUID: meshUUID, networkId: self.currentNetworkKey.networkId.hex)
        self.switchs.removeAll(where: { $0.id == switchData.id })
        removeRealPowerSwitchNodeIfNeeded(realPowerSwitchNode)
        
        var switchGroups: [Group] = []
        if let group = switchData.linkGroup {
            switchGroups.append(group)
        }
        if let group = switchData.subLinkGroup {
            switchGroups.append(group)
        }
        switchGroups.forEach { group in
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
        notifyRealPowerSwitchDeletedIfNeeded(realPowerSwitchNode)
        
    }

    private func silentlyResetPowerSwitchIfNeeded(_ node: Node?) {
        guard let node else {
            return
        }
        do {
            try MeshAPI.resetNodeWithoutWaitingForStatus(address: node.primaryUnicastAddress)
        } catch {
            print("Failed to send Power Switch reset node: \(error)")
        }
    }

    private func removeRealPowerSwitchNodeIfNeeded(_ node: Node?) {
        guard let node else {
            return
        }
        node.deleteExtension()
        self.meshNetwork?.forceRemove(node: node)
    }

    private func notifyRealPowerSwitchDeletedIfNeeded(_ node: Node?) {
        guard node != nil else {
            return
        }
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(
            name: .init(spaceDataChangedNotificaitonName),
            object: SpaceChangeDataType.network(type: .address)
        )
    }
    
    /// 删除dongle
    func deleteDongle(dongleData: DeviceDongleData) {
        guard let meshUUID = self.meshNetwork?.uuid.uuidString else { return }
        dongleData.delete(meshUUID: meshUUID, networkId: self.currentNetworkKey.networkId.hex)
        self.dongles.removeAll(where: { $0.id == dongleData.id })
    }
    
}

extension Group {
    
    private static var infoKey: UInt8 = 0
    private static var lightnessKey: UInt8 = 0
    private static var cctKey: UInt8 = 0
    private static var isOnKey: UInt8 = 0
    
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
                let ccts = self.nodes.filter({ $0.effectiveSupportCct && $0.state }).map({ $0.temperature })
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
        return effectiveSupportCct
    }

    /// 是否有效支持色温
    var effectiveSupportCct: Bool {
        return nodes.contains(where: { $0.effectiveSupportCct })
    }

    /// 有效色温范围，组内 CCT 设备取并集
    var effectiveCctRange: ClosedRange<UInt16> {
        let ranges = nodes.filter({ $0.effectiveSupportCct }).map({ $0.effectiveCctRange })
        guard let first = ranges.first else {
            return NodeAbsoluteCctRange.defaultRange
        }
        return ranges.reduce(first) { result, range in
            min(result.lowerBound, range.lowerBound)...max(result.upperBound, range.upperBound)
        }
    }

    func clampEffectiveCct(_ value: UInt16) -> UInt16 {
        min(effectiveCctRange.upperBound, max(effectiveCctRange.lowerBound, value))
    }
    
    /// 是否需要同步
    var needSync: Bool {
//        return nodes.contains(where: { $0.getNeedSyncGroup(group: self) })
        return nodes.contains(where: { $0.needSyncGroupData })
    }
    
    /// 删除本地化缓存数据（只处理业务扩展数据）
    func deleteExtension() {
        guard let uuid = (self.network ?? MeshNetworkManager.instance.meshNetwork)?.uuid.uuidString else {
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
            self.updateGroupSyncState()
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
            self.updateGroupSyncState()
        }
    }
    
    /// 更新组设备同步状态
    func updateGroupSyncState() {
//        DispatchQueue.global().async {
            self.nodes.forEach { node in
                node.clearSyncStateCache()
            }
//        }
    }
    
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
        
        updateGroupSyncState()
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
                    return !nodeSceneData.isSynced(with: sceneData, for: $0)
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
            needDeleteNodes = self.nodes.filter({ schedule.needsDelete(from: $0, contextGroup: self) })
        }else { // 待同步，获取组内待同步的设备
            needSyncNodes = self.nodes.filter({ schedule.needsSync(on: $0, contextGroup: self) })
            needDeleteNodes = self.nodes.filter({ schedule.needsDelete(from: $0, contextGroup: self) })
        }
        return (needSyncNodes, needDeleteNodes)
    }

}

extension Scene {
    
    private static var infoKey: UInt8 = 0
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
    
    /// 场景是否需要同步
    var needSync: Bool {
        info.groups.contains(where: { group in group.nodes.contains(where: { $0.getSyncData(type: .scenes(scene: self)).count > 0 })  })
    }
    
    /// 获取需要同步数据的组
    var needSyncGroups: [Group] {
        info.groups.filter({ group in
            group.nodes.contains(where: { $0.getSyncData(type: .scenes(scene: self)).count > 0 })
            
//            let sceneResult = group.getNeedSyncDataNodes(scene: self)
//            let isSyncScene = sceneResult.syncNodes.count > 0 || sceneResult.deleteNodes.count > 0
//            return isSyncScene
        })
        
    }
    
    
    /// 删除场景缓存数据
    func deleteExtension() {
        guard let uuid = self.network?.uuid.uuidString else {
            return
        }
        let subnetworkId = self.subNetworkId
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
//        || $0.nodes.contains(where: { $0.scenes.contains(where: { $0.number == self.sceneId }) })
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
        guard let address = ambientLightSensorNodeAddress else {
            return nil
        }
        return MeshNetworkManager.instance.realNodes.first(where: {  $0.contains(elementWithAddress: address) })
    }
    /// 设置的pwm周期
    var pwmPeriod: UInt16?
    
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
    
    /// 邻近照明路径数据
    var proximityLightingPath: GroupProximityLightingPathData?
    
    
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

    /// 当前场景数据应用到指定设备时的目标值。
    /// 支持 CCT 的设备按自身有效色温范围夹紧；不支持 CCT 的设备跳过色温项。
    func deviceTarget(for node: Node) -> SceneExecuteData {
        let data = SceneExecuteData(
            sceneNumber: sceneNumber,
            isOn: isOn,
            lightness: isOn ? lightness : 0,
            cct: node.effectiveSupportCct ? node.clampEffectiveCct(cct) : cct,
            lightControlData: lightControlData
        )
        data.hue = hue
        data.saturation = saturation
        data.state = state
        return data
    }

    /// 判断设备缓存的场景数据是否已达到组场景在该设备上的实际目标。
    /// OFF 场景只比较开关状态，不让未下发的亮度和色温字段影响同步结果。
    func isSynced(with groupSceneData: SceneExecuteData, for node: Node) -> Bool {
        let target = groupSceneData.deviceTarget(for: node)
        guard sceneNumber == target.sceneNumber,
              isOn == target.isOn,
              state == target.state else {
            return false
        }
        guard target.isOn else {
            return true
        }
        guard lightness == target.lightness else {
            return false
        }
        guard node.effectiveSupportCct else {
            return true
        }
        return cct == target.cct
    }
    
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

extension Schedule {
    
    /// 当前日程是否应该作用到指定节点。
    /// contextGroup 用于新增组成员时，节点刚进入组但 group.nodes 可能尚未稳定反映成员关系。
    func targets(node: Node, contextGroup: Group? = nil) -> Bool {
        if nodeAddresses.contains(node.primaryUnicastAddress) {
            return true
        }
        
        let canUseGroupContext = node.groupState != .exitFailure
        if canUseGroupContext {
            if groups.contains(where: { $0.nodes.contains(node) }) {
                return true
            }
            if let contextGroup = contextGroup, groups.contains(contextGroup) {
                return true
            }
            
            if let scene = scene {
                if scene.info.groups.contains(where: { $0.nodes.contains(node) }) {
                    return true
                }
                if let contextGroup = contextGroup, scene.info.groups.contains(contextGroup) {
                    return true
                }
            }
        }
        
        return false
    }
    
    func needsSync(on node: Node, contextGroup: Group? = nil) -> Bool {
        guard node.schedulerSetupModel != nil, targets(node: node, contextGroup: contextGroup) else {
            return false
        }
        guard let nodeEntry = node.schedulerActions[id] else {
            return true
        }
        return !(nodeEntry == schedulerEntry)
    }
    
    func needsDelete(from node: Node, contextGroup: Group? = nil) -> Bool {
        guard node.schedulerSetupModel != nil, node.schedulerActions[id] != nil else {
            return false
        }
        return !targets(node: node, contextGroup: contextGroup)
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
            syncNodes = nodes.filter({ needsSync(on: $0) })
            allSyncNodes.append(contentsOf: nodes)
        case .groups:
            groups.forEach({ group in
                let groupTargetNodes = group.nodes.filter({ node in targets(node: node, contextGroup: group) })
                let groupSyncNodes = groupTargetNodes.filter({ node in needsSync(on: node, contextGroup: group) })
                if groupSyncNodes.count > 0 {
                    syncGroupData.updateValue(groupSyncNodes, forKey: group)
                }
                allSyncNodes.append(contentsOf: groupTargetNodes)
            })
        case .scene:
            scene?.info.groups.forEach({ group in
                let groupTargetNodes = group.nodes.filter({ node in targets(node: node, contextGroup: group) })
                let groupSyncNodes = groupTargetNodes.filter({ node in needsSync(on: node, contextGroup: group) })
                if groupSyncNodes.count > 0 {
                    syncGroupData.updateValue(groupSyncNodes, forKey: group)
                }
                allSyncNodes.append(contentsOf: groupTargetNodes)
            })
        case .profile:
            break
        }
        
        var deleteNodes = needDeleteNodes.filter({ needsDelete(from: $0) && !allSyncNodes.contains($0) })
        
        var deleteGroupData: [Group: [Node]] = [:]
        needDeleteGroups.forEach({ group in
            let groupDeleteNodes = group.nodes.filter({ node in needsDelete(from: node, contextGroup: group) && !allSyncNodes.contains(node) && !deleteNodes.contains(node) })
            // ((!allSyncNodes.contains($0) && !allDeleteNodes.contains($0)) || !nodes.contains($0))
            if groupDeleteNodes.count > 0 {
                deleteGroupData.updateValue(groupDeleteNodes, forKey: group)
//                allDeleteNodes.append(contentsOf: groupDeleteNodes)
            }
        })

        needDeleteScenes.forEach({ scene in
            scene.info.groups.forEach { group in
                let groupDeleteNodes = group.nodes.filter({ node in needsDelete(from: node, contextGroup: group) && !allSyncNodes.contains(node) && !deleteNodes.contains(node) })
                // && !allSyncNodes.contains($0)) && !allDeleteNodes.contains($0)
                if groupDeleteNodes.count > 0 {
                    deleteGroupData.updateValue(groupDeleteNodes, forKey: group)
//                    allDeleteNodes.append(contentsOf: groupDeleteNodes)
                }
            }
        })
        
        let groupedDeleteNodes = deleteGroupData.values.flatMap({ $0 })
        let orphanDeleteNodes = MeshNetworkManager.instance.realNodes.filter({
            needsDelete(from: $0) &&
            !allSyncNodes.contains($0) &&
            !deleteNodes.contains($0) &&
            !groupedDeleteNodes.contains($0)
        })
        deleteNodes.append(contentsOf: orphanDeleteNodes)
        
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
        
        if self.linkGroup != nil {
            var allNodes: [Node] = []
            if deleteSwitch { // 删除动能开关
                
                bindGroups.forEach { group in
                    allNodes.append(contentsOf: group.nodes)
                    let nodes = group.nodes.filter({
                        if self.batteryPowerSwitchData != nil {
                            return $0.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: self, unsubscribe: true).count > 0
                        }
                        return $0.getEnOceanUnSubscriptionMessageHandles(switchKeys: self.switchKeys).count > 0
                    })
                    if nodes.count > 0 {
                        deleteGroupData.updateValue(nodes, forKey: group)
                    }
                }
                // 当前设置动能开关的代理设备
                let currentProxy = allNodes.first(where: { $0.enOceanMacAddress?.count ?? 0 > 0 && $0.enOceanMacAddress == self.enOceanMacAddress })
                deleteProxy = currentProxy
                
            }else {
                // 同步数据
                bindGroups.forEach { group in
                    allNodes.append(contentsOf: group.nodes)
                    if !unbindGroups.contains(group) {
                        let nodes = group.nodes.filter({
                            if self.batteryPowerSwitchData != nil {
                                return $0.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: self, unsubscribe: false).count > 0
                            }
                            return $0.getEnOceanSubscriptionMessageHandles(switchKeys: self.switchKeys).count > 0
                        })
                        if nodes.count > 0 {
                            syncGroupData.updateValue(nodes, forKey: group)
                        }
                    }
                }
                
                unbindGroups.forEach({ group in
                    let nodes = group.nodes.filter({
                        if self.batteryPowerSwitchData != nil {
                            return $0.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: self, unsubscribe: true).count > 0
                        }
                        return $0.getEnOceanUnSubscriptionMessageHandles(switchKeys: self.switchKeys).count > 0
                    })
                    if nodes.count > 0 {
                        deleteGroupData.updateValue(nodes, forKey: group)
                    }
                })
                
                // 判断是否需要同步动能开关代理
                if let mac = self.enOceanMacAddress, let key = self.enOceanSecurityKey, let proxyNode = self.proxyNode {
                    if proxyNode.getEnOceanSwitchBindMessageHandles(enOceanMacAddress: mac, securityKey: key, keyCount: self.maxKeyCount, enabled: self.enabled, switchKeys: self.switchKeys).count > 0 {
                        syncProxy = proxyNode
                    }
                }
                
                
                // 当前设置动能开关的代理设备
//                let currentProxy = allNodes.first(where: { $0.enOceanMacAddress != nil && $0.enOceanMacAddress == self.enOceanMacAddress })
                // 判断当前的代理设备和目标的代理设备是否不一样，不一样需要删除之前的代理
//                if currentProxy?.primaryUnicastAddress != self.proxyNodeAddress {
//                    deleteProxy = currentProxy
//                }
                if let node = self.deleteProxyNode, node.enOceanMacAddress?.count ?? 0 > 0 {
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

extension DeviceDongleData {
    
    /// 是否需要同步数据
    var needSyncData: Bool {
        guard let node = self.bindNode else {
            return false
        }
        return node.getSyncData(type: .dongle(dongleData: self)).count > 0
    }
    
}

extension Node {

    static private var localVersionSEQ: UInt8 = 0
    static private var deviceConfigInfo: UInt8 = 0
    static private var gateway: UInt8 = 0
    static private var cacheNeedSync: UInt8 = 0
    static private var cacheGroupNeedSync: UInt8 = 0
    static private var batteryPowerSwitchRestoreTargetSubscriptionSnapshotsKey: UInt8 = 0
//    static private var lastUpdateSyncTime = 206

    static let batteryPowerSwitchCompanyIdentifier: UInt16 = PJEightKeyPowerSwitchKind.companyIdentifier
    static let batteryPowerSwitchProductIdentifiers: Set<UInt16> = PJEightKeyPowerSwitchKind.batteryProductIdentifiers
    static let acPowerSwitchProductIdentifiers: Set<UInt16> = PJEightKeyPowerSwitchKind.acProductIdentifiers

    static func powerSwitchKind(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> PJEightKeyPowerSwitchKind? {
        PJEightKeyPowerSwitchKind.make(
            companyIdentifier: companyIdentifier,
            productIdentifier: productIdentifier
        )
    }

    static func isBatteryPowerSwitch(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
        powerSwitchKind(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier) == .battery
    }

    static func isACPowerSwitch(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
        powerSwitchKind(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier) == .ac
    }

    static func isPowerSwitch(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
        powerSwitchKind(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier) != nil
    }

    private static let emergencySignControllerCompanyIdentifier: UInt16 = 0x0A78
    private static let emergencySignControllerProductIdentifiers: Set<UInt16> = [0x24C1]
    private static let externalLightSensorCapableLuminaireCompanyIdentifier: UInt16 = 0x0A78
    private static let externalLightSensorCapableLuminaireProductIdentifiers: Set<UInt16> = [
        0x2121,
        0x2122,
        0x2132,
        0x2133,
        0x2491,
        0x2492,
        0x2493,
        0x2494
    ]

    static func isEmergencySignController(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
        guard companyIdentifier == emergencySignControllerCompanyIdentifier,
              let productIdentifier else {
            return false
        }
        return emergencySignControllerProductIdentifiers.contains(productIdentifier)
    }

    static func isExternalLightSensorCapableLuminaire(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
        guard companyIdentifier == externalLightSensorCapableLuminaireCompanyIdentifier,
              let productIdentifier else {
            return false
        }
        return externalLightSensorCapableLuminaireProductIdentifiers.contains(productIdentifier)
    }
    
    /// 设备类型
    enum DeviceType {
        /// 灯/灯+传感器
        case light
        /// 开关
        case switches
        /// 单独传感器
        case sensor
    //    case `switch`
        /// dongle能耗采集
        case dongle
        /// 网关
        case gateway
        /// 应急火警控制器
        case emergencyController
        /// 未知
        case unknown
        
        init(deviceCategory: String) {
            switch deviceCategory {
            case "Lighting":
                self = .light
            case "Sensor", "StandaloneSensor":
                self = .sensor
            case "Dongle":
                self = .dongle
            case "Switches", "BatteryPowerSwitch", "ACPowerSwitch":
                self = .switches
            case "Gateway":
                self = .gateway
            case "EmergencyController":
                self = .emergencyController
            default:
                self = .unknown
            }
        }
    }
    
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
    
    /// 设备配置信息
    var deviceConfigInfo: MeshDeviceConfigInfo? {
        get {
            guard let pid = self.productIdentifier, pid != 0 else {
                return nil
            }
            guard let info = objc_getAssociatedObject(self, &Node.deviceConfigInfo) as? MeshDeviceConfigInfo else {
                let deviceInfo = MeshLibManager.manager.supportDeviceInfos.first(where: { $0.productId == pid })
                self.deviceConfigInfo = deviceInfo
                return deviceInfo
            }
            return info
        }set {
            objc_setAssociatedObject(self, &Node.deviceConfigInfo, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
        
    }
    
    /// 设备类型
    var deviceType: DeviceType {
        guard let configInfo = deviceConfigInfo else {
            return .light
        }
        return DeviceType(deviceCategory: configInfo.deviceCategory)
    }

    var isBatteryPowerSwitch: Bool {
        return Node.isBatteryPowerSwitch(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier)
    }

    var powerSwitchKind: PJEightKeyPowerSwitchKind? {
        return Node.powerSwitchKind(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier)
    }

    var isACPowerSwitch: Bool {
        return Node.isACPowerSwitch(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier)
    }

    var isPowerSwitch: Bool {
        return Node.isPowerSwitch(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier)
    }

    var isEmergencySignController: Bool {
        return Node.isEmergencySignController(companyIdentifier: companyIdentifier, productIdentifier: productIdentifier)
    }

    var isExternalLightSensorCapableLuminaire: Bool {
        return Node.isExternalLightSensorCapableLuminaire(
            companyIdentifier: companyIdentifier,
            productIdentifier: productIdentifier
        )
    }

    var isSupportVendorIdentify: Bool {
        return !isEmergencySignController
    }

    var batteryPowerSwitchPanelType: PJEightKeySwitchPanelDefinition.PanelType? {
        guard isPowerSwitch else {
            return nil
        }
        return PJEightKeyPowerSwitchKind.panelType(productIdentifier: productIdentifier)
    }

    var batteryPowerSwitchRestoreTargetSubscriptionSnapshots: [Address: Set<BatteryPowerSwitchTargetSubscriptionSnapshot>]? {
        get {
            objc_getAssociatedObject(self, &Node.batteryPowerSwitchRestoreTargetSubscriptionSnapshotsKey) as? [Address: Set<BatteryPowerSwitchTargetSubscriptionSnapshot>]
        } set {
            objc_setAssociatedObject(self, &Node.batteryPowerSwitchRestoreTargetSubscriptionSnapshotsKey, newValue as Any?, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    func makeBatteryPowerSwitchRestoreTargetSubscriptionSnapshots(
        group: Group?
    ) -> [Address: Set<BatteryPowerSwitchTargetSubscriptionSnapshot>] {
        let switchDatas = (group?.info.switchs ?? []) + MeshNetworkManager.instance.switchs
        let linkGroups = uniqueBatteryPowerSwitchLinkGroups(from: switchDatas)
        guard !linkGroups.isEmpty else {
            return [:]
        }

        var snapshots: [Address: Set<BatteryPowerSwitchTargetSubscriptionSnapshot>] = [:]
        elements.forEach { element in
            guard element.unicastAddress >= primaryUnicastAddress else {
                return
            }
            let offset = element.unicastAddress - primaryUnicastAddress
            element.models.forEach { model in
                linkGroups.forEach { linkGroup in
                    if model.isSubscribed(to: linkGroup.group) {
                        snapshots[linkGroup.address, default: []].insert(
                            BatteryPowerSwitchTargetSubscriptionSnapshot(
                                linkGroupAddress: linkGroup.address,
                                elementOffset: offset,
                                modelIdentifier: model.modelIdentifier,
                                companyIdentifier: model.companyIdentifier
                            )
                        )
                    }
                }
            }
        }

        #if DEBUG
        if !snapshots.isEmpty {
            let description = snapshots.map { groupAddress, values in
                let models = values.map {
                    "\($0.elementOffset)/\($0.modelIdentifier.hex)"
                }.sorted().joined(separator: ",")
                return "\(groupAddress.hex):[\(models)]"
            }.sorted().joined(separator: " ")
            print("[BPS Target] restore snapshot node=\(primaryUnicastAddress.hex), \(description)")
        }
        #endif

        return snapshots
    }

    private func uniqueBatteryPowerSwitchLinkGroups(from switchDatas: [DeviceSwitchData]) -> [(address: Address, group: Group)] {
        var groups: [(Address, Group)] = []
        var addresses: Set<Address> = []
        switchDatas.forEach { switchData in
            guard switchData.batteryPowerSwitchData != nil,
                  let linkGroup = switchData.linkGroup else {
                return
            }
            let address = linkGroup.address.address
            if addresses.insert(address).inserted {
                groups.append((address, linkGroup))
            }
        }
        return groups
    }

    private var batteryPowerSwitchBrightnessLevelModel: Model? {
        guard let element = lightnessModel?.parentElement else {
            return nil
        }
        return element.model(withSigModelId: .genericLevelServerModelId)
    }

    private func batteryPowerSwitchTargetCapabilityModels(for switchData: PJEightKeySwitchData) -> [Model] {
        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        let actionTypes = switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: appKeyIndex).map { $0.type }
        var models: [Model?] = []

        if actionTypes.contains(.onOffToggle) || actionTypes.contains(.onOffSet) {
            models.append(onoffModel)
        }
        if actionTypes.contains(.levelDelta) || actionTypes.contains(.levelMove) {
            models.append(batteryPowerSwitchBrightnessLevelModel)
        }
        if actionTypes.contains(.sceneRecall) {
            models.append(sceneModel)
        }
        if actionTypes.contains(.lightnessSet) {
            models.append(lightnessModel)
        }
        if actionTypes.contains(.lightCtrlOnOff) {
            models.append(lightLCModel)
        }
        if actionTypes.contains(.ctlSet) {
            models.append(ctlModel)
        }
        if actionTypes.contains(.ctlTemperatureSet) {
            models.append(temperatureModel)
        }

        return uniqueBatteryPowerSwitchModels(models.compactMap { $0 })
    }

    private func batteryPowerSwitchTargetModelLogDescription(_ models: [Model]) -> String {
        models.map {
            let elementAddress = $0.parentElement?.unicastAddress.hex ?? "nil"
            return "\(elementAddress)/\($0.modelIdentifier.hex)"
        }.joined(separator: ",")
    }

    func getBatteryPowerSwitchSubscriptionMessageHandles(
        switchData: PJEightKeySwitchData,
        switchGroup: Group,
        includeExisting: Bool = false
    ) -> [MeshMessageHandle] {
        let desiredModels = batteryPowerSwitchTargetCapabilityModels(for: switchData)
        #if DEBUG
        let actionTypes = switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index).map { $0.type.rawValue.description }.joined(separator: ",")
        print("[BPS Target] subscribe node=\(primaryUnicastAddress.hex), group=\(switchGroup.address.address.hex), actions=\(actionTypes), desired=\(batteryPowerSwitchTargetModelLogDescription(desiredModels))")
        #endif

        return desiredModels
            .filter { includeExisting || !$0.isSubscribed(to: switchGroup) }
            .compactMap { batteryPowerSwitchSubscriptionMessageHandle(model: $0, switchGroup: switchGroup) }
    }

    func getBatteryPowerSwitchRestoreTargetSubscriptionMessageHandles(
        switchData: DeviceSwitchData,
        includeExisting: Bool = false
    ) -> [MeshMessageHandle] {
        guard let batteryPowerSwitchData = switchData.batteryPowerSwitchData,
              let switchGroup = switchData.linkGroup else {
            return []
        }
        let linkGroupAddress = switchGroup.address.address
        guard let snapshots = batteryPowerSwitchRestoreTargetSubscriptionSnapshots?[linkGroupAddress],
              !snapshots.isEmpty else {
            #if DEBUG
            print("[BPS Target] restore skip node=\(primaryUnicastAddress.hex), group=\(linkGroupAddress.hex), reason=no-old-snapshot")
            #endif
            return []
        }

        let desiredModels = batteryPowerSwitchTargetCapabilityModels(for: batteryPowerSwitchData)
        let restoredModels = desiredModels.filter { model in
            guard let elementAddress = model.parentElement?.unicastAddress,
                  elementAddress >= primaryUnicastAddress else {
                return false
            }
            let snapshot = BatteryPowerSwitchTargetSubscriptionSnapshot(
                linkGroupAddress: linkGroupAddress,
                elementOffset: elementAddress - primaryUnicastAddress,
                modelIdentifier: model.modelIdentifier,
                companyIdentifier: model.companyIdentifier
            )
            return snapshots.contains(snapshot)
        }

        #if DEBUG
        print("[BPS Target] restore subscribe node=\(primaryUnicastAddress.hex), group=\(linkGroupAddress.hex), old=\(snapshots.count), desired=\(batteryPowerSwitchTargetModelLogDescription(desiredModels)), matched=\(batteryPowerSwitchTargetModelLogDescription(restoredModels))")
        #endif

        return restoredModels
            .filter { includeExisting || !$0.isSubscribed(to: switchGroup) }
            .compactMap { batteryPowerSwitchSubscriptionMessageHandle(model: $0, switchGroup: switchGroup) }
    }

    func getBatteryPowerSwitchUnsubscriptionMessageHandles(
        switchData: PJEightKeySwitchData,
        switchGroup: Group,
        includeMissing: Bool = false
    ) -> [MeshMessageHandle] {
        batteryPowerSwitchTargetCapabilityModels(for: switchData)
            .filter { includeMissing || $0.isSubscribed(to: switchGroup) }
            .compactMap { batteryPowerSwitchUnsubscriptionMessageHandle(model: $0, switchGroup: switchGroup) }
    }

    func getBatteryPowerSwitchTargetSubscriptionMessageHandles(
        switchData: DeviceSwitchData,
        unsubscribe: Bool,
        includeExisting: Bool = false,
        includeMissing: Bool = false
    ) -> [MeshMessageHandle] {
        guard let batteryPowerSwitchData = switchData.batteryPowerSwitchData,
              let switchGroup = switchData.linkGroup else {
            return []
        }
        if unsubscribe {
            return getBatteryPowerSwitchUnsubscriptionMessageHandles(switchData: batteryPowerSwitchData, switchGroup: switchGroup, includeMissing: includeMissing)
        }
        return getBatteryPowerSwitchSubscriptionMessageHandles(switchData: batteryPowerSwitchData, switchGroup: switchGroup, includeExisting: includeExisting)
    }

    func getSunSmartSubscribeToGroupMessageHandles(
        _ group: Group,
        continuous: Bool? = nil
    ) -> [MeshMessageHandle] {
        if let switchData = MeshNetworkManager.instance.batteryPowerSwitchData(linkGroupAddress: group.address.address) {
            return getBatteryPowerSwitchSubscriptionMessageHandles(switchData: switchData, switchGroup: group)
        }

        return getSubscribeToGroupMessages(group).map { message in
            let handle = MeshMessageHandle(message: message, address: primaryUnicastAddress)
            if let continuous {
                handle.continuous = continuous
            }
            return handle
        }
    }

    func filterSunSmartBatteryPowerSwitchSubscriptionMessageHandles(
        _ handles: [MeshMessageHandle]
    ) -> [MeshMessageHandle] {
        handles.filter { shouldSendSunSmartBatteryPowerSwitchSubscriptionMessage($0.message) }
    }

    private func uniqueBatteryPowerSwitchModels(_ models: [Model]) -> [Model] {
        var identifiers = Set<ObjectIdentifier>()
        return models.filter { identifiers.insert(ObjectIdentifier($0)).inserted }
    }

    private func shouldSendSunSmartBatteryPowerSwitchSubscriptionMessage(_ message: MeshMessage) -> Bool {
        guard let target = batteryPowerSwitchTargetSubscription(from: message),
              let switchData = MeshNetworkManager.instance.batteryPowerSwitchData(linkGroupAddress: target.groupAddress) else {
            return true
        }

        let allowed = batteryPowerSwitchTargetCapabilityModels(for: switchData).contains { model in
            model.parentElement?.unicastAddress == target.elementAddress
                && model.modelIdentifier == target.modelIdentifier
                && model.companyIdentifier == target.companyIdentifier
        }

        #if DEBUG
        if !allowed {
            print("[BPS Target] skip stale restore subscription node=\(primaryUnicastAddress.hex), group=\(target.groupAddress.hex), model=\(target.elementAddress.hex)/\(target.modelIdentifier.hex)")
        }
        #endif

        return allowed
    }

    private func batteryPowerSwitchTargetSubscription(from message: MeshMessage) -> (groupAddress: Address, elementAddress: Address, modelIdentifier: UInt16, companyIdentifier: UInt16?)? {
        if let message = message as? ConfigModelSubscriptionAdd {
            return (message.address, message.elementAddress, message.modelIdentifier, message.companyIdentifier)
        }
        if let message = message as? ConfigModelSubscriptionVirtualAddressAdd {
            return (MeshAddress(message.virtualLabel).address, message.elementAddress, message.modelIdentifier, message.companyIdentifier)
        }
        return nil
    }

    private func batteryPowerSwitchSubscriptionMessageHandle(model: Model, switchGroup: Group) -> MeshMessageHandle? {
        guard let message: ConfigMessage = ConfigModelSubscriptionAdd(group: switchGroup, to: model) ?? ConfigModelSubscriptionVirtualAddressAdd(group: switchGroup, to: model) else {
            return nil
        }
        return MeshMessageHandle(message: message, address: primaryUnicastAddress)
    }

    private func batteryPowerSwitchUnsubscriptionMessageHandle(model: Model, switchGroup: Group) -> MeshMessageHandle? {
        guard let message: ConfigMessage = ConfigModelSubscriptionDelete(group: switchGroup, from: model) ?? ConfigModelSubscriptionVirtualAddressDelete(group: switchGroup, from: model) else {
            return nil
        }
        return MeshMessageHandle(message: message, address: primaryUnicastAddress)
    }
    
    /// 图标名称
    var iconName: String {
        guard let configInfo = deviceConfigInfo else {
            return "device_unknown"
        }
        return configInfo.iconName
    }
   
    /// 离线图标名称
    var offlineIconName: String {
        guard let configInfo = deviceConfigInfo else {
            return "device_offline_unknown"
        }
        return configInfo.offlineIconName
    }
    
    /// 待同步图标名称
    var unsyncIconName: String {
        
        guard let configInfo = deviceConfigInfo else {
            return "device_unknown"
        }
        return configInfo.unsyncIconName
    }
    
    /// 类别名称
    var categoryName: String? {
        return deviceConfigInfo?.categoryName
    }
    
    /// 设备型号
    var modelName: String? {
        return deviceConfigInfo?.modelName
    }
    
    /// 默认的设备名称类型
    var defaultNameCategory: String? {
        if isEmergencySignController {
            return "EM"
        }
        switch self.deviceType {
        case .light:
            return "L"
        case .sensor:
            return "S"
        case .switches:
            return "SW"
        case .gateway:
            return "gateway".localizedString
        case .dongle:
            return "dongle".localizedString
        case .emergencyController:
            return "EFC"
        case .unknown:
            return nil
        }
    }
    
    /// 是否需要同步数据
    var needSync: Bool {
        
        guard let needSync = cacheNeedSync else {
            let syncState = self.getNeedSync()
            self.cacheNeedSync = syncState
            return syncState
        }
        return needSync || needSyncGroupData
//        return self.getSyncData(type: .all).count > 0
    }
    
    /// 是否需要同步组数据
    var needSyncGroupData: Bool {
        
        guard let needSync = cacheGroupNeedSync else {
            let syncState = self.getNeedSyncGroup()
            self.cacheGroupNeedSync = syncState
            return syncState
        }
        return needSync
    }
    
    /// 缓存是否需要同步数据
    var cacheNeedSync: Bool? {
        get {
            objc_getAssociatedObject(self, &Node.cacheNeedSync) as? Bool
        } set {
            objc_setAssociatedObject(self, &Node.cacheNeedSync, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 缓存是否需要同步组数据
    var cacheGroupNeedSync: Bool? {
        get {
            objc_getAssociatedObject(self, &Node.cacheGroupNeedSync) as? Bool
        } set {
            objc_setAssociatedObject(self, &Node.cacheGroupNeedSync, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 缓存的最后更新同步数据时间戳
//    var cacheLastUpdateSyncTime: Int64? {
//        get {
//            objc_getAssociatedObject(self, &Node.lastUpdateSyncTime) as? Int64
//        } set {
//            objc_setAssociatedObject(self, &Node.lastUpdateSyncTime, newValue, .OBJC_ASSOCIATION_RETAIN)
//        }
//    }
    
    /// lightLC第一阶段 lightness
    var lightLCOnLightness: UInt16? {
        guard lightLCModel != nil, let lightnessOn = self.lightLCProperty.lightnessOn, lightnessOn > 0 else {
            return nil
        }
        return lightnessOn
    }
    
    /// 是否支持设置参数
    var supportSetParameter: Bool {
        guard self.sunricherVendorModel != nil, self.productIdentifier != nil else {
            return false
        }
        if isEmergencySignController {
            return false
        }
        if self.deviceType == .switches ||
            self.deviceType == .dongle ||
            self.deviceType == .gateway ||
            self.deviceType == .emergencyController {
            return false
        }
        return true
    }
    
    /// 是否支持pwm频率
    var supportPwmFrequency: Bool {
        guard self.sunricherVendorModel != nil, let pid = self.productIdentifier, self.lightnessModel != nil else {
            return false
        }
        if companyIdentifier == 0x0A78 && (pid == 0x2013 || pid == 0x24B1) {
            return false
        }
        switch pid {
        case 0x0031, 0x0041, 0x0302, 0x0303, 0x1031, 0x1041, 0x1302, 0x1303, 0x2302, 0x2303, 0x2304, 0x2305, 0x2801, 0x2802: // 单独传感器等设备不支持pwm调节
            return false
        default:
            return true
        }
    }
    
    /// 是否支持移动感应灵敏度
    var supportMotionSensitivity: Bool {
        guard self.sunricherVendorModel != nil else {
            return false
        }
        return self.presenceDetectedSensorModel != nil
    }
    
    /// 是否支持校准
    var supportSensorCalibration: Bool {
        guard self.productIdentifier != nil, let version = self.firmwareVersion, self.ambientLightSensorModel != nil, self.sunricherVendorModel != nil else {
            return false
        }
        return version.compare(sensorCalibrationMinimumVersion, options: .numeric) != .orderedAscending
    }
    
    /// 是否支持真实功率计量
    var supportRealPowerMetering: Bool {
        guard self.sunricherVendorModel != nil, let pid = self.productIdentifier else {
            return false
        }
        switch pid {
        case 0x2302, 0x2303, 0x2304, 0x2305, 0x2801, 0x2802:
            return true
        default:
            return false
        }
    }
    
    /// 是否支持真实功率校准
    var supportRealPowerCalibration: Bool {
        guard self.sunricherVendorModel != nil, let pid = self.productIdentifier else {
            return false
        }
        switch pid {
        case 0x2801, 0x2802:
            return true
        default:
            return false
        }
    }
    
    /// 是否支持调光
    var supportDimming: Bool {
        guard let pid = self.productIdentifier, lightnessModel != nil else {
            return false
        }
        if pid == 0x2802 { // 只支持ON/OFF为兼容自动化调光逻辑增加的lightness model
            return false
        }
        return true
    }
    
    /// 是否支持设置默认过渡时间
    var supportDefaultTransitionTime: Bool {
        guard let pid = self.productIdentifier, defaultTransitionTimeModel != nil else {
            return false
        }
        if pid == 0x2802 {
            return false
        }
        return true
    }
    
    /// 传感器校准最低支持版本
    var sensorCalibrationMinimumVersion: String {
        guard let pid = self.productIdentifier else {
            return "1.3.0"
        }
        switch pid {
        case 0x1013:
            return "1.2.33"
        case 0x1041:
            return "1.2.26"
        case 0x1051:
            return "1.2.16"
        default:
            return "1.3.0"
        }
    }
    
    /// 附加子网所需绑定appkey的model list（网关、跨子网数据传输）
    var subnetAppkeyBindModels: [Model] {
        var models: [Model] = []
        if deviceType == .gateway {
            if let vendorModel = sunricherVendorModel {
                models.append(vendorModel)
            }
            if let timeModel = timeModel {
                models.append(timeModel)
            }
            if let timeSetupModel = timeSetupModel {
                models.append(timeSetupModel)
            }
        }
        return models
    }
    /// 是否支持lightControl Scene功能（新版profile）
    var supportLightLCScene: Bool {
        return self.requiredFunctionTypes.contains(.lightLCScene) && self.lightLCSceneModel != nil
//        self.lightLCSceneSetupModel != nil && self.lightLCSceneSetupModel!.boundApplicationKeys.count > 0
    }
    
    /// 刷新同步状态缓存
    func reloadSyncStateCache() {
        self.cacheGroupNeedSync = self.getNeedSyncGroup()
        if self.cacheGroupNeedSync ?? false {
            self.cacheNeedSync = false
        }else {
            self.cacheNeedSync = self.getNeedSync()
        }
//        self.cacheLastUpdateSyncTime = Int64(Date().timeIntervalSince1970)
    }
    
    /// 清除同步状态缓存
    func clearSyncStateCache() {
        self.cacheGroupNeedSync = nil
        self.cacheNeedSync = nil
    }
    
    /// 更新新设备的恢复数据
    func updateResoreData(oldNode: Node, resoreGroup: Group? = nil) {
        
        var addToGroup: Group?
        if let group = resoreGroup ?? oldNode.group, oldNode.groupState != .exitFailure {
            addToGroup = group
        }
        
        // 需要恢复的数据
        let restoreData = NodeRestoreData(addGroupAddress: addToGroup?.address.address, pwmFrequency: oldNode.pwmFrequency)
        if oldNode.phaseEnergyConsumptions.count > 0 {
            restoreData.phaseEnergyConsumptions = oldNode.phaseEnergyConsumptions
        }
        if oldNode.motionSensitivityRange != nil {
            restoreData.motionSensitivityRange = oldNode.motionSensitivityRange
        }
        
        if let group = addToGroup {
            // 恢复的设备之前作为组光照传感器，恢复后更新设备地址缓存到组
            if oldNode.sensorCalibrated, group.info.ambientLightSensorNodeAddress == oldNode.primaryUnicastAddress {
                if let calibrationValue = oldNode.daylightCalibrationValue, calibrationValue > 0 && calibrationValue < 65535 {
                    restoreData.daylightCalibrationValue = calibrationValue
                }
                // 校准数据
                if let data = oldNode.sensorCalibrationData {
                    restoreData.daylightCalibrationData = data
                }
                group.info.ambientLightSensorNodeAddress = self.primaryUnicastAddress
                group.info.save()
                group.updateGroupSyncState()
            }
            
            // 动能开关
            // 如果恢复的设备之前作为动能开关代理
            if let enOceanMacAddress = oldNode.enOceanMacAddress, let switchData = group.info.switchs.first(where: { $0.enOceanMacAddress == enOceanMacAddress && $0.proxyNodeAddress == oldNode.primaryUnicastAddress }), switchData.linkGroup != nil {
                
                switchData.proxyNodeAddress = self.primaryUnicastAddress
                switchData.save()
            }
            
            // 邻近照明路径
            if let proximityLightingPath = group.info.proximityLightingPath {
                let oldAddress = oldNode.sunricherVendorModel?.parentElement?.unicastAddress ?? oldNode.primaryUnicastAddress
  
                let newAddress = self.sunricherVendorModel?.parentElement?.unicastAddress ?? self.primaryUnicastAddress
                /// 是否更新数据
                var update = false
                
                // 替换之前路径的设备地址
                let paths = proximityLightingPath.paths.filter({ $0.items.contains(where: { $0.address == oldAddress }) })
                paths.forEach({ path in
                    if let item = path.items.first(where: { $0.address == oldAddress }) {
                        item.address = newAddress
                        update = true
                    }
                })
                let zones = proximityLightingPath.zones.filter({ $0.addresses.contains(oldAddress) })
                zones.forEach { zone in
                    if let index = zone.addresses.firstIndex(of: oldAddress) {
                        zone.addresses.replaceSubrange(index...index, with: [newAddress])
                        update = true
                    }
                }
                if update {
                    group.info.save()
                    group.updateGroupSyncState()
                }
            }
        }
        
        // 日程
        if oldNode.schedulerActions.count > 0 {
            let schedulers: [Schedule] = oldNode.schedulerActions.compactMap({ action in MeshNetworkManager.instance.schedules.first(where: { $0.id == action.key && action.value.isValid && $0.selectTargetType == .devices }) })
            
            schedulers.forEach { schedule in
                if let index = schedule.nodeAddresses.firstIndex(of: oldNode.primaryUnicastAddress) {
                    schedule.nodeAddresses.replaceSubrange(index...index, with: [self.primaryUnicastAddress])
                    schedule.save()
                }
            }
        }
        // Dongle
        if self.deviceType == .dongle, let dongle = MeshNetworkManager.instance.dongles.first(where: { $0.bindNodeAddress == oldNode.primaryUnicastAddress }) {
            dongle.bindNodeAddress = self.primaryUnicastAddress
            dongle.save()
        }
        // Gateway
//        if self.deviceType == .gateway, let gatewayModel = oldNode.gatewayModel {
//            gatewayModel.address = self.primaryUnicastAddress
//            self.gatewayModel = gatewayModel
//            self.gatewayModel?.save()
//        }
        self.restoreData = restoreData
        self.save()
        
        self.clearSyncStateCache()
    }
    
    /// 获取恢复节点需要数据
    /// - Parameter oldNode: 之前的节点
    /// - Returns: 需要发送的消息数据
    func getResoreMessageHandles(oldNode: Node) -> [MeshMessageHandle] {
        // 设置的消息数据
        var messageHandles: [MeshMessageHandle] = []
        guard let restoreData = self.restoreData else {
            return []
        }
        if let group = restoreData.addGroup {
            
            messageHandles.append(contentsOf: group.getNodeAddMessageHandles(node: self))
            
            // 动能开关
            // 如果恢复的设备之前作为动能开关代理
            if let enOceanMacAddress = oldNode.enOceanMacAddress, let switchData = group.info.switchs.first(where: { $0.enOceanMacAddress == enOceanMacAddress && $0.proxyNodeAddress == oldNode.primaryUnicastAddress }), switchData.linkGroup != nil, let enOceanSecurityKey = switchData.enOceanSecurityKey {
                
                let handles = self.getEnOceanSwitchBindMessageHandles(enOceanMacAddress: enOceanMacAddress, securityKey: enOceanSecurityKey, keyCount: switchData.maxKeyCount, enabled: switchData.enabled, switchKeys: switchData.switchKeys)
                messageHandles.append(contentsOf: handles)
            }
            
        }
        
        // 日程
        if let schedulerSetupModel = self.schedulerSetupModel {
            let setSchedules = MeshNetworkManager.instance.schedules.filter({ $0.nodeAddresses.contains(self.primaryUnicastAddress) })
            setSchedules.forEach { schedule in
                // 设置时区
                if let timeModel = self.timeModel {
                    messageHandles.append(MeshMessageHandle(message: Node.setLocalTimeMessage(), model: timeModel))
                }
                // 设置日程
                messageHandles.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(schedule.id), entry: schedule.schedulerEntry), model: schedulerSetupModel))
            }
        }
        
        if let pwmFrequency = restoreData.pwmFrequency, let vendorModel = self.sunricherVendorModel {
            let messageHandle = MeshMessageHandle(message: SunricherVendorSet(function: .pwmFrequency(pwmFrequency)), model: vendorModel)
            messageHandles.append(messageHandle)
        }
        
        // 能耗设置
        if let phaseEnergyConsumptions = restoreData.phaseEnergyConsumptions, let vendorModel = self.sunricherVendorModel {
            let messageHandle = MeshMessageHandle(message: SunricherVendorSet(function: .phaseEnergyConsumption(list: phaseEnergyConsumptions)), model: vendorModel)
            messageHandles.append(messageHandle)
        }
        
        // 灵敏度范围
        if let motionSensitivityRange = self.restoreData?.motionSensitivityRange,
           self.motionSensitivityRange != motionSensitivityRange,
           self.supportMotionSensitivity,
           let vendorModel = self.sunricherVendorModel {
            
            let sensitivity = self.motionSensitivity ?? min(UInt8(group?.info.profile.sensitivity ?? 100).value16, 65535)
            let messageHandle = MeshMessageHandle(message: SunricherVendorSet(function: .motionSensitivity(sensitivity, maxValue: motionSensitivityRange.upperBound, minValue: motionSensitivityRange.lowerBound)), model: vendorModel)
            messageHandles.append(messageHandle)
        }
        
        // Dongle
        if let dongleData = MeshNetworkManager.instance.dongles.first(where: { $0.bindNodeAddress == self.primaryUnicastAddress }) {
            let dongleSyncDatas = self.getSyncData(type: .dongle(dongleData: dongleData))
            dongleSyncDatas.forEach { data in
                switch data {
                case .syncCollectionSchedules(let schedules):
                    if let model = self.collectionSchedulerSetupModel {
                        let collectionMessageHandles = schedules.map({
                            MeshMessageHandle(message: SchedulerActionSet(index: UInt8($0.0), entry: $0.1), model: model)
                        })
                        messageHandles.append(contentsOf: collectionMessageHandles)
                    }
                case .deleteCollectionSchedules(let scheduleIds):
                    if let model = self.collectionSchedulerSetupModel {
                        let collectionMessageHandles = scheduleIds.map({
                            MeshMessageHandle(message: SchedulerActionSet(index: UInt8($0), entry: .init()), model: model)
                        })
                        messageHandles.append(contentsOf: collectionMessageHandles)
                    }
                default:
                    break
                }
            }
        }
        
        
        return messageHandles
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
        guard let meshNetwork = self.network ?? MeshNetworkManager.instance.meshNetwork else {
            return
        }
        // 删除动能开关
        deleteEnOceanSwitch()
        // 判断删除的设备是不是组绑定的光照传感器
        if let group = meshNetwork.groups.first(where: { $0.info.ambientLightSensorNodeAddress == primaryUnicastAddress }) {
            group.info.ambientLightSensorNodeAddress = nil
            group.info.save(meshUUID: meshNetwork.uuid.uuidString, subnetworkId: group.subNetworkId)
            group.updateGroupSyncState()
        }
        // 检查是否有删除分发者设备，删除分发者需把OTA分发缓存清空
        if let productId = self.productIdentifier {
            if let distributionData = MeshDistributionData.load(productId: productId), distributionData.distributionAddress == self.primaryUnicastAddress {
                distributionData.delete(productId: productId)
            }
        }
        // 删除关联网关
        if let mac = macAddress {
            GatewayModel.delete(siteId: meshNetwork.uuid.uuidString, macAddress: mac)
        }
        changeControlPage = nil
        absoluteCctRange = nil
        savePropertys()
    }
    
    /// 删除组内的场景缓存
    /// - Parameter sceneId: 场景id
    func delete(sceneId: SceneNumber) {
        if let index = self.sceneExecuteDatas.firstIndex(where: { $0.sceneNumber == sceneId }) {
            self.sceneExecuteDatas.remove(at: index)
            self.savePropertys()
            self.clearSyncStateCache()
        }
    }
    
    /// 删除绑定的动能开关
    func deleteEnOceanSwitch(enOceanMacAddress: String? = nil) {

        guard let uuid = self.network?.uuid.uuidString ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
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
            
            clearSyncStateCache()
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
                var isSave = false
                if self.restoreData?.addGroupAddress != nil {
                    self.restoreData?.addGroupAddress = nil
                    isSave = true
                }
                if self.groupState != .inGroup {
                    self.groupState = .inGroup
                    isSave = true
                }
                if isSave {
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
                    if let switchData = MeshNetworkManager.instance.switchs.first(where: { $0.linkGroupAddress == group.address.address || $0.subLinkGroupAddress == group.address.address }), let nodeGroup = self.group {
                        if isSuccess { // 删除成功
                            // 判断是否之前动能开关删除组失败，再次删除后成功，接着判断组里面是否设备都清空动能开关数据
                            if switchData.unbindGroupAddresses.contains(nodeGroup.address.address), !nodeGroup.nodes.contains(where: { node in
                                if switchData.batteryPowerSwitchData != nil {
                                    return node.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: switchData, unsubscribe: true).count > 0
                                }
                                return node.getEnOceanUnSubscriptionMessageHandles(switchKeys: switchData.switchKeys).count > 0
                            }) {
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
                                group.updateGroupSyncState()
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
            if !sceneId.isSpecialScene {
                var cct = temperature
                var lightness = self.lightness
                // 不支持cct，使用group预配置的cct值
                let groupSceneData = self.group?.info.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneId })
                if !self.effectiveSupportCct, let groupCct = groupSceneData?.cct {
                    cct = groupCct
                }
                if let groupSceneExecuteData = groupSceneData {
                    // 判断是否设置了亮度范围，如已设置亮度范围导致达不到目标亮度则判定正确
                    if self.lightnessRange.lowerBound > groupSceneExecuteData.lightness || self.lightnessRange.upperBound < groupSceneExecuteData.lightness {
                        lightness = groupSceneExecuteData.lightness
                    }
                }
                
                let isOn = groupSceneData?.isOn ?? (lightness > 0)
                let sceneData = SceneExecuteData(sceneNumber: sceneId, isOn: isOn, lightness: isOn ? lightness : 0, cct: clampEffectiveCct(cct))
    //            let sceneData = self.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneId })
                if let sceneIndex = self.sceneExecuteDatas.firstIndex(where: { $0.sceneNumber == sceneId }) {
                    self.sceneExecuteDatas.replaceSubrange(sceneIndex...sceneIndex, with: [sceneData])
                }else {
                    self.sceneExecuteDatas.append(sceneData)
    //                self.sceneExecuteDatas.append(SceneExecuteData(sceneNumber: sceneId, isOn: lightness > 0, lightness: lightness, cct: cct))
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
            }
            break
        case is SceneDelete:
            let sceneId = (message as! SceneDelete).scene
            if !sceneId.isSpecialScene {
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
                        group.updateGroupSyncState()
                    }
                }
            }
//            }
           
        case is SchedulerActionSet:
            let actionMessage = (message as! SchedulerActionSet)
            if !actionMessage.entry.isValid {
                self.schedulerActions.removeValue(forKey: Int(actionMessage.index))
//                if let uuid = self.network?.uuid.uuidString {
                    self.savePropertys()
                    
                    // 对应日程删除设备/组
                    if let schedule = MeshNetworkManager.instance.schedules.first(where: {$0.id == actionMessage.index}) {

                        // 设备已加入组，并且组内没有设备缓存对应日程数据，则直接让日程删除该组缓存
                        var isSaveSchedule = false
                        // 判断组是否因为此设备而无法从日程中删除，设备删除后组也从日程中删除
                        if let group = schedule.needDeleteGroups.first(where: { $0.nodes.contains(self) }), !group.nodes.contains(where: { $0.schedulerActions[schedule.id] != nil }) {
                            schedule.needDeleteGroupAddresses.removeAll(where: { $0 == group.address.address })
                            group.info.bindSchedules.removeAll(where: { $0.id == schedule.id })
                            
                            isSaveSchedule = true
                        }
                        // 判断场景是否因为此设备无法从日程中删除，设备删除后场景也从日程中删除
                        if let scene = schedule.needDeleteScenes.first(where: { $0.info.groups.contains(where: { $0.nodes.contains(self) }) }), !scene.info.groups.contains(where: { $0.nodes.contains(where: { $0.schedulerActions[schedule.id] != nil }) }) {
                            schedule.needDeleteSceneNumbers.removeAll(where: { $0 == scene.number })
                            isSaveSchedule = true
                        }
                        
                        if schedule.needDeleteNodes.contains(self) {
                            schedule.needDeleteNodeAddresses.removeAll(where: { $0 == self.primaryUnicastAddress })
                            isSaveSchedule = true
                        }
                        if isSaveSchedule {
                            schedule.save()
                        }
//                    }
                    
                }
                
            }
        case is LightLCLightOnOffSet, is LightLCLightOnOffSetUnacknowledged, is GenericOnOffSetUnacknowledged: // 点击Auto / Off
            
            guard let switchData = MeshNetworkManager.instance.switchs.first(where: { $0.proxyNodeAddress == self.primaryUnicastAddress }), let linkGroup = switchData.linkGroup else { return }
            
            switch message {
            case is LightLCLightOnOffSet, is LightLCLightOnOffSetUnacknowledged: // 点击Auto
                if let isOn = (message as? LightLCLightOnOffSet)?.isOn ?? (message as? LightLCLightOnOffSetUnacknowledged)?.isOn, isOn {
                    switchData.bindGroups.forEach { group in
                        let profile = group.info.profile
                        let lightData = profile.lightControlData
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
                    }
                }
            case is GenericOnOffSetUnacknowledged: // OFF
                if let isOn = (message as? GenericOnOffSetUnacknowledged)?.isOn {
                    var nodes: [Node] = []
                    switchData.bindGroups.forEach({ group in
                        nodes.append(contentsOf: group.nodes.filter({ node in (node.onoffModel?.isSubscribed(to: linkGroup) ?? false) || (node.lightLCModel?.isSubscribed(to: linkGroup) ?? false) }))
                    })
                    nodes.forEach({
                        if isOn {
                            if let trunOffLightness = $0.trunOffLightness {
                                $0.lightness = trunOffLightness
                            }
                        }else {
                            $0.lightness = 0
                        }
                        $0.isOn = isOn
                    })
                }
            default:
                break
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
                            if node.effectiveSupportCct {
                                node.temperature = node.clampEffectiveCct(UInt16(sceneData.cct))
                            }
                        })
                    }
                })
            }
        case is LightCTLTemperatureRangeSet:
            guard isSuccess else {
                return
            }
            let message = message as! LightCTLTemperatureRangeSet
            absoluteCctRange = message.range
            lightCTLTemperatureRange = message.range
            temperature = clampEffectiveCct(temperature)
            savePropertys()
        case is SunricherVendorSet: // 设置自定义消息
            if let vendorMessage = message as? SunricherVendorSet {
                switch vendorMessage.function {
                case .enOceanDelete(let macAddress): // 删除EnOcean按键绑定
                    deleteEnOceanSwitch(enOceanMacAddress: macAddress)
                case .daylightCalibrate:
                    if self.restoreData?.daylightCalibrationValue != nil {
                        self.restoreData?.daylightCalibrationValue = nil
                        save()
                    }
                case .daylightCalibrateRate(let sensorRate, let ambientLightRate):
                    self.restoreData?.daylightCalibrationData?.sensorRatio = nil
                    self.restoreData?.daylightCalibrationData?.ambientlightRatio = nil
                    if self.preConfiguration.resetDaylightCalibration ?? false {
                        self.preConfiguration.resetDaylightCalibration = nil
                        if sensorRate == 100 && ambientLightRate == 100 { // 重置
                            self.sensorCalibrationData = nil
                            self.savePropertys()
                        }
                        if let meshUUID = self.network?.uuid.uuidString {
                            self.preConfiguration.save(meshUUID: meshUUID, nodeAddress: self.primaryUnicastAddress)
                        }
                    }
                case .daylightCalibrateIlluminanceInflectionPoint:
                    if self.restoreData?.daylightCalibrationData != nil {
                        self.restoreData?.daylightCalibrationData?.minLightInflectionPointData = nil
                        self.restoreData?.daylightCalibrationData?.maxLightInflectionPointData = nil
                        self.save()
                    }
                case .pwmFrequency:
                    if self.restoreData?.pwmFrequency != nil {
                        self.restoreData?.pwmFrequency = nil
                        save()
                    }
                default:
                    break
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
    /// pwm阶段
    var pwmPeriod: UInt16?
    /// 是否不需要同步
    func isEmpty() -> Bool {
        return !(subscribeGroup || unsubscribeGroup || syncScenes.count > 0 || syncSchedules.count > 0 || deleteScenes.count > 0 || deleteSchedules.count > 0 || syncProfile.count > 0 || syncSwitchs.count > 0 || deleteSwitchs.count > 0 || syncSwitchProxy != nil || deleteSwitchProxy != nil || pwmPeriod != nil)
    }
}
