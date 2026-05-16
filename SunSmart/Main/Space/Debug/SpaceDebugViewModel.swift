//
//  SpaceDebugViewModel.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import Foundation
import NordicSigMeshSDK

final class SpaceDebugViewModel {
    var onSnapshotChanged: (() -> Void)?

    private var itemsByAddress: [Address: SpaceDebugNodeItem]
    private var scanState: SpaceDebugScanState = .idle
    private var pendingRefresh: DispatchWorkItem?

    init(nodes: [Node]) {
        self.itemsByAddress = SpaceDebugViewModel.makeItems(nodes: nodes)
    }

    var totalCount: Int {
        itemsByAddress.count
    }

    var foundCount: Int {
        itemsByAddress.values.filter(\.isFound).count
    }

    var currentScanState: SpaceDebugScanState {
        scanState
    }

    func replaceNodes(_ nodes: [Node]) {
        itemsByAddress = SpaceDebugViewModel.makeItems(nodes: nodes)
        onSnapshotChanged?()
    }

    func setScanState(_ state: SpaceDebugScanState) {
        scanState = state
        onSnapshotChanged?()
    }

    func resetFoundState() {
        itemsByAddress = Dictionary(
            uniqueKeysWithValues: itemsByAddress.values.map { item in
                var next = item
                next.peripheral = nil
                next.rssi = nil
                next.lastSeen = nil
                next.isConnecting = false
                return (next.address, next)
            }
        )
        onSnapshotChanged?()
    }

    func updateFoundNode(_ data: MeshNodePeripheralData) {
        let address = data.node.primaryUnicastAddress
        guard var item = itemsByAddress[address] else {
            return
        }
        item.peripheral = data.peripheral
        item.rssi = data.rssi.intValue
        item.lastSeen = Date()
        itemsByAddress[address] = item
        scheduleSnapshotRefresh()
    }

    func setConnecting(address: Address?) {
        itemsByAddress = Dictionary(
            uniqueKeysWithValues: itemsByAddress.values.map { item in
                var next = item
                next.isConnecting = address == item.address
                return (next.address, next)
            }
        )
        if let address = address {
            scanState = .connecting(address)
        } else if case .connecting = scanState {
            scanState = .stopped
        }
        onSnapshotChanged?()
    }

    func item(at indexPath: IndexPath) -> SpaceDebugNodeItem {
        sections()[indexPath.section].items[indexPath.row]
    }

    func sections() -> [SpaceDebugSection] {
        SpaceDebugDeviceCategory.allCases.map { category in
            let items = itemsByAddress.values
                .filter { $0.category == category }
                .sorted { lhs, rhs in
                    lhs.displayOrder < rhs.displayOrder
                }
            return SpaceDebugSection(category: category, items: items)
        }.filter { !$0.items.isEmpty }
    }

    private func scheduleSnapshotRefresh() {
        guard pendingRefresh == nil else {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingRefresh = nil
            self?.onSnapshotChanged?()
        }
        pendingRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private static func makeItems(nodes: [Node]) -> [Address: SpaceDebugNodeItem] {
        Dictionary(
            uniqueKeysWithValues: nodes.enumerated().map { index, node in
                (node.primaryUnicastAddress, SpaceDebugNodeItem(node: node, displayOrder: index))
            }
        )
    }
}
