//
//  PJEightKeySwitchMonitorKeyView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import SnapKit

final class PJEightKeySwitchMonitorKeyView: UIView {

    var tapAction: (() -> Void)?
    var longPressAction: (() -> Void)?
    var disabledTapAction: (() -> Void)?

    private let containerView = UIView()
    private let topLabel = UILabel(text: nil, textColor: RGB(195, 201, 221), fontSize: 12, fontWeight: .light, fit: false)
    private let mainLabel = UILabel(text: nil, textColor: Title_Color, fontSize: 16, fontWeight: .light, fit: false)
    private let detailLabel = UILabel(text: nil, textColor: RGB(120, 126, 148), fontSize: 11, fontWeight: .light, fit: false)
    private let arrowImageView = UIImageView()
    private let overlayView = UIView()
    private lazy var pressGestureRecognizer: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePressGesture(_:)))
        gesture.minimumPressDuration = 0
        return gesture
    }()

    private var isPressable = false
    private var isLongPressable = false
    private var isEnabledState = true
    private var didTriggerLongPress = false
    private var longPressWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: PJEightKeySwitchMonitorViewModel.KeyItem, enabled: Bool) {
        isEnabledState = enabled
        topLabel.text = item.topText
        detailLabel.text = item.detailText
        mainLabel.text = item.mainText
        arrowImageView.isHidden = true
        mainLabel.isHidden = false
        detailLabel.isHidden = item.detailText == nil
        topLabel.isHidden = item.topText == nil
        topLabel.numberOfLines = 1
        switch item.style {
        case .scene, .brightness:
            mainLabel.font = UIFont.systemFont(ofSize: 28, weight: .light)
            detailLabel.textColor = RGB(30, 35, 41)
        case .dimming(let direction):
            topLabel.numberOfLines = 2
            topLabel.textColor = RGB(148, 163, 184)
            mainLabel.isHidden = true
            detailLabel.isHidden = true
            arrowImageView.isHidden = false
            arrowImageView.image = UIImage(systemName: direction == .up ? "chevron.up" : "chevron.down")
            arrowImageView.tintColor = RGB(108, 114, 138)
        case .toggle(let kind):
            mainLabel.font = UIFont.systemFont(ofSize: 18, weight: .light)
            if kind == .on {
                topLabel.numberOfLines = 2
                topLabel.textColor = RGB(148, 163, 184)
            }
        }

        overlayView.isHidden = true

        let usesBottomDetailStyle: Bool
        let isScenePressKey: Bool
        let isDimmingKey: Bool
        let isAutoKey: Bool
        switch item.style {
        case .scene:
            usesBottomDetailStyle = true
            isScenePressKey = true
            isDimmingKey = false
            isAutoKey = false
        case .brightness:
            usesBottomDetailStyle = true
            isScenePressKey = false
            isDimmingKey = false
            isAutoKey = false
        case .dimming:
            usesBottomDetailStyle = false
            isScenePressKey = false
            isDimmingKey = true
            isAutoKey = false
        case .toggle(let kind):
            usesBottomDetailStyle = false
            isScenePressKey = false
            isDimmingKey = false
            isAutoKey = kind == .on
        }
        isPressable = enabled && isScenePressKey && item.detailText != nil
        isLongPressable = enabled && (isDimmingKey || isAutoKey)
        containerView.isUserInteractionEnabled = true

        mainLabel.textColor = Title_Color
        if !usesBottomDetailStyle {
            detailLabel.textColor = RGB(120, 126, 148)
        }
        if !isDimmingKey && !isAutoKey {
            topLabel.textColor = RGB(195, 201, 221)
        }
        containerView.backgroundColor = enabled ? .white : RGB(239, 241, 246)
        containerView.layer.shadowOpacity = enabled ? 0.08 : 0
        containerView.layer.borderColor = enabled ? RGB(235, 239, 247).cgColor : RGB(229, 232, 239).cgColor
    }

    private func setupUI() {
        backgroundColor = .clear

        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(12)
        containerView.layer.shadowColor = RGB(82, 91, 131, 0.15).cgColor
        containerView.layer.shadowOpacity = 0.08
        containerView.layer.shadowRadius = 10
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = RGB(235, 239, 247).cgColor
        addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        containerView.addGestureRecognizer(pressGestureRecognizer)

        topLabel.textAlignment = .center
        mainLabel.textAlignment = .center
        detailLabel.textAlignment = .center
        arrowImageView.contentMode = .scaleAspectFit

        [topLabel, mainLabel, detailLabel, arrowImageView].forEach {
            containerView.addSubview($0)
        }

        topLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(4))
            make.left.right.equalToSuperview().inset(SCRXFrom(8))
        }
        mainLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.greaterThanOrEqualToSuperview().offset(SCRXFrom(8))
            make.right.lessThanOrEqualToSuperview().offset(-SCRXFrom(8))
        }
        detailLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(8))
            make.bottom.equalToSuperview().offset(-SCRYFrom(8))
        }
        arrowImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(16))
        }

        overlayView.isHidden = true
    }

    @objc private func handlePressGesture(_ gesture: UILongPressGestureRecognizer) {
        guard isEnabledState || gesture.state == .ended else { return }

        switch gesture.state {
        case .began:
            guard isEnabledState else { return }
            didTriggerLongPress = false
            setPressed(true)
            scheduleLongPressIfNeeded()
        case .changed:
            guard isEnabledState else { return }
            let inside = containerView.bounds.contains(gesture.location(in: containerView))
            if inside {
                if containerView.transform == .identity, !didTriggerLongPress {
                    setPressed(true)
                }
            } else {
                cancelLongPress()
                setPressed(false)
            }
        case .ended:
            let shouldTrigger = containerView.bounds.contains(gesture.location(in: containerView))
            cancelLongPress()
            setPressed(false)
            guard shouldTrigger else { return }
            guard isEnabledState else {
                disabledTapAction?()
                return
            }
            if didTriggerLongPress {
                didTriggerLongPress = false
                return
            }
            guard isPressable else { return }
            triggerTapFeedback()
            tapAction?()
        case .cancelled, .failed:
            cancelLongPress()
            setPressed(false)
        default:
            break
        }
    }

    private func scheduleLongPressIfNeeded() {
        cancelLongPress()
        guard isLongPressable else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isLongPressable else { return }
            self.didTriggerLongPress = true
            self.setPressed(false)
            self.triggerTapFeedback()
            self.longPressAction?()
        }
        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func cancelLongPress() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
    }

    private func setPressed(_ pressed: Bool) {
        if pressed {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                self.containerView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                self.containerView.layer.shadowOpacity = 0.03
            }
            return
        }

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.52,
            initialSpringVelocity: 0.55,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            self.containerView.transform = .identity
            self.containerView.layer.shadowOpacity = 0.08
        }
    }

    private func triggerTapFeedback() {
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}
