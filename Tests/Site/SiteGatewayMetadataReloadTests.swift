import Foundation

enum Permission { case owner, editor, visitor }
struct UserData { let name: String; let uuid: String }
final class SpaceData {
    enum State { case normal, waitDeleted }
    enum GatewayStatus { case online, offline, notBound }
    var id: String
    var siteId = "site"
    var meshUUID = "mesh"
    var meshNetworkId: String
    var state = State.normal
    var permission = Permission.owner
    var deviceCount = 0
    var lastUpdate: Int64 = 100
    var relevanceGatewayId: String?
    var gatewayStatus = GatewayStatus.notBound
    var gatewayLastOnline: Int64?
    var shareCode: String?
    var vistorPasswordEnable = false
    var requiresPasswordVerification = false
    var vistorPassword: String?
    var owner: UserData?
    var editor: UserData?
    var visitors: [UserData] = []
    var applyDeviceAddressCount: Int?
    var applyGroupAddressCount: Int?
    var releaseAddress = false
    var disableEditorPermission = false
    static var rows: [SpaceData] = []
    static var reads = 0

    init(_ id: String) { self.id = id; meshNetworkId = "network-" + id }

    static func load(siteId: String, spaceId: String? = nil) -> [SpaceData] {
        reads += 1
        return rows.filter { $0.siteId == siteId && (spaceId == nil || $0.id == spaceId) }.map { row in
            let space = SpaceData(row.id)
            space.siteId = row.siteId; space.meshUUID = row.meshUUID
            space.meshNetworkId = row.meshNetworkId; space.state = row.state
            space.permission = row.permission; space.deviceCount = row.deviceCount
            space.lastUpdate = row.lastUpdate
            return space
        }
    }
}
final class SiteData {
    let id = "site"
    let meshUUID = "mesh"
    var timezone: String? = "Asia/Shanghai (UTC+08:00)"
    var spaces: [SpaceData] = []
    var gatewayPresence = SiteGatewayLastOnlineSnapshot(gateways: nil)
}
enum SpaceMembershipCoordinator {
    static func accepts(_ payload: [String: Any]) -> Bool { true }
}
enum SpaceConfigurationSafety {
    static func reconcileAuthority(_ space: SpaceData, remote: [String: Any]) {}
}
enum SiteDeviceOwnershipReconciler {
    static var changed = Set<String>()
    static func reconcile(siteId: String) -> Set<String> { changed }
}
enum GatewayDeletionContext {
    static var confirmed = Set<String>()
    static func serverDeletionConfirmed(siteId: String, mac: String) -> Bool {
        confirmed.contains(siteId + ":" + mac)
    }
}
struct MeshNetwork {}
struct Node {}
enum GatewayConnectStatus { case online, offline, inactive }
struct GatewayModel {
    let mac: String
    static var activationOverrides: [String: Bool] = [:]
    static func load(siteId: String) -> [GatewayModel] { [.init(mac: "G1"), .init(mac: "G2")] }
    func resolveNode(in network: MeshNetwork) -> Node? { Node() }
}
final class Gateway {
    let mac: String
    var activate = true
    var connectStatus = GatewayConnectStatus.offline
    var lastOnlineTime: String?
    init(model: GatewayModel, node: Node) {
        mac = model.mac
        activate = GatewayModel.activationOverrides[mac] ?? true
    }
}
extension String {
    var localizedString: String { self }
}
struct GatewayOverviewStats: Equatable {
    var internetOnlineCount: Int
    var internetOfflineCount: Int
    var noGatewayCount: Int
}
final class StatusView {
    var stats = GatewayOverviewStats(internetOnlineCount: 0, internetOfflineCount: 0, noGatewayCount: 0)
    func updateOverviewStats(_ stats: GatewayOverviewStats) { self.stats = stats }
}
final class Header { let gatewayStatusView = StatusView() }
final class SiteController {
    let site: SiteData
    var allSpaces: [SpaceData] { site.spaces }
    init(_ site: SiteData) { self.site = site }
    func sitePrimaryMeshNetwork() -> MeshNetwork? { MeshNetwork() }
}

