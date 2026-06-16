//
//  EmerFireNameCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit

final class EmerFireNameCell: UITableViewCell {

    private enum Layout {
        static let horizontalInset = SCRXFrom(16)
        static let cardRadius = SCRYFrom(5)
    }

    var nameDidChange: ((String) -> Void)?
    var syncAction: (() -> Void)?

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: "Name", textColor: Title_Color, fontSize: 14, fontWeight: .light)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private lazy var syncButton: UIButton = {
        let button = UIButton(
            title: "devices_not_synced".localizedString,
            titleSize: 14,
            titleWeight: .light,
            titleColor: Red_Color,
            fit: false,
            normalImageName: "schedule_sync_failed",
            target: self,
            action: #selector(handleSyncAction)
        )
        button.setImagePosition(position: .left, spacing: SCRXFrom(4))
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        return button
    }()

    private lazy var cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.cardRadius
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor(red: 151 / 255.0, green: 151 / 255.0, blue: 151 / 255.0, alpha: 0.3).cgColor
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var nameTextField: UITextField = {
        let textField = UITextField()
        textField.font = FONTS(15)
        textField.textColor = TextBlack_Color
        textField.clearButtonMode = .whileEditing
        textField.borderStyle = .none
        textField.addTarget(self, action: #selector(textDidChange(_:)), for: .editingChanged)
        return textField
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameDidChange = nil
        syncAction = nil
    }

    func configure(name: String, synced: Bool) {
        nameTextField.text = name
        syncButton.isHidden = synced
    }

    @objc private func textDidChange(_ sender: UITextField) {
        nameDidChange?(sender.text ?? "")
    }

    @objc private func handleSyncAction() {
        syncAction?()
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(titleLabel)
        contentView.addSubview(syncButton)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(16))
            make.right.lessThanOrEqualTo(syncButton.snp.left).offset(-SCRXFrom(8))
        }

        syncButton.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.right.equalTo(SCRXFrom(-16))
        }

        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(Layout.horizontalInset)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(6))
            make.height.equalTo(SCRYFrom(40))
            make.bottom.equalToSuperview().offset(-SCRYFrom(8))
        }

        cardView.addSubview(nameTextField)
        nameTextField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(10))
            make.right.equalTo(SCRXFrom(-10))
            make.top.bottom.equalToSuperview()
        }
    }
}
