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
            let controller = EmerFireAlarmInformationVC(device: self?.currentDevice, config: config)
            let navigationController = NavigationViewController(rootViewController: controller)
            self?.present(navigationController, animated: true)
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
        SRAlertView(title: "notification".localizedString, message: "device_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, actionHandler: { [weak self] _ in
            self?.startDeleteCleanupIfNeeded(for: currentDevice)
        })]).show()
    }

    func startDeleteCleanupIfNeeded(for device: DeviceEmerFireData) {
        let planner = EmergencyFireControllerSyncPlanner(data: device, meshUUID: device.meshUUID, subnetworkId: device.meshNetworkId)
        let cleanupItems = planner.makeDeleteCleanupItems()
        guard !cleanupItems.isEmpty else {
            performDeleteDevice(device)
            return
        }
        guard let space else {
            performDeleteDevice(device)
            return
        }
        guard MeshLibManager.manager.isMeshNetworkConnected else {
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
            self?.performDeleteDevice(device)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    func performDeleteDevice(_ device: DeviceEmerFireData) {
        if let node = device.bindNode {
            deleteNodes(nodes: [node]) { [weak self] successNodes, _ in
                guard let self else { return }
                guard successNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) else {
                    return
                }
                self.finishDeleteDevice(device)
            }
        } else {
            finishDeleteDevice(device)
        }
    }

    func finishDeleteDevice(_ device: DeviceEmerFireData) {
        removePublishGroupIfNeeded(for: device)
        DeviceEmerFireStore.shared.delete(device)
        space?.deviceCount = MeshNetworkManager.instance.realNodes.count
        space?.luminairesCount = MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }.count
        space?.save()
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) { [weak self] in
            NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
            self?.closeOrBack()
        }
    }

    func removePublishGroupIfNeeded(for device: DeviceEmerFireData) {
        guard let publishGroupAddress = device.publishGroupAddress,
              let publishGroup = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(publishGroupAddress)) else {
            return
        }
        do {
            try MeshNetworkManager.instance.meshNetwork?.remove(group: publishGroup)
            print("[EFC] removed publish group device=\(device.name), address=\(String(format: "0x%04X", publishGroupAddress))")
        } catch {
            print("[EFC] failed to remove publish group device=\(device.name), address=\(String(format: "0x%04X", publishGroupAddress)), error=\(error)")
        }
    }
}
