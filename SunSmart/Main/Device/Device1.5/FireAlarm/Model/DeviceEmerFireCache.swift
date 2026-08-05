//
//  DeviceEmerFireCache.swift
//  SunSmart
//
//  Created by One on 2026/8/5.
//

import Foundation

final class DeviceEmerFireCache<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element] = []

    func replace(with newElements: [Element]) {
        withLock {
            elements = newElements
        }
    }

    func merge(_ newElements: [Element], matching areSame: (Element, Element) -> Bool) {
        withLock {
            newElements.forEach { incoming in
                if let index = elements.firstIndex(where: { areSame($0, incoming) }) {
                    elements[index] = incoming
                } else {
                    elements.append(incoming)
                }
            }
        }
    }

    func removeAll(where shouldRemove: (Element) -> Bool) {
        withLock {
            elements.removeAll(where: shouldRemove)
        }
    }

    func snapshot() -> [Element] {
        withLock { elements }
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
