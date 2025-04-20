//
//  DeviceGroupsSelectData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/12.
//

import Foundation
import NordicSigMeshSDK

class DeviceGroupsSelectData {
    
    /// 组名称
    var name: String = ""
    /// 组地址
    var groupAddress: Address
    /// 包含设备
    var addresss: [Address] = []
    /// 是否选中
    var isSelected: Bool = false
    
    
    init(name: String, groupAddress: Address, addresss: [Address], isSelected: Bool) {
        self.name = name
        self.groupAddress = groupAddress
        self.addresss = addresss
        self.isSelected = isSelected
    }
}
