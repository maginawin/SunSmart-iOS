//
//  EmerFireAlarmMoniCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit
import SnapKit

final class EmerFireAlarmMoniCell: UICollectionViewCell {

    private enum Layout {
        static let circleInset = SCRXFrom(6)
        static let badgeSize = SCRXFrom(18)
        static let iconSize = SCRXFrom(28)
        static let titleTopSpacing = SCRYFrom(8)
        static let contentHorizontalInset = SCRXFrom(8)
    }

    private lazy var circleView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var contentStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [iconImageView, titleLabel])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = Layout.titleTopSpacing
        return stackView
    }()

    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 14, fontWeight: .light)
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()

    private lazy var badgeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCircleAppearance()
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        setNeedsLayout()
        layoutIfNeeded()
        updateCircleAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconImageView.image = nil
        titleLabel.text = nil
        badgeImageView.image = nil
        badgeImageView.isHidden = true
    }

    func configure(
        title: String,
        icon: UIImage? = UIImage(named: "group_1"),
        badgeImage: UIImage? = nil
    ) {
        titleLabel.text = title
        iconImageView.image = icon
        badgeImageView.image = badgeImage
        badgeImageView.isHidden = badgeImage == nil
        setNeedsLayout()
        layoutIfNeeded()
        updateCircleAppearance()
    }

    private func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false

        contentView.addSubview(circleView)
        circleView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(contentView.snp.width).offset(-Layout.circleInset * 2)
            make.height.equalTo(circleView.snp.width)
            make.top.greaterThanOrEqualToSuperview().offset(Layout.circleInset)
            make.bottom.lessThanOrEqualToSuperview().offset(-Layout.circleInset)
        }

        iconImageView.snp.makeConstraints { make in
            make.width.height.equalTo(Layout.iconSize)
        }

        circleView.addSubview(contentStackView)
        contentStackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.right.equalToSuperview().inset(Layout.contentHorizontalInset)
        }

        contentView.addSubview(badgeImageView)
        badgeImageView.snp.makeConstraints { make in
            make.top.equalTo(circleView.snp.top).offset(SCRYFrom(4))
            make.right.equalTo(circleView.snp.right).offset(SCRXFrom(2))
            make.width.height.equalTo(Layout.badgeSize)
        }
    }

    private func updateCircleAppearance() {
        let diameter = min(circleView.bounds.width, circleView.bounds.height)
        guard diameter > 0 else { return }
        circleView.layer.cornerRadius = diameter / 2
    }
}
