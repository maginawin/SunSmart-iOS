#!/usr/bin/env python3
"""Run production Site creation/save/load/copy and extension storage on temporary SQLite.
Also run production Site import metadata and upload receipts across separate instances.
Mesh/Space preparation, UI and network transport are test boundaries.
No account database, Mesh device or server is accessed.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SDK = Path(sys.argv[1]).resolve()


def block(text, marker):
    start = text.index(marker)
    end = text.index("{", start) + 1
    depth = 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


database = (ROOT / "SunSmart/Common/Data/Database.swift").read_text()
model = (ROOT / "SunSmart/Common/Data/SiteData.swift").read_text()
mesh = (ROOT / "SunSmart/Common/Data/MeshNetwork+SunSmart.swift").read_text()
imports = (ROOT / "SunSmart/Common/Data/ImportData.swift").read_text()
cloud = (ROOT / "SunSmart/Common/Cloud/CloudSynchronizationManager.swift").read_text()
integrity = (ROOT / "SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift").read_text()
with tempfile.TemporaryDirectory(prefix="site-hdb-persistence-") as directory:
    output = Path(directory)
    sqlite = sorted((SDK / "Sources/SQLite").rglob("*.swift"))
    assert sqlite, "Pass the local SDK checkout containing Sources/SQLite"
    subprocess.run(["swiftc", "-emit-module", "-emit-library", "-module-name", "SQLite",
                    *map(str, sqlite), "-o", str(output / "libSQLite.dylib"),
                    "-emit-module-path", str(output / "SQLite.swiftmodule")], check=True)
    methods = [block(database, marker) for marker in [
        "struct ExpressionKey {", "static func initDatabase()", "static func loadAll()",
        "static func load(siteId: String)", "@discardableResult func save(allData:",
        "@discardableResult func replaceTransferCredentials(",
        "func cloneData() -> SiteData", "static func getNextCloneSiteName("]]
    methods += [block(model, marker) for marker in ["var isHdbSite: Bool", "func loadIsHdbSite()", "func copy() -> Self {", "var standardProperties: SiteStandardProperties {"]]
    methods += [block(mesh, "static func add(name: String")]
    production = "import Foundation\nimport SQLite\n" + block(mesh, "public enum DataError:")
    transfer = (ROOT / "SunSmart/Main/Share/Model/SiteTransferCoordinator.swift").read_text()
    production += "\n" + block(transfer, "struct SiteTransferCredentials:")
    production += "\nextension SiteData {\nprivate static let sitesTableName = \"sites\"\nprivate static let sitesTable = Table(sitesTableName)\n"
    production += "\n".join(methods) + "\n}\n"
    production += '\nextension SunSmartDataManager {\n' + block(database, 'func configurationTransaction(') + '\n}\n'
    def section(source, start, end):
        begin = source.index(start)
        return source[begin:source.index(end, begin)]

    site_import = imports[imports.index('    func update(siteJsonData:'):]
    body = section(site_import, '        guard SpaceMembershipCoordinator.accepts', '        let gatewayImportScope')
    body += section(site_import, '        let json = JSON(siteJsonData)', '        // Process extension fields')
    body += section(site_import, '        if lastUpdate > self.lastUpdate || initialize {', '            // 转让site id') + '        }\n'
    body += '        preparedSiteTimestamp = self.lastUpdate\n        let meshNetwork: Bool? = true\n'
    body += section(site_import, '        guard meshNetwork != nil else', '        GatewayOrphanGuard.endImport')
    production += '\nextension SiteData {\nfunc importFixture(siteJsonData: [String: Any], initialize: Bool = false) -> Bool {\n' + body + 'return true\n}\n}\n'
    production += '\nextension SiteSyncReceiptFixture {\n' + block(cloud, 'private func confirmSiteUpload(').replace('private func', '@MainActor func', 1) + '\n}\n'
    production += '\nextension NetowrkReqeustApi {\n' + block(cloud, 'var configurationSiteTimestamp:') + '\n' + block(cloud, 'var initialSiteTimeZoneSubmission:') + '\n}\n'
    production += '\nenum SpaceConfigurationIntegrityPolicy {\n' + block(integrity, 'static func confirmedTimestamp(') + '\nstatic func integer(_ value: Any?) -> Int64? { (value as? NSNumber)?.int64Value }\n}\n'
    (output / "Production.swift").write_text(production)
    store = (output / "SiteExtensionStore.swift")
    store.write_text((ROOT / "SunSmart/Common/Data/SiteExtensionStore.swift").read_text().replace("import NordicSigMeshSDK", ""))
    subprocess.run(["swiftc", "-parse-as-library", "-I", directory, "-L", directory, "-lSQLite",
                    str(output / "Production.swift"),
                    str(ROOT / "SunSmart/Common/Data/SiteExtensionData.swift"),
                    str(ROOT / "SunSmart/Common/Data/SiteTimeZoneValue.swift"),
                    str(ROOT / "SunSmart/Main/Site/Model/SitePropsEditPolicy.swift"),
                    str(ROOT / "SunSmart/Main/Site/Model/SitePropsAPIClient.swift"),
                    str(ROOT / "SunSmart/Main/Site/Model/SitePropsEditCoordinator.swift"),
                    str(ROOT / "Pods/SwiftyJSON/Source/SwiftyJSON/SwiftyJSON.swift"),
                    str(ROOT / "SunSmart/Common/Data/SiteExtensionState.swift"),
                    str(ROOT / "SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift"),
                    str(store),
                    str(ROOT / "Tests/Site/SiteHDBPersistenceTests.swift"),
                    str(ROOT / "Tests/Site/SiteStandardPropsPersistenceTests.swift"),
                    "-o", str(output / "tests")], check=True)
    subprocess.run([str(output / "tests"), str(output / "site.sqlite")], check=True)

    # The same App database also owns the compact initialization receipt.
    node_model = (ROOT / "SunSmart/Common/Data/Node+SyncData.swift").read_text()
    node_source = "import Foundation\nimport SQLite\nfinal class Node {\n" + block(node_model, "class PreConfiguration: Codable {") + "\n}\n"
    node_source += block(database, "extension Node.PreConfiguration {")
    (output / "NodePersistence.swift").write_text(node_source)
    subprocess.run(["swiftc", "-parse-as-library", "-I", directory, "-L", directory, "-lSQLite",
                    str(output / "NodePersistence.swift"),
                    str(ROOT / "Tests/HDB/HDBInitializationPersistenceTests.swift"),
                    "-o", str(output / "node-tests")], check=True)
    subprocess.run([str(output / "node-tests"), str(output / "node.sqlite")], check=True)
