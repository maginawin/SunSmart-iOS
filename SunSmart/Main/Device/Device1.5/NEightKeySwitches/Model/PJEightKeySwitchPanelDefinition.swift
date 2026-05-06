//
//  PJEightKeySwitchPanelDefinition.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation

struct PJEightKeySwitchPanelDefinition: Equatable {

    enum PanelType: CaseIterable {
        case scene8Key
        case brightness8Key

        var title: String {
            switch self {
            case .scene8Key:
                return "Scene Panel (8 key)"
            case .brightness8Key:
                return "Brightness Panel (8 key)"
            }
        }

        var previewImageName: String {
            switch self {
            case .scene8Key:
                return "Scene Panel (8 key)"
            case .brightness8Key:
                return "Brightness Panel (8 key)"
            }
        }

        var activationInstruction: String {
            switch self {
            case .scene8Key:
                return "neightkeyswitches_activation_instruction_scene".localizedString
            case .brightness8Key:
                return "neightkeyswitches_activation_instruction_brightness".localizedString
            }
        }
    }

    enum ActionKind: Equatable {
        case scene(Int)
        case brightness(Int)
        case dimUp
        case dimDown
        case continuousDimUp
        case continuousDimDown
        case on
        case off
        case auto
    }

    enum ItemStyle {
        case shortPress
        case longPress
    }

    enum Zone: CaseIterable {
        case leftTop
        case leftMiddle
        case leftBottom
        case rightTop
        case rightMiddle
        case rightBottom
    }

    struct Item: Equatable {
        let title: String
        let style: ItemStyle
        let actionKind: ActionKind
    }

    let type: PanelType
    let previewImageName: String
    let topLabels: [String]
    let middleLabels: [String]
    let bottomLabels: [String]
    let zoneItems: [Zone: [Item]]

    static func make(type: PanelType) -> PJEightKeySwitchPanelDefinition {
        switch type {
        case .scene8Key:
            return PJEightKeySwitchPanelDefinition(
                type: .scene8Key,
                previewImageName: PanelType.scene8Key.previewImageName,
                topLabels: ["1", "2"],
                middleLabels: ["3", "4"],
                bottomLabels: ["ON".localizedString, "OFF".localizedString],
                zoneItems: [
                    .leftTop: [
                        .init(title: "neightkeyswitches_scene_1".localizedString, style: .shortPress, actionKind: .scene(1)),
                        .init(title: "neightkeyswitches_scene_3".localizedString, style: .shortPress, actionKind: .scene(3))
                    ],
                    .rightTop: [
                        .init(title: "neightkeyswitches_scene_2".localizedString, style: .shortPress, actionKind: .scene(2)),
                        .init(title: "neightkeyswitches_scene_4".localizedString, style: .shortPress, actionKind: .scene(4))
                    ],
                    .leftMiddle: [
                        .init(title: "neightkeyswitches_dim_up".localizedString, style: .longPress, actionKind: .dimUp),
                        .init(title: "neightkeyswitches_continuous_dim_up".localizedString, style: .longPress, actionKind: .continuousDimUp)
                    ],
                    .rightMiddle: [
                        .init(title: "neightkeyswitches_dim_down".localizedString, style: .longPress, actionKind: .dimDown),
                        .init(title: "neightkeyswitches_continuous_dim_down".localizedString, style: .longPress, actionKind: .continuousDimDown)
                    ],
                    .leftBottom: [
                        .init(title: "ON".localizedString, style: .shortPress, actionKind: .on),
                        .init(title: "AUTO".localizedString, style: .shortPress, actionKind: .auto)
                    ],
                    .rightBottom: [
                        .init(title: "OFF".localizedString, style: .shortPress, actionKind: .off)
                    ]
                ]
            )
        case .brightness8Key:
            return PJEightKeySwitchPanelDefinition(
                type: .brightness8Key,
                previewImageName: PanelType.brightness8Key.previewImageName,
                topLabels: ["100%", "75%"],
                middleLabels: ["50%", "25%"],
                bottomLabels: ["ON".localizedString, "OFF".localizedString],
                zoneItems: [
                    .leftTop: [
                        .init(title: "100%", style: .shortPress, actionKind: .brightness(100)),
                        .init(title: "50%", style: .shortPress, actionKind: .brightness(50))
                    ],
                    .rightTop: [
                        .init(title: "75%", style: .shortPress, actionKind: .brightness(75)),
                        .init(title: "25%", style: .shortPress, actionKind: .brightness(25))
                    ],
                    .leftMiddle: [
                        .init(title: "neightkeyswitches_dim_up".localizedString, style: .longPress, actionKind: .dimUp),
                        .init(title: "neightkeyswitches_continuous_dim_up".localizedString, style: .longPress, actionKind: .continuousDimUp)
                    ],
                    .rightMiddle: [
                        .init(title: "neightkeyswitches_dim_down".localizedString, style: .longPress, actionKind: .dimDown),
                        .init(title: "neightkeyswitches_continuous_dim_down".localizedString, style: .longPress, actionKind: .continuousDimDown)
                    ],
                    .leftBottom: [
                        .init(title: "ON".localizedString, style: .shortPress, actionKind: .on),
                        .init(title: "AUTO".localizedString, style: .shortPress, actionKind: .auto)
                    ],
                    .rightBottom: [
                        .init(title: "OFF".localizedString, style: .shortPress, actionKind: .off)
                    ]
                ]
            )
        }
    }
}
