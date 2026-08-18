import Foundation

@main
struct GatewayCloudSyncGenerationPolicyTests {

    static func main() {
        testNextGenerationIsStrictlyMonotonic()
        testConfirmationNeverRegresses()
        testOldRequestCannotCleanNewDirtyGeneration()
        testMissingRemoteTimestampMergesCleanFields()
        testDirtyGatewayPreservesLocalFields()
        testResetOrReAddReplacesCleanGateway()
        testIdentityComparisonUsesUUIDAddressAndDeviceKey()
        testDirtyIdentityConflictKeepsCurrentRegistrationSnapshot()
        testRegistrationProtectionSnapshotKeepsOnlyOpaqueSections()
        testRegistrationProtectionSnapshotSurvivesPersistenceRoundTrip()
        testPartialSnapshotRefreshPreservesMissingSections()
        testPartialElementSnapshotPreservesOpaqueBinds()
        testCompleteSnapshotCanReplaceReturnedSection()
        testNewGatewayLifecycleDropsOldSnapshotSections()
        testMissingGatewayFieldsStayAbsent()
        testExplicitEmptyAndNullFieldsRemainExplicit()
        testInvalidAssociatedSpacesDoNotBecomeAnEmptyReplacement()
        testRoleTrimmedAssociatedSpacesPreserveOpaqueEntries()
        testCompleteAssociatedSpacesCanReplaceEntries()
        testInvalidScalarFieldsStayAbsent()
        testValidMQTTFieldIsParsedWithoutRequiringCredentials()
        testRegistrationPreservesOpaqueAssociationIndexes()
        testRegistrationRemovesOnlyExplicitlyUnboundIndexes()
        print("GatewayCloudSyncGenerationPolicyTests passed")
    }

    private static func testNextGenerationIsStrictlyMonotonic() {
        require(
            GatewayCloudSyncGenerationPolicy.next(now: 100, current: 100, uploaded: 100) == 101,
            "A new local mutation must be newer than both current and uploaded generations"
        )
        require(
            GatewayCloudSyncGenerationPolicy.next(now: 50, current: 100, uploaded: 120) == 121,
            "Clock rollback must not break monotonic generation ordering"
        )
    }

    private static func testConfirmationNeverRegresses() {
        require(
            GatewayCloudSyncGenerationPolicy.confirmed(previous: 100, submitted: 90) == 100,
            "An old joined request must not reduce the confirmed generation"
        )
        require(
            GatewayCloudSyncGenerationPolicy.confirmed(previous: 80, submitted: 90) == 90,
            "A newer submitted request must advance confirmation"
        )
    }

    private static func testOldRequestCannotCleanNewDirtyGeneration() {
        require(
            GatewayCloudSyncGenerationPolicy.needsAnotherUpload(current: 101, confirmed: 100),
            "Completion for generation 100 must leave generation 101 dirty"
        )
        require(
            !GatewayCloudSyncGenerationPolicy.needsAnotherUpload(current: 100, confirmed: 100),
            "Matching generations must be clean"
        )
        require(
            GatewayCloudSyncGenerationPolicy.needsAnotherUpload(current: 1, confirmed: nil),
            "Missing confirmation must remain dirty"
        )
    }

    private static func testMissingRemoteTimestampMergesCleanFields() {
        require(
            GatewayCloudSnapshotMergePolicy.resolve(
                hasLocalGateway: true,
                localNeedsUpload: false,
                uploadInProgress: false,
                deletionInProgress: false,
                identityChanged: false,
                remoteUpdateTimestamp: nil,
                localUpdateTimestamp: 100
            ) == .mergeFields,
            "A clean cached Gateway must accept field-level cloud updates when the server omits a Gateway timestamp"
        )
    }

    private static func testDirtyGatewayPreservesLocalFields() {
        require(
            GatewayCloudSnapshotMergePolicy.resolve(
                hasLocalGateway: true,
                localNeedsUpload: true,
                uploadInProgress: false,
                deletionInProgress: false,
                identityChanged: true,
                remoteUpdateTimestamp: 200,
                localUpdateTimestamp: 100
            ) == .preserveLocal,
            "A local dirty Gateway must not be overwritten by a cloud snapshot"
        )
    }

    private static func testResetOrReAddReplacesCleanGateway() {
        require(
            GatewayCloudSnapshotMergePolicy.resolve(
                hasLocalGateway: true,
                localNeedsUpload: false,
                uploadInProgress: false,
                deletionInProgress: false,
                identityChanged: true,
                remoteUpdateTimestamp: nil,
                localUpdateTimestamp: 100
            ) == .replaceRemote,
            "A clean Gateway with changed remote identity must be treated as a new lifecycle"
        )
    }

