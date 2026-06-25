//
//  ELControllerFunctionTestHelper.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/26.
//

import Foundation
import NordicSigMeshSDK

final class ELControllerFunctionTestHelper {

    var updateFunctionTestState: ((ELControllerFunctionTestView.FunctionTestState) -> Void)?
    var updateRxTxState: ((ELControllerFunctionTestView.RxTxState) -> Void)?
    var showOfflineMessage: (() -> Void)?

    private let node: Node
    private var isActive = false
    private var resultPollingTimer: Timer?
    private var isResultRequestInFlight = false

    init(node: Node) {
        self.node = node
    }

    deinit {
        stopFunctionTestResultPolling()
    }

    func startPageSession() {
        isActive = true
        resetFunctionTestUI()
        applyStoredRxTxState()

        guard canSendCommands,
              let vendorModel = node.sunricherVendorModel else {
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .elControllerDeviceStatus),
            model: vendorModel,
            timeout: 3
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self, self.isActive else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.code == .elControllerDeviceStatus,
                      status.status.isSuccessful,
                      case .elControllerDeviceStatus(let deviceStatus) = status.status.parameters else {
                    return
                }
                self.applyDeviceStatus(deviceStatus)
            }
        }
    }

    func stopPageSession() {
        isActive = false
        stopFunctionTestResultPolling()
        resetFunctionTestUI()
    }

    func startFunctionTest() {
        guard canSendCommands else {
            showOfflineMessage?()
            return
        }
        guard let vendorModel = node.sunricherVendorModel else {
            updateFunctionTestState?(.failed)
            return
        }

        isActive = true
        stopFunctionTestResultPolling()
        updateFunctionTestState?(.awaiting)

        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .elControllerStartFunctionTest),
            model: vendorModel,
            timeout: 5
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self, self.isActive else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.code == .elControllerStartFunctionTest,
                      status.status.isSuccessful else {
                    self.updateFunctionTestState?(.failed)
                    return
                }
                self.updateFunctionTestState?(.awaiting)
                self.startFunctionTestResultPolling()
            }
        }
    }

    func checkRxTxCable() {
        guard canSendCommands else {
            showOfflineMessage?()
            return
        }
        guard let vendorModel = node.sunricherVendorModel else {
            applyStoredRxTxState()
            return
        }

        updateRxTxState?(.checking)
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .elControllerRxTxCableConnection),
            model: vendorModel,
            timeout: 5
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self, self.isActive else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.code == .elControllerRxTxCableConnection else {
                    self.node.updateELControllerRxTxConnectionState(.fault)
                    self.applyStoredRxTxState()
                    return
                }
                self.applyRxTxStatus(status)
            }
        }
    }

    @discardableResult
    func handleStatus(_ status: SunricherVendorStatus, sentFrom source: Address) -> Bool {
        guard isActive, isExpectedSource(source) else {
            return false
        }

        switch status.status.code {
        case .elControllerRxTxCableConnection:
            applyRxTxStatus(status)
            return true
        case .elControllerDeviceStatus:
            guard status.status.isSuccessful,
                  case .elControllerDeviceStatus(let deviceStatus) = status.status.parameters else {
                return true
            }
            applyDeviceStatus(deviceStatus)
            return true
        case .elControllerFunctionTestResult:
            handleFunctionTestResultStatus(status)
            return true
        case .elControllerStartFunctionTest,
                .elControllerExitFunctionTest:
            return true
        default:
            return false
        }
    }

    private var canSendCommands: Bool {
        node.isKeybindComplete && node.state
    }

    private func resetFunctionTestUI() {
        updateFunctionTestState?(.idle)
    }

    private func applyStoredRxTxState() {
        switch node.elControllerRxTxConnectionState {
        case .unknown:
            updateRxTxState?(.unknown)
        case .normal:
            updateRxTxState?(.normal)
        case .fault:
            updateRxTxState?(.fault)
        }
    }

    private func applyRxTxStatus(_ status: SunricherVendorStatus) {
        node.updateELControllerRxTxConnectionState(status.status.isSuccessful ? .normal : .fault)
        applyStoredRxTxState()
    }

    private func applyDeviceStatus(_ deviceStatus: ELControllerDeviceStatus) {
        if deviceStatus.isFunctionTesting {
            updateFunctionTestState?(.awaiting)
            startFunctionTestResultPolling()
        } else {
            stopFunctionTestResultPolling()
            updateFunctionTestState?(.idle)
        }
    }

    private func startFunctionTestResultPolling() {
        stopFunctionTestResultPolling()

        let timer = Timer(timeInterval: 7, repeats: true) { [weak self] _ in
            self?.requestFunctionTestResult()
        }
        RunLoop.main.add(timer, forMode: .common)
        resultPollingTimer = timer
    }

    private func stopFunctionTestResultPolling() {
        resultPollingTimer?.invalidate()
        resultPollingTimer = nil
        isResultRequestInFlight = false
    }

    private func requestFunctionTestResult() {
        guard isActive,
              !isResultRequestInFlight,
              let vendorModel = node.sunricherVendorModel else {
            return
        }

        isResultRequestInFlight = true
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .elControllerFunctionTestResult),
            model: vendorModel,
            timeout: 1.8
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isResultRequestInFlight = false
                guard self.isActive else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.code == .elControllerFunctionTestResult else {
                    self.updateFunctionTestState?(.awaiting)
                    return
                }
                self.handleFunctionTestResultStatus(status)
            }
        }
    }

    private func handleFunctionTestResultStatus(_ status: SunricherVendorStatus) {
        guard status.status.isSuccessful,
              case .elControllerFunctionTestResult(let result) = status.status.parameters else {
            updateFunctionTestState?(.awaiting)
            return
        }

        stopFunctionTestResultPolling()
        applyFunctionTestResult(result)
        exitFunctionTest()
    }

    private func applyFunctionTestResult(_ result: ELControllerFunctionTestResult) {
        guard result.isValid else {
            updateFunctionTestState?(.invalid)
            return
        }
        guard result.hasFault else {
            updateFunctionTestState?(.passed)
            return
        }
        updateFunctionTestState?(.faults(
            lamp: result.lampFault,
            battery: result.batteryFault,
            circuit: result.circuitFault
        ))
    }

    private func exitFunctionTest() {
        guard isActive,
              let vendorModel = node.sunricherVendorModel else {
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .elControllerExitFunctionTest),
            model: vendorModel
        )
    }

    private func isExpectedSource(_ source: Address) -> Bool {
        if source == node.primaryUnicastAddress {
            return true
        }
        return node.sunricherVendorModel?.parentElement?.unicastAddress == source
    }
}
