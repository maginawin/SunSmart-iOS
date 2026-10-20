#!/usr/bin/env python3
"""Run production Site creation/save/load/copy and extension storage on temporary SQLite.
Only unrelated model metadata, UI and SDK network allocation are test boundaries.
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
        "func cloneData() -> SiteData", "static func getNextCloneSiteName("]]
    methods += [block(model, marker) for marker in ["var isHdbSite: Bool", "func loadIsHdbSite()", "func copy() -> Self {"]]
    methods += [block(mesh, "static func add(name: String")]
    production = "import Foundation\nimport SQLite\n" + block(mesh, "public enum DataError:")
    production += "\nextension SiteData {\nprivate static let sitesTableName = \"sites\"\nprivate static let sitesTable = Table(sitesTableName)\n"
    production += "\n".join(methods) + "\n}\n"
    (output / "Production.swift").write_text(production)
    store = (output / "SiteExtensionStore.swift")
    store.write_text((ROOT / "SunSmart/Common/Data/SiteExtensionStore.swift").read_text().replace("import NordicSigMeshSDK", ""))
    subprocess.run(["swiftc", "-parse-as-library", "-I", directory, "-L", directory, "-lSQLite",
                    str(output / "Production.swift"),
                    str(ROOT / "SunSmart/Common/Data/SiteExtensionData.swift"),
                    str(ROOT / "SunSmart/Common/Data/SiteExtensionState.swift"),
                    str(ROOT / "SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift"),
                    str(store),
                    str(ROOT / "Tests/Site/SiteHDBPersistenceTests.swift"),
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
