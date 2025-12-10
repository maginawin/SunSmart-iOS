//
//  DevicePowerCalibrationInstructionsController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/9.
//

import UIKit

class DevicePowerCalibrationInstructionsController: UIViewController {

    struct InstructionInfo {
        let title: String
        let content: String
    }
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private let instructions: [InstructionInfo] = [
        .init(title: "calibration".localizedString, content: "calibration_instructions_note_1".localizedString),
        .init(title: "separate_calibration".localizedString, content: "calibration_instructions_note_2".localizedString),
        .init(title: "calibrate_all_devices".localizedString, content: "calibration_instructions_note_3".localizedString)
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "calibration_instructions".localizedString
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
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.headIndent = 16
        
        var lastNoteLabel: UILabel?
        instructions.enumerated().forEach { (index, info) in
            
            let titleLabel = UILabel(text: info.title, textColor: ImportantText_Color, fontSize: 15, fit: false)
            contentView.addSubview(titleLabel)
            titleLabel.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(20))
                make.right.equalTo(SCRXFrom(-20))
                if let lastNoteLabel = lastNoteLabel {
                    make.top.equalTo(lastNoteLabel.snp.bottom).offset(SCRYFrom(16))
                }else {
                    make.top.equalTo(SCRYFrom(6))
                }
            }
            
            let noteLabel = UILabel(text: nil, textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
            noteLabel.numberOfLines = 0
            noteLabel.attributedText = NSAttributedString(string: info.content, attributes: [.paragraphStyle: paragraphStyle])
            contentView.addSubview(noteLabel)
            noteLabel.snp.makeConstraints { make in
                make.left.right.equalTo(titleLabel)
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
                if index == instructions.count - 1 {
                    make.bottom.equalToSuperview()
                }
            }
            lastNoteLabel = noteLabel
        }
        
    }
    


}
