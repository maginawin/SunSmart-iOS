//
//  SpaceDebugUARTLogExporter.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import Foundation

enum SpaceDebugUARTLogExporter {
    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMddHHmmss"
        return formatter
    }()

    static func makeLogText(context: SpaceDebugUARTLogExportContext, messages: [SpaceDebugUARTMessage]) -> String {
        var lines: [String] = [
            "UART Debug Log",
            "",
            "Site Name: \(context.siteName)",
            "Space Name: \(context.spaceName)",
            "Group Name: \(context.groupName ?? "")",
            "Device Name: \(context.deviceName)",
            "MAC Address: \(context.macAddress)",
            "Company ID: \(context.companyID)",
            "Product ID: \(context.productID)",
            "Address: \(context.address)",
            "Version Identifier: \(context.versionIdentifier)",
            "Model: \(context.model)",
            "Device Type: \(context.deviceType)",
            "Firmware Version: \(context.firmwareVersion)",
            "Dropped Messages: \(context.droppedMessageCount)",
            "Generated At: \(logDateFormatter.string(from: context.generatedAt))",
            "",
            "Messages:"
        ]

        messages.forEach { message in
            lines.append("[\(logDateFormatter.string(from: message.timestamp))] \(message.text)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func makeFileURL(context: SpaceDebugUARTLogExportContext, messages: [SpaceDebugUARTMessage]) throws -> URL {
        let fileName = makeFileName(context: context)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let text = makeLogText(context: context, messages: messages)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    static func makeFileName(context: SpaceDebugUARTLogExportContext) -> String {
        var components = [
            context.siteName,
            context.spaceName,
            context.groupName ?? "",
            context.deviceName,
            "uart",
            fileDateFormatter.string(from: context.generatedAt)
        ].compactMap { sanitizedFileNameComponent($0) }.filter { !$0.isEmpty }

        if components.isEmpty {
            components = ["uart-log", fileDateFormatter.string(from: context.generatedAt)]
        }

        return components.joined(separator: "-") + ".txt"
    }

    private static func sanitizedFileNameComponent(_ component: String) -> String? {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let invalidCharacters = CharacterSet(charactersIn: "/\\\\:*?\"<>|").union(.newlines)
        let cleaned = trimmed
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}
