//
//  WiFiFirmwareDFUCoordinator.swift
//  SunSmart
//
//  Created by Codex on 2026/7/15.
//

import Foundation
import NordicSigMeshSDK

final class WiFiFirmwareDFUCoordinator {

    enum Event {
        case loadingStart(Bool)
        case currentVersionLoading
        case currentVersion(String)
        case currentVersionFailed
        case updateState(WiFiFirmwareUpdatingState)
        case idle
        case confirmedVersion(String)
    }

    var onEvent: ((Event) -> Void)?

    private let node: Node
    private let sessionStore: WiFiFirmwareDFUSessionStore
    private let networkUUID: UUID?
    private let nodeAddress: UInt16

    private var observerID: UUID?
    private var pollWorkItem: DispatchWorkItem?
    private var generation = 0
    private var requestInFlight = false
    private var consecutiveQueryFailures = 0
    private var isActive = false
    private var session: WiFiFirmwareDFUSession?

    init(
        node: Node,
        sessionStore: WiFiFirmwareDFUSessionStore = .init()
    ) {
        self.node = node
        self.sessionStore = sessionStore
        self.networkUUID = MeshNetworkManager.instance.meshNetwork?.uuid
        self.nodeAddress = node.primaryUnicastAddress
        if let networkUUID {
            self.session = sessionStore.load(networkUUID: networkUUID, nodeAddress: node.primaryUnicastAddress)
        }
    }

    deinit {
        pollWorkItem?.cancel()
        MeshLibManager.manager.removeGlobalMessageObserver(observerID)
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        registerObserverIfNeeded()
        refresh()
    }

    func deactivate() {
        isActive = false
        generation += 1
        requestInFlight = false
        cancelPoll()
        MeshLibManager.manager.removeGlobalMessageObserver(observerID)
        observerID = nil
    }

    func refresh() {
        guard isActive else { return }
        generation += 1
        requestInFlight = false
        cancelPoll()
        consecutiveQueryFailures = 0
        let requestGeneration = generation
        let hadAcceptedSession = session?.accepted == true && session?.terminalConsumed == false
        if let lastState = session?.lastState, hadAcceptedSession {
            emit(.updateState(lastState))
        }
        queryDFUStatus(generation: requestGeneration) { [weak self] status in
            guard let self, self.isCurrent(requestGeneration) else { return }
            if let status, self.restoreMatchingSession(from: status) {
                self.scheduleNextPoll(after: 2)
            } else if status == nil, hadAcceptedSession {
                self.handleQueryFailure()
            } else {
                self.queryCurrentVersion(generation: requestGeneration)
            }
        }
    }

