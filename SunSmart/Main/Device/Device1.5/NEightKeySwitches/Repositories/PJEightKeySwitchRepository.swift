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
        let moreSettingsState: PJEightKeySwitchMoreSettingsViewModel.State
        let syncState: PJEightKeySwitchSyncState
        let desiredConfigVersion: Int
        let desiredConfigHash: String
        let appliedConfigHash: String
        let lastSyncFailedReason: String?
        let lastSyncedAt: Int64?

        init(
            panelType: PJEightKeySwitchPanelDefinition.PanelType,
            moreSettingsState: PJEightKeySwitchMoreSettingsViewModel.State = .default,
            syncState: PJEightKeySwitchSyncState = .pending,
            desiredConfigVersion: Int = 0,
            desiredConfigHash: String = "",
            appliedConfigHash: String = "",
            lastSyncFailedReason: String? = nil,
            lastSyncedAt: Int64? = nil
        ) {
            self.panelType = panelType
            self.moreSettingsState = moreSettingsState
            self.syncState = syncState
            self.desiredConfigVersion = desiredConfigVersion
            self.desiredConfigHash = desiredConfigHash
            self.appliedConfigHash = appliedConfigHash
            self.lastSyncFailedReason = lastSyncFailedReason
            self.lastSyncedAt = lastSyncedAt
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
        static let periodicReporting = Expression<Int>("periodicReporting")
        static let ledIndicatorEnabled = Expression<Bool>("ledIndicatorEnabled")
        static let syncState = Expression<Int>("syncState")
        static let desiredConfigVersion = Expression<Int>("desiredConfigVersion")
        static let desiredConfigHash = Expression<String>("desiredConfigHash")
        static let appliedConfigHash = Expression<String>("appliedConfigHash")
        static let lastSyncFailedReason = Expression<String?>("lastSyncFailedReason")
        static let lastSyncedAt = Expression<Int64?>("lastSyncedAt")
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
                builder.column(ExpressionKey.periodicReporting)
                builder.column(ExpressionKey.ledIndicatorEnabled)
                builder.column(ExpressionKey.syncState)
                builder.column(ExpressionKey.desiredConfigVersion)
                builder.column(ExpressionKey.desiredConfigHash)
                builder.column(ExpressionKey.appliedConfigHash)
                builder.column(ExpressionKey.lastSyncFailedReason)
                builder.column(ExpressionKey.lastSyncedAt)
                builder.unique(ExpressionKey.meshUUID, ExpressionKey.subNetworkKey, ExpressionKey.switchId)
            }
        )
        if let columns = try? SunSmartDataManager.shared.db?.schema.columnDefinitions(table: tableName) {
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
        }
    }

    func save(_ switchData: PJEightKeySwitchData, meshUUID: String? = nil, networkId: String? = nil) {
        guard let uuid = meshUUID ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else { return }
        let subNetworkKey = networkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        let insert = Self.table.insert(or: .replace, [
            ExpressionKey.meshUUID <- uuid,
            ExpressionKey.subNetworkKey <- subNetworkKey,
            ExpressionKey.switchId <- switchData.id,
            ExpressionKey.panelType <- PanelTypeStorage(panelType: switchData.eightKeyPanelType).rawValue,
            ExpressionKey.periodicReporting <- switchData.moreSettingsState.periodicReporting.rawValue,
            ExpressionKey.ledIndicatorEnabled <- switchData.moreSettingsState.ledIndicatorEnabled,
            ExpressionKey.syncState <- switchData.syncState.rawValue,
            ExpressionKey.desiredConfigVersion <- switchData.desiredConfigVersion,
            ExpressionKey.desiredConfigHash <- switchData.desiredConfigHash,
            ExpressionKey.appliedConfigHash <- switchData.appliedConfigHash,
            ExpressionKey.lastSyncFailedReason <- switchData.lastSyncFailedReason,
            ExpressionKey.lastSyncedAt <- switchData.lastSyncedAt
        ])
        _ = try? SunSmartDataManager.shared.db?.run(insert)
    }

    func metadata(for switchData: DeviceSwitchData, meshUUID: String? = nil, networkId: String? = nil) -> Metadata? {
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
        )
        let syncState = PJEightKeySwitchSyncState(rawValue: row[ExpressionKey.syncState]) ?? .synced
        return Metadata(
            panelType: panelTypeStorage.panelType,
            moreSettingsState: state,
            syncState: syncState,
            desiredConfigVersion: row[ExpressionKey.desiredConfigVersion],
            desiredConfigHash: row[ExpressionKey.desiredConfigHash],
            appliedConfigHash: row[ExpressionKey.appliedConfigHash],
            lastSyncFailedReason: row[ExpressionKey.lastSyncFailedReason],
            lastSyncedAt: row[ExpressionKey.lastSyncedAt]
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
}
