//
//  PJNGatewaySpaceRowView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewaySpaceRowView: UIView {

    var deleteTapped: (() -> Void)?

    private let nameLabel = UILabel()
    private let nodesLabel = UILabel()
    private let deleteButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(hex: 0xFBFCFF)
        layer.cornerRadius = SCRYFrom(12)
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(hex: 0xE4E8F1).cgColor

        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.textColor = UIColor(hex: 0x2F3555)
        nodesLabel.font = .systemFont(ofSize: 13, weight: .regular)
        nodesLabel.textColor = UIColor(hex: 0xA1A8B8)
        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = UIColor(hex: 0xC7CBD4)
        deleteButton.addTarget(self, action: #selector(deleteAction), for: .touchUpInside)

        addSubview(nameLabel)
        addSubview(nodesLabel)
        addSubview(deleteButton)
        nameLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(12))
            make.centerY.equalToSuperview()
        }
        deleteButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-12))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(18))
        }
        nodesLabel.snp.makeConstraints { make in
            make.right.equalTo(deleteButton.snp.left).offset(SCRXFrom(-10))
            make.centerY.equalToSuperview()
        }
        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(42))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(name: String, nodesText: String, showsDelete: Bool) {
        nameLabel.text = name
        nodesLabel.text = nodesText
        deleteButton.isHidden = !showsDelete
    }

    @objc private func deleteAction() {
        deleteTapped?()
    }
}
