//
//  GatewayInformationHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/28.
//

import UIKit

final class GatewayHeaderStatusItemView: UIView {

    private let iconImageView = UIImageView()
    private let titleLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
    private let statusLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light, fit: false)

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(iconName: String, title: String?, status: String, iconSize: CGFloat) {
        iconImageView.image = UIImage(named: iconName)
        titleLabel.text = title
        let showsTitle = !(title?.isEmpty ?? true)
        titleLabel.isHidden = !showsTitle
        statusLabel.text = status

        iconImageView.snp.remakeConstraints { make in
            if showsTitle {
                make.bottom.equalTo(statusLabel.snp.top).offset(SCRYFrom(-6))
                make.left.equalTo(statusLabel.snp.left).offset(SCRXFrom(-8))
            } else {
                make.centerX.equalTo(statusLabel)
                make.bottom.equalTo(statusLabel.snp.top).offset(SCRYFrom(-2))
            }
            make.width.height.equalTo(iconSize)
        }

        titleLabel.snp.remakeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(2))
            make.bottom.equalTo(iconImageView.snp.bottom).offset(SCRYFrom(-2))
        }
    }

    private func setupUI() {
        statusLabel.textAlignment = .center
        addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview()
        }

        addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalTo(statusLabel)
            make.bottom.equalTo(statusLabel.snp.top).offset(SCRYFrom(-2))
            make.width.height.equalTo(SCRYFrom(40))
        }

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(2))
            make.centerY.equalTo(iconImageView)
        }
    }
}

class GatewayInformationHeaderView: UIView {

    enum GatewayHeaderStateStyle {
        case gateway
        case sigMesh

        var title: String? {
            switch self {
            case .gateway:
                return nil
            case .sigMesh:
                return "sig_mesh".localizedString
            }
        }

        var onlineImageName: String {
            switch self {
            case .gateway:
                return "gateway_online"
            case .sigMesh:
                return "bluetooth_online"
            }
        }

        var offlineImageName: String {
            switch self {
            case .gateway:
                return "gateway_offline"
            case .sigMesh:
                return "bluetooth_offline"
            }
        }

        func imageName(isOnline: Bool) -> String {
            return isOnline ? onlineImageName : offlineImageName
        }

        var iconSize: CGFloat {
            switch self {
            case .gateway:
                return SCRYFrom(40)
            case .sigMesh:
                return 30
            }
        }

        var stateViewHorizontalOffset: CGFloat {
            switch self {
            case .gateway:
                return 0
            case .sigMesh:
                return SCRXFrom(-12)
            }
        }
    }

    var connectImageView: UIImageView!
    var contentLabel: UILabel!

    private var informationView: UIView!
    private var gatewayStateView: GatewayHeaderStatusItemView!
    private var gatewayStateStyle: GatewayHeaderStateStyle = .gateway
    private var wifiStatusView: GatewayHeaderStatusItemView!
    
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
    
    func setGatewayStateStyle(_ style: GatewayHeaderStateStyle) {
        gatewayStateStyle = style
        updateGatewayStateViewLayout()
    }

    func setWiFiStatusVisible(_ visible: Bool) {
        wifiStatusView.isHidden = !visible
        signalContentView.isHidden = visible
    }

    func updateWiFiStatus(iconName: String, status: String) {
        wifiStatusView.update(
            iconName: iconName,
            title: "wifi_status_title".localizedString,
            status: status,
            iconSize: 30
        )
    }

    func updateData(gateway: Gateway, isProxyReady: Bool) {
        let gatewayModel = gateway.model
        let totalDeviceCount = gatewayModel.associatedSpaces.reduce(0, { (result, space) -> Int in result + space.deviceCount })
        nodeCountLabel.text = "(\(totalDeviceCount))"

        gatewayStateView.update(
            iconName: gatewayStateStyle.imageName(isOnline: isProxyReady),
            title: gatewayStateStyle.title,
            status: isProxyReady ? "online".localizedString : "Offline".localizedString,
            iconSize: gatewayStateStyle.iconSize
        )
        
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
        
        
        gatewayStateView = GatewayHeaderStatusItemView()
        informationView.addSubview(gatewayStateView)
        updateGatewayStateViewLayout()
        
        nodeLabel = UILabel(text: "node".localizedString, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light, fit: false)
        informationView.addSubview(nodeLabel)
        nodeLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(gatewayStateView)
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

        wifiStatusView = GatewayHeaderStatusItemView()
        wifiStatusView.isHidden = true
        informationView.addSubview(wifiStatusView)
        wifiStatusView.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-8))
            make.bottom.equalTo(SCRYFrom(-12))
            make.width.equalTo(SCRXFrom(130))
            make.height.equalTo(SCRYFrom(56))
        }
        
    }

    private func updateGatewayStateViewLayout() {
        guard gatewayStateView != nil else { return }
        gatewayStateView.snp.remakeConstraints { make in
            make.centerX.equalToSuperview().multipliedBy(0.5).offset(gatewayStateStyle.stateViewHorizontalOffset)
            make.bottom.equalTo(SCRYFrom(-12))
            make.width.equalTo(SCRXFrom(130))
            make.height.equalTo(SCRYFrom(56))
        }
    }
    
    
}
