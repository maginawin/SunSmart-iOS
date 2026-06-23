//
//  EmergencyFireControllerSceneEventManager.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

let emergencyFireControllerSceneEventNotificationName = "emergencyFireControllerSceneEventNotification"
let emergencyFireControllerManualControlStateDidChangeNotificationName = "emergencyFireControllerManualControlStateDidChangeNotification"

/// EFC 场景事件的业务态。
/// 控制器实际发出来的是 SceneRecall，这里根据 v2 保留场景号翻译成页面能理解的状态。
enum EmergencyFireControllerSceneEventState: Equatable {
    case powerLossTriggered
    case fireAlarmTriggered
    case restored
    case clear
}

/// 一次由 EFC 发出的应急场景事件。
/// source 是真实 EFC 节点或元素地址，destination 应该是该 EFC 的内部 publish group。
struct EmergencyFireControllerSceneEvent {
    let controllerId: String
    let nodeAddress: Address
    let publishGroupAddress: Address
    let source: Address
    let destination: Address
    let sceneNumber: SceneNumber
    let state: EmergencyFireControllerSceneEventState
}

/// 应急火警场景事件管理器。
///
/// 这个类有两条核心职责：
/// 1. 监听 Mesh 中 EFC 发往内部 publish group 的 SceneRecall，把它转换成监控页状态事件；
/// 2. 维护 proxy filter，把所有 EFC 内部 publish group 加进去，否则手机可能收不到这些组播消息。
///
/// 注意：它不负责发送同步消息，也不负责创建/删除 publish group；那些由 DeviceEmerFireData+Sync
/// 和 EmergencyFireControllerSyncPlanner 处理。
final class EmergencyFireControllerSceneEventManager {

    private static weak var current: EmergencyFireControllerSceneEventManager?
    /// 当前处于 emergency/fire active 状态的控制器 id。
    /// 这个集合用于判断是否需要拦截关联灯组的普通手动控制。
    private static var activeEmergencyControllerIds: Set<String> = []

    private enum ControllerMatchResult {
        case matched(DeviceEmerFireData)
        case failed(reason: String)
    }

    /// 外部注入控制器列表，避免 Manager 直接依赖某个页面或 Store 的生命周期。
    private let controllersProvider: () -> [DeviceEmerFireData]
    /// App 希望 proxy filter 当前包含的 EFC 内部 publish group 地址。
    /// proxy 连接重建后需要用这个集合补加地址。
    private var desiredProxyFilterAddresses: Set<Address> = []

    init(controllersProvider: @escaping () -> [DeviceEmerFireData]) {
        self.controllersProvider = controllersProvider
    }

    func activate() {
        Self.current = self
        refreshProxyFilterAddresses()
        // proxy 可能在页面/空间初始化之后才真正连接，延迟重试能覆盖这个时序问题。
        scheduleProxyFilterRefreshRetries()
        log("activated")
    }

    func deactivate() {
        removeProxyFilterAddresses()
        controllersProvider().forEach {
            Self.activeEmergencyControllerIds.remove($0.id)
        }
        if Self.current === self {
            Self.current = nil
        }
        log("deactivated")
    }

    static func dispatch(message: any MeshMessage, source: Address, destination: Address) {
        current?.handle(message: message, source: source, destination: destination)
    }

    static func refreshProxyFilterAddresses() {
        current?.refreshProxyFilterAddresses()
    }

    static func isManualControlBlocked(for group: Group) -> Bool {
        guard let current else { return false }
        let publishGroups = activeEmergencyPublishGroups(in: current)
        // 只要组内任意灯仍订阅 active EFC 的内部 publish group，就认为普通手动控制有安全风险。
        return group.nodes.contains {
            isSubscribedToEmergencyPublishGroup($0, publishGroups: publishGroups)
        }
    }

    static func isManualControlBlocked(for groups: [Group]) -> Bool {
        guard let current else { return false }
        let publishGroups = activeEmergencyPublishGroups(in: current)
        return groups.contains { group in
            group.nodes.contains {
                isSubscribedToEmergencyPublishGroup($0, publishGroups: publishGroups)
            }
        }
    }

    static func isManualControlBlocked(for node: Node) -> Bool {
        guard let current else { return false }
        return isSubscribedToEmergencyPublishGroup(node, publishGroups: activeEmergencyPublishGroups(in: current))
    }

