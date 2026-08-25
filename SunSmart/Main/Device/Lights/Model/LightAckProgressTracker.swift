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
    private var activeContext: LightAckCommandContext?
    private var activeBaseLines: [String] = []
    private var activeLines: [String] = []
    private var activeExpectedSource: Address?
    private var activeExpectedResponseOpCode: UInt32?
    private var activeAppTxTTL: UInt8?
    private var activeReplayDiagnostic: MeshReplayProtectionDiscardEvent?
    private var replayDiscardObserver: NSObjectProtocol?

    private init() {
        replayDiscardObserver = NotificationCenter.default.addObserver(
            forName: .meshReplayProtectionDiscarded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleReplayProtectionDiscard(notification)
        }
    }

    deinit {
        if let replayDiscardObserver {
            NotificationCenter.default.removeObserver(replayDiscardObserver)
        }
    }

    static func deviceName(_ node: Node) -> String {
        if let name = node.name, !name.isEmpty {
            return name
        }
        return String(format: "0x%04X", node.primaryUnicastAddress)
    }

    static func context(deviceName: String, commandDescription: String, opcode: UInt32) -> LightAckCommandContext {
        LightAckCommandContext(title: "\(deviceName) \(commandDescription)", opcode: opcode)
    }

    func send(message: StaticAcknowledgedMeshMessage, model: Model, context: LightAckCommandContext, defaultTTL: UInt8? = nil) {
        let commandId = UUID()
        activeCommandId = commandId
        activeContext = context
        activeExpectedSource = model.parentElement?.unicastAddress
        activeExpectedResponseOpCode = message.responseOpCode
        activeAppTxTTL = defaultTTL
        activeReplayDiagnostic = nil
        activeBaseLines = [
            String(format: "light_ack_sent_format".localizedString, context.title),
            String(format: "light_ack_command_format".localizedString, context.opcode)
        ]
        activeLines = activeBaseLines
        alertView = LightAckProgressAlertView.show(title: context.title, message: activeLines.joined(separator: "\n"))

        MeshAPI.sendMessageWithReceiveMetadata(
            message: message,
            model: model,
            defaultTTL: defaultTTL
        ) { [weak self] response in
            DispatchQueue.main.async {
                self?.finish(commandId: commandId, context: context, response: response)
            }
        }
    }

    private func finish(
        commandId: UUID,
        context: LightAckCommandContext,
        response: StaticMeshResponseReceiveResult?
    ) {
        guard commandId == activeCommandId else { return }

        activeLines = activeBaseLines
        if let responseResult = response {
            let response = responseResult.response
            if let vendorStatus = response as? SunricherVendorStatus, !vendorStatus.status.isSuccessful {
                activeLines.append(String(format: "light_ack_result_failed_format".localizedString, context.title))
            } else {
                activeLines.append(String(format: "light_ack_result_ok_format".localizedString, context.title))
            }
            if let receivedTTL = responseResult.receivedTTL,
               let activeAppTxTTL {
                activeLines.append(ttlLine(receivedTTL: receivedTTL, appTxTTL: activeAppTxTTL))
            }
            activeLines.append(String(format: "light_ack_response_format".localizedString, String(describing: type(of: response))))
        } else if let activeReplayDiagnostic {
            activeLines.append(contentsOf: replayDiagnosticLines(activeReplayDiagnostic, context: context))
        } else {
            activeLines.append(String(format: "light_ack_result_timeout_format".localizedString, context.title))
        }

        alertView?.update(title: context.title, message: activeLines.joined(separator: "\n"))
        activeContext = nil
        activeExpectedSource = nil
        activeExpectedResponseOpCode = nil
        activeAppTxTTL = nil
    }

    private func handleReplayProtectionDiscard(_ notification: Notification) {
        guard let diagnostic = notification.userInfo?[MeshReplayProtectionDiscardEvent.userInfoKey] as? MeshReplayProtectionDiscardEvent,
              let activeExpectedSource,
              diagnostic.source == activeExpectedSource else {
            return
        }
        let pendingOpCode = diagnostic.pendingResponseOpCode ?? diagnostic.pendingMessageOpCode
        if let pendingOpCode, let activeExpectedResponseOpCode, pendingOpCode != activeExpectedResponseOpCode {
            return
        }

        activeReplayDiagnostic = diagnostic
        guard let activeContext else { return }
        activeLines = activeBaseLines + replayDiagnosticLines(diagnostic, context: activeContext)
        alertView?.update(title: activeContext.title, message: activeLines.joined(separator: "\n"))
    }

    private func replayDiagnosticLines(_ diagnostic: MeshReplayProtectionDiscardEvent, context: LightAckCommandContext) -> [String] {
        var lines = [
            String(format: "light_ack_result_replay_rejected_format".localizedString, context.title)
        ]
        if let activeAppTxTTL {
            lines.append(ttlLine(receivedTTL: diagnostic.receivedTTL, appTxTTL: activeAppTxTTL))
        }
        lines.append(
            String(
                format: "light_ack_replay_detail_format".localizedString,
                Int(diagnostic.source),
                "\(diagnostic.receivedSeqAuth)",
                "\(diagnostic.expectedGreaterThanSeqAuth)"
            )
        )
        return lines
    }

    private func ttlLine(receivedTTL: UInt8, appTxTTL: UInt8) -> String {
        String(
            format: "light_ack_ttl_format".localizedString,
            Int(receivedTTL),
            Int(appTxTTL)
        )
    }
}
