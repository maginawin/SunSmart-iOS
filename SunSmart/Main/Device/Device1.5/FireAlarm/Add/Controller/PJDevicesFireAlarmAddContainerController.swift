//
//  PJDevicesFireAlarmAddContainerController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJDevicesFireAlarmAddContainerController: PJDevicesLegacyContainerController {

    private let context: PJDevicesAddEntryContext

    init(context: PJDevicesAddEntryContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = context.title
        let vc = DeviceAddViewController(space: context.space)
        vc.title = context.title
        vc.appointGroup = context.appointGroup
        vc.addBehavior = context.addBehavior
        configureLegacyAddController(vc)
        embedLegacyController(vc)
    }
}
