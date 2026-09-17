import Foundation
import SQLite3

@main
enum SiteTriggerZoneCandidateTests {
    typealias Candidates = SiteTriggerZoneCandidates
    typealias Reader = SiteTriggerZoneCandidateReader

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appPath = directory.appendingPathComponent("app.sqlite").path
        let meshPath = directory.appendingPathComponent("mesh.sqlite").path
        let source = Reader.Source(appPath: appPath, meshPath: meshPath, eligibleProfileTypes: [7, 8], excludedGroupAddresses: [0xFEFE, 0xFEFD, 0xFEFF])
        let nodeA = "11111111-1111-4111-8111-111111111111"
        let nodeB = "22222222-2222-4222-8222-222222222222"
        let provisioner = "33333333-3333-4333-8333-333333333333"
        let subscriptions = "[{\"models\":[{\"modelId\":\"1000\",\"subscribe\":[\"C001\"]}]},{\"models\":[{\"modelId\":\"0A780001\",\"subscribe\":[]}]}]"
        try execute(appPath, """
        CREATE TABLE spaces (uuid TEXT, siteUUID TEXT, subNetworkKey TEXT, permission INTEGER, state INTEGER, requiresPasswordVerification INTEGER);
        CREATE TABLE groupInfos (meshUUID TEXT, subNetworkKey TEXT, groupAddress INTEGER, profileId TEXT);
        CREATE TABLE profiles (uuid TEXT, meshUUID TEXT, subNetworkKey TEXT, type INTEGER);
        INSERT INTO spaces VALUES ('A','site','netA',1,1,0), ('B','site','netB',2,1,0), ('C','site','netC',1,1,0), ('V','site','netV',3,1,0);
        INSERT INTO groupInfos VALUES ('mesh','netA',49153,'manual'),('mesh','netB',49153,'prox'),('mesh','netC',49153,'photo');
        INSERT INTO profiles VALUES ('manual','mesh','netA',6),('prox','mesh','netB',7),('photo','mesh','netC',8);
        """
        )
        try execute(meshPath, """
        CREATE TABLE meshNetwork (meshUUID TEXT, provisioners BLOB);
        CREATE TABLE groups (id INTEGER PRIMARY KEY, meshUUID TEXT, subnetworkId TEXT, groupAddress INTEGER, isVirtual INTEGER);
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, meshUUID TEXT, subnetworkId TEXT, UUID TEXT, name TEXT, unicastAddress INTEGER, elements BLOB, configComplete INTEGER);
        INSERT INTO meshNetwork VALUES ('mesh',CAST('[{"UUID":"\(provisioner)"}]' AS BLOB));
        INSERT INTO groups VALUES (1,'mesh','netA',49153,0),(2,'mesh','netB',49153,0),(3,'mesh','netC',49153,0);
        INSERT INTO nodes VALUES (1,'mesh','netA','\(nodeA)','Manual group device',1,CAST('\(subscriptions)' AS BLOB),0),
          (2,'mesh','netB','\(nodeB)','Proximity device',1,CAST('\(subscriptions)' AS BLOB),0),
          (3,'mesh','netB','\(provisioner)','Provisioner',100,CAST('\(subscriptions)' AS BLOB),0),
          (4,'mesh','netB','44444444-4444-4444-8444-444444444444','Excluded config',101,CAST('\(subscriptions)' AS BLOB),1);
        """
        )
        let requests = [request("A"), request("B"), request("C"), request("V", restricted: true)]
        let appBefore = try Data(contentsOf: URL(fileURLWithPath: appPath))
        let meshBefore = try Data(contentsOf: URL(fileURLWithPath: meshPath))
        let spaces = Reader.load(requests, source: source)
        check(spaces.map(\.availability) == [.noGroups, .ready, .ready, .restricted], "Profile eligibility and effective permissions")
        check(spaces.allSatisfy { !$0.devicesLoaded && $0.devices.isEmpty }, "Group eligibility must not eagerly enumerate devices")
        var selection = Candidates.Selection()
        selection.reconcile(spaces)
        check(selection.spaceID == "B", "Default must skip the first ineligible Space")
        selection.select("V", in: spaces)
        check(selection.spaceID == "B", "Restricted Space cannot become selected")
        selection.select("C", in: spaces)
        selection.reconcile(Array(spaces.reversed()))
        check(selection.spaceID == "C", "Selection follows identity after reordering")
        let loadedC = Reader.load(requests, source: source, devicesFor: "C")
        check(loadedC[2].isSelectable && loadedC[2].devicesLoaded && loadedC[2].devices.isEmpty, "An empty eligible Group is still a selectable Space")
        let loadedB = Reader.load(requests, source: source, devicesFor: "B")
        check(loadedB[1].devices.count == 1 && loadedB[1].devices[0].identity.deviceID == nodeB, "Same Group/node address in another Space cannot leak; provisioner/config nodes excluded")
        check(try Data(contentsOf: URL(fileURLWithPath: appPath)) == appBefore, "Candidate read must not write App data")
        check(try Data(contentsOf: URL(fileURLWithPath: meshPath)) == meshBefore, "Candidate read must not repair or write Mesh data")

