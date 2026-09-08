import Foundation

@main
enum SyncExecutionPolicyTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }

    static func main() {
        testSuccessMatrix()
        testRetryDependencies()
        testResultCollection()
        print("PASS: production success matrix, retry prerequisites and result scope")
    }

    static func testSuccessMatrix() {
        // 三个输入位依次为 hasMessages、ACK 成功、业务状态成功。
        let acceptedInputs: [SyncOperationResultPolicy.Category: Set<Int>] = [
            .ordinary: [3, 7], .gatewayRepairInitialization: [7],
            .gatewayRecoveryInitialization: [6, 7], .emergencyFireDeleteCleanup: [6, 7],
            .batteryPowerSwitchOwnConfiguration: [6, 7]
        ]
        for category in SyncOperationResultPolicy.Category.allCases {
            for input in 0..<8 {
                let result = SyncOperationResultPolicy.isSuccessful(
                    category: category, hasMessages: input & 4 != 0,
                    resultSuccessful: input & 2 != 0, operationSuccessful: input & 1 != 0
                )
                require(result == acceptedInputs[category]!.contains(input), "success contract: \(category), \(input)")
            }
        }
        require(SyncOperationResultPolicy.ackTimeout(isEmergencyFireDeleteCleanup: true) == 5, "cleanup timeout")
        require(SyncOperationResultPolicy.ackTimeout(isEmergencyFireDeleteCleanup: false) == 15, "ordinary timeout")
        let retry = SyncOperationResultPolicy.emergencyFireDeleteCleanupRetryPolicy
        require(retry.maxAttempts == 3 && retry.retryDelay == 0.2, "cleanup retry budget and delay")
    }

    static func task(_ node: Node, _ action: ActionType) -> SyncDeviceStepTaskModel {
        SyncDeviceStepTaskModel(name: "task", operationType: .configuration(node: node, type: action))
    }

    static func testRetryDependencies() {
        let node = Node()
        let time = task(node, .timeSynchronization)
        let lock = task(node, .profile(type: .profileToggleTriggerConditionLuxLock))
        let independent = task(node, .pirEnabled(true))
        let failed = task(node, .schedule(schedule: .init(name: "schedule", enabled: true)))
        failed.relevanceTaskModels = [time, lock, independent]
        let step = SyncDeviceStepModel(type: "step", state: .none, tasks: [time, lock, independent, failed])
        let device = SyncDevicesModel(name: "device", address: 1)
        device.steps = [step]; step.parentDeviceModel = device
        step.tasks.forEach { $0.parentStepModel = step; $0.state = .successful; $0.isFineshed = true }
        failed.markSkipped(); failed.failedCount = 3
        device.isSelected = true; device.isFineshed = true
        let handle = MeshMessageHandle()
        DeviceOperationType.allowsMessageFactory = true
        DeviceOperationType.testHandles = [handle]
        SyncRetryPolicy().prepareDeviceForResync(device)
        require(failed.state == .none && failed.failedCount == 0 && !failed.isFineshed, "retry resets failed/skipped task")
        require(time.state == .wait && lock.state == .wait, "retry includes required TimeSet and Profile lock")
        require(independent.state == .successful, "retry preserves unrelated successful operations")
        require(!device.isSelected && !device.isFineshed && !step.isFineshed, "retry resets parent lifecycle")
        require(handle.respondAddresss.isEmpty && handle.notRespondAddresss.isEmpty, "retry clears stale SDK response addresses")
        DeviceOperationType.allowsMessageFactory = false
    }

    static func testResultCollection() {
        let node = Node()
        let success = task(node, .pirEnabled(true)); success.state = .successful
        let failure = task(node, .pirEnabled(false)); failure.state = .failed
        let skipped = task(node, .timeSynchronization); skipped.markSkipped()
        let device = SyncDevicesModel(name: "device", address: node.primaryUnicastAddress)
        device.steps = [SyncDeviceStepModel(type: "step", state: .none, tasks: [success, failure, skipped])]
        let direct = SyncDevicesModel(name: "same node in another section", address: node.primaryUnicastAddress)
        direct.operationType = .configuration(node: node, type: .deviceInitialize)
        direct.state = .successful
        let proxyOnlyNode = Node(); proxyOnlyNode.primaryUnicastAddress = 2
        let proxy = SyncDevicesModel(name: "proxy", address: 2)
        proxy.operationType = .configuration(node: proxyOnlyNode, type: .deviceInitialize)
        proxy.state = .successful
        let missing = SyncDevicesModel(name: "not in network", address: 9)
        let section = SyncDevicesSectionModel(title: "result")
        section.devices = [device, missing]
        section.groups = [SyncDevicesGroupModel(groupName: "group", groupAddress: 0xC001, deviceModels: [direct])]
        section.switchProxy = SyncDevicesSwitchProxyModel(name: "proxy", deviceModel: proxy)
        let result = SyncResultCollector().collect(sections: [section], nodes: [node, proxyOnlyNode])
        require(result.count == 1 && result[0].node === node, "merge same-node results, omit missing nodes and Proxy-only result")
        require(result[0].successOperationTypes.count == 2 && result[0].failedOperationTypes.count == 2, "collect direct and task operations; skipped remains unsuccessful")
    }
}
