#!/usr/bin/env python3
"""Run both production callback adapters with a deterministic transport boundary."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'SunSmart/Common/Network/NetworkRequest.swift').read_text()
def section(start, end):
    return source[source.index(start):source.index(end, source.index(start))]

production = 'import Foundation\nclass NetworkRequest {\n' + section(
    '    typealias Success', '    static let shared')
production += section('    private static let responseQueue', '    private static let encodingQueue')
production += 'let provider = TestProvider()\n'
production += section('    @discardableResult func request(_ target: NetowrkReqeustApi, completion:',
                      '\nprivate struct NetworkRequestTimeoutPlugin')
production += section('private extension NetworkRequest {', '\n\n/// 网络请求api错误')
production += section('public enum NetworkApiError:', '/// Encoding is selected')
with tempfile.TemporaryDirectory(prefix='network-response-queue-') as folder:
    folder = Path(folder)
    (folder / 'Production.swift').write_text(production)
    binary = folder / 'tests'
    subprocess.run(['swiftc', '-parse-as-library',
                    str(root / 'Pods/SwiftyJSON/Source/SwiftyJSON/SwiftyJSON.swift'),
                    str(root / 'SunSmart/Common/Data/AppPerformance.swift'),
                    str(folder / 'Production.swift'),
                    str(root / 'Tests/Group/NetworkResponseQueueTests.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
