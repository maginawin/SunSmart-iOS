//
//  PJNGatewayWiFiDFUHistoryViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation

final class PJNGatewayWiFiDFUHistoryViewModel {

    private(set) var items: [PJNGatewayWiFiDFUHistoryItem] = [
        .init(
            version: "1.2.0",
            releaseDateText: "\("release_date".localizedString): Jun 22,2024",
            releaseNotes: [
                "ngateway_wifi_dfu_note_1".localizedString,
                "ngateway_wifi_dfu_note_2".localizedString,
                "ngateway_wifi_dfu_note_3".localizedString,
                "ngateway_wifi_dfu_note_4".localizedString
            ],
            isExpanded: false
        ),
        .init(
            version: "1.1.0",
            releaseDateText: "\("release_date".localizedString): Jun 11,2024",
            releaseNotes: [
                "ngateway_wifi_dfu_note_1".localizedString,
                "ngateway_wifi_dfu_note_2".localizedString,
                "ngateway_wifi_dfu_note_3".localizedString
            ],
            isExpanded: true
        )
    ]

    let title = "firmware_version_history".localizedString

    func toggleExpand(at index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        items[index] = .init(
            version: item.version,
            releaseDateText: item.releaseDateText,
            releaseNotes: item.releaseNotes,
            isExpanded: !item.isExpanded
        )
    }
}
