//
//  EmerFireSelectionCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit
import SnapKit

final class EmerFireSelectionCell: UITableViewCell {

    private var cardPosition: EmerFireCardPosition = .single
    private var topConstraint: Constraint?
    private var bottomConstraint: Constraint?

    private enum Layout {
        static let horizontalInset = SCRXFrom(12)
        static let verticalInset = SCRYFrom(4)
        static let cardRadius = SCRYFrom(10)
        static let contentRadius = SCRYFrom(8)
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

    private lazy var valueContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.contentRadius
        view.layer.borderWidth = 1
        view.layer.borderColor = Line_Color1.cgColor
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    private lazy var valueLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 11, fontWeight: .light)
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.textAlignment = .left
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    private lazy var arrowView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.right"))
        imageView.tintColor = AssistText_Color
        imageView.contentMode = .scaleAspectFit
        return imageView
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
        titleLabel.preferredMaxLayoutWidth = max(cardView.bounds.width - SCRXFrom(32), 0)
        valueLabel.preferredMaxLayoutWidth = max(valueContainerView.bounds.width - SCRXFrom(39), 0)
        applyCardStyle()
    }

    func configure(title: String, value: String, cardPosition: EmerFireCardPosition = .single) {
        titleLabel.text = title
        valueLabel.text = value
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
            make.left.equalTo(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(12))
            make.right.equalToSuperview().offset(-SCRXFrom(16))
        }

        cardView.addSubview(valueContainerView)
        valueContainerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalToSuperview().offset(-SCRYFrom(12))
            make.height.greaterThanOrEqualTo(SCRYFrom(34))
        }

        valueContainerView.addSubview(arrowView)
        arrowView.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-SCRXFrom(12))
            make.centerY.equalToSuperview()
            make.width.equalTo(SCRXFrom(7))
            make.height.equalTo(SCRXFrom(12))
        }

        valueContainerView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(arrowView.snp.left).offset(-SCRXFrom(8))
            make.left.equalToSuperview().offset(SCRXFrom(12))
            make.top.greaterThanOrEqualToSuperview().offset(SCRYFrom(6))
            make.bottom.lessThanOrEqualToSuperview().offset(-SCRYFrom(6))
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
}

final class EmerFireRestoreActionCell: UITableViewCell {

    var actionDidChange: ((EmergencyFireRestoreActionType) -> Void)?

    private var options: [LinkedEmerFireRestoreActionOption] = []
    private var selectedType: EmergencyFireRestoreActionType = .restoreAuto
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
        let label = UILabel(text: "Action type:", textColor: Title_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = SCRYFrom(10)
        return stackView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        actionDidChange = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.preferredMaxLayoutWidth = max(cardView.bounds.width - SCRXFrom(32), 0)
        applyCardStyle()
    }

    func configure(
        options: [LinkedEmerFireRestoreActionOption],
        selectedType: EmergencyFireRestoreActionType,
        cardPosition: EmerFireCardPosition = .single
    ) {
        self.options = options
        self.selectedType = selectedType
        self.cardPosition = cardPosition
        topConstraint?.update(offset: cardPosition.topInset)
        bottomConstraint?.update(offset: -cardPosition.bottomInset)
        reloadOptions()
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
            make.top.equalToSuperview().offset(SCRYFrom(12))
        }

        cardView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(12))
            make.bottom.equalToSuperview().offset(-SCRYFrom(12))
        }

        cardView.addSubview(separatorView)
        separatorView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }

    private func reloadOptions() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        options.enumerated().forEach { index, option in
            let button = UIButton(type: .custom)
            button.tag = index
            button.contentHorizontalAlignment = .left
            button.titleLabel?.font = FONTS(14)
            button.titleLabel?.numberOfLines = 0
            button.setTitle(option.title, for: .normal)
            button.setTitleColor(Title_Color, for: .normal)
            button.setImage(UIImage(named: option.type == selectedType ? "select" : "select_un"), for: .normal)
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: SCRXFrom(8))
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: 0)
            button.addTarget(self, action: #selector(optionAction(_:)), for: .touchUpInside)
            button.snp.makeConstraints { make in
                make.height.greaterThanOrEqualTo(SCRYFrom(26))
            }
            stackView.addArrangedSubview(button)
        }
    }

    @objc private func optionAction(_ sender: UIButton) {
        guard options.indices.contains(sender.tag) else { return }
        let newType = options[sender.tag].type
        guard newType != selectedType else { return }
        selectedType = newType
        reloadOptions()
        actionDidChange?(newType)
    }

    private func applyCardStyle() {
        cardView.layer.cornerRadius = Layout.cardRadius
        cardView.layer.maskedCorners = cardPosition.maskedCorners
        separatorView.isHidden = true
    }
}
