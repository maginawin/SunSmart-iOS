//
//  PJDevicesAddFlowFactory.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

enum PJDevicesAddFlowFactory {

    static func make(context: PJDevicesAddEntryContext) -> UIViewController {
        switch resolveFlowType(from: context) {
        case .fireAlarm:
            return PJDevicesFireAlarmAddContainerController(context: context)
        case .eightKeySwitch:
            return PJDevicesEightKeyAddContainerController(context: context)
        case .gateway:
            return PJDevicesDefaultAddContainerController(context: context)
        }
    }

    static func resolveFlowType(from context: PJDevicesAddEntryContext) -> PJDevicesAddFlowType {
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

private final class PJDevicesDefaultAddContainerController: PJDevicesLegacyContainerController {

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
        vc.bindTarget = context.bindTarget
        vc.addBehavior = context.addBehavior
        configureLegacyAddController(vc)
        embedLegacyController(vc)
    }
}
