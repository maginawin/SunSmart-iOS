//
//  NetowrkReqeustApi.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/28.
//

import Foundation
import Moya
import NordicSigMeshSDK


enum NetowrkReqeustApi {
    
    /// space密码数据
    struct SpacePasswordData {
        let spaceId: String
        let password: String?
        let permission: Permission

        func toJsonData() -> [String: Any] {
            var passwordKey = "visitorPasswd"
            if self.permission == .editor {
                passwordKey = "editorPasswd"
            }
            return ["spaceId": self.spaceId, passwordKey: self.password ?? ""]
        }
    }
    
    /// 地址类型
    enum AddressType: String {
        case device = "device"
        case group = "group"
        case scene = "scene"
    }
    
    /// 获取用户site list
    case sites
    /// 获取site信息
    case siteInfo(siteId: String)
    /// 获取 Edit Site 属性
    case sitePropsRetrieve(siteId: String)
    /// 分量更新 Edit Site 属性
    case sitePropsUpdate(siteId: String, props: [String: Any])
    /// 添加site  useDeivceAddressNum: 已使用的设备地址数量
    case siteAdd(siteData: [String: Any], useDeivceAddressNum: Int)
    /// 更新/提交site数据
    case siteUpload(siteData: [String: Any])
    /// 删除site
    case siteDelete(siteId: String)
    /// 获取space信息  password: editor/visitor权限进入space密码
    case spaceInfo(siteId: String, spaceId: String, password: String?)
    /// 添加space
//    case spaceAdd(space: SpaceData)
    /// 添加spaces
//    case spacesAdd(siteId: String, spaceDatas: [[String: Any]])
    /// 更新/提交space数据
    case spaceUpload(siteId: String, spaceData: [String: Any])
    /// 删除space
    case spaceDelete(siteId: String, spaceId: String)
    /// 批量删除space
    case spacesDelete(siteId: String, spaceIds: [String])
    
    // #****** 分享/权限 ******#
    /// space分享
    case spaceShare(space: SpaceData)
    /// spaces批量分享
    case spacesShare(siteId: String, spaceIds: [String], password: String, userPermission: Permission)
    /// 批量分享list
    case batchShareList(siteId: String)
    /// 撤销批量分享
    case revocationBatchShare(siteId: String, batchId: String)
    /// 加入space permission：权限类型，editor/visitor visitor可能无密码
    case joinSpace(shareId: String, password: String?, permission: Permission)
    /// 批量加入spaces  permission：权限类型，editor/visitor visitor无密码
//    case joinSpaces(shareId: String, password: String?, permission: Permission)
    /// 获取分享数据信息 分享id：space、批量spaces、转移site
    case shareInfo(shareId: String)
    /// space成员信息
    case spaceMembers(siteId: String, spaceId: String)
    /// 清除space内成员   userId: 对应用户id   permission：权限类型  force：是否强制删除
    case clearSpaceMember(siteId: String, spaceId: String, userId: String, permission: Permission, force: Bool)
    /// 批量清除space内成员   userIds: 对应用户id list   permission：权限类型  force：是否强制删除
    case clearSpaceMembers(siteId: String, spaceId: String, userIds: [String], permission: Permission, force: Bool)
    /// 批量清除多个space成员 spaces: 需要删除成员的space  permission：权限类型  force：是否强制删除
    case clearSpacesMembers(siteId: String, spaces: [String], permission: Permission, force: Bool)
    /// editor/visitor 批量解绑space  recycleDeviceAddresses: 回收的设备地址list   recycleGroupAddresses: 回收的组地址list  recycleSceneAddresses: 回收的场景地址list  provisionerData: 用户当前网络地址数据
    case unbindSpaces(siteId: String, spaceIds: [String], recycleDeviceAddresses: [Int]? = nil, recycleGroupAddresses: [Int]? = nil, recycleSceneAddresses: [Int]? = nil, exclusions: [(ivIndex: Int, addresses: [Int])]? = nil, provisionerData: [String: Any]? = nil)
    /// 修改space密码 permission：权限类型，editor/visitor
    case spacePasswordSet(siteId: String, spacePassword: SpacePasswordData)
    /// 批量修改space密码
    case spacesPasswordSet(siteId: String, spacePasswords: [SpacePasswordData])
    /// 清空space密码 permission：权限类型，editor/visitor
//    case spacePasswordClear(siteId: String, spaceId: String, permission: Permission)
    /// 批量启用/禁用space访客密码
    case spacesVisitorPasswordEnabled(siteId: String, spacePasswords: [SpacePasswordData], enabled: Bool)
    
