//
//  PJEightKeySwitchRefreshAlertController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import NordicSigMeshSDK

final class PJEightKeySwitchRefreshAlertController: UIViewController {

    enum State: Equatable {
        case waiting(remainingSeconds: Int)
        case updated
        case timeout
    }

    var cancelAction: (() -> Void)?
    var retryAction: (() -> Void)?
    var timeoutAction: (() -> Void)?

    private var countdownTimer: Timer?
    private var remainingSeconds = 60
    private let contentView = PJEightKeySwitchActivationAlertView()

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        invalidateTimer()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        apply(state: .waiting(remainingSeconds: remainingSeconds))
    }

    func startWaiting() {
        remainingSeconds = 60
        invalidateTimer()
        apply(state: .waiting(remainingSeconds: remainingSeconds))
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.remainingSeconds -= 1
            if self.remainingSeconds <= 0 {
                self.showTimeout()
            } else {
                self.apply(state: .waiting(remainingSeconds: self.remainingSeconds))
            }
        }
    }

    func showUpdated() {
        invalidateTimer()
        apply(state: .updated)
    }

    func showTimeout() {
        invalidateTimer()
        apply(state: .timeout)
        timeoutAction?()
    }

    @objc private func cancelButtonAction() {
        cancelAction?()
        dismiss(animated: true)
    }

    @objc private func retryButtonAction() {
        retryAction?()
    }

    private func setupUI() {
        view.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentView.titleLabel.text = "neightkeyswitches_refresh_device".localizedString
        contentView.updateMessage("neightkeyswitches_refresh_message".localizedString)
        contentView.cancelButton.addTarget(self, action: #selector(cancelButtonAction), for: .touchUpInside)
        contentView.retryButton.addTarget(self, action: #selector(retryButtonAction), for: .touchUpInside)
    }

    private func apply(state: State) {
        contentView.statusContainerView.backgroundColor = .clear
        switch state {
        case .waiting(let remainingSeconds):
            contentView.statusLabel.text = String(format: "neightkeyswitches_refresh_waiting_format".localizedString, remainingSeconds)
            contentView.statusLabel.textColor = RGB(104, 114, 146)
            contentView.waitingSpinnerView.isHidden = false
            contentView.waitingSpinnerView.startAnimating()
            contentView.statusIconView.isHidden = true
            contentView.applyWaitingLayout()
        case .updated:
            contentView.statusLabel.text = "neightkeyswitches_refresh_updated".localizedString
            contentView.statusLabel.textColor = RGB(104, 114, 146)
            contentView.waitingSpinnerView.stopAnimating()
            contentView.waitingSpinnerView.isHidden = true
            contentView.statusIconView.isHidden = false
            contentView.statusIconView.image = UIImage(systemName: "checkmark.circle.fill")
            contentView.statusIconView.tintColor = RGB(97, 211, 160)
            contentView.applyWaitingLayout()
        case .timeout:
            contentView.statusLabel.text = "neightkeyswitches_activation_timeout".localizedString
            contentView.statusLabel.textColor = RGB(104, 114, 146)
            contentView.waitingSpinnerView.stopAnimating()
            contentView.waitingSpinnerView.isHidden = true
            contentView.statusIconView.isHidden = false
            contentView.statusIconView.image = UIImage(systemName: "exclamationmark.circle.fill")
            contentView.statusIconView.tintColor = RGB(247, 120, 109)
            contentView.applyDualButtonLayout()
        }
        if case .waiting = state {
            contentView.statusIconView.image = nil
        }
        view.layoutIfNeeded()
    }

    private func invalidateTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}

protocol PJEightKeySwitchBatteryReading: AnyObject {
    func readBatteryLevel(from node: Node, completion: @escaping (UInt8?) -> Void)
}

final class MeshBatteryPowerSwitchBatteryReader: PJEightKeySwitchBatteryReading {

    func readBatteryLevel(from node: Node, completion: @escaping (UInt8?) -> Void) {
        guard node.batteryModel != nil else {
            completion(nil)
            return
        }

        MeshAPI.sendMessage(
            message: GenericBatteryGet(),
            address: node.primaryUnicastAddress,
            timeout: 2.5
        ) { response in
            guard let status = response as? GenericBatteryStatus,
                  status.isBatteryLevelKnown,
                  status.batteryLevel <= 100 else {
                completion(nil)
                return
            }
            completion(status.batteryLevel)
        }
    }
}

final class PJEightKeySwitchBatteryRefreshFlow {

    private enum State {
        case idle
        case waiting
        case updated
        case timeout
        case cancelled
    }

    private weak var presenter: UIViewController?
    private let node: Node
    private let reader: PJEightKeySwitchBatteryReading
    private let onBatteryLevel: (UInt8) -> Bool
    private let onFinished: () -> Void
    private let batteryRefreshProbeInterval: TimeInterval = 1
    private var alertController: PJEightKeySwitchRefreshAlertController?
    private var probeTimer: Timer?
    private var autoDismissWorkItem: DispatchWorkItem?
    private var generation = UUID()
    private var state: State = .idle

    init(
        presenter: UIViewController,
        node: Node,
        reader: PJEightKeySwitchBatteryReading = MeshBatteryPowerSwitchBatteryReader(),
        onBatteryLevel: @escaping (UInt8) -> Bool,
        onFinished: @escaping () -> Void
    ) {
        self.presenter = presenter
        self.node = node
        self.reader = reader
        self.onBatteryLevel = onBatteryLevel
        self.onFinished = onFinished
    }

    deinit {
        stopProbeTimer()
        autoDismissWorkItem?.cancel()
    }

    func start() {
        let controller = PJEightKeySwitchRefreshAlertController()
        controller.cancelAction = { [weak self] in
            self?.cancel()
        }
        controller.retryAction = { [weak self] in
            self?.startWaiting()
        }
        controller.timeoutAction = { [weak self] in
            self?.handleAlertTimeout()
        }
        alertController = controller
        presenter?.present(controller, animated: true) { [weak self] in
            self?.startWaiting()
        }
    }

    private func startWaiting() {
        generation = UUID()
        state = .waiting
        autoDismissWorkItem?.cancel()
        stopProbeTimer()
        alertController?.startWaiting()
        sendProbe(for: generation)
        probeTimer = Timer.scheduledTimer(withTimeInterval: batteryRefreshProbeInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sendProbe(for: self.generation)
        }
    }

    private func sendProbe(for probeGeneration: UUID) {
        guard case .waiting = state else { return }
        reader.readBatteryLevel(from: node) { [weak self] level in
            DispatchQueue.main.async {
                guard let self,
                      let level,
                      self.generation == probeGeneration,
                      case .waiting = self.state else {
                    return
                }
                self.showUpdated(level: level)
            }
        }
    }

    private func showUpdated(level: UInt8) {
        guard case .waiting = state else { return }
        guard onBatteryLevel(level) else {
            showTimeout(updateAlert: true)
            return
        }
        state = .updated
        generation = UUID()
        stopProbeTimer()
        alertController?.showUpdated()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishAndDismiss()
        }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func handleAlertTimeout() {
        showTimeout(updateAlert: false)
    }

    private func showTimeout(updateAlert: Bool) {
        guard case .waiting = state else { return }
        state = .timeout
        generation = UUID()
        stopProbeTimer()
        if updateAlert {
            alertController?.showTimeout()
        }
    }

    func cancel() {
        state = .cancelled
        generation = UUID()
        stopProbeTimer()
        autoDismissWorkItem?.cancel()
        onFinished()
    }

    private func finishAndDismiss() {
        generation = UUID()
        stopProbeTimer()
        autoDismissWorkItem?.cancel()
        alertController?.dismiss(animated: true) { [weak self] in
            self?.onFinished()
        }
    }

    private func stopProbeTimer() {
        probeTimer?.invalidate()
        probeTimer = nil
    }
}
