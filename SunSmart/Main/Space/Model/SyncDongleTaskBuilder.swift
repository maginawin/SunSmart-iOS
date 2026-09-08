import Foundation
import NordicSigMeshSDK

/// 采集日程的配置和删除分别保留在两个设备模型中，消息仍在执行时生成。
struct SyncDongleTaskBuilder {
    func makeDeviceModels(data: DeviceDongleData) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
        guard let node = data.bindNode else { return (nil, nil) }
        let syncDatas = node.getSyncData(type: .dongle(dongleData: data))
        let configuration = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
        let removal = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
        configuration.imageName = node.iconName
        removal.imageName = node.iconName

        for syncData in syncDatas {
            switch syncData {
            case .syncCollectionSchedules(let schedules):
                append(schedules: schedules, node: node, to: configuration)
            case .deleteCollectionSchedules(let indexes):
                append(schedules: indexes.map { ($0, SchedulerRegistryEntry()) }, node: node, to: removal)
            default:
                break
            }
        }
        return (
            configuration.steps.isEmpty ? nil : configuration,
            removal.steps.isEmpty ? nil : removal
        )
    }

    private func append(schedules: [(Int, SchedulerRegistryEntry)], node: Node, to device: SyncDevicesModel) {
        guard !schedules.isEmpty else { return }
        let tasks = schedules.map { index, entry in
            SyncDeviceStepTaskModel(
                name: "collection_schedule".localizedString + " \(index)",
                operationType: .configuration(node: node, type: .collectionSchedule(index: index, entry: entry))
            )
        }
        let step = SyncDeviceStepModel(type: "collection_schedule".localizedString, state: .none, tasks: tasks)
        tasks.forEach { $0.parentStepModel = step }
        step.parentDeviceModel = device
        device.steps.append(step)
    }
}
