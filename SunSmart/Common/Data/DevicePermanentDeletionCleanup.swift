import Foundation
import NordicSigMeshSDK

final class DevicePermanentDeletionContext {
    private let node: Node
    private let nodeAddress: Address
    private let meshUUID: String?
    private let subnetworkId: String?
    private let schedules: [Schedule]
    private let space: SpaceData?
    private var didCommit = false

    init(node: Node) {
        self.node = node
        nodeAddress = node.primaryUnicastAddress
        meshUUID = (node.network ?? MeshNetworkManager.instance.meshNetwork)?.uuid.uuidString
        subnetworkId = node.subNetworkId
        schedules = MeshNetworkManager.instance.schedules
        space = node.subNetworkId.flatMap { SpaceData.load(subNetworkId: $0) }
    }

    @discardableResult
    func commit() -> ProximityLightingLifecycleResult? {
        guard !didCommit else {
            return nil
        }
        didCommit = true

        var changedScheduleIds: [Int] = []
        let applyDeletion = {
            self.schedules.forEach { schedule in
                let result = DeviceScheduleAddressCleanup.removing(
                    address: self.nodeAddress,
                    activeAddresses: schedule.nodeAddresses,
                    pendingDeleteAddresses: schedule.needDeleteNodeAddresses
                )
                guard result.didChange else {
                    return
                }
                schedule.nodeAddresses = result.activeAddresses
                schedule.needDeleteNodeAddresses = result.pendingDeleteAddresses
                schedule.save(meshUUID: self.meshUUID, meshNetworkId: self.subnetworkId)
                changedScheduleIds.append(schedule.id)
            }
            self.node.deleteExtension()
        }

        let lifecycleResult: ProximityLightingLifecycleResult?
        if let space {
            var transaction = ProximityLightingLifecycleCoordinator.begin(space: space)
            transaction.removeNode(node)
            let result = ProximityLightingLifecycleCoordinator.commit(
                transaction.prepare(),
                allowExistingHardErrors: true,
                hasAdditionalLogicalChange: true,
                applyAdditionalChanges: applyDeletion
            )
            lifecycleResult = result.map {
                .init(
                    didChange: $0.didChange,
                    plan: $0.plan,
                    affectedDeviceAddresses: $0.affectedDeviceAddresses,
                    syncDatas: $0.syncDatas.filter {
                        $0.node.primaryUnicastAddress != self.nodeAddress
                    },
                    repairs: $0.repairs
                )
            }
            if result == nil {
                space.markLocalChangePendingCloudSync()
                applyDeletion()
            }
        } else {
            applyDeletion()
            lifecycleResult = nil
        }
        print(
            "[DevicePermanentDeletion] node=\(nodeAddress.hex) " +
            "scheduleIds=\(changedScheduleIds.sorted()) " +
            "proximityTasks=\(lifecycleResult?.syncDatas.count ?? 0)"
        )
        return lifecycleResult
    }
}
