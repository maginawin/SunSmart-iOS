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
    ///   - changeAddress: 当第一次导入site时是否需要修改手机地址，分以下两种情况：
    ///      1：第一次加入space，服务器生成site数据并分配新的手机地址，则不需要再修改地址；
    ///      2：卸载app后由于没有缓存数据，之前使用的手机地址对应SEQ序列号未知，所以把旧的地址放到地址回收池内回收，并分配新的手机地址
    /// - Returns: site
    static func `import`(siteJsonData: [String: Any], changeAddress: Bool = false) async -> SiteData? {
        
        let json = JSON(siteJsonData)
        guard let uuid = json["uuid"].string,
              let name = json["siteName"].string else {
            return nil
        }
        var isChangeAddress = changeAddress
        var site = SiteData.load(siteId: uuid)
        var initialize = false
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
            initialize = true
        }else if site?.state == .waitDeleted { // 已转让site再次加入算重新
            initialize = true
            isChangeAddress = true
            site?.state = .normal
        }
        await site?.update(siteJsonData: siteJsonData, changeAddress: isChangeAddress, initialize: initialize)
        
        return site
    }
    
    
    /// 更新数据
    /// - Parameter siteJsonData: site数据
    /// - Parameter changeAddress: 是否切换地址
    /// - Parameter initialize 首次更新数据（本地无记录）
    func update(siteJsonData: [String: Any], changeAddress: Bool = false, initialize: Bool = false) async {
        
        let json = JSON(siteJsonData)
        guard let uuid = json["uuid"].string,
              let name = json["siteName"].string else {
            return
        }
        let lastUpdate = json["updateTimestamp"].int64Value
        
        var permission: Permission = .visitor
        switch json["role"].string {
        case "owner":
            permission = .owner
        case "editor":
            permission = .editor
        default:
            break
        }
        self.permission = permission
        
        let currentNetwork = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == self.meshUUID ? MeshNetworkManager.instance.meshNetwork : nil
        var meshNetwork = currentNetwork ?? MeshNetwork.load(meshUUID: self.meshUUID, allData: false)
        var updateNetwork = false
        // 服务器最后更新时间比本地时间新才覆盖本地数据
        if lastUpdate > self.lastUpdate || initialize {
            
            self.name = name
            self.imageId = json["imageId"].intValue
            //        self.isFavourite = json["favourite"].boolValue
            self.sourceType = DataSourceType(rawValue: json["type"].intValue) ?? DataSourceType.create
            self.create = json["createTimestamp"].int64Value
            self.lastUpdate = lastUpdate
            //        if self.lastUploadCloudTimestamp == nil {
            self.lastUploadCloudTimestamp = self.lastUpdate
            //        }
            // 转让site id
            if let shareId = json["shareId"].string {
                self.transferCode = shareId
            }
            
            // 本地手机节点地址
            if self.localAddress == nil, let addressHex = json["provisioner"]["address"].string, let address = Address(hex: addressHex) {
                self.localAddress = address
            }
            
            /// 是否保存mesh数据
//            var meshNetworkSave = false
            if meshNetwork == nil || initialize {
                guard let netKeyDict = siteJsonData["netKey"] as? [String: Any],
                      let netKeyData = try? JSONSerialization.data(withJSONObject: netKeyDict),
                      let netKey = try? jsonDecoder.decode(NetworkKey.self, from: netKeyData),
                      let appKeyDict = siteJsonData["appKey"] as? [String: Any],
                      let appKeyData = try? JSONSerialization.data(withJSONObject: appKeyDict),
                      let appKey = try? jsonDecoder.decode(ApplicationKey.self, from: appKeyData) else {
                    return
                }
                
                // Local Provisioner
                // 本地手机供应者
                let provisionerUuid = UUID()
                var localProvisioner: Provisioner = Provisioner(name: UserData.currentUserName, uuid: provisionerUuid, allocatedUnicastRange: [], allocatedGroupRange: [], allocatedSceneRange: [])
                // 用户地址数据
                if let provisionerJson = json["provisioner"].dictionary {
                    let uuid = provisionerJson["UUID"]?.string ?? provisionerUuid.uuidString
                    let name = provisionerJson["provisionerName"]?.string
                    
                    // 设备地址
                    var allocatedUnicastRange: [AddressRange] = []
                    if let allocatedUnicastRangeJson = provisionerJson["allocatedUnicastRange"]?.array {
                        allocatedUnicastRange = allocatedUnicastRangeJson.compactMap({
                            if let lowAddressString = $0["lowAddress"].string, let lowAddress = Address(hex: lowAddressString),
                               let highAddressString = $0["highAddress"].string, let highAddress = Address(hex: highAddressString) {
                                return AddressRange(from: lowAddress, to: highAddress)
                            }
                            return nil
                        })
                    }
                    
                    // 后续申请的设备地址
                    if let applyUnicastAddresses = provisionerJson["addrLists"]?.arrayObject as? [Int] {
                        // 设备地址
                        let applyUnicastRanges = applyUnicastAddresses.splitArray().compactMap { array in
                            if let lowAddress = array.first, let highAddress = array.last {
                                return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
                            }
                            return nil
                        }
                        allocatedUnicastRange.append(contentsOf: applyUnicastRanges)
                    }
                    
                    // 组地址
                    var allocatedGroupRange: [AddressRange] = []
                    if let allocatedGroupRangeJson = provisionerJson["allocatedGroupRange"]?.array {
                        allocatedGroupRange = allocatedGroupRangeJson.compactMap({
                            if let lowAddressString = $0["lowAddress"].string, let lowAddress = Address(hex: lowAddressString),
                               let highAddressString = $0["highAddress"].string, let highAddress = Address(hex: highAddressString) {
                                return AddressRange(from: lowAddress, to: highAddress)
                            }
                            return nil
                        })
                    }
                    // 后续申请的组地址
                    if let applyGroupAddresses = provisionerJson["group"]?.arrayObject as? [Int] {
                        // 组地址
                        let applyGroupRanges = applyGroupAddresses.splitArray().compactMap { array in
                            if let lowAddress = array.first, let highAddress = array.last {
                                return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
                            }
                            return nil
                        }
                        allocatedGroupRange.append(contentsOf: applyGroupRanges)
                    }
                    
                    
                    // 场景地址
                    var allocatedSceneRange: [SceneRange] = []
                    if let allocatedSceneRangeJson = provisionerJson["allocatedSceneRange"]?.array {
                        allocatedSceneRange = allocatedSceneRangeJson.compactMap({
                            if let firstSceneString = $0["lowAddress"].string ?? $0["firstScene"].string, let firstScene = Address(hex: firstSceneString),
                               let lastSceneString = $0["highAddress"].string ?? $0["lastScene"].string, let lastScene = Address(hex: lastSceneString) {
                                return SceneRange(from: firstScene, to: lastScene)
                            }
                            return nil
                        })
                    }
                    // 后续申请的场景地址
                    if let applySceneAddresses = provisionerJson["scene"]?.arrayObject as? [Int] {
                        // 场景地址
                        let applySceneRanges = applySceneAddresses.splitArray().compactMap { array in
                            if let firstScene = array.first, let lastScene = array.last {
                                return SceneRange(from: UInt16(firstScene), to: UInt16(lastScene))
                            }
                            return nil
                        }
                        allocatedSceneRange.append(contentsOf: applySceneRanges)
                    }
                    
                    let provisioner = Provisioner(name: name ?? UserData.currentUserName, uuid: UUID(uuidString: uuid)!, allocatedUnicastRange: allocatedUnicastRange, allocatedGroupRange: allocatedGroupRange, allocatedSceneRange: allocatedSceneRange)
                    localProvisioner = provisioner
                }
                
                meshNetwork = MeshNetworkManager.createMeshNetwork(meshUUID: self.meshUUID, meshNetworkName: name, localAddress: self.localAddress, provisionerUUID: provisionerUuid.uuidString, provisioner: localProvisioner, networkKey: netKey, applicationKey: appKey).meshNetwork
                if let deviceUsedAddresses = json["provisioner"]["usedAddresses"].arrayObject as? [String] {
                    meshNetwork?.deviceUsedAddresses = deviceUsedAddresses.compactMap({ Address(hex: $0) })
                }
                
                if let ivIndex = json["ivIndex"].uInt32 {
                    meshNetwork?.currentIVIndex = ivIndex
                }
                
                if !(meshNetwork?.networkKeys.contains(where: { $0.index == netKey.index }) ?? false) {
                    meshNetwork?.add(networkKey: netKey)
                    try? appKey.bind(to: netKey)
                    meshNetwork?.add(applicationKey: appKey)
                }
               
                // 废弃的设备地址
                if let exclusions = json["exclusions"].array {
                    let exclusionDataList = exclusions.compactMap({
                        if let ivIndex = $0["ivIndex"].uInt32, let addresses = $0["addresses"].arrayObject as? [String] {
                            return (ivIndex, addresses.compactMap({ Address(hex: $0) }))
                        }
                        return nil
                    })
                    meshNetwork?.setNetworkExclusionAddresses(list: exclusionDataList)
                    // 判断是否使用了废弃地址
                    //                if let localAddress = meshNetwork?.localProvisioner?.primaryUnicastAddress, exclusionDataList.contains(where: { $0.1.contains(localAddress) }) {
                    //                    resetLocalAddress = true
                    //                }
                }
//                meshNetworkSave = true
            }
            
            // 是否卸载后重装APP，需要更新site手机地址
            if UserData.isReinstallation || changeAddress {
                // 重新分配设备地址
                if let provisioner = meshNetwork?.localProvisioner {
                    if let newAddress = meshNetwork?.nextAvailableUnicastAddress(elementsCount: 1, elementsUsing: provisioner, lockInAddress: false) {
                        do {
                            if let lastAddress = provisioner.primaryUnicastAddress {
                                meshNetwork?.insetExclusionAddress(ivIndex: meshNetwork!.currentIVIndex, address: lastAddress)
                            }
                            try meshNetwork?.changeLocalNodeAddress(newAddress)
//                            meshNetworkSave = true
                            self.localAddress = meshNetwork?.localProvisioner?.primaryUnicastAddress
                            self.lastUpdate = Int64(Date().timeIntervalSince1970)
                        } catch {
                            self.localAddress = nil
                        }
                    }else {
                        // 没有地址时将之前的本地节点禁用删除，待后续申请到地址后再分配本地节点，否则会导致发送消息SEQ校验被拦截
                        meshNetwork?.disableConfigurationCapabilities(for: provisioner)
                        self.localAddress = nil
                    }
                }else {
                    self.localAddress = nil
                }
            }
            updateNetwork = true
            // 是否需要保存mesh数据
//            if meshNetworkSave {
//                meshNetwork?.save()
//            }
        }else {
            
            if let ivIndex = json["ivIndex"].uInt32, meshNetwork?.currentIVIndex != ivIndex {
                meshNetwork?.currentIVIndex = ivIndex
                updateNetwork = true
            }
            
            // 更新废弃的设备地址
            if let exclusions = json["exclusions"].array {
                let exclusionDataList: [(ivIndex: UInt32, addresses: [Address])] = exclusions.compactMap({
                    if let ivIndex = $0["ivIndex"].uInt32, let addresses = $0["addresses"].arrayObject as? [String] {
                        return (ivIndex, addresses.compactMap({ Address(hex: $0) }))
                    }
                    return nil
                })
                
                // 之前有服务器不存在的废弃地址，更新数据时追加保存到本地
                var appendExclusionDatas: [(ivIndex: UInt32, addresses: [Address])] = []
                // 检查不符合回收条件并且未记录的废弃地址
                if let currentExclusionAddresses = meshNetwork?.getNetworkExclusionAddresses() {
                    currentExclusionAddresses.forEach { (ivIndex: UInt32, addresses: [Address]) in
                        if (meshNetwork?.currentIVIndex ?? 0) - ivIndex <= 1 {
                            var appendAddresses = addresses
                            if let exclusionData = exclusionDataList.first(where: { $0.ivIndex == ivIndex }) {
                                appendAddresses = addresses.filter({ !exclusionData.addresses.contains($0) })
                            }
                            appendExclusionDatas.append((ivIndex: ivIndex, addresses: appendAddresses))
                        }
                    }
                }
                meshNetwork?.setNetworkExclusionAddresses(list: exclusionDataList)
                appendExclusionDatas.forEach { (ivIndex: UInt32, addresses: [Address]) in
                    addresses.forEach({
                        meshNetwork?.insetExclusionAddress(ivIndex: ivIndex, address: $0)
                    })
                }
            }
        }
      
        if updateNetwork {
            meshNetwork?.save()
        }
        
        // 修改供应者地址资源
        if let provisionerData = json["provisioner"].dictionaryObject {
            self.setProvisioner(provisionerData: provisionerData)
        }
        
        if let spaceDicts = json["spaces"].arrayObject as? [[String: Any]] {
            var spaces: [SpaceData] = []
            await withTaskGroup(of: SpaceData?.self) { group in
                for data in spaceDicts {
                    group.addTask {
                        // 异步处理每个数据
                        return await SpaceData.import(siteId: uuid, meshUUID: self.meshUUID, spaceJsonData: data)
                    }
                }
                // 收集结果
                for await space in group {
                    if let space = space {
                        spaces.append(space)
                    }
                }
            }
            
            // space已提交到服务器，但是本地有但是服务器没有
            let deleteSpaces = self.spaces.filter({ localSpace in !spaces.contains(where: { $0.id == localSpace.id }) && localSpace.uploadCloud })
            deleteSpaces.forEach({ space in
                if space.permission == .editor || space.permission == .visitor {
                    // 设置space为待删除状态
                    space.state = .waitDeleted
                    space.save()
                }
            })
            // 更新site下space数据
            spaces.forEach { space in
                if let index = self.spaces.firstIndex(where: { $0.id == space.id }) {
                    // 如果space已存在则更新数据
                    self.spaces.replaceSubrange(index...index, with: [space])
                }else {
                    // 如果space不存在则新增
                    self.spaces.append(space)
                }
            }
            self.spaces.sort(by: { $0.create < $1.create })
            
//            self.spaces = spaces
            self.spaceCount = nil
        }else {
            self.spaceCount = json["spaceCount"].int
        }
        self.save()
    }
    
    /// 添加site内用户资源
    func insetProvisioner(provisionerData: [String: Any]) {
        
        let provisionerJson = JSON(provisionerData)
        
        let currentNetwork = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == self.meshUUID ? MeshNetworkManager.instance.meshNetwork : nil
        guard let meshNetwork = currentNetwork ?? MeshNetwork.load(meshUUID: self.meshUUID, allData: false) else { return }
        // 如没有供应者，则新建一个
        guard let localProvisioner = meshNetwork.localProvisioner else {
            setProvisioner(provisionerData: provisionerData)
            return
        }
        
        if let deviceAddresses = provisionerJson["device"].arrayObject as? [Int] {
            // 设备地址
            let allocatedUnicastRange = deviceAddresses.splitArray().compactMap { array in
                if let lowAddress = array.first, let highAddress = array.last {
                    return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
                }
                return nil
            }
            try? localProvisioner.allocate(unicastAddressRanges: allocatedUnicastRange)
            // 查看是否缺少手机地址
            if let localAddress = localProvisioner.primaryUnicastAddress {
                if self.localAddress != localAddress {
                    self.localAddress = localAddress
                    self.save()
                }
            }else if let localAddress = meshNetwork.nextAvailableUnicastAddress(elementsCount: 1, elementsUsing: localProvisioner, lockInAddress: false) { // 缺少手机地址自动分配一个
                do {
                    try meshNetwork.changeLocalNodeAddress(localAddress)
                    self.localAddress = localAddress
                    self.save()
                } catch {
                    print("set local address error: \(error)")
                }
            }
        }
        
        if let groupAddresses = provisionerJson["group"].arrayObject as? [Int] {
            // 组地址
            let allocatedGroupRange = groupAddresses.splitArray().compactMap { array in
                if let lowAddress = array.first, let highAddress = array.last {
                    return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
                }
                return nil
            }
            try? localProvisioner.allocate(groupAddressRanges: allocatedGroupRange)
        }
        
        if let sceneAddresses = provisionerJson["scene"].arrayObject as? [Int] {
            // 场景地址
            let allocatedSceneRange = sceneAddresses.splitArray().compactMap { array in
                if let firstScene = array.first, let lastScene = array.last {
                    return SceneRange(from: UInt16(firstScene), to: UInt16(lastScene))
                }
                return nil
            }
            try? localProvisioner.allocate(sceneRanges: allocatedSceneRange)
        }
        meshNetwork.save()
    }
    
    /// 删除手机供应者地址
    /// - Parameters:
    ///   - deviceAddresses: 删除的设备地址
    ///   - groupAddresses: 删除的组地址
    ///   - sceneAddresses: 删除的场景地址
    func deleteProvisionerAddress(deviceAddresses: [Int], groupAddresses: [Int], sceneAddresses: [Int]) {
        let currentNetwork = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == self.meshUUID ? MeshNetworkManager.instance.meshNetwork : nil
        guard let meshNetwork = currentNetwork ?? MeshNetwork.load(meshUUID: self.meshUUID, allData: false) else { return }
        
        let deallocatedUnicastRange = deviceAddresses.splitArray().compactMap { array in
            if let lowAddress = array.first, let highAddress = array.last {
                return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
            }
            return nil
        }
        deallocatedUnicastRange.forEach({
            meshNetwork.localProvisioner?.deallocate(unicastAddressRange: $0)
        })
        
        // 组地址
        let deallocatedGroupRange = groupAddresses.splitArray().compactMap { array in
            if let lowAddress = array.first, let highAddress = array.last {
                return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
            }
            return nil
        }
        deallocatedGroupRange.forEach({
            meshNetwork.localProvisioner?.deallocate(groupAddressRange: $0)
        })
        
        // 场景地址
        let deallocatedSceneRange = sceneAddresses.splitArray().compactMap { array in
            if let firstScene = array.first, let lastScene = array.last {
                return SceneRange(from: UInt16(firstScene), to: UInt16(lastScene))
            }
            return nil
        }
        deallocatedSceneRange.forEach({
            meshNetwork.localProvisioner?.deallocate(sceneRange: $0)
        })
        meshNetwork.save()
    }
    
    
    /// 设置site所有者用户地址数据（覆盖）
    func setOwnerProvisioner(addressData: [String: Any]) {
        
        let addressJson = JSON(addressData)
        let currentNetwork = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == self.meshUUID ? MeshNetworkManager.instance.meshNetwork : nil
        guard let meshNetwork = currentNetwork ?? MeshNetwork.load(meshUUID: self.meshUUID, allData: false),
              let deviceAddressCount = addressJson["ownerDevicesAddress"].int,
              let groupAddressCount = addressJson["ownerGroupsAddress"].int,
              let sceneAddressCount = addressJson["ownerScenesAddress"].int else {
            return
        }
        
        let deviceAddressRange = AddressRange(from: Address.minUnicastAddress, to: Address.minUnicastAddress + UInt16(deviceAddressCount - 1))
        let groupAddressRange = AddressRange(from: Address.minGroupAddress, to: Address.minGroupAddress + UInt16(groupAddressCount - 1))
        let sceneAddressRange = SceneRange(from: Address.minScene, to: Address.minUnicastAddress + UInt16(sceneAddressCount - 1))
        
        let localProvisioner = meshNetwork.localProvisioner
        
        let provisioner = Provisioner(name: localProvisioner?.name ?? UserData.currentUserName, uuid: localProvisioner?.uuid ?? UUID(), allocatedUnicastRange: [deviceAddressRange], allocatedGroupRange: [groupAddressRange], allocatedSceneRange: [sceneAddressRange])
        // 修改供应者地址
        if localProvisioner?.uuid.uuidString == provisioner.uuid.uuidString && localProvisioner?.primaryUnicastAddress != nil {
            try? meshNetwork.changeProvisioner(provisioner)
        }else {
            let address = localProvisioner?.primaryUnicastAddress ?? meshNetwork.nextAvailableUnicastAddress(elementsCount: 1, elementsUsing: provisioner, lockInAddress: false)
            try? meshNetwork.changeProvisioner(provisioner, localAddress: address)
            self.localAddress = address
            self.save()
        }
        meshNetwork.save()
    }
    
    /// 设置site内用户资源（覆盖）
    func setProvisioner(provisionerData: [String: Any]) {
        
        let provisionerJson = JSON(provisionerData)
        let currentNetwork = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == self.meshUUID ? MeshNetworkManager.instance.meshNetwork : nil
        guard let meshNetwork = currentNetwork ?? MeshNetwork.load(meshUUID: self.meshUUID, allData: false) else {
            return
        }
        
        // 设备地址
        var allocatedUnicastRange: [AddressRange] = []
        if let allocatedUnicastRangeJson = provisionerJson["allocatedUnicastRange"].array {
            allocatedUnicastRange = allocatedUnicastRangeJson.compactMap({
                if let lowAddressString = $0["lowAddress"].string, let lowAddress = Address(hex: lowAddressString),
                   let highAddressString = $0["highAddress"].string, let highAddress = Address(hex: highAddressString) {
                    return AddressRange(from: lowAddress, to: highAddress)
                }
                return nil
            })
        }
        // 后续申请的设备地址
        if let applyUnicastAddresses = provisionerJson["allocatedUnicastAddress"].arrayObject as? [Int] {
            // 设备地址
            let applyUnicastRanges = applyUnicastAddresses.splitArray().compactMap { array in
                if let lowAddress = array.first, let highAddress = array.last {
                    return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
                }
                return nil
            }
            allocatedUnicastRange.append(contentsOf: applyUnicastRanges)
        }
        
        // 组地址
        var allocatedGroupRange: [AddressRange] = []
        if let allocatedGroupRangeJson = provisionerJson["allocatedGroupRange"].array {
            allocatedGroupRange = allocatedGroupRangeJson.compactMap({
                if let lowAddressString = $0["lowAddress"].string, let lowAddress = Address(hex: lowAddressString),
                   let highAddressString = $0["highAddress"].string, let highAddress = Address(hex: highAddressString) {
                    return AddressRange(from: lowAddress, to: highAddress)
                }
                return nil
            })
        }
        // 后续申请的组地址
        if let applyGroupAddresses = provisionerJson["allocatedGroupRange"].arrayObject as? [Int] {
            // 组地址
            let applyGroupRanges = applyGroupAddresses.splitArray().compactMap { array in
                if let lowAddress = array.first, let highAddress = array.last {
                    return AddressRange(from: UInt16(lowAddress), to: UInt16(highAddress))
                }
                return nil
            }
            allocatedGroupRange.append(contentsOf: applyGroupRanges)
        }
        
        
        // 场景地址
        var allocatedSceneRange: [SceneRange] = []
        if let allocatedSceneRangeJson = provisionerJson["allocatedSceneRange"].array {
            allocatedSceneRange = allocatedSceneRangeJson.compactMap({
                if let firstSceneString = $0["lowAddress"].string ?? $0["firstScene"].string, let firstScene = Address(hex: firstSceneString),
                   let lastSceneString = $0["highAddress"].string ?? $0["lastScene"].string, let lastScene = Address(hex: lastSceneString) {
                    return SceneRange(from: firstScene, to: lastScene)
                }
                return nil
            })
        }
        // 后续申请的场景地址
        if let applySceneAddresses = provisionerJson["allocatedSceneRange"].arrayObject as? [Int] {
            // 场景地址
            let applySceneRanges = applySceneAddresses.splitArray().compactMap { array in
                if let firstScene = array.first, let lastScene = array.last {
                    return SceneRange(from: UInt16(firstScene), to: UInt16(lastScene))
                }
                return nil
            }
            allocatedSceneRange.append(contentsOf: applySceneRanges)
        }
        
        let localProvisioner = meshNetwork.localProvisioner
        
        let provisioner = Provisioner(name: localProvisioner?.name ?? UserData.currentUserName, uuid: localProvisioner?.uuid ?? UUID(), allocatedUnicastRange: allocatedUnicastRange, allocatedGroupRange: allocatedGroupRange, allocatedSceneRange: allocatedSceneRange)
        // 修改供应者地址
        if localProvisioner?.uuid.uuidString == provisioner.uuid.uuidString && localProvisioner?.primaryUnicastAddress != nil {
            try? meshNetwork.changeProvisioner(provisioner)
        }else {
            let address = localProvisioner?.primaryUnicastAddress ?? meshNetwork.nextAvailableUnicastAddress(elementsCount: 1, elementsUsing: provisioner, lockInAddress: false)
            try? meshNetwork.changeProvisioner(provisioner, localAddress: address)
            self.localAddress = address
            self.save()
        }
        meshNetwork.save()
    }
    
    /// 新增网络废弃地址
    func insetExclusionAddresses(list: [(ivIndex: UInt32, addresses: [Address])]) {
        
        let currentNetwork = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == self.meshUUID ? MeshNetworkManager.instance.meshNetwork : nil
        guard let meshNetwork = currentNetwork ?? MeshNetwork.load(meshUUID: self.meshUUID, allData: false) else {
            return
        }
        list.forEach { (ivIndex: UInt32, addresses: [Address]) in
            addresses.forEach { address in
                meshNetwork.insetExclusionAddress(ivIndex: ivIndex, address: address)
            }
        }
        
    }
    
}