@main
struct SiteGatewayMetadataReloadTests {
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }

    static func fixture() -> (SiteData, SiteController) {
        SpaceData.rows = [SpaceData("S1"), SpaceData("S2")]
        SpaceData.reads = 0
        SiteDeviceOwnershipReconciler.changed = []
        GatewayDeletionContext.confirmed = []
        GatewayModel.activationOverrides = [:]
        let site = SiteData()
        site.spaces = SpaceData.load(siteId: site.id)
        for (index, space) in site.spaces.enumerated() {
            // Configuration timestamp equals the cached version. Presence is
            // applied independently by the actual production metadata importer.
            space.applyRemoteSpaceMetadata([
                "uuid": space.id, "gatewayId": "G\(index + 1)",
                "gatewayOnline": true, "updateTimestamp": space.lastUpdate
            ])
        }
        SpaceData.reads = 0
        return (site, SiteController(site))
    }

    static func expectOnline(_ controller: SiteController, _ phase: String) {
        expect(controller.overview() == .init(internetOnlineCount: 2, internetOfflineCount: 0, noGatewayCount: 0),
               "\(phase): expected All spaces 2 / 0 / 0")
        expect(controller.gateways().allSatisfy { $0.connectStatus == .online },
               "\(phase): both activated gateways must remain online")
    }

    static func main() async {
        let (site, controller) = fixture()
        let originals = site.spaces
        await site.importReload()
        expectOnline(controller, "same-version import without ownership repair")
        controller.reappear()
        expectOnline(controller, "return to Site")
        expect(SpaceData.reads == 0 && site.spaces[0] === originals[0],
               "no ownership changes must keep existing instances without DB reload")

        SpaceData.rows[0].deviceCount = 7
        SpaceData.rows[0].lastUpdate = 200
        SpaceData.rows[0].permission = .editor
        SiteDeviceOwnershipReconciler.changed = ["S1"]
        await site.importReload()
        expectOnline(controller, "ownership repair import")
        expect(site.spaces[0] !== originals[0] && site.spaces[1] === originals[1],
               "reload only changed Spaces")
        expect(site.spaces[0].deviceCount == 7 && site.spaces[0].lastUpdate == 200,
               "gateway preservation must not overwrite repaired configuration")
        expect(site.spaces[0].permission == .editor, "gateway preservation must not overwrite updated permission")
        SpaceData.rows[0].deviceCount = 8
        controller.reappear()
        expectOnline(controller, "return after ownership repair")
        expect(site.spaces[0].deviceCount == 8, "return must load repaired counts")

        controller.refreshList()
        expectOnline(controller, "list notification")
        site.spaces[0].applyRemoteSpaceMetadata([
            "uuid": "S1", "gatewayId": "G1", "gatewayOnline": false,
            "gatewayLastupdate": Int64(1789609650)
        ])
        controller.refreshList()
        expect(controller.overview() == .init(internetOnlineCount: 1, internetOfflineCount: 1, noGatewayCount: 0),
               "real offline status must survive list reload")
        let offline = controller.gateways()[0]
        expect(offline.connectStatus == .offline && offline.lastOnlineTime == "2026-09-17 09:47",
               "offline gateway must retain last online timestamp")

        site.spaces[0].applyRemoteSpaceMetadata(["uuid": "S1", "gatewayId": ""])
        controller.refreshList()
        expect(site.spaces[0].relevanceGatewayId == nil && site.spaces[0].gatewayStatus == .notBound
               && site.spaces[0].gatewayLastOnline == nil, "explicit unbind must clear all metadata")
        let snapshot = SiteGatewayAssociationSnapshot.make(isComplete: true, rawGatewayIds: [])
        if case .clearOrphan = snapshot.decision(for: site.spaces[1].relevanceGatewayId) {
            site.spaces[1].relevanceGatewayId = nil
            site.spaces[1].gatewayStatus = .notBound
            site.spaces[1].gatewayLastOnline = nil
        }
        controller.refreshList()
        expect(controller.overview().noGatewayCount == 2, "owner orphan cleanup must survive reload")

        for role in ["owner", "editor", "visitor"] {
            let (site, controller) = fixture()
            site.spaces[0].applyRemoteSpaceMetadata([
                "uuid": "S1", "role": role, "gatewayId": "G1", "gatewayOnline": false
            ])
            controller.refreshList()
            expect(site.spaces[0].gatewayStatus == .offline && site.spaces[0].gatewayLastOnline == nil,
                   "offline status without a timestamp must survive for \(role)")
            site.spaces[0].applyRemoteSpaceMetadata(["uuid": "S1", "role": role])
            controller.refreshList()
            expect(site.spaces[0].gatewayStatus == .notBound && site.spaces[0].relevanceGatewayId == nil,
                   "missing gateway association must not revive cached binding for \(role)")
        }

        for path in 0..<3 {
            let (site, controller) = fixture()
            GatewayDeletionContext.confirmed = ["site:G1"]
            if path == 0 { await site.importReload() }
            if path == 1 { controller.reappear() }
            if path == 2 { controller.refreshList() }
            expect(site.spaces[0].gatewayStatus == .notBound && site.spaces[0].relevanceGatewayId == nil,
                   "confirmed deletion must invalidate stale memory on reload path \(path)")
            expect(site.spaces[1].gatewayStatus == .online, "deletion must not clear another gateway")
        }

        for mutation in 0..<4 {
            let (site, controller) = fixture()
            switch mutation {
            case 0: SpaceData.rows[0].meshNetworkId = "replacement"
            case 1: SpaceData.rows[0].meshUUID = "another-mesh"
            case 2: site.spaces[0].siteId = "another-site"
            default: SpaceData.rows[0].state = .waitDeleted
            }
            controller.refreshList()
            expect(site.spaces[0].gatewayStatus == .notBound,
                   "do not transfer presence across identity/lifecycle change \(mutation)")
        }
        let (membershipSite, membershipController) = fixture()
        SpaceData.rows = [SpaceData("S2"), SpaceData("S3")]
        membershipController.refreshList()
        expect(membershipSite.spaces.map(\.id) == ["S2", "S3"], "list reload must honor additions/removals")
        expect(membershipSite.spaces[0].gatewayStatus == .online && membershipSite.spaces[1].gatewayStatus == .notBound,
               "new Spaces must not inherit an unrelated gateway")
        await testDisconnectAt()
        await testUnassociatedGatewayPresence()
        await testServerActivation()
        print("SiteGatewayMetadataReloadTests passed (\(checks) checks)")
    }

    static func testDisconnectAt() async {
        expect(TimeZone.current.secondsFromGMT() == 0, "test runner must use phone UTC")
        let rawDate = "2026-09-17T06:26:52.401Z"
        let timestamp: Int64 = 1789626412
        func record(_ date: Any = "2026-09-17T06:26:52.401Z", online: Bool = false) -> [String: Any] {
            ["gatewayId": "g1", "macAddress": " G1 ", "gatewayOnline": online, "disconnectAt": date]
        }
        let (site, controller) = fixture()
        let offlinePayload: [String: Any] = [
            "uuid": "S1", "gatewayId": " g1 ", "gatewayOnline": false,
            "gatewayLastupdate": NSNull(), "updateTimestamp": 100
        ]
        site.spaces[0].applyRemoteSpaceMetadata(offlinePayload)
        await site.importReload(gateways: [record(rawDate), [
            "gatewayId": "G2", "gatewayOnline": true, "disconnectAt": rawDate
        ]])
        expect(site.spaces[0].lastUpdate == 100 && site.spaces[0].gatewayLastOnline == timestamp,
               "same-version real payload must import fractional disconnectAt despite null legacy field")
        expect(controller.gateways()[0].lastOnlineTime == "2026-09-17 14:26",
               "real formatter must use Site +08 despite phone UTC and normalized MAC")
        expect(controller.gateways()[1].connectStatus == .online && controller.gateways()[1].lastOnlineTime == nil,
               "online gateway must not display a historical disconnectAt")
        controller.reappear()
        controller.refreshList()
        expect(controller.gateways()[0].lastOnlineTime == "2026-09-17 14:26",
               "disconnectAt must survive return and list notification")
        SiteDeviceOwnershipReconciler.changed = ["S1"]
        await site.importReload(gateways: [record()])
        expect(site.spaces[0].gatewayLastOnline == timestamp,
               "disconnectAt must survive ownership repair reload")
        site.timezone = "Pacific/Honolulu (UTC-10:00)"
        expect(controller.gateways()[0].lastOnlineTime == "2026-09-16 20:26",
               "Site timezone edit must reformat original timestamp across date boundary")
        site.timezone = "Asia/Kathmandu (UTC+05:45)"
        expect(controller.gateways()[0].lastOnlineTime == "2026-09-17 12:11",
               "non-whole-hour Site offsets must be retained")
        site.timezone = nil
        expect(controller.gateways()[0].lastOnlineTime == "2026-09-17 06:26",
               "missing Site timezone must fall back to phone timezone")
        expect(SiteTimeZoneValue.formattedGatewayLastOnline(timestamp: timestamp, storageValue: "invalid",
                   phoneTimeZone: TimeZone(secondsFromGMT: 3600)!) == "2026-09-17 07:26",
               "invalid Site timezone must use supplied phone fallback")
        expect(SiteTimeZoneValue.formattedGatewayLastOnline(timestamp: timestamp,
                   storageValue: "America/Chicago (UTC-06:00)") == "2026-09-17 00:26",
               "Last online must preserve existing fixed-offset Site semantics")

        for value in ["2026-09-17T06:26:52Z", "2026-09-17T14:26:52.401+08:00", "2026-09-17T14:26:52+08:00"] {
            expect(SiteGatewayLastOnlineSnapshot(gateways: [record(value)]).timestamp(for: "G1") == timestamp,
                   "ISO timestamp must support fractional/whole seconds and explicit offset: \(value)")
        }
        for value: Any in [NSNull(), "", "invalid", "2026-09-17T06:26:52", "1970-01-01T00:00:00Z"] {
            expect(SiteGatewayLastOnlineSnapshot(gateways: [record(value)]).timestamp(for: "G1") == nil,
                   "missing/invalid timestamps must not become now or epoch")
        }
        let oldTimestamp: Int64 = 1789609650
        for value: Any in [oldTimestamp, oldTimestamp * 1000] {
            var payload = offlinePayload
            payload["gatewayLastupdate"] = value
            site.spaces[0].applyRemoteSpaceMetadata(payload)
            await site.importReload(gateways: [record(NSNull())])
            expect(site.spaces[0].gatewayLastOnline == oldTimestamp,
                   "legacy seconds/milliseconds must remain a fallback")
            await site.importReload(gateways: [record()])
            expect(site.spaces[0].gatewayLastOnline == timestamp,
                   "valid disconnectAt must take priority over legacy time")
        }
        for value in [Int64(0), -1] {
            var payload = offlinePayload
            payload["gatewayLastupdate"] = value
            site.spaces[0].applyRemoteSpaceMetadata(payload)
            expect(site.spaces[0].gatewayLastOnline == nil, "invalid legacy time must be unknown")
        }
        site.spaces[0].applyRemoteSpaceMetadata(offlinePayload)
        await site.importReload(gateways: [record(online: true)])
        expect(site.spaces[0].gatewayStatus == .offline && site.spaces[0].gatewayLastOnline == nil,
               "conflicting online states must not import stale disconnectAt or override Space state")
        site.spaces[0].applyRemoteSpaceMetadata(["uuid": "S1", "gatewayId": "G1", "gatewayOnline": true])
        await site.importReload(gateways: [record()])
        expect(site.spaces[0].gatewayLastOnline == nil && controller.gateways()[0].lastOnlineTime == nil,
               "returning online must clear previous Last online")
        site.spaces[0].applyRemoteSpaceMetadata(["uuid": "S1", "gatewayId": ""])
        await site.importReload(gateways: [record()])
        expect(site.spaces[0].gatewayLastOnline == nil, "unbound Space must not regain gateway time")
        site.spaces[0].applyRemoteSpaceMetadata(offlinePayload)
        GatewayDeletionContext.confirmed = ["site: g1 "]
        await site.importReload(gateways: [record()])
        expect(site.spaces[0].gatewayLastOnline == nil && site.spaces[0].gatewayStatus == .notBound,
               "confirmed deletion must clear supplemental disconnectAt")
        GatewayDeletionContext.confirmed = []
        for space in site.spaces {
            var payload = offlinePayload
            payload["uuid"] = space.id
            space.applyRemoteSpaceMetadata(payload)
        }
        await site.importReload(gateways: [record()])
        expect(site.spaces.allSatisfy { $0.gatewayLastOnline == timestamp },
               "all visible Spaces bound to the same gateway must receive identical time")
        let mismatched: [String: Any] = ["gatewayId": "G1", "macAddress": "G2", "gatewayOnline": false, "disconnectAt": rawDate]
        for records in [[record(), mismatched], [mismatched, record()], [record(), record(online: true)], [record(online: true), record()]] {
            expect(SiteGatewayLastOnlineSnapshot(gateways: records).timestamp(for: "G1") == nil,
                   "conflicting identities/presence must fail closed regardless of array order")
        }
        expect(SiteGatewayLastOnlineSnapshot(gateways: [record(), record()]).timestamp(for: "G1") == timestamp,
               "identical duplicate observations remain compatible")
        expect(SiteGatewayLastOnlineSnapshot(gateways: nil).timestamp(for: "G1") == nil,
               "partial response without gateways must not invent a timestamp")
        for role in ["owner", "editor", "visitor"] {
            let (roleSite, _) = fixture()
            var payload = offlinePayload
            payload["role"] = role
            roleSite.spaces[0].applyRemoteSpaceMetadata(payload)
            await roleSite.importReload(gateways: [record()])
            expect(roleSite.spaces[0].gatewayLastOnline == timestamp,
                   "visible associated Space receives disconnectAt for \(role)")
        }
    }
    static func testUnassociatedGatewayPresence() async {
        for hasSpaces in [false, true] {
            let (site, controller) = fixture()
            if hasSpaces {
                site.spaces[0].applyRemoteSpaceMetadata(["uuid": "S1", "gatewayId": ""])
            } else {
                SpaceData.rows = []
                site.spaces = []
            }
            let online: [String: Any] = [
                "gatewayId": " g1 ", "macAddress": "G1", "gatewayOnline": true,
                "disconnectAt": "2026-09-17T06:26:52.401Z"
            ]
            await site.importReload(gateways: [online])
            for path in 0..<3 {
                if path == 1 { controller.reappear() }
                if path == 2 { controller.refreshList() }
                let gateway = controller.gateways()[0]
                expect(gateway.connectStatus == .online && gateway.lastOnlineTime == nil,
                       "unassociated gateway must use server online state; hasSpaces=\(hasSpaces), path=\(path)")
            }
            var offline = online
            offline["gatewayOnline"] = false
            await site.importReload(gateways: [offline])
            let gateway = controller.gateways()[0]
            expect(gateway.connectStatus == .offline && gateway.lastOnlineTime == "2026-09-17 14:26",
                   "unassociated gateway must show server offline state and Site-local disconnectAt")
            await site.importReload(gateways: [online])
            expect(controller.gateways()[0].connectStatus == .online && controller.gateways()[0].lastOnlineTime == nil,
                   "returning online must clear disconnectAt without requiring a Space")
            for records: [[String: Any]]? in [nil, [], [["gatewayId": "G1"]], [online, offline]] {
                await site.importReload(gateways: records)
                expect(controller.gateways()[0].connectStatus == .offline && controller.gateways()[0].lastOnlineTime == nil,
                       "missing or conflicting latest presence must not retain stale online state")
            }
            if hasSpaces {
                expect(site.spaces[0].gatewayStatus == .notBound && site.spaces[1].gatewayStatus == .online,
                       "gateway presence must not invent or alter Space associations")
            }
        }
    }

    static func testServerActivation() async {
        let connectedAt = "2026-09-17T05:57:25.751Z"
        let disconnectedAt = "2026-09-17T06:26:52.401Z"
        // Display activation is defined by JSON nullness, not date parsing or
        // the separate Mesh configuration flag.
        let connectionValues: [Any] = [NSNull(), connectedAt, "", 0, false, [], ["unexpected": true]]
        for spaceMode in 0..<3 {
            for legacyActivated in [true, false] {
                for online in [true, false] {
                    for connectedValue in connectionValues {
                        let (site, controller) = fixture()
                        GatewayModel.activationOverrides["G1"] = legacyActivated
                        if spaceMode == 0 {
                            site.spaces = []
                            SpaceData.rows = []
                        } else {
                            site.spaces[0].applyRemoteSpaceMetadata([
                                "uuid": "S1", "gatewayId": spaceMode == 1 ? "" : "G1",
                                "gatewayOnline": online
                            ])
                        }
                        await site.importReload(gateways: [[
                            "gatewayId": " g1 ", "macAddress": "G1",
                            "gatewayOnline": online, "connectAt": connectedValue,
                            "disconnectAt": disconnectedAt
                        ]])
                        let inactive = connectedValue is NSNull
                        let expected: GatewayConnectStatus = inactive ? .inactive : (online ? .online : .offline)
                        for path in 0..<3 {
                            if path == 1 { controller.reappear() }
                            if path == 2 { controller.refreshList() }
                            let gateway = controller.gateways()[0]
                            expect(gateway.connectStatus == expected,
                                   "connectAt must decide activation before online; spaces=\(spaceMode), legacy=\(legacyActivated), online=\(online), inactive=\(inactive), path=\(path)")
                            expect(gateway.activate == legacyActivated,
                                   "display activation must not mutate the Mesh configuration flag")
                            let expectedTime: String? = inactive || online ? nil : "2026-09-17 14:26"
                            expect(gateway.lastOnlineTime == expectedTime,
                                   "only an activated offline gateway should display Last online")
                        }
                    }
                }
            }
        }

        let (site, controller) = fixture()
        site.spaces = []
        SpaceData.rows = []
        func record(_ value: Any, online: Bool = true) -> [String: Any] {
            ["gatewayId": "G1", "connectAt": value, "gatewayOnline": online,
             "disconnectAt": disconnectedAt]
        }
        await site.importReload(gateways: [record(connectedAt)])
        expect(controller.gateways()[0].connectStatus == .online, "first connection activates gateway display")
        await site.importReload(gateways: [record(connectedAt, online: false)])
        expect(controller.gateways()[0].connectStatus == .offline, "disconnect retains activation")
        await site.importReload(gateways: [])
        await site.importReload(gateways: [record(NSNull())])
        expect(controller.gateways()[0].connectStatus == .inactive,
               "a new registration with null connectAt must not inherit the previous activation")
        await site.importReload(gateways: [record(connectedAt)])
        expect(controller.gateways()[0].connectStatus == .online, "new connection replaces inactive snapshot")

        // Missing fields keep legacy behavior; a previous explicit null must
        // not leak into a later snapshot which omits activation metadata.
        for online in [true, false] {
            for legacyActivated in [true, false] {
                GatewayModel.activationOverrides["G1"] = legacyActivated
                await site.importReload(gateways: [record(NSNull())])
                await site.importReload(gateways: [["gatewayId": "G1", "gatewayOnline": online]])
                let expected: GatewayConnectStatus = online ? .online : (legacyActivated ? .offline : .inactive)
                expect(controller.gateways()[0].connectStatus == expected,
                       "absent connectAt must preserve the previous compatibility rule")
            }
        }
        GatewayModel.activationOverrides["G1"] = true
        let inactive = record(NSNull())
        let active = record(connectedAt)
        let mismatched: [String: Any] = ["gatewayId": "G1", "macAddress": "G2", "connectAt": NSNull()]
        for records in [[inactive, active], [active, inactive], [inactive, mismatched], [mismatched, inactive]] {
            await site.importReload(gateways: records)
            expect(controller.gateways()[0].connectStatus == .offline,
                   "ambiguous gateway records must not supply an activation state")
        }
        await site.importReload(gateways: [inactive, inactive])
        expect(controller.gateways()[0].connectStatus == .inactive, "identical null observations remain usable")
    }
}
