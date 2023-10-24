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
    
    /// 添加场所
    /// - Parameter name: 场所名称
    /// - Returns: 场所
    static func add(name: String) -> SiteData {
        let time = CLongLong(Date().timeIntervalSince1970 * 1000)
        let site = SiteData(id: UUID().uuidString, name: name, imageId: 1, type: .office, create: "\(time)",isFavourite: false, sourceType: .create)
        site.save()
        return site
    }
    
    /// 场所添加空间
    /// - Parameters:
    ///   - name: 空间名称
    ///   - id: 空间id
    ///   - imageId: 空间图片id
    /// - Returns: 空间
    func addSpace(name: String, id: String = UUID().uuidString, imageId: Int = 1) -> SpaceData {
        
        let time = CLongLong(Date().timeIntervalSince1970 * 1000)
        let space = SpaceData(name: name, id: id, siteId: self.id, imageId: imageId, create: "\(time)", isFavourite: false, sourceType: .create, meshUUID: id)
        addSpace(space)
        return space
    }
     
    /// 场所添加空间
    /// - Parameter space: 空间数据
    func addSpace(_ space: SpaceData) {
        // 没有对应mesh网络时创建一个网络
        if MeshNetworkManager.loadMeshNetwork(meshUUID: space.meshUUID) == nil {
            MeshLibManager.manager.createMeshNetwork(meshUUID: space.meshUUID, meshNetworkName: space.name, connected: false)
        }
        space.save()
        spaces.append(space)
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
}

extension SpaceData {
    
    private struct AssociatedKey {
        static var meshManagerKey: String = "meshManager"
    }
    
    var meshManager: MeshNetworkManager? {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.meshManagerKey) as? MeshNetworkManager ??
            MeshNetworkManager.loadMeshNetwork(meshUUID: id)
        }set {
            objc_setAssociatedObject(self, &AssociatedKey.meshManagerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    
    var nodes: [Node] {
        return meshManager?.realNodes ?? []
    }
    
    var groups: [Group] {
        return meshManager?.groups ?? []
    }
    
    var scenes: [Scene] {
        return meshManager?.scenes ?? []
    }
    
    
    /// 获取下一个节点名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 分配的节点名称
    func getNextNodeName(_ defalutName: String = "device_defalut_name".localizedString) -> String {
        objc_sync_enter(self)
        
        var resultName = defalutName + "001"
        // 已存在的节点名称
        let existNames = self.nodes.map({ $0.name ?? "" })
        for index in 1...32767 {
            // ID001
            let name = defalutName + String(format: "%03d", index)
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
        return nodes.contains(where: { $0.name == nodeName })
    }
    
    /// 获取下一个场景名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 分配的场景名称
    func getNextSceneName(_ defalutName: String = "scene_defalut_name".localizedString) -> String {
        // 已存在的场景名称
        let existNames = scenes.map({ $0.name })
        for index in 1...16 {
            let name = defalutName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defalutName + "1"
    }
    
    /// 获取下一个组名称
    /// - Parameter defalutName: 默认名称
    /// - Returns: 分配的组名称
    func getNextGroupName(_ defalutName: String = "group_defalut_name".localizedString) -> String {
        // 已存在的组名称
        let existNames = groups.map({ $0.name })
        for index in 1...16 {
            let name = defalutName + "\(index)"
            if !existNames.contains(name) {
                return name
            }
        }
        return defalutName + "1"
    }
    
    /// 克隆空间数据（空间信息、mesh网络数据）
    /// - Parameter save: 是否本地缓存
    func clone(_ save: Bool = false) -> SpaceData {
        
        let spaceData = self.cloneData()
        // 创建的mesh网络
        let meshManager = MeshNetworkManager.createMeshNetwork(meshUUID: spaceData.id, meshNetworkName: spaceData.name)
        // 克隆目标的mesh网络，同步数据
        if let cloneMeshManager = spaceData.meshManager {
            // clone 组，场景，日程，节律等这些能够预设的参数。（目前只有组、场景）
            cloneMeshManager.groups.forEach { group in
                try? meshManager.meshNetwork?.add(group: group)
            }
            cloneMeshManager.scenes.forEach { scene in
                try? meshManager.meshNetwork?.add(scene: scene.number, name: scene.name)
            }
        }
        _ = meshManager.save()
        if save {
            spaceData.save()
        }
        return spaceData
    }
    
    /// 删除空间数据+mesh网络
    @discardableResult func delete() -> Bool {
        
        // 删除mesh网络文件并断开连接
//        MeshLibManager.manager.removeMeshNetwork(meshUUID: self.meshUUID)
        if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == self.meshUUID {
            MeshLibManager.manager.meshNetworkDisconnect()
        }
        _ = MeshNetworkManager.removeMeshNetwork(meshUUID: self.meshUUID)
        
        return self.deleteData()
    }
    
}

extension Node {
    
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
    
    /// 根据色温范围获取对应色温颜色
    /// - Parameter cct100: 0~100色温
    /// - Returns: 对应色温颜色
    func getCctMixColor() -> UIColor {
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
    
}
