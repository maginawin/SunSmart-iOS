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
            return PJDevicesGatewayRestoreContainerController(context: context)
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
