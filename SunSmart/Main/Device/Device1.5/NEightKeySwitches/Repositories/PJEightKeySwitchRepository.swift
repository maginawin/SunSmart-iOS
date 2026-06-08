//
//  PJEightKeySwitchRepository.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK
import SQLite
import struct SQLite.Expression

enum PJEightKeySwitchSyncState: Int {
    case synced = 0
    case pending = 1
    case failed = 2
}

final class PJEightKeySwitchRepository {

    static let shared = PJEightKeySwitchRepository()

    struct Metadata {
        let panelType: PJEightKeySwitchPanelDefinition.PanelType
        let powerSwitchKind: PJEightKeyPowerSwitchKind
        let moreSettingsState: PJEightKeySwitchMoreSettingsViewModel.State
        let syncState: PJEightKeySwitchSyncState
        let desiredConfigVersion: Int
        let desiredConfigHash: String
        let appliedConfigHash: String
        let lastSyncFailedReason: String?
        let lastSyncedAt: Int64?
        let batteryLevel: UInt8?
        let batteryLastUpdateTime: Int64?
        let appliedTxEnabled: Bool?
        let appliedLEDIndicatorEnabled: Bool?

        init(
            panelType: PJEightKeySwitchPanelDefinition.PanelType,
            powerSwitchKind: PJEightKeyPowerSwitchKind = .battery,
            moreSettingsState: PJEightKeySwitchMoreSettingsViewModel.State = .default,
            syncState: PJEightKeySwitchSyncState = .pending,
            desiredConfigVersion: Int = 0,
            desiredConfigHash: String = "",
            appliedConfigHash: String = "",
            lastSyncFailedReason: String? = nil,
            lastSyncedAt: Int64? = nil,
            batteryLevel: UInt8? = nil,
            batteryLastUpdateTime: Int64? = nil,
            appliedTxEnabled: Bool? = nil,
            appliedLEDIndicatorEnabled: Bool? = nil
        ) {
            self.panelType = panelType
            self.powerSwitchKind = powerSwitchKind
            self.moreSettingsState = moreSettingsState
            self.syncState = syncState
            self.desiredConfigVersion = desiredConfigVersion
            self.desiredConfigHash = desiredConfigHash
            self.appliedConfigHash = appliedConfigHash
            self.lastSyncFailedReason = lastSyncFailedReason
            self.lastSyncedAt = lastSyncedAt
            self.batteryLevel = batteryLevel
            self.batteryLastUpdateTime = batteryLastUpdateTime
            self.appliedTxEnabled = appliedTxEnabled
            self.appliedLEDIndicatorEnabled = appliedLEDIndicatorEnabled
        }
    }

    private enum PanelTypeStorage: Int {
        case scene8Key
        case brightness8Key

        init(panelType: PJEightKeySwitchPanelDefinition.PanelType) {
            switch panelType {
            case .scene8Key:
                self = .scene8Key
            case .brightness8Key:
                self = .brightness8Key
            }
        }

        var panelType: PJEightKeySwitchPanelDefinition.PanelType {
            switch self {
            case .scene8Key:
                return .scene8Key
            case .brightness8Key:
                return .brightness8Key
            }
        }
    }