    static var hasManualControlBlockedGroups: Bool {
        guard let current else { return false }
        let publishGroups = activeEmergencyPublishGroups(in: current)
        return MeshNetworkManager.instance.realNodes.contains {
            isSubscribedToEmergencyPublishGroup($0, publishGroups: publishGroups)
        }
    }

    static func updateManualControlBlocked(controllerId: String?, blocked: Bool) {
        guard let controllerId else { return }
        let oldIds = activeEmergencyControllerIds
        if blocked {
            activeEmergencyControllerIds.insert(controllerId)
        } else {
            activeEmergencyControllerIds.remove(controllerId)
        }
        notifyManualControlStateDidChangeIfNeeded(oldIds: oldIds)
    }

    @discardableResult
    func handle(message: any MeshMessage, source: Address, destination: Address) -> EmergencyFireControllerSceneEvent? {
        // 当前只关心 EFC 触发/停止使用的 SceneRecall。
        // 其它 Mesh 状态消息会由各自页面/模型处理。
        guard let sceneNumber = Self.sceneNumber(from: message) else {
            return nil
        }

        // EFC 的 Scene Client publication 会发到它自己的内部 publish group。
        // 只有 source 能匹配绑定节点，且 destination 能匹配 publishGroupAddress，才认为是本业务事件。
        let matchResult = controllerMatchResult(source: source, destination: destination)
        guard case .matched(let controller) = matchResult,
              let nodeAddress = controller.bindNodeAddress,
              let publishGroupAddress = controller.publishGroupAddress else {
            let reason: String
            if case .failed(let matchReason) = matchResult {
                reason = matchReason
            } else {
                reason = "invalidControllerData"
            }
            log("ignored reason=\(reason) source=\(Self.addressDescription(source)) target=\(Self.addressDescription(destination)) scene=\(Self.sceneDescription(sceneNumber))")
            return nil
        }

        let event = EmergencyFireControllerSceneEvent(
            controllerId: controller.id,
            nodeAddress: nodeAddress,
            publishGroupAddress: publishGroupAddress,
            source: source,
            destination: destination,
            sceneNumber: sceneNumber,
            state: Self.eventState(sceneNumber: sceneNumber)
        )
        Self.updateActiveEmergencyControllers(with: event)
        // 监控页通过这个通知进入 triggered/resuming/normal 等显示态。
        NotificationCenter.default.post(name: .init(emergencyFireControllerSceneEventNotificationName), object: event)
        log("matched controller=\(controller.name) source=\(Self.addressDescription(source)) target=\(Self.addressDescription(destination)) scene=\(Self.sceneDescription(sceneNumber)) state=\(event.state)")
        return event
    }

    func refreshProxyFilterAddresses() {
        // 为了收到 EFC 发往内部 virtual group 的组播，手机 proxy filter 必须包含这些 group 地址。
        let addresses = Set(controllersProvider().compactMap { $0.publishGroupAddress })
        let proxyFilter = MeshNetworkManager.instance.proxyFilter
        let addressesToAdd = addresses.subtracting(proxyFilter.addresses)
        let addressesToRemove = desiredProxyFilterAddresses.subtracting(addresses).intersection(proxyFilter.addresses)

        desiredProxyFilterAddresses = addresses
        guard proxyFilter.proxy != nil else {
            // proxy 还没连上时先记 desired addresses，后续 activate 的延迟重试会再补。
            log("proxy filter pending, desired addresses: \(Self.addressesDescription(addresses))")
            return
        }

        addressesToRemove.forEach { proxyFilter.remove(address: $0) }
        if !addressesToRemove.isEmpty {
            log("removed proxy filter addresses: \(Self.addressesDescription(addressesToRemove))")
        }

        addressesToAdd.forEach { proxyFilter.add(address: $0) }
        if !addressesToAdd.isEmpty {
            log("added proxy filter addresses: \(Self.addressesDescription(addressesToAdd))")
        } else {
            log("proxy filter already contains desired addresses: \(Self.addressesDescription(addresses))")
        }
    }

    static func sceneNumber(from message: any MeshMessage) -> SceneNumber? {
        if let recall = message as? SceneRecall {
            return recall.scene
        }
        if let recall = message as? SceneRecallUnacknowledged {
            return recall.scene
        }
        return nil
    }

    static func eventState(sceneNumber: SceneNumber) -> EmergencyFireControllerSceneEventState {
        switch sceneNumber {
        case DeviceEmerFireData.powerLossTriggerSceneNumber:
            return .powerLossTriggered
        case DeviceEmerFireData.fireAlarmTriggerSceneNumber:
            return .fireAlarmTriggered
        case DeviceEmerFireData.restoreSceneNumber:
            return .restored
        default:
            return .clear
        }
    }

