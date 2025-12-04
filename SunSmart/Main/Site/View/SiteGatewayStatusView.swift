//
//  SiteGatewayStatusView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/11/17.
//

import UIKit
import SnapKit

/// 网关状态显示模式
enum GatewayStatusDisplayMode {
    case overview      // 概览模式：显示统计信息
    case gateway       // 单个网关模式：显示具体网关状态
}

/// 概览统计数据
struct GatewayOverviewStats {
    var internetOnlineCount: Int = 0      // 互联网在线数量
    var internetOfflineCount: Int = 0     // 互联网离线数量
    var noGatewayCount: Int = 0           // 无网关数量
}

/// 单个网关状态数据
enum GatewayStatusType {
    /// 在线
    case online
    /// 离线
    case offline(lastOnlineTime: String)
    /// 重置
    case reset(resetTime: String)
    /// 未激活
    case noActivated
}

protocol SiteGatewayStatusViewDelegate: AnyObject {
    
    /// 网关状态view点击回调
    func gatewayStatusViewClickAction(_ view: SiteGatewayStatusView)
    
    /// 网关操作按钮点击回调
    func gatewayOperationClickAction(_ view: SiteGatewayStatusView)
}

class SiteGatewayStatusView: UIView {
    
    private var contentView: UIView!
    private var stackView: UIStackView!
    private var rightStackView: UIStackView!
    
    weak var delegate: SiteGatewayStatusViewDelegate?
    
    /// 显示模式
    var displayMode: GatewayStatusDisplayMode = .overview {
        didSet {
            updateDisplay()
        }
    }
    
    /// 概览统计数据
    var overviewStats: GatewayOverviewStats = GatewayOverviewStats() {
        didSet {
            if displayMode == .overview {
                updateDisplay()
            }
        }
    }
    
    /// 单个网关状态数据
    var gatewayStatusType: GatewayStatusType = .noActivated {
        didSet {
            if displayMode == .gateway {
                updateDisplay()
            }
        }
    }
    
    /// 单个网关同步状态
    var gatewaySyncState: CloudSynchronizationState? {
        didSet {
            if displayMode == .gateway {
                updateDisplay()
            }
        }
    }
    
