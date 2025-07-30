//
//  GatewayInformationHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/28.
//

import UIKit

class GatewayInformationHeaderView: UIView {

    var connectImageView: UIImageView!
    var contentLabel: UILabel!

    private var informationView: UIView!
    var gatewayStateImageView: UIImageView!
    var gatewayStateLabel: UILabel!
    
    var nodeCountLabel: UILabel!
    var nodeLabel: UILabel!
    
    var signalImageView: UIImageView!
    var signalLabel: UILabel!
    var networkTypeLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
//        XWHUDManager.imageGIF(with: <#T##Data#>)
        connectImageView = UIImageView()
        addSubview(connectImageView)
        connectImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
        }
        
        contentLabel = UILabel(text: "gateway_connecting_message".localizedString, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light, fit: false)
        contentLabel.textAlignment = .center
        addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-12))
        }
        
        informationView = UIView()
        addSubview(informationView)
        informationView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        gatewayStateImageView = UIImageView(image: UIImage(named: "gateway_online"))
        informationView.addSubview(gatewayStateImageView)
        gatewayStateImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview().multipliedBy(0.6)
            make.top.equalTo(SCRYFrom(4))
            
        }
        
    }
    
    
}