    private static func testIdentityComparisonUsesUUIDAddressAndDeviceKey() {
        require(
            !GatewayCloudSnapshotMergePolicy.identityChanged(
                localUUID: "abc",
                localAddress: 0x0013,
                localDeviceKey: "0011",
                remoteUUID: "ABC",
                remoteAddress: 0x0013,
                remoteDeviceKey: "0011"
            ),
            "Identity comparison must normalize case"
        )
        require(
            GatewayCloudSnapshotMergePolicy.identityChanged(
                localUUID: "ABC",
                localAddress: 0x0013,
                localDeviceKey: "0011",
                remoteUUID: "DEF",
                remoteAddress: 0x0013,
                remoteDeviceKey: "0011"
            ),
            "A changed Node UUID must indicate reset or re-add"
        )
        require(
            GatewayCloudSnapshotMergePolicy.identityChanged(
                localUUID: "ABC",
                localAddress: 0x0013,
                localDeviceKey: "0011",
                remoteUUID: "ABC",
                remoteAddress: 0x0014,
                remoteDeviceKey: "0011"
            ),
            "A changed unicast address must indicate a new lifecycle"
        )
    }

    private static func testDirtyIdentityConflictKeepsCurrentRegistrationSnapshot() {
        require(
            !GatewayCloudSnapshotMergePolicy.canUpdateRegistrationSnapshot(
                decision: .preserveLocal,
                identityChanged: true
            ),
            "A dirty old lifecycle must not adopt the new remote lifecycle snapshot"
        )
        require(
            GatewayCloudSnapshotMergePolicy.canUpdateRegistrationSnapshot(
                decision: .preserveLocal,
                identityChanged: false
            ),
            "A dirty Gateway may refresh opaque data for the same lifecycle"
        )
    }

    private static func testRegistrationProtectionSnapshotKeepsOnlyOpaqueSections() {
        let snapshot = GatewayRegistrationProtectionSnapshot.updating(
            current: nil,
            remoteNode: nodePayload(indexes: [0, 1, 2]).merging([
                "deviceKey": "must-not-be-persisted",
                "gatewayPreconfigured": [
                    "mqttConnectInfo": ["password": "must-not-be-persisted"]
                ]
            ]) { _, new in new },
            resetExisting: false,
            responseIsComplete: true
        )
        let keys = Set(snapshot?.nodeData.keys.map { $0 } ?? [])
        require(
            keys == Set(["netKeys", "appKeys", "elements"]),
            "The persisted registration snapshot must contain only opaque association sections"
        )
    }

    private static func testRegistrationProtectionSnapshotSurvivesPersistenceRoundTrip() {
        let snapshot = GatewayRegistrationProtectionSnapshot.updating(
            current: nil,
            remoteNode: nodePayload(indexes: [0, 1, 2]),
            resetExisting: false,
            responseIsComplete: true
        )
        let reloaded = snapshot.flatMap {
            GatewayRegistrationProtectionSnapshot(data: $0.data)
        }
        require(
            indexes(in: reloaded?.nodeData["appKeys"]) == [0, 1, 2],
            "A database Data round trip must retain opaque AppKey indexes"
        )
        require(
            firstModelBindIndexes(in: reloaded?.nodeData ?? [:]) == [0, 1, 2],
            "A database Data round trip must retain model binds"
        )
    }

    private static func testPartialSnapshotRefreshPreservesMissingSections() {
        let original = GatewayRegistrationProtectionSnapshot.updating(
            current: nil,
            remoteNode: nodePayload(indexes: [0, 1, 2]),
            resetExisting: false,
            responseIsComplete: true
        )
        let refreshed = GatewayRegistrationProtectionSnapshot.updating(
            current: original,
            remoteNode: ["appKeys": [["index": 0], ["index": 1]]],
            resetExisting: false,
            responseIsComplete: false
        )
        require(
            indexes(in: refreshed?.nodeData["appKeys"]) == [0, 1, 2],
            "A role-trimmed snapshot section must preserve opaque indexes"
        )
        require(
            indexes(in: refreshed?.nodeData["netKeys"]) == [0, 1, 2],
            "A missing snapshot section must preserve its persisted value"
        )
    }

    private static func testPartialElementSnapshotPreservesOpaqueBinds() {
        let original = GatewayRegistrationProtectionSnapshot.updating(
            current: nil,
            remoteNode: nodePayload(indexes: [0, 1, 2]),
            resetExisting: false,
            responseIsComplete: true
        )
        let refreshed = GatewayRegistrationProtectionSnapshot.updating(
            current: original,
            remoteNode: [
                "elements": [[
                    "index": 0,
                    "models": [["modelId": "1200", "bind": [0, 1]]]
                ]]
            ],
            resetExisting: false,
            responseIsComplete: false
        )
        require(
            firstModelBindIndexes(in: refreshed?.nodeData ?? [:]) == [0, 1, 2],
            "A role-trimmed Element response must preserve opaque model binds"
        )
    }

