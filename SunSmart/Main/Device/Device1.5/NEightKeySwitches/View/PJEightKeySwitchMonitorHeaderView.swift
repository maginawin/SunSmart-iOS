//
//  PJEightKeySwitchMonitorHeaderView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import SnapKit

final class PJEightKeySwitchMonitorHeaderView: UIView {

    struct State {
        enum Layout {
            case battery
            case centeredStatus
        }

        let batteryText: String
        let batteryIconSystemName: String
        let statusPrefixText: String
        let statusText: String
        let statusColor: UIColor
        let updatedText: String
        let showsRefreshButton: Bool
        let layout: Layout
    }

    var refreshAction: (() -> Void)?

    private let batteryIconView = UIImageView()
    private let batteryLabel = UILabel(text: nil, textColor: RGB(79, 93, 132), fontSize: 14, fontWeight: .light, fit: false)
    private let statusPrefixLabel = UILabel(text: nil, textColor: RGB(79, 93, 132), fontSize: 14, fontWeight: .light, fit: false)
    private let statusValueLabel = UILabel(text: nil, textColor: RGB(69, 197, 122), fontSize: 14, fontWeight: .light, fit: false)
    private let statusStackView = UIStackView()
    private let updatedLabel = UILabel(text: nil, textColor: RGB(120, 126, 148), fontSize: 14, fontWeight: .light, fit: false)
    private let refreshButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(state: State) {
        batteryIconView.image = UIImage(named: state.batteryIconSystemName)?.withTintColor(RGB(79, 93, 132), renderingMode: .alwaysOriginal)
        batteryLabel.text = state.batteryText
        statusPrefixLabel.text = state.statusPrefixText
        statusPrefixLabel.isHidden = state.statusPrefixText.isEmpty
        statusValueLabel.text = state.statusText
        statusValueLabel.textColor = state.statusColor
        updatedLabel.text = state.updatedText
        apply(layout: state.layout)
        refreshButton.isHidden = !state.showsRefreshButton || state.layout == .centeredStatus
    }

    func setRefreshing(_ refreshing: Bool) {
        let animationKey = "neightkeyswitches.refresh.rotation"
        if refreshing {
            guard refreshButton.layer.animation(forKey: animationKey) == nil else { return }
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0
            animation.toValue = CGFloat.pi * 2
            animation.duration = 0.8
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            refreshButton.layer.add(animation, forKey: animationKey)
            return
        }
        refreshButton.layer.removeAnimation(forKey: animationKey)
    }

    private func setupUI() {
        batteryIconView.contentMode = .scaleAspectFit
        statusStackView.axis = .horizontal
        statusStackView.alignment = .center
        statusStackView.spacing = SCRXFrom(4)
        updatedLabel.numberOfLines = 1
        updatedLabel.lineBreakMode = .byTruncatingTail
        refreshButton.setImage(UIImage(named: "refresh_ek")?.withTintColor(RGB(79, 93, 132), renderingMode: .alwaysOriginal), for: .normal)
        refreshButton.addTarget(self, action: #selector(refreshButtonAction), for: .touchUpInside)

        [statusPrefixLabel, statusValueLabel].forEach {
            statusStackView.addArrangedSubview($0)
        }

        [batteryLabel, statusPrefixLabel, statusValueLabel].forEach {
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
            $0.setContentHuggingPriority(.required, for: .horizontal)
        }
        updatedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updatedLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        [batteryIconView, batteryLabel, statusStackView, updatedLabel, refreshButton].forEach {
            addSubview($0)
        }

        batteryIconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(24))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(20))
        }

        batteryLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(batteryIconView.snp.right).offset(SCRXFrom(4))
        }

        statusStackView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(batteryLabel.snp.right).offset(SCRXFrom(24))
        }

        refreshButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalToSuperview().offset(-SCRXFrom(24))
            make.width.height.equalTo(SCRXFrom(30))
        }

        updatedLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(statusStackView.snp.right).offset(SCRXFrom(24))
            make.right.equalTo(refreshButton.snp.left).offset(-SCRXFrom(4))
        }
    }

    private func apply(layout: State.Layout) {
        switch layout {
        case .battery:
            batteryIconView.isHidden = false
            batteryLabel.isHidden = false
            updatedLabel.isHidden = false
            statusStackView.snp.remakeConstraints { make in
                make.centerY.equalToSuperview()
                make.left.equalTo(batteryLabel.snp.right).offset(SCRXFrom(24))
            }
            updatedLabel.snp.remakeConstraints { make in
                make.centerY.equalToSuperview()
                make.left.equalTo(statusStackView.snp.right).offset(SCRXFrom(24))
                make.right.equalTo(refreshButton.snp.left).offset(-SCRXFrom(4))
            }
        case .centeredStatus:
            batteryIconView.isHidden = true
            batteryLabel.isHidden = true
            updatedLabel.isHidden = true
            statusStackView.snp.remakeConstraints { make in
                make.center.equalToSuperview()
            }
            updatedLabel.snp.remakeConstraints { make in
                make.left.right.equalToSuperview()
                make.centerY.equalToSuperview()
            }
        }
    }

    @objc private func refreshButtonAction() {
        refreshAction?()
    }
}
