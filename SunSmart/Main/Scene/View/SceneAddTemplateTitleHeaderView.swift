//
//  SceneAddTemplateTitleHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/20.
//

import UIKit

class SceneAddTemplateTitleHeaderView: UITableViewHeaderFooterView {

    var nameLabel: UILabel!
    var arrowImageView: UIImageView!
    var lineView: UIView!
    
    var isShow: Bool = false {
        didSet {
            arrowImageView.image = UIImage(named: isShow ? "arrow_up" : "arrow_down")
        }
    }
    
    var showHideCallback: ((Bool)->Void)?
    
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewClickAction)))
        
        nameLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 15)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(15))
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_down"))
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-14))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// view点击回调
    @objc private func viewClickAction() {
        
        isShow = !isShow
        
        showHideCallback?(isShow)
//        UIView.animate(withDuration: <#T##TimeInterval#>, animations: <#T##() -> Void#>)
    }
    
}
