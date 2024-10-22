//
//  Keychain.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/23.
//

import Foundation
import Security

struct Keychain {
    
    
    private static let service = Bundle.main.bundleIdentifier ?? "com.azoula.sunsmart"
    private static let account = "uuid"
    private static let username = "username"
    private static let serverRegion = "region"
    private static let lastVendorIdentifier = "lastVendorIdentifier"
    
    /// 获取uuid
    static func getUUID() -> String {
        
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassGenericPassword,
//            kSecAttrService as String: service,
//            kSecAttrAccount as String: account,
//            kSecReturnData as String: kCFBooleanTrue!,
//            kSecMatchLimit as String: kSecMatchLimitOne
//        ]
//        
//        var dataTypeRef: AnyObject?
//        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
//        
//        if status == errSecSuccess {
//            if let data = dataTypeRef as? Data,
//                let retrievedUUID = String(data: data, encoding: .utf8) {
//                return retrievedUUID
//            }
//        }
//        
        guard let data = getData(key: account), let retrievedUUID = String(data: data, encoding: .utf8) else {
            // 钥匙串没有缓存，则创建一个uuid并缓存到钥匙串
            let uuid = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            guard saveUUID(uuid) else {
                return ""
            }
            return uuid
        }
        return retrievedUUID
    }
    
    /// 保存uuid到钥匙串
    private static func saveUUID(_ uuid: String) -> Bool {
        guard let data = uuid.data(using: .utf8) else {
            return false
        }
        return saveData(key: account, data: data)
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassGenericPassword,
//            kSecAttrService as String: service,
//            kSecAttrAccount as String: account,
//            kSecValueData as String: data,
//            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
//        ]
//        
//        SecItemDelete(query as CFDictionary) // 删除已有的UUID，以确保只有一个
//        
//        let status = SecItemAdd(query as CFDictionary, nil)
//        return status == errSecSuccess
    }
    
    /// 获取最后使用的APP VendorIdentifier
    static func getLastVendorIdentifier() -> String? {
        guard let data = getData(key: lastVendorIdentifier), let vendorIdentifier = String(data: data, encoding: .utf8) else {
            return nil
        }
        return vendorIdentifier
    }
    
    /// 设置最后使用的APP VendorIdentifier
    static func saveLastVendorIdentifier(vendorIdentifier: String = UIDevice.current.identifierForVendor?.uuidString ?? getUUID()) -> Bool {
        guard let data = vendorIdentifier.data(using: .utf8) else {
            return false
        }
        return saveData(key: lastVendorIdentifier, data: data)
    }
    
    /// 获取服务器地区
    static func getServerRegion() -> ServerRegion? {
        
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassGenericPassword,
//            kSecAttrService as String: service,
//            kSecAttrType as String: serverRegion,
//            kSecReturnData as String: kCFBooleanTrue!,
//            kSecMatchLimit as String: kSecMatchLimitOne
//        ]
//        
//        var dataTypeRef: AnyObject?
//        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
//        
//        if status == errSecSuccess {
//            if let data = dataTypeRef as? Data,
//               let region = ServerRegion(rawValue: Int(UInt8(data: data))) {
//                return region
//            }
//        }
        
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassGenericPassword,
//            kSecAttrService as String: service,
//            kSecAttrAccount as String: serverRegion,
//            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
//        ]
//        SecItemDelete(query as CFDictionary)
        
        guard let data = getData(key: serverRegion), let region = ServerRegion(rawValue: Int(UInt8(data: data))) else { return nil }
        return region
    }
    
    /// 保存服务器地区到钥匙串
   @discardableResult static func saveServerRegion(_ region: ServerRegion) -> Bool {
      
       saveData(key: serverRegion, data: UInt8(region.rawValue).data)
    
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassGenericPassword,
//            kSecAttrService as String: service,
//            kSecAttrType as String: serverRegion,
//            kSecValueData as String: UInt8(region.rawValue).data,
//            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
//        ]
//        
//        SecItemDelete(query as CFDictionary) // 删除已有的地区，以确保只有一个
//        let status = SecItemAdd(query as CFDictionary, nil)
//        return status == errSecSuccess
    }
    
    /// 获取用户名称
    static func getUserName() -> String? {
        guard let data = getData(key: username), let name = String(data: data, encoding: .utf8) else {
            return nil
        }
        return name
    }
    
    /// 保存用户名称
    @discardableResult static func saveUserName(_ name: String) -> Bool {
        guard let data = name.data(using: .utf8) else {
            return false
        }
        return saveData(key: username, data: data)
    }
    
    /// 根据key读取钥匙串数据
    /// - Parameter key: 键名
    /// - Returns: data
    private static func getData(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        return dataTypeRef as? Data
    }
    
    
    /// 保存钥匙串数据
    /// - Parameters:
    ///   - key: 键名
    ///   - data: 数据
    /// - Returns: 是否成功
    private static func saveData(key: String, data: Data) -> Bool {
//        guard let data = uuid.data(using: .utf8) else {
//            return false
//        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    
    
}
