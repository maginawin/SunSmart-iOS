//
//  LightAckProgressTracker.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

struct LightAckCommandContext {
    let title: String
    let opcode: UInt32
}

final class LightAckProgressTracker {

    static let shared = LightAckProgressTracker()

    private var alertView: LightAckProgressAlertView?
    private var activeCommandId = UUID()
    private var activeLines: [String] = []

    private init() {}

    static func deviceName(_ node: Node) -> String {
        if let name = node.name, !name.isEmpty {
            return name
        }
        return String(format: "0x%04X", node.primaryUnicastAddress)
    }

    static func context(deviceName: String, commandDescription: String, opcode: UInt32) -> LightAckCommandContext {
        LightAckCommandContext(title: "\(deviceName) \(commandDescription)", opcode: opcode)
    }

    func send(message: StaticAcknowledgedMeshMessage, model: Model, context: LightAckCommandContext) {
        let commandId = UUID()
        activeCommandId = commandId
        activeLines = [
            String(format: "light_ack_sent_format".localizedString, context.title),
            String(format: "light_ack_command_format".localizedString, context.opcode)
        ]
        alertView = LightAckProgressAlertView.show(title: context.title, message: activeLines.joined(separator: "\n"))

        MeshAPI.sendMessage(message: message, model: model) { [weak self] response in
            DispatchQueue.main.async {
                self?.finish(commandId: commandId, context: context, response: response)
            }
        }
    }

    private func finish(commandId: UUID, context: LightAckCommandContext, response: StaticMeshResponse?) {
        guard commandId == activeCommandId else { return }

        if let response = response {
            if let vendorStatus = response as? SunricherVendorStatus, !vendorStatus.status.isSuccessful {
                activeLines.append(String(format: "light_ack_result_failed_format".localizedString, context.title))
            } else {
                activeLines.append(String(format: "light_ack_result_ok_format".localizedString, context.title))
            }
            activeLines.append(String(format: "light_ack_response_format".localizedString, String(describing: type(of: response))))
        } else {
            activeLines.append(String(format: "light_ack_result_timeout_format".localizedString, context.title))
        }

        alertView?.update(title: context.title, message: activeLines.joined(separator: "\n"))
    }
}
