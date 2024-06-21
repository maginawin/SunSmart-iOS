//
//  NetowrkReqeustApi.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/28.
//

import Foundation
import Moya


enum NetowrkReqeustApi {
    /// 获取用户site list
    case sites
    /// 获取site信息
    case siteInfo(siteId: String)
    /// 添加site
    case siteAdd(siteData: [String: Any])
    /// 更新/提交site数据
    case siteUpload(siteData: [String: Any])
    /// 删除site
    case siteDelete(siteId: String)
    /// 获取space信息  password: editor/visitor权限进入space密码
    case spaceInfo(siteId: String, spaceId: String, password: String)
    /// 添加space
//    case spaceAdd(space: SpaceData)
    /// 添加spaces
//    case spacesAdd(siteId: String, spaceDatas: [[String: Any]])
    /// 更新/提交space数据
    case spaceUpload(siteId: String, spaceData: [String: Any])
    /// 删除space
    case spaceDelete(siteId: String, spaceId: String)
    
}

extension NetowrkReqeustApi: TargetType {
    
    var baseURL: URL {
        return URL(string: "https://www.mericher.com/srv2")!
//        return URL(string: "https://bq23298lvb.execute-api.ap-northeast-1.amazonaws.com/dev")!
    }
    
    var path: String {
        switch self {
        case .sites:
            return "/sitespace/get/sitelist"
        case .siteInfo:
            return "/sitespace/get/siteprops"
        case .siteUpload, .siteAdd:
            return "/sitespace/sync/siteprops"
        case .siteDelete:
            return "/sitespace/del/site"
        case .spaceInfo:
            return "/sitespace/get/spaceprops"
        case .spaceUpload:
            return "/sitespace/sync/spaceprops"
        case .spaceDelete:
            return "/sitespace/del/space"
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
    
    var parameter: [String: Any]? {
        
       
        
        switch self {
        case .sites:
            return ["userId": UserData.currentUserId]
        case .siteInfo(let siteId):
            return ["siteId": siteId, "userId": UserData.currentUserId]
        case .siteAdd(let siteData):
            fallthrough
        case .siteUpload(let siteData):
            
            let user: [String: Any] = [
                "userId": UserData.currentUserId,
                "username": UserData.currentUserName
            ]
            return ["site": siteData, "user": user]
        case .siteDelete(let siteId):
            return ["siteId": siteId, "userId": UserData.currentUserId]
        case .spaceInfo(let siteId, let spaceId, let password):
            return ["siteId": siteId, "spaceId": spaceId, "passwd": password, "userId": UserData.currentUserId]
//        case .spacesAdd(let siteId, let spaceDatas):
//            let spaceDatas = spaces.map({ $0.export() })
//            return ["siteId": siteId, "spaces": spaceDatas, "user": user]
        case .spaceUpload(let siteId, let spaceDatas):
            return ["siteId": siteId, "spaces": [spaceDatas], "userId": UserData.currentUserId]
        case .spaceDelete(let siteId, let spaceId):
            return ["siteId": siteId, "spaceId": spaceId, "userId": UserData.currentUserId]
        }
    }
    
    var task: Moya.Task {
//        switch self {
//        case .uploadProfile(let data): // 上传头像
//            return .uploadCompositeMultipart([MultipartFormData(provider: .data(data), name: "file")], urlParameters: [:])
//        default:
            // 无参数
            if parameter?.isEmpty ?? true {
                return Task.requestPlain
            }
            return .requestParameters(parameters: parameter!, encoding: JSONEncoding.default)
//        }
    }
    
    var headers: [String : String]? {
//        if let token = getHeader() {
//            return ["Authorization": token]
//        }
        return nil
    }
    
}
