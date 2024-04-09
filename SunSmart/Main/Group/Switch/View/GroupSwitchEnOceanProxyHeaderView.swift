//
//  GroupSwitchEnOceanProxyHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/18.
//

import UIKit

class GroupSwitchEnOceanProxyHeaderView: UITableViewHeaderFooterView {

    var titleLabel: UILabel!
    var contentLabel: UILabel!
    var arrowImageView: UIImageView!
    var lineView: UIView!
    var viewActionCallback: ((Bool)->Void)?
    
    var isShow: Bool = false {
        didSet {
            arrowImageView.image = UIImage(named: isShow ? "arrow_up" : "arrow_down")
//            lineView.isHidden = isShow
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
        
        titleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        contentLabel = UILabel(text: "switch_not_linked".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-38))
            make.centerY.equalToSuperview()
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_up"))
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(243, 243, 243, 0.7)
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