    private static let tableName = "pjEightKeySwitchs"
    private static let table = Table(tableName)

    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let switchId = Expression<String>("switchId")
        static let panelType = Expression<Int>("panelType")
        static let powerSwitchKind = Expression<Int>("powerSwitchKind")
        static let periodicReporting = Expression<Int>("periodicReporting")
        static let ledIndicatorEnabled = Expression<Bool>("ledIndicatorEnabled")
        static let syncState = Expression<Int>("syncState")
        static let desiredConfigVersion = Expression<Int>("desiredConfigVersion")
        static let desiredConfigHash = Expression<String>("desiredConfigHash")
        static let appliedConfigHash = Expression<String>("appliedConfigHash")
        static let lastSyncFailedReason = Expression<String?>("lastSyncFailedReason")
        static let lastSyncedAt = Expression<Int64?>("lastSyncedAt")
        static let batteryLevel = Expression<Int?>("batteryLevel")
        static let batteryLastUpdateTime = Expression<Int64?>("batteryLastUpdateTime")
        static let appliedTxEnabled = Expression<Bool?>("appliedTxEnabled")
        static let appliedLEDIndicatorEnabled = Expression<Bool?>("appliedLEDIndicatorEnabled")
    }

    private init() {}

    static func initDatabase() {
        _ = try? SunSmartDataManager.shared.db?.run(
            table.create(temporary: false, ifNotExists: true, withoutRowid: false) { builder in
                builder.column(ExpressionKey.id, primaryKey: true)
                builder.column(ExpressionKey.meshUUID)
                builder.column(ExpressionKey.subNetworkKey)
                builder.column(ExpressionKey.switchId)
                builder.column(ExpressionKey.panelType)
                builder.column(ExpressionKey.powerSwitchKind)
                builder.column(ExpressionKey.periodicReporting)
                builder.column(ExpressionKey.ledIndicatorEnabled)
                builder.column(ExpressionKey.syncState)
                builder.column(ExpressionKey.desiredConfigVersion)
                builder.column(ExpressionKey.desiredConfigHash)
                builder.column(ExpressionKey.appliedConfigHash)
                builder.column(ExpressionKey.lastSyncFailedReason)
                builder.column(ExpressionKey.lastSyncedAt)
                builder.column(ExpressionKey.batteryLevel)
                builder.column(ExpressionKey.batteryLastUpdateTime)
                builder.column(ExpressionKey.appliedTxEnabled)
                builder.column(ExpressionKey.appliedLEDIndicatorEnabled)
                builder.unique(ExpressionKey.meshUUID, ExpressionKey.subNetworkKey, ExpressionKey.switchId)
            }
        )
        if let columns = try? SunSmartDataManager.shared.db?.schema.columnDefinitions(table: tableName) {
            if !columns.contains(where: { $0.name == "powerSwitchKind" }) {
                _ = try? SunSmartDataManager.shared.db?.run(
                    table.addColumn(
                        ExpressionKey.powerSwitchKind,
                        defaultValue: PJEightKeyPowerSwitchKind.battery.rawValue
                    )
                )
            }
            if !columns.contains(where: { $0.name == "syncState" }) {
                _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.syncState, defaultValue: PJEightKeySwitchSyncState.synced.rawValue))
            }
            if !columns.contains(where: { $0.name == "desiredConfigVersion" }) {
                _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.desiredConfigVersion, defaultValue: 0))
            }
            if !columns.contains(where: { $0.name == "desiredConfigHash" }) {
                _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.desiredConfigHash, defaultValue: ""))
            }
            if !columns.contains(where: { $0.name == "appliedConfigHash" }) {
                _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.appliedConfigHash, defaultValue: ""))
            }
            if !columns.contains(where: { $0.name == "lastSyncFailedReason" }) {
                _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.lastSyncFailedReason))
            }
            if !columns.contains(where: { $0.name == "lastSyncedAt" }) {
                _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.lastSyncedAt))
            }
            if !columns.contains(where: { $0.name == "batteryLevel" }) {
                _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.batteryLevel))
            }
            if !columns.contains(where: { $0.name == "batteryLastUpdateTime" }) {
                _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.batteryLastUpdateTime))
            }
            if !columns.contains(where: { $0.name == "appliedTxEnabled" }) {
                _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.appliedTxEnabled))
            }
            if !columns.contains(where: { $0.name == "appliedLEDIndicatorEnabled" }) {
                _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.appliedLEDIndicatorEnabled))
            }
        }
    }

    @discardableResult
    func save(_ switchData: PJEightKeySwitchData, meshUUID: String? = nil, networkId: String? = nil) -> Bool {
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return false }
        let subNetworkKey = networkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        let moreSettingsState = switchData.moreSettingsState.reservingPeriodicReportingDisabled
        let insert = Self.table.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- subNetworkKey,
            ExpressionKey.switchId <- switchData.id,
            ExpressionKey.panelType <- PanelTypeStorage(panelType: switchData.eightKeyPanelType).rawValue,
            ExpressionKey.powerSwitchKind <- switchData.powerSwitchKind.rawValue,
            ExpressionKey.periodicReporting <- moreSettingsState.periodicReporting.rawValue,
            ExpressionKey.ledIndicatorEnabled <- moreSettingsState.ledIndicatorEnabled,
            ExpressionKey.syncState <- switchData.syncState.rawValue,
            ExpressionKey.desiredConfigVersion <- switchData.desiredConfigVersion,
            ExpressionKey.desiredConfigHash <- switchData.desiredConfigHash,
            ExpressionKey.appliedConfigHash <- switchData.appliedConfigHash,
            ExpressionKey.lastSyncFailedReason <- switchData.lastSyncFailedReason,
            ExpressionKey.lastSyncedAt <- switchData.lastSyncedAt,
            ExpressionKey.batteryLevel <- switchData.batteryLevel.map { Int($0) },
            ExpressionKey.batteryLastUpdateTime <- switchData.batteryLastUpdateTime,
            ExpressionKey.appliedTxEnabled <- switchData.appliedTxEnabled,
            ExpressionKey.appliedLEDIndicatorEnabled <- switchData.appliedLEDIndicatorEnabled
        ])
        do {
            try SunSmartDataManager.shared.db?.run(insert)
            return true
        } catch {
            print(error)
            return false
        }
    }

    @discardableResult
    func saveBattery(
        level: UInt8,
        lastUpdateTime: Int64,
        for switchData: PJEightKeySwitchData,
        meshUUID: String? = nil,
        networkId: String? = nil
    ) -> Bool {
        guard level <= 100,
              let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return false
        }
        let subNetworkKey = networkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        let filter = Self.table.filter(
            ExpressionKey.meshUUID == uuid &&
            ExpressionKey.subNetworkKey == subNetworkKey &&
            ExpressionKey.switchId == switchData.id
        )
        let update = filter.update(
            ExpressionKey.batteryLevel <- Int(level),
            ExpressionKey.batteryLastUpdateTime <- lastUpdateTime
        )
        do {
            let affectedRows = try SunSmartDataManager.shared.db?.run(update) ?? 0
            if affectedRows == 0 {
                let previousLevel = switchData.batteryLevel
                let previousLastUpdateTime = switchData.batteryLastUpdateTime
                switchData.batteryLevel = level
                switchData.batteryLastUpdateTime = lastUpdateTime
                guard save(switchData, meshUUID: uuid, networkId: subNetworkKey) else {
                    switchData.batteryLevel = previousLevel
                    switchData.batteryLastUpdateTime = previousLastUpdateTime
                    return false
                }
                updateCachedBattery(level: level, lastUpdateTime: lastUpdateTime, for: switchData)
                return true
            }
            switchData.batteryLevel = level
            switchData.batteryLastUpdateTime = lastUpdateTime
            updateCachedBattery(level: level, lastUpdateTime: lastUpdateTime, for: switchData)
            return true
        } catch {
            print(error)
            return false
        }
    }

    private func updateCachedBattery(
        level: UInt8,
        lastUpdateTime: Int64,
        for switchData: PJEightKeySwitchData
    ) {
        guard let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == switchData.id }) else {
            return
        }

        if let cachedSwitch = MeshNetworkManager.instance.switchs[index] as? PJEightKeySwitchData {
            cachedSwitch.batteryLevel = level
            cachedSwitch.batteryLastUpdateTime = lastUpdateTime
            return
        }

        guard let cachedBatteryPowerSwitch = MeshNetworkManager.instance.switchs[index].batteryPowerSwitchData else {
            return
        }
        cachedBatteryPowerSwitch.batteryLevel = level
        cachedBatteryPowerSwitch.batteryLastUpdateTime = lastUpdateTime
        MeshNetworkManager.instance.switchs[index] = cachedBatteryPowerSwitch
    }

    func metadata(for switchData: DeviceSwitchData, meshUUID: String? = nil, networkId: String? = nil) -> Metadata? {
        metadata(
            for: switchData,
            meshUUID: meshUUID,
            networkId: networkId,
            inferredPowerSwitchKind: switchData.proxyNode?.powerSwitchKind
        )
    }

    func metadata(
        for switchData: DeviceSwitchData,
        meshUUID: String? = nil,
        networkId: String? = nil,
        inferredPowerSwitchKind: PJEightKeyPowerSwitchKind?
    ) -> Metadata? {
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return nil }
        let subNetworkKey = networkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        let filter = Self.table.filter(
            ExpressionKey.meshUUID == uuid &&
            ExpressionKey.subNetworkKey == subNetworkKey &&
            ExpressionKey.switchId == switchData.id
        )
        guard let row = try? SunSmartDataManager.shared.db?.pluck(filter) else {
            return nil
        }
        guard
            let panelTypeStorage = PanelTypeStorage(rawValue: row[ExpressionKey.panelType]),
            let periodicReporting = PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption(rawValue: row[ExpressionKey.periodicReporting])
        else {
            return nil
        }
        let state = PJEightKeySwitchMoreSettingsViewModel.State(
            periodicReporting: periodicReporting,
            ledIndicatorEnabled: row[ExpressionKey.ledIndicatorEnabled]
        ).reservingPeriodicReportingDisabled
        let syncState = PJEightKeySwitchSyncState(rawValue: row[ExpressionKey.syncState]) ?? .synced
        let storedPowerSwitchKind = PJEightKeyPowerSwitchKind(rawValue: row[ExpressionKey.powerSwitchKind]) ?? .battery
        let powerSwitchKind = inferredPowerSwitchKind ?? storedPowerSwitchKind
        let batteryLevel: UInt8? = {
            guard let value = row[ExpressionKey.batteryLevel],
                  (0...100).contains(value) else {
                return nil
            }
            return UInt8(value)
        }()
        return Metadata(
            panelType: panelTypeStorage.panelType,
            powerSwitchKind: powerSwitchKind,
            moreSettingsState: state,
            syncState: syncState,
            desiredConfigVersion: row[ExpressionKey.desiredConfigVersion],
            desiredConfigHash: row[ExpressionKey.desiredConfigHash],
            appliedConfigHash: row[ExpressionKey.appliedConfigHash],
            lastSyncFailedReason: row[ExpressionKey.lastSyncFailedReason],
            lastSyncedAt: row[ExpressionKey.lastSyncedAt],
            batteryLevel: batteryLevel,
            batteryLastUpdateTime: row[ExpressionKey.batteryLastUpdateTime],
            appliedTxEnabled: row[ExpressionKey.appliedTxEnabled],
            appliedLEDIndicatorEnabled: row[ExpressionKey.appliedLEDIndicatorEnabled]
        )
    }

    func makeEightKeySwitch(from switchData: DeviceSwitchData) -> PJEightKeySwitchData? {
        guard let metadata = metadata(for: switchData) else { return nil }
        return PJEightKeySwitchData(baseSwitchData: switchData, metadata: metadata)
    }

    func isEightKeySwitch(_ switchData: DeviceSwitchData) -> Bool {
        metadata(for: switchData) != nil
    }

    func delete(for switchData: DeviceSwitchData, meshUUID: String? = nil, networkId: String? = nil) {
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return }
        let subNetworkKey = networkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        let filter = Self.table.filter(
            ExpressionKey.meshUUID == uuid &&
            ExpressionKey.subNetworkKey == subNetworkKey &&
            ExpressionKey.switchId == switchData.id
        )
        _ = try? SunSmartDataManager.shared.db?.run(filter.delete())
    }

    func deleteAll(meshUUID: String, networkId: String) {
        let filter = Self.table.filter(
            ExpressionKey.meshUUID == meshUUID &&
            ExpressionKey.subNetworkKey == networkId
        )
        _ = try? SunSmartDataManager.shared.db?.run(filter.delete())
    }
}

