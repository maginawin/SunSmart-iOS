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

    private var messageObserverID: UUID?
    private var connectionObserverID: UUID?
    private var queryWorkItem: DispatchWorkItem?
    private var generation = 0
    private var statusQueryInFlight = false
    private var startRequestInFlight = false
    private var pendingStartQueryInFlight = false
    private var currentVersionQueryInFlight = false
    private var pendingStart: WiFiFirmwareDFUStartRecovery?
    private var lastValidStatusAt: TimeInterval?
    private var communicationUnknown = false
    private var isActive = false
    private var session: WiFiFirmwareDFUSession?
    private var reducer: WiFiFirmwareDFUStatusReducer?

    init(
        node: Node,
        sessionStore: WiFiFirmwareDFUSessionStore = .init()
    ) {
        self.node = node
        self.sessionStore = sessionStore
        self.networkUUID = MeshNetworkManager.instance.meshNetwork?.uuid
        self.nodeAddress = node.primaryUnicastAddress

        if let networkUUID,
           var restored = sessionStore.load(
               networkUUID: networkUUID,
               nodeAddress: node.primaryUnicastAddress
           ) {
            if restored.lastStatus?.stage.isTerminal != true && !restored.terminalConsumed {
                restored.requiresAuthoritativeQuery = true
            }
            session = restored
            reducer = WiFiFirmwareDFUStatusReducer(
                targetFirmwareID: restored.targetFirmwareID,
                boundOTAID: restored.otaID,
                lastAcceptedStatus: restored.lastStatus
            )
        }
    }

    deinit {
        queryWorkItem?.cancel()
        MeshLibManager.manager.removeGlobalMessageObserver(messageObserverID)
        MeshLibManager.manager.removeGlobalConnectionObserver(connectionObserverID)
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        registerObserversIfNeeded()
        refresh()
    }

    func deactivate() {
        if isActiveNonterminalSession {
            session?.requiresAuthoritativeQuery = true
            saveSession()
        }
        isActive = false
        generation += 1
        statusQueryInFlight = false
        startRequestInFlight = false
        pendingStartQueryInFlight = false
        currentVersionQueryInFlight = false
        clearPendingStart()
        cancelScheduledQuery()
        MeshLibManager.manager.removeGlobalMessageObserver(messageObserverID)
        MeshLibManager.manager.removeGlobalConnectionObserver(connectionObserverID)
        messageObserverID = nil
        connectionObserverID = nil
    }

    func refresh() {
        guard isActive else { return }
        cancelScheduledQuery()

        if let session, !session.terminalConsumed {
            if session.lastStatus?.stage.isTerminal == true {
                if let lastState = session.lastState {
                    emit(.updateState(lastState))
                }
                if session.lastStatus?.stage == .success {
                    emit(.confirmedVersion(
                        session.lastStatus?.moduleVersion ?? session.targetFirmwareID
                    ))
                }
                return
            }

            if session.requiresAuthoritativeQuery {
                enterCommunicationUnknown()
                queryDFUStatus(authoritative: true)
            } else {
                queryDFUStatus(authoritative: false)
            }
            return
        }

        queryCurrentVersion()
    }

    func start(filename: String, version: String) {
        guard isActive, !startRequestInFlight, pendingStart == nil else { return }
        generation += 1
        statusQueryInFlight = false
        currentVersionQueryInFlight = false
        cancelScheduledQuery()
        clearSession()
        clearPendingStart()
        communicationUnknown = false
        lastValidStatusAt = nil
        let requestGeneration = generation
        emit(.loadingStart(true))

        let otaID = UInt64.random(in: 1...UInt64.max)
        let request: WiFiGatewayDFUStartRequest
        let firmwareID: String
        do {
            let url = try WiFiFirmwareDFUMetadataBuilder.makeURL(filename: filename)
            firmwareID = try WiFiFirmwareDFUMetadataBuilder.firmwareID(version: version)
            request = try WiFiGatewayDFUStartRequest(
                otaID: otaID,
                url: url,
                firmwareID: firmwareID
            )
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

        pendingStart = WiFiFirmwareDFUStartRecovery(
            otaID: otaID,
            firmwareID: firmwareID
        )
        startRequestInFlight = true
        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .wifiGatewayDFUStart(request)),
            model: vendorModel,
            timeout: 10
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.startRequestInFlight = false
                guard let status = response as? SunricherVendorStatus,
                      case .wifiGatewayDFUStart(let startResponse) = status.status.parameters,
                      startResponse.otaID == otaID else {
                    self.resolveMissingStartRET()
                    return
                }
                self.handleStartResponse(startResponse)
            }
        }
    }

    func consumeSuccess() {
        guard let networkUUID else { return }
        session?.terminalConsumed = true
        sessionStore.remove(networkUUID: networkUUID, nodeAddress: nodeAddress)
        session = nil
        reducer = nil
        lastValidStatusAt = nil
        communicationUnknown = false
        cancelScheduledQuery()
        emit(.idle)
    }

    private func handleStartResponse(_ response: WiFiGatewayDFUStartResponse) {
        switch response.result {
        case .accepted:
            establishPendingStart()
        case .internetUnavailable:
            clearPendingStart()
            emit(.loadingStart(false))
            emit(.updateState(.init(kind: .connFailedServerUnable, percent: 0)))
        case .invalidParameters, .busy, .internalError:
            clearPendingStart()
            emit(.loadingStart(false))
            emit(.updateState(.init(kind: .upgradeFailed, percent: 0)))
        case .reserved:
            resolveMissingStartRET()
        }
    }

    private func registerObserversIfNeeded() {
        if messageObserverID == nil {
            messageObserverID = MeshLibManager.manager.addGlobalMessageObserver {
                [weak self] _, message, source, _ in
                guard let self,
                      let networkUUID = self.networkUUID,
                      source == self.nodeAddress,
                      MeshNetworkManager.instance.meshNetwork?.uuid == networkUUID,
                      let report = message as? SunricherReportMessage,
                      case .wifiGatewayDFUStatus(let status) = report.reportData else {
                    return
                }
                DispatchQueue.main.async {
                    self.handleEventStatus(status)
                }
            }
        }

        if connectionObserverID == nil {
            connectionObserverID = MeshLibManager.manager.addGlobalConnectionObserver {
                [weak self] manager, isConnected in
                guard let self,
                      let networkUUID = self.networkUUID,
                      manager.meshNetwork?.uuid == networkUUID else {
                    return
                }
                DispatchQueue.main.async {
                    self.handleConnectionChange(isConnected: isConnected)
                }
            }
        }
    }

    private func handleEventStatus(_ status: WiFiGatewayDFUStatus) {
        guard isActive else { return }
        let snapshot = makeSnapshot(from: status)

        if var pendingStart {
            let matched = pendingStart.record(snapshot, source: .event)
            self.pendingStart = pendingStart
            if matched && !startRequestInFlight {
                establishPendingStart()
            }
            return
        }

        guard session?.requiresAuthoritativeQuery != true else { return }
        handle(snapshot: snapshot, source: .event, authoritative: false)
    }

    private func resolveMissingStartRET() {
        guard var pendingStart else {
            finishUnknownStart()
            return
        }
        let decision = pendingStart.nextAfterMissingRET()
        self.pendingStart = pendingStart

        switch decision {
        case .established:
            establishPendingStart()
        case .queryOnce:
            queryPendingStartStatusOnce()
        case .unknown:
            finishUnknownStart()
        }
    }

    private func queryPendingStartStatusOnce() {
        guard isActive, !pendingStartQueryInFlight else { return }
        guard let vendorModel = validVendorModel() else {
            finishUnknownStart()
            return
        }

        let requestGeneration = generation
        pendingStartQueryInFlight = true
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .wifiGatewayDFUStatus),
            model: vendorModel,
            timeout: WiFiFirmwareDFUQueryTiming.statusTimeout
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.pendingStartQueryInFlight = false
                guard var pendingStart = self.pendingStart else { return }
                if let response = response as? SunricherVendorStatus,
                   case .wifiGatewayDFUStatus(.success(let value)) =
                    response.status.parameters {
                    _ = pendingStart.record(
                        self.makeSnapshot(from: value),
                        source: .query
                    )
                    self.pendingStart = pendingStart
                }
                self.resolveMissingStartRET()
            }
        }
    }

    private func establishPendingStart() {
        guard let pendingStart else {
            finishUnknownStart()
            return
        }
        let pendingReducer = pendingStart.reducer
        let pendingStatus = pendingReducer.lastAcceptedStatus
        let initialState = pendingStatus.flatMap(WiFiFirmwareDFUStateMapper.map)
            ?? .init(kind: .downloading, percent: 0)

        reducer = pendingReducer
        session = WiFiFirmwareDFUSession(
            targetFirmwareID: pendingReducer.targetFirmwareID,
            otaID: pendingReducer.boundOTAID,
            lastStatus: pendingStatus,
            lastState: initialState,
            terminalConsumed: false,
            requiresAuthoritativeQuery: false
        )
        clearPendingStart()
        emit(.loadingStart(false))
        lastValidStatusAt = Date().timeIntervalSince1970
        saveSession()
        emit(.updateState(initialState))

        if let pendingStatus {
            finishOrSchedule(after: pendingStatus)
        } else {
            queryDFUStatus(authoritative: false)
        }
    }

    private func finishUnknownStart() {
        clearPendingStart()
        emit(.loadingStart(false))
        emit(.updateState(.init(kind: .connFailedTimeout, percent: 0)))
    }

    private func handleConnectionChange(isConnected: Bool) {
        guard isActive, isActiveNonterminalSession else { return }

        if isConnected {
            if session?.requiresAuthoritativeQuery == true && !statusQueryInFlight {
                queryDFUStatus(authoritative: true)
            }
            return
        }

        session?.requiresAuthoritativeQuery = true
        saveSession()
        cancelScheduledQuery()
        enterCommunicationUnknown()
    }

    private func queryDFUStatus(authoritative: Bool) {
        guard isActive, !statusQueryInFlight else { return }
        guard let vendorModel = validVendorModel() else {
            handleNoValidStatus()
            return
        }

        let requestGeneration = generation
        statusQueryInFlight = true
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .wifiGatewayDFUStatus),
            model: vendorModel,
            timeout: WiFiFirmwareDFUQueryTiming.statusTimeout
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.statusQueryInFlight = false
                if self.session?.requiresAuthoritativeQuery == true && !authoritative {
                    self.queryDFUStatus(authoritative: true)
                    return
                }
                guard let response = response as? SunricherVendorStatus,
                      case .wifiGatewayDFUStatus(.success(let value)) =
                        response.status.parameters else {
                    self.handleNoValidStatus()
                    return
                }
                self.handle(
                    snapshot: self.makeSnapshot(from: value),
                    source: .query,
                    authoritative: authoritative
                )
            }
        }
    }

    private func handle(
        snapshot: WiFiFirmwareDFUStatusSnapshot,
        source: WiFiFirmwareDFUStatusSource,
        authoritative: Bool
    ) {
        guard var session, !session.terminalConsumed else { return }

        if authoritative {
            guard snapshot.stage != .idle,
                  snapshot.firmwareID == session.targetFirmwareID,
                  session.otaID == nil || snapshot.otaID == session.otaID else {
                handleNoValidStatus()
                return
            }

            var freshReducer = WiFiFirmwareDFUStatusReducer(
                targetFirmwareID: session.targetFirmwareID
            )
            guard freshReducer.reduce(snapshot, source: .query) == .accepted else {
                handleNoValidStatus()
                return
            }
            reducer = freshReducer
            session.requiresAuthoritativeQuery = false
            self.session = session
            accept(snapshot: snapshot)
            return
        }

        guard var reducer else {
            handleNoValidStatus()
            return
        }
        let reduction = reducer.reduce(snapshot, source: source)
        self.reducer = reducer

        switch reduction {
        case .accepted:
            accept(snapshot: snapshot)
        case .ignored(.duplicate):
            markValidCommunication()
            if let lastState = self.session?.lastState {
                emit(.updateState(lastState))
            }
            scheduleNormalQuery()
        case .ignored:
            if source == .query {
                handleNoValidStatus()
            }
        }
    }

    private func accept(snapshot: WiFiFirmwareDFUStatusSnapshot) {
        guard var session,
              let state = WiFiFirmwareDFUStateMapper.map(status: snapshot) else {
            return
        }

        markValidCommunication()
        session.otaID = reducer?.boundOTAID ?? snapshot.otaID
        session.lastStatus = snapshot
        session.lastState = state
        session.requiresAuthoritativeQuery = false
        self.session = session
        saveSession()
        emit(.updateState(state))
        finishOrSchedule(after: snapshot)
    }

    private func finishOrSchedule(after snapshot: WiFiFirmwareDFUStatusSnapshot) {
        guard snapshot.stage.isTerminal else {
            scheduleNormalQuery()
            return
        }

        cancelScheduledQuery()
        if snapshot.stage == .success {
            emit(.confirmedVersion(snapshot.moduleVersion ?? session?.targetFirmwareID ?? ""))
        }
    }

    private func markValidCommunication() {
        lastValidStatusAt = Date().timeIntervalSince1970
        if communicationUnknown {
            communicationUnknown = false
        }
    }

    private func handleNoValidStatus() {
        guard isActive, isActiveNonterminalSession else { return }
        let now = Date().timeIntervalSince1970

        if session?.requiresAuthoritativeQuery == true {
            enterCommunicationUnknown()
            scheduleQuery(after: WiFiFirmwareDFUQueryTiming.unknownQueryInterval)
            return
        }

        let elapsed = max(0, now - (lastValidStatusAt ?? now))
        if elapsed >= WiFiFirmwareDFUQueryTiming.unknownThreshold {
            enterCommunicationUnknown()
            scheduleQuery(after: WiFiFirmwareDFUQueryTiming.unknownQueryInterval)
        } else {
            let remaining = WiFiFirmwareDFUQueryTiming.unknownThreshold - elapsed
            scheduleQuery(after: min(WiFiFirmwareDFUQueryTiming.quietQueryInterval, remaining))
        }
    }

    private func scheduleNormalQuery() {
        scheduleQuery(after: WiFiFirmwareDFUQueryTiming.quietQueryInterval)
    }

    private func scheduleQuery(after interval: TimeInterval) {
        guard isActive, isActiveNonterminalSession else { return }
        cancelScheduledQuery()
        let requestGeneration = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isCurrent(requestGeneration) else { return }
            self.beginScheduledQuery()
        }
        queryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, interval), execute: item)
    }

    private func beginScheduledQuery() {
        guard !statusQueryInFlight else { return }
        if session?.requiresAuthoritativeQuery != true,
           let lastValidStatusAt,
           Date().timeIntervalSince1970 - lastValidStatusAt >=
            WiFiFirmwareDFUQueryTiming.unknownThreshold {
            enterCommunicationUnknown()
        }
        queryDFUStatus(authoritative: session?.requiresAuthoritativeQuery == true)
    }

    private func enterCommunicationUnknown() {
        guard !communicationUnknown else { return }
        communicationUnknown = true
        let percent = session?.lastStatus?.percent ?? session?.lastState?.percent ?? 0
        emit(.updateState(.init(kind: .communicationUnknown, percent: percent)))
    }

    private func queryCurrentVersion() {
        guard isActive, !currentVersionQueryInFlight else { return }
        emit(.currentVersionLoading)
        guard let vendorModel = validVendorModel() else {
            emit(.currentVersionFailed)
            return
        }

        let requestGeneration = generation
        currentVersionQueryInFlight = true
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .wifiGatewayFirmwareVersion),
            model: vendorModel,
            timeout: 5
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.currentVersionQueryInFlight = false
                guard let status = response as? SunricherVendorStatus,
                      case .wifiGatewayFirmwareVersion(.success(let version)) =
                        status.status.parameters else {
                    self.emit(.currentVersionFailed)
                    return
                }
                self.emit(.currentVersion(version))
            }
        }
    }

    private func makeSnapshot(from status: WiFiGatewayDFUStatus) -> WiFiFirmwareDFUStatusSnapshot {
        let stage: WiFiFirmwareDFUStatusStage
        switch status.stage {
        case .idle: stage = .idle
        case .preparing: stage = .preparing
        case .downloading: stage = .downloading
        case .verifying: stage = .verifying
        case .verifyOK: stage = .verifyOK
        case .verifyFail: stage = .verifyFail
        case .rebooting: stage = .rebooting
        case .recovering: stage = .recovering
        case .versionCheck: stage = .versionCheck
        case .success: stage = .success
        case .timeout: stage = .timeout
        case .failed: stage = .failed
        case .cancelled: stage = .cancelled
        }

        let failureCategory: WiFiFirmwareDFUFailureCategory
        switch stage {
        case .timeout:
            failureCategory = .timeout
        case .verifyFail:
            failureCategory = .download
        case .failed:
            switch status.code {
            case .noNetwork, .http, .size, .verify, .metadata:
                failureCategory = .download
            default:
                failureCategory = .other
            }
        default:
            failureCategory = .none
        }

        return .init(
            otaID: status.otaID,
            stage: stage,
            percent: Int(status.percent),
            failureCategory: failureCategory,
            codeIdentifier: "\(codeName(status.code)):0x\(String(format: "%02X", status.code.rawValue))",
            firmwareID: status.firmwareID,
            moduleVersion: status.moduleVersion
        )
    }

    private func codeName(_ code: WiFiGatewayDFUCode) -> String {
        switch code {
        case .none: return "none"
        case .noNetwork: return "noNetwork"
        case .http: return "http"
        case .size: return "size"
        case .verify: return "verify"
        case .version: return "version"
        case .noPartition: return "noPartition"
        case .noMemory: return "noMemory"
        case .otaBegin: return "otaBegin"
        case .otaWrite: return "otaWrite"
        case .otaEnd: return "otaEnd"
        case .setBoot: return "setBoot"
        case .internalError: return "internalError"
        case .triggerError: return "triggerError"
        case .triggerTimeout: return "triggerTimeout"
        case .otaTimeout: return "otaTimeout"
        case .protocolError: return "protocolError"
        case .versionProtocol: return "versionProtocol"
        case .versionMissing: return "versionMissing"
        case .versionQueryError: return "versionQueryError"
        case .versionQueryTimeout: return "versionQueryTimeout"
        case .versionMismatch: return "versionMismatch"
        case .recoveryTimeout: return "recoveryTimeout"
        case .metadata: return "metadata"
        case .reserved: return "reserved"
        }
    }

    private var isActiveNonterminalSession: Bool {
        guard let session, !session.terminalConsumed else { return false }
        return session.lastStatus?.stage.isTerminal != true
    }

    private func validVendorModel() -> Model? {
        guard node.state, node.isKeybindComplete else { return nil }
        return node.sunricherVendorModel
    }

    private func cancelScheduledQuery() {
        queryWorkItem?.cancel()
        queryWorkItem = nil
    }

    private func saveSession() {
        guard let networkUUID, let session else { return }
        sessionStore.save(session, networkUUID: networkUUID, nodeAddress: nodeAddress)
    }

    private func clearPendingStart() {
        pendingStart = nil
        pendingStartQueryInFlight = false
    }

    private func clearSession() {
        if let networkUUID {
            sessionStore.remove(networkUUID: networkUUID, nodeAddress: nodeAddress)
        }
        session = nil
        reducer = nil
    }

    private func isCurrent(_ requestGeneration: Int) -> Bool {
        isActive && generation == requestGeneration
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