    func start(filename: String, version: String) {
        guard isActive else { return }
        generation += 1
        requestInFlight = false
        cancelPoll()
        clearSession()
        consecutiveQueryFailures = 0
        let requestGeneration = generation
        emit(.loadingStart(true))

        let metadata: WiFiGatewayDFUMetadata
        let firmwareID: String
        do {
            let url = try WiFiFirmwareDFUMetadataBuilder.makeURL(filename: filename)
            firmwareID = try WiFiFirmwareDFUMetadataBuilder.firmwareID(version: version)
            metadata = try WiFiGatewayDFUMetadata(url: url, firmwareID: firmwareID)
        } catch {
            emit(.loadingStart(false))
            emit(.updateState(.init(kind: .upgradeFailed, percent: 0)))
            return
        }

        guard let vendorModel = validVendorModel() else {
            emit(.loadingStart(false))
            emit(.updateState(.init(kind: .connFailedTimeout, percent: 0)))
            return
        }

        requestInFlight = true
        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .wifiGatewayDFUStart(metadata)),
            model: vendorModel,
            timeout: 10
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.requestInFlight = false
                self.emit(.loadingStart(false))
                guard let status = response as? SunricherVendorStatus,
                      case .wifiGatewayDFUStart(let result) = status.status.parameters else {
                    self.emit(.updateState(.init(kind: .connFailedTimeout, percent: 0)))
                    return
                }
                self.handleStartResult(result, firmwareID: firmwareID, generation: requestGeneration)
            }
        }
    }

    func consumeSuccess() {
        guard let networkUUID else { return }
        session?.terminalConsumed = true
        sessionStore.remove(networkUUID: networkUUID, nodeAddress: nodeAddress)
        session = nil
        cancelPoll()
        emit(.idle)
    }

    private func handleStartResult(
        _ result: WiFiGatewayDFUStartResult,
        firmwareID: String,
        generation requestGeneration: Int
    ) {
        switch result {
        case .accepted:
            let initialState = WiFiFirmwareUpdatingState(kind: .downloading, percent: 0)
            session = WiFiFirmwareDFUSession(
                targetFirmwareID: firmwareID,
                accepted: true,
                lastState: initialState,
                stageIdentifier: nil,
                codeIdentifier: nil,
                moduleVersion: nil,
                terminalConsumed: false
            )
            saveSession()
            emit(.updateState(initialState))
            queryActiveStatus(generation: requestGeneration)
        case .internetUnavailable:
            emit(.updateState(.init(kind: .connFailedServerUnable, percent: 0)))
        case .invalidParameters, .busy, .internalError, .reserved:
            emit(.updateState(.init(kind: .upgradeFailed, percent: 0)))
        }
    }

    private func registerObserverIfNeeded() {
        guard observerID == nil else { return }
        observerID = MeshLibManager.manager.addGlobalMessageObserver { [weak self] _, message, source, _ in
            guard let self,
                  source == self.nodeAddress,
                  MeshNetworkManager.instance.meshNetwork?.uuid == self.networkUUID,
                  let status = message as? SunricherVendorStatus,
                  case .wifiGatewayDFUStatus(.success(let value)) = status.status.parameters else {
                return
            }
            DispatchQueue.main.async {
                guard self.isActive, !self.requestInFlight else { return }
                self.handle(status: value)
            }
        }
    }

    private func queryActiveStatus(generation requestGeneration: Int) {
        queryDFUStatus(generation: requestGeneration) { [weak self] status in
            guard let self, self.isCurrent(requestGeneration) else { return }
            if let status {
                self.consecutiveQueryFailures = 0
                self.handle(status: status)
            } else {
                self.handleQueryFailure()
            }
        }
    }

    private func queryDFUStatus(
        generation requestGeneration: Int,
        completion: @escaping (WiFiGatewayDFUStatus?) -> Void
    ) {
        guard !requestInFlight, let vendorModel = validVendorModel() else {
            completion(nil)
            return
        }
        requestInFlight = true
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .wifiGatewayDFUStatus),
            model: vendorModel,
            timeout: 5
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.requestInFlight = false
                guard let status = response as? SunricherVendorStatus,
                      case .wifiGatewayDFUStatus(.success(let value)) = status.status.parameters else {
                    completion(nil)
                    return
                }
                completion(value)
            }
        }
    }

    private func queryCurrentVersion(generation requestGeneration: Int) {
        emit(.currentVersionLoading)
        guard !requestInFlight, let vendorModel = validVendorModel() else {
            emit(.currentVersionFailed)
            return
        }
        requestInFlight = true
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .wifiGatewayFirmwareVersion),
            model: vendorModel,
            timeout: 5
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.requestInFlight = false
                guard let status = response as? SunricherVendorStatus,
                      case .wifiGatewayFirmwareVersion(.success(let version)) = status.status.parameters else {
                    self.emit(.currentVersionFailed)
                    return
                }
                self.emit(.currentVersion(version))
            }
        }
    }

    private func restoreMatchingSession(from status: WiFiGatewayDFUStatus) -> Bool {
        guard let session, session.accepted, !session.terminalConsumed else { return false }
        guard status.stage != .idle,
              status.firmwareID == session.targetFirmwareID else {
            clearSession()
            emit(.idle)
            return false
        }
        handle(status: status)
        return true
    }

    private func handle(status: WiFiGatewayDFUStatus) {
        guard var session, session.accepted, !session.terminalConsumed else { return }
        guard status.stage != .idle,
              status.firmwareID == session.targetFirmwareID,
              let state = WiFiFirmwareDFUStateMapper.map(
                status: status,
                targetFirmwareID: session.targetFirmwareID
              ) else {
            clearSession()
            cancelPoll()
            emit(.idle)
            queryCurrentVersion(generation: generation)
            return
        }

        consecutiveQueryFailures = 0
        session.lastState = state
        session.stageIdentifier = WiFiFirmwareDFUStateMapper.stageIdentifier(status.stage)
        session.codeIdentifier = WiFiFirmwareDFUStateMapper.codeIdentifier(status.code)
        session.moduleVersion = status.moduleVersion
        self.session = session
        saveSession()
        emit(.updateState(state))

        switch state.kind {
        case .upgradeComplete:
            cancelPoll()
            emit(.confirmedVersion(status.moduleVersion ?? session.targetFirmwareID))
        case .downloadFailed, .upgradeFailed:
            cancelPoll()
        case .downloading, .updating:
            scheduleNextPoll(after: 2)
        case .connFailedTimeout, .connFailedServerUnable:
            cancelPoll()
        }
    }

    private func handleQueryFailure() {
        consecutiveQueryFailures += 1
        if consecutiveQueryFailures >= 3 {
            scheduleNextPoll(after: 10)
        } else {
            scheduleNextPoll(after: 2)
        }
    }

    private func scheduleNextPoll(after interval: TimeInterval) {
        guard isActive, session?.accepted == true else { return }
        cancelPoll()
        let requestGeneration = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isCurrent(requestGeneration) else { return }
            self.queryActiveStatus(generation: requestGeneration)
        }
        pollWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }

    private func validVendorModel() -> Model? {
        guard node.state, node.isKeybindComplete else { return nil }
        return node.sunricherVendorModel
    }

    private func cancelPoll() {
        pollWorkItem?.cancel()
        pollWorkItem = nil
    }

    private func saveSession() {
        guard let networkUUID, let session else { return }
        sessionStore.save(session, networkUUID: networkUUID, nodeAddress: nodeAddress)
    }

    private func clearSession() {
        guard let networkUUID else {
            session = nil
            return
        }
        sessionStore.remove(networkUUID: networkUUID, nodeAddress: nodeAddress)
        session = nil
    }

    private func isCurrent(_ requestGeneration: Int) -> Bool {
        return isActive && generation == requestGeneration
    }

    private func emit(_ event: Event) {
        if Thread.isMainThread {
            onEvent?(event)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(event)
            }
        }
    }
}