    private func controllerMatchResult(source: Address, destination: Address) -> ControllerMatchResult {
        let controllers = controllersProvider()
        guard !controllers.isEmpty else {
            return .failed(reason: "noController")
        }

        var hasLinkedController = false
        var hasTargetMatch = false
        var hasSourceMatch = false

        for controller in controllers {
            guard let node = controller.bindNode else {
                continue
            }

            hasLinkedController = true
            let sourceMatches = node.primaryUnicastAddress == source || node.contains(elementWithAddress: source)
            let targetMatches = controller.publishGroupAddress == destination

            hasSourceMatch = hasSourceMatch || sourceMatches
            hasTargetMatch = hasTargetMatch || targetMatches

            if sourceMatches && targetMatches {
                return .matched(controller)
            }
        }

        if !hasLinkedController {
            return .failed(reason: "noLinkedController")
        }
        if !hasTargetMatch {
            return .failed(reason: "targetMismatch")
        }
        if !hasSourceMatch {
            return .failed(reason: "sourceMismatch")
        }
        return .failed(reason: "noMatchingController")
    }

    private func removeProxyFilterAddresses() {
        let proxyFilter = MeshNetworkManager.instance.proxyFilter
        let addresses = desiredProxyFilterAddresses.intersection(proxyFilter.addresses)
        addresses.forEach {
            proxyFilter.remove(address: $0)
        }
        if !addresses.isEmpty {
            log("removed proxy filter addresses: \(Self.addressesDescription(addresses))")
        }
        desiredProxyFilterAddresses.removeAll()
    }

    private func scheduleProxyFilterRefreshRetries() {
        [1.0, 3.0, 6.0].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, Self.current === self else { return }
                refreshProxyFilterAddresses()
            }
        }
    }

    private static func updateActiveEmergencyControllers(with event: EmergencyFireControllerSceneEvent) {
        let oldIds = activeEmergencyControllerIds
        switch event.state {
        case .powerLossTriggered, .fireAlarmTriggered:
            activeEmergencyControllerIds.insert(event.controllerId)
        case .restored, .clear:
            activeEmergencyControllerIds.remove(event.controllerId)
        }
        notifyManualControlStateDidChangeIfNeeded(oldIds: oldIds)
    }

    private static func activeEmergencyControllers(in manager: EmergencyFireControllerSceneEventManager) -> [DeviceEmerFireData] {
        manager.controllersProvider().filter {
            activeEmergencyControllerIds.contains($0.id)
        }
    }

    private static func activeEmergencyPublishGroups(in manager: EmergencyFireControllerSceneEventManager) -> [Group] {
        activeEmergencyControllers(in: manager).compactMap { controller in
            guard let publishGroupAddress = controller.publishGroupAddress else {
                return nil
            }
            return MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(publishGroupAddress))
        }
    }

    private static func isSubscribedToEmergencyPublishGroup(_ node: Node, publishGroups: [Group]) -> Bool {
        // 当前拦截依据是灯节点是否仍订阅 active EFC 的业务控制组。
        // Scene Server 只作为历史订阅兼容，新的联动以 Lightness / Light LC 为准。
        publishGroups.contains { publishGroup in
            node.lightnessModel?.isSubscribed(to: publishGroup) == true ||
            node.lightLCModel?.isSubscribed(to: publishGroup) == true ||
            node.sceneModel?.isSubscribed(to: publishGroup) == true
        }
    }

    private static func notifyManualControlStateDidChangeIfNeeded(oldIds: Set<String>) {
        guard oldIds != activeEmergencyControllerIds else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .init(emergencyFireControllerManualControlStateDidChangeNotificationName), object: nil)
        }
    }

    private func log(_ message: String) {
        print("[EFC Scene] \(message)")
    }

    private static func addressesDescription(_ addresses: Set<Address>) -> String {
        guard !addresses.isEmpty else { return "[]" }
        return "[" + addresses.sorted().map { $0.hex }.joined(separator: ", ") + "]"
    }

    private static func sceneDescription(_ sceneNumber: SceneNumber) -> String {
        "0x\(sceneNumber.hex)"
    }

    private static func addressDescription(_ address: Address) -> String {
        "0x\(address.hex)"
    }
}