struct PJEightKeySwitchSharePayload {

    static let key = "powerSwitch"

    private enum PayloadKey {
        static let schemaVersion = "schemaVersion"
        static let powerSwitchKind = "powerSwitchKind"
        static let eightKeyPanelType = "eightKeyPanelType"
        static let moreSettings = "moreSettings"
        static let periodicReporting = "periodicReporting"
        static let ledIndicatorEnabled = "ledIndicatorEnabled"
        static let sync = "sync"
        static let syncState = "syncState"
        static let desiredConfigVersion = "desiredConfigVersion"
        static let desiredConfigHash = "desiredConfigHash"
        static let appliedConfigHash = "appliedConfigHash"
        static let lastSyncFailedReason = "lastSyncFailedReason"
        static let lastSyncedAt = "lastSyncedAt"
        static let battery = "battery"
        static let batteryLevel = "level"
        static let batteryLastUpdateTime = "lastUpdateTime"
        static let applied = "applied"
        static let txEnabled = "txEnabled"
        static let appliedLEDIndicatorEnabled = "ledIndicatorEnabled"
    }

    static func dictionary(
        for switchData: DeviceSwitchData,
        meshUUID: String,
        networkId: String,
        proxyNode: Node?
    ) -> [String: Any]? {
        guard let metadata = PJEightKeySwitchRepository.shared.metadata(
            for: switchData,
            meshUUID: meshUUID,
            networkId: networkId,
            inferredPowerSwitchKind: proxyNode?.powerSwitchKind
        ) else {
            return nil
        }

        if let proxyNode {
            guard proxyNode.isPowerSwitch else {
                return nil
            }
            if let nodeKind = proxyNode.powerSwitchKind,
               nodeKind != metadata.powerSwitchKind {
                return nil
            }
        }

        let moreSettings: [String: Any] = [
            PayloadKey.periodicReporting: metadata.moreSettingsState.periodicReporting.rawValue,
            PayloadKey.ledIndicatorEnabled: metadata.moreSettingsState.ledIndicatorEnabled
        ]

        var sync: [String: Any] = [
            PayloadKey.syncState: metadata.syncState.rawValue,
            PayloadKey.desiredConfigVersion: metadata.desiredConfigVersion,
            PayloadKey.desiredConfigHash: metadata.desiredConfigHash,
            PayloadKey.appliedConfigHash: metadata.appliedConfigHash
        ]
        if let lastSyncFailedReason = metadata.lastSyncFailedReason {
            sync[PayloadKey.lastSyncFailedReason] = lastSyncFailedReason
        }
        if let lastSyncedAt = metadata.lastSyncedAt {
            sync[PayloadKey.lastSyncedAt] = lastSyncedAt
        }

        var battery: [String: Any] = [:]
        if let batteryLevel = metadata.batteryLevel {
            battery[PayloadKey.batteryLevel] = Int(batteryLevel)
        }
        if let batteryLastUpdateTime = metadata.batteryLastUpdateTime {
            battery[PayloadKey.batteryLastUpdateTime] = batteryLastUpdateTime
        }

        var applied: [String: Any] = [:]
        if let appliedTxEnabled = metadata.appliedTxEnabled {
            applied[PayloadKey.txEnabled] = appliedTxEnabled
        }
        if let appliedLEDIndicatorEnabled = metadata.appliedLEDIndicatorEnabled {
            applied[PayloadKey.appliedLEDIndicatorEnabled] = appliedLEDIndicatorEnabled
        }

        return [
            PayloadKey.schemaVersion: 1,
            PayloadKey.powerSwitchKind: metadata.powerSwitchKind.rawValue,
            PayloadKey.eightKeyPanelType: metadata.panelType.shareIdentifier,
            PayloadKey.moreSettings: moreSettings,
            PayloadKey.sync: sync,
            PayloadKey.battery: battery,
            PayloadKey.applied: applied
        ]
    }

