//
//  EmerFireAlarmInfoRowCell.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//
//信息页的cell
import UIKit
import SnapKit

final class EmerFireAlarmInfoRowCell: UITableViewCell {

    private enum Layout {
        static let horizontalInset = SCRXFrom(16)
        static let verticalInset = SCRYFrom(14)
        static let copyButtonSize = SCRYFrom(20)
        static let copySpacing = SCRXFrom(8)
    }

    private let titleLabel: UILabel = {
        let label = UILabel(text: nil, textColor: Title_Color, fontSize: 15, fontWeight: .light)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel(text: nil, textColor: AssistText_Color, fontSize: 14, fontWeight: .light)
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.textAlignment = .right
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    private lazy var copyButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "copy"), for: .normal)
        button.addTarget(self, action: #selector(copyAction), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private let separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Line_Color
        return view
    }()

    private var copyText: String?
    private var copyHandler: ((String) -> Void)?
    private var valueRightToSuperviewConstraint: Constraint?
    private var valueRightToCopyConstraint: Constraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let contentWidth = max(contentView.bounds.width - (Layout.horizontalInset * 2), 0)
        let halfWidth = max((contentWidth - SCRXFrom(12)) / 2, 0)
        titleLabel.preferredMaxLayoutWidth = halfWidth
        valueLabel.preferredMaxLayoutWidth = halfWidth
    }

    func configure(
        title: String,
        value: String,
        showsCopyButton: Bool = false,
        showsSeparator: Bool = true,
        copyHandler: ((String) -> Void)? = nil
    ) {
        titleLabel.text = title
        valueLabel.text = value
        copyText = value
        self.copyHandler = copyHandler
        copyButton.isHidden = !showsCopyButton
        separatorView.isHidden = !showsSeparator
        valueRightToSuperviewConstraint?.update(offset: showsCopyButton ? -SCRXFrom(44) : -Layout.horizontalInset)
        valueRightToCopyConstraint?.update(offset: showsCopyButton ? -Layout.copySpacing : 0)
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .white
        contentView.backgroundColor = .white

        contentView.addSubview(copyButton)
        copyButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-Layout.horizontalInset)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Layout.copyButtonSize)
        }

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(Layout.horizontalInset)
            make.top.bottom.equalToSuperview().inset(Layout.verticalInset)
        }

        contentView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(Layout.verticalInset)
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(12))
            valueRightToSuperviewConstraint = make.right.equalToSuperview().offset(-Layout.horizontalInset).constraint
            valueRightToCopyConstraint = make.right.equalTo(copyButton.snp.left).offset(0).constraint
        }

        contentView.addSubview(separatorView)
        separatorView.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.right.equalToSuperview().offset(-Layout.horizontalInset)
            make.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }
    
    //更新约束
    func updateTitlConstant(update: Bool){
        if update {
            titleLabel.snp.updateConstraints { make in
                make.left.equalToSuperview().offset(Layout.horizontalInset*2)
            }
        }
    }
    

    @objc private func copyAction() {
        guard let copyText else {
            return
        }
        copyHandler?(copyText)
    }
}
