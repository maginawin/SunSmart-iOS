import Foundation

// Platform boundaries only; the script compiles the production creation/deletion methods.
enum Permission { case owner }
enum DataSourceType { case create }
final class FeatureVisibility {
    enum Feature { case spaceHDBConfiguration }
    static let shared = FeatureVisibility()
    var enabled = true
    func isVisible(_ feature: Feature, permission: Permission) -> Bool { enabled }
}
extension SiteData {
    static var hdbSite: Bool { get { hdbEnabled } set { hdbEnabled = newValue } }
    var meshUUID: String { "11111111-1111-4111-8111-111111111111" }
    var lastUpdate: Int64 { get { 1 } set {} }
}
extension SpaceData {
    convenience init(name: String, id: String, siteId: String, imageId: Int, create: Int64,
                     isFavourite: Bool, permission: Permission, sourceType: DataSourceType,
                     meshUUID: String, meshNetworkId: String) {
        self.init(); self.id = id; self.siteId = siteId; self.meshUUID = meshUUID; self.meshNetworkId = meshNetworkId
    }
    func deleteData() -> Bool {
        if Self.persisted?.id == id { Self.persisted = nil }
        return true
    }
}
extension MeshNetworkManager {
    static var creations = 0, removals = 0
    static func addSubnetwork(meshUUID: String, networkKeyName: String, applicationKeyName: String) -> (networkKey: Key, appKey: Key)? {
        creations += 1
        let key = Key(networkId: "new-\(creations)")
        MeshNetwork.saved!.networkKeys.append(key)
        return (key, key)
    }
    static func removeSubnetwork(meshUUID: String, networkId: String) -> Bool {
        removals += 1
        MeshNetwork.saved!.groups.removeAll { $0.subNetworkId == networkId }
        MeshNetwork.saved!.networkKeys.removeAll { $0.networkId == networkId }
        return true
    }
}
extension SpaceConfigurationSafety { static func beginRemoval(_ space: SpaceData) -> Bool { true } }
extension CloudSynchronizationManager { func cancelSynchronizationHandle(space: SpaceData) {} }
final class SunSmartDataManager { static let shared = SunSmartDataManager(); let db: Bool? = true }
final class MeshLibManager { static let manager = MeshLibManager(); var subElementGroupSubscriptionModelIDs: [UInt16] = [0x1000, 0x1300, 0x130F, 0x1310]; func meshNetworkDisconnect() {} }
extension GroupInfo { static func delete(meshUUID: String, networkId: String) -> Bool { true } }
enum SceneInfo { static func delete(meshUUID: String, networkId: String) -> Bool { true } }
extension Schedule { static func deleteAll(meshUUID: String, meshNetworkId: String) -> Bool { true } }
enum Profile { static func deleteProfiles(meshUUID: String, meshNetworkId: String) -> Bool { true } }
extension DeviceSwitchData { static func deleteSwitchs(meshUUID: String, networkId: String) -> Bool { true } }

