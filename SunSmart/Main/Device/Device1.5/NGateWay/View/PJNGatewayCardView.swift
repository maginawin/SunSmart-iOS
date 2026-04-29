//
//  PJNGatewayCardView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewayCardView: UIView {

    let contentStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(18)
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(hex: 0xE4E8F1).cgColor

        addSubview(contentStack)
        contentStack.axis = .vertical
        contentStack.spacing = SCRYFrom(10)
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: SCRYFrom(14), left: SCRXFrom(16), bottom: SCRYFrom(14), right: SCRXFrom(16))
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func embed(_ view: UIView) {
        contentStack.addArrangedSubview(view)
    }
}
