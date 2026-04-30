//
//  PJEightKeySwitchInfoRowView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJEightKeySwitchInfoRowView: UIView {

    enum AccessoryStyle {
        case none
        case arrow
        case valueWithArrow
        case toggle
    }

    let switchControl = UISwitch()
    var tapAction: (() -> Void)?

    private let accessoryStyle: AccessoryStyle

    private lazy var titleLabel: UILabel = {
        UILabel(text: title, textColor: Title_Color, fontSize: 14, fontWeight: .light)
    }()

    private lazy var valueLabel: UILabel = {
        let label = UILabel(text: nil, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        label.textAlignment = .right
        return label
    }()

    private lazy var arrowImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "arrow_right"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var lineView: UIView = {
        let view = UIView()
        view.backgroundColor = Line_Color
        return view
    }()

    private let title: String

    init(title: String, accessory: AccessoryStyle) {
        self.title = title
        self.accessoryStyle = accessory
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setValue(_ value: String?) {
        valueLabel.text = value
    }

    private func setupUI() {
        backgroundColor = .clear

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }

        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalToSuperview()
            make.bottom.equalToSuperview()
            make.height.equalTo(1)
        }

        switch accessoryStyle {
        case .toggle:
            switchControl.onTintColor = Bar_Color
            addSubview(switchControl)
            switchControl.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-16))
                make.centerY.equalToSuperview()
            }
        case .arrow:
            addSubview(arrowImageView)
            arrowImageView.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-12))
                make.centerY.equalToSuperview()
                make.width.height.equalTo(SCRXFrom(16))
            }
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        case .valueWithArrow:
            addSubview(arrowImageView)
            arrowImageView.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-12))
                make.centerY.equalToSuperview()
                make.width.height.equalTo(SCRXFrom(16))
            }

            addSubview(valueLabel)
            valueLabel.snp.makeConstraints { make in
                make.right.equalTo(arrowImageView.snp.left).offset(SCRXFrom(-12))
                make.centerY.equalToSuperview()
                make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(16))
            }
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        case .none:
            addSubview(valueLabel)
            valueLabel.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-16))
                make.centerY.equalToSuperview()
                make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(16))
            }
        }
    }

    @objc private func handleTap() {
        tapAction?()
    }
}
