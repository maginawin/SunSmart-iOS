//
//  BatchImportResultHelpController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/30.
//

import UIKit

class BatchImportResultHelpController: UIViewController {

    private var contentView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "help".localizedString
        navigationItem.leftBarButtonItem = UIBarButtonItem()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        view.backgroundColor = Background_Color
        
        
        setupUI()
    }
    
    @objc private func close() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupUI() {
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(15)
        view.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo((navigationController?.navigationBar.height ?? 0) + SCRYFrom(7))
        }
        
        let presenceEditorTitleLabel = UILabel(text: "presence_editor".localizedString, textColor: TextBlack_Color, fontSize: 16, fit: false)
        contentView.addSubview(presenceEditorTitleLabel)
        presenceEditorTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(20))
        }
        
        let presenceEditorDescLabel = UILabel(text: "presence_editor_help_message".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        presenceEditorDescLabel.numberOfLines = 0
        contentView.addSubview(presenceEditorDescLabel)
        presenceEditorDescLabel.snp.makeConstraints { make in
            make.left.right.equalTo(presenceEditorTitleLabel)
            make.top.equalTo(presenceEditorTitleLabel.snp.bottom).offset(SCRYFrom(12))
        }
        
        let invalidTitleLabel = UILabel(text: "invalid".localizedString, textColor: TextBlack_Color, fontSize: 16, fit: false)
        contentView.addSubview(invalidTitleLabel)
        invalidTitleLabel.snp.makeConstraints { make in
            make.left.right.equalTo(presenceEditorDescLabel)
            make.top.equalTo(presenceEditorDescLabel.snp.bottom).offset(SCRYFrom(24))
        }
        
        let invalidDescLabel = UILabel(text: "invalid_help_message".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        invalidDescLabel.numberOfLines = 0
        contentView.addSubview(invalidDescLabel)
        invalidDescLabel.snp.makeConstraints { make in
            make.left.right.equalTo(invalidTitleLabel)
            make.top.equalTo(invalidTitleLabel.snp.bottom).offset(SCRYFrom(12))
        }
        
        let alreadyExistTitleLabel = UILabel(text: "already_exist".localizedString, textColor: TextBlack_Color, fontSize: 16, fit: false)
        contentView.addSubview(alreadyExistTitleLabel)
        alreadyExistTitleLabel.snp.makeConstraints { make in
            make.left.right.equalTo(invalidTitleLabel)
            make.top.equalTo(invalidDescLabel.snp.bottom).offset(SCRYFrom(24))
        }
        
        let alreadyExistDescLabel = UILabel(text: "already_exist_help_message".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        alreadyExistDescLabel.numberOfLines = 0
        contentView.addSubview(alreadyExistDescLabel)
        alreadyExistDescLabel.snp.makeConstraints { make in
            make.left.right.equalTo(alreadyExistTitleLabel)
            make.top.equalTo(alreadyExistTitleLabel.snp.bottom).offset(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-20))
        }
        
    }


}
