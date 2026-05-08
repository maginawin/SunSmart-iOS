//
//  EmerFireStatusTextCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit
import SnapKit

final class EmerFireStatusTextCell: UITableViewCell {

    private enum Layout {
        static let horizontalInset = SCRXFrom(12)
        static let verticalInset = SCRYFrom(4)
        static let cardRadius = SCRYFrom(10)
        static let contentInset = SCRXFrom(16)
        static let minHeight = SCRYFrom(44)
    }

    private var topConstraint: Constraint?
    private var bottomConstraint: Constraint?
    private var cardPosition: EmerFireCardPosition = .single
    var rightTapAction: (() -> Void)?

    private lazy var cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.cardRadius
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var leftLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    private lazy var rightLabel: UILabel = {
        let label = UILabel(text: nil, textColor: RGB(247, 99, 95), fontSize: 11, fontWeight: .light)
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.textAlignment = .right
        label.isUserInteractionEnabled = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let contentWidth = max(cardView.bounds.width - (Layout.contentInset * 2), 0)
        let halfWidth = max((contentWidth - SCRXFrom(12)) / 2, 0)
        leftLabel.preferredMaxLayoutWidth = halfWidth
        rightLabel.preferredMaxLayoutWidth = halfWidth
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        rightTapAction = nil
        rightLabel.text = nil
        rightLabel.attributedText = nil
    }

    func configure(
        leftText: String,
        rightText: String,
        rightAttributedText: NSAttributedString? = nil,
        rightTextColor: UIColor = RGB(247, 99, 95),
        cardPosition: EmerFireCardPosition = .single
    ) {
        leftLabel.text = leftText
        if let rightAttributedText {
            rightLabel.attributedText = rightAttributedText
        } else {
            rightLabel.text = rightText
        }
        rightLabel.textColor = rightTextColor
        self.cardPosition = cardPosition
        topConstraint?.update(offset: cardPosition.topInset)
        bottomConstraint?.update(offset: -cardPosition.bottomInset)
        applyCardStyle()
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            topConstraint = make.top.equalToSuperview().offset(Layout.verticalInset).constraint
            make.left.right.equalToSuperview().inset(Layout.horizontalInset)
            bottomConstraint = make.bottom.equalToSuperview().offset(-Layout.verticalInset).constraint
            make.height.greaterThanOrEqualTo(Layout.minHeight)
        }

        cardView.addSubview(leftLabel)
        cardView.addSubview(rightLabel)
        rightLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleRightTap)))

        leftLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(Layout.contentInset)
            make.top.bottom.equalToSuperview().inset(SCRYFrom(10))
            make.right.lessThanOrEqualTo(rightLabel.snp.left).offset(-SCRXFrom(12))
        }

        rightLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-Layout.contentInset)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(10))
            make.bottom.lessThanOrEqualToSuperview().offset(-SCRYFrom(10))
        }
    }

    private func applyCardStyle() {
        cardView.layer.cornerRadius = Layout.cardRadius
        cardView.layer.maskedCorners = cardPosition.maskedCorners
    }

    @objc private func handleRightTap() {
        rightTapAction?()
    }
}
