//
//  SceneAddGroupTitleSectionView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/21.
//

import UIKit

class SceneAddGroupTitleSectionView: UICollectionReusableView {
        
    var titleLabel: UILabel!
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        titleLabel = UILabel(text: "choose_groups".localizedString, textColor: RGB(100, 116, 139), fontSize: 14, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.bottom.equalTo(-SCRYFrom(8))
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
