//
//  ContentDisplayViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/9/8.
//

import UIKit

class ContentDisplayViewCell: UITableViewCell {

    var titleLabel: UILabel!
    var bgView: UIView!
    var disableModeImageView: UIImageView!
    var enableModeImageView: UIImageView!
    var noteLabel: UILabel!
    var lineView: UIView!
    var optionsLabel: UILabel!
    var enableSwitch: UISwitch!
    var switchValueCallback: ((Bool)->Void)?
    
    /// 描述
    var note: String? {
        didSet {
            guard let note = self.note else {
                self.noteLabel.attributedText = nil
                return
            }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 8
            noteLabel.attributedText = NSAttributedString(string: note, attributes: [.paragraphStyle: style])
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
    
    @objc private func enableSwitchValueChanged(sender: UISwitch) {
        switchValueCallback?(sender.isOn)
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(17))
        }
        
        bgView = UIView()
        bgView.layer.cornerRadius = SCRYFrom(10)
        bgView.backgroundColor = .white
        contentView.addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalToSuperview()
        }
        
        disableModeImageView = UIImageView()
        bgView.addSubview(disableModeImageView)
        disableModeImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview().multipliedBy(0.6)
            make.top.equalTo(SCRYFrom(20))
//            make.width.height.equalTo(106)
        }
        
        enableModeImageView = UIImageView()
        bgView.addSubview(enableModeImageView)
        enableModeImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview().multipliedBy(1.4)
            make.top.width.height.equalTo(disableModeImageView)
        }
        
        noteLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light, fit: false)
        noteLabel.numberOfLines = 0
        bgView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
//            make.bottom.equalTo(lineView.snp.top).offset(SCRYFrom(-16))
            make.top.equalTo(enableModeImageView.snp.bottom).offset(SCRYFrom(30))
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
