import Foundation

@main enum HDBLightingConfigurationServiceTests {
    static func main() throws {
        func check(_ condition: @autoclosure () throws -> Bool) rethrows { let value = try condition(); precondition(value) }
        let space = SpaceData(), network = MeshNetwork(), node = Node(), other = Node(address: 10)
        let secondaryOnOff = Model(0x1000); secondaryOnOff.boundApplicationKeys = []
        let secondary = Element(); secondary.unicastAddress = 2
        secondary.models = [secondaryOnOff, Model(0x1310), Model(0x130F), Model(0x1300)]
        secondary.models.forEach { $0.parentElement = secondary }
        node.elements.append(secondary)
        network.nodes = [node, other]; network.nodes.forEach { $0.network = network }
        MeshNetwork.saved = network; MeshNetworkManager.instance.meshNetwork = network
        space.hdb = .init(lightingZones: [.init(zoneId: 1, name: "One", groupAddress: 0xC001)])
        network.groups = [Group(0xC001)]; SpaceData.persisted = space.copy()
        try seedPrepared(space: space, node: node)
        try seedPrepared(space: space, node: other)
        let otherBefore = try HDBConfigurationStore.load(space: space).devices.first { $0.nodeUuid == other.uuid }!
        let service = HDBLightingConfigurationService(site: SiteData(), space: space)
        var addresses: [UInt16] = []
        MeshNetworkManager.preparationObserver = { _, model in addresses.append(model.parentElement!.unicastAddress) }
        var errors: [Error] = []
        service.didFinish = { if let error = $0 { errors.append(error) } }
        node.preConfiguration.hdbInitializationSignature = nil
        do {
            try service.set(nodeUuid: node.uuid, command: .timeDelay, values: .defaults)
            fatalError("unprepared write accepted")
        } catch HDBLightingError.notPrepared {}
        precondition(addresses.isEmpty && !service.isRunning)
        MeshLibManager.manager.isMeshNetworkConnected = false
        try service.set(nodeUuid: node.uuid, command: .override, values: .init(failsafeDelay: 0))
        try service.set(nodeUuid: node.uuid, command: .installDate, values: .init(installDate: "21-10-2026"))
        var savedDate: String?
        try service.get(nodeUuid: node.uuid, command: .installDate) { savedDate = $0 }
        precondition(savedDate?.contains("21-10-2026") == true && addresses.isEmpty)
        precondition(node.preConfiguration.hdbInitializationSignature == nil, "metadata must not prepare devices")
        MeshLibManager.manager.isMeshNetworkConnected = true
        try seedPrepared(space: space, node: node)
        try HDBConfigurationStore.update(space: space) {
            $0.devices[0].lightingZones = []
            $0.devices[0].lightingZonesStatus = .pending
        }
        MeshNetworkManager.pausePreparation = true
        try service.set(nodeUuid: node.uuid, command: .intensity, values: .init(dimIntensity: 30, brightIntensity: 90))
        pump { MeshNetworkManager.preparationReply != nil }
        precondition(addresses == [1])
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.dimIntensity?.status == .pending)
        reply()
        pump { MeshNetworkManager.preparationReply != nil }
        precondition(addresses == [1, 1])
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.dimIntensity?.status == .synced)
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.brightIntensity?.status == .pending)
        reply(); pump { !service.isRunning }
        precondition(addresses == [1, 1], "each property must use only the first LC element")
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.brightIntensity?.status == .synced)
        try check(HDBConfigurationStore.load(space: space).devices[1] == otherBefore)
        precondition(errors.isEmpty)

        addresses = []
        try service.set(nodeUuid: node.uuid, command: .override, values: .init(lightingControl: .forceOff))
        pump { MeshNetworkManager.preparationReply != nil }
        precondition(addresses == [1])
        reply(); pump { !service.isRunning }
        precondition(addresses == [1], "Force Off excludes secondary OnOff even when unbound")
        let primary = node.elements[0].models.first { $0.modelIdentifier == 0x1000 }!
        primary.boundApplicationKeys = []
        let beforeFailure = try HDBConfigurationStore.load(space: space)
        do { try service.set(nodeUuid: node.uuid, command: .override, values: .init(lightingControl: .forceOff)); fatalError("unbound primary accepted") }
        catch HDBConfigurationError.modelNotBound {}
        try check(HDBConfigurationStore.load(space: space) == beforeFailure)
        primary.boundApplicationKeys = [ApplicationKey()]

        try service.set(nodeUuid: node.uuid, command: .timeDelay, values: .init(holdTime: 60))
        pump { MeshNetworkManager.preparationReply != nil }
        service.cancel()
        do { try service.set(nodeUuid: node.uuid, command: .override, values: .init(failsafeDelay: 20)); fatalError("reentry during cancel") }
        catch HDBConfigurationError.busy {}
        reply(); pump { !service.isRunning }
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.holdTime?.status == .pending)
        try service.set(nodeUuid: node.uuid, command: .override, values: .init(failsafeDelay: 20))
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.holdTime?.status == .pending)

        try service.set(nodeUuid: node.uuid, command: .timeDelay, values: .init(holdTime: 90))
        pump { MeshNetworkManager.preparationReply != nil }; reply(failure: true); pump { !service.isRunning }
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.holdTime?.status == .pending)
        try service.set(nodeUuid: node.uuid, command: .timeDelay, values: .init(holdTime: 90))
        pump { MeshNetworkManager.preparationReply != nil }; reply(); pump { !service.isRunning }
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.holdTime?.status == .synced)

        try service.set(nodeUuid: node.uuid, command: .timeDelay, values: .init(holdTime: 120))
        pump { MeshNetworkManager.preparationReply != nil }
        try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingConfiguration?.merge(.init(holdTime: 140), status: .pending) }
        try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingConfiguration?.merge(.init(holdTime: 120), status: .pending) }
        reply(); pump { !service.isRunning }
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.holdTime?.status == .pending)
        try service.set(nodeUuid: node.uuid, command: .timeDelay, values: .init(holdTime: 120))
        pump { MeshNetworkManager.preparationReply != nil }; reply(mismatch: true); pump { !service.isRunning }
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.holdTime?.status == .pending)
        precondition(errors.contains { ($0 as? HDBLightingError) == .responseMismatch })

        let beforeMissing = try HDBConfigurationStore.load(space: space)
        for id in [UUID(), node.uuid] {
            if id == node.uuid { node.macAddress = nil }
            do { try service.set(nodeUuid: id, command: .override, values: .init(failsafeDelay: 5)); fatalError("invalid target saved") }
            catch is HDBConfigurationError {}
            do { try service.get(nodeUuid: id, command: .installDate) { _ in fatalError("invalid target read") }; fatalError("invalid target accepted") }
            catch is HDBConfigurationError {}
        }
        try check(HDBConfigurationStore.load(space: space) == beforeMissing)
        node.macAddress = "aabbccddeeff"
        addresses = []
        var readback: String?
        try service.get(nodeUuid: node.uuid, command: .timeDelay) { readback = $0 }
        pump { MeshNetworkManager.preparationReply != nil }; reply(failure: true)
        pump { !service.isRunning }
        let observed = try JSONSerialization.jsonObject(with: Data(readback!.utf8)) as! [String: Any]
        precondition(addresses == [1] && observed["incomplete"] as? Bool == true)
        try check(HDBConfigurationStore.load(space: space) == beforeMissing)
        print("PASS: single-target Set/Get ACKs, empty/pending Zone allowed, isolation, offline metadata, binding failure, cancel, retry, stale/mismatched ACK and missing target/MAC")
    }
    static func reply(failure: Bool = false, mismatch: Bool = false) {
        let pending = MeshNetworkManager.preparationReply!
        MeshNetworkManager.preparationReply = nil
        if failure { pending.1.resume(throwing: HDBConfigurationError.unavailable) }
        else { pending.1.resume(returning: mismatch ? LightingTestMessage(write: .off) : pending.0) }
    }
    static func pump(_ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
        precondition(done(), "asynchronous operation did not settle")
    }
}