    /// 修改批量分享的editor密码
    case batchSpacesPasswordSet(batchId: String, password: String)
    
    /// 转移site
    case transferSite(siteId: String, password: String)
    /// 接收site
    case receiveSite(shareId: String, password: String)
    /// 获取space下活跃用户（owner/editor/visitor）
    case spaceActiveMembers(siteId: String, spaceId: String)
    // #****** 用户 ******#
    /// 心跳
    case heartbeat(siteId: String, spaceId: String, permission: Permission)
    /// 用户信息修改 name：用户名
    case userInfoSet(name: String)
    
    // #****** 地址 ******#
    /// 地址申请 type：地址类型  number：申请数量
    case applyAddress(siteId: String, type: AddressType = .device, number: Int)
    
    /// 回收地址  recycleDeviceAddresses: 回收的设备地址list   recycleGroupAddresses: 回收的组地址list  recycleSceneAddresses: 回收的场景地址list  provisionerData: 用户当前网络地址数据
    case recyclingAddress(siteId: String, recycleDeviceAddresses: [Int]? = nil, recycleGroupAddresses: [Int]? = nil, recycleSceneAddresses: [Int]? = nil, exclusions: [(ivIndex: Int, addresses: [Int])]? = nil, provisionerData: [String: Any]? = nil)
    
    // #****** OTA ******#
    /// 获取最新的固件包
    case firmwareLatestVersion(companyId: String = "0A78", deviceType: String, customId: String = "00", isTesting: Bool = false)
    /// 固件包历史版本list
    case firmwareVersionList(companyId: String = "0A78", deviceType: String, customId: String = "00", isTesting: Bool = false)
    /// 设备配置数据
    case devicesConfig

    /// 模拟设备故障
    case simulateFault(payload: SimulateFaultRequestPayload)
    
    // #****** Gateway ******#
    /// 网关list
    case gatewayList(siteId: String)
    /// 网关绑定到space
    case gatewayBindSpace(spaceId: String, gatewayId: String)
    /// 网关解绑space
    case gatewayUnbindSpace(spaceId: String, gatewayId: String)
    /// 原子清空网关关联的所有space（请求体必须省略spaceId）
    case gatewayUnbindAllSpaces(gatewayId: String)
    /// 网关注册
//    case gatewayRegister(gatewayId: String)
    case gatewayRegister(siteId: String, gatewayId: String, nodeId: String, node: [String: Any], updateTimestamp: Int64)
    /// 删除网关
    case gatewayDelete(gatewayId: String)
    /// 获取网关关联的所有space数据
    case gatewayAssociationSpaceList(siteId: String, gatewayId: String)
    /// 提交网关时区同步
    case gatewayDateTimeUpdate(siteId: String, gateways: [String])
    /// 获取网关时区同步状态
    case gatewayDateTimeRequestStatus(requestId: Int64)
}

extension NetowrkReqeustApi {

