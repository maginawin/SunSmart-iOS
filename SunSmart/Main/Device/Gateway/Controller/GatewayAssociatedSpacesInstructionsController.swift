//
//  GatewayAssociatedSpacesInstructionsController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/28.
//

import UIKit

class GatewayAssociatedSpacesInstructionsController: UIViewController {

    private var contentView: UIView!
    private var imageView: UIImageView!
    private var noteLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "associated_spaces_instructions".localizedString
        
        view.backgroundColor = Background_Color
        
        navigationItem.leftBarButtonItem = UIBarButtonItem()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        
        setupUI()
    }
    
    @objc private func close() {
        navigationController?.popViewController(animated: true)
    }

    private func setupUI() {
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(10)
        view.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(7))
            make.bottom.equalTo(-max(kSafeAreaBottomHeight, SCRYFrom(8)))
        }
        
        imageView = UIImageView(image: UIImage(named: "gateway_associated_spaces"))
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.right.equalTo(SCRXFrom(-12))
            make.top.equalTo(SCRYFrom(39))
            make.height.equalTo(imageView.snp.width).multipliedBy(197 / 335.0)
        }
        
        noteLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = SCRYFrom(6)
        noteLabel.numberOfLines = 0
        noteLabel.attributedText = NSAttributedString(string: "associated_spaces_instructions_message".localizedString, attributes: [.paragraphStyle: style])
        contentView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.right.equalTo(imageView)
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(32))
        }
    }
    
}
