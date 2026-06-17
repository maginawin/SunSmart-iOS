//
//  LinkedEmerFireConfig.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

enum EmergencyFireControllerFunction: String, Codable, CaseIterable, Equatable {
    case powerLossEmergency
    case fireAlarmEmergency
}

enum EmergencyFireRestoreActionType: String, Codable, Equatable {
    case restoreAuto
    case setBrightness
    case none
}

enum EmergencyFireControllerState: String, Codable, CaseIterable, Equatable {
    case emergencyTrigger
    case fireTrigger
    case restore

    var sdkStateIndex: EmergencyFireStateIndex {
        switch self {
        case .emergencyTrigger:
            return .emergencyTrigger
        case .fireTrigger:
            return .fireTrigger
        case .restore:
            return .restore
        }
    }

    var taskTitle: String {
        switch self {
        case .emergencyTrigger:
            return "Emergency"
        case .fireTrigger:
            return "Fire"
        case .restore:
            return "Restore"
        }
    }
}

enum EmergencyFireControllerActionPreset: Codable, Equatable {
    case onOff(UInt8)
    case levelDelta(Int32)
    case levelMove(Int16)
    case sceneRecall(SceneNumber)
    case lightControlOnOff(UInt8)
    case lightness(UInt16)
    case ctl(lightness: UInt16, temperature: UInt16, deltaUV: Int16)
    case ctlTemperature(temperature: UInt16, deltaUV: Int16)
    case hsl(lightness: UInt16, hue: UInt16, saturation: UInt16)
    case hslHue(UInt16)
    case hslSaturation(UInt16)
    case powerLevel(UInt16)
    case invalid

    var sdkAction: EmergencyFireAction {
        switch self {
        case .onOff(let value):
            return .onOff(value)
        case .levelDelta(let delta):
            return .levelDelta(delta)
        case .levelMove(let delta):
            return .levelMove(delta)
        case .sceneRecall(let sceneNumber):
            return .sceneRecall(sceneNumber)
        case .lightControlOnOff(let value):
            return .lightControlOnOff(value)
        case .lightness(let lightness):
            return .lightness(lightness)
        case .ctl(let lightness, let temperature, let deltaUV):
            return .ctl(lightness: lightness, temperature: temperature, deltaUV: deltaUV)
        case .ctlTemperature(let temperature, let deltaUV):
            return .ctlTemperature(temperature: temperature, deltaUV: deltaUV)
        case .hsl(let lightness, let hue, let saturation):
            return .hsl(lightness: lightness, hue: hue, saturation: saturation)
        case .hslHue(let hue):
            return .hslHue(hue)
        case .hslSaturation(let saturation):
            return .hslSaturation(saturation)
        case .powerLevel(let power):
            return .powerLevel(power)
        case .invalid:
            return .invalid
        }
    }
}

/// 单个应急功能的触发配置。
/// Power Loss 和 Fire Alarm 两套配置同时有效；恢复动作使用独立的 restore settings。
struct EmergencyFireControllerModeSettings: Codable, Equatable {
    /// 当前模式希望联动的灯组地址。同步时会让组内灯订阅 EFC 的内部 publish group。
    var associateGroupAddresses: [UInt16]
    /// 触发时要写入保留场景的亮度百分比。
    var triggerBrightness: Int
    /// EFC 触发命令重发参数，最终通过 vendor message 下发给控制器。
    var triggerIntervalSeconds: UInt16
    var triggerCount: UInt16
    /// v2 action_type 高级配置入口。当前 UI 未暴露时为 nil，并由默认规则派生。
    var triggerActionPreset: EmergencyFireControllerActionPreset?
    /// 已从配置里移除、但灯节点还需要取消订阅内部 publish group 的组。
    /// 这个字段不能随意清空，否则旧灯组会残留订阅，后续仍可能被 EFC 控制。
    var pendingUnassociateGroupAddresses: [UInt16]

    static let powerLossDefaultValue = EmergencyFireControllerModeSettings(
        associateGroupAddresses: [],
        triggerBrightness: 10,
        triggerIntervalSeconds: 5,
        triggerCount: 0xFFFF,
        triggerActionPreset: nil,
        pendingUnassociateGroupAddresses: []
    )

    static let fireAlarmDefaultValue = EmergencyFireControllerModeSettings(
        associateGroupAddresses: [],
        triggerBrightness: 100,
        triggerIntervalSeconds: 5,
        triggerCount: 0xFFFF,
        triggerActionPreset: nil,
        pendingUnassociateGroupAddresses: []
    )

    init(
        associateGroupAddresses: [UInt16],
        triggerBrightness: Int,
        triggerIntervalSeconds: UInt16,
        triggerCount: UInt16,
        triggerActionPreset: EmergencyFireControllerActionPreset? = nil,
        pendingUnassociateGroupAddresses: [UInt16]
    ) {
        self.associateGroupAddresses = associateGroupAddresses
        self.triggerBrightness = triggerBrightness
        self.triggerIntervalSeconds = triggerIntervalSeconds
        self.triggerCount = triggerCount
        self.triggerActionPreset = triggerActionPreset
        self.pendingUnassociateGroupAddresses = pendingUnassociateGroupAddresses
    }
}

