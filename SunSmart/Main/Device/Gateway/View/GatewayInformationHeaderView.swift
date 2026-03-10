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
    
    func updateData(gateway: Gateway) {
        let gatewayModel = gateway.model
        let node = gateway.node
        let totalDeviceCount = gatewayModel.associatedSpaces.reduce(0, { (result, space) -> Int in result + space.deviceCount })
        nodeCountLabel.text = "(\(totalDeviceCount))"
        
        if node.state {
            gatewayStateImageView.image = UIImage(named: "gateway_online")
            gatewayStateLabel.text = "Online".localizedString
        }else {
            gatewayStateImageView.image = UIImage(named: "gateway_offline")
            gatewayStateLabel.text = "Offline".localizedString
        }
        
        // 是否插入sim卡
        if gatewayModel.isSimInserted {
            // 信号级别
            switch gatewayModel.signalLevel {
            case .goodSignal:
                signalLabel.text = "gateway_signal_good".localizedString
                signalImageView.image = UIImage(named: "gateway_signal_good")
            case .poorSignal:
                signalLabel.text = "gateway_signal_poor".localizedString
                signalImageView.image = UIImage(named: "gateway_signal_poor")
            case .noSignal:
                signalLabel.text = "gateway_signal_none".localizedString
                signalImageView.image = UIImage(named: "gateway_signal_none")
            case .unknownSignal:
                signalLabel.text = "gateway_signal_unknown".localizedString
                signalImageView.image = UIImage(named: "gateway_signal_unknown")
            case .signalError:
                signalLabel.text = "gateway_signal_error".localizedString
                signalImageView.image = UIImage(named: "gateway_signal_exception")
            }
        }else { // 无sim卡
            signalLabel.text = "gateway_sim_not_inserted".localizedString
            signalImageView.image = UIImage(named: "gateway_simcard_notdetecte")
        }
    
    }
    
    private func setupUI() {
        
        connectImageView = UIImageView()
        connectImageView.isHidden = true
        addSubview(connectImageView)
        connectImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(56))
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
        
        nodeCountLabel = UILabel(text: "(0)", textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
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