extension SpaceData {
    
    /// 导入space数据
    /// - Parameters:
    ///   - siteId: 所属site id
    ///   - meshUUID: 网络uuid
    ///   - spaceJsonData: space数据
    /// - Returns: space
    static func `import`(siteId: String, meshUUID: String, spaceJsonData: [String: Any]) async -> SpaceData? {
        
        //       return await withCheckedContinuation { continuation in
        let json = JSON(spaceJsonData)
        guard let uuid = json["uuid"].string,
              let name = json["spaceName"].string else {
            return nil
        }
        
        var space = SpaceData.load(siteId: siteId, spaceId: uuid).first
        var initialize = false
        if space == nil{
            
            guard let netKeyDict = json["netKey"].dictionaryObject,
                  let netKeyData = try? JSONSerialization.data(withJSONObject: netKeyDict),
                  let netKey = try? jsonDecoder.decode(NetworkKey.self, from: netKeyData) else {
                return nil
            }
            
            var permission: Permission = .visitor
            switch json["role"].string {
            case "owner":
                permission = .owner
            case "editor":
                permission = .editor
            default:
                break
            }
            let newSpace = SpaceData(name: name, id: uuid, siteId: siteId, imageId: 0, create: json["createTimestamp"].int64Value, lastUpdate: json["updateTimestamp"].int64Value, isFavourite: false, permission: permission, sourceType: .share, meshUUID: meshUUID, meshNetworkId: netKey.networkId.hex)
            space = newSpace
            initialize = true
        }
        //            Task {
        await space?.update(spaceJsonData: spaceJsonData, initialize: initialize)
        //                continuation.resume(returning: space)
        //            }
        return space
        //        }
    }
    
