//
//  EmerFireInfoCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit
import SnapKit

final class EmerFireInfoCell: UITableViewCell {

    private var cardPosition: EmerFireCardPosition = .single
    private var topConstraint: Constraint?
    private var bottomConstraint: Constraint?
    private var detailHeightConstraint: Constraint?

    private enum Layout {
        static let horizontalInset = SCRXFrom(16)
        static let verticalInset = SCRXFrom(8)
    }

    private lazy var cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    private lazy var separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 228 / 255.0, green: 229 / 255.0, blue: 235 / 255.0, alpha: 1)
        view.isHidden = true
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: RGB(46, 49, 93), fontSize: 16, fontWeight: .light)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    private lazy var detailTextView: UITextView = {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byCharWrapping
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.required, for: .vertical)
        return textView
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
        let preferredWidth = max(cardView.bounds.width, 0)
        if titleLabel.preferredMaxLayoutWidth != preferredWidth {
            titleLabel.preferredMaxLayoutWidth = preferredWidth
        }
        updateDetailTextViewHeightIfNeeded()
        applyCardStyle()
    }

    func configure(title: String, lines: [String], cardPosition: EmerFireCardPosition = .single) {
        titleLabel.text = title
        detailTextView.attributedText = detailAttributedText(lines: lines)
        detailTextView.invalidateIntrinsicContentSize()
        self.cardPosition = cardPosition
        topConstraint?.update(offset: cardPosition.topInset)
        bottomConstraint?.update(offset: -cardPosition.bottomInset)
        setNeedsLayout()
        layoutIfNeeded()
        updateDetailTextViewHeightIfNeeded()
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
        }

        cardView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalToSuperview()
        }

        cardView.addSubview(detailTextView)
        detailTextView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(4))
            make.bottom.equalToSuperview()
            detailHeightConstraint = make.height.greaterThanOrEqualTo(0).constraint
        }

        cardView.addSubview(separatorView)
        separatorView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }

    private func applyCardStyle() {
        separatorView.isHidden = true
    }

    private func detailAttributedText(lines: [String]) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = SCRYFrom(22)
        paragraphStyle.maximumLineHeight = SCRYFrom(22)
        paragraphStyle.lineBreakMode = .byCharWrapping

        return NSAttributedString(
            string: lines.joined(separator: "\n"),
            attributes: [
                .font: UIFont.systemFont(ofSize: FontFit(12), weight: .regular),
                .foregroundColor: RGB(100, 116, 139),
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private func updateDetailTextViewHeightIfNeeded() {
        let targetWidth = max(detailTextView.bounds.width, cardView.bounds.width)
        guard targetWidth > 0 else { return }
        let fittingSize = detailTextView.sizeThatFits(CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude))
        detailHeightConstraint?.update(offset: ceil(fittingSize.height))
    }
}
