//
//  EmerFireAlarmMonitorRouting.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import UIKit
import NordicSigMeshSDK

extension EmerFireAlarmMonitorVC {
    var isUnlinkedVirtualEmergencyFireController: Bool {
        currentDevice?.bindNode == nil
    }

    @objc func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: self.collectionView.contentOffset.y), animated: true)
    }
    
    @objc func moreClick() {
        if isUnlinkedVirtualEmergencyFireController {
            showUnlinkedVirtualEmergencyFireControllerMenu()
            return
        }

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
            guard let self else { return }
            guard let node = self.currentDevice?.bindNode else {
                XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
                return
            }
            let controller = DeviceInformationViewController(
                node: node,
                emptyGroupText: "Not yet linked to a group".localizedString,
                showsSceneSection: false,
                groupTextOverride: self.informationGroupText()
            )
            self.navigationController?.pushViewController(controller, animated: true)
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

    private func showUnlinkedVirtualEmergencyFireControllerMenu() {
        let config = currentConfig ?? currentDevice.map(viewModel.makeConfig(from:))
        var items: [MenuPopView.MenuItem] = []
        if canConfigureDevice {
            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: { [weak self] _ in
                self?.openEditSettings(config: config)
            }))
        }
        if space?.deviceOperates.contains(.delete) ?? false {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
                guard let self, let currentDevice = self.currentDevice else { return }
                self.confirmDeleteEmergencyFireControllerDeviceOrVirtual(
                    currentDevice,
                    space: space,
                    presentsSyncModally: false
                ) { [weak self] in
                    self?.finishDeleteDevice()
                }
            }))
        }

        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
    }

    private func informationGroupText() -> String? {
        let groupNames = viewModel.displayGroups().map { $0.group.name }
        guard !groupNames.isEmpty else { return nil }
        return groupNames.joined(separator: ", ")
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
        navigationController?.pushViewController(controller, animated: true)
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
        let controller = SyncDevicesViewController(type: .emergencyFire(data: currentDevice, items: nil, context: .saveConfiguration(persistsSyncResult: true, changedFromConfiguration: nil)))
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
        confirmDeleteEmergencyFireControllerDeviceOrVirtual(
            currentDevice,
            space: space,
            presentsSyncModally: false
        ) { [weak self] in
            self?.finishDeleteDevice()
        }
    }

    func finishDeleteDevice() {
        if let space {
            space.deviceCount = MeshNetworkManager.instance.realNodes.count
            space.luminairesCount = MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }.count
            space.save()
        }
        NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        closeOrBack()
    }
}

extension DeviceProtocol where Self: UIViewController {