@main enum HDBSpaceCreationTests {
    static func main() throws {
        let site = SiteData(), network = MeshNetwork()
        MeshNetwork.saved = network; MeshNetworkManager.instance.meshNetwork = network
        // Deliberately include virtual/reserved addresses, duplicates and unsorted allocation.
        MeshAPI.allocation = [0x8001, 0xC000, 0xFEFD, 0xFEFE, 0xFEFF, 0xFFFF, 0xC001] + Array((UInt16(0xC001)...0xC100).reversed())
        let originalKey = MeshNetworkManager.instance.currentNetworkKey.networkId
        guard let first = try site.addSpace(name: "First") else { fatalError("creation failed") }
        precondition(first.hdb?.lightingZones.map(\.zoneId) == Array(1...63), "new Space needs all 63 Zones")
        let firstAddresses = first.hdb!.lightingZones.map(\.groupAddress)
        precondition(firstAddresses == Array(UInt16(0xC001)...0xC03F))
        precondition(first.hdb!.devices.isEmpty && SpaceData.saveCount == 1)
        precondition(network.groups.count == 63 && network.groups.allSatisfy { !$0.isVirtual && $0.subNetworkId == first.meshNetworkId })
        precondition(CloudSynchronizationManager.shared.submissions == 0, "creation caller alone queues upload")
        precondition(MeshNetworkManager.instance.currentNetworkKey.networkId == originalKey, "creation must not switch active Space")
        guard let second = try site.addSpace(name: "Second") else { fatalError("second creation failed") }
        precondition(second.hdb!.lightingZones.first!.groupAddress == 0xC040)
        precondition(Set(firstAddresses).isDisjoint(with: second.hdb!.lightingZones.map(\.groupAddress)))
        precondition(SpaceData.saveCount == 2 && site.spaces.count == 2)
        // A legacy Space is still empty until manual creation, which also excludes other Spaces.
        let legacy = SpaceData(); SpaceData.persisted = legacy.copy()
        let old = try HDBConfigurationStore.load(space: legacy)
        precondition(old.lightingZones.isEmpty)
        let manual = try HDBConfigurationStore.createZone(space: legacy, zoneId: 1, name: "Manual")
        precondition(manual.groupAddress == 0xC07F)
        // Existing normal Space deletion releases only its own groups for reuse.
        precondition(first.delete())
        guard let reused = try site.addSpace(name: "Reuse") else { fatalError("reuse failed") }
        precondition(reused.hdb!.lightingZones.map(\.groupAddress) == firstAddresses)
        precondition(network.groups.contains { $0.subNetworkId == second.meshNetworkId })
        let beforeGroups = network.groups.count, beforeKeys = network.networkKeys.count, beforeSpaces = site.spaces.count
        let available = MeshAPI.allocation
        MeshAPI.allocation = Array(UInt16(0xC100)...0xC13D) // 62 addresses.
        let creations = MeshNetworkManager.creations
        do { _ = try site.addSpace(name: "Short"); fatalError("short allocation accepted") } catch HDBConfigurationError.addressUnavailable {}
        precondition(MeshNetworkManager.creations == creations && site.spaces.count == beforeSpaces)
        MeshAPI.allocation = available
        for failure in 0..<3 {
            Group.failAddress = failure == 0 ? 0xC090 : nil
            GroupInfo.failAddress = failure == 1 ? 0xC090 : nil
            SpaceData.failSave = failure == 2
            do { _ = try site.addSpace(name: "Failure"); fatalError("failed save accepted") } catch HDBConfigurationError.persistenceFailed {}
            precondition(network.groups.count == beforeGroups && network.networkKeys.count == beforeKeys)
            precondition(site.spaces.count == beforeSpaces && CloudSynchronizationManager.shared.submissions == 1)
        }
        Group.failAddress = nil; GroupInfo.failAddress = nil; SpaceData.failSave = false
        guard let retry = try site.addSpace(name: "Retry") else { fatalError("retry failed") }
        precondition(retry.hdb!.lightingZones.first!.groupAddress == 0xC080)
        // Standard Sites must create an ordinary Space even with no HDB addresses available.
        SiteData.hdbSite = false
        MeshAPI.allocation = []
        let groupsBeforeStandard = network.groups.count
        guard let standard = try site.addSpace(name: "Standard") else { fatalError("standard creation failed") }
        precondition(standard.hdb == nil && network.groups.count == groupsBeforeStandard)
        SiteData.failTypeRead = true
        let creationsBeforeReadFailure = MeshNetworkManager.creations
        do { _ = try site.addSpace(name: "Unreadable"); fatalError("unreadable type accepted") }
        catch HDBConfigurationError.persistenceFailed {}
        precondition(MeshNetworkManager.creations == creationsBeforeReadFailure)
        SiteData.failTypeRead = false
        SiteData.hdbSite = true
        // Disabling the HDB configuration rule retains ordinary Space creation behavior.
        FeatureVisibility.shared.enabled = false
        MeshAPI.allocation = []
        guard let ordinary = try site.addSpace(name: "Ordinary") else { fatalError("ordinary creation failed") }
        precondition(ordinary.hdb == nil)
        print("PASS: 63 Zones, global unique allocated addresses, legacy manual creation, normal deletion reuse, shortage before subnet, save failure cleanup, retry and feature gate")
    }
}

extension MeshNetwork { func group(withAddress address: UInt16) -> Group? { groups.first { $0.address.address == address } } }