    var diagnosticName: String {
        switch self {
        case .sites: return "sites"
        case .siteInfo: return "siteInfo"
        case .sitePropsRetrieve: return "sitePropsRetrieve"
        case .sitePropsUpdate: return "sitePropsUpdate"
        case .siteAdd: return "siteAdd"
        case .siteUpload: return "siteUpload"
        case .siteDelete: return "siteDelete"
        case .spaceInfo: return "spaceInfo"
        case .spaceUpload: return "spaceUpload"
        case .spaceDelete: return "spaceDelete"
        case .spacesDelete: return "spacesDelete"
        case .spaceShare: return "spaceShare"
        case .spacesShare: return "spacesShare"
        case .batchShareList: return "batchShareList"
        case .revocationBatchShare: return "revocationBatchShare"
        case .joinSpace: return "joinSpace"
        case .shareInfo: return "shareInfo"
        case .spaceMembers: return "spaceMembers"
        case .clearSpaceMember: return "clearSpaceMember"
        case .clearSpaceMembers: return "clearSpaceMembers"
        case .clearSpacesMembers: return "clearSpacesMembers"
        case .unbindSpaces: return "unbindSpaces"
        case .spacePasswordSet: return "spacePasswordSet"
        case .spacesPasswordSet: return "spacesPasswordSet"
        case .spacesVisitorPasswordEnabled: return "spacesVisitorPasswordEnabled"
        case .batchSpacesPasswordSet: return "batchSpacesPasswordSet"
        case .transferSite: return "transferSite"
        case .receiveSite: return "receiveSite"
        case .spaceActiveMembers: return "spaceActiveMembers"
        case .heartbeat: return "heartbeat"
        case .userInfoSet: return "userInfoSet"
        case .applyAddress: return "applyAddress"
        case .recyclingAddress: return "recyclingAddress"
        case .firmwareLatestVersion: return "firmwareLatestVersion"
        case .firmwareVersionList: return "firmwareVersionList"
        case .devicesConfig: return "devicesConfig"
        case .simulateFault: return "simulateFault"
        case .gatewayList: return "gatewayList"
        case .gatewayBindSpace: return "gatewayBindSpace"
        case .gatewayUnbindSpace: return "gatewayUnbindSpace"
        case .gatewayUnbindAllSpaces: return "gatewayUnbindAllSpaces"
        case .gatewayRegister: return "gatewayRegister"
        case .gatewayDelete: return "gatewayDelete"
        case .gatewayAssociationSpaceList: return "gatewayAssociationSpaceList"
        case .gatewayDateTimeUpdate: return "gatewayDateTimeUpdate"
        case .gatewayDateTimeRequestStatus: return "gatewayDateTimeRequestStatus"
        }
    }

    var requestTimeoutInterval: TimeInterval {
        switch self {
        case .gatewayUnbindAllSpaces, .gatewayDelete:
            return 30
        default:
            return 10
        }
    }

    var declaredContentEncodingGzip: Bool {
        headers?["Content-Encoding"]?.localizedCaseInsensitiveContains("gzip") == true
    }

    var actualBodyGzip: Bool {
        switch task {
        case .requestCompositeData(let bodyData, _):
            return bodyData.isGzipData
        default:
            return false
        }
    }

    var sanitizedParameters: [String: Any]? {
        guard let parameters else {
            return nil
        }
        return Self.sanitizedValue(parameters) as? [String: Any]
    }

    static func sanitizedValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            dict.forEach { key, value in
                if sensitiveParameterKeys.contains(key) {
                    result[key] = "<redacted>"
                } else {
                    result[key] = sanitizedValue(value)
                }
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { sanitizedValue($0) }
        }
        return value
    }

    private static let sensitiveParameterKeys: Set<String> = [
        "passwd",
        "editorPasswd",
        "visitorPasswd"
    ]
}

private extension Data {

    var isGzipData: Bool {
        count >= 2 && self[startIndex] == 0x1f && self[index(after: startIndex)] == 0x8b
    }
}

extension NetowrkReqeustApi: TargetType {
    
    var baseURL: URL {
        return UserData.currentServerRegion.baseURL
//        return URL(string: "https://www.mericher.com/srv2")!
    }
    
