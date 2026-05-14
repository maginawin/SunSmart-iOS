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

enum EmergencyFireControllerSceneEventState: Equatable {
    case powerLossTriggered
    case powerLossStopped
    case fireAlarmTriggered
    case fireAlarmStopped
    case clear
}

struct EmergencyFireControllerSceneEvent {
    let controllerId: String
    let nodeAddress: Address
    let publishGroupAddress: Address
    let source: Address
    let destination: Address
    let sceneNumber: SceneNumber
    let state: EmergencyFireControllerSceneEventState
}

final class EmergencyFireControllerSceneEventManager {

    private static weak var current: EmergencyFireControllerSceneEventManager?
    private static var activeEmergencyControllerIds: Set<String> = []

    private let controllersProvider: () -> [DeviceEmerFireData]
    private var desiredProxyFilterAddresses: Set<Address> = []

    init(controllersProvider: @escaping () -> [DeviceEmerFireData]) {
        self.controllersProvider = controllersProvider
    }

    func activate() {
        Self.current = self
        refreshProxyFilterAddresses()
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
        guard let sceneNumber = Self.sceneNumber(from: message) else {
            return nil
        }

        guard let controller = matchingController(source: source, destination: destination),
              let nodeAddress = controller.bindNodeAddress,
              let publishGroupAddress = controller.publishGroupAddress else {
            log("ignored scene recall scene: \(sceneNumber), source: \(source.hex), destination: \(destination.hex)")
            return nil
        }

        let event = EmergencyFireControllerSceneEvent(
            controllerId: controller.id,
            nodeAddress: nodeAddress,
            publishGroupAddress: publishGroupAddress,
            source: source,
            destination: destination,
            sceneNumber: sceneNumber,
            state: Self.eventState(sceneNumber: sceneNumber, workMode: controller.configuration.workMode)
        )
        Self.updateActiveEmergencyControllers(with: event)
        NotificationCenter.default.post(name: .init(emergencyFireControllerSceneEventNotificationName), object: event)
        log("matched scene recall controller: \(controller.name), scene: \(sceneNumber), state: \(event.state), source: \(source.hex), destination: \(destination.hex)")
        return event
    }

    func refreshProxyFilterAddresses() {
        let addresses = Set(controllersProvider().compactMap { $0.publishGroupAddress })
        let proxyFilter = MeshNetworkManager.instance.proxyFilter
        let addressesToAdd = addresses.subtracting(proxyFilter.addresses)
        let addressesToRemove = desiredProxyFilterAddresses.subtracting(addresses).intersection(proxyFilter.addresses)

        desiredProxyFilterAddresses = addresses
        guard proxyFilter.proxy != nil else {
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

    static func eventState(sceneNumber: SceneNumber, workMode: EmergencyFireControllerWorkMode) -> EmergencyFireControllerSceneEventState {
        switch workMode {
        case .powerLossEmergency:
            switch sceneNumber {
            case DeviceEmerFireData.powerLossTriggerSceneNumber:
                return .powerLossTriggered
            case DeviceEmerFireData.powerLossStopSceneNumber:
                return .powerLossStopped
            default:
                return .clear
            }
        case .fireAlarmEmergency:
            switch sceneNumber {
            case DeviceEmerFireData.fireAlarmTriggerSceneNumber:
                return .fireAlarmTriggered
            case DeviceEmerFireData.fireAlarmStopSceneNumber:
                return .fireAlarmStopped
            default:
                return .clear
            }
        case .allDisabled:
            return .clear
        }
    }

    private func matchingController(source: Address, destination: Address) -> DeviceEmerFireData? {
        controllersProvider().first { controller in
            guard controller.publishGroupAddress == destination,
                  let node = controller.bindNode else {
                return false
            }
            return node.primaryUnicastAddress == source || node.contains(elementWithAddress: source)
        }
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
        case .powerLossStopped, .fireAlarmStopped, .clear:
            activeEmergencyControllerIds.remove(event.controllerId)
        }
        notifyManualControlStateDidChangeIfNeeded(oldIds: oldIds)
    }

    private static func activeEmergencyControllers(in manager: EmergencyFireControllerSceneEventManager) -> [DeviceEmerFireData] {
        manager.controllersProvider().filter {
            activeEmergencyControllerIds.contains($0.id) && $0.configuration.workMode != .allDisabled
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
        publishGroups.contains { publishGroup in
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
}
