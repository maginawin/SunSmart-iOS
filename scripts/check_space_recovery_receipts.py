#!/usr/bin/env python3
"""Run production upload confirmation, unknown-outcome recovery and persistence."""
from pathlib import Path
import subprocess
import tempfile
import re
import sys
import os
import json
sys.dont_write_bytecode = True
from hdb_recovery_test_source import recovery_mesh_source

root = Path(__file__).resolve().parents[1]
def read(path): return (root / path).read_text()
def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]
safety = read('SunSmart/Common/Data/SpaceConfigurationSafety.swift')
methods = section(safety, 'enum SpaceConfigurationSafety {', '    static func configurationAvailable(')
methods = methods.replace('URL(fileURLWithPath: NSHomeDirectory())\n            .appendingPathComponent("Library/Application Support/SpaceConfigurationRecovery")', 'testRoot')
methods = methods.replace('UserDefaults.standard', 'testDefaults')
# SDK Node decoding is already a boundary in this harness. Use the same
# composition object boundary as the fixture probe, retaining the real App
# device factory and mapped SDK Model extension rules.
methods = methods.replace('''                let node = try CloudNodeImport.decode(dictionary)
                node.macAddress = mac
                return try HDBConfigurationStore.deviceConfiguration(node: node, sensorTypes: dictionary["sensorTypes"] as? [String] ?? [])''',
    '                return try RecoveryMeshFactory.resolve(dictionary, mac)')
methods = methods.replace('FileManager.default.moveItem(at: root, to: archive)', 'testMoveItem(at: root, to: archive)')
methods = methods.replace('        try state.write(to: stateURL(space))',
    '        if failStateWrite { throw CocoaError(.fileWriteNoPermission) }\n        try state.write(to: stateURL(space))')
# App database discovery is an integration boundary, not a substitute state machine.
start = methods.index('    static func resumeLocalRemovals()')
end = methods.index('    static func activateImport(', start)
methods = methods[:start] + methods[end:]
methods = methods[:methods.index('    static func syncReadRequest(')] if '    static func syncReadRequest(' in methods else methods
methods += section(safety, '    static func needsUpgradeBaseline(', '    /// Preserve both side stores')
methods += section(safety, '    static func beginImport(', '    @MainActor\n    static func prepareUpload(')
methods += section(safety, '    @MainActor\n    static func prepareUpload(', '    /// Called only after the user explicitly chooses')
methods += section(safety, '    /// Called only after the user explicitly chooses', '    struct ReferenceRepairReview')
methods = methods.replace('UserDefaults.standard', 'testDefaults')
methods += section(safety, '    private static func saveRecoveryPayload(', '    @MainActor\n    static func applyReferenceRepair(')
methods += """
    static let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    static let suite = "SpaceRecovery-" + UUID().uuidString
    static let testDefaults = UserDefaults(suiteName: suite)!
    static var failArchiveMove = false
    static var failStateWrite = false
    static var failMembershipWrite = false
    static func testMoveItem(at source: URL, to destination: URL) throws {
        if failArchiveMove { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.moveItem(at: source, to: destination)
    }
    static var failCheckpoint = false
    static func checkpoint(_ space: SpaceData, refresh: Bool = false) -> Bool { !failCheckpoint }
    enum SafetyError: Error { case invalidCheckpoint, persistenceFailed }
    static func testDirectory(_ space: SpaceData) throws -> URL { try directory(space) }
    static func testSaveState(_ state: SpaceRecoveryState, space: SpaceData) throws { try saveState(state, space: space) }
    static func testMigrated(_ space: SpaceData) -> Bool { testDefaults.bool(forKey: "spaceConfigurationMigrated." + key(space)) }
}
"""
imports = read('SunSmart/Common/Data/ImportData.swift')
metadata = section(imports,
    '    func applyRemoteSpaceMetadata(', '    /// 更新空间内基本数据')
test = read('Tests/Group/SpaceRecoveryReceiptTests.swift').replace('// METADATA_METHOD', metadata)
# Share the SDK Group decoder and optional Node field decoder with the import
# fixture. Mesh object loading and scheduler restoration remain explicit doubles.
sdk = root / '.local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision'
codecs = section(read('Tests/Group/CloudNodeImportTests.swift'), '// Only optional identifier', 'enum Outcome:')
codecs = codecs.replace('// SDK_OPTIONAL_FIELDS', section((sdk / 'Mesh Model/Node.swift').read_text(),
    '        if let companyIdentifierAsString = try container.decodeIfPresent',
    '        self.features = try container.decodeIfPresent'))
codecs = codecs.replace('// SDK_GROUP_DECODER', section((sdk / 'Mesh Model/Group.swift').read_text(),
    '    private enum CodingKeys:', '\n}\n\nextension Group:'))
test += '\n' + codecs + '\n' + section((sdk / 'Type Extensions/Int+Hex.swift').read_text(),
    'internal extension UInt16 {', 'internal extension Int16 {')
test += '\n' + section(imports, 'enum CloudNodeImport {', '\n/// Stage timings')
# Execute the production update prefix through both async freshness guards,
# followed by its actual legacy Zone gate (without the unrelated Mesh importer).
# Mesh preparation/export and App database reads are controlled test boundaries.
preparation = section(imports, '    func update(\n        spaceJsonData:',
    '        return await withCheckedContinuation { continuation in')
zone_gate = section(imports, '            if !resumingImport, SpaceConfigurationIntegrityPolicy.legacySpaceZoneDeletionNeedsReview(',
                    '            let proximityImportDisposition =')
