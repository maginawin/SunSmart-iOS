//
//  SiteGatewayHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/11/22.
//

import UIKit

class SiteGatewayHeaderView: UICollectionReusableView {
        
    var gatewayListView: GatewayListView!
    var gatewayStatusView: SiteGatewayStatusView!
    let timeZoneReviewSyncView = SiteTimeZoneReviewSyncView()
    var onReviewSync: (() -> Void)?

    var showGatewayListView: Bool = true {
        didSet {
            gatewayListView.isHidden = !showGatewayListView
            updateLayout()
        }
    }

    var showGatewayStatusView: Bool = true {
        didSet {
            gatewayStatusView.isHidden = !showGatewayStatusView
            updateLayout()
        }
    }

    var timeZoneReviewState: SiteTimeZoneReviewState = .hidden {
        didSet {
            switch timeZoneReviewState {
            case .hidden:
                timeZoneReviewSyncView.isHidden = true
            case let .review(serverTimezone, gatewayCount):
                timeZoneReviewSyncView.isHidden = false
                timeZoneReviewSyncView.update(
                    serverTimezone: serverTimezone,
                    gatewayCount: gatewayCount
                )
            }
            updateLayout()
        }
    }
    
//    var gateways: [GatewayModel] = [] {
//        didSet {
//            updateData()
//        }
//    }
    
//    var selectIndex: Int = 0 {
//        didSet {
//            guard gateways.count > 0 else {
//                return
//            }
//            updateData()
//        }
//    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
//    private func updateData() {
//        
//        var items = gateways.map({ GatewayListItem(id: $0.mac, title: $0.name, status: .online, gatewayModel: $0)})
//        if items.count > 0 {
//            items.insert(.init(id: "", title: "overview".localizedString), at: 0)
//        }
//        gatewayListView.updateItems(items)
//     
//        guard gateways.count > 0 else {
//            gatewayStatusView.isHidden = true
//            return
//        }
//        gatewayStatusView.isHidden = false
//        if selectIndex == 0 {
//            gatewayStatusView.displayMode = .overview
//            gatewayStatusView.updateOverviewStats(.init(internetOnlineCount: <#T##Int#>, internetOfflineCount: <#T##Int#>, noGatewayCount: <#T##Int#>))
//            
//        }else {
//            gatewayStatusView.displayMode = .gateway
//        }
//        
//        
//    }
    
    private func setupUI() {
        
        gatewayListView = GatewayListView()
        addSubview(gatewayListView)
        
        gatewayStatusView = SiteGatewayStatusView()
//        gatewayStatusView.updateOverviewStats(.init(internetOnlineCount: 3, internetOfflineCount: 2, noGatewayCount: 3))
//        gatewayStatusView.setDisplayMode(.gateway)
//        gatewayStatusView.updateGatewayStatus(.init(isInternetOnline: false, lastOnlineTime: "2025-11-18 15:30"))
        addSubview(gatewayStatusView)

        timeZoneReviewSyncView.onReviewSync = { [weak self] in
            self?.onReviewSync?()
        }
        timeZoneReviewSyncView.isHidden = true
        addSubview(timeZoneReviewSyncView)

        updateLayout()
    }

    private func updateLayout() {
        gatewayListView.snp.remakeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(showGatewayListView ? SCRYFrom(40) : 0)
        }

        gatewayStatusView.snp.remakeConstraints { make in
            make.left.right.equalToSuperview()
            if showGatewayListView {
                make.top.equalTo(gatewayListView.snp.bottom).offset(SCRYFrom(8))
            } else {
                make.top.equalToSuperview()
            }
            make.height.equalTo(showGatewayStatusView ? SCRYFrom(40) : 0)
        }

        timeZoneReviewSyncView.snp.remakeConstraints { make in
            make.left.right.equalToSuperview()
            if showGatewayStatusView {
                make.top.equalTo(gatewayStatusView.snp.bottom).offset(SCRYFrom(8))
            } else if showGatewayListView {
                make.top.equalTo(gatewayListView.snp.bottom).offset(SCRYFrom(8))
            } else {
                make.top.equalToSuperview()
            }
            let isVisible: Bool
            if case .review = timeZoneReviewState {
                isVisible = true
            } else {
                isVisible = false
            }
            make.height.equalTo(isVisible ? SCRYFrom(56) : 0)
        }
    }
    
}

//extension SiteGatewayHeaderView: GatewayListViewDelegate {
//    
//    /// 点击网关项回调
//    func gatewayListView(_ view: GatewayListView, didSelectItem item: GatewayListItem, at index: Int) {
//        
//    }
//    
//    /// 点击菜单按钮回调
//    func gatewayListViewDidClickMenu(_ view: GatewayListView) {
//        
//    }
//    
//    /// 点击添加网关
//    func gatewayListViewDidClickAdd(_ view: GatewayListView) {
////        let vc = SiteDeviceAddViewController(site: site)
////        navigationController?.pushViewController(vc, animated: true)
//    }
//    
//}
