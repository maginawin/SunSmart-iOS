//
//  LinkedEmerFireConfig.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

/// 应急火警控制器的业务工作模式。
/// 这里的枚举是 App 本地语义，真正下发到设备时会映射成 vendor 协议里的 EmergencyControllerMode。
enum EmergencyFireControllerWorkMode: String, Codable, Equatable {
    case powerLossEmergency
    case fireAlarmEmergency
    case allDisabled

    var vendorMode: EmergencyControllerMode {
        switch self {
        case .powerLossEmergency:
            return .emergency
        case .fireAlarmEmergency:
            return .fire
        case .allDisabled:
            return .disabled
        }
    }
}

/// 单个应急模式下的配置。
/// power loss 和 fire alarm 两套配置共用这个结构，切换模式时只会激活当前 workMode 对应的一套。
struct EmergencyFireControllerModeSettings: Codable, Equatable {
    /// 当前模式希望联动的灯组地址。同步时会让组内灯订阅 EFC 的内部 publish group。
    var associateGroupAddresses: [UInt16]
    /// 触发时要写入保留场景的亮度百分比。
    var triggerBrightness: Int
    /// EFC 触发命令重发参数，最终通过 vendor message 下发给控制器。
    var triggerIntervalSeconds: UInt16
    var triggerCount: UInt16
    /// EFC 停止/恢复命令重发参数。
    var stopIntervalSeconds: UInt16
    var stopCount: UInt16
    /// 设备从 emergency/fire active 恢复到 normal UI 状态前等待的秒数。
    var restoreDelaySeconds: UInt8
    /// 已从配置里移除、但灯节点还需要取消订阅内部 publish group 的组。
    /// 这个字段不能随意清空，否则旧灯组会残留订阅，后续仍可能被 EFC 控制。
    var pendingUnassociateGroupAddresses: [UInt16]

    private enum CodingKeys: String, CodingKey {
        case associateGroupAddresses
        case triggerBrightness
        case triggerIntervalSeconds
        case triggerCount
        case stopIntervalSeconds
        case stopCount
        case restoreDelaySeconds
        case pendingUnassociateGroupAddresses
    }

    static let defaultValue = EmergencyFireControllerModeSettings(
        associateGroupAddresses: [],
        triggerBrightness: 100,
        triggerIntervalSeconds: 5,
        triggerCount: 0xFFFF,
        stopIntervalSeconds: 5,
        stopCount: 2,
        restoreDelaySeconds: 2,
        pendingUnassociateGroupAddresses: []
    )

    init(
        associateGroupAddresses: [UInt16],
        triggerBrightness: Int,
        triggerIntervalSeconds: UInt16,
        triggerCount: UInt16,
        stopIntervalSeconds: UInt16,
        stopCount: UInt16,
        restoreDelaySeconds: UInt8,
        pendingUnassociateGroupAddresses: [UInt16]
    ) {
        self.associateGroupAddresses = associateGroupAddresses
        self.triggerBrightness = triggerBrightness
        self.triggerIntervalSeconds = triggerIntervalSeconds
        self.triggerCount = triggerCount
        self.stopIntervalSeconds = stopIntervalSeconds
        self.stopCount = stopCount
        self.restoreDelaySeconds = restoreDelaySeconds
        self.pendingUnassociateGroupAddresses = pendingUnassociateGroupAddresses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaultValue
        associateGroupAddresses = try container.decodeIfPresent([UInt16].self, forKey: .associateGroupAddresses) ?? defaults.associateGroupAddresses
        triggerBrightness = try container.decodeIfPresent(Int.self, forKey: .triggerBrightness) ?? defaults.triggerBrightness
        triggerIntervalSeconds = try container.decodeIfPresent(UInt16.self, forKey: .triggerIntervalSeconds) ?? defaults.triggerIntervalSeconds
        triggerCount = try container.decodeIfPresent(UInt16.self, forKey: .triggerCount) ?? defaults.triggerCount
        stopIntervalSeconds = try container.decodeIfPresent(UInt16.self, forKey: .stopIntervalSeconds) ?? defaults.stopIntervalSeconds
        stopCount = try container.decodeIfPresent(UInt16.self, forKey: .stopCount) ?? defaults.stopCount
        restoreDelaySeconds = try container.decodeIfPresent(UInt8.self, forKey: .restoreDelaySeconds) ?? defaults.restoreDelaySeconds
        pendingUnassociateGroupAddresses = try container.decodeIfPresent([UInt16].self, forKey: .pendingUnassociateGroupAddresses) ?? []
    }
}

/// EFC 的 desired configuration。
/// 数据库存的是这份配置，真实 Mesh 设备是否已经对齐要看 isSynced 和同步流程结果。
struct EmergencyFireControllerConfiguration: Codable, Equatable {
    var workMode: EmergencyFireControllerWorkMode
    var powerLossSettings: EmergencyFireControllerModeSettings
    var fireAlarmSettings: EmergencyFireControllerModeSettings

    static let defaultValue = EmergencyFireControllerConfiguration(
        workMode: .powerLossEmergency,
        powerLossSettings: .defaultValue,
        fireAlarmSettings: .defaultValue
    )
}

extension EmergencyFireControllerConfiguration {

    /// 当前激活模式下真正应该被 EFC 控制的灯组。
    /// allDisabled 时返回空，但 pending cleanup 仍然可能存在，不能因此跳过清理。
    var activeLightLCGroupAddresses: Set<Address> {
        switch workMode {
        case .powerLossEmergency:
            return Set(powerLossSettings.associateGroupAddresses)
        case .fireAlarmEmergency:
            return Set(fireAlarmSettings.associateGroupAddresses)
        case .allDisabled:
            return []
        }
    }

    /// 是否还有待清理订阅。用于删除、导入、同步态判断。
    var hasPendingCleanup: Bool {
        !powerLossSettings.pendingUnassociateGroupAddresses.isEmpty ||
        !fireAlarmSettings.pendingUnassociateGroupAddresses.isEmpty
    }

    /// 导入后重新判断同步态使用的业务意图。
    /// 不要盲信外部 JSON 的 isSynced；只要还有绑定、publish group 或配置意图，就应该让同步流程重新对齐。
    var hasSyncIntent: Bool {
        workMode != .allDisabled ||
        !activeLightLCGroupAddresses.isEmpty ||
        hasPendingCleanup
    }
}

/// 编辑页和监控页之间传递的轻量配置快照。
/// 它不是数据库实体，保存时需要回写到 DeviceEmerFireData。
struct LinkedEmerFireConfig: Equatable {
    var deviceId: String?
    var spaceId: String?
    var meshUUID: String?
    var meshNetworkId: String?
    var deviceName: String
    var isSynced: Bool
    var reportToGateway: Bool
    var publishGroupAddress: Address?
    var configuration: EmergencyFireControllerConfiguration
}

extension Notification.Name {
    static let linkedEmerFireConfigDidChange = Notification.Name("linkedEmerFireConfigDidChange")
}

extension NotificationCenter {
    func postLinkedEmerFireConfigDidChange(_ config: LinkedEmerFireConfig) {
        if Thread.isMainThread {
            post(name: .linkedEmerFireConfigDidChange, object: config)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.post(name: .linkedEmerFireConfigDidChange, object: config)
            }
        }
    }
}
