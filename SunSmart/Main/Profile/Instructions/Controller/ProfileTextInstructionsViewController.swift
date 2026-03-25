//
//  ProfileTextInstructionsViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2026/1/5.
//

import UIKit

struct ProfileTextInstructionInfo {
    let title: String
    let content: String
}

class ProfileTextInstructionsViewController: UIViewController {
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    let instructions: [ProfileTextInstructionInfo]
    
    init(vcTitle: String, instructions: [ProfileTextInstructionInfo]) {
        self.instructions = instructions
        super.init(nibName: nil, bundle: nil)
        
        self.title = vcTitle
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

//        title = "calibration_instructions".localizedString
        view.backgroundColor = Background_Color
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        
        setupUI()
    }
    
    @objc private func close() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.bottom.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(10)
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.leading.equalTo(SCRXFrom(16))
            make.trailing.equalTo(SCRXFrom(-16))
            make.top.bottom.equalToSuperview()
            make.width.equalTo(scrollView.snp.width).offset(SCRXFrom(-32))
            make.height.greaterThanOrEqualTo(scrollView.snp.height).offset(-max(kSafeAreaBottomHeight, SCRYFrom(16)))
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8
//        paragraphStyle.headIndent = 16
        
        var lastNoteLabel: UILabel?
        instructions.enumerated().forEach { (index, info) in
            
            let titleLabel = UILabel(text: info.title, textColor: ImportantText_Color, fontSize: 14, fit: false)
            contentView.addSubview(titleLabel)
            titleLabel.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                if let lastNoteLabel = lastNoteLabel {
                    make.top.equalTo(lastNoteLabel.snp.bottom).offset(SCRYFrom(16))
                }else {
                    make.top.equalTo(SCRYFrom(22))
                }
            }
            
            let noteLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
            noteLabel.numberOfLines = 0
            noteLabel.attributedText = NSAttributedString(string: info.content, attributes: [.paragraphStyle: paragraphStyle])
            contentView.addSubview(noteLabel)
            noteLabel.snp.makeConstraints { make in
                make.left.right.equalTo(titleLabel)
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
                if index == instructions.count - 1 {
                    make.bottom.equalTo(SCRYFrom(-8)).priority(.low)
                }
            }
            lastNoteLabel = noteLabel
        }
        
    }

}
