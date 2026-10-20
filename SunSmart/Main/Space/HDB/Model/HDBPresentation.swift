import Foundation

enum HDBPresentation {
    static func members(zoneId: Int, in config: HDBConfiguration) -> [HDBDeviceConfiguration] {
        config.devices.filter { $0.lightingZones.contains { $0.zoneId == zoneId } }
            .sorted { $0.nodeAddress < $1.nodeAddress }
    }
    static func selectedZones(_ device: HDBDeviceConfiguration) -> Set<Int> { Set(device.lightingZones.map(\.zoneId)) }
    static func statusKey(_ device: HDBDeviceConfiguration) -> String {
        switch device.lightingZonesStatus {
        case .pending: return "hdb_pending"
        case .synced: return "hdb_synced"
        }
    }
    static func json(_ device: HDBDeviceConfiguration) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(device), as: UTF8.self)
    }
}
