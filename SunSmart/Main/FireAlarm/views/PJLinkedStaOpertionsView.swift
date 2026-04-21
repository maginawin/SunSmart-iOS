//
//  PJLinkedStaOpertionsView.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit

class PJLinkedStaOpertionsView: UIView {
    var createAction: (() -> Void)?

    private lazy var linkedButton: UIButton = {
        UIButton(
            title: "LINKED",
            titleSize: 16,
            titleWeight: .light,
            titleColor: Green_Color,
            target: self,
            action: #selector(handleCreate)
        )
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .white
        
        addSubview(linkedButton)
        linkedButton.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func handleCreate() {
        createAction?()
    }
}
