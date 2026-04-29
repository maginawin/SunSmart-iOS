//
//  PJNGatewayCopyInformationView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewayCopyInformationView: UIView {

    var tapped: (() -> Void)?

    private let button = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        button.setTitle("copy_gateway_information".localizedString, for: .normal)
        button.setTitleColor(ImportantText_Color, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        button.setImage(UIImage(named: "share_copy"), for: .normal)
        button.tintColor = ImportantText_Color
        button.setImagePosition(position: .right, spacing: SCRXFrom(8))
        button.addTarget(self, action: #selector(buttonAction), for: .touchUpInside)

        addSubview(button)
        button.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(62))
        }
    }

    @objc private func buttonAction() {
        tapped?()
    }
}
