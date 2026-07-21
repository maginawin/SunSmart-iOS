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
        case startAvailability(Bool)
        case cancelAvailability(Bool)
        case cancelNotEffective
        case idle
        case confirmedVersion(String)
    }

    private enum StatusQueryPurpose: Equatable {
        case normal(authoritative: Bool)
        case cancelRecovery
        case cancelUnknown
    }

    var onEvent: ((Event) -> Void)?

    private let node: Node
    private let sessionStore: WiFiFirmwareDFUSessionStore
    private let networkUUID: UUID?
    private let nodeAddress: UInt16

    private var messageObserverID: UUID?
    private var connectionObserverID: UUID?
    private var queryWorkItem: DispatchWorkItem?
    private var cancelGateWorkItem: DispatchWorkItem?
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
    private var cancelReducer = WiFiFirmwareDFUCancelReducer()

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
            restored.prepareForPageRecovery()
            session = restored
            reducer = WiFiFirmwareDFUStatusReducer(
                targetFirmwareID: restored.targetFirmwareID,
                boundOTAID: restored.otaID,
                lastAcceptedStatus: restored.lastStatus
            )
            cancelReducer = WiFiFirmwareDFUCancelReducer(state: restored.cancelState)
        }
    }

    deinit {
        queryWorkItem?.cancel()
        cancelGateWorkItem?.cancel()
        MeshLibManager.manager.removeGlobalMessageObserver(messageObserverID)
        MeshLibManager.manager.removeGlobalConnectionObserver(connectionObserverID)
    }

    func beginInitialLoad() {
        if var session, !session.terminalConsumed {
            session.prepareForPageRecovery()
            self.session = session
            saveSession()
        }
        isActive = true
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
        registerObserversIfNeeded()
        emit(.currentVersionLoading)
        enterCommunicationUnknown()
        restoreCancelTransactionGate()
        queryDFUStatus(purpose: .normal(authoritative: true))
    }

    func deactivate() {
        if var session, !session.terminalConsumed {
            session.prepareForPageRecovery()
            self.session = session
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
        cancelScheduledCancelGateDeadline()
        MeshLibManager.manager.removeGlobalMessageObserver(messageObserverID)
        MeshLibManager.manager.removeGlobalConnectionObserver(connectionObserverID)
        messageObserverID = nil
        connectionObserverID = nil
        emitStartAvailability()
    }

    func refreshOTAStatus() {
        guard isActive else { return }
        registerObserversIfNeeded()
        cancelScheduledQuery()

        if let session, !session.terminalConsumed {
            if session.cancelState.blocksNewStart {
                emit(.cancelAvailability(false))
                if session.cancelState.phase == .unknown {
                    emitCancellationUnknownState()
                } else if let lastState = session.lastState {
                    emit(.updateState(lastState))
                }
                applyCancel(.resume)
                return
            }

            if session.requiresAuthoritativeQuery {
                enterCommunicationUnknown()
                queryDFUStatus(purpose: .normal(authoritative: true))
                return
            }

            if session.lastStatus?.stage.isTerminal == true {
                if let lastState = session.lastState {
                    emit(.updateState(lastState))
                }
                if session.lastStatus?.stage == .success {
                    emit(.confirmedVersion(
                        session.lastStatus?.moduleVersion ?? session.targetFirmwareID
                    ))
                }
                emit(.cancelAvailability(false))
                return
            }

            queryDFUStatus(purpose: .normal(authoritative: false))
            return
        }

        queryDFUStatus(purpose: .normal(authoritative: false))
    }

    func start(filename: String, version: String) {
        guard canStartNewOTA() else { return }
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
        emitStartAvailability()
        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .wifiGatewayDFUStart(request)),
            model: vendorModel,
            timeout: WiFiGatewayV19Timing.responseTimeout(for: .dfuStart)
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.startRequestInFlight = false
                self.emitStartAvailability()
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

    func cancel() {
        guard isActive,
              var session,
              !session.terminalConsumed,
              !session.requiresAuthoritativeQuery,
              let otaID = session.otaID,
              otaID != 0,
              session.lastStatus?.otaID == otaID,
              session.lastStatus?.firmwareID == session.targetFirmwareID,
              let stage = session.lastStatus?.stage,
              [.preparing, .downloading].contains(stage),
              !session.cancelState.hasAttempted,
              let vendorModel = validVendorModel(),
              let request = try? WiFiGatewayDFUCancelRequest(otaID: otaID) else {
            return
        }

        let now = Date().timeIntervalSince1970
        guard session.transactionGate.beginCancel(
            at: now,
            timeout: WiFiGatewayV19Timing.responseTimeout(for: .dfuCancel)
        ) else {
            return
        }
        _ = cancelReducer.reduce(.sent)
        session.cancelState = cancelReducer.state
        self.session = session
        saveSession()
        scheduleCancelGateDeadline()
        emitStartAvailability()
        emit(.cancelAvailability(false))
        cancelScheduledQuery()
        let requestGeneration = generation

        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .wifiGatewayDFUCancel(request)),
            model: vendorModel,
            timeout: WiFiGatewayV19Timing.responseTimeout(for: .dfuCancel)
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.finishCancelTransaction()
                self.handleCancelCallback(response, expectedOTAID: otaID)
            }
        }
    }

    func consumeSuccess() {
        session?.terminalConsumed = true
        clearSession()
        lastValidStatusAt = nil
        communicationUnknown = false
        cancelScheduledQuery()
        emit(.idle)
        emitStartAvailability()
    }

    private func handleStartResponse(_ response: WiFiGatewayDFUStartResponse) {
        switch response.result {
        case .accepted:
            establishPendingStart()
        case .internetUnavailable:
            clearPendingStart()
            emit(.loadingStart(false))
            emit(.updateState(.init(kind: .connFailedServerUnable, percent: 0)))
            emitStartAvailability()
        case .invalidParameters, .busy, .internalError:
            clearPendingStart()
            emit(.loadingStart(false))
            emit(.updateState(.init(kind: .upgradeFailed, percent: 0)))
            emitStartAvailability()
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
                      MeshNetworkManager.instance.meshNetwork?.uuid == networkUUID else {
                    return
                }

                if let report = message as? SunricherReportMessage,
                   case .wifiGatewayDFUStatus(let status) = report.reportData {
                    DispatchQueue.main.async {
                        self.handleEventStatus(status)
                    }
                    return
                }

                if let status = message as? SunricherVendorStatus,
                   case .wifiGatewayDFUCancel(let response) = status.status.parameters {
                    DispatchQueue.main.async {
                        self.handleCancelResponse(response)
                    }
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
        if isMatchingCurrentSession(snapshot),
           session?.cancelState.hasAttempted == true {
            handleCancellationEvent(snapshot)
            return
        }
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
            timeout: WiFiGatewayV19Timing.responseTimeout(for: .dfuStatus)
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
        emitStartAvailability()

        if let pendingStatus {
            finishOrSchedule(after: pendingStatus)
            emitCancelAvailability(for: pendingStatus)
        } else {
            emit(.cancelAvailability(false))
            queryDFUStatus(purpose: .normal(authoritative: false))
        }
    }

    private func finishUnknownStart() {
        clearPendingStart()
        emit(.loadingStart(false))
        emit(.updateState(.init(kind: .connFailedTimeout, percent: 0)))
        emitStartAvailability()
    }

    private func handleConnectionChange(isConnected: Bool) {
        guard isActive else { return }

        if isConnected {
            if session?.cancelState.blocksNewStart == true {
                applyCancel(.resume)
                return
            }
            if session?.requiresAuthoritativeQuery == true && !statusQueryInFlight {
                queryDFUStatus(purpose: .normal(authoritative: true))
            } else if session == nil, communicationUnknown, !statusQueryInFlight {
                queryDFUStatus(purpose: .normal(authoritative: true))
            }
            return
        }

        session?.requiresAuthoritativeQuery = true
        saveSession()
        cancelScheduledQuery()
        if session?.cancelState.blocksNewStart == true {
            emit(.cancelAvailability(false))
        } else {
            enterCommunicationUnknown()
        }
        emitStartAvailability()
    }

    private func queryDFUStatus(purpose: StatusQueryPurpose) {
        guard isActive, !statusQueryInFlight else { return }
        guard let vendorModel = validVendorModel() else {
            handleInvalidStatusQuery(for: purpose)
            return
        }

        let requestGeneration = generation
        statusQueryInFlight = true
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .wifiGatewayDFUStatus),
            model: vendorModel,
            timeout: WiFiGatewayV19Timing.responseTimeout(for: .dfuStatus)
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.statusQueryInFlight = false
                if case .normal(let authoritative) = purpose,
                   self.session?.requiresAuthoritativeQuery == true,
                   !authoritative {
                    self.queryDFUStatus(purpose: .normal(authoritative: true))
                    return
                }
                guard let response = response as? SunricherVendorStatus,
                      case .wifiGatewayDFUStatus(.success(let value)) =
                        response.status.parameters else {
                    self.handleInvalidStatusQuery(for: purpose)
                    return
                }
                let snapshot = self.makeSnapshot(from: value)
                switch purpose {
                case .normal(let authoritative):
                    if self.session?.cancelState.blocksNewStart == true {
                        self.resumeCancelQueryAfterCompetingNormalQuery()
                        return
                    }
                    self.handle(
                        snapshot: snapshot,
                        source: .query,
                        authoritative: authoritative
                    )
                case .cancelRecovery:
                    self.handleCancellationQuery(snapshot, purpose: .cancelRecovery)
                case .cancelUnknown:
                    self.handleCancellationQuery(snapshot, purpose: .cancelUnknown)
                }
            }
        }
    }

    private func handleInvalidStatusQuery(for purpose: StatusQueryPurpose) {
        switch purpose {
        case .normal(let authoritative):
            if session?.cancelState.blocksNewStart == true {
                resumeCancelQueryAfterCompetingNormalQuery()
            } else {
                handleNoValidStatus(failCurrentVersion: authoritative)
            }
        case .cancelRecovery:
            applyCancel(.recoveryQuery(.invalid))
        case .cancelUnknown:
            applyCancel(.unknownQuery(.invalid))
        }
    }

    private func resumeCancelQueryAfterCompetingNormalQuery() {
        switch session?.cancelState.phase {
        case .pending, .recovering:
            queryDFUStatus(purpose: .cancelRecovery)
        case .unknown:
            queryDFUStatus(purpose: .cancelUnknown)
        case .notRequested, .resolved, .none:
            break
        }
    }

    private func handleCancelCallback(
        _ response: StaticMeshResponse?,
        expectedOTAID: UInt64
    ) {
        guard let status = response as? SunricherVendorStatus,
              case .wifiGatewayDFUCancel(let cancelResponse) = status.status.parameters,
              cancelResponse.otaID == expectedOTAID else {
            applyCancel(.pendingTimeout)
            return
        }
        handleCancelResponse(cancelResponse)
    }

    private func handleCancelResponse(_ response: WiFiGatewayDFUCancelResponse) {
        guard isActive,
              let session,
              session.cancelState.hasAttempted,
              response.otaID != 0,
              response.otaID == session.otaID else {
            return
        }

        let result: WiFiFirmwareDFUCancelRET
        switch response.result {
        case .success: result = .success
        case .invalidParameters: result = .invalidParameters
        case .notCancelled: result = .notCancelled
        case .unconfirmed: result = .unconfirmed
        case .busy: result = .busy
        case .reserved: result = .reserved
        }
        applyCancel(.response(result))
    }

    private func handleCancellationEvent(_ snapshot: WiFiFirmwareDFUStatusSnapshot) {
        guard var reducer else { return }
        let source: WiFiFirmwareDFUStatusSource = snapshot.stage == .cancelled
            ? .cancellation
            : .event
        let reduction = reducer.reduce(snapshot, source: source)
        self.reducer = reducer

        switch reduction {
        case .accepted:
            accept(snapshot: snapshot, scheduleNextQuery: false)
        case .ignored(.duplicate):
            markValidCommunication()
            if let lastState = session?.lastState {
                emit(.updateState(lastState))
            }
        case .ignored:
            return
        }
        applyCancel(.matchedStatus(snapshot.stage))
    }

    private func handleCancellationQuery(
        _ snapshot: WiFiFirmwareDFUStatusSnapshot,
        purpose: StatusQueryPurpose
    ) {
        let observation = cancellationObservation(for: snapshot)
        switch observation {
        case .matchedIntermediate, .matchedCancelled, .matchedOtherTerminal:
            guard var session else { return }
            var freshReducer = WiFiFirmwareDFUStatusReducer(
                targetFirmwareID: session.targetFirmwareID
            )
            let source: WiFiFirmwareDFUStatusSource = snapshot.stage == .cancelled
                ? .cancellation
                : .query
            guard freshReducer.reduce(snapshot, source: source) == .accepted else {
                handleInvalidStatusQuery(for: purpose)
                return
            }
            reducer = freshReducer
            session.requiresAuthoritativeQuery = false
            self.session = session
            accept(snapshot: snapshot, scheduleNextQuery: false)
        case .idle, .invalid:
            break
        }

        switch purpose {
        case .cancelRecovery:
            applyCancel(.recoveryQuery(observation))
        case .cancelUnknown:
            applyCancel(.unknownQuery(observation))
        case .normal:
            break
        }
    }

    private func cancellationObservation(
        for snapshot: WiFiFirmwareDFUStatusSnapshot
    ) -> WiFiFirmwareDFUCancelStatusObservation {
        guard snapshot.stage != .idle else { return .idle }
        guard isMatchingCurrentSession(snapshot) else { return .invalid }
        if snapshot.stage == .cancelled {
            return .matchedCancelled
        }
        if snapshot.stage.isTerminal {
            return .matchedOtherTerminal
        }
        return .matchedIntermediate(snapshot.stage)
    }

    private func isMatchingCurrentSession(_ snapshot: WiFiFirmwareDFUStatusSnapshot) -> Bool {
        guard let session,
              let otaID = session.otaID,
              otaID != 0 else {
            return false
        }
        return snapshot.otaID == otaID &&
            snapshot.firmwareID == session.targetFirmwareID
    }

    private func applyCancel(_ input: WiFiFirmwareDFUCancelInput) {
        guard var session, session.cancelState.hasAttempted || input == .sent else {
            return
        }
        let action = cancelReducer.reduce(input)
        session.cancelState = cancelReducer.state
        self.session = session
        saveSession()
        emitStartAvailability()
        performCancel(action)
    }

    private func performCancel(_ action: WiFiFirmwareDFUCancelAction) {
        switch action {
        case .none:
            break
        case .updateOriginalOTA:
            emit(.cancelAvailability(false))
            cancelScheduledQuery()
        case .cancellationSucceeded:
            acceptCancellationSuccess()
        case .originalOTAFinished:
            cancelScheduledQuery()
            emit(.cancelAvailability(false))
        case .continueOriginalOTA(let showFailureTip):
            if showFailureTip {
                emit(.cancelNotEffective)
            }
            emit(.cancelAvailability(false))
            scheduleNormalQuery()
        case .requestRecoveryQuery:
            cancelScheduledQuery()
            queryDFUStatus(purpose: .cancelRecovery)
        case .requestUnknownQuery:
            cancelScheduledQuery()
            queryDFUStatus(purpose: .cancelUnknown)
        case .enterUnknown:
            emitCancellationUnknownState()
            scheduleQuery(
                after: WiFiFirmwareDFUCancelTiming.unknownQueryInterval,
                purpose: .cancelUnknown
            )
        case .scheduleUnknownQuery(let updateOriginalOTA):
            if updateOriginalOTA {
                emitCancellationUnknownState()
            }
            scheduleQuery(
                after: WiFiFirmwareDFUCancelTiming.unknownQueryInterval,
                purpose: .cancelUnknown
            )
        case .clearSession:
            clearSession()
            lastValidStatusAt = nil
            communicationUnknown = false
            cancelScheduledQuery()
            emit(.idle)
        }
    }

    private func acceptCancellationSuccess() {
        guard let session,
              let otaID = session.otaID,
              otaID != 0 else {
            return
        }
        if session.lastStatus?.stage == .cancelled {
            cancelScheduledQuery()
            emit(.cancelAvailability(false))
            return
        }

        let previous = session.lastStatus
        let cancelled = WiFiFirmwareDFUStatusSnapshot(
            otaID: otaID,
            stage: .cancelled,
            percent: previous?.percent ?? session.lastState?.percent ?? 0,
            failureCategory: .none,
            codeIdentifier: "none:0x00",
            firmwareID: session.targetFirmwareID,
            moduleVersion: nil
        )
        guard var reducer,
              reducer.reduce(cancelled, source: .cancellation) == .accepted else {
            return
        }
        self.reducer = reducer
        accept(snapshot: cancelled, scheduleNextQuery: false)
    }

    private func emitCancellationUnknownState() {
        let percent = session?.lastStatus?.percent ?? session?.lastState?.percent ?? 0
        emit(.cancelAvailability(false))
        emit(.updateState(.init(kind: .cancellationUnknown, percent: percent)))
    }

    private func handle(
        snapshot: WiFiFirmwareDFUStatusSnapshot,
        source: WiFiFirmwareDFUStatusSource,
        authoritative: Bool
    ) {
        if authoritative, snapshot.stage == .idle {
            markValidCommunication()
            clearStaleTerminalAfterAuthoritativeQuery()
            return
        }

        guard var session, !session.terminalConsumed else {
            if authoritative {
                handleUnboundAuthoritativeStatus(snapshot)
                return
            }
            if snapshot.stage == .idle {
                emit(.idle)
            }
            return
        }

        if authoritative {
            switch WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                session: session,
                candidate: snapshot
            ) {
            case .acceptStatus:
                break
            case .clearStaleTerminal:
                clearStaleTerminalAfterAuthoritativeQuery()
                return
            case .retainSession:
                handleNoValidStatus(failCurrentVersion: true)
                return
            }

            var freshReducer = WiFiFirmwareDFUStatusReducer(
                targetFirmwareID: session.targetFirmwareID
            )
            guard freshReducer.reduce(snapshot, source: .query) == .accepted else {
                handleNoValidStatus(failCurrentVersion: true)
                return
            }
            reducer = freshReducer
            session.requiresAuthoritativeQuery = false
            self.session = session
            accept(snapshot: snapshot)
            scheduleCurrentVersionAfterAuthoritativeStatus(snapshot)
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
            if let lastStatus = self.session?.lastStatus {
                emitCancelAvailability(for: lastStatus)
            }
            scheduleNormalQuery()
        case .ignored:
            if source == .query {
                handleNoValidStatus()
            }
        }
    }

    private func handleUnboundAuthoritativeStatus(
        _ snapshot: WiFiFirmwareDFUStatusSnapshot
    ) {
        guard let firmwareID = snapshot.firmwareID else {
            handleNoValidStatus(failCurrentVersion: true)
            return
        }
        var freshReducer = WiFiFirmwareDFUStatusReducer(
            targetFirmwareID: firmwareID
        )
        guard freshReducer.reduce(snapshot, source: .query) == .accepted else {
            handleNoValidStatus(failCurrentVersion: true)
            return
        }

        let transactionGate = session?.transactionGate ?? .init()
        reducer = freshReducer
        session = WiFiFirmwareDFUSession(
            targetFirmwareID: firmwareID,
            otaID: snapshot.otaID,
            lastStatus: nil,
            lastState: nil,
            terminalConsumed: false,
            requiresAuthoritativeQuery: false,
            transactionGate: transactionGate
        )
        accept(snapshot: snapshot)
        scheduleCurrentVersionAfterAuthoritativeStatus(snapshot)
    }

    private func scheduleCurrentVersionAfterAuthoritativeStatus(
        _ snapshot: WiFiFirmwareDFUStatusSnapshot
    ) {
        if snapshot.stage == .preparing || snapshot.stage.isTerminal {
            queryCurrentVersion()
        }
    }

    private func accept(
        snapshot: WiFiFirmwareDFUStatusSnapshot,
        scheduleNextQuery: Bool = true
    ) {
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
        emitCancelAvailability(for: snapshot)
        emitStartAvailability()
        if snapshot.stage.isTerminal || scheduleNextQuery {
            finishOrSchedule(after: snapshot)
        }
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
        queryCurrentVersion()
    }

    private func markValidCommunication() {
        lastValidStatusAt = Date().timeIntervalSince1970
        if communicationUnknown {
            communicationUnknown = false
        }
    }

    private func handleNoValidStatus(failCurrentVersion: Bool = false) {
        if failCurrentVersion {
            emit(.currentVersionFailed)
        }
        guard isActive, isStatusQueryEligibleSession else {
            enterCommunicationUnknown()
            return
        }
        let now = Date().timeIntervalSince1970

        if session == nil {
            enterCommunicationUnknown()
            scheduleQuery(
                after: WiFiFirmwareDFUQueryTiming.unknownQueryInterval,
                purpose: .normal(authoritative: true)
            )
            return
        }

        if session?.requiresAuthoritativeQuery == true {
            enterCommunicationUnknown()
            scheduleQuery(
                after: WiFiFirmwareDFUQueryTiming.unknownQueryInterval,
                purpose: .normal(authoritative: true)
            )
            return
        }

        let elapsed = max(0, now - (lastValidStatusAt ?? now))
        if elapsed >= WiFiFirmwareDFUQueryTiming.unknownThreshold {
            enterCommunicationUnknown()
            scheduleQuery(
                after: WiFiFirmwareDFUQueryTiming.unknownQueryInterval,
                purpose: .normal(authoritative: false)
            )
        } else {
            let remaining = WiFiFirmwareDFUQueryTiming.unknownThreshold - elapsed
            scheduleQuery(
                after: min(WiFiFirmwareDFUQueryTiming.quietQueryInterval, remaining),
                purpose: .normal(authoritative: false)
            )
        }
    }

    private func scheduleNormalQuery() {
        guard session?.cancelState.blocksNewStart != true else { return }
        scheduleQuery(
            after: WiFiFirmwareDFUQueryTiming.quietQueryInterval,
            purpose: .normal(authoritative: false)
        )
    }

    private func scheduleQuery(
        after interval: TimeInterval,
        purpose: StatusQueryPurpose
    ) {
        guard isActive, isStatusQueryEligibleSession else { return }
        cancelScheduledQuery()
        let requestGeneration = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isCurrent(requestGeneration) else { return }
            self.beginScheduledQuery(purpose: purpose)
        }
        queryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, interval), execute: item)
    }

    private func beginScheduledQuery(purpose: StatusQueryPurpose) {
        guard !statusQueryInFlight else { return }
        if case .normal = purpose {
            if session?.requiresAuthoritativeQuery != true,
               let lastValidStatusAt,
               Date().timeIntervalSince1970 - lastValidStatusAt >=
                WiFiFirmwareDFUQueryTiming.unknownThreshold {
                enterCommunicationUnknown()
            }
        }
        queryDFUStatus(purpose: purpose)
    }

    private func enterCommunicationUnknown() {
        guard !communicationUnknown else { return }
        communicationUnknown = true
        let percent = session?.lastStatus?.percent ?? session?.lastState?.percent ?? 0
        emit(.updateState(.init(kind: .communicationUnknown, percent: percent)))
        emitStartAvailability()
    }

    private func emitCancelAvailability(for snapshot: WiFiFirmwareDFUStatusSnapshot) {
        let isCancellableStage = snapshot.stage == .preparing || snapshot.stage == .downloading
        let enabled = isCancellableStage &&
            session?.requiresAuthoritativeQuery == false &&
            session?.cancelState.hasAttempted == false &&
            snapshot.otaID != 0 &&
            snapshot.otaID == session?.otaID &&
            snapshot.firmwareID == session?.targetFirmwareID
        emit(.cancelAvailability(enabled))
    }

    private func clearStaleTerminalAfterAuthoritativeQuery() {
        clearSession()
        lastValidStatusAt = nil
        communicationUnknown = false
        cancelScheduledQuery()
        emit(.idle)
        emitStartAvailability()
        queryCurrentVersion()
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
            timeout: WiFiGatewayV19Timing.responseTimeout(for: .firmwareVersion)
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

    private var isStatusQueryEligibleSession: Bool {
        guard let session else { return communicationUnknown }
        return session.isStatusQueryEligible
    }

    private func canStartNewOTA(
        at now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        guard isActive,
              !communicationUnknown,
              !startRequestInFlight,
              pendingStart == nil,
              session?.transactionGate.blocksStart(at: now) != true else {
            return false
        }
        guard let session, !session.terminalConsumed else { return true }
        return !session.requiresAuthoritativeQuery &&
            !session.cancelState.blocksNewStart &&
            session.lastStatus?.stage.isTerminal == true
    }

    private func emitStartAvailability() {
        emit(.startAvailability(canStartNewOTA()))
    }

    private func validVendorModel() -> Model? {
        guard node.state, node.isKeybindComplete else { return nil }
        return node.sunricherVendorModel
    }

    private func cancelScheduledQuery() {
        queryWorkItem?.cancel()
        queryWorkItem = nil
    }

    private func restoreCancelTransactionGate() {
        guard var session else {
            emitStartAvailability()
            return
        }

        let now = Date().timeIntervalSince1970
        if session.transactionGate.expireIfNeeded(at: now) {
            self.session = session
            persistOrRemoveConsumedSession(at: now)
        } else if session.terminalConsumed &&
                    !session.transactionGate.blocksStart(at: now) {
            removeSessionCompletely()
        }
        scheduleCancelGateDeadline()
        emitStartAvailability()
    }

    private func scheduleCancelGateDeadline() {
        cancelScheduledCancelGateDeadline()
        guard isActive,
              let deadline = session?.transactionGate.cancelDeadline else {
            return
        }

        let now = Date().timeIntervalSince1970
        guard deadline > now else {
            expireCancelTransactionGate()
            return
        }

        let requestGeneration = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isCurrent(requestGeneration) else { return }
            self.expireCancelTransactionGate()
        }
        cancelGateWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, deadline - now),
            execute: item
        )
    }

    private func cancelScheduledCancelGateDeadline() {
        cancelGateWorkItem?.cancel()
        cancelGateWorkItem = nil
    }

    private func finishCancelTransaction() {
        cancelScheduledCancelGateDeadline()
        guard var session else {
            emitStartAvailability()
            return
        }
        session.transactionGate.finishCancel()
        self.session = session
        persistOrRemoveConsumedSession()
        emitStartAvailability()
    }

    private func expireCancelTransactionGate() {
        cancelScheduledCancelGateDeadline()
        guard var session else {
            emitStartAvailability()
            return
        }
        guard session.transactionGate.expireIfNeeded(
            at: Date().timeIntervalSince1970
        ) else {
            scheduleCancelGateDeadline()
            return
        }
        self.session = session
        persistOrRemoveConsumedSession()
        emitStartAvailability()
    }

    private func persistOrRemoveConsumedSession(
        at now: TimeInterval = Date().timeIntervalSince1970
    ) {
        guard let session else { return }
        if session.terminalConsumed &&
            !session.transactionGate.blocksStart(at: now) {
            removeSessionCompletely()
        } else {
            saveSession()
        }
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
        let now = Date().timeIntervalSince1970
        if var session, session.transactionGate.blocksStart(at: now) {
            session.terminalConsumed = true
            self.session = session
            reducer = nil
            cancelReducer = .init()
            saveSession()
            emitStartAvailability()
            return
        }
        removeSessionCompletely()
        emitStartAvailability()
    }

    private func removeSessionCompletely() {
        if let networkUUID {
            sessionStore.remove(networkUUID: networkUUID, nodeAddress: nodeAddress)
        }
        session = nil
        reducer = nil
        cancelReducer = .init()
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
