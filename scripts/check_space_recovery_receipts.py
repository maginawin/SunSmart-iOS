#!/usr/bin/env python3
"""Run production upload confirmation, unknown-outcome recovery and persistence."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
def read(path): return (root / path).read_text()
def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]
safety = read('SunSmart/Common/Data/SpaceConfigurationSafety.swift')
methods = section(safety, 'enum SpaceConfigurationSafety {', '    static func configurationAvailable(')
methods = methods.replace('URL(fileURLWithPath: NSHomeDirectory())\n            .appendingPathComponent("Library/Application Support/SpaceConfigurationRecovery")', 'testRoot')
methods = methods.replace('UserDefaults.standard', 'testDefaults')
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
methods = methods.replace('UserDefaults.standard', 'testDefaults')
methods += """
    static let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    static let suite = "SpaceRecovery-" + UUID().uuidString
    static let testDefaults = UserDefaults(suiteName: suite)!
    static var failArchiveMove = false
    static var failStateWrite = false
    static func testMoveItem(at source: URL, to destination: URL) throws {
        if failArchiveMove { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.moveItem(at: source, to: destination)
    }
    static func checkpoint(_ space: SpaceData, refresh: Bool = false) -> Bool { true }
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
# Execute the production update prefix through both async freshness guards.
# Mesh preparation/export and App database reads are controlled test boundaries.
preparation = section(imports, '    func update(\n        spaceJsonData:',
    '        return await withCheckedContinuation { continuation in')
test = test.replace('// IMPORT_PREPARATION_METHOD', '@MainActor\n' + preparation
    + '        _ = proximityPreflight\n        return .prepared\n    }\n')
test += '\n' + section(imports, 'final class SiteImportTrace', '\nstruct SpaceImportOutcome')
test += '\n' + read('Tests/Group/SpaceImportPreparationTests.swift')
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
# Ensure every normal success entry uses the tested local-only completion method.
after_upload = section(cloud, '            let requestResult = await NetworkRequest.shared.request(api)',
                       '            let completionResult = result')
assert 'finishAcceptedSubmission(context, space: space)' in after_upload
assert 'resumeUpload(' not in after_upload and '.spaceInfo(' not in after_upload and '.siteInfo(' not in after_upload
share = read('SunSmart/Main/Share/Controller/ShareAuthorityViewController.swift')
assert '.siteUpload(siteData:' not in share
assert '.syncSite(site: site, syncSpaces: uploadSpaces)' in share

network = read('SunSmart/Common/Network/NetworkRequest.swift')
test = test.replace('// NETWORK_ERROR_TYPE', section(network, 'public enum NetworkApiError:', '/// Encoding is selected'))
with tempfile.TemporaryDirectory(prefix='space-receipt-tests-') as temp:
    temp = Path(temp)
    harness = temp / 'Harness.swift'
    harness.write_text(test + '\n' + methods)
    binary = temp / 'Tests'
    subprocess.run(['swiftc', '-parse-as-library',
        str(root / 'Pods/SwiftyJSON/Source/SwiftyJSON/SwiftyJSON.swift'),
        str(root / 'SunSmart/Common/Data/AppPerformance.swift'),
        str(root / 'SunSmart/Common/Data/SpaceProtectionReadSnapshot.swift'),
        str(root / 'SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift'),
        str(root / 'SunSmart/Common/Data/SpaceMembershipStore.swift'),
        str(root / 'SunSmart/Common/Data/SiteTimeZoneValue.swift'),
        str(root / 'SunSmart/Main/Site/Model/SitePropsEditPolicy.swift'),
        str(root / 'SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift'),
        str(root / 'SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift'),
        str(root / 'SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift'),
        str(root / 'SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift'),
        str(harness), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
