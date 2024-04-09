//
//  ProfileInstructionsHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/27.
//

import UIKit

class ProfileInstructionsHeaderView: UITableViewHeaderFooterView {

    private var iconImageView: UIImageView!
    var titleLabel: UILabel!
    var arrowImageView: UIImageView!
    var lineView: UIView!
    var viewActionCallback: ((Bool)->Void)?
    
    var isShow: Bool = false {
        didSet {
            arrowImageView.image = UIImage(named: isShow ? "arrow_up" : "arrow_down")
            lineView.isHidden = isShow
        }
    }
    
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        contentView.backgroundColor = .white
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewClick)))
        setupUI()
    }
    
    @objc private func viewClick() {
        
        viewActionCallback?(!isShow)
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView(image: UIImage(named: "profile_instruction_tip"))
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(23))
            make.centerY.equalToSuperview()
        }
        
        titleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(54))
            make.right.equalTo(SCRXFrom(-54))
            make.centerY.equalToSuperview()
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_up"))
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-13))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(1)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
