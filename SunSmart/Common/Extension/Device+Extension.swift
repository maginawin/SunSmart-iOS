//
//  Device+Extension.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/7/8.
//

import Foundation

public extension UIDevice {
    
    /// 设备型号名称
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        switch identifier {
        case "iPod9,1":                                 return "iPod touch"
        case "iPhone8,1":                               return "iPhone 6s"
        case "iPhone8,2":                               return "iPhone 6s Plus"
        case "iPhone9,1", "iPhone9,3":                  return "iPhone 7"
        case "iPhone9,2", "iPhone9,4":                  return "iPhone 7 Plus"
        case "iPhone10,1", "iPhone10,4":                return "iPhone 8"
        case "iPhone10,2", "iPhone10,5":                return "iPhone 8 Plus"
        case "iPhone10,3", "iPhone10,6":                return "iPhone X"
        case "iPhone11,2":                              return "iPhone XS"
        case "iPhone11,4", "iPhone11,6":                return "iPhone XS Max"
        case "iPhone11,8":                              return "iPhone XR"
        case "iPhone12,1":                              return "iPhone 11"
        case "iPhone12,3":                              return "iPhone 11 Pro"
        case "iPhone12,5":                              return "iPhone 11 Pro Max"
        case "iPhone12,8":                              return "iPhone SE 2"
        case "iPhone13,1":                              return "iPhone 12 mini"
        case "iPhone13,2":                              return "iPhone 12"
        case "iPhone13,3":                              return "iPhone 12 Pro"
        case "iPhone13,4":                              return "iPhone 12 Pro Max"
        case "iPhone14,4":                              return "iPhone 13 mini"
        case "iPhone14,5":                              return "iPhone 13"
        case "iPhone14,2":                              return "iPhone 13 Pro"
        case "iPhone14,3":                              return "iPhone 13 Pro Max"
        case "iPhone14,6":                              return "iPhone SE 3"
        case "iPhone15,2":                              return "iPhone 14 Pro"
        case "iPhone15,3":                              return "iPhone 14 Pro Max"
        case "iPhone14,7":                              return "iPhone 14"
        case "iPhone14,8":                              return "iPhone 14 Plus"
        case "iPhone15,4":                              return "iPhone 15"
        case "iPhone15,5":                              return "iPhone 15 Plus"
        case "iPhone16,1":                              return "iPhone 15 Pro"
        case "iPhone16,2":                              return "iPhone 15 Pro Max"
        case "iPhone17,1":                              return "iPhone 16 Pro"
        case "iPhone17,2":                              return "iPhone 16 Pro Max"
        case "iPhone17,3":                              return "iPhone 16"
        case "iPhone17,4":                              return "iPhone 16 Plus"
        case "iPhone17,5":                              return "iPhone 16e"
        case "iPhone18,1":                              return "iPhone 17 Pro"
        case "iPhone18,2":                              return "iPhone 17 Pro Max"
        case "iPhone18,3":                              return "iPhone 17"
        case "iPhone18,4":                              return "iPhone 17 Air"
        case "iPhone18,5":                              return "iPhone 17e"
            
        case "iPad6,11", "iPad6,12":                    return "iPad 5"
        case "iPad7,5", "iPad7,6":                      return "iPad 6"
        case "iPad7,11", "iPad7,12":                    return "iPad 7"
        case "iPad11,6", "iPad11,7":                    return "iPad 8"
        case "iPad12,1", "iPad12,2":                    return "iPad 9"
        case "iPad13,18", "iPad13,19":                  return "iPad 10"
        case "iPad15,7", "iPad15,8":                    return "iPad (A16)"
        case "iPad4,1", "iPad4,2", "iPad4,3":           return "iPad Air"
        case "iPad5,3", "iPad5,4":                      return "iPad Air 2"
        case "iPad11,3", "iPad11,4":                    return "iPad Air 3"
        case "iPad13,1", "iPad13,2":                    return "iPad Air 4"
        case "iPad13,16", "iPad13,17":                  return "iPad Air 5"
        case "iPad2,5", "iPad2,6", "iPad2,7":           return "iPad mini"
        case "iPad4,4", "iPad4,5", "iPad4,6":           return "iPad mini 2"
        case "iPad4,7", "iPad4,8", "iPad4,9":           return "iPad mini 3"
        case "iPad5,1", "iPad5,2":                      return "iPad mini 4"
        case "iPad11,1", "iPad11,2":                    return "iPad mini 5"
        case "iPad14,1", "iPad14,2":                    return "iPad mini 6"
        case "iPad6,3", "iPad6,4":                      return "iPad Pro"
        case "iPad6,7", "iPad6,8":                      return "iPad Pro"
        case "iPad7,1", "iPad7,2":                      return "iPad Pro 2"
        case "iPad7,3", "iPad7,4":                      return "iPad Pro"
        case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4":return "iPad Pro"
        case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8":return "iPad Pro 3"
        case "iPad8,9", "iPad8,10":                     return "iPad Pro 2"
        case "iPad8,11", "iPad8,12":                    return "iPad Pro 4"
        case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7":
                                                        return "iPad Pro 3"
        case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11":
                                                        return "iPad Pro 5"
        case "iPad14,3", "iPad14,4":                    return "iPad Pro 4"
        case "iPad14,5", "iPad14,6":                    return "iPad Pro 6"
        case "iPad14,8", "iPad14,9":                    return "iPad Air 6"
        case "iPad15,3", "iPad15,4", "iPad15,5", "iPad15,6": return "iPad Air M3"
        case "iPad14,10", "iPad14,11":                  return "iPad Air 7"
        case "iPad16,8", "iPad16,9", "iPad16,10", "iPad16,11":
                                                        return "iPad Air M4"
        case "iPad16,1", "iPad16,2":                    return "iPad mini 7"
        case "iPad16,3", "iPad16,4":                    return "iPad Pro 5"
        case "iPad16,5", "iPad16,6":                    return "iPad Pro 7"
            
        default:                                        return identifier
        }
    }
}
