//
//  GatewayFirmwareScanDebugLogger.swift
//  SunSmart
//
//  Created by One on 2026/8/6.
//

import Foundation

final class GatewayFirmwareScanDebugLogger {
    private struct EventKey: Hashable {
        let stage: String
        let reason: String
        let deviceKey: String
        let networkKeyIndex: UInt16?
    }

    let sessionID: String

    private let sink: (String) -> Void
    private var eventKeys: Set<EventKey> = []
    private var reasonCounts: [String: Int] = [:]
    private var finished = false

    init(
        sessionID: String,
        sink: @escaping (String) -> Void = { print($0) }
    ) {
        self.sessionID = sessionID
        self.sink = sink
    }

    static func makeSessionID() -> String {
        String(UUID().uuidString.prefix(8))
    }

    func record(
        stage: String,
        result: String,
        reason: String,
        deviceKey: String,
        cid: UInt16? = nil,
        pid: UInt16? = nil,
        address: UInt16? = nil,
        rssi: Int? = nil,
        macAddress: String? = nil,
        peripheralIdentifier: UUID? = nil,
        networkKeyIndex: UInt16? = nil,
        networkKeySource: String? = nil,
        allowedNetworkKeyCount: Int? = nil
    ) {
        #if DEBUG
        guard !finished else {
            return
        }
        let eventKey = EventKey(
            stage: stage,
            reason: reason,
            deviceKey: deviceKey,
            networkKeyIndex: networkKeyIndex
        )
        guard eventKeys.insert(eventKey).inserted else {
            return
        }

        reasonCounts[reason, default: 0] += 1
        var fields = [
            "[GatewayFirmwareScan]",
            "session=\(sessionID)",
            "stage=\(stage)",
            "result=\(result)",
            "reason=\(reason)",
            "device=\(deviceKey)"
        ]
        if let cid {
            fields.append("cid=\(String(format: "%04X", cid))")
        }
        if let pid {
            fields.append("pid=\(String(format: "%04X", pid))")
        }
        if let address {
            fields.append("address=\(String(format: "%04X", address))")
        }
        if let rssi {
            fields.append("rssi=\(rssi)")
        }
        if let networkKeyIndex {
            fields.append(
                "network_key_index=\(String(format: "%04X", networkKeyIndex))"
            )
        }
        if let networkKeySource {
            fields.append("network_key_source=\(networkKeySource)")
        }
        if let allowedNetworkKeyCount {
            fields.append("allowed_network_key_count=\(allowedNetworkKeyCount)")
        }
        if let macSuffix = Self.suffix(macAddress) {
            fields.append("mac_suffix=\(macSuffix)")
        }
        if let peripheralSuffix = Self.suffix(
            peripheralIdentifier?.uuidString
        ) {
            fields.append("peripheral_suffix=\(peripheralSuffix)")
        }
        sink(fields.joined(separator: " "))
        #endif
    }

    func finish() {
        #if DEBUG
        guard !finished else {
            return
        }
        finished = true
        let counts = reasonCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        sink(
            "[GatewayFirmwareScan] session=\(sessionID) " +
            "stage=summary result=finished reasons=\(counts)"
        )
        #endif
    }

    private static func suffix(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value
            .filter(\.isHexDigit)
            .uppercased()
        guard !normalized.isEmpty else {
            return nil
        }
        return String(normalized.suffix(4))
    }
}
