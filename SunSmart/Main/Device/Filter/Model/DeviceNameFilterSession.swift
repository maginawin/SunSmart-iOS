//
//  DeviceNameFilterSession.swift
//  SunSmart
//
//  Created by One on 2026/7/22.
//

import Foundation

final class DeviceNameFilterSession {
    typealias Observer = (String) -> Void

    private var observers: [UUID: Observer] = [:]
    private(set) var query: String = ""

    var isActive: Bool {
        !query.isEmpty
    }

    @discardableResult
    func observe(_ observer: @escaping Observer) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(query)
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    func submit(_ rawQuery: String) {
        let normalized = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != query else {
            return
        }
        query = normalized
        observers.values.forEach { $0(query) }
    }

    func reset() {
        submit("")
    }

    func matches(_ candidate: String) -> Bool {
        !isActive || candidate.localizedCaseInsensitiveContains(query)
    }

    func matches(anyOf candidates: [String]) -> Bool {
        !isActive || candidates.contains { matches($0) }
    }

    func filtered<Value>(_ values: [Value], names: (Value) -> [String]) -> [Value] {
        guard isActive else {
            return values
        }
        return values.filter { matches(anyOf: names($0)) }
    }
}
