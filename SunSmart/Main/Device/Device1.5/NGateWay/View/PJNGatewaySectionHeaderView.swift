//
//  PJNGatewaySectionHeaderView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewaySectionHeaderView: UIView {

    var actionTapped: (() -> Void)?

    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = UIColor(hex: 0x2F3555)
        actionButton.setTitleColor(UIColor(hex: 0xA1A8B8), for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        actionButton.addTarget(self, action: #selector(actionButtonAction), for: .touchUpInside)

        addSubview(titleLabel)
        addSubview(actionButton)
        titleLabel.snp.makeConstraints { make in
            make.left.centerY.equalToSuperview()
        }
        actionButton.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
        }
        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(24))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, actionTitle: String?, showsAction: Bool) {
        titleLabel.text = title
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isHidden = !showsAction
    }

    @objc private func actionButtonAction() {
        actionTapped?()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: SCRYFrom(24))
    }
}
