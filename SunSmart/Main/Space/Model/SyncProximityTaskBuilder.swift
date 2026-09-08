import Foundation
import NordicSigMeshSDK

final class SyncProximityTaskBuilder {
    private(set) var proximityLightingTaskModels: [SyncDeviceStepTaskModel] = []

    func appendProximityLightingItems(
        to section: SyncDevicesSectionModel,
        datas: [(node: Node, syncData: NodeSyncData)],
        title: String
    ) {
        datas.forEach { node, syncData in
            let device = SyncDevicesModel(
                name: node.name ?? "",
                address: node.primaryUnicastAddress
            )
            device.imageName = node.iconName

            let operation: ActionType
            let itemTitle: String
            switch syncData {
            case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                operation = .proximityLightingNeighbor(
                    relayNumber: relayNumber,
                    neighborAddresses: neighborAddresses
                )
                itemTitle = title
            case .proximityLightingRelayNumber(let relayNumber):
                operation = .proximityLightingRelayNumber(relayNumber: relayNumber)
                itemTitle = title
            case .proximityLightingEnabled(let enabled):
                operation = .proximityLightingEnabled(enabled: enabled)
                itemTitle = enabled
                    ? "proximity_lighting_enabled".localizedString
                    : "proximity_lighting_disable".localizedString
            default:
                return
            }

            let task = SyncDeviceStepTaskModel(
                name: itemTitle,
                operationType: .configuration(node: node, type: operation)
            )
            let step = SyncDeviceStepModel(
                type: itemTitle,
                state: .none,
                tasks: [task]
            )
            task.parentStepModel = step
            proximityLightingTaskModels.append(task)
            step.parentDeviceModel = device
            device.steps.append(step)
            section.devices.append(device)
        }
    }

}
