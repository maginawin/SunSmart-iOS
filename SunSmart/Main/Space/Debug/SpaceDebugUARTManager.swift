//
//  SpaceDebugUARTManager.swift
//  SunSmart
//
//  Created on 2026/5/18.
//

import Foundation
import NordicSigMeshSDK

struct SpaceDebugUARTDeviceKey: Hashable {
    let siteId: String
    let spaceId: String
    let address: Address
}

enum SpaceDebugUARTManagerEvent {
    case stateChanged
    case messageAppended(SpaceDebugUARTDeviceKey, SpaceDebugUARTMessage)
    case bufferChanged(SpaceDebugUARTDeviceKey)
    case allCleared
}

struct SpaceDebugUARTDeviceBuffer {
    var messages: [SpaceDebugUARTMessage] = []
    var droppedMessageCount: Int = 0
    var lastActiveAt: Date = Date()
}

final class SpaceDebugUARTManager {
    static let shared = SpaceDebugUARTManager()

    private let perDeviceMessageTrimThreshold = 100_000
    private let perDeviceMessageTrimTarget = 80_000
    private let deviceBufferLimit = 30

    private var observers: [UUID: (SpaceDebugUARTManagerEvent) -> Void] = [:]
    private var buffers: [SpaceDebugUARTDeviceKey: SpaceDebugUARTDeviceBuffer] = [:]
    private var activeSiteId: String?
    private weak var activeSpace: SpaceData?
    private var currentKey: SpaceDebugUARTDeviceKey?
    private var currentEvaluationID = UUID()
    private var meshConnectionObservation: NSKeyValueObservation?

    private(set) var isReceiveEnabled = false
    private(set) var currentSupportState: SpaceDebugUARTSupportViewState = .disconnected
    private(set) var isCurrentProxyNotifying = false

    private init() {
        observeMeshConnection()
    }

    @discardableResult
    func observe(_ observer: @escaping (SpaceDebugUARTManagerEvent) -> Void) -> UUID {
        let token = UUID()
        observers[token] = observer
        observer(.stateChanged)
        return token
    }

    func removeObserver(_ token: UUID?) {
        guard let token else {
            return
        }
        observers[token] = nil
    }

    func key(siteId: String, spaceId: String, address: Address) -> SpaceDebugUARTDeviceKey {
        SpaceDebugUARTDeviceKey(siteId: siteId, spaceId: spaceId, address: address)
    }

    func key(space: SpaceData, node: Node) -> SpaceDebugUARTDeviceKey {
        key(siteId: space.siteId, spaceId: space.id, address: node.primaryUnicastAddress)
    }

    func cachedMessages(for key: SpaceDebugUARTDeviceKey) -> [SpaceDebugUARTMessage] {
        buffers[key]?.messages ?? []
    }

    func droppedMessageCount(for key: SpaceDebugUARTDeviceKey) -> Int {
        buffers[key]?.droppedMessageCount ?? 0
    }

    func hasCache(for key: SpaceDebugUARTDeviceKey) -> Bool {
        !(buffers[key]?.messages.isEmpty ?? true)
    }

    func cachedKeys(siteId: String, spaceId: String) -> Set<Address> {
        Set(buffers.keys
            .filter { $0.siteId == siteId && $0.spaceId == spaceId && hasCache(for: $0) }
            .map(\.address))
    }

    func activateSite(_ siteId: String) {
        if activeSiteId != siteId {
            resetAll()
            activeSiteId = siteId
        }
    }

    func endSite(_ siteId: String) {
        guard activeSiteId == siteId else {
            return
        }
        resetAll()
        activeSiteId = nil
        activeSpace = nil
    }

    func setActiveSpace(_ space: SpaceData) {
        activateSite(space.siteId)
        activeSpace = space
    }

    func resetAll() {
        stopCurrentNotifications()
        isReceiveEnabled = false
        currentSupportState = .disconnected
        currentKey = nil
        buffers.removeAll()
        notify(.allCleared)
        notify(.stateChanged)
    }

    func setReceiveEnabled(_ enabled: Bool, space: SpaceData?) {
        isReceiveEnabled = enabled
        if let space {
            setActiveSpace(space)
        }
        if enabled {
            evaluateCurrentProxy(space: space ?? activeSpace)
        } else {
            stopCurrentNotifications()
            notify(.stateChanged)
        }
    }

    func clearMessages(for key: SpaceDebugUARTDeviceKey) {
        guard buffers[key] != nil else {
            return
        }
        buffers[key]?.messages.removeAll()
        buffers[key]?.droppedMessageCount = 0
        buffers[key]?.lastActiveAt = Date()
        notify(.bufferChanged(key))
        notify(.stateChanged)
    }

