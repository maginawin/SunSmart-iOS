//
//  ContentDisplayControlStyleViewCell.swift
//  SunSmart
//

import UIKit

class ContentDisplayControlStyleViewCell: UITableViewCell {

    var titleLabel: UILabel!
    private var bgView: UIView!
    private var noteLabel: UILabel!
    private var stackView: UIStackView!
    private var simpleCard: ControlStyleCardView!
    private var detailedCard: ControlStyleCardView!

    var selectionCallback: ((SpaceControlType) -> Void)?

    var selectedType: SpaceControlType = .simple {
        didSet {
            updateSelection()
        }
    }

    var note: String? {
        didSet {
            guard let note = note else {
                noteLabel.attributedText = nil
                return
            }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 6
            noteLabel.attributedText = NSAttributedString(string: note, attributes: [.paragraphStyle: style])
        }
    }

    var isEditable: Bool = true {
        didSet {
            simpleCard.isEnabled = isEditable
            detailedCard.isEnabled = isEditable
            simpleCard.alpha = isEditable ? 1 : 0.55
            detailedCard.alpha = isEditable ? 1 : 0.55
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        selectionCallback = nil
        selectedType = .simple
        isEditable = true
    }

    @objc private func selectSimple() {
        guard isEditable else { return }
        selectionCallback?(.simple)
    }

    @objc private func selectDetailed() {
        guard isEditable else { return }
        selectionCallback?(.detailed)
    }

    private func setupUI() {
        titleLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(16))
            make.height.equalTo(SCRYFrom(17))
        }

        bgView = UIView()
        bgView.layer.cornerRadius = SCRYFrom(10)
        bgView.backgroundColor = .white
        bgView.clipsToBounds = true
        contentView.addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalToSuperview()
        }

        noteLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light, fit: false)
        noteLabel.numberOfLines = 0
        bgView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(16))
        }

        simpleCard = ControlStyleCardView(
            imageName: "simple control type image",
            title: "simple_control_style".localizedString,
            subtitle: "simple_control_style_note".localizedString
        )
        detailedCard = ControlStyleCardView(
            imageName: "detailed control type image",
            title: "detailed_control_style".localizedString,
            subtitle: "detailed_control_style_note".localizedString
        )

        simpleCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectSimple)))
        detailedCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectDetailed)))

        stackView = UIStackView(arrangedSubviews: [simpleCard, detailedCard])
        stackView.axis = .horizontal
        stackView.spacing = SCRXFrom(12)
        stackView.distribution = .fillEqually
        bgView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(22))
            make.height.equalTo(SCRYFrom(188))
            make.bottom.equalTo(SCRYFrom(-16))
        }

        updateSelection()
    }

    private func updateSelection() {
        simpleCard.isSelected = selectedType == .simple
        detailedCard.isSelected = selectedType == .detailed
    }
}

private class ControlStyleCardView: UIView {

    private let imageView = UIImageView()
    private let titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .regular)
    private let subtitleLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
    private let indicatorImageView = UIImageView()

    var isEnabled: Bool = true {
        didSet {
            isUserInteractionEnabled = isEnabled
        }
    }

    var isSelected: Bool = false {
        didSet {
            layer.borderColor = (isSelected ? Bar_Color : Line_Color).cgColor
            indicatorImageView.image = UIImage(named: isSelected ? "purple selected" : "purple unselected")
        }
    }

    init(imageName: String, title: String, subtitle: String) {
        super.init(frame: .zero)
        layer.cornerRadius = SCRYFrom(14)
        layer.borderWidth = 1
        backgroundColor = .white
        imageView.image = UIImage(named: imageName)
        imageView.contentMode = .scaleAspectFit
        titleLabel.text = title
        titleLabel.textAlignment = .center
        subtitleLabel.text = subtitle
        subtitleLabel.textAlignment = .center
        setupUI()
        isSelected = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(17))
            make.right.equalTo(SCRXFrom(-17))
            make.top.equalTo(SCRYFrom(17))
            make.height.equalTo(SCRYFrom(68))
        }

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(12))
            make.height.equalTo(SCRYFrom(21))
        }

        addSubview(subtitleLabel)
        subtitleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(2))
            make.height.equalTo(SCRYFrom(18))
        }

        addSubview(indicatorImageView)
        indicatorImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(subtitleLabel.snp.bottom).offset(SCRYFrom(12))
            make.width.height.equalTo(SCRYFrom(16))
        }
    }
}