    func confirmDeleteEmergencyFireControllerDeviceOrVirtual(
        _ device: DeviceEmerFireData,
        space: SpaceData?,
        presentsSyncModally: Bool,
        preferredContentSize: CGSize? = nil,
        completion: @escaping () -> Void
    ) {
        guard space?.deviceOperates.contains(.delete) ?? false else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return
        }
        if device.bindNode == nil {
            confirmDeleteUnlinkedVirtualEmergencyFireController(
                device,
                space: space,
                completion: completion
            )
            return
        }
        confirmDeleteEmergencyFireControllerDevice(
            device,
            space: space,
            presentsSyncModally: presentsSyncModally,
            preferredContentSize: preferredContentSize,
            completion: completion
        )
    }

    private func confirmDeleteUnlinkedVirtualEmergencyFireController(
        _ device: DeviceEmerFireData,
        space: SpaceData?,
        completion: @escaping () -> Void
    ) {
        SRAlertView(title: "notification".localizedString, message: "Are you sure to delete the EFC device?".localizedString, actions: [
            .cancelAction,
            SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                self?.deleteUnlinkedVirtualEmergencyFireController(
                    device,
                    space: space,
                    completion: completion
                )
            })
        ]).show()
    }

    private func deleteUnlinkedVirtualEmergencyFireController(
        _ device: DeviceEmerFireData,
        space: SpaceData?,
        completion: @escaping () -> Void
    ) {
        DeviceEmerFireStore.shared.deleteCachedDevice(device)
        if let space {
            space.deviceCount = MeshNetworkManager.instance.realNodes.count
            space.luminairesCount = MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }.count
            space.save()
        }
        NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            completion()
        }
    }

    func confirmDeleteEmergencyFireControllerDevice(
        _ device: DeviceEmerFireData,
        space: SpaceData?,
        presentsSyncModally: Bool,
        preferredContentSize: CGSize? = nil,
        completion: @escaping () -> Void
    ) {
        SRAlertView(title: "notification".localizedString, message: "device_delete_message".localizedString, actions: [
            .cancelAction,
            SRAlertAction(title: "alert_item_delete".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                self?.deleteEmergencyFireControllerDevice(
                    device,
                    space: space,
                    presentsSyncModally: presentsSyncModally,
                    preferredContentSize: preferredContentSize,
                    completion: completion
                )
            })
        ]).show()
    }

    private func deleteEmergencyFireControllerDevice(
        _ device: DeviceEmerFireData,
        space: SpaceData?,
        presentsSyncModally: Bool,
        preferredContentSize: CGSize?,
        completion: @escaping () -> Void
    ) {
        let planner = EmergencyFireControllerSyncPlanner(data: device, meshUUID: device.meshUUID, subnetworkId: device.meshNetworkId)
        let hasAssociateGroups = !device.configuration.activeLightLCGroupAddresses.isEmpty ||
            device.configuration.hasPendingCleanup
        guard hasAssociateGroups else {
            deleteEmergencyFireControllerNodeAndCache(device, space: space, completion: completion)
            return
        }
        let cleanupItems = planner.makeDeleteCleanupItems()
        guard !cleanupItems.isEmpty else {
            deleteEmergencyFireControllerNodeAndCache(device, space: space, completion: completion)
            return
        }
        let needsMeshSync = cleanupItems.flatMap { $0.tasks }.contains { !$0.messageHandles.isEmpty }
        if needsMeshSync, !MeshLibManager.manager.isMeshNetworkConnected {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            device.markDeleteCleanupInterrupted(meshUUID: device.meshUUID, subnetworkId: device.meshNetworkId)
            return
        }
        let controller = SyncDevicesViewController(type: .emergencyFire(data: device, items: cleanupItems, context: .deleteCleanup))
        controller.syncSuccessCallback = { [weak self, weak controller, weak device] _ in
            guard let self, let device else { return }
            let finishDeletion = {
                self.clearEmergencyFireControllerAssociations(device)
                self.deleteEmergencyFireControllerNodeAndCache(
                    device,
                    space: space,
                    completion: completion
                )
            }
            if let controller, self.navigationController?.topViewController === controller {
                self.navigationController?.popViewController(animated: false)
                finishDeletion()
            } else if let presentedViewController = self.presentedViewController {
                presentedViewController.dismiss(animated: true, completion: finishDeletion)
            } else {
                finishDeletion()
            }
        }
        if let preferredContentSize {
            controller.preferredContentSize = preferredContentSize
        }
        if presentsSyncModally || navigationController == nil {
            present(NavigationViewController(rootViewController: controller), animated: true)
        } else {
            navigationController?.pushViewController(controller, animated: true)
        }
    }

    private func clearEmergencyFireControllerAssociations(_ device: DeviceEmerFireData) {
        device.configuration.powerLossSettings.associateGroupAddresses.removeAll()
        device.configuration.fireAlarmSettings.associateGroupAddresses.removeAll()
        device.configuration.powerLossSettings.pendingUnassociateGroupAddresses.removeAll()
        device.configuration.fireAlarmSettings.pendingUnassociateGroupAddresses.removeAll()
        device.isSynced = true
        DeviceEmerFireStore.shared.save(device)
    }

    private func deleteEmergencyFireControllerNodeAndCache(
        _ device: DeviceEmerFireData,
        space: SpaceData?,
        completion: @escaping () -> Void
    ) {
        guard let node = device.bindNode else {
            DeviceEmerFireStore.shared.deleteCachedDevice(device)
            completion()
            return
        }
        deleteNodes(nodes: [node]) { successNodes, _ in
            guard successNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) else {
                return
            }
            DeviceEmerFireStore.shared.deleteCachedDevice(device)
            completion()
        }
    }
}
