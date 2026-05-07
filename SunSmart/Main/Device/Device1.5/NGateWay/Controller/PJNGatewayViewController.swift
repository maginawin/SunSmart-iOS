//
//  PJNGatewayViewController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import NordicSigMeshSDK

final class PJNGatewayViewController: UIViewController, DeviceProtocol {

    private let pageViewModel: PJNGatewayPageViewModel
    private let detailView = PJNGatewayDetailView()
    private let switch2_4GHzAlertView = PJNGatewaySwitch2_4GHzAlertView()

    init(site: SiteData, gateway: Gateway) {
        self.pageViewModel = PJNGatewayPageViewModel(site: site, gateway: gateway)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = pageViewModel.title
        view.backgroundColor = UIColor(hex: 0xF5F7FB)
        setupUI()
        setupNavigation()
        bindActions()
        render()
        refreshCurrentSSID()
        
    }

    private func setupNavigation() {
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(moreClick)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(backAction)
        )
        
    }
    
    @objc private func backAction() {
        if let navigationController, navigationController.viewControllers.first != self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
    
    private func setupUI() {
        view.addSubview(detailView)
        detailView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func bindActions() {
        detailView.nameChanged = { [weak self] in
            self?.pageViewModel.updateName($0)
            self?.title = $0
        }
        detailView.activateChanged = { [weak self] in
            self?.pageViewModel.updateActivate($0)
        }
        detailView.ssidChangeTapped = { [weak self] in
            self?.handleSSIDChangeAction()
        }
        detailView.refreshTapped = { [weak self] in
            guard let self else { return }
            self.pageViewModel.gatewayModel.isSSIDRefreshing = true
            self.render()
            self.pageViewModel.refreshNetworkDetails { [weak self] _ in
                self?.pageViewModel.gatewayModel.isSSIDRefreshing = false
                self?.render()
            }
        }
        detailView.advancedTapped = { [weak self] in
            self?.pageViewModel.toggleAdvancedSettings()
            self?.render()
        }
        detailView.ipModeChanged = { [weak self] in
            self?.pageViewModel.updateIPMode($0)
            self?.render()
        }
        detailView.ipAddressChanged = { [weak self] in self?.pageViewModel.updateIPAddress($0) }
        detailView.subnetMaskChanged = { [weak self] in self?.pageViewModel.updateSubnetMask($0) }
        detailView.gatewayAddressChanged = { [weak self] in self?.pageViewModel.updateGatewayAddress($0) }
        detailView.primaryDNSChanged = { [weak self] in self?.pageViewModel.updatePrimaryDNS($0) }
        detailView.secondaryDNSChanged = { [weak self] in self?.pageViewModel.updateSecondaryDNS($0) }
        detailView.connectTapped = { [weak self] in
            self?.pageViewModel.handleConnectAction {
                self?.render()
            }
        }
        detailView.addSpaceTapped = { [weak self] in
            self?.showAssociatedSpaces()
        }
        detailView.deleteSpaceTapped = { [weak self] index in
            self?.handleDeleteAssociatedSpace(at: index)
        }
        detailView.authorizeTapped = { [weak self] in
            self?.authorizeRequest()
        }
        detailView.copyInformationTapped = { [weak self] in
            self?.copyGatewayInformation()
        }
        detailView.saveTapped = { [weak self] in
            self?.pageViewModel.saveChanges()
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
        }
        switch2_4GHzAlertView.settingsTapped = { [weak self] in
            self?.switch2_4GHzAlertView.dismiss()
            self?.openWiFiSettings()
        }
    }

    private func render() {
        detailView.render(pageViewModel.detailViewModel)
    }

    private func refreshCurrentSSID() {
        pageViewModel.refreshCurrentSSID { [weak self] hasConnectedSSID in
            guard let self else { return }
            self.render()
        }
    }

    private func handleSSIDChangeAction() {
        switch2_4GHzAlertView.present(in: view)
    }

    private func openWiFiSettings() {
        if let wifiSettingsURL = URL(string: "App-Prefs:root=WIFI"), UIApplication.shared.canOpenURL(wifiSettingsURL) {
            UIApplication.shared.open(wifiSettingsURL)
            return
        }
        if let appSettingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(appSettingsURL)
        }
    }

    private func copyGatewayInformation() {
        let gatewayModel = pageViewModel.gatewayModel
        let node = pageViewModel.node
        var copyContent = ""
        copyContent.append("\("name".localizedString): \(gatewayModel.name)")
        copyContent.append("\n\("MAC".localizedString): \(node.macAddressResult ?? gatewayModel.mac)")
        copyContent.append("\n\("address".localizedString): \(node.primaryUnicastAddress)")

        if let modelName = node.modelName {
            copyContent.append("\n\("model".localizedString): \(modelName)")
        }
        if let categoryName = node.categoryName {
            copyContent.append("\n\("device_type".localizedString): \(categoryName)")
        }
        if let version = node.firmwareVersion {
            copyContent.append("\n\("firmware".localizedString): \(version)")
        }

        copyContent.append("\n\("activate".localizedString): \(gatewayModel.activate ? "Yes".localizedString : "No".localizedString)")

        if gatewayModel.associatedSpaces.count > 0 {
            let spacesName = gatewayModel.associatedSpaces.map(\.spaceName).joined(separator: ",")
            copyContent.append("\n\("associated_spaces".localizedString): \(spacesName)")
        } else {
            copyContent.append("\n\("associated_spaces".localizedString): \("no_associated_spaces".localizedString)")
        }

        if let apn = gatewayModel.apn {
            copyContent.append("\n\("apn".localizedString): \(apn)")
        } else {
            copyContent.append("\n\("apn".localizedString): \("not_set".localizedString)")
        }

        if let mqttServerInfo = gatewayModel.mqttServerInfo {
            let server = mqttServerInfo.serverAddress.replacingOccurrences(of: "tcp://", with: "")
            let parts = server.components(separatedBy: ":")
            copyContent.append("\n\("server_address".localizedString): \(parts.first ?? "N/A")")
            copyContent.append("\n\("port".localizedString): \(parts.count > 1 ? parts[1] : "N/A")")
            copyContent.append("\n\("client_id".localizedString): \(mqttServerInfo.clientId)")
        } else {
            copyContent.append("\n\("server_address".localizedString): N/A")
            copyContent.append("\n\("port".localizedString): N/A")
            copyContent.append("\n\("client_id".localizedString): N/A")
        }

        UIPasteboard.general.string = copyContent
        XWHUDManager.showTipHUD("copy_success".localizedString, isLineFeed: false)
    }

    private func authorizeRequest() {
        guard NetworkRequest.shared.networkable else {
            XWHUDManager.showTipHUD("phone_no_network".localizedString, isLineFeed: true)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
            do {
                let didAuthorize = try await self.pageViewModel.authorizeServerIfNeeded()
                if didAuthorize {
                    NotificationCenter.default.post(
                        name: .init(siteGatewayDataChangedNotificaitonName),
                        object: self.pageViewModel.gateway
                    )
                }
            } catch let error as NetworkApiError {
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
                return
            } catch {
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD("server_failure".localizedString)
                return
            }

            XWHUDManager.hide()
            self.render()
        }
    }

    private func showAssociatedSpaces() {
        guard pageViewModel.gatewayModel.mqttServerInfo != nil else {
            XWHUDManager.showTipHUD("associate_space_unauthorized_message".localizedString, isLineFeed: true, afterDelay: 1.5)
            return
        }

        let spaces = pageViewModel.availableAssociatedSpaces()
        guard !spaces.isEmpty else {
            return
        }

        let controller = GatewayAssociatedSpacesController(gateway: pageViewModel.gateway.model, spaces: spaces)
        controller.associatedSpacesSelectCallback = { [weak self] spaces in
            guard let self else { return }
            self.pageViewModel.applyAssociatedSpaces(spaces)
            self.render()
            NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.pageViewModel.gateway)
            NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func handleDeleteAssociatedSpace(at index: Int) {
        guard let space = pageViewModel.associatedSpace(at: index) else {
            return
        }
        unbindAssociatedSpace(space)
    }

    private func unbindAssociatedSpace(_ space: GatewaySpaceData) {
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        pageViewModel.unbindAssociatedSpace(space) { [weak self] result in
            XWHUDManager.hide()
            guard let self else {
                return
            }
            switch result {
            case .success:
                self.render()
                NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.pageViewModel.gateway)
                NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }

    @objc private func moreClick() {
        var items: [MenuPopView.MenuItem] = []
        items.append(.init(icon: UIImage(named: "WiFiDFU"), title: "WiFi DFU", tapItemBack: { [weak self] _ in
            self?.showWiFiDFU()
        }))
        if pageViewModel.site.deviceOperates.contains(.delete) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
                self?.deleteGateway()
            }))
        }
        items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { [weak self] _ in
            self?.showInformation()
        }))
        items.append(.init(icon: UIImage(named: "Identify_gateway"), title: "Identify", tapItemBack: { [weak self] _ in
            guard let self else { return }
            MeshAPI.identify(address: self.pageViewModel.node.primaryUnicastAddress)
        }))
        items.append(.init(icon: UIImage(named: "Diagnosis"), title: "Diagnosis", tapItemBack: { _ in
            XWHUDManager.showTipHUD("Diagnosis", isLineFeed: false)
        }))

        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(120))
    }

    private func showInformation() {
        navigationController?.pushViewController(DeviceInformationViewController(node: pageViewModel.node), animated: true)
    }

    private func showWiFiDFU() {
        let controller = PJNGatewayWiFiDFUViewController(node: pageViewModel.node)
        if isIPad {
            controller.preferredContentSize = iPadPreferredContentSize
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func deleteGateway() {
        guard pageViewModel.site.deviceOperates.contains(.edit) else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }

        SRAlertView(
            title: "notification".localizedString,
            message: "gateway_delete_message".localizedString,
            actions: [
                .cancelAction,
                SRAlertAction(title: "alert_item_continue".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                    self?.performDeleteGateway()
                })
            ]
        ).show()
    }

    private func performDeleteGateway() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
                let deletedOnServer = try await pageViewModel.deleteGatewayRegistrationIfNeeded()
                XWHUDManager.hide()
                resetNode(authorize: deletedOnServer)
            } catch let error as NetworkApiError {
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            } catch let error as PJNGatewayPageViewModel.DeleteGatewayError {
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            } catch {
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD("server_failure".localizedString)
            }
        }
    }

    private func resetNode(authorize: Bool = false) {
        let message = authorize ? "gateway_force_delete_message".localizedString : "gateway_no_authorize_force_delete_message".localizedString

        deleteNodes(nodes: [pageViewModel.node], forceDeleteMessage: message, forceDeleteNote: "gateway_force_delete_note".localizedString) { [weak self] successNodes, _ in
            guard let self else { return }
            if successNodes.contains(where: { $0.primaryUnicastAddress == self.pageViewModel.node.primaryUnicastAddress }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.pageViewModel.gateway.model.delete()
                    NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
                    NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
                    self.closeAfterDelete()
                }
            } else if authorize {
                NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.pageViewModel.gateway)
                self.render()
            }
        }
    }

    private func closeAfterDelete() {
        if presentingViewController != nil && navigationController?.viewControllers.count == 1 {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
        MeshLibManager.manager.close()
    }
}
