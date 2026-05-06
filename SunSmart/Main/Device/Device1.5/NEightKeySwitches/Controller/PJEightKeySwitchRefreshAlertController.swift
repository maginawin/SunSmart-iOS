//
//  PJEightKeySwitchRefreshAlertController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJEightKeySwitchRefreshAlertController: UIViewController {

    enum State: Equatable {
        case waiting(remainingSeconds: Int)
        case updated
        case timeout
    }

    var cancelAction: (() -> Void)?
    var retryAction: (() -> Void)?

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
    }

    @objc private func cancelButtonAction() {
        dismiss(animated: true) { [weak self] in
            self?.cancelAction?()
        }
    }

    @objc private func retryButtonAction() {
        retryAction?()
        startWaiting()
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
