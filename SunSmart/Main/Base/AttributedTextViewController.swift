//
//  AttributedTextViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/2.
//

import UIKit

class AttributedTextViewController: UIViewController {

    private lazy var textView: UITextView = {
        let textV = UITextView()
        textV.textColor = TextBlack_Color
        textV.font = UIFont.systemFont(ofSize: 14, weight: .light)
        textV.isEditable = false
        textV.backgroundColor = .clear
        textV.textContainerInset = .zero
        textV.textContainer.lineFragmentPadding = 0
        return textV
    }()
    
    let attributedStr: NSAttributedString
    
    init(vcTitle: String, attributedStr: NSAttributedString) {
        self.attributedStr = attributedStr
        super.init(nibName: nil, bundle: nil)
        self.title = vcTitle
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        textView.attributedText = attributedStr
        
        view.backgroundColor = Background_Color
        view.addSubview(textView)
        textView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(20))
//            make.top.equalTo(SCRYFrom(20) + (navigationController?.navigationBar.frame.maxY ?? kNavigationHeight))
            make.bottom.equalTo(SCRYFrom(-20))
        }
    }
    

}
