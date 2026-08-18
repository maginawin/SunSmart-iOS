//
//  GatewayServerAuthorizationService.swift
//  SunSmart
//
import Foundation
import NordicSigMeshSDK

enum GatewayServerAuthorizationRequestPolicy: Equatable {
    case ifMissing
    case always
}

struct GatewayServerAuthorizationReceipt {
    let information: GatewayInformation.MQTTConnectInformation
    let submittedGeneration: Int64
}

enum GatewayServerAuthorizationError: Error, Equatable {
    case noNetwork
    case nodeExportFailed
    case requestFailed(NetworkApiError)
    case invalidResponse(missingFields: [String])
    case persistenceFailed
    case serverDeletionPendingLocalReset

    var networkApiError: NetworkApiError {
        switch self {
        case .noNetwork:
            return .noNetwork
        case .requestFailed(let error):
            return error
        case .nodeExportFailed, .invalidResponse, .persistenceFailed, .serverDeletionPendingLocalReset:
            return .init(
                code: 9998,
                message: diagnosticDescription,
                httpStatusCode: nil,
                responseBody: nil
            )
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .noNetwork:
            return "phone has no network"
        case .nodeExportFailed:
            return "node export failed"
        case .requestFailed(let error):
            return "request failed: \(error.code)"
        case .invalidResponse(let missingFields):
            return "invalid response fields: \(missingFields.sorted().joined(separator: ","))"
        case .persistenceFailed:
            return "gateway persistence failed"
        case .serverDeletionPendingLocalReset:
            return "gateway server deletion is pending local reset"
        }
    }
}

extension GatewayServerAuthorizationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noNetwork:
            return "phone_no_network".localizedString
        case .requestFailed(let error):
            return error.localizedDescription
        case .nodeExportFailed, .invalidResponse, .persistenceFailed, .serverDeletionPendingLocalReset:
            return "server_failure".localizedString
        }
    }
}