    private static func testCompleteSnapshotCanReplaceReturnedSection() {
        let original = GatewayRegistrationProtectionSnapshot.updating(
            current: nil,
            remoteNode: nodePayload(indexes: [0, 1, 2]),
            resetExisting: false,
            responseIsComplete: true
        )
        let refreshed = GatewayRegistrationProtectionSnapshot.updating(
            current: original,
            remoteNode: ["appKeys": [["index": 0], ["index": 1]]],
            resetExisting: false,
            responseIsComplete: true
        )
        require(
            indexes(in: refreshed?.nodeData["appKeys"]) == [0, 1],
            "A complete Owner response may replace an explicitly returned section"
        )
        require(
            indexes(in: refreshed?.nodeData["netKeys"]) == [0, 1, 2],
            "Even a complete response must not clear an omitted section"
        )
    }

    private static func testNewGatewayLifecycleDropsOldSnapshotSections() {
        let original = GatewayRegistrationProtectionSnapshot.updating(
            current: nil,
            remoteNode: nodePayload(indexes: [0, 1, 2]),
            resetExisting: false,
            responseIsComplete: true
        )
        let refreshed = GatewayRegistrationProtectionSnapshot.updating(
            current: original,
            remoteNode: ["appKeys": [["index": 0]]],
            resetExisting: true,
            responseIsComplete: false
        )
        require(
            refreshed?.nodeData["netKeys"] == nil,
            "A reset or re-added Gateway must not inherit old lifecycle NetKeys"
        )
    }

    private static func testMissingGatewayFieldsStayAbsent() {
        let patch = GatewayCloudConfigurationPatch(nodePayload: [
            "name": "Remote Gateway",
            "gatewayPreconfigured": ["activate": true]
        ])
        require(value(patch.name) == "Remote Gateway", "An explicit name must be parsed")
        require(value(patch.activate) == true, "An explicit activation state must be parsed")
        require(isAbsent(patch.associatedSpaces), "Missing associatedSpaces must stay absent")
        require(isAbsent(patch.apn), "Missing APN must stay absent")
        require(isAbsent(patch.mqttConnectInfo), "Missing MQTT information must stay absent")
    }

    private static func testExplicitEmptyAndNullFieldsRemainExplicit() {
        let patch = GatewayCloudConfigurationPatch(nodePayload: [
            "gatewayPreconfigured": [
                "associatedSpaces": [],
                "apn": NSNull(),
                "mqttConnectInfo": NSNull()
            ]
        ])
        require(
            value(patch.associatedSpaces)?.isEmpty == true,
            "An explicit empty associatedSpaces array must remain an explicit replacement"
        )
        require(isClear(patch.apn), "An explicit null APN must request a clear")
        require(isClear(patch.mqttConnectInfo), "Explicit null MQTT information must request a clear")
    }

    private static func testInvalidAssociatedSpacesDoNotBecomeAnEmptyReplacement() {
        let patch = GatewayCloudConfigurationPatch(nodePayload: [
            "gatewayPreconfigured": [
                "associatedSpaces": [[
                    "spaceId": "space-1",
                    "spaceName": "Space 1"
                ]]
            ]
        ])
        require(
            isAbsent(patch.associatedSpaces),
            "A malformed associatedSpaces response must preserve the complete local list"
        )
    }

    private static func testRoleTrimmedAssociatedSpacesPreserveOpaqueEntries() {
        let local = [
            associatedSpace(id: "space-1", appKeyIndex: 1),
            associatedSpace(id: "space-2", appKeyIndex: 2)
        ]
        let merged = GatewayCloudAssociatedSpaceMergePolicy.resolve(
            local: local,
            remote: [associatedSpace(id: "space-1", appKeyIndex: 1)],
            responseIsComplete: false
        )
        require(
            merged.map(\.spaceId) == ["space-1", "space-2"],
            "A role-trimmed association list must preserve opaque local entries"
        )
    }

    private static func testCompleteAssociatedSpacesCanReplaceEntries() {
        let merged = GatewayCloudAssociatedSpaceMergePolicy.resolve(
            local: [
                associatedSpace(id: "space-1", appKeyIndex: 1),
                associatedSpace(id: "space-2", appKeyIndex: 2)
            ],
            remote: [associatedSpace(id: "space-1", appKeyIndex: 1)],
            responseIsComplete: true
        )
        require(
            merged.map(\.spaceId) == ["space-1"],
            "A complete Owner association list may replace persisted entries"
        )
    }

