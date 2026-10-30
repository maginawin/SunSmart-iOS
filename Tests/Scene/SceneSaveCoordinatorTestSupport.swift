import Foundation
final class SyncExecutionEnvironment { var configurationIsCurrent: () -> Bool = { true } }
class SyncDevicesModel {
    enum State { case successful, failed }
    var state: State = .successful
    init(name: String, address: UInt16) {}
}
final class SyncDevicesSectionModel {
    var devices: [SyncDevicesModel] = []
    init(title: String) {}
}
final class SyncExecutionSession {
    enum Kind { case devices([Node]), scene(Scene) }
    enum State { case syncSuccess, syncFailure }
    static var formalStarts = 0
    static var sent: [MeshMessageHandle] = []
    static var pendingStop: (() -> Void)?
    static var deferStop = false
    static var deferFormal = false
    static var lateInvalidation: (() -> Void)?
    static var lateFormal: (() -> Void)?
    let kind: Kind
    var publishesCloudChange = true
    var parameterOnlyOperations: [ObjectIdentifier: () -> [MeshMessageHandle]] = [:]
    var sections: [SyncDevicesSectionModel] = []
    var onStopped: (() -> Void)?
    var onPlanInvalidated: (() -> Void)?
    var onSettled: ((State) -> Void)?
    let environment: SyncExecutionEnvironment
    init(type: Kind, reSync: Bool, environment: SyncExecutionEnvironment) { self.environment = environment; kind = type }
    func start() {
        if case .scene = kind { Self.formalStarts += 1 }
        guard environment.configurationIsCurrent() else { onPlanInvalidated?(); return }
        for section in sections { for model in section.devices {
            let handles = parameterOnlyOperations[ObjectIdentifier(model)]?() ?? []
            Self.sent += handles
            model.state = handles.isEmpty ? .failed : .successful
        } }
        if case .scene = kind, Self.deferFormal {
            Self.lateInvalidation = onPlanInvalidated
            let callback = onSettled; Self.lateFormal = { callback?(.syncSuccess) }
        } else { onSettled?(.syncSuccess) }
    }
    func close() { if Self.deferStop { Self.pendingStop = onStopped } else { onStopped?() } }
}
struct SyncSceneScheduleTaskBuilder {
    func appendScene(to: SyncDevicesSectionModel, removal: SyncDevicesSectionModel, scene: Scene) {}
}
extension Scene { var needSync: Bool { !(info.configuration?.pendingOperations.isEmpty ?? true) } }
