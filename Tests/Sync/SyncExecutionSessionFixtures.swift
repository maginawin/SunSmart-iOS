// Session 主体、任务选择、回写、重试和兼容模型来自生产；以下只替代 SDK/业务边界。
struct TestVendorModel { var parentElement: TestElement? }
struct TestElement { var unicastAddress: Address }
enum DeviceBlinkMode { case none, fast, breathing }
struct SunricherVendorSet {
    enum Function { case daylightLuxTriggerLock(delay: Int) }
    init(function: Function) {}
}
extension UInt16 { static var allNodes: UInt16 { 0xFFFF } }
enum MeshAPI {
    static func sendMessage(message: SunricherVendorSet, address: Address) {}
    static func sendMessage(message: SunricherVendorSet, model: Int) {}
}
extension MeshNetwork {
    func node(withAddress address: Address) -> Node? { nodes.first { $0.primaryUnicastAddress == address } }
}
extension MeshNetworkManager { var test: Int { 0 } }
extension DeviceOperationType {
    var isSuccessful: Bool {
        switch self { case .configuration(let node, _), .delete(let node, _): return node.applied }
    }
}
extension SyncDevicesViewController {
    enum SyncState { case inSync, syncFailure, syncSuccess }
    enum EmergencyFireSyncContext { case placeholder }
    enum SyncType {
        case devices([Node])
        case batteryPowerSwitch(PJEightKeySwitchData)
        case gatewayRecovery(Node, GatewayModel, GatewayRecoveryTrigger)
        case gatewayServerRecovery(Node, GatewayModel)
    }
}
final class ProfileSensorProtectionContext {
    var handles: [MeshMessageHandle] = []
    var starts = 0
    func remainingTargetStateMessageHandles() -> [MeshMessageHandle] { handles }
    func markPreDisableStarted() { starts += 1 }
    func markTargetStateTaskStarted(for node: Node) { starts += 1 }
}
enum SpaceChangeDataType { case device }
let spaceDataChangedNotificaitonName = "session-test"

final class SyncExecutionEnvironment {
    var configurationAvailable: () -> Bool = { true }
    var bluetoothAvailable: () -> Bool = { true }
    var delay: (TimeInterval, @escaping () -> Void) -> Void = { _, _ in fatalError("install clock") }
    var authorize: (GatewayModel, Node, @escaping (String?) -> Void) -> (() -> Void) = { _, _, _ in fatalError("install authorization") }
    var stop: (@escaping () -> Void) -> Void = { _ in fatalError("install stop") }
    var send: ([MeshMessageHandle], TimeInterval, ((MeshMessageHandle, Int) -> Void)?, ((MeshMessageHandle) -> Void)?, (([MeshMessageHandle]) -> Void)?) -> Void = { _, _, _, _, _ in fatalError("install transport") }
    func addMessage(messageHandles: [MeshMessageHandle], ackMessageTimeout: TimeInterval = 5,
                    successfulBack: ((MeshMessageHandle, Int) -> Void)? = nil,
                    failedBack: ((MeshMessageHandle) -> Void)? = nil,
                    finishedBack: (([MeshMessageHandle]) -> Void)?) {
        send(messageHandles, ackMessageTimeout, successfulBack, failedBack, finishedBack)
    }
}
extension SyncExecutionSession {
    var batteryPowerSwitchDataForSync: PJEightKeySwitchData? {
        if case .batteryPowerSwitch(let data) = type { return data }; return nil
    }
    func operationType(for model: SyncCellModel) -> DeviceOperationType? {
        (model as? SyncDevicesModel)?.operationType ?? (model as? SyncDeviceStepTaskModel)?.operationType
    }
    func prepareDaylightHandles(for model: SyncCellModel, handles: [MeshMessageHandle]) -> [MeshMessageHandle] { handles }
    func batteryPowerSwitchMessageHandles(for model: SyncCellModel, defaultHandles: [MeshMessageHandle]) -> [MeshMessageHandle] { defaultHandles }
    func completeEmptyEmergencyFireControllerTaskIfNeeded(for model: SyncCellModel, messageHandles: [MeshMessageHandle]) -> Bool { false }
    func isMissingRequiredTimeSynchronizationHandle(_ model: SyncCellModel, messageHandles: [MeshMessageHandle]) -> Bool {
        operationType(for: model)?.isTimedScheduleTimeSyncOperation == true && messageHandles.isEmpty
    }
    func isBatteryPowerSwitchOwnConfiguration(_ model: SyncCellModel) -> Bool { isBatteryPowerSwitchKeyConfigConfiguration(model) }
    func isMissingRequiredBatteryPowerSwitchConfigurationHandles(_ model: SyncCellModel, messageHandles: [MeshMessageHandle]) -> Bool {
        isBatteryPowerSwitchOwnConfiguration(model) && messageHandles.isEmpty
    }
    func markBatteryPowerSwitchOwnConfigurationTasksFailed() {}
    func containsBatteryPowerSwitchConfiguration(_ device: SyncDevicesModel) -> Bool { false }
    func isBatteryPowerSwitchKeyConfigConfiguration(_ model: SyncCellModel) -> Bool {
        if case .batteryPowerSwitchKeyConfig = operationType(for: model)?.action { return true }; return false
    }
    func ackTimeout(for model: SyncCellModel) -> TimeInterval { 15 }
    func received(handle: MeshMessageHandle, statusMessage: Int, model: SyncCellModel, messageHandles: [MeshMessageHandle]) {}
    func failed(handle: MeshMessageHandle) {}
    func emergencyFireDeleteCleanupRetryPolicy(for model: SyncCellModel) -> SyncOperationResultPolicy.RetryPolicy? { nil }
    func logEmergencyFireDeleteCleanupResultIfNeeded(for model: SyncCellModel, resultMessageHandles: [MeshMessageHandle], resultSuccessful: Bool, attempt: Int, maxAttempts: Int, willRetry: Bool) {}
    func isSyncOperationSuccessful(model: SyncCellModel, resultSuccessful: Bool, operationSuccessful: Bool, messageHandles: [MeshMessageHandle]) -> Bool {
        SyncOperationResultPolicy.isSuccessful(category: .ordinary, hasMessages: !messageHandles.isEmpty, resultSuccessful: resultSuccessful, operationSuccessful: operationSuccessful)
    }
    func clearEmergencyFireControllerPendingIfNeeded(for model: SyncCellModel) {}
    func persistEmergencyFireDeleteCleanupProgressIfNeeded(for model: SyncCellModel) {}
    func persistEmergencyFireDeleteCleanupFailureIfNeeded() {}
    func finishEmergencyFireControllerSyncIfNeeded(success: Bool) {}
    func finishEmergencyFireControllerAssociationSyncIfNeeded() {}
}
