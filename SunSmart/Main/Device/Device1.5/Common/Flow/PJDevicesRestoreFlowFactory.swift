//
//  PJDevicesRestoreFlowFactory.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

enum PJDevicesRestoreFlowFactory {

    static func make(context: PJDevicesRestoreEntryContext) -> UIViewController {
        switch resolveFlowType(from: context) {
        case .fireAlarm:
            return PJDevicesFireAlarmRestoreContainerController(context: context)
        case .eightKeySwitch:
            return PJDevicesEightKeyRestoreContainerController(context: context)
        case .gateway:
            return PJDevicesDefaultRestoreContainerController(context: context)
        }
    }

    static func resolveFlowType(from context: PJDevicesRestoreEntryContext) -> PJDevicesRestoreFlowType {
        switch context.source {
        case .fireAlarm:
            return .fireAlarm
        case .eightKeySwitch:
            return .eightKeySwitch
        case .gateway:
            return .gateway
        }
    }
}

private final class PJDevicesDefaultRestoreContainerController: PJDevicesLegacyContainerController {

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
