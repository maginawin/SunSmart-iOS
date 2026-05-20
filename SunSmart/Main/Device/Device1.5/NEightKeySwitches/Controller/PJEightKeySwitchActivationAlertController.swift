//
//  PJEightKeySwitchActivationAlertController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import NordicSigMeshSDK

final class PJEightKeySwitchActivationAlertController: UIViewController {

    var actionHandler: ((Int) -> Void)?

    private let contentView = PJEightKeySwitchActivationAlertView()

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    func apply(content: PJEightKeySwitchActivationAlertView.Content) {
        contentView.apply(content: content)
    }

    @objc private func firstButtonAction() {
        actionHandler?(0)
    }

    @objc private func secondButtonAction() {
        actionHandler?(1)
    }

    private func setupUI() {
        view.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentView.cancelButton.addTarget(self, action: #selector(firstButtonAction), for: .touchUpInside)
        contentView.retryButton.addTarget(self, action: #selector(secondButtonAction), for: .touchUpInside)
    }
}

protocol PJEightKeySwitchActivationDetecting: AnyObject {
    func sendActivationProbe(to node: Node, completion: @escaping (Bool) -> Void)
}

final class MeshBatteryPowerSwitchActivationDetector: PJEightKeySwitchActivationDetecting {

    func sendActivationProbe(to node: Node, completion: @escaping (Bool) -> Void) {
        guard let vendorModel = node.sunricherVendorModel else {
            completion(false)
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .batteryPowerSwitchCapability),
            model: vendorModel,
            timeout: 1.5
        ) { response in
            guard let status = response as? SunricherVendorStatus else {
                completion(false)
                return
            }
            completion(status.status.isSuccessful && status.status.code == .batteryPowerSwitchCapability)
        }
    }
}

final class PJEightKeySwitchActivationFlow {

    private enum State {
        case idle
        case waiting
        case detected
        case noResponse
        case cancelled
    }

    private weak var presenter: UIViewController?
    private let switchData: PJEightKeySwitchData
    private let detector: PJEightKeySwitchActivationDetecting
    private let onDetectedCompleted: () -> Void
    private let titleText = "neightkeyswitches_save_after_activation".localizedString
    private var alertController: PJEightKeySwitchActivationAlertController?
    private var countdownTimer: Timer?
    private var probeTimer: Timer?
    private var autoProceedWorkItem: DispatchWorkItem?
    private var remainingSeconds = 60
    private var generation = UUID()
    private var state: State = .idle

    init(
        presenter: UIViewController,
        switchData: PJEightKeySwitchData,
        detector: PJEightKeySwitchActivationDetecting = MeshBatteryPowerSwitchActivationDetector(),
        onDetectedCompleted: @escaping () -> Void
    ) {
        self.presenter = presenter
        self.switchData = switchData
        self.detector = detector
        self.onDetectedCompleted = onDetectedCompleted
    }

    deinit {
        stopTimers()
        autoProceedWorkItem?.cancel()
    }

    func start() {
        let controller = PJEightKeySwitchActivationAlertController()
        controller.actionHandler = { [weak self] index in
            self?.handleAction(at: index)
        }
        alertController = controller
        controller.apply(content: waitingContent())
        presenter?.present(controller, animated: true) { [weak self] in
            self?.startWaiting()
        }
    }

    private func startWaiting() {
        generation = UUID()
        state = .waiting
        remainingSeconds = 60
        autoProceedWorkItem?.cancel()
        stopTimers()
        applyWaitingContent()
        sendProbe(for: generation)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickCountdown()
        }
        probeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sendProbe(for: self.generation)
        }
    }

    private func tickCountdown() {
        guard case .waiting = state else { return }
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            showNoResponse()
        } else {
            applyWaitingContent()
        }
    }

    private func sendProbe(for probeGeneration: UUID) {
        guard case .waiting = state, let node = switchData.proxyNode else { return }
        detector.sendActivationProbe(to: node) { [weak self] detected in
            DispatchQueue.main.async {
                guard let self,
                      detected,
                      self.generation == probeGeneration,
                      case .waiting = self.state else {
                    return
                }
                self.showDetected()
            }
        }
    }

    private func showDetected() {
        state = .detected
        stopTimers()
        alertController?.apply(content: .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: "neightkeyswitches_activation_detected".localizedString,
            statusStyle: .success,
            actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
        ))
        let workItem = DispatchWorkItem { [weak self] in
            self?.completeDetected()
        }
        autoProceedWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func showNoResponse() {
        state = .noResponse
        stopTimers()
        alertController?.apply(content: .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: "neightkeyswitches_activation_timeout".localizedString,
            statusStyle: .failure,
            actions: [
                .init(title: "cancel".localizedString.uppercased(), style: .normal),
                .init(title: "try_again".localizedString.uppercased(), style: .primary)
            ]
        ))
    }

    private func applyWaitingContent() {
        alertController?.apply(content: waitingContent())
    }

    private func waitingContent() -> PJEightKeySwitchActivationAlertView.Content {
        .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: String(format: "neightkeyswitches_activation_waiting_format".localizedString, remainingSeconds),
            statusStyle: .loading,
            actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
        )
    }

    private func handleAction(at index: Int) {
        switch state {
        case .waiting:
            cancel()
        case .detected:
            cancel()
        case .noResponse:
            if index == 0 {
                cancel()
            } else {
                startWaiting()
            }
        case .idle, .cancelled:
            cancel()
        }
    }

    private func completeDetected() {
        guard case .detected = state else { return }
        alertController?.dismiss(animated: true) { [weak self] in
            self?.onDetectedCompleted()
        }
    }

    private func cancel() {
        state = .cancelled
        generation = UUID()
        stopTimers()
        autoProceedWorkItem?.cancel()
        alertController?.dismiss(animated: true)
    }

    private func stopTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        probeTimer?.invalidate()
        probeTimer = nil
    }
}
