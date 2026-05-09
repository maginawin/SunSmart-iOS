//
//  PJDevicesLegacyContainerController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import NordicSigMeshSDK

class PJDevicesLegacyContainerController: UIViewController {

    var deviceAddCallback: (([Node]) -> Void)?

    func embedLegacyController(_ child: UIViewController) {
        addChild(child)
        view.addSubview(child.view)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        child.didMove(toParent: self)
        syncNavigationItem(from: child)
    }

    func configureLegacyAddController(_ controller: DeviceAddViewController) {
        controller.deviceAddCallback = deviceAddCallback
    }

    private func syncNavigationItem(from child: UIViewController) {
        navigationItem.leftBarButtonItem = child.navigationItem.leftBarButtonItem
        navigationItem.rightBarButtonItem = child.navigationItem.rightBarButtonItem
        navigationItem.leftBarButtonItems = child.navigationItem.leftBarButtonItems
        navigationItem.rightBarButtonItems = child.navigationItem.rightBarButtonItems
    }
}
