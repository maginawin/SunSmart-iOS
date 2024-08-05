//
//  ExternalVendorMessage+Extension.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/27.
//

import Foundation
import NordicSigMeshSDK

extension ExternalVendorMessage {
    
    /// 自定义操作code
    enum OperationCode: UInt8 {
        case userPermission = 0x01
    }
    
    /// 自定义操作
    enum Operation {
        
        /// 自定义操作data
        var data: Data {
            switch self {
            case .userPermission(let event):
                return Data() + OperationCode.userPermission.rawValue + event.type + event.data
            }
        }
        
        // 用户授权  event：事件类型
        case userPermission(_ event: UserPermission)
        
        /// data转自定义操作
        internal init?(data: Data) {
            guard data.count >= 2 else {
                return nil
            }
            // 操作类型
            let mainType: UInt8 = data.read(fromOffset: 0)
            // 子类型
            let subType: UInt8 = data.read(fromOffset: 1)
            
            switch mainType {
            case OperationCode.userPermission.rawValue:
                switch subType {
                case UserPermission.Code.ask.rawValue:
                    self = .userPermission(.ask)
                case UserPermission.Code.reply.rawValue:
                    let permissionType: UInt8 = data.read(fromOffset: 2)
                    guard let permission = Permission(rawValue: Int(permissionType)) else {
                        return nil
                    }
                    self = .userPermission(.reply(permission: permission))
                default:
                    return nil
                }
            default:
                return nil
            }
        }
        
    }
    
    
    /// 用户权限
    enum UserPermission {
      
        enum Code: UInt8 {
            case ask = 0x01
            case reply = 0x02
        }
        
        /// 类型
        var type: UInt8 {
            switch self {
            case .ask:
                return Code.ask.rawValue
            case .reply:
                return Code.reply.rawValue
            }
        }
        
        var data: Data {
            switch self {
            case .ask:
                return Data()
            case .reply(let permission):
                return Data([UInt8(permission.rawValue)])
            }
        }
        
        /// 询问他人权限
        case ask
        /// 回复自己的权限
        case reply(permission: Permission)
    }
    
//    static var operationKey = 1
    
//    var operation: Operation? {
//        get {
//            objc_getAssociatedObject(self, &ExternalVendorMessage.operationKey) as? Operation
//        }set {
//            objc_setAssociatedObject(self, &ExternalVendorMessage.operationKey, newValue, .OBJC_ASSOCIATION_RETAIN)
//        }
//    }
    
    /// 初始化自定义操作
    init(operation: Operation) {
        self.init(parameters: operation.data)!
    }
    
    /// 解析自定义操作数据
    func unmarshal() -> Operation? {
        guard let data = self.parameters else { return nil }
        return Operation(data: data)
    }
    
//    public init?(parameters: Data) {
//        
//        self.parameters = parameters
//    }
    

    
}

