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
    
    private var signalContentView: UIView!
    private var signalView: UIView!
    var signalImageView: UIImageView!
    var signalLabel: UILabel!
    var networkTypeLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 展示连接中UI
    func showConnectingUI() {
        
        if let filePath = Bundle.main.path(forResource: "XWHUDManager_loading", ofType: "gif"),
            let imageData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
            connectImageView.image = XWHUDManager.imageGIF(with: imageData)
        }

        connectImageView.isHidden = false
        contentLabel.isHidden = false
        
        informationView.isHidden = true
    }
    
    /// 隐藏连接中UI
    func hideConnectingUI() {
        connectImageView.image = nil
        connectImageView.isHidden = true
        contentLabel.isHidden = true
        
        informationView.isHidden = false
    }
    
    private func setupUI() {
        
        connectImageView = UIImageView()
        connectImageView.isHidden = true
        addSubview(connectImageView)
        connectImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
        }
        
        contentLabel = UILabel(text: "gateway_connecting_message".localizedString, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light, fit: false)
        contentLabel.textAlignment = .center
        contentLabel.isHidden = true
        addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(-12)
        }
        
        informationView = UIView()
        addSubview(informationView)
        informationView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        
        gatewayStateLabel = UILabel(text: "online".localizedString, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light, fit: false)
        informationView.addSubview(gatewayStateLabel)
        gatewayStateLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview().multipliedBy(0.5)
            make.bottom.equalTo(SCRYFrom(-12))
        }
        
        gatewayStateImageView = UIImageView(image: UIImage(named: "gateway_online"))
        informationView.addSubview(gatewayStateImageView)
        gatewayStateImageView.snp.makeConstraints { make in
            make.centerX.equalTo(gatewayStateLabel)
            make.bottom.equalTo(gatewayStateLabel.snp.top).offset(SCRYFrom(-2))
        }
        
        nodeLabel = UILabel(text: "node".localizedString, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light, fit: false)
        informationView.addSubview(nodeLabel)
        nodeLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(gatewayStateLabel)
        }
        
        nodeCountLabel = UILabel(text: "(70)", textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        informationView.addSubview(nodeCountLabel)
        nodeCountLabel.snp.makeConstraints { make in
            make.centerX.equalTo(nodeLabel)
            make.bottom.equalTo(nodeLabel.snp.top).offset(SCRYFrom(-10))
        }
        
        signalContentView = UIView()
        informationView.addSubview(signalContentView)
        signalContentView.snp.makeConstraints { make in
            make.centerX.equalToSuperview().multipliedBy(1.5)
            make.bottom.equalTo(nodeLabel)
            make.width.greaterThanOrEqualTo(SCRXFrom(48))
        }
        
        signalView = UIView()
        signalContentView.addSubview(signalView)
        signalView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
        }
        
        signalImageView = UIImageView(image: UIImage(named: "gateway_signal_good"))
        signalView.addSubview(signalImageView)
        signalImageView.snp.makeConstraints { make in
            make.top.left.bottom.equalToSuperview()
        }
        
        networkTypeLabel = UILabel(text: "4G", textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        signalView.addSubview(networkTypeLabel)
        networkTypeLabel.snp.makeConstraints { make in
            make.left.equalTo(signalImageView.snp.right).offset(2)
            make.bottom.equalTo(signalImageView).offset(-2)
            make.right.equalToSuperview()
        }
          
        signalLabel = UILabel(text: "Poor Signal", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light, fit: false)
        signalContentView.addSubview(signalLabel)
        signalLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview().priority(.low)
            make.bottom.equalToSuperview()
            make.top.equalTo(signalImageView.snp.bottom).offset(6)
        }
        
    }
    
    
}
