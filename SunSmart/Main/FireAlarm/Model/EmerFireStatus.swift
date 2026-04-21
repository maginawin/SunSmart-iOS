//
//  EmerFireStatus.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import Foundation

enum EmerFireStatus: Int, CaseIterable {
    case onlineBoundDevice          // 在线，已绑定设备
    case offlineBoundDevice         // 离线，已绑定设备
    case unboundDevice              // 未绑定设备
    case syncIssueDevice            // 有同步问题设备
    case repairRequiredDevice       // 有修复问题设备
    case gatewayUnassignedWarning   // 警告：未绑定网关，仅 linked 后展示
}
