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

    private enum Layout {
        static let horizontalInset = SCRXFrom(12)
        static let verticalInset = SCRYFrom(4)
        static let cardRadius = SCRYFrom(10)
    }

    private lazy var cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.cardRadius
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 228 / 255.0, green: 229 / 255.0, blue: 235 / 255.0, alpha: 1)
        view.isHidden = true
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 12, fontWeight: .regular)
        label.numberOfLines = 0
        return label
    }()

    private lazy var detailStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = SCRYFrom(6)
        stackView.alignment = .fill
        stackView.distribution = .fill
        return stackView
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
        applyCardStyle()
    }

    func configure(title: String, lines: [String], cardPosition: EmerFireCardPosition = .single) {
        titleLabel.text = title
        rebuildDetailStack(lines: lines)
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
        }

        cardView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(14))
        }

        cardView.addSubview(detailStackView)
        detailStackView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalToSuperview().offset(-SCRYFrom(14))
        }

        cardView.addSubview(separatorView)
        separatorView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }

    private func applyCardStyle() {
        cardView.layer.cornerRadius = Layout.cardRadius
        cardView.layer.maskedCorners = cardPosition.maskedCorners
        separatorView.isHidden = true
    }

    private func rebuildDetailStack(lines: [String]) {
        detailStackView.arrangedSubviews.forEach { view in
            detailStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        lines.forEach { line in
            let label = UILabel(text: line, textColor: Message_Color, fontSize: 10, fontWeight: .light)
            label.numberOfLines = 0
            detailStackView.addArrangedSubview(label)
        }
    }
}
