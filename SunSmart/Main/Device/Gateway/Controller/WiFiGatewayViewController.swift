//
//  WiFiGatewayViewController.swift
//  SunSmart
//

import UIKit
import NordicSigMeshSDK

final class WiFiGatewayViewController: GatewayViewController {

    override func configureNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(closeAction)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(moreClick)
        )
    }

    override func showConfiguredBottomActions() {
        bottomView.showSaveOnlyUI()
    }

    override func showRepairBottomActions() {
        bottomView.showSaveOnlyUI()
    }

    @objc private func moreClick() {
        var items: [MenuPopView.MenuItem] = []
        items.append(.init(icon: UIImage(named: "menu_wifi_dfu"), title: "WiFi DFU", tapItemBack: { _ in
        }))
        if site.deviceOperates.contains(.edit) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
                self?.deleteBtnAction()
            }))
        }
        items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { [weak self] _ in
            guard let self else { return }
            let controller = DeviceInformationViewController(node: self.node, showsGroupSection: false, showsSceneSection: false)
            self.navigationController?.pushViewController(controller, animated: true)
        }))
        items.append(.init(icon: UIImage(named: "menu_identify"), title: "Identify", tapItemBack: { [weak self] _ in
            guard let self else { return }
            MeshAPI.identify(address: self.node.primaryUnicastAddress)
        }))
        items.append(.init(icon: UIImage(named: "menu_diagnosis"), title: "Diagnosis", tapItemBack: { _ in
        }))

        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(120))
    }
}
