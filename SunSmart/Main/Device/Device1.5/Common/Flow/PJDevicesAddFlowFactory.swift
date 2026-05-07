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
            return PJDevicesGatewayAddContainerController(context: context)
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
