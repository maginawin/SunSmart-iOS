#!/usr/bin/env python3
"""Run the production transfer coordinator with controllable network/storage boundaries."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="site-transfer-") as directory:
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", "-parse-as-library",
                    str(root / "SunSmart/Main/Share/Model/SiteTransferCoordinator.swift"),
                    str(root / "Tests/Site/SiteTransferCoordinatorTests.swift"),
                    "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    # Exercise the entire production Site import wrapper with the existing Mesh
    # storage doubles; address allocation itself remains a device-test boundary.
    imports = (root / "SunSmart/Common/Data/ImportData.swift").read_text()
    start = imports.index("    static func `import`(siteJsonData:")
    site_import = imports[start:imports.index("    /// 更新数据", start)]
    keys = (root / "SunSmart/Common/Data/SpaceConfigurationSafety.swift").read_text()
    contract = keys[keys.index("enum SpaceKeyIntegrity {"):keys.index("/// Recovery data stays")]
    doubles = (root / "Tests/Group/SpaceKeyIntegrityTests.swift").read_text().split("// PRODUCTION_KEY_CONTRACT")[0]
    fixture = (root / "Tests/Site/SiteTransferImportTests.swift").read_text()
    harness = Path(directory) / "Import.swift"
    harness.write_text(doubles + contract + fixture.replace("// PRODUCTION_SITE_IMPORT",
                      "extension SiteData {\n" + site_import + "\n}"))
    subprocess.run(["swiftc", "-parse-as-library", str(harness),
                    str(root / "Pods/SwiftyJSON/Source/SwiftyJSON/SwiftyJSON.swift"),
                    "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
