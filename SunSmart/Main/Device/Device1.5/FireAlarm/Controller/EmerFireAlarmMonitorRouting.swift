//
//  EmerFireAlarmMonitorRouting.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import UIKit
import NordicSigMeshSDK

extension EmerFireAlarmMonitorVC {
    @objc func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: self.collectionView.contentOffset.y), animated: true)
    }
    
    @objc func moreClick() {
        let config = currentConfig ?? currentDevice.map(viewModel.makeConfig(from:))
        var items: [MenuPopView.MenuItem] = []
        if canConfigureDevice {
            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] _ in
                self?.openEditSettings(config: config)
            }))
        }
        if space?.deviceOperates.contains(.delete) ?? false {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] _ in
                self?.deleteDevice()
            }))
        }

        items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: {[weak self] _ in
            guard let node = self?.currentDevice?.bindNode else {
                XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
                return
            }
            let controller = DeviceInformationViewController(
                node: node,
                emptyGroupText: "Not yet linked to a group".localizedString,
                showsSceneSection: false
            )
            self?.navigationController?.pushViewController(controller, animated: true)
        }))

        if !isAllEmergencyFunctionsDisabled, canConfigureDevice {
            items.append(.init(icon: UIImage(named: "menu_refresh"), title: "refresh".localizedString, tapItemBack: {[weak self] _ in
                self?.refresh()
            }))
        }
        
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10

        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
       
    }

    func openEditSettings(config: LinkedEmerFireConfig? = nil) {
        guard space?.deviceOperates.contains(.edit) ?? false else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return
        }
        guard let config = config ?? currentConfig ?? currentDevice.map(viewModel.makeConfig(from:)) else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        let controller = LinkedEmerFireEditVC(config: config, space: space)
        controller.editable = true
        let navigationController = NavigationViewController(rootViewController: controller)
        present(navigationController, animated: true)
    }


    func refresh() {
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 1.0)
        reloadCurrentDevice()
        if currentConfig == nil, let currentDevice {
            currentConfig = viewModel.makeConfig(from: currentDevice)
        }
        applySavedConfig()
        if let node = currentDevice?.bindNode {
            MeshAPI.getNodeState(address: node.primaryUnicastAddress)
        }
        refreshRealState()
    }


    func repairBtnClick() {
        guard let space, let currentDevice else {
            return
        }
        let controller = EmerFireAlarmControllerSyncVC(space: space, data: currentDevice)
        navigationController?.pushViewController(controller, animated: true)
    }

    func closeOrBack() {
        if presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1 {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    func deleteDevice() {
        guard let currentDevice else { return }
        SRAlertView(title: "notification".localizedString, message: "emergency_fire_controller_delete_config_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, actionHandler: { [weak self] _ in
            self?.startDeleteCleanupIfNeeded(for: currentDevice)
        })]).show()
    }

    func startDeleteCleanupIfNeeded(for device: DeviceEmerFireData) {
        let planner = EmergencyFireControllerSyncPlanner(data: device, meshUUID: device.meshUUID, subnetworkId: device.meshNetworkId)
        let cleanupItems = planner.makeDeleteCleanupItems()
        guard let space else {
            finishDeleteConfiguration(device)
            return
        }
        let needsMeshSync = cleanupItems.flatMap { $0.tasks }.contains { !$0.messageHandles.isEmpty }
        guard !needsMeshSync || MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }

        let controller = EmerFireAlarmControllerSyncVC(
            space: space,
            data: device,
            items: cleanupItems,
            persistsSyncResult: false
        ) { [weak self, weak device] in
            guard let device else { return }
            self?.finishDeleteConfiguration(device)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    func finishDeleteConfiguration(_ device: DeviceEmerFireData) {
        DeviceEmerFireStore.shared.clearMonitoringConfiguration(for: device)
        currentDevice = device
        currentConfig = device.toConfig()
        NotificationCenter.default.post(name: .linkedEmerFireConfigDidChange, object: currentConfig)
        applySavedConfig()
        refreshRealState()
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) { [weak self] in
            NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            self?.closeOrBack()
        }
    }
}
