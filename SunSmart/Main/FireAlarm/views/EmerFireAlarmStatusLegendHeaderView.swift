//
//  EmerFireAlarmStatusLegendHeaderView.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit
import SnapKit

final class EmerFireAlarmStatusLegendHeaderView: UIView {

    private enum Layout {
        static let height = SCRYFrom(56)
        static let horizontalInset = SCRXFrom(16)
        static let containerHorizontalInset = SCRXFrom(12)
        static let itemSpacing = SCRXFrom(14)
        static let indicatorSize = SCRXFrom(14)
        static let cornerRadius = SCRYFrom(2)
        static let containerCornerRadius = SCRYFrom(16)
    }

    private final class LegendItemView: UIView {
        private lazy var indicatorView: UIView = {
            let view = UIView()
            view.layer.cornerRadius = Layout.cornerRadius
            view.layer.masksToBounds = true
            return view
        }()

        private lazy var indicatorImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.isHidden = true
            return imageView
        }()

        private lazy var titleLabel: UILabel = {
            let label = UILabel(text: nil, textColor: Title_Color, fontSize: 10, fontWeight: .light)
            return label
        }()

        init(title: String, color: UIColor? = nil, image: UIImage? = nil) {
            super.init(frame: .zero)
            titleLabel.text = title
            setupUI()
            if let image {
                indicatorImageView.image = image.withRenderingMode(.alwaysOriginal)
                indicatorImageView.isHidden = false
                indicatorView.isHidden = true
            } else {
                indicatorView.backgroundColor = color
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupUI() {
            addSubview(indicatorView)
            indicatorView.snp.makeConstraints { make in
                make.left.centerY.equalToSuperview()
                make.width.height.equalTo(Layout.indicatorSize)
            }

            addSubview(indicatorImageView)
            indicatorImageView.snp.makeConstraints { make in
                make.edges.equalTo(indicatorView)
            }

            addSubview(titleLabel)
            titleLabel.snp.makeConstraints { make in
                make.left.equalTo(indicatorView.snp.right).offset(SCRXFrom(6))
                make.centerY.equalToSuperview()
                make.right.equalToSuperview()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Layout.height)
    }

    private lazy var triggeredItem = LegendItemView(title: "Triggered", image: UIImage(named: "sts2"))
    private lazy var resumeItem = LegendItemView(title: "Resume", image: UIImage(named: "sts5"))
    private lazy var inactiveItem = LegendItemView(title: "Inactive", image: UIImage(named: "sts6"))
    private lazy var disabledItem = LegendItemView(title: "Disabled", image: UIImage(named: "sts4"))

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [triggeredItem, resumeItem, inactiveItem, disabledItem])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Layout.itemSpacing
        return stackView
    }()

    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = RGB(247, 247, 249)
        view.layer.cornerRadius = Layout.containerCornerRadius
        view.layer.masksToBounds = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear

        addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(Layout.containerHorizontalInset)
            make.top.bottom.equalToSuperview().inset(SCRYFrom(6))
        }

        containerView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(Layout.horizontalInset)
            make.top.bottom.equalToSuperview()
        }
    }
}
