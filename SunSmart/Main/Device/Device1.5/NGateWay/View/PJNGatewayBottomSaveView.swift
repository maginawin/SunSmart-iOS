//
//  PJNGatewayBottomSaveView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewayBottomSaveView: UIView {

    var tapped: (() -> Void)?

    private let lineView = UIView()
    private let saveButton = UIButton(type: .system)
    private let safeAreaFillView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(enabled: Bool) {
        saveButton.isEnabled = enabled
    }

    private func setupUI() {
        backgroundColor = .white

        lineView.backgroundColor = Line_Color
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(1)
        }

        saveButton.setTitle("save".localizedString, for: .normal)
        saveButton.setTitleColor(Bar_Color, for: .normal)
        saveButton.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        saveButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .light)
        saveButton.backgroundColor = .white
        saveButton.addTarget(self, action: #selector(saveButtonAction), for: .touchUpInside)
        addSubview(saveButton)
        saveButton.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }

        safeAreaFillView.backgroundColor = .white
        addSubview(safeAreaFillView)
        safeAreaFillView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(saveButton.snp.bottom)
        }
    }

    @objc private func saveButtonAction() {
        tapped?()
    }
}
