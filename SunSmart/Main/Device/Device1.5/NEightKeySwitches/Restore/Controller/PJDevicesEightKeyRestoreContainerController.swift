//
//  PJDevicesEightKeyRestoreContainerController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJDevicesEightKeyRestoreContainerController: PJDevicesLegacyContainerController {

    private let context: PJDevicesRestoreEntryContext

    init(context: PJDevicesRestoreEntryContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = context.title
        let vc = DeviceRestoreViewController(site: context.site, space: context.space, restoreMode: context.restoreMode)
        vc.title = context.title
        embedLegacyController(vc)
    }
}
