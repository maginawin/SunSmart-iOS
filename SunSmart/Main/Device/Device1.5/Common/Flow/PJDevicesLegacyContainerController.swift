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
    }

    func configureLegacyAddController(_ controller: DeviceAddViewController) {
        controller.deviceAddCallback = deviceAddCallback
    }
}
