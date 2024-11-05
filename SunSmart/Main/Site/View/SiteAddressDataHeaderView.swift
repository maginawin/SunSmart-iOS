//
//  SiteAddressDataHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/10/23.
//

import UIKit

class SiteAddressDataHeaderView: UITableViewHeaderFooterView {

    var deviceAddressLabel: UILabel!
    var groupAddressLabel: UILabel!
    var sceneAddressLabel: UILabel!
    var recycleAddressLabel: UILabel!
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        deviceAddressLabel = UILabel(text: "", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        addSubview(deviceAddressLabel)
        deviceAddressLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalToSuperview()
        }
        
        groupAddressLabel = UILabel(text: "", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        addSubview(groupAddressLabel)
        groupAddressLabel.snp.makeConstraints { make in
            make.left.equalTo(self.snp.centerX)
            make.centerY.equalTo(deviceAddressLabel)
        }
        
        sceneAddressLabel = UILabel(text: "", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        addSubview(sceneAddressLabel)
        sceneAddressLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceAddressLabel)
            make.bottom.equalTo(SCRYFrom(-6))
        }
        
        recycleAddressLabel = UILabel(text: "", textColor: RGB(100, 136, 139), fontSize: 13, fontWeight: .light)
        addSubview(recycleAddressLabel)
        recycleAddressLabel.snp.makeConstraints { make in
            make.left.equalTo(groupAddressLabel)
            make.centerY.equalTo(sceneAddressLabel)
        }
        
        
    }
    
    
}
