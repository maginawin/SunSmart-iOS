//
//  EmerFireAlarmInfoSectionHeaderView.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit
import SnapKit

final class EmerFireAlarmInfoSectionHeaderView: UITableViewHeaderFooterView {

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 15, fontWeight: .light)
        return label
    }()

    private let arrowImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "arrow_up_black"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var tapButton: UIButton = {
        let button = UIButton(type: .custom)
        button.addTarget(self, action: #selector(headerTapped), for: .touchUpInside)
        return button
    }()

    var tapHandler: (() -> Void)?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, showsArrow: Bool, isExpanded: Bool) {
        titleLabel.text = title
        arrowImageView.isHidden = !showsArrow
        arrowImageView.image = UIImage(named: isExpanded ? "arrow_up_black" : "arrow_down_black")
        tapButton.isEnabled = showsArrow
    }

    private func setupUI() {
        contentView.backgroundColor = Background_Color

        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        containerView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(20))
        }

        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualTo(arrowImageView.snp.left).offset(-SCRXFrom(12))
        }

        containerView.addSubview(tapButton)
        tapButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    @objc private func headerTapped() {
        tapHandler?()
    }
}
