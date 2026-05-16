//
//  SpaceDebugSummaryView.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import UIKit

final class SpaceDebugSummaryView: UIView {
    private let stateLabel = UILabel()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(state: SpaceDebugScanState, found: Int, total: Int) {
        stateLabel.text = state.title
        countLabel.text = String(format: "debug_found_format".localizedString, found, total)
    }

    private func setupUI() {
        backgroundColor = Background_Color

        let container = UIView()
        container.backgroundColor = .white
        container.layer.cornerRadius = SCRXFrom(8)
        addSubview(container)
        container.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(8))
        }

        stateLabel.font = Font_Medium_Size(15)
        stateLabel.textColor = Title_Color
        container.addSubview(stateLabel)
        stateLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }

        countLabel.font = FONTS(SCRXFrom(13))
        countLabel.textColor = SubText_Color
        container.addSubview(countLabel)
        countLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.left.greaterThanOrEqualTo(stateLabel.snp.right).offset(SCRXFrom(12))
        }
    }
}
