import Foundation

@main
struct GatewayFirmwareScanDebugLoggerTests {
    static func main() {
        var lines: [String] = []
        let logger = GatewayFirmwareScanDebugLogger(
            sessionID: "A1B2C3D4",
            sink: { lines.append($0) }
        )
        let peripheralID = UUID(
            uuidString: "11111111-2222-3333-4444-555566667777"
        )!

        logger.record(
            stage: "page_candidate",
            result: "rejected",
            reason: "missing_product_id",
            deviceKey: "node-0003",
            address: 0x0003,
            macAddress: "AABBCCDDEEFF",
            peripheralIdentifier: peripheralID
        )
        logger.record(
            stage: "page_candidate",
            result: "rejected",
            reason: "missing_product_id",
            deviceKey: "node-0003",
            address: 0x0003,
            macAddress: "AABBCCDDEEFF",
            peripheralIdentifier: peripheralID
        )
        logger.record(
            stage: "eligibility",
            result: "disabled",
            reason: "rssi_unavailable",
            deviceKey: "node-0003",
            address: 0x0003,
            macAddress: "AABBCCDDEEFF"
        )
        logger.record(
            stage: "key_scope",
            result: "accepted",
            reason: "gateway_key_scope_ready",
            deviceKey: "node-0003",
            address: 0x0003,
            allowedNetworkKeyCount: 3
        )
        [UInt16(7), UInt16(8)].forEach { index in
            logger.record(
                stage: "key_scope",
                result: "rejected",
                reason: "associated_space_key_unresolved",
                deviceKey: "node-0003",
                address: 0x0003,
                networkKeyIndex: index,
                networkKeySource: "associated_space"
            )
        }
        logger.finish()
        logger.finish()

        #if DEBUG
        precondition(lines.count == 6)
        precondition(
            lines.allSatisfy { $0.contains("[GatewayFirmwareScan]") }
        )
        precondition(lines.allSatisfy { !$0.contains("AABBCCDDEEFF") })
        precondition(
            lines.allSatisfy { !$0.contains(peripheralID.uuidString) }
        )
        precondition(lines.contains { $0.contains("mac_suffix=EEFF") })
        precondition(
            lines.contains { $0.contains("peripheral_suffix=7777") }
        )
        precondition(
            lines.last?.contains("missing_product_id:1") == true
        )
        precondition(lines.last?.contains("rssi_unavailable:1") == true)
        precondition(
            lines.contains { $0.contains("allowed_network_key_count=3") }
        )
        precondition(lines.contains { $0.contains("network_key_index=0007") })
        precondition(lines.contains { $0.contains("network_key_index=0008") })
        precondition(
            lines.contains { $0.contains("network_key_source=associated_space") }
        )
        #else
        precondition(lines.isEmpty)
        #endif
        print("GatewayFirmwareScanDebugLoggerTests passed")
    }
}
