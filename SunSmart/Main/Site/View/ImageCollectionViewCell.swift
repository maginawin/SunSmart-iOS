//
//  ImageCollectionViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import UIKit

class ImageCollectionViewCell: UICollectionViewCell {
    
    var imageView: UIImageView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRXFrom(8)
        layer.borderColor = Bar_Color.cgColor
        layer.borderWidth = 0
        clipsToBounds = true
        
        imageView = UIImageView()
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
