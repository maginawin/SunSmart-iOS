//
//  EmerFireNameCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit

final class EmerFireNameCell: UITableViewCell {

    private enum Layout {
        static let horizontalInset = SCRXFrom(12)
        static let cardRadius = SCRYFrom(10)
    }

    var nameDidChange: ((String) -> Void)?
    var syncAction: (() -> Void)?

    private lazy var titleLabel: UILabel = {
        UILabel(text: "Name", textColor: Title_Color, fontSize: 12, fontWeight: .light)
    }()

    private lazy var syncIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "group_11"))
        return imageView
    }()

    private lazy var syncButton: UIButton = {
        let button = UIButton(title: "devices_not_synced".localizedString, titleSize: 14, titleColor: Error_Red_Color, fit: false, target: self, action: #selector(handleSyncAction))
        button.contentHorizontalAlignment = .left
        button.titleLabel?.font = FONTS(14)
        return button
    }()

    private lazy var syncContainerView: UIView = {
        UIView()
    }()

    private lazy var cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.cardRadius
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
        syncIconView.isHidden = synced
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
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(2))
        }

        contentView.addSubview(syncContainerView)
        syncContainerView.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.right.equalTo(SCRXFrom(-16))
        }

        syncContainerView.addSubview(syncIconView)
        syncIconView.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(16))
        }

        syncContainerView.addSubview(syncButton)
        syncButton.snp.makeConstraints { make in
            make.left.equalTo(syncIconView.snp.right).offset(SCRXFrom(4))
            make.top.bottom.right.equalToSuperview()
        }

        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(Layout.horizontalInset)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(10))
            make.bottom.equalToSuperview().offset(-SCRYFrom(4))
        }

        cardView.addSubview(nameTextField)
        nameTextField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(14))
        }
    }
}