    var path: String {
        switch self {
        case .sites:
            return "/sitespace/get/sitelist"
        case .siteInfo:
            return "/sitespace/get/siteprops"
        case .sitePropsRetrieve:
            return "/sitespace/retrieve/siteprops"
        case .sitePropsUpdate:
            return "/sitespace/update/siteprops"
        case .siteUpload, .siteAdd:
            return "/sitespace/sync/siteprops"
        case .siteDelete:
            return "/sitespace/site/delete"
        case .spaceInfo:
            return "/sitespace/get/spaceprops"
        case .spaceUpload:
            return "/sitespace/sync/spaceprops"
        case .spaceDelete:
            return "/sitespace/spaces/delete"
        case .spacesDelete:
            return "/sitespace/spaces/delete"
        case .spacePasswordSet:
            return "/sitespace/space/changepass"
        case .spacesPasswordSet:
            return "/sitespace/space/bulk/changepass"
        case .spacesVisitorPasswordEnabled:
            return "/sitespace/space/visitpass/enable"
        case .batchSpacesPasswordSet:
            return "/sitespace/batchshare/changepass"
//        case .spacePasswordClear:
//            return "/sitespace/space/clearpass"
        case .transferSite:
            return "/sitespace/site/ownertrans"
        case .spaceShare, .spaceMembers:
            return "/sitespace/space/singleshare"
        case .spacesShare:
            return "/sitespace/space/batchshare"
        case .batchShareList:
            return "/sitespace/site/batchshare/list"
        case .revocationBatchShare:
            return "/sitespace/site/batchshare/delete"
        case .joinSpace, .receiveSite:
            return "/sitespace/share/receive"
        case .shareInfo:
            return "/sitespace/share/info"
        case .clearSpaceMember:
            return "/sitespace/space/permis/reclaim"
        case .clearSpaceMembers:
            return "/sitespace/space/permis/bulk/reclaim"
        case .clearSpacesMembers:
            return "/sitespace/site/permis/bulk/reclaim"
        case .unbindSpaces:
            return "/sitespace/space/unbind"
        case .heartbeat:
            return "/sitespace/user/hb"
        case .userInfoSet:
            return "/sitespace/user/update"
        case .applyAddress:
            return "/sitespace/address/claim"
        case .recyclingAddress:
            return "/sitespace/address/release"
        case .spaceActiveMembers:
            return "/sitespace/get/activeuser"
        case .firmwareLatestVersion:
            return "/sitespace/ota/latest"
        case .firmwareVersionList:
            return "/sitespace/ota/history"
        case .devicesConfig:
            return "/sitespace/ota/configfile"
        case .simulateFault:
            return "/temporary/device/alert/add"
        case .gatewayList:
            return "/sitespace/site/gateways"
        case .gatewayBindSpace:
            return "/sitespace/sapce/gateway/bind"
        case .gatewayUnbindSpace, .gatewayUnbindAllSpaces:
            return "/sitespace/sapce/gateway/unbind"
        case .gatewayRegister:
            return "/sitespace/sapce/gateway/regist"
        case .gatewayDelete:
            return "/sitespace/sapce/gateway/delete"
        case .gatewayAssociationSpaceList:
            return "/sitespace/sapce/gateway/reference"
        case .gatewayDateTimeUpdate:
            return "/sitespace/gateway/datetime/update"
        case .gatewayDateTimeRequestStatus:
            return "/sitespace/request/status"
        }
    }
    
    var method: Moya.Method {
//        switch self {
//        case .updateNetwork:
//            return .get
//        default:
//            return .post
//        }
        return .post
    }
    
    var sampleData: Data {
        return "".data(using: .utf8)!
    }
    
