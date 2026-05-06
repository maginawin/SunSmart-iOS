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
        let batteryText: String
        let batteryIconSystemName: String
        let statusPrefixText: String
        let statusText: String
        let statusColor: UIColor
        let updatedText: String
    }

    var refreshAction: (() -> Void)?

    private let batteryIconView = UIImageView()
    private let batteryLabel = UILabel(text: nil, textColor: RGB(79, 93, 132), fontSize: 14, fontWeight: .light, fit: false)
    private let statusPrefixLabel = UILabel(text: nil, textColor: RGB(79, 93, 132), fontSize: 14, fontWeight: .light, fit: false)
    private let statusValueLabel = UILabel(text: nil, textColor: RGB(69, 197, 122), fontSize: 14, fontWeight: .light, fit: false)
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
        batteryIconView.image = UIImage(named:"battery_ek")?.withTintColor(RGB(79, 93, 132), renderingMode: .alwaysOriginal)
        batteryLabel.text = state.batteryText
        statusPrefixLabel.text = state.statusPrefixText
        statusValueLabel.text = state.statusText
        statusValueLabel.textColor = state.statusColor
        updatedLabel.text = state.updatedText
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
        refreshButton.setImage(UIImage(named: "refresh_ek")?.withTintColor(RGB(79, 93, 132), renderingMode: .alwaysOriginal), for: .normal)
        refreshButton.addTarget(self, action: #selector(refreshButtonAction), for: .touchUpInside)

        [batteryIconView, batteryLabel, statusPrefixLabel, statusValueLabel, updatedLabel, refreshButton].forEach {
            addSubview($0)
        }

        batteryIconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(24))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(20))
        }

        batteryLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(batteryIconView.snp.right).offset(SCRXFrom(6))
        }

        statusPrefixLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(batteryLabel.snp.right).offset(SCRXFrom(24))
        }

        statusValueLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(statusPrefixLabel.snp.right).offset(SCRXFrom(4))
        }

        refreshButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalToSuperview().offset(-SCRXFrom(24))
            make.width.height.equalTo(SCRXFrom(30))
        }

        updatedLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(refreshButton.snp.left).offset(-SCRXFrom(23))
        }
    }

    @objc private func refreshButtonAction() {
        refreshAction?()
    }
}