    /// 单个网关权限状态
    var gatewayPermissionState: GatewayPermissionState = .normal {
        didSet {
            if displayMode == .gateway {
                updateDisplay()
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func statusViewTapAction() {
        delegate?.gatewayStatusViewClickAction(self)
    }
    
    @objc private func operationBtnAction() {
        guard gatewayPermissionState == .normal else {
            XWHUDManager.showTipHUD("gateway_no_permission_message".localizedString, isLineFeed: true)
            return
        }
        delegate?.gatewayOperationClickAction(self)
    }
    
    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        contentView = UIView()
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalTo(UIEdgeInsets(top: 0, left: SCRXFrom(10), bottom: 0, right: SCRXFrom(10)))
        }
        
        stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .equalSpacing
        stackView.spacing = SCRXFrom(4)
        stackView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(statusViewTapAction)))
        contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.right.centerY.equalToSuperview()
        }
        
        rightStackView = UIStackView()
        rightStackView.axis = .horizontal
        rightStackView.spacing = SCRXFrom(8)
        contentView.addSubview(rightStackView)
        rightStackView.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
        }
    }
    
    private func updateDisplay() {
        // 清除旧的视图
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rightStackView.arrangedSubviews.forEach({ $0.removeFromSuperview() })
        
        switch displayMode {
        case .overview:
            setupOverviewDisplay()
        case .gateway:
            setupGatewayDisplay()
        }
    }
    
    /// 设置概览显示
    private func setupOverviewDisplay() {
        
        stackView.snp.remakeConstraints { make in
            make.left.right.centerY.equalToSuperview()
        }
        
        // Internet Online
        let onlineView = createStatusItemView(
            iconName: "gateway_internet_online",
            title: "\("internet_online".localizedString): \(overviewStats.internetOnlineCount)",
        )
        stackView.addArrangedSubview(onlineView)
        
        
        // Internet Offline
        let offlineView = createStatusItemView(
            iconName: "gateway_internet_offline",
            title: "\("internet_offline".localizedString): \(overviewStats.internetOfflineCount)"
        )
        stackView.addArrangedSubview(offlineView)
        
        
        // No Gateway
        let noGatewayView = createStatusItemView(
            iconName: nil, // 使用圆形图标
            title: "\("no_gateway".localizedString): \(overviewStats.noGatewayCount)",
        )
        stackView.addArrangedSubview(noGatewayView)
        
        
        // 如果没有数据，显示空状态
//        if overviewStats.internetOnlineCount == 0 &&
//           overviewStats.internetOfflineCount == 0 &&
//           overviewStats.noGatewayCount == 0 {
//            let emptyLabel = UILabel(
//                text: "no_data".localizedString,
//                textColor: SubText_Color,
//                fontSize: 12,
//                fontWeight: .light
//            )
//            stackView.addArrangedSubview(emptyLabel)
//        }
    }
    
    /// 设置单个网关显示
    private func setupGatewayDisplay() {
        
        stackView.snp.remakeConstraints { make in
            make.left.centerY.equalToSuperview()
        }
        stackView.spacing = SCRXFrom(4)
        
        var iconImageName: String!
        var title: String!
        var messageAttStr: NSAttributedString?
        
        switch gatewayStatusType {
        case .online:
            iconImageName = "gateway_internet_online"
            title = "internet_online".localizedString
        case .offline(let lastOnlineTime):
            iconImageName = "gateway_internet_offline"
            title = "internet_offline".localizedString
            
            let attStr = NSMutableAttributedString(string: "\("last_online".localizedString): \(lastOnlineTime)")
            attStr.addAttribute(.foregroundColor, value: ImportantText_Color, range: (attStr.string as NSString).range(of: lastOnlineTime))
            messageAttStr = attStr
            
        case .reset(let resetTime):
            iconImageName = "gateway_internet_offline"
            title = "gateway_reset_title".localizedString
            
            let attStr = NSMutableAttributedString(string: "\("reset_time".localizedString): \(resetTime)")
            attStr.addAttribute(.foregroundColor, value: ImportantText_Color, range: (attStr.string as NSString).range(of: resetTime))
            messageAttStr = attStr
            
        case .noActivated:
            iconImageName = "gateway_no_activate"
            title = "gateway_not_activated".localizedString
            
            let attStr = NSMutableAttributedString(string: "\("click_to_setup".localizedString)", attributes: [.underlineStyle: 1])
            messageAttStr = attStr
        }
        
        // Internet状态
        let statusView = createStatusItemView(
            iconName: iconImageName,
            title: title
        )
        stackView.addArrangedSubview(statusView)
        
        
        // 同步状态
        if let syncState = gatewaySyncState {
            var statusImageView: UIImageView?
            switch syncState {
            case .inProgress:
                statusImageView = UIImageView(image: UIImage(named: "sync_loading_small"))
                statusImageView?.layer.addRotationAnimation(duration: 1.2, repeatCount: 9999, animationKey: "loading")
            case .successful:
                statusImageView = UIImageView(image: UIImage(named: "sync_success_small"))
            case .failure:
                statusImageView = UIImageView(image: UIImage(named: "sync_failed_small"))
            default:
                break
            }
            if let imageView = statusImageView {
                stackView.addArrangedSubview(imageView)
            }
        }
        
        // 描述
        if let attStr = messageAttStr {
            let timeLabel = UILabel(
                text: nil,
                textColor: SubText_Color,
                fontSize: 12,
                fontWeight: .light
            )
            timeLabel.attributedText = attStr
            rightStackView.addArrangedSubview(timeLabel)
        }
        
        // 操作按钮
        let operationBtn = UIButton(normalImageName: "device_add_setting", target: self, action: #selector(operationBtnAction))
        if gatewayPermissionState == .noPermission {
            operationBtn.setImage(UIImage(named: "device_add_setting")?.withTintColor(RGB(255, 72, 49)), for: .normal)
        }
        rightStackView.addArrangedSubview(operationBtn)
    }
    
    /// 创建状态项视图
    /// - Parameters:
    ///   - iconName: 图标名称（可选，如果为nil则使用圆形视图）
    ///   - title: 标题文本
    /// - Returns: 状态项视图
    private func createStatusItemView(iconName: String?, title: String) -> UIView {
        let containerView = UIView()

        var iconImageView: UIImageView?
        // 图标
        if let iconName = iconName, let icon = UIImage(named: iconName) {
            let imageView = UIImageView(image: icon)
            containerView.addSubview(imageView)
            imageView.snp.makeConstraints { make in
                make.left.equalToSuperview()
                make.centerY.equalToSuperview()
                make.width.height.equalTo(12)
            }
            iconImageView = imageView
        }
        
        // 标题
        let titleLabel = UILabel(
            text: title,
            textColor: ImportantText_Color,
            fontSize: 12,
            fontWeight: .light
        )
        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            if let imageView =  iconImageView {
                make.left.equalTo(imageView.snp.right).offset(SCRXFrom(4))
            }else {
                make.left.equalToSuperview()
            }
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
            make.top.bottom.equalToSuperview()
        }
        
        return containerView
    }
    
    /// 更新概览统计数据
    /// - Parameter stats: 统计数据
    func updateOverviewStats(_ stats: GatewayOverviewStats) {
        overviewStats = stats
    }
    
    /// 更新单个网关状态
    /// - Parameter status: 网关状态数据
    func updateGatewayStatus(_ type: GatewayStatusType, syncState: CloudSynchronizationState? = nil, permissionState: GatewayPermissionState? = nil) {
        gatewayStatusType = type
        gatewaySyncState = syncState
        if permissionState != nil {
            gatewayPermissionState = permissionState!
        }
    }
    
    /// 设置显示模式
    /// - Parameter mode: 显示模式
    func setDisplayMode(_ mode: GatewayStatusDisplayMode) {
        displayMode = mode
    }
}
