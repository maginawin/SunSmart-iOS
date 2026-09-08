#!/usr/bin/env python3
"""检查 App 日志的编译条件，并验证 Release 下不输出、不计算日志参数。"""

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True)


def main():
    swiftc = Path(run("xcrun", "--find", "swiftc").strip())
    sdk = run("xcrun", "--sdk", "macosx", "--show-sdk-path").strip()
    host = swiftc.parent.parent / "lib/swift/host"
    with tempfile.TemporaryDirectory(prefix="sunsmart-debug-logging-") as temp:
        work = Path(temp)
        compiler = [swiftc, "-sdk", sdk, "-module-cache-path", work / "cache"]
        audit = work / "audit"
        run(*compiler, "-I", host, "-L", host, "-Xlinker", "-rpath",
            "-Xlinker", host, ROOT / "scripts/tests/DebugLoggingAudit.swift", "-o", audit)
        paths = sorted((ROOT / "SunSmart").rglob("*.swift"))
        entries = json.loads(run(audit, *paths))
        failures = [entry for entry in entries if not entry["guarded"]]
        for entry in failures:
            source = Path(entry["path"]).read_bytes()
            line = source[:entry["start"]].count(b"\n") + 1
            print(f'{entry["path"]}:{line}: 日志缺少 #if DEBUG 保护')
        if failures:
            raise SystemExit(1)
        print(f"PASS: {len(entries)} 处 App 日志调用均受 #if DEBUG 保护")

        # 直接提取生产代码的日志方法，防止测试与实际实现脱节。
        source = (ROOT / "SunSmart/Main/Device/Device1.5/FireAlarm/Model/"
                  "EmergencyFireControllerSceneEventManager.swift").read_text()
        begin = source.index("    private func log(")
        end = source.index("\n    }", begin) + len("\n    }")
        method = source[begin:end]
        fixture = work / "main.swift"
        fixture.write_text("""
import Foundation
final class Probe {
    var evaluations = 0
    func message() -> String { evaluations += 1; return "probe" }
    func check() {
        log(message())
        #if DEBUG
        precondition(evaluations == 1)
        #else
        precondition(evaluations == 0)
        #endif
    }
""" + method + "\n}\nProbe().check()\n")
        for name, flags, expected in [
            ("Debug", ["-D", "DEBUG", "-Onone"], "[EFC Scene] probe\n"),
            ("Release", ["-O"], ""),
            ("ReleaseWithoutOptimization", ["-Onone"], ""),
        ]:
            binary = work / name
            run(*compiler, *flags, fixture, "-o", binary)
            output = run(binary)
            if output != expected:
                raise SystemExit(f"{name} 日志输出不符合预期: {output!r}")
            print(f"PASS: {name} 输出和参数求值符合预期")


if __name__ == "__main__":
    main()
