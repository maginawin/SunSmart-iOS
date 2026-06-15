//
//  DeviceEmerFireRepository.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
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

    @discardableResult
    func deleteAll(meshUUID: String, meshNetworkId: String) -> Bool {
        DeviceEmerFireData.deleteAll(meshUUID: meshUUID, networkId: meshNetworkId)
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

    private static let tableName = "emergencyFireControllers"
    private static let table = Table(tableName)

    struct ExpressionKey {
        static let id = Expression<Int64>("id")
        static let meshUUID = Expression<String>("meshUUID")
        static let subNetworkKey = Expression<String>("subNetworkKey")
        static let controllerId = Expression<String>("controllerId")
        static let spaceId = Expression<String>("spaceId")
        static let name = Expression<String>("name")
        static let bindNodeAddress = Expression<Int?>("bindNodeAddress")
        static let publishGroupAddress = Expression<Int?>("publishGroupAddress")
        static let isSynced = Expression<Bool>("isSynced")
        static let reportToGateway = Expression<Bool>("reportToGateway")
        static let configurationData = Expression<Data?>("configurationData")
        static let createTime = Expression<Int64>("createTime")
        static let lastUpdate = Expression<Int64>("lastUpdate")
    }

    static func initDatabase() {
        _ = try? SunSmartDataManager.shared.db?.run(
            DeviceEmerFireData.table.create(temporary: false, ifNotExists: true, withoutRowid: false) { builder in
                builder.column(ExpressionKey.id, primaryKey: true)
                builder.column(ExpressionKey.meshUUID)
                builder.column(ExpressionKey.subNetworkKey)
                builder.column(ExpressionKey.controllerId)
                builder.column(ExpressionKey.spaceId)
                builder.column(ExpressionKey.name)
                builder.column(ExpressionKey.bindNodeAddress)
                builder.column(ExpressionKey.publishGroupAddress)
                builder.column(ExpressionKey.isSynced)
                builder.column(ExpressionKey.reportToGateway)
                builder.column(ExpressionKey.configurationData)
                builder.column(ExpressionKey.createTime)
                builder.column(ExpressionKey.lastUpdate)
                builder.unique(ExpressionKey.meshUUID, ExpressionKey.subNetworkKey, ExpressionKey.controllerId)
            }
        )

        if let columns = try? SunSmartDataManager.shared.db?.schema.columnDefinitions(table: tableName) {
            let columnNames = Set(columns.map { $0.name })
            if !columnNames.contains("spaceId") {
                _ = try? SunSmartDataManager.shared.db?.run(DeviceEmerFireData.table.addColumn(ExpressionKey.spaceId, defaultValue: ""))
            }
            if !columnNames.contains("publishGroupAddress") {
                _ = try? SunSmartDataManager.shared.db?.run(DeviceEmerFireData.table.addColumn(ExpressionKey.publishGroupAddress))
            }
            if !columnNames.contains("configurationData") {
                _ = try? SunSmartDataManager.shared.db?.run(DeviceEmerFireData.table.addColumn(ExpressionKey.configurationData))
            }
            migrateMissingColumns(columnNames)
        }
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
            predicate = predicate.filter(ExpressionKey.spaceId == spaceId || ExpressionKey.spaceId == "")
        }
        if let id {
            predicate = predicate.filter(ExpressionKey.controllerId == id)
        }

        let filter = predicate.order(ExpressionKey.createTime.asc)
        var devices: [DeviceEmerFireData] = []
        if let rows = try? SunSmartDataManager.shared.db?.prepare(filter) {
            for row in rows {
                let bindNodeAddress = row[ExpressionKey.bindNodeAddress].flatMap { Address($0) }
                let publishGroupAddress = row[ExpressionKey.publishGroupAddress].flatMap { Address($0) }
                let configuration = row[ExpressionKey.configurationData].flatMap {
                    try? emerFireJSONDecoder.decode(EmergencyFireControllerConfiguration.self, from: $0)
                } ?? .defaultValue
                let device = DeviceEmerFireData(
                    id: row[ExpressionKey.controllerId],
                    spaceId: row[ExpressionKey.spaceId],
                    meshUUID: row[ExpressionKey.meshUUID],
                    meshNetworkId: row[ExpressionKey.subNetworkKey],
                    name: row[ExpressionKey.name],
                    bindNodeAddress: bindNodeAddress,
                    publishGroupAddress: publishGroupAddress,
                    isSynced: row[ExpressionKey.isSynced],
                    reportToGateway: row[ExpressionKey.reportToGateway],
                    configuration: configuration,
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
            ExpressionKey.controllerId <- id,
            ExpressionKey.spaceId <- spaceId,
            ExpressionKey.name <- name,
            ExpressionKey.bindNodeAddress <- bindNodeAddress.map { Int($0) },
            ExpressionKey.publishGroupAddress <- publishGroupAddress.map { Int($0) },
            ExpressionKey.isSynced <- isSynced,
            ExpressionKey.reportToGateway <- reportToGateway,
            ExpressionKey.configurationData <- try? emerFireJSONEncoder.encode(configuration),
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
            ExpressionKey.controllerId == id
        let filter = DeviceEmerFireData.table.filter(predicate)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
            return true
        } catch {
            print(error)
            return false
        }
    }

    @discardableResult
    static func deleteAll(meshUUID: String, networkId: String) -> Bool {
        let predicate = ExpressionKey.meshUUID == meshUUID &&
            ExpressionKey.subNetworkKey == networkId
        let filter = DeviceEmerFireData.table.filter(predicate)
        do {
            try SunSmartDataManager.shared.db?.run(filter.delete())
            return true
        } catch {
            print(error)
            return false
        }
    }

    private static func migrateMissingColumns(_ columnNames: Set<String>) {
        let db = SunSmartDataManager.shared.db
        if !columnNames.contains("isSynced") {
            _ = try? db?.run(table.addColumn(ExpressionKey.isSynced, defaultValue: false))
        }
        if !columnNames.contains("reportToGateway") {
            _ = try? db?.run(table.addColumn(ExpressionKey.reportToGateway, defaultValue: true))
        }
        if !columnNames.contains("createTime") {
            _ = try? db?.run(table.addColumn(ExpressionKey.createTime, defaultValue: Int64(Date().timeIntervalSince1970)))
        }
        if !columnNames.contains("lastUpdate") {
            _ = try? db?.run(table.addColumn(ExpressionKey.lastUpdate, defaultValue: Int64(Date().timeIntervalSince1970)))
        }
    }
}
