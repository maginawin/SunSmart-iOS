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
struct GatewayStatusData {
    var isInternetOnline: Bool = false    // 是否互联网在线
    var lastOnlineTime: String?           // 最后在线时间
}

class SiteGatewayStatusView: UIView {
    
    private var contentView: UIView!
    private var stackView: UIStackView!
    
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
    var gatewayStatus: GatewayStatusData = GatewayStatusData() {
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
        contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.right.centerY.equalToSuperview()
        }
    }
    
    private func updateDisplay() {
        // 清除旧的视图
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        switch displayMode {
        case .overview:
            setupOverviewDisplay()
        case .gateway:
            setupGatewayDisplay()
        }
    }
    
    /// 设置概览显示
    private func setupOverviewDisplay() {
        // Internet Online
        if overviewStats.internetOnlineCount > 0 {
            let onlineView = createStatusItemView(
                iconName: "gateway_internet_online",
                title: "\("internet_online".localizedString): \(overviewStats.internetOnlineCount)",
            )
            stackView.addArrangedSubview(onlineView)
        }
        
        // Internet Offline
        if overviewStats.internetOfflineCount > 0 {
            let offlineView = createStatusItemView(
                iconName: "gateway_internet_offline",
                title: "\("internet_offline".localizedString): \(overviewStats.internetOfflineCount)"
            )
            stackView.addArrangedSubview(offlineView)
        }
        
        // No Gateway
        if overviewStats.noGatewayCount > 0 {
            let noGatewayView = createStatusItemView(
                iconName: nil, // 使用圆形图标
                title: "\("no_gateway".localizedString): \(overviewStats.noGatewayCount)",
            )
            stackView.addArrangedSubview(noGatewayView)
        }
        
        // 如果没有数据，显示空状态
        if overviewStats.internetOnlineCount == 0 &&
           overviewStats.internetOfflineCount == 0 &&
           overviewStats.noGatewayCount == 0 {
            let emptyLabel = UILabel(
                text: "no_data".localizedString,
                textColor: SubText_Color,
                fontSize: 12,
                fontWeight: .light
            )
            stackView.addArrangedSubview(emptyLabel)
        }
    }
    
    /// 设置单个网关显示
    private func setupGatewayDisplay() {
        // Internet状态
        let statusView = createStatusItemView(
            iconName: gatewayStatus.isInternetOnline ? "gateway_internet_online" : "gateway_internet_offline", // 使用圆形图标
            title: gatewayStatus.isInternetOnline ? "internet_online".localizedString : "internet_offline".localizedString
        )
        stackView.addArrangedSubview(statusView)
        
        // 最后在线时间
        if let lastOnlineTime = gatewayStatus.lastOnlineTime {
            let timeLabel = UILabel(
                text: "\("last_online".localizedString): \(lastOnlineTime)",
                textColor: SubText_Color,
                fontSize: 12,
                fontWeight: .light
            )
            let attStr = NSMutableAttributedString(string: "\("last_online".localizedString): \(lastOnlineTime)")
            attStr.addAttribute(.foregroundColor, value: ImportantText_Color, range: (attStr.string as NSString).range(of: lastOnlineTime))
            timeLabel.attributedText = attStr
            stackView.addArrangedSubview(timeLabel)
        }
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
    func updateGatewayStatus(_ status: GatewayStatusData) {
        gatewayStatus = status
    }
    
    /// 设置显示模式
    /// - Parameter mode: 显示模式
    func setDisplayMode(_ mode: GatewayStatusDisplayMode) {
        displayMode = mode
    }
}
