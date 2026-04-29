//
//  PJTopbtBoLabView.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit

final class PJTopbtBoLabView: UIView {

    private let imageName: String?
    private let image: UIImage?
    private let title: String
    private weak var target: AnyObject?
    private let action: Selector?

    lazy var button: UIButton = {
        let button = UIButton(normalImageName: imageName, target: target, action: action)
        if let image = image {
            button.setImage(image, for: .normal)
        }
        button.layer.cornerRadius = SCRYFrom(34)
        button.backgroundColor = Bar_Color
        return button
    }()

    lazy var titleLabel: UILabel = {
        UILabel(
            text: title,
            textColor: Title_Color,
            fontSize: 14,
            fontWeight: .light
        )
    }()

    init(
        imageName: String? = nil,
        image: UIImage? = nil,
        title: String,
        target: AnyObject?,
        action: Selector?
    ) {
        self.imageName = imageName
        self.image = image
        self.title = title
        self.target = target
        self.action = action
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(button)
        button.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(68))
        }

        addSubview(titleLabel)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalTo(button)
            make.top.equalTo(button.snp.bottom).offset(SCRYFrom(12))
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview()
        }
    }
}