    static func metadata(
        from dictionary: [String: Any],
        proxyNode: Node?
    ) -> PJEightKeySwitchRepository.Metadata? {
        guard let powerSwitchKindRawValue = intValue(dictionary[PayloadKey.powerSwitchKind]),
              let powerSwitchKind = PJEightKeyPowerSwitchKind(rawValue: powerSwitchKindRawValue),
              let panelTypeIdentifier = dictionary[PayloadKey.eightKeyPanelType] as? String,
              let panelType = PJEightKeySwitchPanelDefinition.PanelType(shareIdentifier: panelTypeIdentifier),
              let moreSettingsDictionary = dictionary[PayloadKey.moreSettings] as? [String: Any],
              let periodicReportingRawValue = intValue(moreSettingsDictionary[PayloadKey.periodicReporting]),
              let periodicReporting = PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption(rawValue: periodicReportingRawValue),
              let ledIndicatorEnabled = boolValue(moreSettingsDictionary[PayloadKey.ledIndicatorEnabled]),
              let syncDictionary = dictionary[PayloadKey.sync] as? [String: Any],
              let syncStateRawValue = intValue(syncDictionary[PayloadKey.syncState]),
              let syncState = PJEightKeySwitchSyncState(rawValue: syncStateRawValue),
              let desiredConfigVersion = intValue(syncDictionary[PayloadKey.desiredConfigVersion]),
              let desiredConfigHash = syncDictionary[PayloadKey.desiredConfigHash] as? String,
              let appliedConfigHash = syncDictionary[PayloadKey.appliedConfigHash] as? String else {
            return nil
        }

        if let proxyNode {
            guard proxyNode.isPowerSwitch else {
                return nil
            }
            if let nodeKind = proxyNode.powerSwitchKind,
               nodeKind != powerSwitchKind {
                return nil
            }
        }

        let batteryDictionary = dictionary[PayloadKey.battery] as? [String: Any]
        let batteryLevel = batteryLevelValue(batteryDictionary?[PayloadKey.batteryLevel])
        let appliedDictionary = dictionary[PayloadKey.applied] as? [String: Any]
        let moreSettingsState = PJEightKeySwitchMoreSettingsViewModel.State(
            periodicReporting: periodicReporting,
            ledIndicatorEnabled: ledIndicatorEnabled
        ).reservingPeriodicReportingDisabled

        return PJEightKeySwitchRepository.Metadata(
            panelType: panelType,
            powerSwitchKind: powerSwitchKind,
            moreSettingsState: moreSettingsState,
            syncState: syncState,
            desiredConfigVersion: desiredConfigVersion,
            desiredConfigHash: desiredConfigHash,
            appliedConfigHash: appliedConfigHash,
            lastSyncFailedReason: syncDictionary[PayloadKey.lastSyncFailedReason] as? String,
            lastSyncedAt: int64Value(syncDictionary[PayloadKey.lastSyncedAt]),
            batteryLevel: batteryLevel,
            batteryLastUpdateTime: int64Value(batteryDictionary?[PayloadKey.batteryLastUpdateTime]),
            appliedTxEnabled: boolValue(appliedDictionary?[PayloadKey.txEnabled]),
            appliedLEDIndicatorEnabled: boolValue(appliedDictionary?[PayloadKey.appliedLEDIndicatorEnabled])
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(value)
        case let value as UInt8:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        switch value {
        case let value as Int64:
            return value
        case let value as Int:
            return Int64(value)
        case let value as NSNumber:
            return value.int64Value
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        default:
            return nil
        }
    }

    private static func batteryLevelValue(_ value: Any?) -> UInt8? {
        guard let intValue = intValue(value),
              (0...100).contains(intValue) else {
            return nil
        }
        return UInt8(intValue)
    }
}

private extension PJEightKeySwitchPanelDefinition.PanelType {

    var shareIdentifier: String {
        switch self {
        case .scene8Key:
            return "scene8Key"
        case .brightness8Key:
            return "brightness8Key"
        }
    }

    init?(shareIdentifier: String) {
        switch shareIdentifier {
        case "scene8Key":
            self = .scene8Key
        case "brightness8Key":
            self = .brightness8Key
        default:
            return nil
        }
    }
}
