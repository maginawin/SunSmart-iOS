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

final class PJEightKeySwitchRepository {

    static let shared = PJEightKeySwitchRepository()

    struct Metadata {
        let panelType: PJEightKeySwitchPanelDefinition.PanelType
        let moreSettingsState: PJEightKeySwitchMoreSettingsViewModel.State
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
                builder.unique(ExpressionKey.meshUUID, ExpressionKey.subNetworkKey, ExpressionKey.switchId)
            }
        )
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
            ExpressionKey.ledIndicatorEnabled <- switchData.moreSettingsState.ledIndicatorEnabled
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
        return Metadata(panelType: panelTypeStorage.panelType, moreSettingsState: state)
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
