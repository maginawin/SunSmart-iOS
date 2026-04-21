//
//  DeviceBottomActionView.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit

final class DeviceBottomActionView: UIView {

    static let contentHeight = SCRYFrom(56)
    static var preferredHeight: CGFloat {
        contentHeight + (isIPad ? 0 : kSafeAreaBottomHeight)
    }

    var deleteAction: (() -> Void)?
    var saveAction: (() -> Void)?
    var createAction: (() -> Void)?

    private lazy var lineView: UIView = {
        let view = UIView()
        view.backgroundColor = Line_Color
        return view
    }()

    private lazy var deleteButton: UIButton = {
        UIButton(
            title: "alert_item_delete".localizedString,
            titleSize: 16,
            titleWeight: .light,
            titleColor: Red_Color,
            target: self,
            action: #selector(handleDelete)
        )
    }()

    private lazy var buttonLineView: UIView = {
        let view = UIView()
        view.backgroundColor = Line_Color1
        return view
    }()

    private lazy var saveButton: UIButton = {
        UIButton(
            title: "save".localizedString,
            titleSize: 16,
            titleWeight: .light,
            titleColor: Title_Done_Color,
            target: self,
            action: #selector(handleSave)
        )
    }()

    private lazy var createButton: UIButton = {
        UIButton(
            title: "CREATE".localizedString,
            titleSize: 16,
            titleWeight: .light,
            titleColor: Title_Done_Color,
            target: self,
            action: #selector(handleCreate)
        )
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCreateMode(_ isCreateMode: Bool) {
        createButton.isHidden = !isCreateMode
        deleteButton.isHidden = isCreateMode
        saveButton.isHidden = isCreateMode
        buttonLineView.isHidden = isCreateMode
    }

    @objc private func handleDelete() {
        deleteAction?()
    }

    @objc private func handleSave() {
        saveAction?()
    }

    @objc private func handleCreate() {
        createAction?()
    }

    private func setupUI() {
        backgroundColor = .white

        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(1)
        }

        addSubview(deleteButton)
        deleteButton.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalTo(Self.contentHeight)
            make.right.equalTo(snp.centerX)
        }

        addSubview(buttonLineView)
        buttonLineView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(deleteButton)
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(40))
        }

        addSubview(saveButton)
        saveButton.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
            make.left.equalTo(snp.centerX)
            make.height.equalTo(deleteButton)
        }

        createButton.isHidden = true
        addSubview(createButton)
        createButton.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(deleteButton)
        }
    }
}