        let zone = UUID(), otherZone = UUID()
        let device = loadedB[1].devices[0]
        check(device.deviceAddress == 2 && device.address == 1,
              "Space Trigger Zone uses the Vendor Model element, not the trigger source or primary address")
        check(Candidates.device(for: 1, in: loadedB[1]) == device, "Trigger address resolves only in the loaded Space")
        check(Candidates.device(for: 1, in: loadedC[2]) == nil, "Same address in another Space cannot be borrowed")
        check(Candidates.device(for: 2, in: loadedB[1]) == device, "Sensor element address resolves to its stable node")
        check(Candidates.device(for: 3, in: loadedB[1]) == nil, "Unknown element address is ignored")
        let member = SiteTriggerZoneMember(identity: .init(spaceID: "B", nodeUUID: UUID(uuidString: nodeB)!),
                                           groupAddress: 0xC001, primaryAddress: 1, deviceAddress: 2)
        check(Reader.validates([member], requests: requests, source: source),
              "Save re-reads the same eligible Group, node and trigger element")
        let staleMember = SiteTriggerZoneMember(identity: member.identity,
                                                groupAddress: 0xC002, primaryAddress: 1, deviceAddress: 2)
        check(!Reader.validates([staleMember], requests: requests, source: source),
              "A stale Group snapshot cannot be uploaded")
        let wrongElement = SiteTriggerZoneMember(identity: member.identity,
                                                 groupAddress: 0xC001, primaryAddress: 1, deviceAddress: 1)
        check(!Reader.validates([wrongElement], requests: requests, source: source),
              "A primary-address guess cannot replace the Vendor Model element")
        var candidateSpace = loadedB[1]
        let fresh = Candidates.Device(identity: .init(siteID: "site", spaceID: "B", deviceID: nodeA), name: "New", address: 2, groupAddress: 0xC001)
        candidateSpace.devices = [device, fresh, fresh]
        let memberships = [Candidates.Membership(zoneID: otherZone, devices: [device.identity])]
        check(Candidates.filteredDevices(in: candidateSpace, zoneID: zone, memberships: memberships, includeAdded: false) == [fresh], "Ignore covers all Site Zones and deduplicates candidates")
        check(Candidates.filteredDevices(in: candidateSpace, zoneID: zone, memberships: memberships, includeAdded: true) == [device, fresh], "Include added also retains new devices")
        let current = memberships + [.init(zoneID: zone, devices: [device.identity])]
        check(Candidates.filteredDevices(in: candidateSpace, zoneID: zone, memberships: current, includeAdded: true) == [fresh], "Current Zone members never repeat")
        let foreign = Candidates.Identity(siteID: "other-site", spaceID: "B", deviceID: nodeB)
        check(Candidates.filteredDevices(in: candidateSpace, zoneID: zone, memberships: [.init(zoneID: otherZone, devices: [foreign])], includeAdded: false).count == 2, "Membership identity includes Site")
        check(Candidates.filteredDevices(in: candidateSpace, zoneID: nil, memberships: [], includeAdded: true).isEmpty, "No selected Zone has no candidates")
        check(Candidates.filteredDevices(in: loadedB[3], zoneID: zone, memberships: [], includeAdded: true).isEmpty, "Role gating precedes device filtering")
        selection.reconcile([spaces[0], spaces[3]])
        check(selection.spaceID == nil, "No eligible option must produce nil, not index zero")
        check(Candidates.placeholderKey(for: []) == "site_zone_no_spaces", "No spaces")
        check(Candidates.placeholderKey(for: [spaces[0]]) == "site_zone_no_eligible_spaces", "No eligible groups")
        check(Candidates.placeholderKey(for: [spaces[3]]) == "site_zone_no_editable_spaces", "No editable spaces")