struct EmergencyFireControllerRestoreSettings: Codable, Equatable {
    var actionType: EmergencyFireRestoreActionType
    var brightness: Int
    var resumingSeconds: UInt8
    var sendCount: UInt16

    static let defaultValue = EmergencyFireControllerRestoreSettings(
        actionType: .restoreAuto,
        brightness: 100,
        resumingSeconds: 2,
        sendCount: 2
    )
}

/// EFC 的 desired configuration。
/// 数据库存的是这份配置，真实 Mesh 设备是否已经对齐要看 isSynced 和同步流程结果。
struct EmergencyFireControllerConfiguration: Codable, Equatable {
    var powerLossSettings: EmergencyFireControllerModeSettings
    var fireAlarmSettings: EmergencyFireControllerModeSettings
    var restoreSettings: EmergencyFireControllerRestoreSettings

    static let defaultValue = EmergencyFireControllerConfiguration(
        powerLossSettings: .powerLossDefaultValue,
        fireAlarmSettings: .fireAlarmDefaultValue,
        restoreSettings: .defaultValue
    )
}

extension EmergencyFireControllerConfiguration {

    var enabled: Bool {
        true
    }

    /// 两种应急功能下真正应该被 EFC 控制的灯组。
    var activeLightLCGroupAddresses: Set<Address> {
        Set(powerLossSettings.associateGroupAddresses + fireAlarmSettings.associateGroupAddresses)
    }

    /// 是否还有待清理订阅。用于删除、导入、同步态判断。
    var hasPendingCleanup: Bool {
        !powerLossSettings.pendingUnassociateGroupAddresses.isEmpty ||
        !fireAlarmSettings.pendingUnassociateGroupAddresses.isEmpty
    }

    /// 导入后重新判断同步态使用的业务意图。
    /// 不要盲信外部 JSON 的 isSynced；只要还有绑定、publish group 或配置意图，就应该让同步流程重新对齐。
    var hasSyncIntent: Bool {
        !activeLightLCGroupAddresses.isEmpty || hasPendingCleanup
    }

    func settings(for function: EmergencyFireControllerFunction) -> EmergencyFireControllerModeSettings {
        switch function {
        case .powerLossEmergency:
            return powerLossSettings
        case .fireAlarmEmergency:
            return fireAlarmSettings
        }
    }

    func resendParameters(for state: EmergencyFireControllerState) -> EmergencyFireResendParameters {
        switch state {
        case .emergencyTrigger, .fireTrigger:
            let settings = state == .emergencyTrigger ? powerLossSettings : fireAlarmSettings
            return .init(
                stateIndex: state.sdkStateIndex,
                intervalSeconds: settings.triggerIntervalSeconds,
                count: settings.triggerCount
            )
        case .restore:
            return .init(
                stateIndex: state.sdkStateIndex,
                intervalSeconds: 5,
                count: restoreSettings.sendCount
            )
        }
    }

    func triggerResendParameters() -> EmergencyFireResendParameters {
        .init(
            stateIndex: .emergencyAndFireSync,
            intervalSeconds: powerLossSettings.triggerIntervalSeconds,
            count: powerLossSettings.triggerCount
        )
    }

    func triggerResendParametersEqual(to other: EmergencyFireControllerConfiguration?) -> Bool {
        guard let other else {
            return false
        }
        let lhs = triggerResendParameters()
        let rhs = other.triggerResendParameters()
        return lhs.stateIndex == rhs.stateIndex &&
            lhs.intervalSeconds == rhs.intervalSeconds &&
            lhs.count == rhs.count
    }

    func restoreDelaySeconds() -> UInt8 {
        restoreSettings.resumingSeconds
    }

    func actionConfig(
        for state: EmergencyFireControllerState,
        targetAddress: Address?,
        appKeyIndex: UInt16,
        ttl: UInt8,
        transitionTime: UInt8 = 0,
        delay: UInt8 = 0
    ) -> EmergencyFireActionConfig {
        guard enabled,
              let targetAddress,
              !activeLightLCGroupAddresses.isEmpty,
              let action = action(for: state) else {
            return .init(stateIndex: state.sdkStateIndex, action: .invalid)
        }
        return .init(
            stateIndex: state.sdkStateIndex,
            action: action,
            stage1Target: targetAddress,
            stage2Target: targetAddress,
            appKeyIndex: appKeyIndex,
            ttl: ttl,
            transitionTime: transitionTime,
            delay: delay
        )
    }

    private func action(for state: EmergencyFireControllerState) -> EmergencyFireAction? {
        switch state {
        case .emergencyTrigger:
            return powerLossSettings.triggerActionPreset?.sdkAction ?? .lightness(Self.lightness(from: powerLossSettings.triggerBrightness))
        case .fireTrigger:
            return fireAlarmSettings.triggerActionPreset?.sdkAction ?? .lightness(Self.lightness(from: fireAlarmSettings.triggerBrightness))
        case .restore:
            switch restoreSettings.actionType {
            case .restoreAuto:
                return .lightControlOnOff(1)
            case .setBrightness:
                return .lightness(Self.lightness(from: restoreSettings.brightness))
            case .none:
                return .invalid
            }
        }
    }

    private static func lightness(from percent: Int) -> UInt16 {
        Node.getLightness(lightness100: min(max(percent, 0), 100))
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
