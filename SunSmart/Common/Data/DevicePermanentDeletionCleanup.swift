import Foundation
import NordicSigMeshSDK

final class DevicePermanentDeletionContext {
    private let node: Node
    private let nodeAddress: Address
    private let meshUUID: String?
    private let subnetworkId: String?
    private let schedules: [Schedule]
    private var didCommit = false

    init(node: Node) {
        self.node = node
        nodeAddress = node.primaryUnicastAddress
        meshUUID = (node.network ?? MeshNetworkManager.instance.meshNetwork)?.uuid.uuidString
        subnetworkId = node.subNetworkId
        schedules = MeshNetworkManager.instance.schedules
    }

    func commit() {
        guard !didCommit else {
            return
        }
        didCommit = true

        var changedScheduleIds: [Int] = []
        schedules.forEach { schedule in
            let result = DeviceScheduleAddressCleanup.removing(
                address: nodeAddress,
                activeAddresses: schedule.nodeAddresses,
                pendingDeleteAddresses: schedule.needDeleteNodeAddresses
            )
            guard result.didChange else {
                return
            }
            schedule.nodeAddresses = result.activeAddresses
            schedule.needDeleteNodeAddresses = result.pendingDeleteAddresses
            schedule.save(meshUUID: meshUUID, meshNetworkId: subnetworkId)
            changedScheduleIds.append(schedule.id)
        }

        node.deleteExtension()
        print(
            "[DevicePermanentDeletion] node=\(nodeAddress.hex) " +
            "scheduleIds=\(changedScheduleIds.sorted())"
        )
    }
}
