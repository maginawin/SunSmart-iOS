//
//  SyncGatewaysScanSession.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import Foundation

struct SyncGatewaysScanSessionCore {
    enum Phase: Equatable {
        case idle
        case running(lastTick: TimeInterval)
        case paused
        case finished
    }

    let sessionID: UUID
    private(set) var phase: Phase = .idle

    mutating func resume(at now: TimeInterval) {
        switch phase {
        case .idle, .paused:
            phase = .running(lastTick: now)
        case .running, .finished:
            break
        }
    }

    @discardableResult
    mutating func pause(at now: TimeInterval) -> TimeInterval {
        guard case .running(let lastTick) = phase else { return 0 }
        phase = .paused
        return max(0, now - lastTick)
    }

    mutating func consumeElapsed(at now: TimeInterval) -> TimeInterval {
        guard case .running(let lastTick) = phase else { return 0 }
        let elapsed = max(0, now - lastTick)
        phase = .running(lastTick: max(lastTick, now))
        return elapsed
    }

    func accepts(callbackSessionID: UUID) -> Bool {
        guard callbackSessionID == sessionID,
              case .running = phase else {
            return false
        }
        return true
    }

    mutating func finish() {
        phase = .finished
    }
}

#if canImport(CoreBluetooth) && canImport(NordicSigMeshSDK)
import CoreBluetooth
import NordicSigMeshSDK

final class SyncGatewaysScanSession {
    var onAdvertisement: ((String, Int) -> Void)?
    var onActiveElapsed: ((TimeInterval) -> Void)?
    var onAvailabilityFailure: ((CBManagerState) -> Void)?

    private var core: SyncGatewaysScanSessionCore
    private let allowedNetworkKeyIndexesByNodeAddress: [UInt16: Set<UInt16>]
    private let targetIDByNodeAddress: [UInt16: String]
    private var peripheralsByTargetID: [String: CBPeripheral] = [:]
    private var activeScanCycleID: UUID?
    private var timer: Timer?
    private var bluetoothObservation: NSKeyValueObservation?
    private var resumeRequested = false

    init(context: SyncGatewaysContext) {
        core = SyncGatewaysScanSessionCore(sessionID: context.sessionID)
        allowedNetworkKeyIndexesByNodeAddress = context.allowedNetworkKeyIndexesByNodeAddress
        targetIDByNodeAddress = context.targets.reduce(into: [UInt16: String]()) {
            result, target in
            guard let address = target.node?.primaryUnicastAddress else { return }
            result[address] = target.descriptor.id
        }
        bluetoothObservation = MeshLibManager.manager.observe(
            \.bluetoothState,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let state = change.newValue else { return }
            DispatchQueue.main.async {
                self?.handleBluetoothState(state)
            }
        }
    }

    deinit {
        finish()
    }

    func start() {
        resume()
    }

    func pause() {
        resumeRequested = false
        pauseRuntime()
    }

    func resume() {
        guard core.phase != .finished else { return }
        resumeRequested = true
        handleBluetoothState(MeshLibManager.manager.bluetoothState)
    }

    func finish() {
        guard core.phase != .finished else { return }
        resumeRequested = false
        core.finish()
        activeScanCycleID = nil
        timer?.invalidate()
        timer = nil
        peripheralsByTargetID.removeAll()
        bluetoothObservation?.invalidate()
        bluetoothObservation = nil
        MeshLibManager.manager.stopRefreshNodesRSSI()
    }

    func peripheral(for targetID: String) -> CBPeripheral? {
        peripheralsByTargetID[targetID]
    }

    private func handleBluetoothState(_ state: CBManagerState) {
        guard core.phase != .finished, resumeRequested else { return }
        guard state == .poweredOn else {
            pauseRuntime()
            if state != .unknown {
                onAvailabilityFailure?(state)
            }
            return
        }

        core.resume(at: ProcessInfo.processInfo.systemUptime)
        startTimerIfNeeded()
        startScanCycleIfNeeded()
    }

    private func pauseRuntime() {
        let elapsed = core.pause(at: ProcessInfo.processInfo.systemUptime)
        if elapsed > 0 {
            onActiveElapsed?(elapsed)
        }
        activeScanCycleID = nil
        timer?.invalidate()
        timer = nil
        MeshLibManager.manager.stopRefreshNodesRSSI()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = self.core.consumeElapsed(
                at: ProcessInfo.processInfo.systemUptime
            )
            if elapsed > 0 {
                self.onActiveElapsed?(elapsed)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func startScanCycleIfNeeded() {
        guard activeScanCycleID == nil,
              core.accepts(callbackSessionID: core.sessionID) else {
            return
        }
        let cycleID = UUID()
        let sessionID = core.sessionID
        activeScanCycleID = cycleID

        MeshLibManager.manager.refreshNodesRSSI(
            withWaitFor: 60,
            allowedNetworkKeyIndexesByNodeAddress: allowedNetworkKeyIndexesByNodeAddress,
            nodeScan: { [weak self] data in
                guard let self,
                      self.activeScanCycleID == cycleID,
                      self.core.accepts(callbackSessionID: sessionID),
                      let targetID = self.targetIDByNodeAddress[
                        data.node.primaryUnicastAddress
                      ] else {
                    return
                }
                self.peripheralsByTargetID[targetID] = data.peripheral
                self.onAdvertisement?(targetID, data.rssi.intValue)
            },
            finished: { [weak self] _ in
                guard let self,
                      self.activeScanCycleID == cycleID,
                      self.core.accepts(callbackSessionID: sessionID) else {
                    return
                }
                self.activeScanCycleID = nil
                DispatchQueue.main.async { [weak self] in
                    self?.startScanCycleIfNeeded()
                }
            }
        )
    }
}
#endif
