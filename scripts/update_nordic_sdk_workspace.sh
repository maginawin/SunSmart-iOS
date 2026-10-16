#!/usr/bin/env bash
set -euo pipefail

# Update the shared workspace lockfile to the latest remote release commit.
script_dir="$(cd "$(dirname "$0")" && pwd)"
app_root="$(cd "$script_dir/.." && pwd)"

"$script_dir/check_nordic_sdk_dependency.sh"

python3 - "$app_root/SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved" <<'PYTHON'
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile


def update(resolved_file):
    original = resolved_file.read_bytes()
    resolved = json.loads(original)
    pins = [pin for pin in resolved["pins"] if pin.get("identity") == "nordic-sig-mesh-sdk"]
    if len(pins) != 1:
        raise ValueError("Expected exactly one NordicSigMeshSDK pin.")
    pin = pins[0]
    if pin.get("kind") != "remoteSourceControl" or pin["state"].get("branch") != "release":
        raise ValueError("NordicSigMeshSDK must use the remote release branch.")
    repository = pin["location"]
    old_revision = pin["state"]["revision"]
    if not isinstance(repository, str) or not repository:
        raise ValueError("NordicSigMeshSDK repository URL is missing.")
    if not isinstance(old_revision, str) or not re.fullmatch(r"[0-9a-f]{40}", old_revision):
        raise ValueError("NordicSigMeshSDK revision is invalid.")

    print("Fetching the latest NordicSigMeshSDK release SHA...", flush=True)
    result = subprocess.run(
        ["git", "ls-remote", "--exit-code", "--", repository, "refs/heads/release"],
        check=True, capture_output=True, text=True, timeout=60,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )
    match = re.fullmatch(r"([0-9a-f]{40})\s+refs/heads/release", result.stdout.strip())
    if not match:
        raise ValueError("Remote release branch did not return a valid commit SHA.")
    revision = match.group(1)
    if revision == old_revision:
        print(f"PASS: NordicSigMeshSDK is already up to date ({revision}).")
        return

    pin["state"]["revision"] = revision
    updated = json.dumps(resolved, indent=2, separators=(",", " : "), ensure_ascii=False) + "\n"
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=resolved_file.parent,
                                         prefix=".Package.resolved.", delete=False) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(updated)
        os.chmod(temporary_path, stat.S_IMODE(resolved_file.stat().st_mode))
        # Xcode may have changed the lockfile while the remote query was running.
        if resolved_file.read_bytes() != original:
            raise ValueError("Package.resolved changed during the update; please run the script again.")
        os.replace(temporary_path, resolved_file)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()
    print(f"PASS: NordicSigMeshSDK updated from {old_revision} to {revision}.")
    print(f"Updated: {resolved_file}")


try:
    update(Path(sys.argv[1]))
except subprocess.CalledProcessError as error:
    detail = error.stderr.strip() or "Remote release branch was not found."
    print(f"FAIL: Could not query NordicSigMeshSDK release: {detail}", file=sys.stderr)
    sys.exit(1)
except subprocess.TimeoutExpired:
    print("FAIL: SDK remote query timed out; Package.resolved was not changed.", file=sys.stderr)
    sys.exit(1)
except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
    print(f"FAIL: {error}", file=sys.stderr)
    sys.exit(1)
PYTHON
