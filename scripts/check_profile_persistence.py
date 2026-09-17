#!/usr/bin/env python3
"""Run production Profile/GroupInfo persistence against temporary real SQLite.

Only UIKit presentation and unrelated Mesh/template services are replaced.
Model defaults, copying, Codable, SQL schema/save/load/transaction and Profile
cloud mapping are extracted verbatim (the import result assignment becomes return).
No device, account database or network is accessed.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SDK = Path(sys.argv[1]).resolve()


def block(source, marker):
    start = source.index(marker)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def read(path):
    return (ROOT / path).read_text()


with tempfile.TemporaryDirectory(prefix="profile-persistence-") as folder:
    output = Path(folder)
    sqlite = sorted((SDK / "Sources/SQLite").rglob("*.swift"))
    assert sqlite, "Pass the resolved SDK checkout containing Sources/SQLite"
    subprocess.run(["swiftc", "-emit-module", "-emit-library", "-module-name", "SQLite",
                    *map(str, sqlite), "-o", str(output / "libSQLite.dylib"),
                    "-emit-module-path", str(output / "SQLite.swiftmodule")], check=True)

    model = block(read("SunSmart/Main/Profile/Model/Profile.swift"), "class Profile: Copyable")
    model = model.replace(block(model, "var instruction:"), "")
    database = read("SunSmart/Common/Data/Database.swift")
    header = database[:database.index("class SunSmartDataManager")].replace("import NordicSigMeshSDK", "")
    # Profile SQL tests do not use cross-Space identity queries or Mesh snapshot caching.
    for marker in ["enum SiteDeviceOwnershipStore", "struct ConfigurationSnapshotRevision", "final class ConfigurationMeshReadSnapshot"]:
        header = header.replace(block(header, marker), "")
    manager = """
class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Connection?
""" + block(database, "@discardableResult\n    func configurationTransaction(") + "\n}\n"
    group_info = block(read("SunSmart/Common/Data/MeshNetwork+SunSmart.swift"), "class GroupInfo {")
    compatibility = block(read("SunSmart/Common/Data/SpaceConfigurationSafety.swift"), "enum ProfileStorageCompatibility")
    exported = read("SunSmart/Common/Data/ExportData.swift")
    export_start = exported.index("let profile = group.info.profile", exported.index("var groupDicts:"))
    export_end = exported.index('groupDict.updateValue(profileDict, forKey: "profile")', export_start)
    export = "func exportProfile(_ group: HarnessGroup) -> [String: Any] {\n" + exported[export_start:export_end] + "\nreturn profileDict\n}\n"
    imported = read("SunSmart/Common/Data/ImportData.swift")
    parse = block(imported, 'if let id = profileJson["id"].string, let type = Profile.ProfileType')
    parse = parse.replace("group.info.profile = profile", "return profile")
    import_profile = 'func importProfile(_ profileDict: [String: Any]) -> Profile? {\nlet profileJson = JSON(profileDict)\n' + parse + '\nreturn nil\n}\n'
    (output / "Production.swift").write_text("\n".join([header, model, manager, group_info,
        block(database, "extension GroupInfo {"), block(database, "extension Profile {"),
        compatibility, export, import_profile]))
    subprocess.run(["swiftc", "-D", "DEBUG", "-parse-as-library", "-I", folder,
                    "-L", folder, "-lSQLite", str(output / "Production.swift"),
                    str(ROOT / "Pods/SwiftyJSON/Source/SwiftyJSON/SwiftyJSON.swift"),
                    str(ROOT / "SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift"),
                    str(ROOT / "Tests/Group/ProfilePersistenceTests.swift"),
                    "-o", str(output / "tests")], check=True)
    result = subprocess.run([str(output / "tests")], capture_output=True, text=True)
    # Repeated boundary rejections are expected; show each diagnostic once.
    seen = set()
    for line in result.stdout.splitlines():
        if line not in seen:
            print(line)
            seen.add(line)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    result.check_returncode()
