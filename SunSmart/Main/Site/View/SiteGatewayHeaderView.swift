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
    
    var showGatewayListView: Bool = true {
        didSet {
            if showGatewayListView {
                gatewayListView.isHidden = false
                gatewayStatusView.snp.remakeConstraints { make in
                    make.left.right.equalTo(gatewayListView)
                    make.top.equalTo(gatewayListView.snp.bottom).offset(SCRYFrom(8))
                    make.height.equalTo(SCRYFrom(40))
                }
            }else {
                gatewayListView.isHidden = true
                gatewayStatusView.snp.remakeConstraints { make in
                    make.top.left.right.equalToSuperview()
                    make.height.equalTo(SCRYFrom(40))
                }
            }
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
        gatewayListView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(40))
        }
        
        gatewayStatusView = SiteGatewayStatusView()
//        gatewayStatusView.updateOverviewStats(.init(internetOnlineCount: 3, internetOfflineCount: 2, noGatewayCount: 3))
//        gatewayStatusView.setDisplayMode(.gateway)
//        gatewayStatusView.updateGatewayStatus(.init(isInternetOnline: false, lastOnlineTime: "2025-11-18 15:30"))
        addSubview(gatewayStatusView)
        gatewayStatusView.snp.makeConstraints { make in
            make.left.right.equalTo(gatewayListView)
            make.top.equalTo(gatewayListView.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
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
