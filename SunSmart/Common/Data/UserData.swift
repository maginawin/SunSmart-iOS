//
//  UserData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/31.
//

import Foundation

class UserData {
    
    /// 名称
    let name: String
    /// uuid
    let uuid: String
    
    init(name: String, uuid: String) {
        self.name = name
        self.uuid = uuid
    }
}

extension UserData {
    
    private static var regionKey = 1
    /// 当前用户id
    static let currentUserId = Keychain.getUUID()
    /// 当前用户名称
    static let currentUserName = UIDevice.current.name
    
    /// 当前服务器分区
    static var currentServerRegion: ServerRegion {
        get {
            guard let region = objc_getAssociatedObject(self, &regionKey) as? ServerRegion else {
                self.currentServerRegion = Keychain.getServerRegion() ?? .northAmerica
                return self.currentServerRegion
            }
            return region
        }set {
            Keychain.saveServerRegion(newValue)
            objc_setAssociatedObject(self, &regionKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    
}
