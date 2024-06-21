//
//  Keychain.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/23.
//

import Foundation
import Security

struct Keychain {
    
    private static let service = "com.azoula.sunsmart.app"
    private static let account = "uuid"
    private static let serverRegion = "region"
    
    /// 获取uuid
    static func getUUID() -> String {
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let data = dataTypeRef as? Data,
                let retrievedUUID = String(data: data, encoding: .utf8) {
                return retrievedUUID
            }
        }
        // 钥匙串没有缓存，则创建一个uuid并缓存到钥匙串
        let uuid = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        guard saveUUID(uuid) else {
            return ""
        }
        return uuid
    }
    
    /// 保存uuid到钥匙串
    private static func saveUUID(_ uuid: String) -> Bool {
        guard let data = uuid.data(using: .utf8) else {
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary) // 删除已有的UUID，以确保只有一个
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// 获取服务器地区
    static func getServerRegion() -> ServerRegion? {
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrType as String: serverRegion,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let data = dataTypeRef as? Data,
               let region = ServerRegion(rawValue: Int(UInt8(data: data))) {
                return region
            }
        }
        return nil
    }
    
    /// 保存服务器地区到钥匙串
   @discardableResult static func saveServerRegion(_ region: ServerRegion) -> Bool {
       
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrType as String: serverRegion,
            kSecValueData as String: UInt8(region.rawValue).data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary) // 删除已有的地区，以确保只有一个
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
   
    
}
