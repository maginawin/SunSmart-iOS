//
//  DebugBluetoothSession.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import Foundation
import NordicSigMeshSDK

final class DebugBluetoothSession {
    var onUnexpectedDisconnect: ((Node) -> Void)?

    private let space: SpaceData
    private let uartMessageTrimThreshold = 100_000
    private let uartMessageTrimTarget = 80_000
    private var connectedNode: Node?
    private var isEnding = false
    private var isConnecting = false
    private var meshConnectionObservation: NSKeyValueObservation?
    private var uartMessageHandler: ((SpaceDebugUARTMessage) -> Void)?

    private(set) var uartMessages: [SpaceDebugUARTMessage] = []
    private(set) var droppedUARTMessageCount = 0
    private(set) var isReceivingUARTMessages = false

    init(space: SpaceData) {
        self.space = space
        observeMeshConnection()
    }

    deinit {
        finish()
    }

    func prepare(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            MeshLibManager.manager.stopRefreshNodesRSSI()
            MeshLibManager.manager.meshNetworkDisconnect()
            MeshLibManager.manager.setMeshNetworkConnected(meshUUID: self.space.meshUUID, subNetworkId: self.space.meshNetworkId, connected: false)

            guard let manager = MeshLibManager.manager.meshNetworkManager else {
                completion(false)
                return
            }

            manager.loadExtensionData { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }

    func startScan(onNodeFound: @escaping (MeshNodePeripheralData) -> Void) {
        MeshLibManager.manager.stopRefreshNodesRSSI()
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 99999, nodeScan: { data in
            DispatchQueue.main.async {
                onNodeFound(data)
            }
        }, finished: nil)
    }

    func stopScan() {
        MeshLibManager.manager.stopRefreshNodesRSSI()
    }

    func connect(_ item: SpaceDebugNodeItem, completion: @escaping (Bool) -> Void) {
        stopScan()
        connectedNode = item.node
        isConnecting = true
        MeshLibManager.manager.connectProxy(node: item.node, peripheral: item.peripheral) { [weak self] success in
            DispatchQueue.main.async {
                self?.isConnecting = false
                if !success {
                    self?.connectedNode = nil
                }
                completion(success)
            }
        }
    }

    func reconnect(completion: @escaping (Bool) -> Void) {
        guard let node = connectedNode else {
            completion(false)
            return
        }
        isConnecting = true
        MeshLibManager.manager.connectProxy(node: node) { [weak self] success in
            DispatchQueue.main.async {
                self?.isConnecting = false
                completion(success)
            }
        }
    }

    func checkUARTSupport(completion: @escaping (SpaceDebugUARTSupportViewState) -> Void) {
        guard let proxy = MeshLibManager.manager.currentProxy else {
            completion(.disconnected)
            return
        }
        proxy.discoverDebugUARTService { state in
            DispatchQueue.main.async {
                completion(Self.mapUARTState(state))
            }
        }
    }

    func startUARTMessages(
        onMessage: @escaping (SpaceDebugUARTMessage) -> Void,
        completion: @escaping (SpaceDebugUARTSupportViewState) -> Void
    ) {
        guard let proxy = MeshLibManager.manager.currentProxy else {
            completion(.disconnected)
            return
        }
        uartMessageHandler = onMessage
        isReceivingUARTMessages = true
        proxy.startDebugUARTMessages(onMessage: { [weak self] message in
            DispatchQueue.main.async {
                guard let self = self, self.isReceivingUARTMessages else {
                    return
                }
                let viewMessage = SpaceDebugUARTMessage(text: message.text, timestamp: message.timestamp)
                self.appendUARTMessage(viewMessage)
            }
        }, completion: { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion(Self.mapUARTState(state))
                    return
                }
                let mappedState = Self.mapUARTState(state)
                if case .supported = mappedState {
                    self.isReceivingUARTMessages = true
                } else {
                    self.isReceivingUARTMessages = false
                    self.uartMessageHandler = nil
                }
                completion(mappedState)
            }
        })
    }

    func stopUARTMessages() {
        isReceivingUARTMessages = false
        uartMessageHandler = nil
        MeshLibManager.manager.currentProxy?.stopDebugUARTMessages()
    }

    func cachedUARTMessages() -> [SpaceDebugUARTMessage] {
        return uartMessages
    }

    func clearUARTMessages() {
        uartMessages.removeAll()
        droppedUARTMessageCount = 0
    }

    func finish() {
        guard !isEnding else {
            return
        }
        isEnding = true
        stopUARTMessages()
        clearUARTMessages()
        stopScan()
        if connectedNode != nil {
            MeshLibManager.manager.close()
        }
        MeshLibManager.manager.meshNetworkDisconnect()
        connectedNode = nil
        meshConnectionObservation = nil
    }

    private func appendUARTMessage(_ message: SpaceDebugUARTMessage) {
        uartMessages.append(message)
        trimUARTMessagesIfNeeded()
        uartMessageHandler?(message)
    }

    private func trimUARTMessagesIfNeeded() {
        guard uartMessages.count > uartMessageTrimThreshold else {
            return
        }
        let removeCount = uartMessages.count - uartMessageTrimTarget
        uartMessages.removeFirst(removeCount)
        droppedUARTMessageCount += removeCount
    }

    private func observeMeshConnection() {
        meshConnectionObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new]) { [weak self] _, _ in
            guard let self = self else {
                return
            }
            DispatchQueue.main.async {
                guard !self.isEnding, !self.isConnecting, !MeshLibManager.manager.isMeshNetworkConnected, let node = self.connectedNode else {
                    return
                }
                self.onUnexpectedDisconnect?(node)
            }
        }
    }

    private static func mapUARTState(_ state: DebugUARTSupportState) -> SpaceDebugUARTSupportViewState {
        switch state {
        case .supported:
            return .supported
        case .unsupported:
            return .unsupported
        case .disconnected:
            return .disconnected
        case .discoveryFailed(let message):
            return .failed(message)
        }
    }
}
