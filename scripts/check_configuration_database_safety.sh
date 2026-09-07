#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
sdk_root="${1:?Pass the resolved Nordic SDK checkout path}"
test_build="$(mktemp -d "${TMPDIR:-/tmp}/configuration-db-tests.XXXXXX")"
sqlite_sources=()
while IFS= read -r source; do sqlite_sources+=("$source"); done < <(rg --files "$sdk_root/Sources/SQLite" -g '*.swift')
swiftc -emit-module -emit-library -module-name SQLite "${sqlite_sources[@]}" -o "$test_build/libSQLite.dylib" -emit-module-path "$test_build/SQLite.swiftmodule"
python3 - "$repo_root" "$test_build" <<'PY'
from pathlib import Path
import sys
repo, output = map(Path, sys.argv[1:])
safety = (repo / 'SunSmart/Common/Data/SpaceConfigurationSafety.swift').read_text()
checkpoint = safety[safety.index('struct ConfigurationDatabaseCheckpoint {'):]
database = (repo / 'SunSmart/Common/Data/Database.swift').read_text()
start = database.index('    @discardableResult\n    func configurationTransaction(')
end = database.index('\n}\n', start)
transaction = database[start:end]
(output / 'ProductionDatabaseSafety.swift').write_text('import Foundation\nimport SQLite\n' + checkpoint + '\nclass SunSmartDataManager {\nlet db: Connection?\ninit(db: Connection?) { self.db = db }\n' + transaction + '\n}\n')
PY
swiftc -parse-as-library -I "$test_build" -L "$test_build" -lSQLite "$test_build/ProductionDatabaseSafety.swift" "$repo_root/Tests/Group/ConfigurationDatabaseCheckpointTests.swift" -o "$test_build/tests"
"$test_build/tests"