    /// 更新空间内基本数据+设备、组、场景、日程
    /// - Parameter spaceJsonData: 空间数据
    /// - Parameter initialize: 是否初始化数据（本地无记录）
    func update(spaceJsonData: [String: Any], initialize: Bool = false) async {
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
            
            // 分享id
            if let shareId = json["shareId"].string {
                self.shareCode = shareId
            }
            // 是否启用访客密码
            if let vistorPasswordEnable = json["visitProtected"].bool {
                self.vistorPasswordEnable = vistorPasswordEnable
                if !vistorPasswordEnable, self.permission == .visitor {
                    self.requiresPasswordVerification = false
                }
            }
            // 访客密码
            if let visitorPasswd = json["visitorPasswd"].string {
                self.vistorPassword = visitorPasswd.count > 0 ? visitorPasswd : nil
            }
            
            // 权限
            if let role = json["role"].string {
                var permission: Permission = .visitor
                switch role {
                case "owner":
                    permission = .owner
                case "editor":
                    permission = .editor
                default:
                    break
                }
                self.permission = permission
            }
            
            if let userId = json["owner"]["userId"].string, let userName = json["owner"]["username"].string {
                self.owner = .init(name: userName, uuid: userId)
            }else {
                self.owner = nil
            }
            
            if let userId = json["editor"]["userId"].string, let userName = json["editor"]["username"].string {
                self.editor = .init(name: userName, uuid: userId)
            }else {
                self.editor = nil
            }
            // 访客数据
            if let visitors = json["visitors"].arrayObject as? [[String: Any]] {
                self.visitors = visitors.compactMap({
                    if let userId = $0["userId"] as? String, let userName = $0["username"] as? String {
                        return UserData(name: userName, uuid: userId)
                    }
                    return nil
                })
            }
            
            if self.state == .waitDeleted {
                self.state = .normal
                self.requiresPasswordVerification = false
                self.applyDeviceAddressCount = nil
                self.releaseAddress = false
                self.disableEditorPermission = false
            }
            // 用户事件
            if let events = json["userEvents"].arrayObject as? [String] {
//                var requiresPasswordVerification = false
                // 密码被修改
                if (self.permission == .editor && events.contains("EditorPasswdChanged")) || (self.permission == .visitor && events.contains("VisitorPasswdChanged") && self.vistorPasswordEnable) {
                    self.requiresPasswordVerification = true
                }
            }
            
            // 子网key丢失
            if let network = MeshNetwork.load(meshUUID: meshUUID, subnetworkId: self.meshNetworkId, allData: false), !network.networkKeys.contains(where: { $0.networkId.hex == self.meshNetworkId }) {
                // 修复子网key数据
                if let netKeyDict = json["netKey"].dictionaryObject,
                   let netKeyData = try? JSONSerialization.data(withJSONObject: netKeyDict),
                   let netKey = try? jsonDecoder.decode(NetworkKey.self, from: netKeyData),
                   let appKeyDict = json["appKey"].dictionaryObject,
                   let appKeyData = try? JSONSerialization.data(withJSONObject: appKeyDict),
                   let appKey = try? jsonDecoder.decode(ApplicationKey.self, from: appKeyData) {
                    
                    if !network.networkKeys.contains(where: { $0.index == netKey.index }) {
                        network.add(networkKey: netKey)
                        network.add(applicationKey: appKey)
                        network.save()
                    }
                    self.meshNetworkId = netKey.networkId.hex
                }
            }
            
            let lastUpdate = json["updateTimestamp"].int64Value
            // 服务器最后更新时间比本地时间新才覆盖本地数据
            guard lastUpdate > self.lastUpdate || initialize else {
                //                return
                continuation.resume()
                self.save()
                return
            }
            
            let meshUUID = self.meshUUID
            
            var meshNetwork: MeshNetwork?
            if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == meshUUID && MeshNetworkManager.instance.currentNetworkKey.networkId.hex == self.meshNetworkId {
                meshNetwork = MeshNetworkManager.instance.meshNetwork
            }else {
                meshNetwork = MeshNetwork.load(meshUUID: meshUUID, subnetworkId: self.meshNetworkId)
            }
            
            guard let network = meshNetwork else {
                continuation.resume()
                return
            }
            
            if let netKeyDict = json["netKey"].dictionaryObject,
               let netKeyData = try? JSONSerialization.data(withJSONObject: netKeyDict),
               let netKey = try? jsonDecoder.decode(NetworkKey.self, from: netKeyData),
               let appKeyDict = json["appKey"].dictionaryObject,
               let appKeyData = try? JSONSerialization.data(withJSONObject: appKeyDict),
               let appKey = try? jsonDecoder.decode(ApplicationKey.self, from: appKeyData) {
                
                if !network.networkKeys.contains(where: { $0.index == netKey.index }) {
                    network.add(networkKey: netKey)
                    network.add(applicationKey: appKey)
                    network.save()
                }
                self.meshNetworkId = netKey.networkId.hex
            }
            
            self.name = json["spaceName"].stringValue
            self.imageId = json["imageId"].intValue
            self.sourceType = .init(rawValue: json["source"].intValue) ?? .create
            //            self.isFavourite = json["favourite"].boolValue
            self.create = json["createTimestamp"].int64Value
            self.lastUpdate = json["updateTimestamp"].int64Value
            //            if self.lastUploadCloudTimestamp == nil {
            self.lastUploadCloudTimestamp = self.lastUpdate
            //            }
//            let localNodes = Node.load(meshUUID: self.meshUUID, subnetworkId: self.meshNetworkId)
            
            network.nodes.filter({ !$0.isLocalProvisioner }).forEach { node in
                network.forceRemove(node: node)
//                node.deleteExtension()
            }
            // 设备
            let nodes = nodeDicts.compactMap { nodeDict in
                var decodeNodeDict = nodeDict
                if let uuid = nodeDict["uuid"] as? String { // 换算成大写UUID提供Node解码
                    decodeNodeDict.updateValue(uuid, forKey: "UUID")
                }
                if let data = try? JSONSerialization.data(withJSONObject: decodeNodeDict), let node = try? jsonDecoder.decode(Node.self, from: data) {
                    let nodeJson = JSON(nodeDict)
                    if let version = nodeJson["versionSEQ"].uInt32 {
                        node.versionSEQ = version
                    }
//                    if let localNode = localNodes.first(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) {
//                        // 判断本地缓存比线上节点版本高则使用本地节点数据
//                        if localNode.versionSEQ > node.versionSEQ {
//                            return localNode
//                        }
//                        node = localNode
//                    }
                    
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
                    if let defaultLightness = nodeJson["defaultLightness"].uInt16 {
                        node.defalutLightness = defaultLightness
                    }
                    if let defaultCct = nodeJson["defaultCct"].uInt16 {
                        node.defaultCct = defaultCct
                    }
                    if let timezoneOffset = nodeJson["timezoneOffset"].uInt8, let timestamp = nodeJson["timestamp"].int64, timestamp >= 0 {
                        node.timezone = timezoneOffset.decodeFromTzOffset()
                        node.timestamp = UInt64(timestamp)
                    }
                    if let enOceanMacAddress = nodeJson["enOceanMacAddress"].string {
                        node.enOceanMacAddress = enOceanMacAddress
                        // 动能开关按键配置
                        if let enOceanProxySwitchKeyDicts = nodeJson["enOceanProxySwitchKeys"].arrayObject as? [[String: Any]],
                           let data = try? JSONSerialization.data(withJSONObject: enOceanProxySwitchKeyDicts),
                           let enOceanProxySwitchKeys = try? jsonDecoder.decode([SwitchKey].self, from: data) {
                            node.enOceanProxySwitchKeys = enOceanProxySwitchKeys
                        }
                        
                        if let enOceanKeyScenes = nodeJson["enOceanKeyScenes"].arrayObject as? [String] {
                            node.enOceanKeySceneNumbers = enOceanKeyScenes.map({ SceneNumber(hex: $0) ?? 0 })
                        }
                    }
                    
                    if let firmwareID = nodeJson["firmwareID"].string, !firmwareID.isEmpty {
                        let data = Data(hex: firmwareID)
                        if data.count == 6 || data.count == 8 {
                            node.firmwareID = data
                        }
                    }
                    if let distributionFirmwareID = nodeJson["distributionFirmwareID"].string, !distributionFirmwareID.isEmpty {
                        let data = Data(hex: distributionFirmwareID)
                        if data.count == 6 || data.count == 8 {
                            node.distributionFirmwareID = data
                        }
                    }
                    
                    if let compositionHash = nodeJson["compositionHash"].string, !compositionHash.isEmpty {
                        node.compositionHash = compositionHash
                    }
                    if let defaultTransitionTime = nodeJson["defaultTransitionTime"].uInt8 {
                        node.defaultTransitionTime = .init(rawValue: defaultTransitionTime)
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
                                let yearValue = scheduleJson["year"].int ?? 0
                                var year: SchedulerYear = .any()
                                if yearValue < 100 {
                                    year = .specific(year: yearValue)
                                }
                            
                                let entry = SchedulerRegistryEntry(year: year, month: .any(of: Schedule.allMonths), day: .specific(day: scheduleJson["day"].int ?? 0), hour: .specific(hour: scheduleJson["hour"].int ?? 0), minute: .specific(minute: scheduleJson["minute"].int ?? 0), second: .specific(second: scheduleJson["second"].int ?? 0), dayOfWeek: .any(of: dayOfWeek), action: SchedulerAction(rawValue: scheduleJson["action"].uInt8 ?? 0x0F) ?? .noAction, transitionTime: .init(steps: scheduleJson["transitionTime"].uInt8 ?? 0, stepResolution: .seconds), sceneNumber: scheduleJson["sceneNumber"].uInt16 ?? 0)
                                node.schedulerActions.updateValue(entry, forKey: id)
                            }
                        }
                        node.scheduleIds = node.schedulerActions.map({ $0.key })
                    }
                    
                    if let lightLCPropertyDict = nodeJson["lightLCPropertys"].dictionaryObject,
                       let lightLCPropertyData = try? JSONSerialization.data(withJSONObject: lightLCPropertyDict) {
                        
                        if let lightLCProperty = try? jsonDecoder.decode(LightLCProperty.self, from: lightLCPropertyData) {
                            node.lightLCProperty = lightLCProperty
                        }
                    }
                    
                    // 光感校准值
                    if let daylightCalibrationValue = nodeJson["daylightCalibrationValue"].uInt16 {
                        node.daylightCalibrationValue = daylightCalibrationValue
                    }
                    
                    return node
                }
                return nil
            }
            
            
