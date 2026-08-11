//
//  SyncGatewaysCloudBridge.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import Foundation

struct SyncGatewaysCloudBatchState {
    private var pendingGatewayIDs: Set<String> = []
    private var didRegisterWork = false
    private var didIssueRefresh = false

    mutating func register(gatewayID: String) -> Bool {
        guard !didIssueRefresh,
              !pendingGatewayIDs.contains(gatewayID) else {
            return false
        }
        didRegisterWork = true
        pendingGatewayIDs.insert(gatewayID)
        return true
    }

    mutating func settle(gatewayID: String) -> Bool {
        guard pendingGatewayIDs.remove(gatewayID) != nil,
              pendingGatewayIDs.isEmpty,
              didRegisterWork,
              !didIssueRefresh else {
            return false
        }
        didIssueRefresh = true
        return true
    }

    mutating func resetForNextBatch() -> Bool {
        guard pendingGatewayIDs.isEmpty, didIssueRefresh else { return false }
        didRegisterWork = false
        didIssueRefresh = false
        return true
    }
}

enum SyncGatewaysCloudEnqueueKind {
    case deviceSuccess
    case dirtyRetry
}

enum SyncGatewaysCloudEnqueuePolicy {
    static func generation(
        for kind: SyncGatewaysCloudEnqueueKind,
        now: Int64,
        current: Int64,
        uploaded: Int64?
    ) -> Int64 {
        switch kind {
        case .deviceSuccess:
            return GatewayCloudSyncGenerationPolicy.next(
                now: now,
                current: current,
                uploaded: uploaded
            )
        case .dirtyRetry:
            return current
        }
    }
}

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

final class SyncGatewaysCloudBridge {
    var onCloudState: ((String, SyncGatewayCloudState) -> Void)?

    private var batchState = SyncGatewaysCloudBatchState()
    private var activeGenerationByGatewayID: [String: Int64] = [:]
    private let refreshSiteSnapshot: () async -> Void

    init(refreshSiteSnapshot: @escaping () async -> Void) {
        self.refreshSiteSnapshot = refreshSiteSnapshot
    }

    func beginBatch() {
        _ = batchState.resetForNextBatch()
    }

    func refreshSiteSnapshotNow() {
        Task { [refreshSiteSnapshot] in
            await refreshSiteSnapshot()
        }
    }

    func recordDeviceSuccessAndEnqueue(
        _ target: SyncGatewayRuntimeTarget
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let gateway = target.gateway, target.node != nil else { return }
        gateway.lastUpdate = SyncGatewaysCloudEnqueuePolicy.generation(
            for: .deviceSuccess,
            now: Int64(Date().timeIntervalSince1970),
            current: gateway.lastUpdate,
            uploaded: gateway.lastUploadCloudTimestamp
        )
        gateway.syncCloudError = nil
        guard gateway.save() else {
            onCloudState?(target.descriptor.id, .failed)
            return
        }
        enqueue(target)
    }

    func retryDirty(_ target: SyncGatewayRuntimeTarget) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let gateway = target.gateway,
              target.node != nil,
              gateway.needUploadCloud else {
            return
        }
        enqueue(target)
    }

    func finishBatchIfNeeded() {
        // Terminal callbacks settle the batch. This explicit hook documents that
        // leaving the page does not cancel registered cloud work.
    }

    private func enqueue(_ target: SyncGatewayRuntimeTarget) {
        guard let gateway = target.gateway, let node = target.node else { return }
        let gatewayID = target.descriptor.id
        let generation = gateway.lastUpdate
        if let activeGeneration = activeGenerationByGatewayID[gatewayID],
           activeGeneration >= generation {
            return
        }

        activeGenerationByGatewayID[gatewayID] = generation
        _ = batchState.register(gatewayID: gatewayID)
        onCloudState?(gatewayID, .pending)
        CloudSynchronizationManager.shared.addSynchronizationHandle(
            operation: .syncGateway(gateway: gateway, node: node),
            level: .promptly
        ) { [self] state in
            guard activeGenerationByGatewayID[gatewayID] == generation else {
                return
            }
            switch state {
            case .wait:
                break
            case .inProgress:
                onCloudState?(gatewayID, .uploading)
            case .successful:
                finish(
                    gatewayID: gatewayID,
                    generation: generation,
                    state: .clean
                )
            case .failure:
                finish(
                    gatewayID: gatewayID,
                    generation: generation,
                    state: .failed
                )
            case .cancel:
                finish(
                    gatewayID: gatewayID,
                    generation: generation,
                    state: .failed
                )
            }
        }
    }

    private func finish(
        gatewayID: String,
        generation: Int64,
        state: SyncGatewayCloudState
    ) {
        guard activeGenerationByGatewayID[gatewayID] == generation else { return }
        activeGenerationByGatewayID[gatewayID] = nil
        onCloudState?(gatewayID, state)
        if batchState.settle(gatewayID: gatewayID) {
            Task { [refreshSiteSnapshot] in
                await refreshSiteSnapshot()
            }
        }
    }
}
#endif
