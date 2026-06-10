//
//  ContentDisplaySwitchViewCell.swift
//  SunSmart
//

import UIKit

class ContentDisplaySwitchViewCell: UITableViewCell {

    var titleLabel: UILabel!
    private var bgView: UIView!
    private var noteLabel: UILabel!
    private var lineView: UIView!
    private var optionsLabel: UILabel!
    private var enableSwitch: UISwitch!

    var switchValueCallback: ((Bool) -> Void)?

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

    var optionTitle: String? {
        didSet {
            optionsLabel.text = optionTitle
        }
    }

    var isOn: Bool {
        get { enableSwitch.isOn }
        set { enableSwitch.setOn(newValue, animated: false) }
    }

    var isEditable: Bool = true {
        didSet {
            enableSwitch.isEnabled = isEditable
            optionsLabel.alpha = isEditable ? 1 : 0.55
            enableSwitch.alpha = isEditable ? 1 : 0.55
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
        switchValueCallback = nil
        isEditable = true
    }

    @objc private func enableSwitchValueChanged(sender: UISwitch) {
        switchValueCallback?(sender.isOn)
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

        lineView = UIView()
        lineView.backgroundColor = Line_Color
        bgView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalToSuperview()
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(1)
        }

        optionsLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        bgView.addSubview(optionsLabel)
        optionsLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(lineView.snp.bottom).offset(SCRYFrom(13))
            make.bottom.equalTo(SCRYFrom(-14))
            make.width.lessThanOrEqualTo(SCRXFrom(230))
        }

        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged), for: .valueChanged)
        bgView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalTo(optionsLabel)
        }
    }
}
