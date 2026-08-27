//
//  UpDownRatioCommandScheduler.swift
//  SunSmart
//

import Foundation

struct UpDownRatioCommandScheduler {

    enum Kind: Equatable {
        case sampling
        case final
    }

    struct Command: Equatable {
        let value: Int
        let kind: Kind
        let editGeneration: UInt
    }

    private(set) var isCommandInFlight = false
    private var pendingCommands: [Command] = []

    mutating func enqueueSampling(value: Int, editGeneration: UInt) -> Command? {
        let command = Command(
            value: clamped(value),
            kind: .sampling,
            editGeneration: editGeneration
        )
        if pendingCommands.last?.kind == .sampling {
            pendingCommands[pendingCommands.count - 1] = command
        } else {
            pendingCommands.append(command)
        }
        return takeNextCommandIfIdle()
    }

    mutating func enqueueFinal(value: Int, editGeneration: UInt) -> Command? {
        if pendingCommands.last?.kind == .sampling {
            pendingCommands.removeLast()
        }
        pendingCommands.append(
            Command(
                value: clamped(value),
                kind: .final,
                editGeneration: editGeneration
            )
        )
        return takeNextCommandIfIdle()
    }

    mutating func completeCurrentCommand() -> Command? {
        guard isCommandInFlight else { return nil }
        isCommandInFlight = false
        return takeNextCommandIfIdle()
    }

    private mutating func takeNextCommandIfIdle() -> Command? {
        guard !isCommandInFlight, !pendingCommands.isEmpty else { return nil }
        isCommandInFlight = true
        return pendingCommands.removeFirst()
    }

    private func clamped(_ value: Int) -> Int {
        max(0, min(100, value))
    }
}
