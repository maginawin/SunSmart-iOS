//
//  DeviceEmerFireRepository.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/27.
//

import Foundation
import NordicSigMeshSDK
import SQLite
import struct SQLite.Expression

final class DeviceEmerFireRepository {

    static let shared = DeviceEmerFireRepository()

    private init() {}

    func load(
        meshUUID: String,
        meshNetworkId: String,
        spaceId: String? = nil,
        id: String? = nil
    ) -> [DeviceEmerFireData] {
        DeviceEmerFireData.load(
            meshUUID: meshUUID,
            meshNetworkId: meshNetworkId,
            spaceId: spaceId,
            id: id
        )
    }

    @discardableResult
    func save(_ device: DeviceEmerFireData) -> Bool {
        device.save(meshUUID: device.meshUUID, networkId: device.meshNetworkId)
    }

    @discardableResult
    func delete(_ device: DeviceEmerFireData) -> Bool {
        device.delete(meshUUID: device.meshUUID, networkId: device.meshNetworkId)
    }
}

private var emerFireJSONEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .withoutEscapingSlashes
    return encoder
}

private var emerFireJSONDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

extension DeviceEmerFireData {

    private static let tableName = "deviceEmerFireDatas"
    private static let table = Table(tableName)

    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let deviceId = Expression<String>("deviceId")
        static let spaceId = Expression<String>("spaceId")
        static let name = Expression<String>("name")
        static let bindNodeAddress = Expression<Int?>("bindNodeAddress")
        static let isSynced = Expression<Bool>("isSynced")
        static let reportToGateway = Expression<Bool>("reportToGateway")
        static let enablePowerLossEmergency = Expression<Bool>("enablePowerLossEmergency")
        static let enableFireAlarmEmergency = Expression<Bool>("enableFireAlarmEmergency")
        static let powerLossGroupIndex = Expression<Int>("powerLossGroupIndex")
        static let fireAlarmGroupIndex = Expression<Int>("fireAlarmGroupIndex")
        static let powerLossGroupAddresses = Expression<Data?>("powerLossGroupAddresses")
        static let fireAlarmGroupAddresses = Expression<Data?>("fireAlarmGroupAddresses")
        static let powerLossBrightness = Expression<Int>("powerLossBrightness")
        static let powerLossResuming = Expression<Int>("powerLossResuming")
        static let powerLossSendCount = Expression<Int>("powerLossSendCount")
        static let fireAlarmBrightness = Expression<Int>("fireAlarmBrightness")
        static let fireAlarmResuming = Expression<Int>("fireAlarmResuming")
        static let fireAlarmSendCount = Expression<Int>("fireAlarmSendCount")
        static let createTime = Expression<Int64>("createTime")
        static let lastUpdate = Expression<Int64>("lastUpdate")
    }

    static func initDatabase() {
        _ = try? SunSmartDataManager.shared.db?.run(
            DeviceEmerFireData.table.create(temporary: false, ifNotExists: true, withoutRowid: false) { builder in
                builder.column(ExpressionKey.id, primaryKey: true)
                builder.column(ExpressionKey.meshUUID)
                builder.column(ExpressionKey.subNetworkKey)
                builder.column(ExpressionKey.deviceId)
                builder.column(ExpressionKey.spaceId)
                builder.column(ExpressionKey.name)
                builder.column(ExpressionKey.bindNodeAddress)
                builder.column(ExpressionKey.isSynced)
                builder.column(ExpressionKey.reportToGateway)
                builder.column(ExpressionKey.enablePowerLossEmergency)
                builder.column(ExpressionKey.enableFireAlarmEmergency)
                builder.column(ExpressionKey.powerLossGroupIndex)
                builder.column(ExpressionKey.fireAlarmGroupIndex)
                builder.column(ExpressionKey.powerLossGroupAddresses)
                builder.column(ExpressionKey.fireAlarmGroupAddresses)
                builder.column(ExpressionKey.powerLossBrightness)
                builder.column(ExpressionKey.powerLossResuming)
                builder.column(ExpressionKey.powerLossSendCount)
                builder.column(ExpressionKey.fireAlarmBrightness)
                builder.column(ExpressionKey.fireAlarmResuming)
                builder.column(ExpressionKey.fireAlarmSendCount)
                builder.column(ExpressionKey.createTime)
                builder.column(ExpressionKey.lastUpdate)
                builder.unique(ExpressionKey.meshUUID, ExpressionKey.subNetworkKey, ExpressionKey.deviceId)
            }
        )
    }

    static func load(
        meshUUID: String,
        meshNetworkId: String,
        spaceId: String? = nil,
        id: String? = nil
    ) -> [DeviceEmerFireData] {
        var predicate = DeviceEmerFireData.table.filter(
            ExpressionKey.meshUUID == meshUUID &&
            ExpressionKey.subNetworkKey == meshNetworkId
        )
        if let spaceId {
            predicate = predicate.filter(ExpressionKey.spaceId == spaceId)
        }
        if let id {
            predicate = predicate.filter(ExpressionKey.deviceId == id)
        }

        let filter = predicate.order(ExpressionKey.createTime.asc)
        var devices: [DeviceEmerFireData] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                let powerLossGroupAddresses = decodeAddresses(from: row[ExpressionKey.powerLossGroupAddresses])
                let fireAlarmGroupAddresses = decodeAddresses(from: row[ExpressionKey.fireAlarmGroupAddresses])
                let bindNodeAddress = row[ExpressionKey.bindNodeAddress].flatMap { Address($0) }
                let device = DeviceEmerFireData(
                    id: row[ExpressionKey.deviceId],
                    spaceId: row[ExpressionKey.spaceId],
                    meshUUID: row[ExpressionKey.meshUUID],
                    meshNetworkId: row[ExpressionKey.subNetworkKey],
                    name: row[ExpressionKey.name],
                    bindNodeAddress: bindNodeAddress,
                    isSynced: row[ExpressionKey.isSynced],
                    reportToGateway: row[ExpressionKey.reportToGateway],
                    enablePowerLossEmergency: row[ExpressionKey.enablePowerLossEmergency],
                    enableFireAlarmEmergency: row[ExpressionKey.enableFireAlarmEmergency],
                    powerLossGroupIndex: row[ExpressionKey.powerLossGroupIndex],
                    fireAlarmGroupIndex: row[ExpressionKey.fireAlarmGroupIndex],
                    powerLossGroupAddresses: powerLossGroupAddresses,
                    fireAlarmGroupAddresses: fireAlarmGroupAddresses,
                    powerLossBrightness: row[ExpressionKey.powerLossBrightness],
                    powerLossResuming: row[ExpressionKey.powerLossResuming],
                    powerLossSendCount: row[ExpressionKey.powerLossSendCount],
                    fireAlarmBrightness: row[ExpressionKey.fireAlarmBrightness],
                    fireAlarmResuming: row[ExpressionKey.fireAlarmResuming],
                    fireAlarmSendCount: row[ExpressionKey.fireAlarmSendCount],
                    createTime: row[ExpressionKey.createTime],
                    lastUpdate: row[ExpressionKey.lastUpdate]
                )
                devices.append(device)
            }
        }
        return devices
    }

    @discardableResult
    func save(meshUUID: String? = nil, networkId: String? = nil) -> Bool {
        let meshUUID = meshUUID ?? self.meshUUID
        let networkId = networkId ?? self.meshNetworkId
        let insert = DeviceEmerFireData.table.insert(or: .replace, [
            ExpressionKey.meshUUID <- meshUUID,
            ExpressionKey.subNetworkKey <- networkId,
            ExpressionKey.deviceId <- id,
            ExpressionKey.spaceId <- spaceId,
            ExpressionKey.name <- name,
            ExpressionKey.bindNodeAddress <- bindNodeAddress.map { Int($0) },
            ExpressionKey.isSynced <- isSynced,
            ExpressionKey.reportToGateway <- reportToGateway,
            ExpressionKey.enablePowerLossEmergency <- enablePowerLossEmergency,
            ExpressionKey.enableFireAlarmEmergency <- enableFireAlarmEmergency,
            ExpressionKey.powerLossGroupIndex <- powerLossGroupIndex,
            ExpressionKey.fireAlarmGroupIndex <- fireAlarmGroupIndex,
            ExpressionKey.powerLossGroupAddresses <- Self.encodeAddresses(powerLossGroupAddresses),
            ExpressionKey.fireAlarmGroupAddresses <- Self.encodeAddresses(fireAlarmGroupAddresses),
            ExpressionKey.powerLossBrightness <- powerLossBrightness,
            ExpressionKey.powerLossResuming <- powerLossResuming,
            ExpressionKey.powerLossSendCount <- powerLossSendCount,
            ExpressionKey.fireAlarmBrightness <- fireAlarmBrightness,
            ExpressionKey.fireAlarmResuming <- fireAlarmResuming,
            ExpressionKey.fireAlarmSendCount <- fireAlarmSendCount,
            ExpressionKey.createTime <- createTime,
            ExpressionKey.lastUpdate <- Int64(Date().timeIntervalSince1970)
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
    func delete(meshUUID: String, networkId: String) -> Bool {
        let predicate = ExpressionKey.meshUUID == meshUUID &&
            ExpressionKey.subNetworkKey == networkId &&
            ExpressionKey.deviceId == id
        let filter = DeviceEmerFireData.table.filter(predicate)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
            return true
        } catch {
            print(error)
            return false
        }
    }

    private static func encodeAddresses(_ addresses: [UInt16]) -> Data? {
        guard !addresses.isEmpty else { return nil }
        return try? emerFireJSONEncoder.encode(addresses)
    }

    private static func decodeAddresses(from data: Data?) -> [UInt16] {
        guard let data,
              let addresses = try? emerFireJSONDecoder.decode([UInt16].self, from: data) else {
            return []
        }
        return addresses
    }
}