    func evaluateCurrentProxy(space: SpaceData?) {
        if let space {
            setActiveSpace(space)
        }

        guard let space = space ?? activeSpace else {
            stopCurrentNotifications()
            currentSupportState = .disconnected
            currentKey = nil
            notify(.stateChanged)
            return
        }

        guard activeSiteId == nil || activeSiteId == space.siteId else {
            stopCurrentNotifications()
            currentSupportState = .disconnected
            currentKey = nil
            notify(.stateChanged)
            return
        }

        guard let proxy = MeshLibManager.manager.currentProxy,
              let node = proxy.node,
              MeshNetworkManager.instance.realNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) else {
            stopCurrentNotifications()
            currentSupportState = .disconnected
            currentKey = nil
            notify(.stateChanged)
            return
        }

        let key = key(space: space, node: node)
        currentKey = key
        currentSupportState = .checking
        notify(.stateChanged)

        let evaluationID = UUID()
        currentEvaluationID = evaluationID
        proxy.discoverDebugUARTService { [weak self] state in
            DispatchQueue.main.async {
                guard let self, self.currentEvaluationID == evaluationID else {
                    return
                }
                let mappedState = Self.mapUARTState(state)
                self.currentSupportState = mappedState
                guard case .supported = mappedState else {
                    self.stopCurrentNotifications()
                    self.notify(.stateChanged)
                    return
                }
                if self.isReceiveEnabled {
                    self.startNotifications(proxy: proxy, key: key)
                } else {
                    self.notify(.stateChanged)
                }
            }
        }
    }

    private func startNotifications(proxy: GattBearer, key: SpaceDebugUARTDeviceKey) {
        ensureBufferExists(for: key)
        buffers[key]?.lastActiveAt = Date()
        isCurrentProxyNotifying = true
        notify(.stateChanged)

        proxy.startDebugUARTMessages(onMessage: { [weak self] message in
            DispatchQueue.main.async {
                guard let self, self.isReceiveEnabled, self.currentKey == key else {
                    return
                }
                let viewMessage = SpaceDebugUARTMessage(text: message.text, timestamp: message.timestamp)
                self.append(viewMessage, for: key)
            }
        }, completion: { [weak self] state in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                let mappedState = Self.mapUARTState(state)
                self.currentSupportState = mappedState
                self.isCurrentProxyNotifying = mappedState == .supported && self.isReceiveEnabled
                self.notify(.stateChanged)
            }
        })
    }

    private func stopCurrentNotifications() {
        isCurrentProxyNotifying = false
        MeshLibManager.manager.currentProxy?.stopDebugUARTMessages()
    }

    private func ensureBufferExists(for key: SpaceDebugUARTDeviceKey) {
        if buffers[key] != nil {
            buffers[key]?.lastActiveAt = Date()
            return
        }
        if buffers.count >= deviceBufferLimit,
           let keyToRemove = buffers.min(by: { $0.value.lastActiveAt < $1.value.lastActiveAt })?.key {
            buffers.removeValue(forKey: keyToRemove)
            notify(.bufferChanged(keyToRemove))
        }
        buffers[key] = SpaceDebugUARTDeviceBuffer(lastActiveAt: Date())
        notify(.bufferChanged(key))
    }

    private func append(_ message: SpaceDebugUARTMessage, for key: SpaceDebugUARTDeviceKey) {
        ensureBufferExists(for: key)
        buffers[key]?.messages.append(message)
        buffers[key]?.lastActiveAt = Date()
        trimMessagesIfNeeded(for: key)
        notify(.messageAppended(key, message))
    }

    private func trimMessagesIfNeeded(for key: SpaceDebugUARTDeviceKey) {
        guard let count = buffers[key]?.messages.count, count > perDeviceMessageTrimThreshold else {
            return
        }
        let removeCount = count - perDeviceMessageTrimTarget
        buffers[key]?.messages.removeFirst(removeCount)
        buffers[key]?.droppedMessageCount += removeCount
        notify(.bufferChanged(key))
    }

    private func observeMeshConnection() {
        meshConnectionObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                if MeshLibManager.manager.isMeshNetworkConnected {
                    self.evaluateCurrentProxy(space: self.activeSpace)
                } else {
                    self.stopCurrentNotifications()
                    self.currentSupportState = .disconnected
                    self.currentKey = nil
                    self.notify(.stateChanged)
                }
            }
        }
    }

    private func notify(_ event: SpaceDebugUARTManagerEvent) {
        observers.values.forEach { $0(event) }
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
