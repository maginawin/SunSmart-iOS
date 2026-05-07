//
//  PJDevicesLegacyContainerController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

class PJDevicesLegacyContainerController: UIViewController {

    func embedLegacyController(_ child: UIViewController) {
        addChild(child)
        view.addSubview(child.view)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        child.didMove(toParent: self)
    }
}
