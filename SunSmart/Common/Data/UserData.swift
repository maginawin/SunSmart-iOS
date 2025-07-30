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
    private static var userNameKey = 2
    
    private static let isTermsOfServiceKey = "isTermsOfService"
    private static let lastVendorIdentifier = "lastVendorIdentifier"
    
    /// 当前用户id
    static let currentUserId = Keychain.getUUID()
    /// 是否重装APP
    static var isReinstallation: Bool {
        // 1. 钥匙串缓存的uuid
        let keychainExists = Keychain.getLastVendorIdentifier() != nil
        // 2. 检查 UserDefaults
        let defaults = UserDefaults.standard
        let defaultsExists = defaults.bool(forKey: UserData.lastVendorIdentifier)
        
        // 钥匙串有数据但 UserDefaults 无标记 卸载 → 重装
        if keychainExists && !defaultsExists {
            defaults.set(true, forKey: UserData.lastVendorIdentifier)
            defaults.synchronize()
            return true
        } else if !keychainExists { // 首次安装
            _ = Keychain.saveLastVendorIdentifier()
            defaults.set(true, forKey: UserData.lastVendorIdentifier)
            defaults.synchronize()
        }
        return false // 非重装
    }
    
    /// 是否同意使用协议
    static var isTermsOfService: Bool {
        get {
            return UserDefaults.standard.bool(forKey: isTermsOfServiceKey) 
        }set {
            UserDefaults.standard.set(newValue, forKey: isTermsOfServiceKey)
            UserDefaults.standard.synchronize()
        }
    }
    
//    currentUserId != UIDevice.current.identifierForVendor?.uuidString
    
    /// 当前用户名称
    static var currentUserName: String {
        get {
            var name = objc_getAssociatedObject(self, &userNameKey) as? String
            if name == nil {
                // 读取钥匙串缓存
                if let cacheName = Keychain.getUserName() {
                    name = cacheName
                }else {
                    // 未读取到缓存
                    // iOS16及以上读取不到设备名称，则设备型号+随机4位数生成设备名称
                    if #available(iOS 16.0, *) {
                        name = "\(UIDevice.current.modelName)_\(String.generateRandomNumberString(length: 4))"
                    }else {
                        name = UIDevice.current.name
                    }
                }
                // 缓存到钥匙串
                Keychain.saveUserName(name!)
            }
            return name ?? ""
        }set {
            Keychain.saveUserName(newValue)
            objc_setAssociatedObject(self, &userNameKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 当前服务器分区
    static var currentServerRegion: ServerRegion {
        get {
            guard let region = objc_getAssociatedObject(self, &regionKey) as? ServerRegion else {
                let currentServerRegion = Keychain.getServerRegion() ?? .northAmerica
                return currentServerRegion
            }
            return region
        }set {
            Keychain.saveServerRegion(newValue)
            objc_setAssociatedObject(self, &regionKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    
}
