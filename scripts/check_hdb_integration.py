#!/usr/bin/env python3
"""Exercise production Store, Service and Executor with only SDK/database/cloud boundaries doubled."""
from pathlib import Path
import subprocess
import tempfile
import sys
from hdb_publication_test_source import with_publication_policy
ROOT = Path(__file__).resolve().parents[1]
device_tasks = "--device-tasks" in sys.argv or "--add-execution" in sys.argv or "--subelement" in sys.argv
files = ["SunSmart/Common/Data/HDBConfiguration.swift", "SunSmart/Common/Data/HDBLightingZonePolicy.swift", "SunSmart/Common/Data/HDBConfigurationStore.swift", "SunSmart/Common/Data/HDBConfigurationStore+Mesh.swift", "SunSmart/Main/Space/Model/SyncRunLifecycle.swift", "SunSmart/Main/Space/Model/SyncSessionCoordinator.swift", "SunSmart/Main/Space/HDB/Model/HDBLightingZoneExecutor.swift", "SunSmart/Main/Space/HDB/Model/HDBLightingZoneService.swift", "SunSmart/Common/Data/LightGroupControlCommandSender.swift", "Tests/HDB/HDBTestBoundaries.swift", "Tests/HDB/HDBMeshTestBoundaries.swift", "Tests/HDB/HDBControlTestBoundaries.swift", "Tests/HDB/HDBIntegrationTests.swift"]

files += ["SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift", "Tests/HDB/HDBSDKKeybindTestBoundaries.swift"]
# Use the actual mapped SDK getter, so subscription mutations affect readiness.
# This intentionally requires the same local SDK checkout as the App workspace.
sdk_config = ROOT / ".local-sdk/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Config.swift"
if not sdk_config.is_file():
    raise SystemExit("Missing mapped local SDK; run scripts/setup_local_nordic_sdk_workspace.sh first")
sdk_source = sdk_config.read_text()
getter_start = sdk_source.index("    var isKeybindComplete: Bool {")
sdk_getter = sdk_source[getter_start:sdk_source.index("    /// 是否完成基本配置", getter_start)]

def source(path):
    text = (ROOT / path).read_text()
    if path.endswith("HDBDeviceAddCompletion.swift"):
        text = text.split("/// Owns provisioning-to-HDB completion")[0]
    if path.endswith("HDBTestBoundaries.swift"):
        controller = (ROOT / "SunSmart/Main/Space/Controller/SpaceViewController.swift").read_text()
        start = controller.index("    func refreshSummaryCountsFromSpaceMesh()")
        method = controller[start:controller.index("\n    private func markSpaceUploadNeeded", start)]
        text = text.replace("    func refreshSummaryCountsFromSpaceMesh() {}", method)
    if path.endswith("HDBMeshTestBoundaries.swift"):
        text = text.replace("var isProvisioner = false, isConfigComplete = false, isKeybindComplete = true",
                            "var isProvisioner = false, isConfigComplete = false")
        text += "\nextension Node {\n" + sdk_getter + "\n}\n"
        # Exercise the production cache lookup at the HDB Optional Site reader;
        # only topology preparation and the database remain test boundaries.
        context = (ROOT / "SunSmart/Common/Data/NodeSyncReadContext.swift").read_text()
        start = context.index("    func memoized<Value>")
        method = context[start:context.index("\n    func node(", start)]
        text = text.replace("    func memoized<T>(_ key: String, read: () -> T) -> T { read() }",
                            "    private var memoizedValues: [String: Any] = [:]\n" + method)
    if device_tasks and path.endswith("HDBDeviceSyncTestBoundaries.swift"):
        text = text[:text.index("final class HDBDeviceSyncTask")] + text[text.index("final class SyncDeviceStepTaskModel"):]
    return text

if "--add-completion" in sys.argv or "--add-execution" in sys.argv:
    files[files.index("Tests/HDB/HDBIntegrationTests.swift")] = ("Tests/HDB/HDBDeviceAddExecutionTests.swift"
        if "--add-execution" in sys.argv else "Tests/HDB/HDBDeviceAddCompletionTests.swift")
    files.append("SunSmart/Main/Device/Model/HDBDeviceAddCompletion.swift")
if "--device-tasks" in sys.argv:
    files[files.index("Tests/HDB/HDBIntegrationTests.swift")] = "Tests/HDB/HDBDeviceSyncTaskTests.swift"
if "--subelement" in sys.argv:
    files[files.index("Tests/HDB/HDBIntegrationTests.swift")] = "Tests/HDB/HDBSubelementSubscriptionTests.swift"
if device_tasks:
    files += ["Tests/HDB/HDBLightingTransportBoundaries.swift", "Tests/HDB/HDBDeviceSyncTaskBoundaries.swift"]
if "--device-sync" in sys.argv:
    files[files.index("Tests/HDB/HDBIntegrationTests.swift")] = "Tests/HDB/HDBDeviceSyncServiceTests.swift"

files += ["SunSmart/Common/Data/HDBDevicePreparationPolicy.swift", "SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift", "Tests/HDB/HDBDeviceSyncTestBoundaries.swift"]

with tempfile.TemporaryDirectory(prefix="hdb-integration-") as directory:
    harness = Path(directory) / "Harness.swift"
    extra = "enum HDBLightingError: Error { case notPrepared }\n"
    task_source = (ROOT / "SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift").read_text()
    if not device_tasks: task_source = task_source.split("/// A task owns")[0]
    harness.write_text(with_publication_policy(extra + "\n".join(source(f).replace("import NordicSigMeshSDK", "") for f in files) + "\n" + task_source.replace("import NordicSigMeshSDK", ""), ROOT))
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", "-parse-as-library", str(harness), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