        var loadState = Candidates.LoadState()
        var failed = spaces
        failed[1].availability = .unavailable
        selection.reconcile(loadState.accept(failed, devicesFor: "B"))
        check(selection.spaceID == "C", "A failed device projection advances to the next eligible Space")
        failed = spaces
        failed[2].availability = .unavailable
        selection.reconcile(loadState.accept(failed, devicesFor: "C"))
        check(selection.spaceID == nil, "Two corrupt Spaces cannot repeatedly reselect one another")
        loadState.reset()
        selection.reconcile(loadState.accept(spaces, devicesFor: nil))
        check(selection.spaceID == "B", "Explicit refresh permits recovery")

        // Failures must remain distinguishable from valid empty snapshots.
        try execute(appPath, "UPDATE spaces SET requiresPasswordVerification = 1 WHERE uuid = 'B'")
        check(Reader.load(requests, source: source, devicesFor: "B")[1].availability == .restricted, "Recheck authorization before reading device data")
        check(!Reader.validates([member], requests: requests, source: source),
              "Changed local authorization blocks Save")
        try execute(appPath, "UPDATE spaces SET requiresPasswordVerification = 0 WHERE uuid = 'B'; DELETE FROM profiles WHERE uuid = 'prox'")
        check(Reader.load(requests, source: source)[1].availability == .unavailable, "Missing Profile is not no eligible groups")
        check(!Reader.validates([member], requests: requests, source: source),
              "Removed Profile blocks Save")
        try execute(appPath, "INSERT INTO profiles VALUES ('prox','mesh','netB',7)")
        try execute(meshPath, "UPDATE nodes SET elements = CAST('invalid' AS BLOB) WHERE id = 2")
        check(Reader.load(requests, source: source, devicesFor: "B")[1].availability == .unavailable, "Corrupt membership is not an empty Space")
        try execute(meshPath, "UPDATE nodes SET elements = CAST('\(subscriptions)' AS BLOB), UUID = 'invalid' WHERE id = 2")
        check(Reader.load(requests, source: source, devicesFor: "B")[1].availability == .unavailable, "Invalid stable identity cannot generate a random replacement")
        check(Reader.load([request("B", expected: 2)], source: source)[0].availability == .unavailable, "Partial local Group data is not complete eligibility")
        let absentPath = directory.appendingPathComponent("absent.sqlite").path
        let absentSource = Reader.Source(appPath: absentPath, meshPath: absentPath, eligibleProfileTypes: [7, 8], excludedGroupAddresses: [])
        check(Reader.load(requests, source: absentSource)[0].availability == .unavailable, "Failed read must have an explicit state")
        check(!FileManager.default.fileExists(atPath: absentPath), "Read-only open must not create a database")
        check(Reader.load([request("V", restricted: true)], source: absentSource)[0].availability == .restricted, "Restricted summaries do not require reading Mesh storage")
        print("PASS: Site candidates, scoped read-only databases, permissions, Profile eligibility, stable identity, selection, filtering and failure states")
    }

    private static func request(_ id: String, restricted: Bool = false, expected: Int = 1) -> Reader.Request {
        .init(siteID: "site", meshUUID: "mesh", subnetID: "net" + id,
              space: .init(id: id, name: id, accessLabelKey: restricted ? "visitor" : nil,
                           availability: restricted ? .restricted : .loading), expectedGroupCount: expected)
    }

    private static func execute(_ path: String, _ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw Reader.ReadError.database }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }

    private static func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
}
