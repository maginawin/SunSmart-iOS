//
//  SyncGatewaysState.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import Foundation

enum SyncGatewayDeviceState: Equatable {
    case pending
    case syncing(UUID)
    case failed
    case synced
}

enum SyncGatewayCloudState: Equatable {
    case clean
    case pending
    case uploading
    case failed
}

enum SyncGatewayAction: Equatable {
    case sync
    case syncing
    case retry
    case disabledSync
    case disabledRetry
    case synced
    case unavailable
}

enum SyncGatewayDeviceSyncResult: Equatable {
    case success
    case failure
}

struct SyncGatewaysProgress: Equatable {
    let updated: Int
    let total: Int
}

struct SyncGatewayItemState: Equatable {
    let id: String
    let displayName: String?
    let remoteOrder: Int
    let isSyncable: Bool
    var device: SyncGatewayDeviceState
    var cloud: SyncGatewayCloudState
    var rssi: Int?
    var activeMissingDuration: TimeInterval
    var isNoSignal: Bool
}

struct SyncGatewaysState {
    private var items: [SyncGatewayItemState]

    init(targets: [SyncGatewayTargetDescriptor]) {
        items = targets.map { target in
            SyncGatewayItemState(
                id: target.id,
                displayName: target.displayName,
                remoteOrder: target.remoteOrder,
                isSyncable: target.isSyncable,
                device: .pending,
                cloud: .clean,
                rssi: nil,
                activeMissingDuration: 0,
                isNoSignal: true
            )
        }
    }

    var nearbyItems: [SyncGatewayItemState] {
        items
            .filter { item in
                if case .synced = item.device { return false }
                if case .syncing = item.device { return true }
                return !item.isNoSignal
            }
            .sorted { $0.remoteOrder < $1.remoteOrder }
    }

    var otherItems: [SyncGatewayItemState] {
        let other = items.filter { item in
            if case .synced = item.device { return true }
            if case .syncing = item.device { return false }
            return item.isNoSignal
        }
        return other.sorted { lhs, rhs in
            let lhsSynced = lhs.device == .synced
            let rhsSynced = rhs.device == .synced
            if lhsSynced != rhsSynced {
                return !lhsSynced
            }
            return lhs.remoteOrder < rhs.remoteOrder
        }
    }

    var progress: SyncGatewaysProgress {
        SyncGatewaysProgress(
            updated: items.filter { $0.device == .synced }.count,
            total: items.count
        )
    }

    var attentionCount: Int {
        items.filter { $0.device != .synced }.count
    }

    func item(id: String) -> SyncGatewayItemState? {
        items.first { $0.id == id }
    }

    func action(for id: String) -> SyncGatewayAction? {
        guard let item = item(id: id) else { return nil }
        if case .synced = item.device { return .synced }
        if case .syncing = item.device { return .syncing }
        guard item.isSyncable, !item.isNoSignal else { return .unavailable }

        if hasActiveAttempt {
            return item.device == .failed ? .disabledRetry : .disabledSync
        }
        return item.device == .failed ? .retry : .sync
    }

    mutating func receiveAdvertisement(id: String, rssi: Int) {
        guard let index = index(for: id) else { return }
        items[index].rssi = rssi
        items[index].activeMissingDuration = 0
        items[index].isNoSignal = false
    }

    mutating func advanceActiveScan(by elapsed: TimeInterval) {
        guard elapsed > 0 else { return }
        for index in items.indices {
            if case .syncing = items[index].device { continue }
            guard !items[index].isNoSignal else { continue }
            items[index].activeMissingDuration += elapsed
            if items[index].activeMissingDuration >= 15 {
                items[index].isNoSignal = true
                items[index].rssi = nil
            }
        }
    }

    mutating func beginSync(id: String) -> UUID? {
        guard !hasActiveAttempt,
              let index = index(for: id),
              items[index].isSyncable,
              !items[index].isNoSignal else {
            return nil
        }
        switch items[index].device {
        case .pending, .failed:
            let attemptID = UUID()
            items[index].device = .syncing(attemptID)
            return attemptID
        case .syncing, .synced:
            return nil
        }
    }

    mutating func finishSync(
        id: String,
        attemptID: UUID,
        result: SyncGatewayDeviceSyncResult
    ) {
        guard let index = index(for: id),
              items[index].device == .syncing(attemptID) else {
            return
        }
        switch result {
        case .success:
            items[index].device = .synced
            items[index].cloud = .pending
        case .failure:
            items[index].device = .failed
        }
    }

    mutating func setCloudState(id: String, state: SyncGatewayCloudState) {
        guard let index = index(for: id) else { return }
        items[index].cloud = state
    }

    private var hasActiveAttempt: Bool {
        items.contains { item in
            if case .syncing = item.device { return true }
            return false
        }
    }

    private func index(for id: String) -> Int? {
        items.firstIndex { $0.id == id }
    }
}
