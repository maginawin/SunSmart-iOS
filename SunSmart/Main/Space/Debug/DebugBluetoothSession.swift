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
    private var connectedNode: Node?
    private var isEnding = false
    private var isConnecting = false
    private var meshConnectionObservation: NSKeyValueObservation?

    init(space: SpaceData) {
        self.space = space
        observeMeshConnection()
    }

    deinit {
        finish()
    }

    func prepare(completion: @escaping (Bool, Node?) -> Void) {
        DispatchQueue.main.async {
            MeshLibManager.manager.stopRefreshNodesRSSI()
            let currentNode = self.currentConnectedNodeInSpace()
            self.connectedNode = currentNode

            guard let manager = MeshLibManager.manager.meshNetworkManager else {
                completion(false, currentNode)
                return
            }

            manager.loadExtensionData { result in
                DispatchQueue.main.async {
                    completion(result, currentNode)
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

    func currentConnectedNodeInSpace() -> Node? {
        guard let node = MeshLibManager.manager.currentProxy?.node else {
            return nil
        }
        guard MeshNetworkManager.instance.realNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) else {
            return nil
        }
        return node
    }

    func connect(_ item: SpaceDebugNodeItem, completion: @escaping (Bool) -> Void) {
        stopScan()
        if MeshLibManager.manager.currentProxy?.node?.primaryUnicastAddress == item.node.primaryUnicastAddress {
            connectedNode = item.node
            completion(true)
            return
        }

        connectedNode = item.node
        isConnecting = true
        if MeshLibManager.manager.currentProxy != nil {
            MeshLibManager.manager.close()
        }

        MeshLibManager.manager.connectProxy(node: item.node, peripheral: item.peripheral) { [weak self] success in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion(success)
                    return
                }
                self.isConnecting = false
                if !success {
                    self.connectedNode = self.currentConnectedNodeInSpace()
                } else {
                    self.connectedNode = item.node
                    SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: self.space)
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
                guard let self = self else {
                    completion(success)
                    return
                }
                self.isConnecting = false
                if success {
                    self.connectedNode = node
                    SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: self.space)
                }
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

    func finish() {
        guard !isEnding else {
            return
        }
        isEnding = true
        stopScan()
        connectedNode = nil
        meshConnectionObservation = nil
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
                self.connectedNode = nil
                self.onUnexpectedDisconnect?(node)
                MeshLibManager.manager.close()
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