actor GatewayServerAuthorizationService {
    typealias MQTTInformation = GatewayInformation.MQTTConnectInformation

    static let shared = GatewayServerAuthorizationService()

    private struct InFlightAuthorization {
        let id: UUID
        let submittedGeneration: Int64
        let task: Task<Result<MQTTInformation, GatewayServerAuthorizationError>, Never>
    }

    private var inFlightAuthorizations: [String: InFlightAuthorization] = [:]

    static func isValid(_ information: MQTTInformation?) -> Bool {
        guard let information else { return false }
        return !information.serverAddress.isEmpty
            && !information.clientId.isEmpty
            && !(information.userName?.isEmpty ?? true)
            && !(information.password?.isEmpty ?? true)
    }

    static func parse(
        response: [String: Any]
    ) -> Result<MQTTInformation, GatewayServerAuthorizationError> {
        guard let data = response["data"] as? [String: Any] else {
            return .failure(.invalidResponse(missingFields: ["data"]))
        }

        var missingFields: [String] = []
        let username = data["mqttUsername"] as? String
        let password = data["mqttPassword"] as? String
        let clientId = data["mqttClientId"] as? String
        let host = data["host"] as? String
        let port = data["port"] as? Int

        if username?.isEmpty != false { missingFields.append("mqttUsername") }
        if password?.isEmpty != false { missingFields.append("mqttPassword") }
        if clientId?.isEmpty != false { missingFields.append("mqttClientId") }
        if host?.isEmpty != false { missingFields.append("host") }
        if port == nil || !(1...65535).contains(port ?? 0) { missingFields.append("port") }

        guard missingFields.isEmpty,
              let username,
              let password,
              let clientId,
              let host,
              let port else {
            return .failure(.invalidResponse(missingFields: missingFields))
        }

        return .success(
            MQTTInformation(
                customId: customId,
                serverAddress: "tcp://\(host):\(port)",
                userName: username,
                password: password,
                clientId: clientId,
                keepalive: 60,
                clearSession: true,
                authMode: .none,
                sslVersion: .all
            )
        )
    }

    private static func persist(
        _ information: MQTTInformation,
        to gateway: GatewayModel
    ) -> Result<MQTTInformation, GatewayServerAuthorizationError> {
        let previousInformation = gateway.mqttServerInfo
        gateway.mqttServerInfo = information
        guard gateway.save() else {
            gateway.mqttServerInfo = previousInformation
            return .failure(.persistenceFailed)
        }
        return .success(information)
    }

    func authorize(
        gateway: GatewayModel,
        node: Node,
        policy: GatewayServerAuthorizationRequestPolicy = .ifMissing
    ) async -> Result<MQTTInformation, GatewayServerAuthorizationError> {
        let result = await authorizeWithReceipt(
            gateway: gateway,
            node: node,
            policy: policy,
            requestedGeneration: gateway.lastUpdate
        )
        return result.map(\.information)
    }

    func authorizeWithReceipt(
        gateway: GatewayModel,
        node: Node,
        policy: GatewayServerAuthorizationRequestPolicy = .ifMissing,
        requestedGeneration: Int64
    ) async -> Result<GatewayServerAuthorizationReceipt, GatewayServerAuthorizationError> {
        guard !gateway.isServerDeletionInProgress,
              !gateway.serverDeletionPendingLocalReset else {
            return .failure(.serverDeletionPendingLocalReset)
        }
        if policy == .ifMissing,
           let information = gateway.mqttServerInfo,
           Self.isValid(information) {
            return .success(
                GatewayServerAuthorizationReceipt(
                    information: information,
                    submittedGeneration: requestedGeneration
                )
            )
        }
        guard NetworkRequest.shared.networkable else {
            return .failure(.noNetwork)
        }

        let key = "\(gateway.siteId)|\(gateway.mac.uppercased())"
        let authorization: InFlightAuthorization
        if let existing = inFlightAuthorizations[key] {
            authorization = existing
        } else {
            let id = UUID()
            let task = Task<Result<MQTTInformation, GatewayServerAuthorizationError>, Never> {
                guard var nodeData = await node.export() else {
                    return .failure(.nodeExportFailed)
                }
                nodeData = GatewayRegistrationPayloadPolicy
                    .mergeOpaqueAssociationData(
                        localNode: nodeData,
                        remoteNode: gateway.registrationProtectionSnapshot?.nodeData,
                        associatedAppKeyIndexes: gateway.associatedSpaces.map(
                            \.appKeyIndex
                        ),
                        isActivated: gateway.activate
                    )
                nodeData["gatewayPreconfigured"] = gateway.export()
                let result = await NetworkRequest.shared.request(
                    .gatewayRegister(
                        siteId: gateway.siteId,
                        gatewayId: gateway.mac,
                        nodeId: node.uuid.uuidString,
                        node: nodeData,
                        updateTimestamp: requestedGeneration
                    )
                )
                switch result {
                case .success(let response):
                    return Self.parse(response: response)
                case .failure(let error):
                    return .failure(.requestFailed(error))
                }
            }
            authorization = InFlightAuthorization(
                id: id,
                submittedGeneration: requestedGeneration,
                task: task
            )
            inFlightAuthorizations[key] = authorization
        }

        let result = await authorization.task.value
        if inFlightAuthorizations[key]?.id == authorization.id {
            inFlightAuthorizations[key] = nil
        }

        guard !gateway.isServerDeletionInProgress,
              !gateway.serverDeletionPendingLocalReset else {
            return .failure(.serverDeletionPendingLocalReset)
        }

        switch result {
        case .success(let information):
            return Self.persist(information, to: gateway).map {
                GatewayServerAuthorizationReceipt(
                    information: $0,
                    submittedGeneration: authorization.submittedGeneration
                )
            }
        case .failure(let error):
            if policy == .always,
               let information = gateway.mqttServerInfo,
               Self.isValid(information),
               case .invalidResponse = error {
                return .success(
                    GatewayServerAuthorizationReceipt(
                        information: information,
                        submittedGeneration: authorization.submittedGeneration
                    )
                )
            }
            return .failure(error)
        }
    }

    func waitForInFlightAuthorizationToFinish(
        gateway: GatewayModel
    ) async {
        let key = "\(gateway.siteId)|\(gateway.mac.uppercased())"
        guard let authorization = inFlightAuthorizations[key] else {
            return
        }
        _ = await authorization.task.value
        if inFlightAuthorizations[key]?.id == authorization.id {
            inFlightAuthorizations[key] = nil
        }
    }
}
