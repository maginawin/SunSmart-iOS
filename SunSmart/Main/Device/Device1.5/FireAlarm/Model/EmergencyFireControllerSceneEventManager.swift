//
//  EmergencyFireControllerSceneEventManager.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

let emergencyFireControllerSceneEventNotificationName = "emergencyFireControllerSceneEventNotification"

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

    private func log(_ message: String) {
        print("[EFC Scene] \(message)")
    }

    private static func addressesDescription(_ addresses: Set<Address>) -> String {
        guard !addresses.isEmpty else { return "[]" }
        return "[" + addresses.sorted().map { $0.hex }.joined(separator: ", ") + "]"
    }
}