zone_gate = zone_gate.replace('continuation.resume(returning: .skipped)\n                return', 'return .skipped')
test = test.replace('// IMPORT_PREPARATION_METHOD', '@MainActor\n' + preparation
    + '        _ = proximityPreflight\n        _ = timedReferencesChanged\n' + zone_gate + '        return .prepared\n    }\n')
test += '\n' + section(imports, 'final class SiteImportTrace', '\nstruct SpaceImportOutcome')
test += '\n' + read('Tests/Group/SpaceImportPreparationTests.swift')
test += '\n' + read('Tests/Group/OlderCloudBaselineTests.swift')
test += '\n' + read('Tests/Group/SpaceDefaultRecoveryReceiptTests.swift')
test += '\n' + recovery_mesh_source(root)
membership = section(read('SunSmart/Common/Data/SpaceMembershipCoordinator.swift'),
    'enum SpaceMembershipCoordinator {', '    static var savedCopiesDirectory:') + '}\n'
membership = membership.replace('URL(fileURLWithPath: NSHomeDirectory())\n        .appendingPathComponent("Library/Application Support/SpaceMembership")',
    'SpaceConfigurationSafety.testRoot.appendingPathComponent("membership")')
test += '\n' + membership

cloud = read('SunSmart/Common/Cloud/CloudSynchronizationManager.swift')
site_confirmation = section(cloud, '    /// Persist only the Site version', '    /// 开始同步到服务器')
site_confirmation = site_confirmation.replace('private func confirmSiteUpload', 'func confirmSiteUpload')
api_properties = section(cloud, 'private extension NetowrkReqeustApi {', '\n#if DEBUG')
api_properties = api_properties.replace('private extension', 'extension')
test += '\n' + read('Tests/Group/CloudUploadConfirmationTests.swift').replace(
    '// SITE_CONFIRMATION_METHOD', site_confirmation) + '\n' + api_properties
# Ensure a successful upload reads the submitted Space back before clearing its receipt.
after_upload = section(cloud, '            let requestResult = await NetworkRequest.shared.request(api)',
                       '            let completionResult = result')
assert 'await SpaceConfigurationSafety.resumeUpload(space)' in after_upload
share = read('SunSmart/Main/Share/Controller/ShareAuthorityViewController.swift')
assert '.siteUpload(siteData:' not in share
assert '.syncSite(site: site, syncSpaces: uploadSpaces)' in share

network = read('SunSmart/Common/Network/NetworkRequest.swift')
test = test.replace('// NETWORK_ERROR_TYPE', section(network, 'public enum NetworkApiError:', '/// Encoding is selected'))
with tempfile.TemporaryDirectory(prefix='space-receipt-tests-') as temp:
    temp = Path(temp)
    harness = temp / 'Harness.swift'
    harness.write_text(test + '\n' + methods)
    membership_store = temp / 'SpaceMembershipStore.swift'
    membership_store.write_text(read('SunSmart/Common/Data/SpaceMembershipStore.swift').replace(
        '    func write(_ record: SpaceMembershipRecord) throws {',
        '    func write(_ record: SpaceMembershipRecord) throws {\n'
        '        if SpaceConfigurationSafety.failMembershipWrite { throw CocoaError(.fileWriteNoPermission) }'))
    binary = temp / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library', '-D', 'DEBUG',
        str(root / 'Pods/SwiftyJSON/Source/SwiftyJSON/SwiftyJSON.swift'),
        str(root / 'SunSmart/Common/Data/AppPerformance.swift'),
        str(root / 'SunSmart/Common/Data/SpaceProtectionReadSnapshot.swift'),
        str(root / 'SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift'),
        str(membership_store),
        str(root / 'SunSmart/Common/Data/SiteGatewayAssociationConsistencyPolicy.swift'),
        str(root / 'SunSmart/Common/Data/SiteTimeZoneValue.swift'),
        str(root / 'SunSmart/Main/Site/Model/SitePropsEditPolicy.swift'),
        str(root / 'SunSmart/Common/Data/HDBConfiguration.swift'), str(root / 'SunSmart/Common/Data/HDBLightingZonePolicy.swift'), str(root / 'SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift'),
        str(root / 'SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift'),
        str(root / 'SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift'),
        str(root / 'SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift'),
        str(root / 'SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift'),
        str(harness), '-o', str(binary)], check=True)
    arguments = sys.argv[1:]
    environment = os.environ.copy()
    if "--local-membership-sample" in arguments:
        index = arguments.index("--local-membership-sample")
        paths = arguments[index + 1:index + 4]
        if len(paths) != 3 or not all(Path(path).is_file() for path in paths):
            raise SystemExit("--local-membership-sample requires old cloud, current cloud, and inspection JSON files")
        environment["SUNSMART_LOCAL_MEMBERSHIP_SAMPLES"] = json.dumps(paths)
        arguments = arguments[:index] + arguments[index + 4:]
    result = subprocess.run([str(binary), *arguments], capture_output=True, text=True, env=environment)
    if result.returncode:
        print('\n'.join(result.stdout.splitlines()[-50:]) + '\n' + result.stderr)
        match = re.search(r'Harness.swift:(\d+):', result.stderr)
        if match:
            line = int(match.group(1))
            lines = harness.read_text().splitlines()
            for index in range(max(0, line - 4), min(len(lines), line + 3)):
                print(f'{index + 1}: {lines[index]}')
        raise SystemExit(result.returncode)
    print('\n'.join(line for line in result.stdout.splitlines() if line.startswith('PASS:')))
