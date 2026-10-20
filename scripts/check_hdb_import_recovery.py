#!/usr/bin/env python3
"""Execute the production import preparation and Space.save guards.

Only storage/journal and unrelated import policies are doubled. This is not a
SQLite transaction or SDK/cloud integration test.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def section(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


database = (ROOT / "SunSmart/Common/Data/Database.swift").read_text()
imports = (ROOT / "SunSmart/Common/Data/ImportData.swift").read_text()
save = section(database, "    @discardableResult func save(importingConfiguration:",
               "        _ = Keychain.saveSpacePassword")
preparation = section(imports, '        let trace = SiteImportTrace("space:" + id)',
                      '        trace.mark("metadataPrepared")')
tests = (ROOT / "Tests/HDB/HDBImportRecoveryTests.swift").read_text()
tests = tests.replace("// PRODUCTION_SAVE", save + """
        hdbPersistenceBaseline = hdb
        Self.persisted = copy()
        Self.persisted!.hdb = hdbData.map { try! jsonDecoder.decode(HDBConfiguration.self, from: $0) }
        return true
    }
""").replace("// PRODUCTION_IMPORT_PREPARATION", preparation)
sources = [ROOT / "SunSmart/Common/Data/HDBConfiguration.swift",
           ROOT / "SunSmart/Common/Data/HDBLightingZonePolicy.swift"]
with tempfile.TemporaryDirectory(prefix="hdb-import-recovery-") as directory:
    harness = Path(directory) / "Harness.swift"
    harness.write_text(tests)
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", "-parse-as-library", *map(str, sources),
                    str(harness), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
