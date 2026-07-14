//
//  FirmwareVersionUpdatePolicy.swift
//  SunSmart
//
//  Created by One on 2026/7/14.
//

import Foundation

enum FirmwareVersionUpdateEligibility: Equatable {
    case allowed
    case disallowed
    case invalid
}

enum FirmwareVersionUpdatePolicy {
    case numeric
    case bleBatchAware

    func isCurrentVersionUpToDate(
        currentVersion: String?,
        targetVersion: String?
    ) -> Bool {
        eligibility(
            currentVersion: currentVersion,
            targetVersion: targetVersion
        ) == .disallowed
    }

    func eligibility(
        currentVersion: String?,
        targetVersion: String?
    ) -> FirmwareVersionUpdateEligibility {
        guard let currentVersion, let targetVersion else {
            return .invalid
        }

        switch self {
        case .numeric:
            return targetVersion.compare(currentVersion, options: .numeric) == .orderedDescending
                ? .allowed
                : .disallowed
        case .bleBatchAware:
            guard let current = ParsedBLEFirmwareVersion(currentVersion),
                  let target = ParsedBLEFirmwareVersion(targetVersion) else {
                return .invalid
            }

            if current.base != target.base {
                return target.base.lexicographicallyPrecedes(current.base)
                    ? .disallowed
                    : .allowed
            }

            switch (current.batch, target.batch) {
            case (nil, nil), (nil, .some):
                return .disallowed
            case (.some, nil):
                return .allowed
            case let (.some(currentBatch), .some(targetBatch)):
                return currentBatch == targetBatch ? .disallowed : .allowed
            }
        }
    }
}

private struct ParsedBLEFirmwareVersion {
    let base: [UInt]
    let batch: String?

    init?(_ value: String) {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 || components.count == 4 else {
            return nil
        }

        let base = components.prefix(3).compactMap { UInt($0) }
        guard base.count == 3 else {
            return nil
        }

        if components.count == 4, components[3].isEmpty {
            return nil
        }

        self.base = base
        self.batch = components.count == 4 ? String(components[3]) : nil
    }
}
