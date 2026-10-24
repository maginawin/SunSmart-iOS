import Foundation

@main enum HDBZoneControlTests {
    static func main() throws {
        let space = SpaceData()
        SpaceData.persisted = space.copy()
        let node = Node(), network = MeshNetwork()
        node.network = network; network.nodes = [node]
        MeshNetwork.saved = network; MeshNetworkManager.instance.meshNetwork = network
        let zone = try HDBConfigurationStore.createZone(space: space, zoneId: 7, name: "Test")
        let other = try HDBConfigurationStore.createZone(space: space, zoneId: 8, name: "Other")
        try HDBConfigurationStore.update(space: space) {
            $0.devices = [.init(nodeUuid: node.uuid, nodeAddress: 1, mac: "AA:BB:CC:DD:EE:FF",
                               lightingZones: [.init(zoneId: 7)])]
        }
        let service = HDBLightingZoneService(site: SiteData(), space: space)
        let original = try HDBConfigurationStore.load(space: space)
        let uploads = CloudSynchronizationManager.shared.submissions
        try service.control(zoneId: 7, groupAddress: zone.groupAddress, action: .auto)
        try service.control(zoneId: 7, groupAddress: zone.groupAddress, action: .on)
        try service.control(zoneId: 7, groupAddress: zone.groupAddress, action: .off)
        for value in [0, 1, 50, 100] {
            try service.control(zoneId: 7, groupAddress: zone.groupAddress, action: .brightness(value))
        }
        precondition(ControlRadio.messages.count == 7)
        precondition(ControlRadio.messages.allSatisfy { $0.address == zone.groupAddress })
        let auto = ControlRadio.messages[0].message as! LightLCLightOnOffSetUnacknowledged
        precondition(auto.isOn && auto.transitionTime == nil && auto.delay == nil,
                     "Zone Auto must use the device's saved RampUp")
        precondition((ControlRadio.messages[1].message as! GenericOnOffSetUnacknowledged).isOn)
        precondition(!(ControlRadio.messages[2].message as! GenericOnOffSetUnacknowledged).isOn)
        precondition(ControlRadio.messages.suffix(4).map { ($0.message as! LightLightnessSetUnacknowledged).lightness } == [0, 655, 32767, 65535])
        for detected in [true, false, false, true] {
            let count = ControlRadio.messages.count
            try service.publishPresence(zoneId: 7, groupAddress: zone.groupAddress, detected: detected)
            precondition(ControlRadio.messages.count == count + 1, "One click submits one event")
            let sent = ControlRadio.messages.last!
            let message = sent.message as! SensorStatus
            precondition(sent.address == zone.groupAddress && sent.address != 7)
            precondition(SensorStatus.opCode == 0x52 && message.values.count == 1)
            precondition(message.values[0].property.id == 0x004D)
            precondition(message.values[0].value == .bool(detected))
            precondition(message.parameters == Data([0xA0, 0x09, detected ? 1 : 0]),
                         "Use the SDK Sensor Status MPID and one-byte Presence value")
        }
        let afterControl = try HDBConfigurationStore.load(space: space)
        precondition(afterControl == original)
        precondition(CloudSynchronizationManager.shared.submissions == uploads)
        precondition(SyncExecutionEnvironment.batches.isEmpty && SyncExecutionEnvironment.stops == 0)

        func reject(_ action: HDBZoneControlAction = .on, id: Int = 7, address: UInt16? = nil,
                    includingPresence: Bool = true) throws {
            let count = ControlRadio.messages.count
            do {
                try service.control(zoneId: id, groupAddress: address ?? zone.groupAddress, action: action)
                fatalError("invalid control accepted")
            } catch { precondition(ControlRadio.messages.count == count) }
            if includingPresence {
                for detected in [true, false] {
                    do {
                        try service.publishPresence(zoneId: id, groupAddress: address ?? zone.groupAddress, detected: detected)
                        fatalError("invalid presence publication accepted")
                    } catch { precondition(ControlRadio.messages.count == count) }
                }
            }
        }
        try reject(.brightness(-1), includingPresence: false)
        try reject(.brightness(101), includingPresence: false)
        try reject(address: other.groupAddress)
        try reject(id: 8, address: other.groupAddress) // Empty zone.
        MeshLibManager.manager.isMeshNetworkConnected = false
        try reject()
        MeshLibManager.manager.isMeshNetworkConnected = true
        MeshProxyMessageCommand.shared.isBusy = true
        try reject()
        MeshProxyMessageCommand.shared.isBusy = false
        UserData.currentUserId = "other"; try reject(); UserData.currentUserId = "user"
        UserData.currentServerRegion = "other"; try reject(); UserData.currentServerRegion = "region"
        MeshNetworkManager.instance.currentNetworkKey.networkId = "other"
        try reject(); MeshNetworkManager.instance.currentNetworkKey.networkId = "network"
        SpaceData.persisted?.canEditing = false; try reject(); SpaceData.persisted?.canEditing = true
        space.canEditing = false; try reject(); space.canEditing = true
        EmergencyFireControllerSceneEventManager.blockedNodes = [node.uuid]
        try reject(); EmergencyFireControllerSceneEventManager.blockedNodes = []
        EmergencyFireControllerSceneEventManager.blockedGroups = [zone.groupAddress]
        try reject(); EmergencyFireControllerSceneEventManager.blockedGroups = []
        try service.control(zoneId: 7, groupAddress: zone.groupAddress, action: .on)
        network.groups.removeAll { $0.address.address == zone.groupAddress }
        try reject(); network.groups.append(Group(zone.groupAddress))

        // Only current targets are known; no Space-wide block for other pending devices.
        try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingZonesStatus = .pending }
        try service.control(zoneId: 7, groupAddress: zone.groupAddress, action: .off)
        for detected in [true, false] {
            try service.publishPresence(zoneId: 7, groupAddress: zone.groupAddress, detected: detected)
        }
        try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingZones = [] }
        try reject()
        precondition(SyncExecutionEnvironment.stops == 0)
        print("PASS: group controls and SDK Presence encoding; no intent/upload changes; pending members allowed; scope, connection and emergency guards")
    }
}
