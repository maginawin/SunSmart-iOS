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
        static var addStateKey: UInt8 = 0
        static var selectedStateKey: UInt8 = 0
        static var startAddDateKey: UInt8 = 0
        static var addProgressKey: UInt8 = 0
        static var elementCountKey: UInt8 = 0
//        static var isSupportKey = 6
        static var iconKey: UInt8 = 0
        static var deviceType: UInt8 = 0
        static var activityDate: UInt8 = 0
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
        /// 同步失败
        case syncFailed
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
    
    /// 元素地址数量
    var elementCount: Int {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.elementCountKey) as? Int ?? 1
        }set {
            objc_setAssociatedObject(self, &AssociatedKey.elementCountKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 是否支持设备
//    var isSupport: Bool {
//        get {
//            objc_getAssociatedObject(self, &AssociatedKey.isSupportKey) as? Bool ?? false
//        }set {
//            objc_setAssociatedObject(self, &AssociatedKey.isSupportKey, newValue, .OBJC_ASSOCIATION_RETAIN)
//        }
//    }
    
    /// 图标
    var icon: String? {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.iconKey) as? String
        }set {
            objc_setAssociatedObject(self, &AssociatedKey.iconKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 设备类型
    var deviceType: Node.DeviceType {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.deviceType) as? Node.DeviceType ?? .unknown
        }set {
            objc_setAssociatedObject(self, &AssociatedKey.deviceType, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var isBatteryPowerSwitch: Bool {
        return Node.isBatteryPowerSwitch(companyIdentifier: cid, productIdentifier: pid)
    }

    var powerSwitchKind: PJEightKeyPowerSwitchKind? {
        return PJEightKeyPowerSwitchKind.make(companyIdentifier: cid, productIdentifier: pid)
    }

    var powerSwitchPanelType: PJEightKeySwitchPanelDefinition.PanelType? {
        return PJEightKeyPowerSwitchKind.panelType(productIdentifier: pid)
    }

    var isACPowerSwitch: Bool {
        return powerSwitchKind == .ac
    }

    var isPowerSwitch: Bool {
        return powerSwitchKind != nil
    }
    
    /// 设备触发时间（触感器感应等）
    var activityDate: Date? {
        get {
            objc_getAssociatedObject(self, &AssociatedKey.activityDate) as? Date
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKey.activityDate, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 设备是否触发中（1.5s内）
    var isActivitying: Bool {
        guard let activityDate = self.activityDate else {
            return false
        }
        return Date().distance(to: activityDate) < 1.5
    }
    
    /// 更新数据 rssi/触发类型（适用于搜索到重复设备时）
    func updateData(device: ProvisioningDevice) {
        if device.triggerActionTypes.count > 0 {
            self.triggerActionTypes = device.triggerActionTypes
            self.activityDate = device.activityDate
        } else if !self.isActivitying {
            self.triggerActionTypes.removeAll()
            self.activityDate = nil
        }
        self.rssi = device.rssi
        self.deviceName = device.deviceName
        self.elementCount = self.elementCount
        self.icon = device.icon
        self.deviceType = device.deviceType
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
