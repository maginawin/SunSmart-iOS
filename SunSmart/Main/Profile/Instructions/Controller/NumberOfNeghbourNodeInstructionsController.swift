//
//  NumberOfNeghbourNodeInstructionsController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/26.
//

import UIKit

class NumberOfNeghbourNodeInstructionsController: UIViewController {

    private var imageView: UIImageView!
    private var personImageView: UIImageView!
    private var contentLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        title = "number_of_neighbour_node".localizedString
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        imageView = UIImageView(image: UIImage(named: "path_number_neighbour"))
        view.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(11))
//            make.top.equalTo((navigationController?.navigationBar.height ?? kNavigationHeight) + SCRYFrom(11))
            make.height.equalTo(imageView.snp.width).multipliedBy(112 / 343.0)
        }
        
        personImageView = UIImageView(image: UIImage(named: "profile_person_big"))
        imageView.addSubview(personImageView)
        personImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(-14)
        }
        
        
        contentLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        contentLabel.numberOfLines = 0
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        let textAttStr = NSAttributedString(string: "number_neighbour_node_instruction_desc".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        contentLabel.attributedText = textAttStr
        view.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(32))
            make.right.equalTo(SCRXFrom(-32))
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(16))
        }
        
    }
  
    @objc private func back() {
        navigationController?.popViewController(animated: true)
    }

}