    private static func testInvalidScalarFieldsStayAbsent() {
        let patch = GatewayCloudConfigurationPatch(nodePayload: [
            "gatewayPreconfigured": [
                "activate": 1,
                "apn": ["unexpected": "object"],
                "mqttConnectInfo": [
                    "serverAddress": "tcp://example.com:1883",
                    "clientId": "client",
                    "clearSession": 1
                ]
            ]
        ])
        require(isAbsent(patch.activate), "A numeric activate value must not become Bool")
        require(isAbsent(patch.apn), "An invalid APN type must preserve the local value")
        require(
            isAbsent(patch.mqttConnectInfo),
            "An invalid nested MQTT field must preserve the complete local configuration"
        )
    }

    private static func testValidMQTTFieldIsParsedWithoutRequiringCredentials() {
        let patch = GatewayCloudConfigurationPatch(nodePayload: [
            "gatewayPreconfigured": [
                "mqttConnectInfo": [
                    "serverAddress": "tcp://example.com:1883",
                    "clientId": "client",
                    "keepalive": 90,
                    "clearSession": false,
                    "authMode": 0,
                    "sslVersion": 4
                ]
            ]
        ])
        let mqtt = value(patch.mqttConnectInfo)
        require(mqtt?.serverAddress == "tcp://example.com:1883", "MQTT server must parse")
        require(mqtt?.userName == nil, "Optional MQTT username may be absent")
        require(mqtt?.password == nil, "Optional MQTT password may be absent")
        require(mqtt?.keepalive == 90, "MQTT keepalive must parse")
    }

    private static func testRegistrationPreservesOpaqueAssociationIndexes() {
        let remote = nodePayload(indexes: [0, 1, 2])
        let local = nodePayload(indexes: [0, 1])
        let merged = GatewayRegistrationPayloadPolicy.mergeOpaqueAssociationData(
            localNode: local,
            remoteNode: remote,
            associatedAppKeyIndexes: [1, 2],
            isActivated: true
        )

        require(indexes(in: merged["appKeys"]) == [0, 1, 2],
                "A partial Editor payload must preserve the opaque AppKey index")
        require(indexes(in: merged["netKeys"]) == [0, 1, 2],
                "A partial Editor payload must preserve the opaque NetKey index")
        require(gatewaySubnetIndexes(in: merged) == [1, 2],
                "Gateway subnet indexes must come from the complete associated-space draft")
        require(firstModelBindIndexes(in: merged) == [0, 1, 2],
                "Element binds must preserve opaque associated indexes")
    }

    private static func testRegistrationRemovesOnlyExplicitlyUnboundIndexes() {
        let merged = GatewayRegistrationPayloadPolicy.mergeOpaqueAssociationData(
            localNode: nodePayload(indexes: [0, 1]),
            remoteNode: nodePayload(indexes: [0, 1, 2]),
            associatedAppKeyIndexes: [2],
            isActivated: true
        )
        require(indexes(in: merged["appKeys"]) == [0, 2],
                "An authorized unbind must remove only the absent final association")
        require(firstModelBindIndexes(in: merged) == [0, 2],
                "Model binds must follow the final complete association set")
    }

    private static func nodePayload(indexes: [Int]) -> [String: Any] {
        [
            "netKeys": indexes.map { ["index": $0, "updated": false] },
            "appKeys": indexes.map { ["index": $0, "updated": false] },
            "gatewayInfo": ["subnetAppkeyIndexs": indexes.filter { $0 != 0 }],
            "elements": [[
                "index": 0,
                "models": [[
                    "modelId": "1200",
                    "bind": indexes,
                    "subscribe": []
                ]]
            ]]
        ]
    }

    private static func associatedSpace(
        id: String,
        appKeyIndex: UInt16
    ) -> GatewayCloudAssociatedSpace {
        GatewayCloudAssociatedSpace(
            spaceId: id,
            spaceName: id,
            deviceCount: 0,
            appKeyIndex: appKeyIndex
        )
    }

    private static func indexes(in value: Any?) -> [Int] {
        (value as? [[String: Any]] ?? [])
            .compactMap { $0["index"] as? Int }
            .sorted()
    }

    private static func gatewaySubnetIndexes(in payload: [String: Any]) -> [Int] {
        let info = payload["gatewayInfo"] as? [String: Any]
        return (info?["subnetAppkeyIndexs"] as? [Int] ?? []).sorted()
    }

    private static func firstModelBindIndexes(in payload: [String: Any]) -> [Int] {
        let elements = payload["elements"] as? [[String: Any]]
        let models = elements?.first?["models"] as? [[String: Any]]
        return (models?.first?["bind"] as? [Int] ?? []).sorted()
    }

    private static func value<T>(_ field: GatewayCloudPatchField<T>) -> T? {
        guard case .value(let value) = field else { return nil }
        return value
    }

    private static func isAbsent<T>(_ field: GatewayCloudPatchField<T>) -> Bool {
        if case .absent = field { return true }
        return false
    }

    private static func isClear<T>(_ field: GatewayCloudPatchField<T>) -> Bool {
        if case .clear = field { return true }
        return false
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
        }
    }
}
