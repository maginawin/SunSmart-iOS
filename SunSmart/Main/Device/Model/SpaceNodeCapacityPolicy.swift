//
//  SpaceNodeCapacityPolicy.swift
//  SunSmart
//
//  Created by One on 2026/8/5.
//

enum SpaceNodeCapacityPolicy {
    static let maxNodeCount = 500

    static func remainingNodeCount(
        existingNodeCount: Int,
        inFlightNodeCount: Int
    ) -> Int {
        let occupiedNodeCount = max(existingNodeCount, 0) + max(inFlightNodeCount, 0)
        return max(maxNodeCount - occupiedNodeCount, 0)
    }

    static func acceptedNodeCount(
        existingNodeCount: Int,
        inFlightNodeCount: Int,
        requestedNodeCount: Int
    ) -> Int {
        min(
            max(requestedNodeCount, 0),
            remainingNodeCount(
                existingNodeCount: existingNodeCount,
                inFlightNodeCount: inFlightNodeCount
            )
        )
    }

    static func acceptedPrefix<Element>(
        _ elements: [Element],
        existingNodeCount: Int,
        inFlightNodeCount: Int
    ) -> [Element] {
        acceptedElements(
            elements,
            existingNodeCount: existingNodeCount,
            inFlightNodeCount: inFlightNodeCount,
            nodeCost: { _ in 1 }
        )
    }

    static func acceptedElements<Element>(
        _ elements: [Element],
        existingNodeCount: Int,
        inFlightNodeCount: Int,
        nodeCost: (Element) -> Int
    ) -> [Element] {
        var remainingNodeCount = remainingNodeCount(
            existingNodeCount: existingNodeCount,
            inFlightNodeCount: inFlightNodeCount
        )
        return elements.filter { element in
            let cost = max(nodeCost(element), 0)
            guard cost <= remainingNodeCount else {
                return false
            }
            remainingNodeCount -= cost
            return true
        }
    }
}