//            network.getNetworkExclusionAddresses().filter { (ivIndex: UInt32, addresses: [Address]) in
//                
//            }
            let exclusions = network.getNetworkExclusionAddresses()
            nodes.forEach({
                // 判断设备是否存在废弃地址内，如果存在则清空废弃地址内缓存（如多用户编辑数据并未及时提交，使用了旧数据则可能出现导入的设备地址在废弃地址内）
                if network.isAddressInExclusion(node: $0) {
                    let range = AddressRange(from: $0.primaryUnicastAddress, elementsCount: $0.elementsCount)
                    for address in range.range {
                        network.deleteExclusionAddress(ivIndex: network.currentIVIndex, address: address)
                        if network.currentIVIndex > 0 {
                            network.deleteExclusionAddress(ivIndex: network.currentIVIndex - 1, address: address)
                        }
                    }
                }
                try? network.add(node: $0)
            })
            
            while network.scenes.count > 0 {
                network.forceRemove(scene: network.scenes.first!.number)
            }
            SceneInfo.delete(meshUUID: meshUUID, networkId: self.meshNetworkId)
            // 场景
            let scenes = sceneDicts.compactMap { sceneDict in
                let sceneJson = JSON(sceneDict)
                if let sceneNumberHex = sceneJson["number"].string, let sceneNumber = SceneNumber(hex: sceneNumberHex), let name = sceneJson["name"].string {
                    let scene = Scene(sceneNumber, name: name)
                    scene.subNetworkId = self.meshNetworkId
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
//                group.deleteExtension()
            }
            GroupInfo.delete(meshUUID: meshUUID, networkId: self.meshNetworkId)
            Profile.deleteProfiles(meshUUID: meshUUID, meshNetworkId: self.meshNetworkId)
            // 按键
//            var switches: [GroupSwitch] = []
            
            let groups = groupDicts.compactMap { groupDict in
                if let data = try? JSONSerialization.data(withJSONObject: groupDict), let group = try? jsonDecoder.decode(Group.self, from: data) {
                    let groupJson = JSON(groupDict)
                    group.isVirtual = groupJson["isVirtual"].boolValue
                    group.subNetworkId = self.meshNetworkId
                    guard !group.isVirtual else {
                        return group
                    }
                    group.info = GroupInfo(address: group.address.address, imageId: groupJson["imageId"].int ?? 1, imageText: groupJson["imageText"].string)
                    // profile
                    if let profileDict = groupJson["profile"].dictionaryObject {
                        let profileJson = JSON(profileDict)
                        if let id = profileJson["id"].string, let type = Profile.ProfileType(rawValue: profileJson["type"].int ?? 1) {
                            
                            let lightData = Profile.LightData(profileType: type, highEndTrim: profileJson["highEndTrim"].int ?? 100, lowEndTrim: profileJson["lowEndTrim"].int ?? 0, occupancyLevel: profileJson["occupancyLevel"].int ?? 100, vacantLevel: profileJson["vacantLevel"].int ?? 50, taskLevel: profileJson["taskLevel"].int ?? 100, autoMinLevel: profileJson["autoMinLevel"].int ?? 0, t1: profileJson["timeT1"].int ?? 0, t2: profileJson["timeT2"].int ?? 0, t3: profileJson["timeT3"].int ?? 0, t4: profileJson["timeT4"].int ?? 0, t5: profileJson["timeT5"].int ?? 0)
                            
                            let profile = Profile(id: id, type: type, lightData: lightData, powerUpState: Profile.PowerUpState(rawValue: profileJson["powerUpState"].uInt8 ?? 0), manualOverrideTimeout: profileJson["manualOverrideTimeout"].uInt32 ?? 600)
                            if let powerOnCct = profileJson["powerOnCct"].uInt16 {
                                profile.powerUpCct = powerOnCct
                            }
                            profile.adjustSpeed = profileJson["adjustSpeed"].int ?? 50
                            group.info.profile = profile
                        }
                    }
                    // 选择的光照传感器
                    if let sensorAddressHex = groupJson["daylightSensorAddress"].string,
                       let sensorAddress = Address(hex: sensorAddressHex) {
                        group.info.ambientLightSensorNodeAddress = sensorAddress
                    }
                    // scenes data
                    if let sceneDicts = groupJson["scenesDatas"].arrayObject,
                       let data = try? JSONSerialization.data(withJSONObject: sceneDicts) {
                        let sceneExecuteDatas = try? jsonDecoder.decode([SceneExecuteData].self, from: data)
                        group.info.sceneExecuteDatas = sceneExecuteDatas ?? []
                    }
                    
                    // schedules
                    let bindSchedules = schedules.filter({ schedule in
                        schedule.groupAddresses.contains(group.address.address) ||
                        schedule.needDeleteGroupAddresses.contains(group.address.address) ||
                        group.info.sceneExecuteDatas.contains(where: { $0.sceneNumber == schedule.sceneNumber })
                    })
                    group.info.bindSchedules = bindSchedules
                    
                    // switches
//                    if let switcheDicts = groupJson["switches"].arrayObject {
//                        switcheDicts.forEach { switcheDict in
//                            let switcheJson = JSON(switcheDict)
//                            if let id = switcheJson["id"].string, let name = switcheJson["name"].string {
//                                var sceneA: SceneNumber?
//                                var sceneB: SceneNumber?
//                                if let sceneAHex = switcheJson["sceneA"].string,
//                                   let sceneANumber = SceneNumber(sceneAHex) {
//                                    sceneA = sceneANumber
//                                }
//                                if let sceneBHex = switcheJson["sceneB"].string,
//                                   let sceneBNumber = SceneNumber(sceneBHex) {
//                                    sceneB = sceneBNumber
//                                }
//                                
//                                var proxyNode: Node?
//                                if let macAddress = switcheJson["enOceanMacAddress"].string {
//                                    proxyNode = nodes.first(where: { $0.enOceanMacAddress == macAddress })
//                                }
//                                let groupSwitch = GroupSwitch(id: id, groupAddress: group.address.address, enabled: switcheJson["enabled"].bool ?? true, name: name, sceneANumber: sceneA, sceneBNumber: sceneB, proxyNodeAddress: proxyNode?.primaryUnicastAddress)
//                                group.info.switchs.append(groupSwitch)
//                                switches.append(groupSwitch)
//                            }
//                        }
//                    }
                    return group
                }
                return nil
            }
            groups.forEach({
                try? network.add(group: $0)
                $0.saveExtension()
            })
            
            var switches: [DeviceSwitchData] = []
            if let switchesDicts = json["switches"].arrayObject as? [[String: Any]] {
                switchesDicts.forEach { dict in
                    let switcheJson = JSON(dict)
                    if let id = switcheJson["id"].string, let name = switcheJson["name"].string {
                        let switchData = DeviceSwitchData(id: id, enabled: switcheJson["enabled"].boolValue, name: name)
                        if let typeValue = switcheJson["panelType"].uInt8, let panelType = DeviceSwitchData.PanelType(rawValue: typeValue) {
                            switchData.panelType = panelType
                        }
                        if let addressHex = switcheJson["linkGroupAddress"].string, let linkGroupAddress = Address(hex: addressHex) {
                            switchData.linkGroupAddress = linkGroupAddress
                        }
                        if let addressHex = switcheJson["subLinkGroupAddress"].string, let subLinkGroupAddress = Address(hex: addressHex) {
                            switchData.subLinkGroupAddress = subLinkGroupAddress
                        }
                        
                        if let sceneAHex = switcheJson["sceneA"].string,
                           let sceneANumber = SceneNumber(hex: sceneAHex) {
                            switchData.sceneANumber = sceneANumber
                        }
                        if let sceneBHex = switcheJson["sceneB"].string,
                           let sceneBNumber = SceneNumber(hex: sceneBHex) {
                            switchData.sceneBNumber = sceneBNumber
                        }
                        if let sceneCHex = switcheJson["sceneC"].string,
                           let sceneCNumber = SceneNumber(hex: sceneCHex) {
                            switchData.sceneCNumber = sceneCNumber
                        }
                        if let sceneDHex = switcheJson["sceneD"].string,
                           let sceneDNumber = SceneNumber(hex: sceneDHex) {
                            switchData.sceneDNumber = sceneDNumber
                        }
                        
                        if let proxyAddress = switcheJson["proxyNodeAddress"].string {
                            switchData.proxyNodeAddress = Address(hex: proxyAddress)
                        }
                        
                        if let bindGroupAddresseStrings = switcheJson["bindGroupAddresses"].arrayObject as? [String] {
                            switchData.bindGroupAddresses = bindGroupAddresseStrings.compactMap({ Address(hex: $0) })
                        }
                        if let unbindGroupAddresseStrings = switcheJson["unbindGroupAddresses"].arrayObject as? [String] {
                            switchData.unbindGroupAddresses = unbindGroupAddresseStrings.compactMap({ Address(hex: $0) })
                        }
                        if let enOceanMacAddress = switcheJson["enOceanMacAddress"].string {
                            switchData.enOceanMacAddress = enOceanMacAddress
                        }
                        if let enOceanSecurityKey = switcheJson["enOceanSecurityKey"].string {
                            switchData.enOceanSecurityKey = enOceanSecurityKey
                        }
                        switches.append(switchData)
                    }
                }
            }
            DeviceSwitchData.deleteSwitchs(meshUUID: meshUUID, networkId: self.meshNetworkId)
            switches.forEach { switchData in
                switchData.save(meshUUID: meshUUID, networkId: self.meshNetworkId)
            }
            
            self.deviceCount = (meshNetwork?.nodes ?? nodes).count
            self.luminairesCount = nodes.filter({ $0.lightnessModel != nil }).count
            self.groupCount = groups.filter({ !$0.isVirtual }).count
            self.sceneCount = scenes.count
            self.scheheduleCount = schedules.count
            self.switchesCount = switches.count
            self.save()
            continuation.resume()
        }
    }
    
}