    var parameters: [String: Any]? {
        
        switch self {
        case .sites:
            return ["userId": UserData.currentUserId]
        case .siteInfo(let siteId):
            return ["siteId": siteId, "userId": UserData.currentUserId]
        case .sitePropsRetrieve(let siteId):
            let props: [String: Any] = [
                "timezone": NSNull(),
                "imageId": NSNull(),
                "siteName": NSNull(),
                "updateTimestamp": NSNull()
            ]
            return ["userId": UserData.currentUserId, "siteId": siteId, "props": props]
        case .sitePropsUpdate(let siteId, let props):
            return ["userId": UserData.currentUserId, "siteId": siteId, "props": props]
        case .siteAdd(let siteData, let useDeivceAddressNum):
            
            let user: [String: Any] = [
                "userId": UserData.currentUserId,
                "username": UserData.currentUserName
            ]
            return ["site": siteData, "devicesInSetle": useDeivceAddressNum, "user": user]
            
        case .siteUpload(let siteData):
            
            let user: [String: Any] = [
                "userId": UserData.currentUserId,
                "username": UserData.currentUserName
            ]
            return ["site": siteData, "user": user]
        case .siteDelete(let siteId):
            return ["siteId": siteId, "userId": UserData.currentUserId]
        case .spaceInfo(let siteId, let spaceId, let password):
            return ["siteId": siteId, "spaceId": spaceId, "passwd": password ?? "", "userId": UserData.currentUserId]
//        case .spacesAdd(let siteId, let spaceDatas):
//            let spaceDatas = spaces.map({ $0.export() })
//            return ["siteId": siteId, "spaces": spaceDatas, "user": user]
        case .spaceUpload(let siteId, let spaceDatas):
            return ["siteId": siteId, "spaces": [spaceDatas], "userId": UserData.currentUserId]
        case .spaceDelete(let siteId, let spaceId):
            return ["siteId": siteId, "spaces": [spaceId], "userId": UserData.currentUserId]
        case .spacesDelete(let siteId, let spaceIds):
            return ["siteId": siteId, "spaces": spaceIds, "userId": UserData.currentUserId]
        case .spacePasswordSet(let siteId, let spacePassword):
            
            var parameter: [String: Any] = ["siteId": siteId, "userId": UserData.currentUserId]
            spacePassword.toJsonData().forEach({
                parameter.updateValue($0.value, forKey: $0.key)
            })
            return parameter
        case .spacesPasswordSet(let siteId, let spaces):
            
            let spaceDatas = spaces.map({ $0.toJsonData() })
            return ["siteId": siteId, "spaces": spaceDatas, "userId": UserData.currentUserId]
        case .spacesVisitorPasswordEnabled(let siteId, let spaces, let enabled):
            
            let spaceDatas = spaces.map({ $0.toJsonData() })
            return ["siteId": siteId, "spaces": spaceDatas, "enable": enabled, "userId": UserData.currentUserId]
        case .batchSpacesPasswordSet(let batchId, let password):
            return ["token": batchId, "passwd": password, "userId": UserData.currentUserId]
//        case .spacePasswordClear(let siteId, let spaceId, let permission):
//            
//            var parameter: [String: Any] = ["siteId": siteId, "spaceId": spaceId, "userId": UserData.currentUserId]
//            if permission == .editor {
//                parameter.updateValue(false, forKey: "withEditorPasswd")
//            }else {
//                parameter.updateValue(false, forKey: "withVisitorPasswd")
//            }
//            return parameter
        case .spaceShare(let space):
            
            var parameter = ["siteId": space.siteId, "spaceId": space.id, "editorPasswd": space.editorPassword ?? "", "sharerRole": space.permission.dataString, "userId": UserData.currentUserId]
            if let password = space.vistorPassword {
                parameter.updateValue(password, forKey: "visitorPasswd")
            }
            return parameter
        case .spacesShare(let siteId, let spaceIds, let password, let userPermission):
            return ["siteId": siteId, "spaces": spaceIds, "passwd": password, "sharerRole": userPermission.dataString, "userId": UserData.currentUserId]
        case .batchShareList(let siteId):
            return ["siteId": siteId, "userId": UserData.currentUserId]
        case .revocationBatchShare(let siteId, let batchId):
            return ["siteId": siteId, "token": batchId, "userId": UserData.currentUserId]
        case .joinSpace(let shareId, let password, let permission):
      
            let user: [String: Any] = [
                "userId": UserData.currentUserId,
                "username": UserData.currentUserName
            ]
            return ["token": shareId, "passwd": password ?? "", "roleName": permission.dataString, "user": user]
        case .receiveSite(let shareId, let password):
            
            let user: [String: Any] = [
                "userId": UserData.currentUserId,
                "username": UserData.currentUserName
            ]
            return ["token": shareId, "passwd": password, "user": user]
        case .shareInfo(let shareId):
            return ["token": shareId, "userId": UserData.currentUserId]
        case .spaceMembers(let siteId, let spaceId):
            return ["siteId": siteId, "spaceId": spaceId, "userId": UserData.currentUserId]
        case .clearSpaceMember(let siteId, let spaceId, let userId, let permission, let force):
            
            return ["siteId": siteId, "spaceId": spaceId, "userId": UserData.currentUserId, "reclaimUserId": userId, "roleName": permission.dataString, "force": force]
        case .clearSpaceMembers(let siteId, let spaceId, let userIds, let permission, let force):
            return ["siteId": siteId, "spaceId": spaceId, "userId": UserData.currentUserId, "reclaimUserList": userIds, "roleName": permission.dataString, "force": force]
        case .clearSpacesMembers(let siteId, let spaces, let permission, let force):
            return ["siteId": siteId, "spaces": spaces, "userId": UserData.currentUserId, "roleName": permission.dataString, "force": force]
        case .unbindSpaces(let siteId, let spaceIds, let recycleDeviceAddresses, let recycleGroupAddresses, let recycleSceneAddresses, let exclusions, let provisionerData):
            
            var parameters: [String: Any] = ["siteId": siteId, "spaces": spaceIds, "userId": UserData.currentUserId]
            // 判断是否回收地址
            if recycleDeviceAddresses != nil || recycleGroupAddresses != nil || recycleSceneAddresses != nil {
                var addressDict: [String: [Int]] = [:]
                if let deviceAddresses = recycleDeviceAddresses {
                    addressDict.updateValue(deviceAddresses, forKey: "device")
                }
                if let groupAddresses = recycleGroupAddresses {
                    addressDict.updateValue(groupAddresses, forKey: "group")
                }
                if let sceneAddresses = recycleSceneAddresses {
                    addressDict.updateValue(sceneAddresses, forKey: "scene")
                }
                parameters.updateValue(addressDict, forKey: "addrLists")
            }
            if provisionerData != nil {
                parameters.updateValue(provisionerData!, forKey: "provisioner")
            }
            // 是否回收废弃地址数据
            if let exclusions = exclusions {
                parameters.updateValue(exclusions.map({ ["ivIndex": $0.ivIndex, "addresses": $0.addresses] }), forKey: "exclusions")
            }
            
            return parameters
        case .transferSite(let siteId, let password):
            return ["siteId": siteId, "passwd": password, "userId": UserData.currentUserId]
        case .heartbeat(let siteId, let spaceId, let permission):
            return ["siteId": siteId, "spaceId": spaceId, "userId": UserData.currentUserId, "roleName": permission.dataString]
        case .userInfoSet(let name):
            return ["username": name, "userId": UserData.currentUserId]
        case .applyAddress(let siteId, let type, let number):
            return ["siteId": siteId, "addrType": type.rawValue, "number": number, "userId": UserData.currentUserId]
        case .recyclingAddress(let siteId, let recycleDeviceAddresses, let recycleGroupAddresses, let recycleSceneAddresses, let exclusions, let provisionerData):
            
            var parameters: [String: Any] = ["siteId": siteId, "userId": UserData.currentUserId]
            // 判断是否回收地址
            if recycleDeviceAddresses != nil || recycleGroupAddresses != nil || recycleSceneAddresses != nil {
                var addressDict: [String: [Int]] = [:]
                if let deviceAddresses = recycleDeviceAddresses {
                    addressDict.updateValue(deviceAddresses, forKey: "device")
                }
                if let groupAddresses = recycleGroupAddresses {
                    addressDict.updateValue(groupAddresses, forKey: "group")
                }
                if let sceneAddresses = recycleSceneAddresses {
                    addressDict.updateValue(sceneAddresses, forKey: "scene")
                }
                parameters.updateValue(addressDict, forKey: "addrLists")
            }
            if provisionerData != nil {
                parameters.updateValue(provisionerData!, forKey: "provisioner")
            }
            
            // 是否回收废弃地址数据
            if let exclusions = exclusions {
                parameters.updateValue(exclusions.map({ ["ivIndex": $0.ivIndex, "addresses": $0.addresses] }), forKey: "exclusions")
            }   
            return parameters
        case .spaceActiveMembers(let siteId, let spaceId):
            return ["siteId": siteId, "spaceId": spaceId]
        case .firmwareLatestVersion(let companyId, let deviceType, let customId, let isTesting):
            var parameters = ["manufacturerId": companyId, "deviceType": deviceType, "customerId": customId]
            if isTesting {
                parameters.updateValue("dev", forKey: "profile")
            }
            return parameters
        case .firmwareVersionList(let companyId, let deviceType, let customId, let isTesting):
            var parameters = ["manufacturerId": companyId, "deviceType": deviceType, "customerId": customId]
            if isTesting {
                parameters.updateValue("dev", forKey: "profile")
            }
            return parameters
        case .devicesConfig:
            return nil
        case .simulateFault(let payload):
            return payload.parameters
        case .gatewayList(let siteId):
            return ["siteId": siteId]
        case .gatewayBindSpace(let spaceId, let gatewayId):
            return ["spaceId": spaceId, "gatewayId": gatewayId, "userId": UserData.currentUserId]
        case .gatewayUnbindSpace(let spaceId, let gatewayId):
            return ["spaceId": spaceId, "gatewayId": gatewayId, "userId": UserData.currentUserId]
        case .gatewayUnbindAllSpaces(let gatewayId):
            return ["gatewayId": gatewayId, "userId": UserData.currentUserId]
//        case .gatewayRegister(let gatewayId):
//            return ["gatewayId": gatewayId, "userId": UserData.currentUserId]
        case .gatewayRegister(let siteId, let gatewayId, let nodeId, let node, let updateTimestamp):
            return ["siteId": siteId, "gatewayId": gatewayId, "nodeId": nodeId, "node": node, "updateTimestamp": updateTimestamp, "userId": UserData.currentUserId]
        case .gatewayDelete(let gatewayId):
            return ["gatewayId": gatewayId, "userId": UserData.currentUserId]
        case .gatewayAssociationSpaceList(let siteId, let gatewayId):
            return ["siteId": siteId, "gatewayId": gatewayId]
        case .gatewayDateTimeUpdate(let siteId, let gateways):
            return ["siteId": siteId, "gateways": gateways]
        case .gatewayDateTimeRequestStatus(let requestId):
            return ["requestId": requestId]
        }
    }
    
