//
//  ProvisioningDevice+Add.swift
//  HomeeMesh
//
//  Created by 袁科鸿 on 2023/1/4.
//

import Foundation
import NordicSigMeshSDK

extension ProvisioningDevice {
    
    private struct AssociatedKey {
        static var addStateKey: String = "addState"
        static var selectedStateKey: String = "selectedState"
        static var startAddDateKey: String = "startAddDate"
        static var addProgressKey: String = "addProgress"
    }
    
    /// 设备选中状态
    enum DeviceSelectedState {
        /// 未选中
        case unselected
        /// 选中
        case selected
        /// 不可选
        case disabled
    }
    
    /// 设备添加状态
    enum DeviceAddState {
        /// 无
        case none
        /// 扫描中
        case scaning
        /// 等待添加
        case wait
        /// identify连接中
        case identifyConnecting
        /// identify等待
        case identifyWait
        /// identify中
        case identifying
        /// identify失败
        case identifyFail
        /// 添加设备连接中
        case addConnecting
        /// 添加中（provisioning+keybind）
        case adding
        /// 添加成功
        case success
        /// 添加失败
        case failed
    }
    
    /// 设备添加状态
    var selectedState: DeviceSelectedState {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.selectedStateKey) as? DeviceSelectedState ?? .unselected
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKey.selectedStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 设备添加状态
    var addState: DeviceAddState {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.addStateKey) as? DeviceAddState ?? .none
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKey.addStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 开始添加的时间
    var startAddDate: Date? {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.startAddDateKey) as? Date
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKey.startAddDateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 超时时长（暂时写死 120s）
    private var timeoutDuration: Int {
        get {
            return 120
        }
    }
    
    /// 添加进度 0.0~1.0
    var addProgress: Float {
        get {
            // 开始添加设备
            guard let startDate = self.startAddDate else { return 0 }
            // （当前时间-开始添加时间）/ 超时时长
            let progress = Float(Date().timeIntervalSince1970 - startDate.timeIntervalSince1970) / Float(timeoutDuration)
            return min(progress, 1)
        }
    }
  
}

extension PBGattBearer {
    
    /// 获取identify数据
    /// - Parameter attentionTimer: identify时间（s）
    /// - Returns: identify数据
    func identify(andAttractFor attentionTimer: UInt8 = 5) {
        let data = Data([0x00, attentionTimer])
        try? send(data, ofType: .provisioningPdu)
    }
    
}
