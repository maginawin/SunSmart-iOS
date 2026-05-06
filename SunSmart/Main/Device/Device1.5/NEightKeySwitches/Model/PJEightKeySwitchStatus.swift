//
//  PJEightKeySwitchStatus.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation

enum PJEightKeySwitchStatus: Int, CaseIterable {
    case boundEnabled           // 绑定了开关，且启用
    case boundDisabled          // 绑定了开关，且禁用
    case unboundEnabled         // 没绑定开关，且启用
    case syncIssueBoundSwitch   // 绑定的开关有同步问题
    case repairRequiredMode     // 添加的开关绑定 mode 有问题，需要修复
    case unboundDisabled        // 没绑定开关，且禁用

    /// 预留状态图标资源名，资源到位后直接替换即可。
    var iconAssetName: String {
        switch self {
        case .boundEnabled:
            return "eight_key_switch_bound_enabled"
        case .boundDisabled:
            return "eight_key_switch_bound_enabled"
        case .unboundEnabled:
            return "eight_key_switch_bound_enabled"
        case .syncIssueBoundSwitch:
            return "eight_key_switch_sync_issue"
        case .repairRequiredMode:
            return "eight_key_switch_repair_required"
        case .unboundDisabled:
            return "eight_key_switch_bound_enabled"
        }
    }

    var needsDashedBorder: Bool {
        switch self {
        case .unboundEnabled, .unboundDisabled:
            return true
        default:
            return false
        }
    }

    var needsDimmedBackground: Bool {
        switch self {
        case .boundDisabled, .unboundDisabled:
            return true
        default:
            return false
        }
    }
}