    var task: Moya.Task {
//        switch self {
//        case .uploadProfile(let data): // 上传头像
//            return .uploadCompositeMultipart([MultipartFormData(provider: .data(data), name: "file")], urlParameters: [:])
//        default:
        guard let requestParameters = parameters else {
            // 无参数
            return .requestPlain
        }
//        switch self {
//        case .siteUpload:
//            fallthrough
//        case .spaceUpload:
//            if let bodyData = try? JSONSerialization.data(withJSONObject: requestParameters), let gzipData = try? bodyData.gzipped() {
//                return .requestCompositeData(bodyData: gzipData, urlParameters: [:])
//            }
//        default:
//            break
//        }
            return .requestParameters(parameters: requestParameters, encoding: JSONEncoding.default)
//        }
    }
    
    var headers: [String : String]? {
        var headers: [String: String] = [:]
        #if Archipelago || SLGSync
        headers.updateValue(appKey, forKey: "appKey")
        headers.updateValue(appSecret, forKey: "appSecret")
        #endif
        switch self {
        case .siteInfo:
            fallthrough
        case .spaceInfo:
            fallthrough
        case .siteUpload:
            fallthrough
        case .spaceUpload:
            headers.updateValue("gzip", forKey: "Content-Encoding")
            headers.updateValue("gzip", forKey: "Accept-Encoding")
        default:
            break
        }
        return headers
    }
    
}


