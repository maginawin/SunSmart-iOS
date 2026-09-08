import Foundation
import NordicSigMeshSDK

struct SyncResultData {
    let node: Node
    /// 成功的操作类型list
    var successOperationTypes: [DeviceOperationType]
    /// 失败的操作类型list
    var failedOperationTypes: [DeviceOperationType]
}

/// 保留原回调范围：普通设备及 Group 成员；不扩展到 Proxy。
struct SyncResultCollector {
    func collect(sections: [SyncDevicesSectionModel], nodes: [Node]) -> [SyncResultData] {
        // 设备数据list
        var resultDatas: [SyncResultData] = []
        var deviceModels: [SyncDevicesModel] = []
        sections.forEach { section in
            deviceModels.append(contentsOf: section.devices)
            section.groups.forEach { groupModel in
                deviceModels.append(contentsOf: groupModel.deviceModels)
            }
        }

        if deviceModels.count > 0 {
            // 获取读取失败的设备参数类型
            deviceModels.forEach { deviceModel in
                if let node = nodes.first(where: { $0.primaryUnicastAddress == deviceModel.address }) {

                    var successOperationTypes: [DeviceOperationType] = []
                    var failedOperationTypes: [DeviceOperationType] = []
                    if let operationType = deviceModel.operationType {
                        if deviceModel.state == .successful {
                            successOperationTypes.append(operationType)
                        }else {
                            failedOperationTypes.append(operationType)
                        }
                    }else {
                        deviceModel.steps.forEach { step in
                            step.tasks.forEach { task in
                                if task.state == .successful {
                                    successOperationTypes.append(task.operationType)
                                }else {
                                    failedOperationTypes.append(task.operationType)
                                }
                            }
                        }
                    }
                    if let index = resultDatas.firstIndex(where: { $0.node == node }) {
                        var data = resultDatas[index]
                        data.successOperationTypes.append(contentsOf: successOperationTypes)
                        data.failedOperationTypes.append(contentsOf: failedOperationTypes)
                        resultDatas[index] = data
                    }else {
                        let data = SyncResultData(node: node, successOperationTypes: successOperationTypes, failedOperationTypes: failedOperationTypes)
                        resultDatas.append(data)
                    }
                }
            }
        }

        return resultDatas
    }
}
