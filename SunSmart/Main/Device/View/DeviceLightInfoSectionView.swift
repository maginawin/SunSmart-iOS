//
//  DeviceLightInfoSectionView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/10/17.
//

import UIKit

class DeviceLightInfoSectionView: UITableViewHeaderFooterView {

    var titleLabel: UILabel!
    var contentLabel: UILabel!
    var showImageView: UIImageView!
    private var bgView: UIView!
    var lineView: UIView!
    var sectionViewClickCallback: (()->Void)?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
//        backgroundColor = .white
        setupUI()
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewClick)))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func viewClick() {
        
        sectionViewClickCallback?()
    }
    
    private func setupUI() {
        
        bgView = UIView()
        bgView.backgroundColor = .white
        addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        contentLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
//        contentLabel.textAlignment = .right
        contentLabel.isHidden = true
        addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-15))
            make.centerY.equalToSuperview()
            make.width.lessThanOrEqualTo(SCRXFrom(180))
//            make.left.equalTo(SCRXFrom(120))
        }
        
        showImageView = UIImageView(image: UIImage(named: "arrow_down"))
        showImageView.isHidden = true
        addSubview(showImageView)
        showImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(243, 243, 243)
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
    }
}