/// 服务器地区
enum ServerRegion {
    
#if Archipelago
    static let defaultRegions: [ServerRegion] = [.northAmerica]
#elseif SylSmart
    static let defaultRegions: [ServerRegion] = [.asiaPacific]
#elseif SLGSync
    static let defaultRegions: [ServerRegion] = [.northAmerica]
#else
    static let defaultRegions: [ServerRegion] = [.chinaMainland, .asiaPacific, .northAmerica, .europe]
#endif
    
    var rawValue: Int {
        switch self {
        case .chinaMainland:
            return 1
        case .northAmerica:
            return 2
        case .europe:
            return 3
        case .asiaPacific:
            return 4
        }
    }
    
    /// 服务器base url
    var baseURL: URL {
        var urlStr = ""
        switch self {
        case .chinaMainland:
            urlStr = "https://www.mericher.com/srv2"
        case .asiaPacific:
            urlStr = "https://sunsmart-ap.mericher.com/srv2"
        case .northAmerica:
            urlStr = "https://sunsmart-us.mericher.com/srv2"
        case .europe:
            urlStr = "https://sunsmart-eu.mericher.com/srv2"
        }
        return URL(string: urlStr)!
    }
    
    var data: (icon: String, name: String) {
        switch self {
        case .chinaMainland:
            return ("china_map", "china_mainland".localizedString)
        case .asiaPacific:
            return ("asia_pacific_map", "asia_pacific".localizedString)
        case .northAmerica:
            return ("north_america_map", "north_america".localizedString)
        case .europe:
            return ("europe_map", "europe".localizedString)
        }
    }
    
    init?(rawValue: Int) {
        switch rawValue {
        case 1:
            self = .chinaMainland
        case 2:
            self = .northAmerica
        case 3:
            self = .europe
        case 4:
            self = .asiaPacific
        default:
            return nil
        }
    }
    
    init?(regionCode: String?) {
        guard let code = regionCode else {
            return nil
        }
        
        if String.isChinaMainland(regionCode: code) {
            self = .chinaMainland
        }else if String.isNorthAmerica(regionCode: code) {
            self = .northAmerica
        }else if String.isEurope(regionCode: code) {
            self = .europe
        }else if  String.isAsiaPacific(regionCode: code) {
            self = .asiaPacific
        }else {
            return nil
        }
    }
    
    /// 中国大陆
    case chinaMainland
    /// 亚太
    case asiaPacific
    /// 北美
    case northAmerica
    /// 欧洲
    case europe
}
